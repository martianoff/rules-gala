package gala

import (
	"reflect"
	"sort"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// lib describes one gala_library in the rule index.
type lib struct {
	pkg        string
	importpath string
	// generated marks a rule produced by GenerateRules this run: imports holds
	// its raw import paths. Otherwise the rule is one read from an existing
	// BUILD file whose directory is not being updated, described by deps and
	// galaDeps.
	generated bool
	imports   []string
	deps      []string
	galaDeps  []string
	// visibility defaults to public.
	visibility []string
}

// indexGraph indexes libs the way gazelle does, which also fills gl's graph.
func indexGraph(c *config.Config, gl *galaLang, libs []lib) *resolve.RuleIndex {
	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return gl })
	for _, l := range libs {
		r := rule.NewRule("gala_library", l.pkg[lastSlash(l.pkg)+1:])
		r.SetAttr("importpath", l.importpath)
		vis := l.visibility
		if vis == nil {
			vis = []string{"//visibility:public"}
		}
		r.SetAttr("visibility", vis)
		if l.generated {
			r.SetPrivateAttr(galaImportsKey, &galaImports{imports: l.imports, self: l.importpath})
		} else {
			if len(l.deps) > 0 {
				r.SetAttr("deps", l.deps)
			}
			if len(l.galaDeps) > 0 {
				r.SetAttr("gala_deps", l.galaDeps)
			}
		}
		f := rule.EmptyFile(l.pkg+"/BUILD.bazel", l.pkg)
		r.Insert(f)
		ix.AddRule(c, r, f)
	}
	ix.Finish()
	return ix
}

// gen is shorthand for a library generated this run.
func gen(pkg string, imports ...string) lib {
	return lib{pkg: pkg, importpath: "martianoff/gala/" + pkg, generated: true, imports: imports}
}

// imp is the in-repo import path of pkg under the default prefix.
func imp(pkg string) string { return "martianoff/gala/" + pkg }

