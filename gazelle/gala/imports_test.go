package gala

import (
	"path/filepath"
	"reflect"
	"testing"
)

func TestParseImports(t *testing.T) {
	data := []byte(`[
		{"file":"a.gala","package":"main","imports":[{"path":"fmt","alias":"","dot":false},{"path":"martianoff/gala/collection_immutable","alias":"","dot":true}],"error":""},
		{"file":"broken.gala","package":"","imports":[],"error":"parse error at line 3"}
	]`)
	got, err := parseImports(data)
	if err != nil {
		t.Fatalf("parseImports: %v", err)
	}
	if _, ok := got["broken.gala"]; ok {
		t.Errorf("file with error should be skipped, but was present")
	}
	a, ok := got["a.gala"]
	if !ok {
		t.Fatalf("a.gala missing from result")
	}
	if a.Package != "main" {
		t.Errorf("package = %q, want main", a.Package)
	}
	want := []string{"fmt", "martianoff/gala/collection_immutable"}
	if !reflect.DeepEqual(a.Imports, want) {
		t.Errorf("imports = %v, want %v", a.Imports, want)
	}
}

func TestParseImportsInvalidJSON(t *testing.T) {
	if _, err := parseImports([]byte("not json")); err == nil {
		t.Errorf("expected error for invalid JSON, got nil")
	}
}

func TestResolveHelper(t *testing.T) {
	// A bare command name is left for PATH lookup, with or without a
	// workspace root set.
	t.Setenv("BUILD_WORKSPACE_DIRECTORY", "/work/root")
	if got := resolveHelper("gala"); got != "gala" {
		t.Errorf("bare name = %q, want gala", got)
	}
	// A relative path (a Bazel $(execpath)) is anchored at the workspace root.
	rel := filepath.Join("bazel-out", "bin", "cmd", "gala", "gala")
	if got, want := resolveHelper(rel), filepath.Join("/work/root", rel); got != want {
		t.Errorf("relative = %q, want %q", got, want)
	}
	// An absolute path is used verbatim (filepath.Abs yields a
	// platform-correct absolute path, incl. a drive letter on Windows).
	abs, err := filepath.Abs(filepath.Join("opt", "gala"))
	if err != nil {
		t.Fatalf("filepath.Abs: %v", err)
	}
	if got := resolveHelper(abs); got != abs {
		t.Errorf("absolute = %q, want %q", got, abs)
	}
	// Without a workspace root, a relative path is returned unchanged.
	t.Setenv("BUILD_WORKSPACE_DIRECTORY", "")
	if got := resolveHelper(rel); got != rel {
		t.Errorf("relative without workspace = %q, want %q", got, rel)
	}
}
