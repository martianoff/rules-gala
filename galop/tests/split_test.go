package split

import "testing"

// A lexer grammar and a parser grammar generate into one Go package, with the
// trailing Lexer/Parser trimmed from the file names.
func TestSplitGrammarOutputs(t *testing.T) {
	if CalcParserFile != "calc_parser.go" {
		t.Errorf("parser file: got %q", CalcParserFile)
	}
	if CalcLexerFile != "calc_lexer.go" {
		t.Errorf("lexer file: got %q", CalcLexerFile)
	}
}
