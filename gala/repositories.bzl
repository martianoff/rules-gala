"""Repository rule and macro for resolving GALA module dependencies.

`gala_module` is consumed by the bzlmod extension in
`@rules_gala//gala:extensions.bzl`. `gala_dependencies` is the
WORKSPACE-mode equivalent, kept for repos that have not migrated
off WORKSPACE.

Modules are resolved from the local GALA module cache at
`~/.gala/pkg/mod/<module_path>@<version>` (or `%USERPROFILE%\\.gala\\pkg\\mod\\...`
on Windows). Run `gala mod add <path>@<version>` to populate the cache.
"""

load("//gala/private:gala_mod_parser.bzl", "module_path_to_repo_name", "parse_gala_mod")

def _parse_go_mod_requires(content):
    requires = []
    in_require_block = False
    for line in content.split("\n"):
        line = line.strip()
        if not line:
            continue
        if "//" in line:
            line = line[:line.index("//")].strip()
        if line == "require (" or line.startswith("require("):
            in_require_block = True
            continue
        if line == ")":
            in_require_block = False
            continue
        if line.startswith("require ") and "(" not in line:
            parts = [p for p in line[8:].split(" ") if p]
            if parts:
                requires.append(parts[0])
            continue
        if in_require_block:
            parts = [p for p in line.split(" ") if p]
            if parts:
                requires.append(parts[0])
    return requires

def _go_module_to_bazel_label(module_path):
    """Convert a Go module path to a canonical Gazelle go_deps Bzlmod label.

    Example: github.com/google/uuid -> @@gazelle++go_deps+com_github_google_uuid//:uuid
    """
    name = module_path.replace(".", "_").replace("/", "_").replace("-", "_")
    parts = name.split("_")
    if len(parts) >= 2 and parts[0] in ["github", "gitlab", "bitbucket"]:
        parts = [parts[1], parts[0]] + parts[2:]
    repo_name = "_".join(parts)
    target_name = module_path.split("/")[-1]
    return "@@gazelle++go_deps+" + repo_name + "//:" + target_name

def _gala_module_impl(repository_ctx):
    module_path = repository_ctx.attr.module_path
    version = repository_ctx.attr.version

    if repository_ctx.os.name.startswith("windows"):
        home = repository_ctx.os.environ.get("USERPROFILE", "")
        cache_base = home + "\\.gala\\pkg\\mod"
    else:
        home = repository_ctx.os.environ.get("HOME", "")
        cache_base = home + "/.gala/pkg/mod"

    cache_path = cache_base + "/" + module_path + "@" + version
    cache_dir = repository_ctx.path(cache_path)

    if not cache_dir.exists:
        fail("""
GALA module not found in cache: %s@%s

Run 'gala mod add %s@%s' to fetch it first, then re-run bazel.
""" % (module_path, version, module_path, version))

    go_files = []
    package_name = ""
    go_deps = []

    for f in cache_dir.readdir():
        name = f.basename

        if name == "BUILD.bazel" or name == "BUILD":
            continue

        if name.endswith(".gen.go") or (name.endswith("_gen.go") and not name.endswith(".gen.go")):
            repository_ctx.symlink(f, name)
            go_files.append(name)
        elif name.endswith(".gala") and not name.endswith("_test.gala"):
            repository_ctx.symlink(f, name)
            if not package_name:
                content = repository_ctx.read(f)
                for line in content.split("\n"):
                    line = line.strip()
                    if line.startswith("package "):
                        package_name = line[8:].strip()
                        break
        elif name == "go.mod":
            repository_ctx.symlink(f, name)
            content = repository_ctx.read(f)
            go_deps = _parse_go_mod_requires(content)
        elif name == "gala.mod":
            repository_ctx.symlink(f, name)

    if not package_name:
        package_name = module_path.split("/")[-1]

    srcs_str = "[" + ", ".join(['"%s"' % f for f in go_files]) + "]" if go_files else "[]"

    all_deps = ["@gala//std"] + list(repository_ctx.attr.deps)
    for go_dep in go_deps:
        # Skip GALA stdlib packages — they ship in @gala//std already.
        if go_dep.startswith("martianoff/gala/"):
            continue
        bazel_label = _go_module_to_bazel_label(go_dep)
        if bazel_label:
            all_deps.append(bazel_label)
    deps_str = "[" + ", ".join(['"%s"' % d for d in all_deps]) + "]"

    build_content = '''
load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "{name}",
    srcs = {srcs},
    importpath = "{importpath}",
    visibility = ["//visibility:public"],
    deps = {deps},
)
'''.format(
        name = package_name,
        srcs = srcs_str,
        importpath = module_path,
        deps = deps_str,
    )

    repository_ctx.file("BUILD.bazel", build_content)

gala_module = repository_rule(
    implementation = _gala_module_impl,
    attrs = {
        "module_path": attr.string(
            mandatory = True,
            doc = "Module path (e.g., github.com/user/repo).",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Version (e.g., v1.2.3).",
        ),
        "sum": attr.string(
            doc = "Expected hash from gala.sum (optional, not yet enforced).",
        ),
        "deps": attr.string_list(
            doc = "Bazel labels of this module's other deps.",
        ),
    },
    doc = "Fetch a GALA module from the local cache and expose it as a Bazel target.",
)

def _gala_deps_impl(repository_ctx):
    gala_mod_path = repository_ctx.attr.gala_mod
    gala_mod_content = repository_ctx.read(gala_mod_path)
    deps = parse_gala_mod(gala_mod_content)

    bzl_content = '''"""Auto-generated GALA dependencies from gala.mod."""

load("@rules_gala//gala:repositories.bzl", "gala_module")

def declare_gala_deps():
    """Declare all GALA module dependencies."""
'''

    for path, version, is_go in deps:
        if is_go:
            continue
        repo_name = module_path_to_repo_name(path)
        bzl_content += '''
    gala_module(
        name = "{repo_name}",
        module_path = "{path}",
        version = "{version}",
    )
'''.format(repo_name = repo_name, path = path, version = version)

    repository_ctx.file("deps.bzl", bzl_content)
    repository_ctx.file("BUILD.bazel", "")

_gala_deps = repository_rule(
    implementation = _gala_deps_impl,
    attrs = {
        "gala_mod": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
    },
)

def gala_dependencies(gala_mod = "//:gala.mod"):
    """Generate gala_module repos for every GALA dep in gala.mod.

    WORKSPACE-mode convenience macro. Bzlmod consumers use the
    extension in `@rules_gala//gala:extensions.bzl` instead.
    """
    _gala_deps(name = "gala_deps", gala_mod = gala_mod)
