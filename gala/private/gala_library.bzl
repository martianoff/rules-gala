"""gala_library and gala_binary macros.

Each macro transpiles the given .gala sources to Go and wires them
into a `go_library` / `go_binary` from rules_go. The stdlib dep is
auto-injected as `@gala//std`, so consumers must `bazel_dep(name =
"gala")` for the macro output to compile.
"""

load("@rules_go//go:def.bzl", "go_binary", "go_library")
load(
    "//gala/private:transpile.bzl",
    "gala_transpile",
    "gala_transpile_package",
)
load("//gala/private:transitive_deps.bzl", "gala_transitive_go_deps")

_STDLIB = "@gala//std"

def transitive_go_deps_embed(name, deps, kwargs):
    """Declares the gala_transitive_go_deps target of a GALA target's Go rule.

    Generated Go may name a type of any package reachable through deps (see
    transitive_deps.bzl), so the Go rule embeds a target that makes those
    packages direct deps.

    Args:
        name: Name of the Go rule.
        deps: The Go rule's deps.
        kwargs: The Go rule's other attributes. testonly, tags and
            target_compatible_with are copied; `embed` is popped.

    Returns:
        The Go rule's embed list, with the new target appended.
    """
    gala_transitive_go_deps(
        name = name + "_transitive_go_deps",
        deps = deps,
        testonly = kwargs.get("testonly"),
        tags = kwargs.get("tags"),
        target_compatible_with = kwargs.get("target_compatible_with"),
    )
    return list(kwargs.pop("embed", [])) + [":" + name + "_transitive_go_deps"]

def _resolve_srcs(name, src, srcs):
    if src and srcs:
        fail("%s: specify either 'src' or 'srcs', not both" % name)
    if src:
        return [src]
    if not srcs:
        fail("%s: either 'src' or 'srcs' must be specified" % name)
    return srcs

def _gala_sources_label(dep):
    if ":" in dep:
        return dep + "_gala_sources"
    name = dep.split("/")[-1]
    return dep + ":" + name + "_gala_sources"

def gala_library(name, src = None, srcs = None, importpath = "", deps = [], gala_deps = [], embedsrcs = [], go_srcs = [], **kwargs):
    """Build a GALA library (transpiled to a `go_library`).

    Args:
        name: Target name.
        src: A single .gala source (legacy; prefer srcs).
        srcs: List of .gala source files.
        importpath: Go import path for the resulting library.
        deps: Bazel labels of Go/GALA deps to forward to go_library.
        gala_deps: Other gala_library labels. Their `_gala_sources`
            filegroups are added to the transpiler's --search path.
        embedsrcs: Files embedded via `//go:embed` directives in the GALA
            source. Forwarded to go_library.
        go_srcs: Hand-written .go files in the same package. They are
            made available to the transpiler for cross-language type
            inference and compiled into the resulting go_library.
        **kwargs: Forwarded to go_library.
    """
    srcs = _resolve_srcs(name, src, srcs)

    gen_go_srcs = [name + "_" + str(i) + ".gen.go" for i in range(len(srcs))]

    if len(srcs) > 1:
        gala_transpile_package(
            name = name + "_transpile",
            srcs = srcs,
            outs = gen_go_srcs,
            extra_srcs = go_srcs,
            gala_deps = gala_deps,
            go_deps = deps,
        )
    else:
        gala_transpile(
            name = name + "_transpile_0",
            src = srcs[0],
            out = gen_go_srcs[0],
            extra_srcs = go_srcs,
            gala_deps = gala_deps,
            go_deps = deps,
        )

    all_deps = list(deps) + list(gala_deps) + [_STDLIB]
    embed = transitive_go_deps_embed(name, all_deps, kwargs)

    go_library(
        name = name,
        srcs = gen_go_srcs + go_srcs,
        importpath = importpath,
        deps = all_deps,
        embed = embed,
        embedsrcs = embedsrcs,
        **kwargs
    )

    # Expose this library's GALA source files so downstream packages
    # that depend on it can find them via gala_deps and have them
    # included in the transpiler's --search path.
    native.filegroup(
        name = name + "_gala_sources",
        srcs = srcs,
        visibility = ["//visibility:public"],
    )

def gala_binary(name, src = None, srcs = None, deps = [], gala_deps = [], embedsrcs = [], **kwargs):
    """Build a GALA executable (transpiled to a `go_binary`).

    Args mirror gala_library, minus importpath/go_srcs.
    """
    srcs = _resolve_srcs(name, src, srcs)

    go_srcs = [name + "_" + str(i) + ".gen.go" for i in range(len(srcs))]

    if len(srcs) > 1:
        gala_transpile_package(
            name = name + "_transpile",
            srcs = srcs,
            outs = go_srcs,
            gala_deps = gala_deps,
            go_deps = deps,
        )
    else:
        gala_transpile(
            name = name + "_transpile_0",
            src = srcs[0],
            out = go_srcs[0],
            gala_deps = gala_deps,
            go_deps = deps,
        )

    all_deps = list(deps) + list(gala_deps) + [_STDLIB]
    embed = transitive_go_deps_embed(name, all_deps, kwargs)

    go_binary(
        name = name,
        srcs = go_srcs,
        deps = all_deps,
        embed = embed,
        embedsrcs = embedsrcs,
        **kwargs
    )
