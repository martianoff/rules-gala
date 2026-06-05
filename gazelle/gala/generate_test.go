package gala

import (
	"encoding/json"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/language"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// fakeImports maps a file name to the imports the fake helper should report.
var fakeImports = map[string]rawFile{
	"regex.gala": {
		File:    "regex.gala",
		Package: "regex",
		Imports: []rawImport{
			{Path: "regexp"},
			{Path: "martianoff/gala/std", Dot: true},
			{Path: "martianoff/gala/collection_immutable", Dot: true},
			{Path: "martianoff/gala/go_interop"},
		},
	},
	"regex_test.gala": {
		File:    "regex_test.gala",
		Package: "main",
		Imports: []rawImport{
			{Path: "martianoff/gala/test", Dot: true},
			{Path: "martianoff/gala/regex"},
		},
	},
	"math.gala": {File: "math.gala", Package: "mathlib"},
	"main.gala": {
		File:    "main.gala",
		Package: "main",
		Imports: []rawImport{{Path: "martianoff/gala/collection_immutable", Dot: true}},
	},
	"core.gala": {File: "core.gala", Package: "core"},
	"coll.gala": {File: "coll.gala", Package: "coll"},
	"perf_test.gala": {
		File:    "perf_test.gala",
		Package: "main",
		Imports: []rawImport{{Path: "martianoff/gala/collection_immutable", Dot: true}},
	},
	"alpha_test.gala": {
		File:    "alpha_test.gala",
		Package: "main",
		Imports: []rawImport{
			{Path: "martianoff/gala/test", Dot: true},
			{Path: "martianoff/gala/multitest"},
		},
	},
	"beta_test.gala": {
		File:    "beta_test.gala",
		Package: "main",
		Imports: []rawImport{
			{Path: "martianoff/gala/test", Dot: true},
			{Path: "martianoff/gala/collection_immutable", Dot: true},
		},
	},
	"lib.gala": {
		File:    "lib.gala",
		Package: "mixedgopkg",
		Imports: []rawImport{{Path: "martianoff/gala/collection_immutable", Dot: true}},
	},
	"mixed_internal_test.gala": {
		File:    "mixed_internal_test.gala",
		Package: "mixedgopkg",
		Imports: []rawImport{{Path: "martianoff/gala/test", Dot: true}},
	},
	"internal_lib.gala": {
		File:    "internal_lib.gala",
		Package: "internalpkg",
		Imports: []rawImport{{Path: "martianoff/gala/collection_immutable", Dot: true}},
	},
	"internal_lib_test.gala": {
		File:    "internal_lib_test.gala",
		Package: "internalpkg",
		Imports: []rawImport{{Path: "martianoff/gala/test", Dot: true}},
	},
	"internal_lib2_test.gala": {
		File:    "internal_lib2_test.gala",
		Package: "internalpkg",
		Imports: []rawImport{{Path: "martianoff/gala/test", Dot: true}},
	},
	"lib_test.gala": {
		File:    "lib_test.gala",
		Package: "main",
		Imports: []rawImport{
			{Path: "martianoff/gala/test", Dot: true},
			{Path: "martianoff/gala/mixedgopkg"},
		},
	},
}

// fakeRunner is an importRunner that emits the JSON contract for the requested
// files from fakeImports, so tests never touch a real "gala" binary.
func fakeRunner(helper, dir string, files []string) ([]byte, error) {
	out := make([]rawFile, 0, len(files))
	for _, f := range files {
		if rf, ok := fakeImports[f]; ok {
			out = append(out, rf)
		} else {
			out = append(out, rawFile{File: f})
		}
	}
	return json.Marshal(out)
}

func testConfig() *config.Config {
	c := config.New()
	c.Exts[languageName] = newGalaConfig()
	return c
}

func genArgs(c *config.Config, rel string, files []string) language.GenerateArgs {
	return language.GenerateArgs{
		Config:       c,
		Dir:          filepath.Join("testdata", rel),
		Rel:          rel,
		RegularFiles: files,
	}
}

func attrStrings(r *rule.Rule, key string) []string {
	v := r.AttrStrings(key)
	sort.Strings(v)
	return v
}

func TestGenerateLibraryAndTest(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "regexlike", []string{"regex.gala", "regex_test.gala"}))

	if len(res.Gen) != 2 {
		t.Fatalf("got %d rules, want 2 (library + test)", len(res.Gen))
	}
	lib := res.Gen[0]
	if lib.Kind() != "gala_library" || lib.Name() != "regexlike" {
		t.Errorf("rule0 = %s %q, want gala_library regexlike", lib.Kind(), lib.Name())
	}
	if got := lib.AttrString("importpath"); got != "martianoff/gala/regexlike" {
		t.Errorf("importpath = %q", got)
	}
	if got := attrStrings(lib, "srcs"); !reflect.DeepEqual(got, []string{"regex.gala"}) {
		t.Errorf("lib srcs = %v", got)
	}
	test := res.Gen[1]
	// One gala_test per file, named after the file stem.
	if test.Kind() != "gala_test" || test.Name() != "regex_test" {
		t.Errorf("rule1 = %s %q, want gala_test regex_test", test.Kind(), test.Name())
	}
	if got := attrStrings(test, "srcs"); !reflect.DeepEqual(got, []string{"regex_test.gala"}) {
		t.Errorf("test srcs = %v", got)
	}
}

