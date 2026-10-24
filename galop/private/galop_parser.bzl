"""Implementation of galop_parser."""

load(":naming.bzl", "FLAVORS", "KINDS", "galop_go_outputs")

_TOOLCHAIN = "@rules_gala//galop:toolchain_type"

# -D options the rule sets itself; the declared outputs depend on them, so
# they must not be overridden through `defines`.
_RESERVED_DEFINES = ["language", "flavor"]

def _galop_parser_impl(ctx):
    grammar = ctx.file.grammar
    if not grammar.basename.endswith(".g4"):
        fail("galop_parser: grammar must be a .g4 file, got %s" % grammar.basename)
    grammar_name = grammar.basename[:-len(".g4")]

    for key in ctx.attr.defines:
        if key in _RESERVED_DEFINES:
            fail(("galop_parser: -D%s is set by the rule; use the `%s` attribute " +
                  "instead of `defines`") % (key, "flavor" if key == "flavor" else "language"))

    names = galop_go_outputs(
        grammar_name = grammar_name,
        kind = ctx.attr.kind,
        flavor = ctx.attr.flavor,
        listener = ctx.attr.listener,
        visitor = ctx.attr.visitor,
    )

    # Outputs live in a directory named after the target, so several
    # galop_parser targets in one package never collide.
    outs = [ctx.actions.declare_file(ctx.label.name + "/" + n) for n in names]
    out_dir = outs[0].dirname

    args = ctx.actions.args()
    args.add("-o", out_dir)
    args.add("-Xexact-output-dir")
    args.add("-Dlanguage=Go")
    args.add("-Dflavor=" + ctx.attr.flavor)
    if ctx.attr.package:
        args.add("-package", ctx.attr.package)
    args.add("-listener" if ctx.attr.listener else "-no-listener")
    args.add("-visitor" if ctx.attr.visitor else "-no-visitor")
    for key, value in sorted(ctx.attr.defines.items()):
        args.add("-D%s=%s" % (key, value))
    args.add_all(ctx.attr.galop_opts)
    args.add(grammar)

    info = ctx.toolchains[_TOOLCHAIN].galopinfo
    ctx.actions.run(
        executable = info.galop,
        arguments = [args],
        inputs = [grammar] + ctx.files.imports,
        outputs = outs,
        mnemonic = "GalopGenerate",
        progress_message = "Generating Go parser from %{label} (" + grammar.short_path + ")",
    )

    return [DefaultInfo(files = depset(outs))]

galop_parser = rule(
    implementation = _galop_parser_impl,
    doc = """Generates a Go parser from an ANTLR `.g4` grammar with galop.

The generated `.go` files are this target's default outputs, so the target
can go straight into the `srcs` of a `go_library`.

The grammar name is taken from the file name (`Calc.g4` declares grammar
`Calc`); galop, like ANTLR, rejects a grammar whose name differs from its
file name. Because Bazel must know the output file names before galop runs,
`kind` has to say whether the grammar is a combined, lexer or parser grammar.
""",
    attrs = {
        "grammar": attr.label(
            allow_single_file = [".g4"],
            mandatory = True,
            doc = "The `.g4` grammar. Its base name must equal the grammar name.",
        ),
        "imports": attr.label_list(
            allow_files = [".g4", ".tokens"],
            doc = "Other grammars this one imports, or token vocabularies it " +
                  "references with `tokenVocab`. They are made available to " +
                  "galop as inputs; keep them next to `grammar` (galop looks " +
                  "there) or point galop at them with `galop_opts`.",
        ),
        "kind": attr.string(
            default = "combined",
            values = KINDS,
            doc = "What the grammar declares: `combined` (`grammar T;`), " +
                  "`lexer` (`lexer grammar TLexer;`) or `parser` " +
                  "(`parser grammar TParser;`). Determines the output files.",
        ),
        "package": attr.string(
            doc = "Go package name of the generated code (`-package`). " +
                  "Empty means galop's default.",
        ),
        "flavor": attr.string(
            default = "companion",
            values = FLAVORS,
            doc = "galop's Go output flavor (`-Dflavor`). `companion` " +
                  "generates code that sits next to ANTLR's own generated " +
                  "package; `standalone` also generates the listener and " +
                  "visitor files.",
        ),
        "listener": attr.bool(
            default = True,
            doc = "Generate a parse-tree listener (`-listener` / `-no-listener`).",
        ),
        "visitor": attr.bool(
            default = False,
            doc = "Generate a parse-tree visitor (`-visitor` / `-no-visitor`).",
        ),
        "defines": attr.string_dict(
            doc = "Extra grammar options passed as `-D<key>=<value>`. " +
                  "`language` and `flavor` are set by the rule and rejected here.",
        ),
        "galop_opts": attr.string_list(
            doc = "Extra raw command-line arguments, inserted before the grammar. " +
                  "Options that change which files are generated (`-o`, " +
                  "`-Dflavor`, …) will break the declared outputs.",
        ),
    },
    toolchains = [_TOOLCHAIN],
)
