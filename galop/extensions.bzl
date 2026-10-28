"""Bzlmod extension that registers prebuilt galop binaries as toolchains.

    galop = use_extension("@rules_gala//galop:extensions.bzl", "galop")
    galop.toolchain(version = "0.2.3")
    use_repo(galop, "galop_toolchains")
    register_toolchains("@galop_toolchains//:all")

For every platform the chosen galop version publishes a binary for (from 0.2.3:
linux-amd64, linux-arm64, darwin-amd64, darwin-arm64, windows-amd64) this declares a repo that downloads the release asset and
verifies it against the checksum table in //galop/private:versions.bzl, plus a
galop_toolchain and a `toolchain()` constrained to that exec platform in the
hub repo `@galop_toolchains`. Downloads are lazy: only the binary for the exec
platform that toolchain resolution picks is fetched.

Other exec platforms, and platforms an older version has no binary for, get no
toolchain, so galop_parser fails toolchain resolution there; register your own
galop_toolchain for them.

If several modules request a version, the root module's request wins;
otherwise the highest requested version is used.
"""

load("//galop/private:versions.bzl", "DEFAULT_BASE_URL", "GALOP_VERSIONS", "PLATFORMS")

_HUB = "galop_toolchains"

_BINARY_BUILD = """\
exports_files(["{out}"], visibility = ["//visibility:public"])

alias(
    name = "galop",
    actual = "{out}",
    visibility = ["//visibility:public"],
)
"""

def _galop_binary_impl(rctx):
    # The file sits in bin/ so it never shares a name with the "galop" alias:
    # on Linux and macOS the asset has no extension, and a source file named
    # like a rule in the same package is a Bazel error.
    out = "bin/galop.exe" if rctx.attr.asset.endswith(".exe") else "bin/galop"
    rctx.download(
        url = rctx.attr.urls,
        output = out,
        sha256 = rctx.attr.sha256,
        executable = True,
    )
    rctx.file("BUILD.bazel", _BINARY_BUILD.format(out = out))

_galop_binary = repository_rule(
    implementation = _galop_binary_impl,
    attrs = {
        "asset": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "urls": attr.string_list(mandatory = True),
    },
    doc = "Downloads one prebuilt galop release binary.",
)

_HUB_TOOLCHAIN = """\
galop_toolchain(
    name = "{p}_impl",
    galop = "@{repo}//:galop",
)

toolchain(
    name = "{p}",
    exec_compatible_with = {constraints},
    toolchain = ":{p}_impl",
    toolchain_type = "{toolchain_type}",
    visibility = ["//visibility:public"],
)
"""

def _galop_hub_impl(rctx):
    parts = ['load("{}", "galop_toolchain")\n'.format(rctx.attr.toolchain_bzl)]
    for p in sorted(rctx.attr.platforms.keys()):
        parts.append(_HUB_TOOLCHAIN.format(
            p = p,
            repo = rctx.attr.binary_repos[p],
            constraints = repr(rctx.attr.platforms[p]),
            toolchain_type = rctx.attr.toolchain_type,
        ))
    rctx.file("BUILD.bazel", "\n".join(parts))

_galop_hub = repository_rule(
    implementation = _galop_hub_impl,
    attrs = {
        "binary_repos": attr.string_dict(mandatory = True),
        "platforms": attr.string_list_dict(mandatory = True),
        "toolchain_bzl": attr.string(mandatory = True),
        "toolchain_type": attr.string(mandatory = True),
    },
    doc = "Hub repo declaring one galop toolchain per published platform.",
)

def _version_key(version):
    return [int(p) if p.isdigit() else 0 for p in version.split("-")[0].split(".")]

def _select_tag(module_ctx):
    root = None
    others = []
    for mod in module_ctx.modules:
        for tag in mod.tags.toolchain:
            if not mod.is_root:
                others.append(tag)
            elif root != None:
                fail("galop: the root module may call galop.toolchain() only once")
            else:
                root = tag
    if root != None:
        return root
    best = None
    for tag in others:
        if best == None or _version_key(tag.version) > _version_key(best.version):
            best = tag
    return best

def _missing_checksum_message(version, missing, base_url):
    lines = [
        '"{p}": "<sha256 of {a}>",'.format(p = p, a = PLATFORMS[p].asset)
        for p in sorted(PLATFORMS.keys())
    ]
    return """galop: no SHA-256 checksum for galop {v} on {missing}.

rules_gala only downloads galop binaries whose checksums it knows. Take the
hashes from {base}/{v}/checksums-sha256.txt
and either add this entry to GALOP_VERSIONS in
@rules_gala//galop/private:versions.bzl (then release rules_gala):

    "{v}": {{
{entry}
    }},

or pass them from your MODULE.bazel:

    galop.toolchain(
        version = "{v}",
        sha256 = {{
{entry2}
        }},
    )
""".format(
        v = version,
        missing = ", ".join(missing),
        base = base_url,
        entry = "\n".join(["        " + line for line in lines]),
        entry2 = "\n".join(["            " + line for line in lines]),
    )

def _galop_extension_impl(module_ctx):
    tag = _select_tag(module_ctx)
    if tag == None:
        return module_ctx.extension_metadata(reproducible = True)

    for p in tag.sha256:
        if p not in PLATFORMS:
            fail("galop: unknown platform %r in sha256; expected one of %s" %
                 (p, sorted(PLATFORMS.keys())))

    base_url = tag.base_url.rstrip("/")
    known = GALOP_VERSIONS.get(tag.version, {})
    checksums = {}
    for p in sorted(PLATFORMS.keys()):
        sha = tag.sha256.get(p) or known.get(p)
        if sha:
            checksums[p] = sha

    # A platform without a checksum gets no toolchain: older galop releases
    # don't publish every platform, and galop_parser then fails toolchain
    # resolution there, as it does on any unsupported exec platform. With no
    # checksum at all the version is unknown, which is an error.
    if not checksums:
        fail(_missing_checksum_message(tag.version, sorted(PLATFORMS.keys()), base_url))

    binary_repos = {}
    constraints = {}
    for p in sorted(checksums.keys()):
        info = PLATFORMS[p]
        repo = "galop_" + p
        _galop_binary(
            name = repo,
            asset = info.asset,
            sha256 = checksums[p],
            urls = ["{}/{}/{}".format(base_url, tag.version, info.asset)],
        )
        binary_repos[p] = repo
        constraints[p] = info.exec_compatible_with

    _galop_hub(
        name = _HUB,
        binary_repos = binary_repos,
        platforms = constraints,
        toolchain_bzl = str(Label("//galop:toolchain.bzl")),
        toolchain_type = str(Label("//galop:toolchain_type")),
    )

    return module_ctx.extension_metadata(reproducible = True)

_toolchain_tag = tag_class(
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "galop release version: a bare semver tag such as `0.2.1`.",
        ),
        "sha256": attr.string_dict(
            doc = "Per-platform SHA-256 hashes (`darwin_arm64`, " +
                  "`linux_amd64`, `windows_amd64`) for a version that is not " +
                  "yet in rules_gala's checksum table. Overrides the table.",
        ),
        "base_url": attr.string(
            default = DEFAULT_BASE_URL,
            doc = "Where release assets are fetched from, as " +
                  "`<base_url>/<version>/<asset>`. Override for a mirror.",
        ),
    },
    doc = "Selects the galop release to register as toolchains.",
)

galop = module_extension(
    implementation = _galop_extension_impl,
    tag_classes = {"toolchain": _toolchain_tag},
    doc = "Registers prebuilt galop release binaries as toolchains.",
)
