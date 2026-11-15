"""What the transpiler types a GALA package's Go dependencies from.

The transpiler needs the types of every Go package a dependency's API reaches,
not only of those the GALA code imports: cobra's `Command.Flags()` returns a
`*pflag.FlagSet`, so `cmd.Flags().GetString("x")` lowers to `Try[string]` only
if pflag's types are known too.

rules_go has already compiled every one of those libraries, and the compiler
wrote each one's export data (GoArchiveData.export_file, the .x file). With a
toolchain that declares `go_export_data`, the transpile rules hand the
transpiler those files, `--go-export=<importpath>=<.x file>,...`, and the
directory of the standard library's compiled archives, `--go-stdlib-export`,
so it reads every package's types instead of type-checking them from source.

gala_go_deps_aspect collects the libraries and their export files over the
dependency graph as depsets, and the entries are written from them when the
action runs, so analysis flattens nothing. GALA libraries are left out: their
types come from their .gala source, and the Go view of them, their compiled
.gen.go, would shadow those. Their own Go deps still count.

Direct deps also keep a `--go-src=<importpath>=<dir>` entry, as before: the
hand-written .go files of a GALA package are type-checked from source against
them.
"""

load("@rules_go//go:def.bzl", "GoArchive")
load("//gala/private:transitive_deps.bzl", "GalaLibraryInfo")

GalaGoExportsInfo = provider(
    doc = "The Go libraries whose export data a library's dependents get, and their export files.",
    fields = {
        "is_gala": "bool: the library is a GALA package: it embeds a target carrying GalaLibraryInfo, or a library that is one.",
        "own": "list: the library's GoArchiveData, or none for a GALA library.",
        "dep_archives": "depset: the GoArchiveData of every non-GALA library it depends on, directly or not.",
        "dep_exports": "depset: the export files of those libraries.",
    },
)

def _infos(targets):
    return [t[GalaGoExportsInfo] for t in targets if type(t) == "Target" and GalaGoExportsInfo in t]

def _merge(deps, embeds = []):
    """Archives and export files of deps (each with its own) and of what embeds depend on."""
    return (
        depset(
            [a for d in deps for a in d.own],
            transitive = [d.dep_archives for d in deps + embeds],
        ),
        depset(
            [a.export_file for d in deps for a in d.own],
            transitive = [d.dep_exports for d in deps + embeds],
        ),
    )

def _gala_go_deps_aspect_impl(target, ctx):
    attr = ctx.rule.attr
    embedded = [e for e in (getattr(attr, "embed", None) or []) if type(e) == "Target"]

    # Every GALA library embeds its gala_transitive_go_deps target, and a
    # library embedding a GALA library compiles that library's files.
    markers = [e for e in embedded if GalaLibraryInfo in e]
    is_gala = bool(markers) or any([i.is_gala for i in _infos(embedded)])

    own = []
    if GoArchive in target and not is_gala:
        data = target[GoArchive].data
        if data.importpath and data.export_file:
            own.append(data)

    # An embedded library's files are compiled into this library's archive,
    # so only what it depends on counts; a GALA marker's deps are the
    # library's own. A go_proto_library's compilers bring the protobuf runtime
    # packages its generated code imports.
    deps = []
    for name in ["deps", "compiler", "compilers"]:
        value = getattr(attr, name, None)
        deps.extend(value if type(value) == "list" else [value])
    archives, exports = _merge(
        _infos(deps),
        _infos([e for e in embedded if e not in markers]),
    )
    return [GalaGoExportsInfo(
        is_gala = is_gala,
        own = own,
        dep_archives = archives,
        dep_exports = exports,
    )]

# Applied to a GALA rule's go_deps. It follows the attributes rules_go takes a
# library's archive deps from.
gala_go_deps_aspect = aspect(
    implementation = _gala_go_deps_aspect_impl,
    attr_aspects = ["deps", "embed", "compiler", "compilers"],
    provides = [GalaGoExportsInfo],
)

def go_export_entry(data):
    """The --go-export entries of a GoArchiveData, for args.add_joined's map_each.

    A library compiled under an importmap is named by it in the export data of
    the packages that import it, so it gets an entry under each name.
    """
    names = [data.importpath]
    if data.importmap and data.importmap != data.importpath:
        names.append(data.importmap)
    return [name + "=" + data.export_file.path for name in names]

def go_src_entry(data):
    """The --go-src entry of a GoArchiveData: `<importpath>=<source dir>`.

    rules_go merges an embedded library's files into the archive that embeds
    it, ahead of the library's own, so the directory is that of a file in the
    library's own package: a checked-in one if it has any, because a GALA
    library lists its generated .gen.go files, which the analyzer skips,
    ahead of its hand-written .go files. A library with no file of its own
    (all of them embedded) takes the first file's directory.

    Args:
        data: A GoArchiveData.

    Returns:
        The entry, or None for a library without an import path or files.
    """
    if not data.importpath or not data.srcs:
        return None
    label = data.label
    own = [
        f
        for f in data.srcs
        if f.owner.package == label.package and f.owner.workspace_name == label.workspace_name
    ]
    pick = ([f for f in own if f.is_source] or own or data.srcs)[0]
    return data.importpath + "=" + pick.dirname

def go_deps_info(deps):
    """Returns what the transpiler types the Go libraries in deps from.

    Args:
        deps: Targets of an attribute that applies gala_go_deps_aspect.

    Returns:
        A struct with `direct` (the GoArchiveData of each direct dep, for
        --go-src), `direct_srcs` (a depset of their .go files, but for a GALA
        library's generated ones, which the analyzer skips: they would make
        the transpile wait for the library's own),
        `archives` (a depset of the GoArchiveData of every reachable non-GALA
        library, for --go-export) and `exports` (their export files).
    """
    direct = []
    direct_srcs = []
    for d in deps:
        if GoArchive not in d:
            continue
        data = d[GoArchive].data
        is_gala = GalaGoExportsInfo in d and d[GalaGoExportsInfo].is_gala
        direct.append(data)
        direct_srcs.extend([f for f in data.srcs if f.extension == "go" and (f.is_source or not is_gala)])
    archives, exports = _merge(_infos(deps))
    return struct(
        direct = direct,
        direct_srcs = depset(direct_srcs),
        archives = archives,
        exports = exports,
    )
