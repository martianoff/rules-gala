"""Public Starlark API for galop support.

    load("@rules_gala//galop:defs.bzl", "galop_parser")

galop_parser generates a Go parser from an ANTLR `.g4` grammar using the
galop parser generator, resolved through `@rules_gala//galop:toolchain_type`.
See the README for toolchain setup.
"""

load("//galop/private:galop_parser.bzl", _galop_parser = "galop_parser")
load("//galop/private:naming.bzl", _galop_go_outputs = "galop_go_outputs")

galop_parser = _galop_parser

# Exposed for macros that need to know the generated file names up front.
galop_go_outputs = _galop_go_outputs
