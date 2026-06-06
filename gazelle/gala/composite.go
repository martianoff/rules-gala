// composite.go presents GALA and Go as a single Gazelle language. A consumer
// loads only "@gala_gazelle//gala", yet pure-GALA, mixed GALA/Go, and pure-Go
// packages are all managed — with no collision, because the two halves never
// both claim a directory. Per-directory routing sends any directory containing
// a .gala file to the GALA generator (which folds hand-written .go into a
// gala_library via go_srcs) and every other directory to the embedded
// gazelle-go language.
package gala

import (
	"context"
	"flag"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/language"
	golang "github.com/bazelbuild/bazel-gazelle/language/go"
	"github.com/bazelbuild/bazel-gazelle/repo"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
	"strings"
)

// goName is the language name gazelle-go tags its ImportSpecs and index lookups
// with. It matches goLangExtKey ("go") but names the resolve-language concept.
const goName = "go"

// compositeLang routes between the GALA half and an embedded gazelle-go.
type compositeLang struct {
	gala   *galaLang
	goLang language.Language
}

// NewLanguage is the entry point referenced by gazelle_binary's generated main.
func NewLanguage() language.Language {
	return &compositeLang{gala: newGalaLang(), goLang: golang.NewLanguage()}
}

var (
	_ language.Language            = (*compositeLang)(nil)
	_ config.Configurer            = (*compositeLang)(nil)
	_ language.ModuleAwareLanguage = (*compositeLang)(nil)
	_ language.LifecycleManager    = (*compositeLang)(nil)
	_ resolve.CrossResolver        = (*compositeLang)(nil)
)

// isGalaKind reports whether a rule kind is owned by the GALA half.
func isGalaKind(kind string) bool {
	switch kind {
	case "gala_library", "gala_binary", "gala_test", "gala_exec_test":
		return true
	default:
		return false
	}
}

func (c *compositeLang) Name() string { return c.gala.Name() }

// --- config.Configurer: drive both so c.Exts["gala"] and c.Exts["go"] are set.

func (c *compositeLang) RegisterFlags(fs *flag.FlagSet, cmd string, cfg *config.Config) {
	c.gala.RegisterFlags(fs, cmd, cfg)
	c.goLang.RegisterFlags(fs, cmd, cfg)
}

func (c *compositeLang) CheckFlags(fs *flag.FlagSet, cfg *config.Config) error {
	if err := c.gala.CheckFlags(fs, cfg); err != nil {
		return err
	}
	return c.goLang.CheckFlags(fs, cfg)
}

func (c *compositeLang) KnownDirectives() []string {
	return append(c.gala.KnownDirectives(), c.goLang.KnownDirectives()...)
}

func (c *compositeLang) Configure(cfg *config.Config, rel string, f *rule.File) {
	c.gala.Configure(cfg, rel, f)
	c.goLang.Configure(cfg, rel, f)
}

// --- Kinds / Loads: merge both halves.

func (c *compositeLang) Kinds() map[string]rule.KindInfo {
	merged := map[string]rule.KindInfo{}
	for k, v := range c.goLang.Kinds() {
		merged[k] = v
	}
	for k, v := range c.gala.Kinds() {
		merged[k] = v
	}
	return merged
}

func (c *compositeLang) Loads() []rule.LoadInfo {
	return append(c.gala.Loads(), c.goLang.Loads()...)
}

// ApparentLoads is preferred over Loads under bzlmod. The GALA loads are static
// (@rules_gala//...); the Go loads come from the embedded language if it is
// module-aware, else its plain Loads().
func (c *compositeLang) ApparentLoads(moduleToApparentName func(string) string) []rule.LoadInfo {
	loads := c.gala.Loads()
	if ma, ok := c.goLang.(language.ModuleAwareLanguage); ok {
		loads = append(loads, ma.ApparentLoads(moduleToApparentName)...)
	} else {
		loads = append(loads, c.goLang.Loads()...)
	}
	return loads
}

// --- GenerateRules / Fix.

func (c *compositeLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
	for _, f := range args.RegularFiles {
		if strings.HasSuffix(f, ".gala") {
			return c.gala.GenerateRules(args)
		}
	}
	return c.goLang.GenerateRules(args)
}

func (c *compositeLang) Fix(cfg *config.Config, f *rule.File) {
	c.gala.Fix(cfg, f)
	c.goLang.Fix(cfg, f)
}

// --- resolve.Resolver: route by rule kind.

func (c *compositeLang) Imports(cfg *config.Config, r *rule.Rule, f *rule.File) []resolve.ImportSpec {
	if isGalaKind(r.Kind()) {
		return c.gala.Imports(cfg, r, f)
	}
	return c.goLang.Imports(cfg, r, f)
}

func (c *compositeLang) Embeds(r *rule.Rule, from label.Label) []label.Label {
	if isGalaKind(r.Kind()) {
		return c.gala.Embeds(r, from)
	}
	return c.goLang.Embeds(r, from)
}

func (c *compositeLang) Resolve(cfg *config.Config, ix *resolve.RuleIndex, rc *repo.RemoteCache, r *rule.Rule, imports interface{}, from label.Label) {
	if isGalaKind(r.Kind()) {
		c.gala.Resolve(cfg, ix, rc, r, imports, from)
		return
	}
	c.goLang.Resolve(cfg, ix, rc, r, imports, from)
}

// CrossResolve bridges the composite's single-language indexing to gazelle-go's
// resolver. Gazelle records every rule under THIS language's Name ("gala"),
// because there is only one registered language (see resolve/index.go: the
// record's Lang is mrslv(rule).Name()). gazelle-go's resolver, however, looks up
// the index filtering by record-language == "go", so it never sees in-repo
// go_library targets and would drop every cross-package Go dep. When that lookup
// misses, gazelle consults registered CrossResolvers; re-query the index under
// this language's own name so the go_library record is found.
//
// GALA imports need no bridging: they are indexed and looked up under the same
// "gala" name, and have prefix/stdlib fallbacks besides. FindRulesByImport does
// not re-enter CrossResolvers, so there is no recursion.
func (c *compositeLang) CrossResolve(cfg *config.Config, ix *resolve.RuleIndex, imp resolve.ImportSpec, lang string) []resolve.FindResult {
	if imp.Lang != goName {
		return nil
	}
	return ix.FindRulesByImport(imp, c.Name())
}

// --- Lifecycle / Finishable: guarded delegation to the Go half, which relies
// on these to set up and tear down its resolver state.

func (c *compositeLang) Before(ctx context.Context) {
	if lm, ok := c.goLang.(language.LifecycleManager); ok {
		lm.Before(ctx)
	}
}

func (c *compositeLang) AfterResolvingDeps(ctx context.Context) {
	if lm, ok := c.goLang.(language.LifecycleManager); ok {
		lm.AfterResolvingDeps(ctx)
	}
}

func (c *compositeLang) DoneGeneratingRules() {
	if fl, ok := c.goLang.(language.FinishableLanguage); ok {
		fl.DoneGeneratingRules()
	}
}
