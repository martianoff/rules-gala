package expr

import "testing"

// The antlr flavor marks its files with `_galop`, so they can sit next to
// the files ANTLR generates.
func TestANTLRFlavorOutputs(t *testing.T) {
	if ExprGalopParserFile != "expr_galop_parser.go" {
		t.Errorf("parser file: got %q", ExprGalopParserFile)
	}
	if ExprGalopLexerFile != "expr_galop_lexer.go" {
		t.Errorf("lexer file: got %q", ExprGalopLexerFile)
	}
}
