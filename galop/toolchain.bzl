"""Toolchain rule and provider for galop.

galop (https://github.com/martianoff/galop) reads ANTLR `.g4` grammars and
generates Go parsers. galop_parser resolves the executable at action time via
`ctx.toolchains["@rules_gala//galop:toolchain_type"].galopinfo`.

The `galop` module extension (extensions.bzl) registers toolchains backed by
prebuilt release binaries. To use any other executable — for example galop
built from source with gala_binary — declare your own:

    load("@rules_gala//galop:toolchain.bzl", "galop_toolchain")

    galop_toolchain(
        name = "my_galop_impl",
        galop = "//cmd/galop",
    )

    toolchain(
        name = "my_galop",
        toolchain = ":my_galop_impl",
        toolchain_type = "@rules_gala//galop:toolchain_type",
    )

and register it with `register_toolchains("//path/to:my_galop")`.
"""

GalopToolchainInfo = provider(
    doc = "The galop executable used by galop_parser.",
    fields = {
        "galop": "FilesToRunProvider: the galop parser generator.",
    },
)

def _galop_toolchain_impl(ctx):
    info = GalopToolchainInfo(
        galop = ctx.attr.galop[DefaultInfo].files_to_run,
    )
    return [platform_common.ToolchainInfo(galopinfo = info)]

galop_toolchain = rule(
    implementation = _galop_toolchain_impl,
    doc = "Declare a galop toolchain. Pair with a `toolchain()` declaration " +
          "that binds it to `@rules_gala//galop:toolchain_type`.",
    attrs = {
        "galop": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
            allow_files = True,
            doc = "The galop executable: a prebuilt binary file or any " +
                  "executable target (e.g. a gala_binary or go_binary).",
        ),
    },
)
