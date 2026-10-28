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

// The antlr flavor with -DnativePackage also writes the converter to the
// native tree, for a grammar with parser rules; galop rejects the define with
// the native flavor, or blank, and writes nothing.
func TestNativePackage(t *testing.T) {
	dir := t.TempDir()
	grammar := filepath.Join(dir, "Calc.g4")
	if err := os.WriteFile(grammar, []byte("grammar Calc;\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	base := []string{"-Xexact-output-dir", "-Dlanguage=Go"}
	run1 := func(out string, opts ...string) error {
		if err := os.MkdirAll(out, 0o755); err != nil {
			t.Fatal(err)
		}
		return run(append(append(append([]string{"-o", out}, base...), opts...), grammar))
	}

	out := filepath.Join(dir, "antlr")
	if err := run1(out, "-Dflavor=antlr", "-DnativePackage=example.com/calc/native"); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"calc_galop_parser.go", "calc_galop_native.go", "calc_galop_lexer.go"} {
		if _, err := os.Stat(filepath.Join(out, f)); err != nil {
			t.Errorf("%s: %v", f, err)
		}
	}

	for _, c := range []struct{ name, flavor, value, want string }{
		{"native", "native", "example.com/calc/native", "error(505):  Go code generation failed: nativePackage=example.com/calc/native needs flavor=antlr: it adds a converter to the antlr flavor's output"},
		{"blank", "antlr", "  ", "error(505):  Go code generation failed: nativePackage must name the native flavor's Go package, not be empty"},
	} {
		out := filepath.Join(dir, c.name)
		err := run1(out, "-Dflavor="+c.flavor, "-DnativePackage="+c.value)
		if err == nil || err.Error() != c.want {
			t.Errorf("%s: got %v, want %q", c.name, err, c.want)
		}
		if entries, _ := os.ReadDir(out); len(entries) != 0 {
			t.Errorf("%s: wrote %d files, want none", c.name, len(entries))
		}
	}
}
