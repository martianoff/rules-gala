"""The Go sources the transpiler types a GALA package's Go dependencies from.

The transpiler's analyzer types a third-party Go package by parsing its .go
source, because go/importer's source mode cannot find a versioned module in
Bazel's external tree. It needs the source of every package it reaches, not
only of those the GALA code imports: cobra's `Command.Flags()` returns a
`*pflag.FlagSet`, so `cmd.Flags().GetString("x")` has a Go signature, and
lowers to `Try[string]`, only if pflag's source is wired in too.

go_src_info gives, for every Go library reachable from a list of deps, an
`<importpath>=<dir>` entry for the transpiler's --go-src flag and the
library's .go files to stage as action inputs. Both are depsets, so nothing
is flattened during analysis: the entries are rules_go's own GoArchive
`transitive` depset, turned into strings when the action runs, and the files
are collected by gala_go_srcs_aspect.

GALA libraries are go_libraries too, so their generated .gen.go files are
collected as well. The analyzer skips files the transpiler wrote, and types a
GALA package from its .gala source, so they are inert.
"""

load("@rules_go//go:def.bzl", "GoArchive")

GalaGoSrcsInfo = provider(
    doc = "The .go files of a Go library and of every library it depends on.",
    fields = {"srcs": "depset of .go files."},
)

def _go_files(files):
    return [f for f in files if f.extension == "go"]

# The attributes rules_go takes a library's archive deps from: a library's
# deps and embeds, and the compilers of a go_proto_library, whose own deps
# are the protobuf runtime packages the generated code imports. Following
# them all stages the files of every library in GoArchive.transitive.
_DEP_ATTRS = ["deps", "embed", "compiler", "compilers"]

def _gala_go_srcs_aspect_impl(target, ctx):
    own = _go_files(target[GoArchive].data.srcs) if GoArchive in target else []
    deps = []
    for attr in _DEP_ATTRS:
        value = getattr(ctx.rule.attr, attr, None)
        if type(value) == "Target":
            deps.append(value)
        elif type(value) == "list":
            deps.extend(value)
    return [GalaGoSrcsInfo(srcs = depset(own, transitive = [
        d[GalaGoSrcsInfo].srcs
        for d in deps
        if type(d) == "Target" and GalaGoSrcsInfo in d
    ]))]

# Applied to a GALA rule's go_deps.
gala_go_srcs_aspect = aspect(
    implementation = _gala_go_srcs_aspect_impl,
    attr_aspects = _DEP_ATTRS,
    provides = [GalaGoSrcsInfo],
)

def go_src_entry(data):
    """The --go-src entry of a GoArchiveData: `<importpath>=<source dir>`.

    rules_go merges an embedded library's files into the archive that embeds
    it, ahead of the library's own, so the directory is that of a file in the
    library's own package: a checked-in one if it has any, because a GALA
    library lists its generated .gen.go files, which the analyzer skips,
    ahead of its hand-written .go files. A library with no file of its own
    (all of them embedded) takes the first file's directory.

    For args.add_joined's map_each, so it runs when the action does.

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

def go_src_info(deps):
    """Returns the --go-src archives and the .go files reachable from deps.

    Args:
        deps: Targets of an attribute that applies gala_go_srcs_aspect.

    Returns:
        A struct: `archives`, a depset of GoArchiveData (one per library, for
        go_src_entry), and `srcs`, a depset of their .go files.
    """
    return struct(
        archives = depset(transitive = [d[GoArchive].transitive for d in deps if GoArchive in d]),
        srcs = depset(transitive = [d[GalaGoSrcsInfo].srcs for d in deps if GalaGoSrcsInfo in d]),
    )
