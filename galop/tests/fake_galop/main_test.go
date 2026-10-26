package main

import (
	"os"
	"path/filepath"
	"testing"
)

// An unknown flavor is galop's error 508, reported before any file is written.
func TestUnknownFlavor(t *testing.T) {
	dir := t.TempDir()
	grammar := filepath.Join(dir, "Calc.g4")
	if err := os.WriteFile(grammar, []byte("grammar Calc;\ns : ID ;\nID : [a-z]+ ;\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(dir, "out")
	if err := os.Mkdir(out, 0o755); err != nil {
		t.Fatal(err)
	}

	err := run([]string{"-o", out, "-Xexact-output-dir", "-Dlanguage=Go", "-Dflavor=companion", grammar})
	want := "error(508):  unknown Go flavor companion (supported: native, antlr)"
	if err == nil || err.Error() != want {
		t.Fatalf("got %v, want %q", err, want)
	}
	if entries, _ := os.ReadDir(out); len(entries) != 0 {
		t.Errorf("wrote %d files, want none", len(entries))
	}
}

// Without -Dflavor the native flavor is generated.
func TestDefaultFlavorIsNative(t *testing.T) {
	dir := t.TempDir()
	grammar := filepath.Join(dir, "Calc.g4")
	if err := os.WriteFile(grammar, []byte("grammar Calc;\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"-o", dir, "-Xexact-output-dir", "-Dlanguage=Go", grammar}); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"calc_parser.go", "calc_lexer.go"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Errorf("%s: %v", f, err)
		}
	}
}
