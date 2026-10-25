package gala

import (
	"log"
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/rule"
	bzl "github.com/bazelbuild/buildtools/build"
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
	// c and gc are the config of the library's directory. An import the
	// library wrote is classified with them, not with the config of the rule
	// being resolved.
	c  *config.Config
	gc *galaConfig
	// raw holds the imports of a rule generated this run; nil means the rule
	// was only read from an existing BUILD file (its directory is not being
	// updated).
	raw *galaImports
	// deps and galaDeps are labels from the rule's BUILD attrs: every entry
	// for a rule not regenerated (they stand in for its imports), only the
	// `# keep` entries for a regenerated one (gazelle won't drop those).
	deps     []label.Label
	galaDeps []label.Label
}

// closure is the set of GALA dependencies reachable from one import path.
type closure struct {
	edges []edge
	// std are stdlib deps read from BUILD attrs; they are not walked.
	std []stdLeaf
	// galaLeaves are gala_deps labels that can't be mapped back to an import
	// path (cross-module libraries).
	galaLeaves []label.Label
}

// edge is an import path reached by the walk and the library that wrote it.
type edge struct {
	imp string
	by  *depNode
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
	n := &depNode{label: l, visibility: ruleVisibility(r, f), c: c, gc: getGalaConfig(c)}
	if gi, ok := r.PrivateAttr(galaImportsKey).(*galaImports); ok && gi != nil {
		n.raw = gi
	}
	keptOnly := n.raw != nil
	for attr, dst := range map[string]*[]label.Label{"deps": &n.deps, "gala_deps": &n.galaDeps} {
		strs, complete := listStrings(r.Attr(attr), keptOnly)
		if !complete {
			log.Printf("gazelle(gala): %s: %s is not a plain list (select(), a variable, ...); only its list parts are followed for transitive GALA deps", l, attr)
		}
		*dst = absLabels(strs, c.RepoName, f.Pkg)
	}
	g.nodes[importpath] = n
	g.byLabel[l] = importpath
}

// listStrings returns the string elements of an attr value, including the
// list parts of a `+` concatenation. keptOnly limits it to elements marked
// `# keep`. complete is false when part of the value isn't a list literal.
func listStrings(e bzl.Expr, keptOnly bool) (strs []string, complete bool) {
	switch e := e.(type) {
	case nil:
		return nil, true
	case *bzl.ListExpr:
		complete = true
		for _, el := range e.List {
			s, ok := el.(*bzl.StringExpr)
			if !ok {
				complete = false
				continue
			}
			if !keptOnly || rule.ShouldKeep(el) {
				strs = append(strs, s.Value)
			}
		}
		return strs, complete
	case *bzl.BinaryExpr:
		if e.Op != "+" {
			return nil, false
		}
		x, xok := listStrings(e.X, keptOnly)
		y, yok := listStrings(e.Y, keptOnly)
		return append(x, y...), xok && yok
	default:
		return nil, false
	}
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
			l.Canonical = false
		}
		out = append(out, l)
	}
	return out
}

// canSee reports whether a rule in fromPkg may depend on n. It understands
// //visibility:public, //visibility:private, and __pkg__ / __subpackages__ in
// the main repo — what generated libraries use (see libraryVisibility) and
// the common hand-written forms. Any other entry (a package_group, another
// repo) is skipped, so an unknown form never adds a dep that would fail
// Bazel's visibility check. nil visibility is Bazel's private default.
func (n *depNode) canSee(fromPkg string) bool {
	vis := n.visibility
	if len(vis) == 0 {
		vis = []string{"//visibility:private"}
	}
	for _, v := range vis {
		switch v {
		case "//visibility:public":
			return true
		case "//visibility:private":
			if fromPkg == n.label.Pkg {
				return true
			}
			continue
		}
		l, err := label.Parse(v)
		if err != nil || (l.Repo != "" && l.Repo != n.label.Repo) {
			continue
		}
		l = l.Abs(n.label.Repo, n.label.Pkg)
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

// stdLeaf is a stdlib dep read from a BUILD attr, kept as written (only its
// repo respelled) so an explicit target name survives.
type stdLeaf struct {
	label label.Label
	imp   string
}

// edges returns n's direct dependencies: in-repo GALA libraries and raw
// imports as import paths, stdlib labels from its BUILD attrs, and gala_deps
// labels that are neither (cross-module libraries). Any other label in deps is
// a plain Go dep, which is not propagated.
func (g *depGraph) edges(n *depNode) (imps []string, std []stdLeaf, galaLeaves []label.Label) {
	if n.raw != nil {
		imps = append(imps, n.raw.imports...)
	}
	for _, attr := range []struct {
		labels []label.Label
		gala   bool
	}{{n.deps, false}, {n.galaDeps, true}} {
		for _, l := range attr.labels {
			if imp, ok := g.byLabel[l]; ok {
				imps = append(imps, imp)
			} else if sl, imp, ok := parseStdlibLabel(n.gc, l); ok && l.Repo != n.label.Repo {
				std = append(std, stdLeaf{label: sl, imp: imp})
			} else if attr.gala {
				galaLeaves = append(galaLeaves, l)
			}
		}
	}
	return imps, std, galaLeaves
}

// reachable returns every import path reachable from root through indexed
// gala_library rules, each with the library that wrote it, skipping that
// library's macro-injected imports. Only indexed libraries are expanded: the
// deps of libraries from other modules are not visible to gazelle. The result
// is not filtered by kind or visibility; Resolve does that per rule.
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
		imps, std, leaves := g.edges(n)
		cl.galaLeaves = append(cl.galaLeaves, leaves...)
		for _, s := range std {
			if !n.gc.ImplicitDeps[s.imp] {
				cl.std = append(cl.std, s)
			}
		}
		for _, imp := range imps {
			if seen[imp] || n.gc.ImplicitDeps[imp] {
				continue
			}
			seen[imp] = true
			cl.edges = append(cl.edges, edge{imp: imp, by: n})
			queue = append(queue, imp)
		}
	}
	g.closures[root] = cl
	return cl
}
