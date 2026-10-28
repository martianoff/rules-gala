package exprconverter

import "testing"

// With the nativePackage define, the antlr flavor also writes the converter
// to the native tree, which galop_parser declares and compiles.
func TestConverterOutput(t *testing.T) {
	if ExprGalopNativeFile != "expr_galop_native.go" {
		t.Errorf("converter file: got %q", ExprGalopNativeFile)
	}
	if ExprGalopParserFile != "expr_galop_parser.go" || ExprGalopLexerFile != "expr_galop_lexer.go" {
		t.Errorf("parser and lexer files: got %q, %q", ExprGalopParserFile, ExprGalopLexerFile)
	}
}
