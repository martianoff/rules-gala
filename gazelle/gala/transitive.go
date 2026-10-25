package gala

import (
	"path"
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// Transitive GALA deps
//
// A package's generated Go can name types from packages its GALA source never
// imports. If `c` imports only `b`, and `b` exports
// `func Find(name string) Option[a.Cmd]`, then `b.Find("x").Map((x) => x.Name)`
// in `c` transpiles to a Go func literal that must spell its parameter type,
// `func(x a.Cmd) string`, so the generated Go for `c` imports `a`. rules_go's
// strict-deps check rejects that unless `a` is a direct dep of `c`, and the
// transpile action also needs `a` among the direct deps to load its metadata.
//
// So every GALA rule's deps also get the transitive closure of the GALA
// libraries its GALA deps depend on. Extra deps that turn out unused are
// harmless; missing ones fail the build. Plain Go deps are not propagated.
//
// Gazelle indexes every rule (Imports) before it resolves any (Resolve), so
// Imports records each gala_library's own dependencies in a depGraph and
// Resolve walks it.

// galaImportsKey is the private attr under which GenerateRules attaches a
// rule's galaImports. Gazelle copies private attrs onto the BUILD rule a
// generated rule is merged into, so Imports can tell a rule generated this run
// (raw GALA imports known) from one only read from an existing BUILD file.
const galaImportsKey = "_gala_imports"

// depGraph holds what each indexed gala_library depends on.
type depGraph struct {
	// nodes maps a gala_library's importpath to its record.
	nodes map[string]*depNode
	// byLabel maps a gala_library's absolute label to its importpath, to map
	// the deps of rules read from existing BUILD files back to import paths.
	byLabel map[label.Label]string
}

// depNode is one gala_library in the graph.
type depNode struct {
	label label.Label
	// visibility is the rule's visibility, or the package default.
	visibility []string
	// imports is the raw import list, set for rules generated this run.
	imports  []string
	hasRaw   bool
	gc       *galaConfig
	repoName string
	// deps and galaDeps are the absolute labels of a rule that was not
	// regenerated this run (its directory is not being updated): the best
	// record of its dependencies gazelle has.
	deps     []label.Label
	galaDeps []label.Label
}

func newDepGraph() *depGraph {
	return &depGraph{nodes: map[string]*depNode{}, byLabel: map[label.Label]string{}}
}

// record adds a gala_library to the graph. The first rule for an importpath
// wins, matching resolveImport, which takes the first index match.
func (g *depGraph) record(c *config.Config, r *rule.Rule, f *rule.File, importpath string) {
	if c == nil || f == nil {
		return
	}
	if _, dup := g.nodes[importpath]; dup {
		return
	}
	l := label.New(c.RepoName, f.Pkg, r.Name())
	n := &depNode{
		label:      l,
		visibility: ruleVisibility(r, f),
		gc:         getGalaConfig(c),
		repoName:   c.RepoName,
	}
	if gi, ok := r.PrivateAttr(galaImportsKey).(*galaImports); ok && gi != nil {
		n.imports = gi.imports
		n.hasRaw = true
	} else {
		n.deps = absLabels(r.AttrStrings("deps"), c.RepoName, f.Pkg)
		n.galaDeps = absLabels(r.AttrStrings("gala_deps"), c.RepoName, f.Pkg)
	}
	g.nodes[importpath] = n
	g.byLabel[l] = importpath
}

// ruleVisibility returns r's visibility, falling back to the package's
// default_visibility (and Bazel's private default when neither is set).
func ruleVisibility(r *rule.Rule, f *rule.File) []string {
	if v := r.AttrStrings("visibility"); len(v) > 0 {
		return v
	}
	for _, pr := range f.Rules {
		if pr.Kind() == "package" {
			if v := pr.AttrStrings("default_visibility"); len(v) > 0 {
				return v
			}
		}
	}
	return []string{"//visibility:private"}
}

// absLabels parses label strings written in package pkg into absolute labels.
// Unparseable entries are dropped.
func absLabels(strs []string, repo, pkg string) []label.Label {
	out := make([]label.Label, 0, len(strs))
	for _, s := range strs {
		l, err := label.Parse(s)
		if err != nil {
			continue
		}
		out = append(out, normalizeLabel(l, repo, pkg))
	}
	return out
}

// normalizeLabel makes l absolute and spells the main repo the way the rule
// index does (label.New(c.RepoName, ...)), so labels compare equal.
func normalizeLabel(l label.Label, repo, pkg string) label.Label {
	l = l.Abs(repo, pkg)
	if l.Repo == "" {
		l.Repo = repo
	}
	return l
}

// visibleFrom reports whether a rule with the given visibility, declared in
// package nodePkg, may be depended on from package fromPkg. It understands
// //visibility:public, //visibility:private, __pkg__ and __subpackages__ in the
// main repo; anything else (package groups, other repos) counts as not visible,
// so an unknown form never adds a dep that could fail Bazel's visibility check.
func visibleFrom(vis []string, repo, nodePkg, fromPkg string) bool {
	for _, v := range vis {
		switch v {
		case "//visibility:public":
			return true
		case "//visibility:private":
			if fromPkg == nodePkg {
				return true
			}
			continue
		}
		l, err := label.Parse(v)
		if err != nil {
			continue
		}
		l = normalizeLabel(l, repo, nodePkg)
		if l.Repo != repo {
			continue
		}
		switch l.Name {
		case "__pkg__":
			if fromPkg == l.Pkg {
				return true
			}
		case "__subpackages__":
			if l.Pkg == "" || fromPkg == l.Pkg || strings.HasPrefix(fromPkg, l.Pkg+"/") {
				return true
			}
		}
	}
	return false
}

// edges returns the GALA dependencies of node n as import paths, plus any
// gala_deps labels that cannot be mapped back to an import path (a
// cross-module library wired by a `# gazelle:resolve` override).
func (g *depGraph) edges(n *depNode) (imps []string, galaLeaves []label.Label) {
	if n.hasRaw {
		return n.imports, nil
	}
	toImport := func(l label.Label) (string, bool) {
		if imp, ok := g.byLabel[l]; ok {
			return imp, true
		}
		// A GALA stdlib library from the external stdlib repo.
		if n.gc != nil && l.Repo != n.repoName && l.Repo == n.gc.StdlibRepo && l.Pkg != "" && l.Name == path.Base(l.Pkg) {
			return n.gc.StdlibPrefix + "/" + l.Pkg, true
		}
		return "", false
	}
	for _, l := range n.deps {
		// Anything else in deps is a plain Go dep, which is not propagated.
		if imp, ok := toImport(l); ok {
			imps = append(imps, imp)
		}
	}
	for _, l := range n.galaDeps {
		if imp, ok := toImport(l); ok {
			imps = append(imps, imp)
		} else {
			galaLeaves = append(galaLeaves, l)
		}
	}
	return imps, galaLeaves
}

// addTransitiveDeps adds to deps / galaDeps the GALA libraries reachable from
// the rule's direct GALA imports (roots), excluding the rule's own package.
//
// A transitive import is followed only when it is known to be GALA:
//   - an indexed gala_library (in-repo; its own deps are followed in turn),
//   - a `# gazelle:resolve gala` override (written to gala_deps), or
//   - a GALA stdlib package from the external stdlib repo.
//
// The deps of packages outside this repo are not visible to gazelle, so the
// walk stops there. Unindexed in-repo import paths are skipped, because they
// can't be told apart from in-repo Go packages.
func (g *depGraph) addTransitiveDeps(
	c *config.Config,
	gc *galaConfig,
	roots []string,
	exclude map[string]bool,
	from label.Label,
	deps, galaDeps map[string]bool,
) {
	visited := map[string]bool{}
	for imp := range exclude {
		visited[imp] = true
	}
	var queue []string
	for _, imp := range roots {
		if !visited[imp] {
			visited[imp] = true
			queue = append(queue, imp)
		}
	}
	isRoot := map[string]bool{}
	for _, imp := range roots {
		isRoot[imp] = true
	}

	for len(queue) > 0 {
		cur := queue[0]
		queue = queue[1:]

		if !isRoot[cur] {
			if !g.addOne(c, gc, cur, from, deps, galaDeps) {
				continue
			}
		}
		n, ok := g.nodes[cur]
		if !ok {
			continue
		}
		imps, leaves := g.edges(n)
		for _, l := range leaves {
			galaDeps[l.Rel(from.Repo, from.Pkg).String()] = true
		}
		for _, imp := range imps {
			if visited[imp] || gc.ImplicitDeps[imp] {
				continue
			}
			visited[imp] = true
			queue = append(queue, imp)
		}
	}
}

// addOne adds the dep for a transitively reached import path and reports
// whether it is a GALA library whose own deps should be followed.
func (g *depGraph) addOne(
	c *config.Config,
	gc *galaConfig,
	imp string,
	from label.Label,
	deps, galaDeps map[string]bool,
) bool {
	if l, ok := resolve.FindRuleWithOverride(c, resolve.ImportSpec{Lang: languageName, Imp: imp}, languageName); ok {
		galaDeps[l.Rel(from.Repo, from.Pkg).String()] = true
		return true
	}
	if n, ok := g.nodes[imp]; ok {
		// A dep the rule can't see would fail Bazel's visibility check — and
		// the generated Go could not name its types anyway. Still follow its
		// deps: those may be visible and needed.
		if visibleFrom(n.visibility, n.repoName, n.label.Pkg, from.Pkg) {
			deps[n.label.Rel(from.Repo, from.Pkg).String()] = true
		}
		return true
	}
	if _, inRepo := relUnder(imp, gc.Prefix); inRepo {
		return false
	}
	if rel, ok := relUnder(imp, gc.StdlibPrefix); ok && rel != "" {
		deps[label.New(gc.StdlibRepo, rel, path.Base(rel)).String()] = true
		return true
	}
	return false
}