func TestResolveTransitiveGalaDeps(t *testing.T) {
	tests := []struct {
		name string
		// prefix overrides the default gala_prefix when set.
		prefix string
		// resolveDirective is an optional `# gazelle:resolve` value.
		resolveDirective string
		libs             []lib
		// The rule being resolved.
		kind         string
		pkg          string
		importpath   string
		imports      []string
		self         string
		wantDeps     []string
		wantGalaDeps []string
	}{
		{
			name:     "chain: c gets a through b",
			libs:     []lib{gen("a"), gen("b", imp("a"))},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{imp("b")},
			self:     imp("c"),
			wantDeps: []string{"//a", "//b"},
		},
		{
			name:     "long chain is followed to the end",
			libs:     []lib{gen("a"), gen("b", imp("a")), gen("e", imp("b"))},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{imp("e")},
			self:     imp("c"),
			wantDeps: []string{"//a", "//b", "//e"},
		},
		{
			name:     "diamond adds the shared dep once",
			libs:     []lib{gen("a"), gen("b", imp("a")), gen("d", imp("a"))},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{imp("b"), imp("d")},
			self:     imp("c"),
			wantDeps: []string{"//a", "//b", "//d"},
		},
		{
			name:     "cycle terminates and never adds the rule itself",
			libs:     []lib{gen("a", imp("b")), gen("b", imp("a"))},
			kind:     "gala_library",
			pkg:      "a",
			imports:  []string{imp("b")},
			self:     imp("a"),
			wantDeps: []string{"//b"},
		},
		{
			name:     "consumer of a cycle gets both members",
			libs:     []lib{gen("a", imp("b")), gen("b", imp("a"))},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{imp("a")},
			self:     imp("c"),
			wantDeps: []string{"//a", "//b"},
		},
		{
			name: "plain Go deps of a GALA dep are not propagated",
			libs: []lib{
				gen("a"),
				// A mixed package: its go_srcs import Go stdlib, a third-party
				// module and an in-repo Go package (not a gala_library).
				gen("b", imp("a"), "fmt", "github.com/google/uuid", imp("gohelper")),
			},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{imp("b")},
			self:     imp("c"),
			wantDeps: []string{"//a", "//b"},
		},
		{
			name: "macro-injected std is neither added nor walked",
			libs: []lib{
				gen("go_interop"),
				gen("std", imp("go_interop")),
				gen("a", imp("std")),
				gen("b", imp("a"), imp("std")),
			},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{imp("b"), imp("std")},
			self:     imp("c"),
			wantDeps: []string{"//a", "//b"},
		},
		{
			name: "tests get transitive deps too",
			libs: []lib{gen("a"), gen("b", imp("a"))},
			kind: "gala_test",
			pkg:  "c",
			// A standalone test importing b.
			imports:  []string{imp("test"), imp("b")},
			wantDeps: []string{"//a", "//b"},
		},
		{
			name:     "standalone test next to its library",
			libs:     []lib{gen("a"), gen("b", imp("a"))},
			kind:     "gala_test",
			pkg:      "b",
			imports:  []string{imp("b")},
			wantDeps: []string{":b", "//a"},
		},
		{
			name: "internal test never depends on its own package",
			libs: []lib{
				gen("b", imp("a")),
				// A rule left over in an existing BUILD file that points back
				// at b; the internal test compiles b's sources itself.
				{pkg: "a", importpath: imp("a"), deps: []string{"//b"}},
			},
			kind:       "gala_test",
			pkg:        "b",
			importpath: imp("b"),
			imports:    []string{imp("a")},
			wantDeps:   []string{"//a"},
		},
		{
			name: "partial run: deps of a library not regenerated are read from its BUILD rule",
			libs: []lib{
				{pkg: "a", importpath: imp("a")},
				// b's directory is not being updated: only its existing deps
				// are known. The Go dep is not propagated.
				{pkg: "b", importpath: imp("b"), deps: []string{"//a", "@com_github_google_uuid//:uuid"}},
			},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{imp("b")},
			self:     imp("c"),
			wantDeps: []string{"//a", "//b"},
		},
		{
			name:   "partial run: external stdlib deps are carried over, but not walked",
			prefix: "github.com/me/app",
			libs: []lib{
				{
					pkg:        "b",
					importpath: "github.com/me/app/b",
					deps:       []string{"@gala//collection_immutable", "@gala//std", "//a"},
				},
				{pkg: "a", importpath: "github.com/me/app/a", deps: []string{":local_go"}},
			},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{"github.com/me/app/b"},
			self:     "github.com/me/app/c",
			wantDeps: []string{"//a", "//b", "@gala//collection_immutable"},
		},
		{
			name:   "external stdlib import of a generated dep is added",
			prefix: "github.com/me/app",
			libs: []lib{
				{
					pkg: "b", importpath: "github.com/me/app/b", generated: true,
					imports: []string{"martianoff/gala/collection_immutable", "martianoff/gala/std"},
				},
			},
			kind:     "gala_library",
			pkg:      "c",
			imports:  []string{"github.com/me/app/b"},
			self:     "github.com/me/app/c",
			wantDeps: []string{"//b", "@gala//collection_immutable"},
		},
		{
			name:             "a resolve override reached transitively goes to gala_deps",
			resolveDirective: "gala github.com/other/ext @ext//:ext",
			libs:             []lib{gen("b", "github.com/other/ext")},
			kind:             "gala_library",
			pkg:              "c",
			imports:          []string{imp("b")},
			self:             imp("c"),
			wantDeps:         []string{"//b"},
			wantGalaDeps:     []string{"@ext//:ext"},
		},
		{
			name: "gala_deps of a library not regenerated are carried over",
			libs: []lib{
				{pkg: "b", importpath: imp("b"), galaDeps: []string{"@ext//:ext"}},
			},
			kind:         "gala_library",
			pkg:          "c",
			imports:      []string{imp("b")},
			self:         imp("c"),
			wantDeps:     []string{"//b"},
			wantGalaDeps: []string{"@ext//:ext"},
		},
		{
			name: "internal package is added only where visible",
			libs: []lib{
				{
					pkg: "lib/internal/detail", importpath: imp("lib/internal/detail"), generated: true,
					visibility: []string{"//lib:__subpackages__"},
				},
				gen("lib/api", imp("lib/internal/detail")),
			},
			kind:     "gala_library",
			pkg:      "app",
			imports:  []string{imp("lib/api")},
			self:     imp("app"),
			wantDeps: []string{"//lib/api"},
		},
		{
			name: "internal package is added inside its tree",
			libs: []lib{
				{
					pkg: "lib/internal/detail", importpath: imp("lib/internal/detail"), generated: true,
					visibility: []string{"//lib:__subpackages__"},
				},
				gen("lib/api", imp("lib/internal/detail")),
			},
			kind:     "gala_library",
			pkg:      "lib/other",
			imports:  []string{imp("lib/api")},
			self:     imp("lib/other"),
			wantDeps: []string{"//lib/api", "//lib/internal/detail"},
		},
		{
			name: "deps behind an invisible library are still followed",
			libs: []lib{
				gen("a"),
				{
					pkg: "lib/internal/detail", importpath: imp("lib/internal/detail"), generated: true,
					imports: []string{imp("a")}, visibility: []string{"//lib:__subpackages__"},
				},
				gen("lib/api", imp("lib/internal/detail")),
			},
			kind:     "gala_library",
			pkg:      "app",
			imports:  []string{imp("lib/api")},
			self:     imp("app"),
			wantDeps: []string{"//a", "//lib/api"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gl := &galaLang{runner: fakeRunner, graph: newDepGraph()}
			c := testConfig()
			if tt.prefix != "" {
				getGalaConfig(c).Prefix = tt.prefix
			}
			if tt.resolveDirective != "" {
				f, err := rule.LoadData("BUILD.bazel", "", []byte("# gazelle:resolve "+tt.resolveDirective+"\n"))
				if err != nil {
					t.Fatal(err)
				}
				(&resolve.Configurer{}).Configure(c, "", f)
			}
			ix := indexGraph(c, gl, tt.libs)

			r := rule.NewRule(tt.kind, "target")
			if tt.importpath != "" {
				r.SetAttr("importpath", tt.importpath)
			}
			from := label.New("", tt.pkg, "target")
			gl.Resolve(c, ix, nil, r, &galaImports{imports: tt.imports, self: tt.self}, from)

			if got := sorted(r.AttrStrings("deps")); !reflect.DeepEqual(got, sorted(tt.wantDeps)) {
				t.Errorf("deps = %v, want %v", got, tt.wantDeps)
			}
			if got := sorted(r.AttrStrings("gala_deps")); !reflect.DeepEqual(got, sorted(tt.wantGalaDeps)) {
				t.Errorf("gala_deps = %v, want %v", got, tt.wantGalaDeps)
			}
		})
	}
}

