"""Public Starlark API for rules_gala.

Load everything from here:

    load("@rules_gala//gala:defs.bzl",
        "gala_library",
        "gala_binary",
        "gala_test",
        "gala_exec_test",
        "gala_unit_test",
        "gala_transpile",
        "gala_transpile_package",
        "gala_bootstrap_transpile",
        "gala_imports_helper",
    )
"""

load(
    "//gala/private:gala_library.bzl",
    _gala_binary = "gala_binary",
    _gala_library = "gala_library",
)
load(
    "//gala/private:gala_test.bzl",
    _gala_test = "gala_test",
)
load(
    "//gala/private:test_rules.bzl",
    _gala_exec_test = "gala_exec_test",
    _gala_unit_test = "gala_unit_test",
)
load(
    "//gala/private:transpile.bzl",
    _gala_bootstrap_transpile = "gala_bootstrap_transpile",
    _gala_transpile = "gala_transpile",
    _gala_transpile_package = "gala_transpile_package",
)
load(
    "//gala/private:gazelle.bzl",
    _gala_imports_helper = "gala_imports_helper",
)

gala_library = _gala_library
gala_binary = _gala_binary
gala_test = _gala_test
gala_exec_test = _gala_exec_test
gala_unit_test = _gala_unit_test
gala_transpile = _gala_transpile
gala_transpile_package = _gala_transpile_package
gala_bootstrap_transpile = _gala_bootstrap_transpile
gala_imports_helper = _gala_imports_helper