func TestGenerateOneTestPerFile(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "multitest",
		[]string{"core.gala", "alpha_test.gala", "beta_test.gala"}))

	// Expect: 1 library + 2 separate per-file gala_test rules.
	if len(res.Gen) != 3 {
		t.Fatalf("got %d rules, want 3 (library + 2 per-file tests)", len(res.Gen))
	}
	if res.Gen[0].Kind() != "gala_library" {
		t.Errorf("rule0 = %s, want gala_library", res.Gen[0].Kind())
	}

	// Collect the test rules by name and check each carries only its own src
	// and its own import payload.
	tests := map[string]*rule.Rule{}
	payloads := map[string]*galaImports{}
	for i, r := range res.Gen {
		if r.Kind() == "gala_test" {
			tests[r.Name()] = r
			payloads[r.Name()] = res.Imports[i].(*galaImports)
		}
	}
	if len(tests) != 2 {
		t.Fatalf("got %d gala_test rules, want 2: %v", len(tests), keys(tests))
	}
	for name, wantSrc := range map[string]string{
		"alpha_test": "alpha_test.gala",
		"beta_test":  "beta_test.gala",
	} {
		r, ok := tests[name]
		if !ok {
			t.Errorf("missing per-file test rule %q", name)
			continue
		}
		if got := attrStrings(r, "srcs"); !reflect.DeepEqual(got, []string{wantSrc}) {
			t.Errorf("%s srcs = %v, want [%s]", name, got, wantSrc)
		}
	}

	// Per-file deps must not be unioned: alpha imports multitest, beta imports
	// collection_immutable — neither should see the other's import.
	if got := payloads["alpha_test"].imports; !contains(got, "martianoff/gala/multitest") || contains(got, "martianoff/gala/collection_immutable") {
		t.Errorf("alpha_test imports leaked across files: %v", got)
	}
	if got := payloads["beta_test"].imports; !contains(got, "martianoff/gala/collection_immutable") || contains(got, "martianoff/gala/multitest") {
		t.Errorf("beta_test imports leaked across files: %v", got)
	}
}

func TestGenerateSkipsBenchmarkMainTest(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "benchlike",
		[]string{"coll.gala", "perf_test.gala"}))

	// perf_test.gala is package main with main() — a benchmark binary, not a
	// framework test. It must NOT produce a gala_test (which would collide with
	// the hand-wired gala_binary). Only the library should be generated.
	if len(res.Gen) != 1 {
		t.Fatalf("got %d rules, want 1 (library only): %v", len(res.Gen), ruleKinds(res.Gen))
	}
	if res.Gen[0].Kind() != "gala_library" {
		t.Errorf("rule0 = %s, want gala_library", res.Gen[0].Kind())
	}
	for _, r := range res.Gen {
		if r.Kind() == "gala_test" {
			t.Errorf("unexpected gala_test %q generated for a benchmark main", r.Name())
		}
	}
}

