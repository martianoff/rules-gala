"""Analysis tests for what the transpile rules tell the transpiler about Go deps."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//gala/private:go_exports.bzl", "gala_go_deps_aspect", "go_deps_info", "go_export_entry", "go_src_entry")
load("//gala/private:transpile.bzl", "gala_transpile_worker_single")

_ProbeInfo = provider(doc = "What go_deps_info returned for the probe's deps.", fields = ["src_entries", "srcs", "export_entries", "exports"])

def _go_deps_probe_impl(ctx):
    info = go_deps_info(ctx.attr.deps)
    return [_ProbeInfo(
        src_entries = [go_src_entry(d) for d in info.direct],
        srcs = info.direct_srcs.to_list(),
        export_entries = [e for a in info.archives.to_list() for e in go_export_entry(a)],
        exports = info.exports.to_list(),
    )]

# Stands in for the transpile rules: its deps carry the aspect, as their
# go_deps do, and it returns what they would pass the transpiler.
_go_deps_probe = rule(
    implementation = _go_deps_probe_impl,
    attrs = {"deps": attr.label_list(aspects = [gala_go_deps_aspect])},
)

_PKG = "gala/tests/"

def _short(entry):
    """`<importpath>=<export file>` with the file's output directory dropped."""
    path, file = entry.split("=")
    return path + "=" + file[file.index(_PKG):]

def _go_deps_test_impl(ctx):
    env = analysistest.begin(ctx)
    info = analysistest.target_under_test(env)[_ProbeInfo]

    # Each direct dep keeps its source directory: mid's, though its archive
    # lists the embedded library's file and its generated one (under
    # bazel-out) first. Their .go files are staged, not mid.s.
    asserts.equals(
        env,
        [
            "example.com/top=" + _PKG + "top",
            "example.com/mid=" + _PKG + "mid",
            "example.com/galapkg=" + _PKG + "galapkg",
        ],
        info.src_entries,
    )
    asserts.equals(
        env,
        ["embedded.go", "galapkg.go", "generated.go", "mid.go", "top.go"],
        sorted([f.basename for f in info.srcs]),
    )

    # Every Go library reachable through deps and embeds has its export file,
    # except the GALA package (galapkg), a library embedding it (galawrap), and
    # the library mid embeds, whose files are compiled into mid's. The GALA
    # package's own Go dep (galadep) counts. leaf, compiled under an importmap, is
    # named by it too.
    asserts.equals(
        env,
        [
            "example.com/embeddep=" + _PKG + "embeddep/embeddep.x",
            "example.com/galadep=" + _PKG + "galadep/galadep.x",
            "example.com/leaf=" + _PKG + "leaf/leaf.x",
            "example.com/mid=" + _PKG + "mid/mid.x",
            "example.com/top=" + _PKG + "top/top.x",
            "example.com/vendor/leaf=" + _PKG + "leaf/leaf.x",
        ],
        sorted([_short(e) for e in info.export_entries]),
    )
    asserts.equals(
        env,
        ["embeddep.x", "galadep.x", "leaf.x", "mid.x", "top.x"],
        sorted([f.basename for f in info.exports]),
    )
    return analysistest.end(env)

_go_deps_test = analysistest.make(_go_deps_test_impl)

def _flags(env):
    """The transpile action's --go-* flag names."""
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "GalaTranspile"]
    asserts.equals(env, 1, len(actions), "expected one GalaTranspile action")
    return sorted([a.split("=")[0] for a in actions[0].argv if a.startswith("--go-")])

def _export_on_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.equals(env, ["--go-export", "--go-src", "--go-stdlib-export"], _flags(env))
    return analysistest.end(env)

def _export_on_no_go_deps_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.equals(env, ["--go-stdlib-export"], _flags(env))
    return analysistest.end(env)

def _export_off_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.equals(env, ["--go-src"], _flags(env))
    return analysistest.end(env)

def _toolchain_test(impl, toolchain):
    return analysistest.make(impl, config_settings = {
        "//command_line_option:extra_toolchains": [str(Label(toolchain))],
    })

_export_on_test = _toolchain_test(_export_on_test_impl, "//gala/tests:export_toolchain")
_export_on_no_go_deps_test = _toolchain_test(_export_on_no_go_deps_test_impl, "//gala/tests:export_toolchain")
_export_off_test = _toolchain_test(_export_off_test_impl, "//gala/tests:no_export_toolchain")

def go_exports_test_suite(name):
    """Declares the tests.

    Args:
        name: name of the test_suite.
    """
    _go_deps_probe(name = name + "_probe", deps = ["//gala/tests/top", "//gala/tests/mid", "//gala/tests/galawrap"], tags = ["manual"])
    _go_deps_test(name = name + "_go_deps", target_under_test = ":" + name + "_probe")

    gala_transpile_worker_single(
        name = name + "_transpile",
        src = "x.gala",
        out = name + "_x.go",
        go_deps = ["//gala/tests/top"],
        tags = ["manual"],
    )
    _export_on_test(name = name + "_export_on", target_under_test = ":" + name + "_transpile")
    _export_off_test(name = name + "_export_off", target_under_test = ":" + name + "_transpile")

    gala_transpile_worker_single(
        name = name + "_transpile_no_go_deps",
        src = "x.gala",
        out = name + "_y.go",
        tags = ["manual"],
    )
    _export_on_no_go_deps_test(name = name + "_export_on_no_go_deps", target_under_test = ":" + name + "_transpile_no_go_deps")

    native.test_suite(
        name = name,
        tests = [name + "_go_deps", name + "_export_on", name + "_export_on_no_go_deps", name + "_export_off"],
    )
