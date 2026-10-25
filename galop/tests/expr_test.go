package expr

import "testing"

// The standalone flavor adds listener and visitor files.
func TestStandaloneOutputs(t *testing.T) {
	for got, want := range map[string]string{
		ExprGalopParser:  "expr_galop_parser.go",
		ExprGalopLexer:   "expr_galop_lexer.go",
		ExprListener:     "expr_listener.go",
		ExprBaseListener: "expr_base_listener.go",
		ExprVisitor:      "expr_visitor.go",
		ExprBaseVisitor:  "expr_base_visitor.go",
	} {
		if got != want {
			t.Errorf("got %q, want %q", got, want)
		}
	}
}
