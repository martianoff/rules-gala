"""Names of the Go files galop generates for a grammar.

This is the single place that encodes galop's output naming. galop_parser
declares exactly these files as action outputs, so if galop's naming changes
only this function needs to follow.
"""

KINDS = ["combined", "lexer", "parser"]
FLAVORS = ["companion", "standalone"]

def _trim_suffix(s, suffix):
    if s.endswith(suffix) and len(s) > len(suffix):
        return s[:-len(suffix)]
    return s

def galop_go_outputs(grammar_name, kind, flavor, listener, visitor):
    """Returns the basenames of the Go files galop writes for one grammar.

    Follows ANTLR's Go target: the file prefix is the grammar name, lowercased.
    For a `parser grammar` a trailing `Parser` is trimmed from the name, for a
    `lexer grammar` a trailing `Lexer`, so `parser grammar CalcParser` and
    `lexer grammar CalcLexer` produce `calc_galop_parser.go` and
    `calc_galop_lexer.go`.

    Args:
        grammar_name: the grammar name, which equals the .g4 file's base name.
        kind: "combined", "lexer" or "parser".
        flavor: "companion" or "standalone".
        listener: whether a parse-tree listener is generated.
        visitor: whether a parse-tree visitor is generated.

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

    outs = []
    if kind in ("combined", "parser"):
        outs.append(base + "_galop_parser.go")
    if kind in ("combined", "lexer"):
        outs.append(base + "_galop_lexer.go")

    # In the companion flavor the output sits next to ANTLR's own generated
    # package, which already has the listener and visitor, so those flags add
    # no files. Lexers never get a listener or visitor.
    if flavor == "standalone" and kind != "lexer":
        if listener:
            outs.append(base + "_listener.go")
            outs.append(base + "_base_listener.go")
        if visitor:
            outs.append(base + "_visitor.go")
            outs.append(base + "_base_visitor.go")
    return outs