func TestGenerateMixedGoPackage(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	// A package mixing .gala with an extra native.go (gala didn't generate it).
	// lib.gen.go is a transpiler output (excluded from go_srcs); lib_test.gala
	// is a framework test (still its own gala_test).
	res := gl.GenerateRules(genArgs(c, "mixedgopkg",
		[]string{"lib.gala", "native.go", "lib.gen.go", "lib_test.gala"}))

	var lib, test *rule.Rule
	var libImports []string
	for i, r := range res.Gen {
		switch r.Kind() {
		case "gala_library":
			lib = r
			libImports = res.Imports[i].(*galaImports).imports
		case "gala_test":
			test = r
		default:
			t.Errorf("unexpected %s %q", r.Kind(), r.Name())
		}
	}
	if lib == nil {
		t.Fatalf("no gala_library generated for mixed package: %v", ruleKinds(res.Gen))
	}
	// The .gala is compiled (not dropped) and the extra .go is folded in via
	// go_srcs — the transpiler output (.gen.go) is NOT.
	if got := attrStrings(lib, "srcs"); !reflect.DeepEqual(got, []string{"lib.gala"}) {
		t.Errorf("lib srcs = %v, want [lib.gala]", got)
	}
	if got := attrStrings(lib, "go_srcs"); !reflect.DeepEqual(got, []string{"native.go"}) {
		t.Errorf("lib go_srcs = %v, want [native.go]", got)
	}
	if lib.AttrString("importpath") != "martianoff/gala/mixedgopkg" {
		t.Errorf("importpath = %q", lib.AttrString("importpath"))
	}
	// The go_srcs' own imports join the dep payload (native.go imports go_interop).
	if !contains(libImports, "martianoff/gala/go_interop") {
		t.Errorf("lib imports missing native.go's go_interop dep: %v", libImports)
	}
	// The pure-GALA framework test is still its own rule.
	if test == nil || test.Name() != "lib_test" {
		t.Errorf("expected gala_test lib_test, got %v", ruleKinds(res.Gen))
	}
}

// Internal (white-box) tests — declaring the same package as the library — are
// bundled into ONE gala_test named "<dir>_test" with pkg + lib_srcs (so they
// share helpers across files) and inherit the library's imports.
func TestGenerateInternalTest(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "internalpkg",
		[]string{"internal_lib.gala", "internal_lib_test.gala", "internal_lib2_test.gala"}))

	var tests []*rule.Rule
	var testImps []string
	for i, r := range res.Gen {
		if r.Kind() == "gala_test" {
			tests = append(tests, r)
			testImps = res.Imports[i].(*galaImports).imports
		}
	}
	if len(tests) != 1 {
		t.Fatalf("want exactly 1 bundled internal gala_test, got %v", ruleKinds(res.Gen))
	}
	test := tests[0]
	if test.Name() != "internalpkg_test" {
		t.Errorf("name = %q, want internalpkg_test", test.Name())
	}
	if got := test.AttrString("pkg"); got != "internalpkg" {
		t.Errorf("pkg = %q, want internalpkg", got)
	}
	// Full importpath (not just pkg) so a stdlib-named package wouldn't self-collide.
	if got := test.AttrString("importpath"); got != "martianoff/gala/internalpkg" {
		t.Errorf("importpath = %q, want martianoff/gala/internalpkg", got)
	}
	// Both internal test files are bundled (so cross-file helpers resolve).
	if got := attrStrings(test, "srcs"); !reflect.DeepEqual(got, []string{"internal_lib2_test.gala", "internal_lib_test.gala"}) {
		t.Errorf("srcs = %v, want both internal test files", got)
	}
	if got := attrStrings(test, "lib_srcs"); !reflect.DeepEqual(got, []string{"internal_lib.gala"}) {
		t.Errorf("lib_srcs = %v, want [internal_lib.gala]", got)
	}
	// The lib's imports (collection_immutable) are inherited because lib_srcs
	// are compiled into the test.
	if !contains(testImps, "martianoff/gala/collection_immutable") {
		t.Errorf("internal test should inherit lib imports: %v", testImps)
	}
}

// A standalone test (package main) keeps the plain form — no pkg/lib_srcs.
func TestGenerateStandaloneTestNoPkg(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "regexlike", []string{"regex.gala", "regex_test.gala"}))
	for _, r := range res.Gen {
		if r.Kind() == "gala_test" {
			if r.AttrString("pkg") != "" {
				t.Errorf("standalone test got pkg=%q, want none", r.AttrString("pkg"))
			}
			if len(attrStrings(r, "lib_srcs")) != 0 {
				t.Errorf("standalone test got lib_srcs, want none")
			}
		}
	}
}

