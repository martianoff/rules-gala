package gala

import (
	"go/parser"
	"go/token"
	"log"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/bazelbuild/bazel-gazelle/language"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// mainFuncRe matches a zero-argument main function declaration, used together
// with a "package main" declaration to identify a gala_binary. This is a
// lightweight content check, not a re-parse of the grammar.
var mainFuncRe = regexp.MustCompile(`(?m)^\s*func\s+main\s*\(\s*\)`)

// galaImports is the opaque payload carried from GenerateRules to Resolve for
// each generated rule (GenerateResult.Imports).
type galaImports struct {
	// imports is the deduped set of GALA import paths across the rule's files.
	imports []string
	// self is the rule's own importpath, excluded from its own deps.
	self string
}

// GenerateRules implements language.Language. It produces one gala_library (or
// gala_binary for a "package main" with a main()) for the non-test sources in a
// directory, plus a gala_test for any *_test.gala files.
func (gl *galaLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
	gc := getGalaConfig(args.Config)

	// `# gazelle:gala_generation off` hands this directory (and, inherited, its
	// subtree) to manual wiring. Emitting nothing means gazelle never merges
	// onto or re-resolves the deps of any hand-authored GALA rules here, so a
	// curated/mixed package is left exactly as written.
	if !gc.Generate {
		return language.GenerateResult{}
	}

	var galaFiles []string
	for _, f := range args.RegularFiles {
		if strings.HasSuffix(f, ".gala") {
			galaFiles = append(galaFiles, f)
		}
	}
	if len(galaFiles) == 0 {
		return language.GenerateResult{}
	}

	infos, err := extractImports(gl.runner, gc.Helper, args.Dir, galaFiles)
	if err != nil {
		log.Printf("gazelle(gala): %s: extracting imports: %v", args.Rel, err)
		infos = map[string]fileInfo{}
	}

	// Additional Go sources — any .go in the package that gala did NOT produce
	// (i.e. not a .gen.go transpiler output) and isn't a _test.go — share the
	// package with the .gala sources. Whether a human wrote them or another tool
	// generated them, they must compile alongside the transpiled .gala.
	// rules_gala's gala_library does this via its `go_srcs` attribute, so a
	// mixed GALA/Go package is still one gala_library — fold the .go in rather
	// than dropping it.
	//
	// NOTE: the Go gazelle language, if enabled in the same gazelle_binary, also
	// emits a go_library for these .go files, which would collide with this
	// gala_library on the directory-base name. Keep the Go language off
	// mixed-package .go (see README "Mixed GALA/Go packages").
	goSrcs := extraGoSrcs(args.RegularFiles)

	// Partition into library/binary sources and framework-test files. A
	// *_test.gala file that declares `package main` with a `main()` is a
	// runnable benchmark binary, not a framework test — those are hand-wired
	// gala_binary targets (e.g. perf_gala), so the extension leaves them alone
	// rather than minting a colliding gala_test.
	var srcFiles, testFiles []string
	for _, f := range galaFiles {
		if strings.HasSuffix(f, "_test.gala") {
			if fileIsMain(args.Dir, f, infos) {
				log.Printf("gazelle(gala): %s: skipping %s (package main with main(); manage it as a gala_binary by hand)", args.Rel, f)
				continue
			}
			testFiles = append(testFiles, f)
		} else {
			srcFiles = append(srcFiles, f)
		}
	}

	var res language.GenerateResult
	name := dirName(args.Rel)

	// Non-test sources: gala_library (with any extra .go folded into go_srcs),
	// or gala_binary for a runnable main.
	if len(srcFiles) > 0 {
		sort.Strings(srcFiles)
		isMain := detectMain(args.Dir, srcFiles, infos)
		importPath := joinImportPath(gc.Prefix, args.Rel)

		if isMain && len(goSrcs) > 0 {
			// gala_binary has no go_srcs, so a mixed `package main` can't be
			// folded into one rule — leave it to manual wiring.
			log.Printf("gazelle(gala): %s: mixed GALA/Go `package main` (gala_binary has no go_srcs); leaving to manual wiring", args.Rel)
		} else {
			imps := collectImports(srcFiles, infos)
			var r *rule.Rule
			if isMain {
				r = rule.NewRule("gala_binary", name)
				r.SetAttr("srcs", srcFiles)
			} else {
				r = rule.NewRule("gala_library", name)
				r.SetAttr("srcs", srcFiles)
				r.SetAttr("importpath", importPath)
				r.SetAttr("visibility", []string{"//visibility:public"})
				if len(goSrcs) > 0 {
					// Mixed package: bundle the extra .go and add their Go
					// imports so deps cover both source kinds.
					r.SetAttr("go_srcs", goSrcs)
					imps = mergeSortedUnique(imps, goFileImports(args.Dir, goSrcs))
				}
			}
			res.Gen = append(res.Gen, r)
			res.Imports = append(res.Imports, &galaImports{
				imports: imps,
				self:    importPath,
			})
		}
	}

	// Test sources: one gala_test per *_test.gala file, named after the file
	// stem, carrying that file's own resolved deps. This matches the repo
	// convention (one test target per file) and avoids name collisions with
	// existing per-file rules when regenerating.
	//
	// A test that declares the SAME package as the library (an internal/
	// white-box test) compiles against the library's sources and must embed
	// them: gala_test takes `pkg = <package>` + `lib_srcs = <lib .gala>`, and
	// its deps are the union of the test's and the library's imports (the lib
	// sources are compiled into the test binary). A standalone test (typically
	// `package main`) keeps the plain form.
	libPkg := libPackageOf(srcFiles, infos)
	sort.Strings(testFiles)
	for _, tf := range testFiles {
		testName := strings.TrimSuffix(tf, ".gala")
		r := rule.NewRule("gala_test", testName)
		r.SetAttr("srcs", []string{tf})
		imps := collectImports([]string{tf}, infos)
		tfPkg := ""
		if info, ok := infos[tf]; ok {
			tfPkg = info.Package
		}
		if libPkg != "" && libPkg != "main" && tfPkg == libPkg {
			r.SetAttr("pkg", libPkg)
			r.SetAttr("lib_srcs", srcFiles)
			imps = mergeSortedUnique(imps, collectImports(srcFiles, infos))
		}
		res.Gen = append(res.Gen, r)
		res.Imports = append(res.Imports, &galaImports{
			imports: imps,
			self:    "",
		})
	}

	return res
}

// extraGoSrcs returns the sorted Go sources in a directory that gala did not
// generate: every .go file that is not a .gen.go transpiler output and not a
// _test.go (Go test files belong to a go_test, not the gala_library). These may
// be hand-written or produced by another tool; either way they share the
// package and are folded into gala_library.go_srcs for a mixed GALA/Go package.
func extraGoSrcs(files []string) []string {
	var out []string
	for _, f := range files {
		if strings.HasSuffix(f, ".go") && !strings.HasSuffix(f, ".gen.go") && !strings.HasSuffix(f, "_test.go") {
			out = append(out, f)
		}
	}
	sort.Strings(out)
	return out
}

// goFileImports returns the sorted, deduped import paths declared by the given
// Go files (parsed imports-only). These feed dep resolution for a mixed
// package's go_srcs alongside the .gala imports; non-GALA paths (Go stdlib,
// third-party) are dropped later by the resolver.
func goFileImports(dir string, files []string) []string {
	set := map[string]bool{}
	for _, f := range files {
		fset := token.NewFileSet()
		af, err := parser.ParseFile(fset, filepath.Join(dir, f), nil, parser.ImportsOnly)
		if err != nil {
			log.Printf("gazelle(gala): parsing %s for imports: %v", f, err)
			continue
		}
		for _, spec := range af.Imports {
			p := strings.Trim(spec.Path.Value, `"`)
			if p != "" {
				set[p] = true
			}
		}
	}
	out := make([]string, 0, len(set))
	for p := range set {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

// mergeSortedUnique returns the sorted union of two import-path slices.
func mergeSortedUnique(a, b []string) []string {
	set := map[string]bool{}
	for _, x := range a {
		set[x] = true
	}
	for _, x := range b {
		set[x] = true
	}
	out := make([]string, 0, len(set))
	for x := range set {
		out = append(out, x)
	}
	sort.Strings(out)
	return out
}

// libPackageOf returns the GALA package declared by the library's non-test
// sources (they share one package), or "" if unknown. Used to detect internal
// tests — those declaring the same package as the library.
func libPackageOf(srcFiles []string, infos map[string]fileInfo) string {
	for _, f := range srcFiles {
		if info, ok := infos[f]; ok && info.Package != "" {
			return info.Package
		}
	}
	return ""
}

// dirName returns the rule base name for a directory: the final path segment,
// or "root" for the repository root.
func dirName(rel string) string {
	if rel == "" {
		return "root"
	}
	return path.Base(rel)
}

// joinImportPath builds the importpath for a directory from the prefix and the
// repo-relative directory path.
func joinImportPath(prefix, rel string) string {
	if rel == "" {
		return prefix
	}
	return prefix + "/" + rel
}

// detectMain reports whether the source set forms a runnable binary: at least
// one file declares "package main" and contains a zero-arg main() function.
func detectMain(dir string, srcFiles []string, infos map[string]fileInfo) bool {
	for _, f := range srcFiles {
		if fileIsMain(dir, f, infos) {
			return true
		}
	}
	return false
}

// fileIsMain reports whether a single file declares "package main" and defines
// a zero-arg main() function.
func fileIsMain(dir, f string, infos map[string]fileInfo) bool {
	if info, ok := infos[f]; !ok || info.Package != "main" {
		return false
	}
	data, err := os.ReadFile(filepath.Join(dir, f))
	if err != nil {
		return false
	}
	return mainFuncRe.Match(data)
}

// collectImports returns the sorted, deduped union of import paths declared by
// the given files.
func collectImports(files []string, infos map[string]fileInfo) []string {
	set := map[string]bool{}
	for _, f := range files {
		info, ok := infos[f]
		if !ok {
			continue
		}
		for _, imp := range info.Imports {
			set[imp] = true
		}
	}
	out := make([]string, 0, len(set))
	for imp := range set {
		out = append(out, imp)
	}
	sort.Strings(out)
	return out
}
