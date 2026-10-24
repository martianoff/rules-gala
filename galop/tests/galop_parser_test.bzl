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
        "-Dflavor=companion",
        "-package",
        "calcpkg",
        "-no-listener",
        "-visitor",
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
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "GalopGenerate"]
    argv = actions[0].argv
    asserts.false(env, "-package" in argv, "no -package when package is empty")
    asserts.true(env, "-listener" in argv, "listener is on by default")
    asserts.true(env, "-no-visitor" in argv, "visitor is off by default")
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
        # (grammar name, kind, flavor, listener, visitor, expected)
        ("Calc", "combined", "companion", True, True, ["calc_galop_parser.go", "calc_galop_lexer.go"]),
        ("CalcParser", "parser", "companion", True, False, ["calc_galop_parser.go"]),
        ("CalcLexer", "lexer", "companion", True, False, ["calc_galop_lexer.go"]),
        # Only a trailing suffix of the matching kind is trimmed.
        ("CalcParser", "combined", "companion", True, False, ["calcparser_galop_parser.go", "calcparser_galop_lexer.go"]),
        ("CalcLexer", "parser", "companion", True, False, ["calclexer_galop_parser.go"]),
        ("Parser", "parser", "companion", True, False, ["parser_galop_parser.go"]),
        ("Expr", "combined", "standalone", True, False, [
            "expr_galop_parser.go",
            "expr_galop_lexer.go",
            "expr_listener.go",
            "expr_base_listener.go",
        ]),
        ("ExprParser", "parser", "standalone", False, True, [
            "expr_galop_parser.go",
            "expr_visitor.go",
            "expr_base_visitor.go",
        ]),
        ("ExprLexer", "lexer", "standalone", True, True, ["expr_galop_lexer.go"]),
    ]
    for name, kind, flavor, listener, visitor, want in cases:
        asserts.equals(
            env,
            want,
            galop_go_outputs(name, kind, flavor, listener, visitor),
            "%s %s %s listener=%s visitor=%s" % (name, kind, flavor, listener, visitor),
        )
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
        listener = False,
        visitor = True,
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
        defines = {"flavor": "standalone"},
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