// An internal test of a MIXED package gets lib_go_srcs (the library's .go) so
// the test can reach symbols defined there, and the .go imports join its deps.
func TestGenerateMixedInternalTest(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "mixedgopkg",
		[]string{"lib.gala", "native.go", "lib.gen.go", "mixed_internal_test.gala"}))

	var test *rule.Rule
	var imps []string
	for i, r := range res.Gen {
		if r.Kind() == "gala_test" {
			test = r
			imps = res.Imports[i].(*galaImports).imports
		}
	}
	if test == nil {
		t.Fatalf("no gala_test generated: %v", ruleKinds(res.Gen))
	}
	if got := test.AttrString("pkg"); got != "mixedgopkg" {
		t.Errorf("pkg = %q", got)
	}
	if got := attrStrings(test, "lib_srcs"); !reflect.DeepEqual(got, []string{"lib.gala"}) {
		t.Errorf("lib_srcs = %v, want [lib.gala]", got)
	}
	if got := attrStrings(test, "lib_go_srcs"); !reflect.DeepEqual(got, []string{"native.go"}) {
		t.Errorf("lib_go_srcs = %v, want [native.go]", got)
	}
	// native.go imports go_interop → joins the test deps.
	if !contains(imps, "martianoff/gala/go_interop") {
		t.Errorf("mixed internal test should inherit native.go imports: %v", imps)
	}
}

// `# gazelle:gala_generation off` must suppress all rule generation for the
// directory, so gazelle leaves any hand-authored GALA rules untouched.
func TestGenerateDisabledByDirective(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	getGalaConfig(c).Generate = false
	res := gl.GenerateRules(genArgs(c, "regexlike", []string{"regex.gala", "regex_test.gala"}))
	if len(res.Gen) != 0 {
		t.Fatalf("gala_generation off should emit no rules, got %v", ruleKinds(res.Gen))
	}
}

// generationEnabled treats the documented falsey spellings as "off" and every
// other value (including empty / unknown) as "on".
func TestGenerationEnabled(t *testing.T) {
	for _, off := range []string{"off", "OFF", "Disabled", "false", "none", "0", "no"} {
		if generationEnabled(off) {
			t.Errorf("generationEnabled(%q) = true, want false", off)
		}
	}
	for _, on := range []string{"", "auto", "on", "true", "anything"} {
		if !generationEnabled(on) {
			t.Errorf("generationEnabled(%q) = false, want true", on)
		}
	}
}

// extraGoSrcs returns the Go sources gala didn't generate (not .gen.go outputs,
// not _test.go) that belong in a gala_library's go_srcs.
func TestExtraGoSrcs(t *testing.T) {
	cases := []struct {
		name  string
		files []string
		want  []string
	}{
		{"only gala", []string{"a.gala", "b.gala"}, nil},
		{"gen go only", []string{"a.gala", "a.gen.go"}, nil},
		{"extra go", []string{"a.gala", "native.go"}, []string{"native.go"}},
		{"excludes go tests", []string{"a.gala", "native.go", "native_test.go"}, []string{"native.go"}},
		{"sorted", []string{"z.go", "a.go"}, []string{"a.go", "z.go"}},
	}
	for _, tc := range cases {
		got := extraGoSrcs(tc.files)
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: extraGoSrcs(%v) = %v, want %v", tc.name, tc.files, got, tc.want)
		}
	}
}

func ruleKinds(rules []*rule.Rule) []string {
	out := make([]string, len(rules))
	for i, r := range rules {
		out[i] = r.Kind() + ":" + r.Name()
	}
	return out
}

func keys(m map[string]*rule.Rule) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func contains(xs []string, v string) bool {
	for _, x := range xs {
		if x == v {
			return true
		}
	}
	return false
}

func TestGenerateLibraryNoImports(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "mathlike", []string{"math.gala"}))
	if len(res.Gen) != 1 {
		t.Fatalf("got %d rules, want 1", len(res.Gen))
	}
	r := res.Gen[0]
	if r.Kind() != "gala_library" || r.AttrString("importpath") != "martianoff/gala/mathlike" {
		t.Errorf("got %s importpath=%q", r.Kind(), r.AttrString("importpath"))
	}
}

func TestGenerateBinary(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "binlike", []string{"main.gala"}))
	if len(res.Gen) != 1 {
		t.Fatalf("got %d rules, want 1", len(res.Gen))
	}
	r := res.Gen[0]
	if r.Kind() != "gala_binary" || r.Name() != "binlike" {
		t.Errorf("got %s %q, want gala_binary binlike", r.Kind(), r.Name())
	}
	if r.AttrString("importpath") != "" {
		t.Errorf("binary should not have importpath, got %q", r.AttrString("importpath"))
	}
}

func TestGeneratePrefixDirective(t *testing.T) {
	gl := &galaLang{runner: fakeRunner}
	c := testConfig()
	getGalaConfig(c).Prefix = "github.com/me/app"
	res := gl.GenerateRules(genArgs(c, "mathlike", []string{"math.gala"}))
	if got := res.Gen[0].AttrString("importpath"); got != "github.com/me/app/mathlike" {
		t.Errorf("importpath = %q, want github.com/me/app/mathlike", got)
	}
}
