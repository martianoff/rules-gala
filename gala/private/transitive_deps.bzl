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

def _reachable_archives(deps):
    """Returns the GoArchive of every Go library reachable from deps.

    A GoArchive's `direct` lists the archives of its own deps, those of the
    libraries it embeds included, so walking it covers the whole graph.
    """
    seen = {}
    stack = [dep[GoArchive] for dep in deps if GoArchive in dep]

    # Starlark has no while loop. The walk ends when the stack is empty, long
    # before the bound: each archive's deps are pushed once, when it is first
    # seen.
    for _ in range(1 << 30):
        if not stack:
            break
        archive = stack.pop()
        if archive.data.importpath in seen:
            continue
        seen[archive.data.importpath] = archive
        stack.extend(archive.direct)
    return seen.values()

def _gala_transitive_go_deps_impl(ctx):
    go = go_context(ctx, include_deprecated_properties = False)
    return [new_go_info(go, ctx.attr, deps = _reachable_archives(ctx.attr.deps))]

gala_transitive_go_deps = rule(
    implementation = _gala_transitive_go_deps_impl,
    doc = "A source-less GoInfo whose deps are every Go library reachable from deps (see the module docstring).",
    attrs = {
        "deps": attr.label_list(
            providers = [GoArchive],
            doc = "The deps of the GALA target that embeds this one.",
        ),
        "_go_context_data": attr.label(default = "@rules_go//:go_context_data"),
    },
    toolchains = ["@rules_go//go:toolchain"],
    provides = [GoInfo],
)
