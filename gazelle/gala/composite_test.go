package gala

import (
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// A go_library imported across packages must still resolve under the composite,
// even though gazelle indexes every rule under this extension's single language
// name ("gala") while gazelle-go's resolver queries the index as "go".
// CrossResolve bridges that gap; without it, in-repo Go deps are silently
// dropped (observed as stripped //internal/... deps across a pure-Go tree).
func TestCompositeCrossResolveGo(t *testing.T) {
	cl := NewLanguage().(*compositeLang)
	c := config.New()

	// Index a go_library the way gazelle does: the sole registered language is
	// the composite, so the record's language is the composite's Name ("gala").
	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return cl })
	lib := rule.NewRule("go_library", "build")
	lib.SetAttr("importpath", "martianoff/gala/internal/build")
	f := rule.EmptyFile("internal/build/BUILD.bazel", "internal/build")
	lib.Insert(f)
	ix.AddRule(c, lib, f)
	ix.Finish()

	spec := resolve.ImportSpec{Lang: goName, Imp: "martianoff/gala/internal/build"}

	// The underlying mismatch: a plain "go" lookup misses because the record is
	// tagged with the composite's name, not "go".
	if got := ix.FindRulesByImport(spec, goName); len(got) != 0 {
		t.Fatalf("baseline FindRulesByImport(go) = %v, want empty (record tagged %q)", got, cl.Name())
	}

	// The fix: CrossResolve re-queries under the composite's name and finds it.
	got := cl.CrossResolve(c, ix, spec, goName)
	if len(got) != 1 || got[0].Label.Pkg != "internal/build" {
		t.Fatalf("CrossResolve(go) = %v, want //internal/build:build", got)
	}

	// Non-go imports are not bridged here — GALA has its own resolution path.
	if got := cl.CrossResolve(c, ix, resolve.ImportSpec{Lang: languageName, Imp: "x"}, languageName); got != nil {
		t.Fatalf("CrossResolve(gala) = %v, want nil", got)
	}
}
