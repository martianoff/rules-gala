package gala

import (
	"path"
	"sort"
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	golang "github.com/bazelbuild/bazel-gazelle/language/go"
	"github.com/bazelbuild/bazel-gazelle/repo"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// goLangExtKey is the config.Exts key gazelle-go stores its config under. We
// only delegate to gazelle-go's resolver when that config is present, i.e. when
// the composite (NewLanguage) wired the Go half in — never for standalone GALA.
const goLangExtKey = "go"

// Imports implements resolve.Resolver. A gala_library is indexed by its
// importpath so other rules can resolve imports to it. gala_binary and
// gala_test are not importable, so they are not indexed (return nil).
//
// It also records the library's own dependencies, which Resolve walks to add
// transitive GALA deps.
func (gl *galaLang) Imports(c *config.Config, r *rule.Rule, f *rule.File) []resolve.ImportSpec {
	if r.Kind() != "gala_library" {
		return nil
	}
	importpath := r.AttrString("importpath")
	if importpath == "" {
		return nil
	}
	gl.graph.record(c, r, f, importpath)
	return []resolve.ImportSpec{{Lang: languageName, Imp: importpath}}
}

// Embeds implements resolve.Resolver. GALA rules do not embed one another.
func (*galaLang) Embeds(r *rule.Rule, from label.Label) []label.Label { return nil }

// Resolve implements resolve.Resolver. It translates each GALA import path in
// the rule's payload into a Bazel label and writes the sorted set to "deps",
// then adds the GALA libraries those deps transitively depend on.
func (gl *galaLang) Resolve(
	c *config.Config,
	ix *resolve.RuleIndex,
	rc *repo.RemoteCache,
	r *rule.Rule,
	imports interface{},
	from label.Label,
) {
	gi, ok := imports.(*galaImports)
	if !ok || gi == nil {
		return
	}
	gc := getGalaConfig(c)

	deps := map[string]bool{}
	galaDeps := map[string]bool{}
	var roots []string
	for _, imp := range gi.imports {
		if imp == gi.self {
			continue
		}
		if gc.ImplicitDeps[imp] {
			// Injected automatically by the gala_* macros (std, test).
			continue
		}
		roots = append(roots, imp)
		switch lbl, kind := classifyImport(c, gc, ix, imp, from); kind {
		case depOverride:
			galaDeps[lbl] = true
		case depIndexed, depInRepo, depStdlib:
			deps[lbl] = true
		default:
			// Not a GALA import. In a mixed package the go_srcs reference Go
			// stdlib / in-repo Go / third-party Go; defer to gazelle-go's
			// resolver (available only in composite mode). Go stdlib resolves
			// to no dep; everything else to its label.
			if l, gok := resolveGoImport(c, ix, rc, imp, from); gok {
				deps[l] = true
			}
		}
	}

	// Add the GALA deps' own GALA deps, transitively (README.md "Transitive
	// GALA deps"). Plain Go deps are not propagated. The rule's own package is
	// never its own dep: a library's importpath, or the package an internal
	// test compiles in via lib_srcs.
	exclude := map[string]bool{gi.self: true, r.AttrString("importpath"): true}
	for _, root := range roots {
		cl := gl.graph.reachable(root)
		for _, l := range cl.galaLeaves {
			galaDeps[l.Rel(from.Repo, from.Pkg).String()] = true
		}
		for _, imp := range cl.imports {
			if exclude[imp] || gc.ImplicitDeps[imp] {
				continue
			}
			switch lbl, kind := classifyImport(c, gc, ix, imp, from); kind {
			case depOverride:
				galaDeps[lbl] = true
			case depIndexed:
				if n := gl.graph.nodes[imp]; n != nil && n.canSee(from.Pkg) {
					deps[lbl] = true
				}
			case depStdlib:
				deps[lbl] = true
			}
			// depInRepo (unindexed) is skipped: it can't be told apart from an
			// in-repo Go package.
		}
	}

	setSortedAttr(r, "deps", deps)
	setSortedAttr(r, "gala_deps", galaDeps)
}

// setSortedAttr writes the sorted keys of set to the named attr, or deletes the
// attr when the set is empty.
func setSortedAttr(r *rule.Rule, attr string, set map[string]bool) {
	if len(set) == 0 {
		r.DelAttr(attr)
		return
	}
	sorted := make([]string, 0, len(set))
	for d := range set {
		sorted = append(sorted, d)
	}
	sort.Strings(sorted)
	r.SetAttr(attr, sorted)
}

// depKind says how classifyImport resolved an import path.
type depKind int

const (
	// depNone: not a GALA import (Go stdlib, other Go paths).
	depNone depKind = iota
	// depOverride: an explicit `# gazelle:resolve gala <imp> <label>`. It
	// names a GALA library the transpiler can't find on its search path — a
	// library from ANOTHER Bazel module — so it goes in gala_deps, which puts
	// its sources on the search path, not just in deps.
	depOverride
	// depIndexed: an in-repo gala_library indexed under this importpath.
	depIndexed
	// depInRepo: under the in-repo prefix but not indexed → //<relpath>.
	depInRepo
	// depStdlib: GALA stdlib namespace not present in-repo → @<repo>//<relpath>.
	depStdlib
)

// classifyImport maps a GALA import path to a Bazel label string (relative to
// from) and says what kind of dep it is. Lookup order: override, index,
// in-repo prefix, stdlib namespace.
func classifyImport(c *config.Config, gc *galaConfig, ix *resolve.RuleIndex, imp string, from label.Label) (string, depKind) {
	if l, ok := resolve.FindRuleWithOverride(c, resolve.ImportSpec{Lang: languageName, Imp: imp}, languageName); ok {
		return l.Rel(from.Repo, from.Pkg).String(), depOverride
	}
	if matches := ix.FindRulesByImport(resolve.ImportSpec{Lang: languageName, Imp: imp}, languageName); len(matches) > 0 {
		return matches[0].Label.Rel(from.Repo, from.Pkg).String(), depIndexed
	}
	if rel, ok := relUnder(imp, gc.Prefix); ok && rel != "" {
		return label.New("", rel, path.Base(rel)).Rel(from.Repo, from.Pkg).String(), depInRepo
	}
	if rel, ok := relUnder(imp, gc.StdlibPrefix); ok && rel != "" {
		return stdlibLabel(gc, rel).String(), depStdlib
	}
	return "", depNone
}

// stdlibLabel is the label of the GALA stdlib package at rel in the external
// stdlib repo: @<repo>//<rel>:<base>. stdlibImport is its inverse.
func stdlibLabel(gc *galaConfig, rel string) label.Label {
	return label.New(gc.StdlibRepo, rel, path.Base(rel))
}

// stdlibImport maps a stdlibLabel back to its import path.
func stdlibImport(gc *galaConfig, l label.Label) (string, bool) {
	if l.Repo != gc.StdlibRepo || l.Pkg == "" || l.Name != path.Base(l.Pkg) {
		return "", false
	}
	return gc.StdlibPrefix + "/" + l.Pkg, true
}

// resolveGoImport maps a non-GALA import to its Bazel label using gazelle-go's
// resolver, but only when the Go half has been configured (composite mode). It
// returns ok=false for Go stdlib (no dep needed) and when the Go config is
// absent (standalone GALA use), so a mixed package's third-party Go deps (e.g.
// @com_github_google_uuid) are resolved without the GALA half re-implementing
// Go resolution.
func resolveGoImport(c *config.Config, ix *resolve.RuleIndex, rc *repo.RemoteCache, imp string, from label.Label) (string, bool) {
	if _, ok := c.Exts[goLangExtKey]; !ok {
		return "", false
	}
	l, err := golang.ResolveGo(c, ix, rc, imp, from)
	if err != nil || l == label.NoLabel {
		return "", false
	}
	return l.Rel(from.Repo, from.Pkg).String(), true
}

// relUnder returns the path of imp relative to ns ("" when imp == ns) and
// whether imp lies within the ns namespace.
func relUnder(imp, ns string) (string, bool) {
	if ns == "" {
		return "", false
	}
	if imp == ns {
		return "", true
	}
	if strings.HasPrefix(imp, ns+"/") {
		return strings.TrimPrefix(imp, ns+"/"), true
	}
	return "", false
}
