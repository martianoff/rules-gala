package calc

import "testing"

// The generated files compile into package `calc` (from `package = "calc"`)
// and are exactly the ones galop's naming promises.
func TestCombinedGrammarOutputs(t *testing.T) {
	if CalcGalopParser != "calc_galop_parser.go" {
		t.Errorf("parser file: got %q", CalcGalopParser)
	}
	if CalcGalopLexer != "calc_galop_lexer.go" {
		t.Errorf("lexer file: got %q", CalcGalopLexer)
	}
}
