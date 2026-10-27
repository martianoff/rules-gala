package calc

import "testing"

// The generated files compile into package `calc` (from `package = "calc"`)
// and are exactly the ones galop's naming promises for the native flavor.
func TestCombinedGrammarOutputs(t *testing.T) {
	if CalcParserFile != "calc_parser.go" {
		t.Errorf("parser file: got %q", CalcParserFile)
	}
	if CalcLexerFile != "calc_lexer.go" {
		t.Errorf("lexer file: got %q", CalcLexerFile)
	}
}
