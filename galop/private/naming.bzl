"""Names of the Go files galop generates for a grammar.

This is the single place that encodes galop's output naming. galop_parser
declares exactly these files as action outputs, so if galop's naming changes
only this function needs to follow.
"""

KINDS = ["combined", "lexer", "parser"]

# galop's Go output flavors (`-Dflavor`). The first is galop's default.
FLAVORS = ["native", "antlr"]

def _trim_suffix(s, suffix):
    if s.endswith(suffix) and len(s) > len(suffix):
        return s[:-len(suffix)]
    return s

def galop_go_outputs(grammar_name, kind, flavor = "native"):
    """Returns the basenames of the Go files galop writes for one grammar.

    Follows ANTLR's Go target: the file prefix is the grammar name, lowercased.
    For a `parser grammar` a trailing `Parser` is trimmed from the name, for a
    `lexer grammar` a trailing `Lexer`, so `parser grammar CalcParser` and
    `lexer grammar CalcLexer` produce `calc_parser.go` and `calc_lexer.go`.
    The `antlr` flavor adds `_galop` (`calc_galop_parser.go`), so its files
    can sit next to the ones ANTLR generates.

    galop accepts `-listener` and `-visitor` for ANTLR compatibility, but no
    flavor writes listener or visitor files.

    Args:
        grammar_name: the grammar name, which equals the .g4 file's base name.
        kind: "combined", "lexer" or "parser".
        flavor: "native" or "antlr".

    Returns:
        A list of file basenames.
    """
    if kind not in KINDS:
        fail("galop: unknown grammar kind %r; expected one of %s" % (kind, KINDS))
    if flavor not in FLAVORS:
        fail("galop: unknown flavor %r; expected one of %s" % (flavor, FLAVORS))

    if kind == "parser":
        base = _trim_suffix(grammar_name, "Parser")
    elif kind == "lexer":
        base = _trim_suffix(grammar_name, "Lexer")
    else:
        base = grammar_name
    base = base.lower()
    if flavor == "antlr":
        base += "_galop"

    outs = []
    if kind in ("combined", "parser"):
        outs.append(base + "_parser.go")
    if kind in ("combined", "lexer"):
        outs.append(base + "_lexer.go")
    return outs
