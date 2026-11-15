"""Analysis tests for go_src_info, which feeds the transpiler's --go-src flag."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//gala/private:go_srcs.bzl", "gala_go_srcs_aspect", "go_src_entry", "go_src_info")

_ProbeInfo = provider(doc = "What go_src_info returned for the probe's deps.", fields = ["entries", "srcs"])

def _go_srcs_probe_impl(ctx):
    info = go_src_info(ctx.attr.deps)
    return [_ProbeInfo(
        entries = [go_src_entry(a) for a in info.archives.to_list()],
        srcs = info.srcs.to_list(),
    )]

# Stands in for the transpile rules: its deps carry the aspect, as their
# go_deps do, and it returns what they would pass the transpiler.
_go_srcs_probe = rule(
    implementation = _go_srcs_probe_impl,
    attrs = {"deps": attr.label_list(aspects = [gala_go_srcs_aspect])},
)

_PKG = "gala/tests/"

def _transitive_test_impl(ctx):
    env = analysistest.begin(ctx)
    info = analysistest.target_under_test(env)[_ProbeInfo]

    # Every library reachable from the one direct dep, through deps and
    # embed, maps to its source directory. mid's archive lists the embedded
    # library's files first, then its generated file (under bazel-out), but
    # mid's import path maps to the directory of its checked-in files.
    asserts.equals(
        env,
        [
            "example.com/embeddep=" + _PKG + "embeddep",
            "example.com/leaf=" + _PKG + "leaf",
            "example.com/mid=" + _PKG + "mid",
            "example.com/top=" + _PKG + "top",
        ],
        sorted(info.entries),
    )

    # Only .go files are staged: mid's assembly file is not.
    asserts.equals(
        env,
        ["embedded.go", "embeddep.go", "generated.go", "leaf.go", "mid.go", "top.go"],
        sorted([f.basename for f in info.srcs]),
    )
    return analysistest.end(env)

_transitive_test = analysistest.make(_transitive_test_impl)

def go_srcs_test_suite(name):
    """Declares the go_src_info tests.

    Args:
        name: name of the test_suite.
    """
    _go_srcs_probe(name = name + "_probe", deps = ["//gala/tests/top"], tags = ["manual"])
    _transitive_test(name = name + "_transitive", target_under_test = ":" + name + "_probe")

    native.test_suite(
        name = name,
        tests = [name + "_transitive"],
    )
