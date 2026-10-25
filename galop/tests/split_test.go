package split

import "testing"

// A lexer grammar and a parser grammar generate into one Go package, with the
// trailing Lexer/Parser trimmed from the file names.
func TestSplitGrammarOutputs(t *testing.T) {
	if CalcParserGalopParser != "calc_galop_parser.go" {
		t.Errorf("parser file: got %q", CalcParserGalopParser)
	}
	if CalcLexerGalopLexer != "calc_galop_lexer.go" {
		t.Errorf("lexer file: got %q", CalcLexerGalopLexer)
	}
}
