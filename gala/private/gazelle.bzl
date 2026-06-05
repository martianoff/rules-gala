"""Toolchain-resolved gala helper for the Gazelle extension.

The `gala_gazelle` Gazelle extension extracts imports by shelling out to a
`gala imports --json` helper. Rather than hard-wire a specific gala binary
(e.g. `@gala//cmd/gala:gala`) or rely on whatever `gala` is on `PATH`,
`gala_imports_helper` re-exports the gala binary from the **registered GALA
toolchain**. The helper that extracts imports is then the same gala the
toolchain transpiles with, so BUILD generation is reproducible and never drifts
from the consumed gala version.

Usage in the consumer's `BUILD.bazel`:

    load("@rules_gala//gala:defs.bzl", "gala_imports_helper")

    gala_imports_helper(name = "gala_imports")

    gazelle(
        name = "gazelle",
        gazelle = ":gazelle_bin",
        data = [":gala_imports"],
        extra_args = ["-gala_helper=$(execpath :gala_imports)"],
    )
"""

_TOOLCHAIN = "@rules_gala//gala:toolchain_type"

def _gala_imports_helper_impl(ctx):
    info = ctx.toolchains[_TOOLCHAIN].galainfo
    gala = info.gala_binary.executable

    # Symlink the toolchain's gala binary to a same-extension output so it stays
    # runnable on every host. Bazel does NOT add a `.exe` suffix to a Starlark
    # rule's predeclared executable on Windows, so a bare `ctx.label.name`
    # symlink to `gala.exe` would not execute — mirror the source extension.
    ext = gala.extension
    out = ctx.actions.declare_file(ctx.label.name + ("." + ext if ext else ""))
    ctx.actions.symlink(
        output = out,
        target_file = gala,
        is_executable = True,
    )

    # `gala imports` only parses the files passed on its command line, so the
    # binary (which embeds the stdlib) is self-sufficient; carry it in runfiles
    # so the symlink resolves wherever gazelle stages it.
    return [DefaultInfo(
        executable = out,
        files = depset([out]),
        runfiles = ctx.runfiles(files = [gala]),
    )]

gala_imports_helper = rule(
    implementation = _gala_imports_helper_impl,
    executable = True,
    toolchains = [_TOOLCHAIN],
    doc = "Re-export the registered GALA toolchain's gala binary as a runnable " +
          "import-extraction helper for the gala_gazelle Gazelle extension.",
)
