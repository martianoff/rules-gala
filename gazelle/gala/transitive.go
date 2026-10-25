package gala

import (
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// Every GALA rule also gets its GALA deps' own GALA deps, transitively, as
// direct deps; README.md "Transitive GALA deps" explains why.

// galaImportsKey is the private attr under which GenerateRules attaches a
// gala_library's galaImports. Gazelle copies private attrs onto the BUILD rule
// a generated rule is merged into, so Imports can tell a rule generated this
// run (raw imports known) from one only read from an existing BUILD file.
const galaImportsKey = "_gala_imports"

// depGraph holds what each indexed gala_library depends on. Imports fills it
// and Resolve reads it: gazelle indexes every rule before resolving any.
type depGraph struct {
	// nodes maps a gala_library's importpath to its record. It exists next to
	// the RuleIndex because the index exposes neither a rule's attrs nor a
	// lookup by label.
	nodes map[string]*depNode
	// byLabel maps a gala_library's absolute label to its importpath.
	byLabel map[label.Label]string
	// closures memoizes reachable, by root import path.
	closures map[string]*closure
}

// depNode is one gala_library in the graph.
type depNode struct {
	label      label.Label
	visibility []string
	gc         *galaConfig
	// raw holds the imports of a rule generated this run; nil means the rule
	// was only read from an existing BUILD file (its directory is not being
	// updated), so its existing deps and galaDeps stand in for its imports.
	raw      *galaImports
	deps     []label.Label
	galaDeps []label.Label
}

// closure is the set of GALA dependencies reachable from one import path.
type closure struct {
	imports []string
	// galaLeaves are gala_deps labels of rules not regenerated this run that
	// can't be mapped back to an import path (cross-module libraries).
	galaLeaves []label.Label
}

func newDepGraph() *depGraph {
	return &depGraph{
		nodes:    map[string]*depNode{},
		byLabel:  map[label.Label]string{},
		closures: map[string]*closure{},
	}
}

// record adds a gala_library to the graph. The first rule for an importpath
// wins, as in the RuleIndex lookup.
func (g *depGraph) record(c *config.Config, r *rule.Rule, f *rule.File, importpath string) {
	if c == nil || f == nil {
		return
	}
	if _, dup := g.nodes[importpath]; dup {
		return
	}
	l := label.New(c.RepoName, f.Pkg, r.Name())
	n := &depNode{label: l, visibility: ruleVisibility(r, f), gc: getGalaConfig(c)}
	if gi, ok := r.PrivateAttr(galaImportsKey).(*galaImports); ok && gi != nil {
		n.raw = gi
	} else {
		n.deps = absLabels(r.AttrStrings("deps"), c.RepoName, f.Pkg)
		n.galaDeps = absLabels(r.AttrStrings("gala_deps"), c.RepoName, f.Pkg)
	}
	g.nodes[importpath] = n
	g.byLabel[l] = importpath
}

// ruleVisibility returns r's visibility, falling back to the package's
// default_visibility. nil means neither is set (Bazel's private default).
func ruleVisibility(r *rule.Rule, f *rule.File) []string {
	if v := r.AttrStrings("visibility"); len(v) > 0 {
		return v
	}
	for _, pr := range f.Rules {
		if pr.Kind() == "package" {
			return pr.AttrStrings("default_visibility")
		}
	}
	return nil
}

// absLabels parses label strings written in package pkg into absolute labels,
// spelling the main repo as the RuleIndex does. Unparseable entries are dropped.
func absLabels(strs []string, repo, pkg string) []label.Label {
	out := make([]label.Label, 0, len(strs))
	for _, s := range strs {
		l, err := label.Parse(s)
		if err != nil {
			continue
		}
		l = l.Abs(repo, pkg)
		if l.Repo == "" {
			l.Repo = repo
		}
		out = append(out, l)
	}
	return out
}

// canSee reports whether a rule in fromPkg may depend on n. It recognizes the
// two visibilities generated libraries get (see libraryVisibility): public,
// and an internal/ package's //<parent>:__subpackages__. Anything else — a
// package_group, a private or hand-written list — counts as not visible, so an
// unknown form never adds a dep that would fail Bazel's visibility check.
func (n *depNode) canSee(fromPkg string) bool {
	if len(n.visibility) != 1 {
		return false
	}
	switch v := n.visibility[0]; {
	case v == "//visibility:public":
		return true
	case v == libraryVisibility(n.label.Pkg)[0]:
		root := strings.TrimSuffix(strings.TrimPrefix(v, "//"), ":__subpackages__")
		return root == "" || fromPkg == root || strings.HasPrefix(fromPkg, root+"/")
	}
	return false
}

// edges returns n's direct GALA dependencies as import paths, plus any
// gala_deps labels that can't be mapped back to one.
func (g *depGraph) edges(n *depNode) (imps []string, galaLeaves []label.Label) {
	if n.raw != nil {
		return n.raw.imports, nil
	}
	toImport := func(l label.Label) (string, bool) {
		if imp, ok := g.byLabel[l]; ok {
			return imp, true
		}
		if l.Repo != n.label.Repo {
			return stdlibImport(n.gc, l)
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

// reachable returns every import path reachable from root through indexed
// gala_library rules, skipping each rule's macro-injected imports. Only
// indexed libraries are expanded: the deps of libraries from other modules
// are not visible to gazelle. The result is not filtered by kind or
// visibility; Resolve classifies each entry for the rule at hand.
func (g *depGraph) reachable(root string) *closure {
	if cl, ok := g.closures[root]; ok {
		return cl
	}
	cl := &closure{}
	seen := map[string]bool{root: true}
	for queue := []string{root}; len(queue) > 0; queue = queue[1:] {
		n, ok := g.nodes[queue[0]]
		if !ok {
			continue
		}
		imps, leaves := g.edges(n)
		cl.galaLeaves = append(cl.galaLeaves, leaves...)
		for _, imp := range imps {
			if seen[imp] || n.gc.ImplicitDeps[imp] {
				continue
			}
			seen[imp] = true
			cl.imports = append(cl.imports, imp)
			queue = append(queue, imp)
		}
	}
	g.closures[root] = cl
	return cl
}
