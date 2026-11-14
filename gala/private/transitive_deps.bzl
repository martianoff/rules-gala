"""gala_transitive_go_deps: a GALA package's transitive Go deps, made direct.

The transpiler writes out types the GALA source only reaches through another
package: a lambda's parameter type, an `if` used as a value, a `Some(x)`.
When `main` imports `geo` and `geo.Points()` returns `Array[shape.Point]`,
the Go for `geo.Points().Map((p) => p.X)` is `func(p shape.Point) int`. Go
cannot infer a function literal's signature, so the generated file must
import `shape` even though the GALA file never does. Under rules_go's strict
dependency check that import fails `go build` unless `shape` is a direct dep.

Every GALA macro therefore embeds one of these targets in the go_library,
go_binary or go_test it creates. It provides a GoInfo with no sources whose
deps are the GoArchive of every Go library reachable from the macro's deps.
rules_go merges an embedded target's deps into the embedding target's own,
so those packages may be imported. Direct deps take precedence over the
merged ones (rules_go keeps the first archive for an import path).

Only what may be imported changes, not what is built: every archive listed
here is already built for the target's direct deps, and the compiler reads
only the export data of the packages a file imports.
"""

load("@rules_go//go:def.bzl", "GoArchive", "GoInfo", "go_context", "new_go_info")

_GalaReachableGoInfo = provider(
    doc = "The Go library targets reachable through a target's deps.",
    fields = {
        "libraries": "depset of Targets that provide GoArchive, the target's own excluded.",
    },
)

def _reachable(dep, include_self):
    """Returns the depsets of Go libraries dep makes reachable."""
    out = []
    if include_self and GoArchive in dep:
        out.append(depset([dep]))
    if _GalaReachableGoInfo in dep:
        out.append(dep[_GalaReachableGoInfo].libraries)
    return out

def _reachable_go_libraries_aspect_impl(target, ctx):
    transitive = []
    for dep in getattr(ctx.rule.attr, "deps", []):
        transitive.extend(_reachable(dep, include_self = True))

    # An embedded library is compiled into this one, under its import path:
    # its deps are reachable, it is not a package of its own.
    for dep in getattr(ctx.rule.attr, "embed", []):
        transitive.extend(_reachable(dep, include_self = False))
    return [_GalaReachableGoInfo(libraries = depset(transitive = transitive))]

_reachable_go_libraries_aspect = aspect(
    implementation = _reachable_go_libraries_aspect_impl,
    attr_aspects = ["deps", "embed"],
)

def _gala_transitive_go_deps_impl(ctx):
    go = go_context(ctx, include_deprecated_properties = False)
    transitive = []
    for dep in ctx.attr.deps:
        transitive.extend(_reachable(dep, include_self = True))
    libraries = depset(transitive = transitive).to_list()
    return [new_go_info(go, ctx.attr, deps = [lib[GoArchive] for lib in libraries])]

gala_transitive_go_deps = rule(
    implementation = _gala_transitive_go_deps_impl,
    doc = "A source-less GoInfo whose deps are every Go library reachable from deps (see the module docstring).",
    attrs = {
        "deps": attr.label_list(
            aspects = [_reachable_go_libraries_aspect],
            doc = "The deps of the GALA target that embeds this one.",
        ),
        "_go_context_data": attr.label(default = "@rules_go//:go_context_data"),
    },
    toolchains = ["@rules_go//go:toolchain"],
    provides = [GoInfo],
)
