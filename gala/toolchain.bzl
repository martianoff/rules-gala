"""Toolchain rule and provider for the GALA language.

Wire executables and language assets up here and the rules in
`@rules_gala//gala:defs.bzl` resolve them at action time via
`ctx.toolchains["@rules_gala//gala:toolchain_type"].galainfo`.
"""

GalaToolchainInfo = provider(
    doc = "Executables and files the GALA rules need at action time.",
    fields = {
        "gala_binary": "FilesToRunProvider: the gala transpiler.",
        "gala_worker": "FilesToRunProvider: the persistent-worker variant " +
                       "of the transpiler. Defaults to gala_binary if unset.",
        "gala_bootstrap": "FilesToRunProvider: the bootstrap transpiler " +
                          "used only when building the stdlib.",
        "test_runner": "FilesToRunProvider: gala_test_runner — invoked by " +
                       "gala_exec_test to diff actual vs expected output.",
        "test_runner_runfiles": "runfiles: the test_runner target's default " +
                                "runfiles. Merged into gala_exec_test runfiles.",
        "test_gen": "FilesToRunProvider: gala_test_gen — emits the Go main " +
                    "that discovers and runs `Test*` functions for gala_test.",
        "all_gala_sources": "depset[File]: every .gala source in the workspace " +
                            "the transpiler is allowed to --search.",
        "go_mod": "File: the consuming repo's go.mod, used to derive its " +
                  "module root for the transpiler's --search path.",
    },
)

def _gala_toolchain_impl(ctx):
    worker = ctx.attr.gala_worker or ctx.attr.gala_binary
    info = GalaToolchainInfo(
        gala_binary = ctx.attr.gala_binary[DefaultInfo].files_to_run,
        gala_worker = worker[DefaultInfo].files_to_run,
        gala_bootstrap = ctx.attr.gala_bootstrap[DefaultInfo].files_to_run if ctx.attr.gala_bootstrap else None,
        test_runner = ctx.attr.test_runner[DefaultInfo].files_to_run if ctx.attr.test_runner else None,
        test_runner_runfiles = ctx.attr.test_runner[DefaultInfo].default_runfiles if ctx.attr.test_runner else None,
        test_gen = ctx.attr.test_gen[DefaultInfo].files_to_run if ctx.attr.test_gen else None,
        all_gala_sources = depset(ctx.files.all_gala_sources),
        go_mod = ctx.file.go_mod,
    )
    return [platform_common.ToolchainInfo(galainfo = info)]

gala_toolchain = rule(
    implementation = _gala_toolchain_impl,
    doc = "Declare a GALA toolchain. Pair with a `toolchain()` " +
          "declaration that binds this to `@rules_gala//gala:toolchain_type`.",
    attrs = {
        "gala_binary": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
            doc = "The gala transpiler binary.",
        ),
        "gala_worker": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The persistent-worker variant of the transpiler. " +
                  "If omitted, gala_binary is used for both.",
        ),
        "gala_bootstrap": attr.label(
            executable = True,
            cfg = "exec",
            doc = "Bootstrap transpiler used only for stdlib transpilation.",
        ),
        "test_runner": attr.label(
            executable = True,
            cfg = "exec",
            doc = "gala_test_runner binary used by gala_exec_test.",
        ),
        "test_gen": attr.label(
            executable = True,
            cfg = "exec",
            doc = "gala_test_gen binary used by gala_test.",
        ),
        "all_gala_sources": attr.label(
            allow_files = [".gala"],
            doc = "Filegroup of every .gala source in the workspace. The " +
                  "transpiler walks this for cross-package type resolution.",
        ),
        "go_mod": attr.label(
            allow_single_file = True,
            doc = "The consuming repo's go.mod. Its directory becomes the " +
                  "default --search path entry for the transpiler.",
        ),
    },
)
