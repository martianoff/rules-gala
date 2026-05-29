"""Test rules:

  gala_exec_test (was: gala_test)
    Diff a binary's stdout against an `expected` file.

  gala_unit_test
    Wrap a gala_binary as a test (exit-code-only).
"""

load("//gala/private:gala_library.bzl", "gala_binary")

_TOOLCHAIN = "@rules_gala//gala:toolchain_type"

# ---- exec test (stdout vs expected) ---------------------------------------

def _exec_test_rule_impl(ctx):
    info = ctx.toolchains[_TOOLCHAIN].galainfo
    if not info.test_runner:
        fail("gala_exec_test requires a toolchain whose `test_runner` " +
             "attribute is set. The toolchain in use does not provide one.")

    binary = ctx.executable.binary
    expected = ctx.file.expected
    runner = info.test_runner.executable

    extension = ".bat" if ctx.attr.is_windows else ".sh"
    executable = ctx.actions.declare_file(ctx.label.name + extension)

    if ctx.attr.is_windows:
        runner_path = runner.short_path.replace("/", "\\")
        binary_path = binary.short_path.replace("/", "\\")
        expected_path = expected.short_path.replace("/", "\\")
        ctx.actions.write(
            output = executable,
            content = "@echo off\n\"%s\" %%* \"%s\" \"%s\"" % (runner_path, binary_path, expected_path),
            is_executable = True,
        )
    else:
        ctx.actions.write(
            output = executable,
            content = "#!/bin/bash\n%s \"$@\" %s %s" % (runner.short_path, binary.short_path, expected.short_path),
            is_executable = True,
        )

    runfiles = ctx.runfiles(files = [binary, expected, runner])
    runfiles = runfiles.merge(ctx.attr.binary[DefaultInfo].default_runfiles)
    if info.test_runner_runfiles:
        runfiles = runfiles.merge(info.test_runner_runfiles)

    return [DefaultInfo(executable = executable, runfiles = runfiles)]

_exec_test_rule = rule(
    implementation = _exec_test_rule_impl,
    test = True,
    toolchains = [_TOOLCHAIN],
    attrs = {
        "binary": attr.label(executable = True, cfg = "target", mandatory = True),
        "expected": attr.label(allow_single_file = True, mandatory = True),
        "is_windows": attr.bool(default = False),
    },
)

def gala_exec_test(name, src = None, srcs = None, expected = "", deps = [], gala_deps = [], **kwargs):
    """Test that a GALA program's stdout matches a checked-in expected file.

    Replaces the macro formerly named `gala_test`.
    """
    binary_name = name + "_bin"
    gala_binary(
        name = binary_name,
        src = src,
        srcs = srcs,
        deps = deps,
        gala_deps = gala_deps,
        **kwargs
    )
    _exec_test_rule(
        name = name,
        binary = ":" + binary_name,
        expected = expected,
        is_windows = select({
            "@platforms//os:windows": True,
            "//conditions:default": False,
        }),
    )

# ---- unit test (binary-as-test, no output diff) ---------------------------

def _unit_test_rule_impl(ctx):
    binary = ctx.executable.binary
    extension = ".bat" if ctx.attr.is_windows else ".sh"
    executable = ctx.actions.declare_file(ctx.label.name + extension)

    if ctx.attr.is_windows:
        binary_path = binary.short_path.replace("/", "\\")
        ctx.actions.write(
            output = executable,
            content = "@echo off\n\"%s\" %%*" % binary_path,
            is_executable = True,
        )
    else:
        ctx.actions.write(
            output = executable,
            content = "#!/bin/bash\n%s \"$@\"" % binary.short_path,
            is_executable = True,
        )

    binary_runfiles = ctx.attr.binary[DefaultInfo].default_runfiles
    return [DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = [binary]).merge(binary_runfiles),
    )]

gala_unit_test_rule = rule(
    implementation = _unit_test_rule_impl,
    test = True,
    attrs = {
        "binary": attr.label(executable = True, cfg = "target", mandatory = True),
        "is_windows": attr.bool(default = False),
    },
)

def gala_unit_test(name, src = None, srcs = None, deps = [], **kwargs):
    """Run a gala_binary as a test (pass/fail = exit code)."""
    binary_name = name + "_bin"
    gala_binary(
        name = binary_name,
        src = src,
        srcs = srcs,
        deps = deps,
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

