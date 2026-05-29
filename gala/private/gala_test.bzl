"""gala_test macro — Test*-function discovery, the canonical GALA test rule.

Replaces the macro formerly named `gala_go_test`. Given .gala test files
with functions named `TestXxx(t T) T`, this macro:

  1. Runs gala_test_gen (from the toolchain) to emit a Go main that
     discovers and runs every Test* function.
  2. Transpiles the .gala test files (and any lib_srcs) to Go.
  3. Wraps the result as a go_binary (external tests, pkg = "main") or
     a go_library + go_test (internal tests, pkg matches the library
     under test) and registers it as a Bazel test target.
"""

load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load(
    "//gala/private:transpile.bzl",
    "gala_transpile",
    "gala_transpile_package",
)
load("//gala/private:test_rules.bzl", "gala_unit_test_rule")

_TOOLCHAIN = "@rules_gala//gala:toolchain_type"
_STDLIB = "@gala//std"
_TEST_FRAMEWORK = "@gala//test"
_TEST_GALA_SOURCES = "@gala//test:gala_sources"

# ---- test main generation -------------------------------------------------

def _test_gen_rule_impl(ctx):
    info = ctx.toolchains[_TOOLCHAIN].galainfo
    if not info.test_gen:
        fail("gala_test requires a toolchain whose `test_gen` attribute is " +
             "set. The toolchain in use does not provide one.")

    out = ctx.actions.declare_file(ctx.label.name + "_main.go")

    args = ctx.actions.args()
    args.add("-output", out)
    args.add("-package", ctx.attr.pkg)
    args.add_all(ctx.files.srcs)

    ctx.actions.run(
        outputs = [out],
        inputs = ctx.files.srcs,
        executable = info.test_gen,
        arguments = [args],
        mnemonic = "GalaTestGen",
        progress_message = "Generating test main for %s" % ctx.label,
    )

    return [DefaultInfo(files = depset([out]))]

_test_gen_rule = rule(
    implementation = _test_gen_rule_impl,
    toolchains = [_TOOLCHAIN],
    attrs = {
        "srcs": attr.label_list(allow_files = [".gala"], mandatory = True),
        "pkg": attr.string(
            default = "main",
            doc = "Package name for the generated main file.",
        ),
    },
)

# ---- public macro ---------------------------------------------------------

def gala_test(name, srcs, deps = [], gala_deps = [], pkg = "main", embed = [], lib_srcs = [], **kwargs):
    """GALA test rule — discovers and runs `Test*` functions.

    Test functions must:

      - Start with the prefix `Test` (e.g., `TestAddition`).
      - Take a single parameter of type `T` and return `T`:
        `func TestXxx(t T) T = ...`.

    For external tests (`pkg = "main"`, the default), use `package main`
    in the test sources and import the library under test.

    For internal tests (`pkg` matches the library), put the test in the
    same package and either pass `lib_srcs` (GALA sources to compile
    alongside the test) or `embed` (already-transpiled `.go` labels).

    Args:
        name: Test target name.
        srcs: Test `.gala` files (e.g., `["foo_test.gala"]`).
        deps: Bazel labels of additional deps.
        gala_deps: Other gala_library labels (cross-package type info).
        pkg: Package name. Default `"main"` for external tests.
        embed: Go source labels for internal tests.
        lib_srcs: GALA library sources to bundle into the test binary
            (alternative to defining a separate gala_library).
        **kwargs: Forwarded to the underlying go_binary / go_test.
    """

    # Step 1: generate the test-main.go that discovers Test* functions.
    gen_name = name + "_gen"
    _test_gen_rule(
        name = gen_name,
        srcs = srcs,
        pkg = pkg,
    )

    # The test framework sources must be on the transpiler's --search
    # path so it can resolve `T`, `RunCases`, etc. — except when the
    # package under test *is* the test framework itself.
    test_extra_srcs = [Label(_TEST_GALA_SOURCES)] if pkg != "test" else []

    # Step 2: transpile lib_srcs (if any), then test srcs.
    transpiled_lib_srcs = [name + "_lib_" + str(i) + ".gen.go" for i in range(len(lib_srcs))]
    if len(lib_srcs) > 1:
        gala_transpile_package(
            name = name + "_lib_transpile",
            srcs = lib_srcs,
            outs = transpiled_lib_srcs,
            extra_srcs = test_extra_srcs,
            gala_deps = gala_deps,
        )
    elif len(lib_srcs) == 1:
        gala_transpile(
            name = name + "_lib_transpile_0",
            src = lib_srcs[0],
            out = transpiled_lib_srcs[0],
            extra_srcs = test_extra_srcs,
            gala_deps = gala_deps,
        )
    else:
        transpiled_lib_srcs = []

    all_package_files = list(srcs) + list(lib_srcs)
    transpiled_srcs = [name + "_test_" + str(i) + ".go" for i in range(len(srcs))]

    # Per-file transpile for test sources because each test source needs
    # the other test sources + every lib_src as `package_files`, which
    # gala_transpile_package doesn't model.
    for i, src in enumerate(srcs):
        siblings = [f for f in all_package_files if f != src]
        gala_transpile(
            name = name + "_transpile_" + str(i),
            src = src,
            out = transpiled_srcs[i],
            package_files = siblings,
            extra_srcs = test_extra_srcs,
            gala_deps = gala_deps,
        )

    main_go_src = ":" + gen_name

    final_deps = list(deps) + list(gala_deps)
    if pkg != "test":
        final_deps.append(Label(_TEST_FRAMEWORK))
    if pkg != "std":
        final_deps.append(Label(_STDLIB))

    if pkg == "main":
        # External test: package main → wrap a go_binary as the test.
        binary_name = name + "_bin"
        all_srcs = transpiled_lib_srcs + transpiled_srcs + [main_go_src] + embed

        go_binary(
            name = binary_name,
            srcs = all_srcs,
            deps = final_deps,
            **kwargs
        )

        gala_unit_test_rule(
            name = name,
            binary = ":" + binary_name,
            is_windows = select({
                "@platforms//os:windows": True,
                "//conditions:default": False,
            }),
        )
    else:
        # Internal test: same package as the library under test. Use
        # go_library + go_test with embed; avoids the go_binary
        # package-main constraint.
        lib_name = name + "_lib"
        if transpiled_lib_srcs or embed:
            go_library(
                name = lib_name,
                srcs = transpiled_lib_srcs + embed,
                deps = final_deps,
                importpath = pkg,
            )
            test_embed = [":" + lib_name]
        else:
            test_embed = []

        go_test(
            name = name,
            srcs = transpiled_srcs + [main_go_src],
            embed = test_embed,
            deps = final_deps,
            **kwargs
        )
