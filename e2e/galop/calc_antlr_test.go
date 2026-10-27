package calc_antlr_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The antlr flavor writes calc_galop_parser.go and calc_galop_lexer.go in
// package calc, building on ANTLR's runtime and ANTLR's generated CalcParser.
func TestGenerated(t *testing.T) {
	want := map[string]string{
		"calc_galop_parser.go": "type CalcGalopParser struct",
		"calc_galop_lexer.go":  "type CalcGalopLexer struct",
	}
	files := strings.Fields(os.Getenv("CALC_ANTLR_FILES"))
	if len(files) != len(want) {
		t.Fatalf("got files %v, want %d", files, len(want))
	}
	for _, f := range files {
		src, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		s := string(src)
		decl, ok := want[filepath.Base(f)]
		if !ok {
			t.Errorf("unexpected file %s", f)
			continue
		}
		for _, needle := range []string{"package calc\n", `"github.com/antlr4-go/antlr/v4"`, decl} {
			if !strings.Contains(s, needle) {
				t.Errorf("%s: missing %q", filepath.Base(f), needle)
			}
		}
	}
}
