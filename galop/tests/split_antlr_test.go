package splitantlr

import "testing"

// The antlr flavor trims a trailing Lexer/Parser the same way and adds
// `_galop` to the file names.
func TestSplitGrammarANTLROutputs(t *testing.T) {
	if CalcGalopParserFile != "calc_galop_parser.go" {
		t.Errorf("parser file: got %q", CalcGalopParserFile)
	}
	if CalcGalopLexerFile != "calc_galop_lexer.go" {
		t.Errorf("lexer file: got %q", CalcGalopLexerFile)
	}
}
