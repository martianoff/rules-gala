"""Public Starlark API for the gala_gazelle Gazelle extension.

Wire a toolchain-driven Gazelle for GALA in a single call:

    load("@gala_gazelle//gala:defs.bzl", "gala_gazelle")

    gala_gazelle(
        name = "gazelle",
        gala_prefix = "github.com/you/project",
    )

`bazel run //:gazelle` then manages GALA, mixed GALA/Go, and pure-Go BUILD
files. The import helper is driven from the registered GALA toolchain by
default, so BUILD generation is reproducible and never drifts from the gala
version the toolchain builds with.
"""

load("@gazelle//:def.bzl", "gazelle", "gazelle_binary")
load("@rules_gala//gala:defs.bzl", "gala_imports_helper")

def gala_gazelle(
        name,
        gala_prefix = None,
        gala_helper = None,
        languages = None,
        extra_args = None,
        **kwargs):
    """Create a toolchain-driven gazelle setup for GALA.

    Generates three targets:

      <name>_bin           a gazelle_binary with the composite GALA language.
                           The composite embeds Gazelle's Go language, so it
                           manages GALA, mixed GALA/Go, and pure-Go packages —
                           do NOT also pass "@gazelle//language/go".
      <name>_gala_imports  a gala_imports_helper re-exporting the registered
                           GALA toolchain's gala binary (the import-extraction
                           helper). Omitted when `gala_helper` is set.
      <name>               the runnable gazelle rule, wired to the helper.

    Args:
      name: base name; the runnable target is `//:<name>`.
      gala_prefix: import-path prefix for in-repo GALA packages (passed as
        `-gala_prefix`; equivalent to a `# gazelle:gala_prefix` directive).
      gala_helper: optional label of a gala binary to use as the import helper
        INSTEAD of the registered toolchain. Set this to pin a specific gala
        version/binary; by default the toolchain is used (reproducible).
      languages: extra gazelle_binary languages to bundle alongside the GALA
        composite. Rarely needed — the composite already manages Go.
      extra_args: extra arguments forwarded to the gazelle rule.
      **kwargs: forwarded to the gazelle rule (e.g. visibility, tags).
    """
    gazelle_binary(
        name = name + "_bin",
        languages = (languages or []) + ["@gala_gazelle//gala"],
        visibility = ["//visibility:private"],
    )

    args = list(extra_args or [])
    if gala_prefix:
        args.append("-gala_prefix=" + gala_prefix)

    if gala_helper:
        helper = gala_helper
    else:
        helper = ":" + name + "_gala_imports"
        gala_imports_helper(name = name + "_gala_imports")

    args.append("-gala_helper=$(execpath {})".format(helper))

    gazelle(
        name = name,
        gazelle = ":" + name + "_bin",
        data = [helper],
        extra_args = args,
        **kwargs
    )
