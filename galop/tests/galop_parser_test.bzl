"""Analysis and unit tests for galop_parser and its output naming."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//galop:defs.bzl", "galop_go_outputs", "galop_parser")

def _basenames(files):
    return [f.basename for f in files]

def _command_line_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "GalopGenerate"]
    asserts.equals(env, 1, len(actions), "expected one GalopGenerate action")
    argv = actions[0].argv

    # argv[0] is the galop executable.
    o = argv.index("-o")
    asserts.true(
        env,
        argv[o + 1].endswith("galop/tests/args_parser"),
        "-o should be the target's output directory, got %s" % argv[o + 1],
    )
    asserts.equals(env, [
        "-Xexact-output-dir",
        "-Dlanguage=Go",
        "-Dflavor=antlr",
        "-package",
        "calcpkg",
        "-DcontextSuperClass=MyCtx",
        "-DsuperClass=MyBase",
        "-Werror",
        "-message-format",
        "gnu",
    ], argv[o + 2:-1])
    asserts.true(env, argv[-1].endswith("galop/tests/Calc.g4"), "grammar last, got %s" % argv[-1])

    asserts.equals(
        env,
        ["calc_galop_parser.go", "calc_galop_lexer.go"],
        _basenames(target[DefaultInfo].files.to_list()),
    )
    return analysistest.end(env)

_command_line_test = analysistest.make(_command_line_test_impl)

def _minimal_command_line_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "GalopGenerate"]
    argv = actions[0].argv
    asserts.true(env, "-Dflavor=native" in argv, "native is the default flavor")
    asserts.false(env, "-package" in argv, "no -package when package is empty")
    for flag in ["-listener", "-no-listener", "-visitor", "-no-visitor"]:
        asserts.false(env, flag in argv, "%s is not passed: it adds no files" % flag)
    asserts.equals(
        env,
        ["calc_parser.go", "calc_lexer.go"],
        _basenames(target[DefaultInfo].files.to_list()),
    )
    return analysistest.end(env)

_minimal_command_line_test = analysistest.make(_minimal_command_line_test_impl)

def _reserved_define_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "-Dflavor is set by the rule")
    return analysistest.end(env)

_reserved_define_test = analysistest.make(_reserved_define_test_impl, expect_failure = True)

def _naming_test_impl(ctx):
    env = unittest.begin(ctx)
    cases = [
        # (grammar name, kind, flavor, expected)
        ("Calc", "combined", "native", ["calc_parser.go", "calc_lexer.go"]),
        ("CalcParser", "parser", "native", ["calc_parser.go"]),
        ("CalcLexer", "lexer", "native", ["calc_lexer.go"]),
        ("Calc", "combined", "antlr", ["calc_galop_parser.go", "calc_galop_lexer.go"]),
        ("CalcParser", "parser", "antlr", ["calc_galop_parser.go"]),
        ("CalcLexer", "lexer", "antlr", ["calc_galop_lexer.go"]),
        # Only a trailing suffix of the matching kind is trimmed.
        ("CalcParser", "combined", "native", ["calcparser_parser.go", "calcparser_lexer.go"]),
        ("CalcLexer", "parser", "native", ["calclexer_parser.go"]),
        ("CalcParser", "combined", "antlr", ["calcparser_galop_parser.go", "calcparser_galop_lexer.go"]),
        ("CalcLexer", "parser", "antlr", ["calclexer_galop_parser.go"]),
        # A name that is only the suffix is kept.
        ("Parser", "parser", "native", ["parser_parser.go"]),
        ("Lexer", "lexer", "antlr", ["lexer_galop_lexer.go"]),
    ]
    for name, kind, flavor, want in cases:
        asserts.equals(
            env,
            want,
            galop_go_outputs(name, kind, flavor),
            "%s %s %s" % (name, kind, flavor),
        )

    # native is the default flavor.
    asserts.equals(env, ["expr_parser.go", "expr_lexer.go"], galop_go_outputs("Expr", "combined"))
    return unittest.end(env)

_naming_test = unittest.make(_naming_test_impl)

def galop_parser_test_suite(name):
    """Declares the analysis and unit tests.

    Args:
        name: name of the test_suite.
    """
    galop_parser(
        name = "args_parser",
        grammar = "Calc.g4",
        package = "calcpkg",
        flavor = "antlr",
        defines = {"superClass": "MyBase", "contextSuperClass": "MyCtx"},
        galop_opts = ["-Werror", "-message-format", "gnu"],
        tags = ["manual"],
    )
    _command_line_test(name = name + "_command_line", target_under_test = ":args_parser")

    galop_parser(
        name = "minimal_parser",
        grammar = "Calc.g4",
        tags = ["manual"],
    )
    _minimal_command_line_test(name = name + "_minimal_command_line", target_under_test = ":minimal_parser")

    galop_parser(
        name = "reserved_define_parser",
        grammar = "Calc.g4",
        defines = {"flavor": "antlr"},
        tags = ["manual"],
    )
    _reserved_define_test(name = name + "_reserved_define", target_under_test = ":reserved_define_parser")

    unittest.suite(name + "_naming", _naming_test)

    native.test_suite(
        name = name,
        tests = [
            name + "_command_line",
            name + "_minimal_command_line",
            name + "_reserved_define",
            name + "_naming",
        ],
    )