// sorted returns a sorted copy, with nil for an empty input so a missing attr
// compares equal to an empty want.
func sorted(s []string) []string {
	if len(s) == 0 {
		return nil
	}
	out := append([]string(nil), s...)
	sort.Strings(out)
	return out
}

func TestCanSee(t *testing.T) {
	tests := []struct {
		name    string
		vis     []string
		nodePkg string
		fromPkg string
		want    bool
	}{
		{"public", []string{"//visibility:public"}, "a", "b", true},
		{"internal, inside its tree", []string{"//lib:__subpackages__"}, "lib/internal/x", "lib/y", true},
		{"internal, the tree root itself", []string{"//lib:__subpackages__"}, "lib/internal/x", "lib", true},
		{"internal, sibling prefix", []string{"//lib:__subpackages__"}, "lib/internal/x", "library", false},
		{"internal, outside its tree", []string{"//lib:__subpackages__"}, "lib/internal/x", "app", false},
		{"repo-root internal", []string{"//:__subpackages__"}, "internal/x", "anything", true},
		{"subpackages not matching the internal rule", []string{"//lib:__subpackages__"}, "lib/x", "lib/y", false},
		{"private is not recognised", []string{"//visibility:private"}, "a", "a", false},
		{"package group is not recognised", []string{"//groups:friends"}, "a", "b", false},
		{"no visibility", nil, "a", "b", false},
		{"several entries are not recognised", []string{"//visibility:public", "//a:__pkg__"}, "a", "b", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			n := &depNode{label: label.New("", tt.nodePkg, "x"), visibility: tt.vis}
			if got := n.canSee(tt.fromPkg); got != tt.want {
				t.Errorf("canSee(%v in %q from %q) = %v, want %v", tt.vis, tt.nodePkg, tt.fromPkg, got, tt.want)
			}
		})
	}
}

func TestRuleVisibilityFallsBackToPackageDefault(t *testing.T) {
	f, err := rule.LoadData("a/BUILD.bazel", "a", []byte(`
package(default_visibility = ["//a:__subpackages__"])

gala_library(name = "a", importpath = "martianoff/gala/a")
`))
	if err != nil {
		t.Fatal(err)
	}
	var lib *rule.Rule
	for _, r := range f.Rules {
		if r.Kind() == "gala_library" {
			lib = r
		}
	}
	if got, want := ruleVisibility(lib, f), []string{"//a:__subpackages__"}; !reflect.DeepEqual(got, want) {
		t.Errorf("ruleVisibility = %v, want %v", got, want)
	}

	bare := rule.EmptyFile("b/BUILD.bazel", "b")
	r := rule.NewRule("gala_library", "b")
	r.Insert(bare)
	if got := ruleVisibility(r, bare); got != nil {
		t.Errorf("ruleVisibility = %v, want nil", got)
	}
}

func TestGeneratedLibraryCarriesImports(t *testing.T) {
	gl := &galaLang{runner: fakeRunner, graph: newDepGraph()}
	c := testConfig()
	res := gl.GenerateRules(genArgs(c, "regexlike", []string{"regex.gala"}))
	if len(res.Gen) == 0 || res.Gen[0].Kind() != "gala_library" {
		t.Fatalf("expected a gala_library, got %v", res.Gen)
	}
	gi, ok := res.Gen[0].PrivateAttr(galaImportsKey).(*galaImports)
	if !ok || gi != res.Imports[0] {
		t.Errorf("gala_library private attr %q = %v, want the rule's import payload", galaImportsKey, res.Gen[0].PrivateAttr(galaImportsKey))
	}
}
