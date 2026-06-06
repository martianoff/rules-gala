# gala_gazelle — a Gazelle extension for GALA

`gala_gazelle` teaches [Gazelle](https://github.com/bazelbuild/bazel-gazelle)
to generate and maintain BUILD targets for [GALA](https://github.com/martianoff/gala)
source. It manages `gala_library`, `gala_binary`, `gala_test`, and
`gala_exec_test` rules (loaded from `@rules_gala//gala:defs.bzl`) and resolves
GALA `import` strings to Bazel labels.

Import extraction is delegated to a small helper binary — `gala imports --json`
— instead of re-implementing the ANTLR grammar, mirroring the helper model used
by the rules_python Gazelle plugin.

## Adding the extension (consumer setup)

This is a standalone Bazel module. In your `MODULE.bazel`:

```starlark
bazel_dep(name = "gala_gazelle", version = "0.2.4", dev_dependency = True)
```

`@gala_gazelle//gala` is a **composite language**: it embeds gazelle's Go
language and routes per directory — any directory containing a `.gala` file is
managed by the GALA half (pure-GALA and mixed GALA/Go via `go_srcs`), every
other directory by the embedded Go language. So a single language handles GALA,
mixed, **and** pure-Go packages with no cross-language target-name collision.

### Recommended: the `gala_gazelle` macro

One call wires a composite `gazelle_binary` **and** a toolchain-driven import
helper, so BUILD generation is reproducible — the gala that extracts imports is
the same gala the registered toolchain transpiles with:

```starlark
load("@gala_gazelle//gala:defs.bzl", "gala_gazelle")

# gazelle:gala_prefix github.com/you/project
gala_gazelle(name = "gazelle")
```

Run it with `bazel run //:gazelle`. This creates `//:gazelle_bin`,
`//:gazelle_gala_imports` (the toolchain helper), and `//:gazelle`.

Pin a specific gala for the helper with `gala_helper = "//cmd/gala:gala"` (any
gala binary label); by default the **registered GALA toolchain** is used.
Requires `gala_gazelle` ≥ 0.2.4 (which depends on `rules_gala` ≥ 0.1.3 for
`gala_imports_helper`).

> **Caveat — dev_dependency + consumer-loaded BUILD.** The macro adds
> `load("@gala_gazelle//gala:defs.bzl", …)` to the BUILD file you call it from.
> If you list `gala_gazelle` as a `dev_dependency` (recommended) **and** that
> same BUILD file is loaded when your module is consumed as a *non-root*
> dependency — e.g. a module that ships a GALA toolchain referencing
> `//:all_gala_sources` from its root BUILD — the load fails for the consumer
> (`No repository visible as '@gala_gazelle'`), because dev-dependencies are
> stripped for non-root modules. In that case use the [manual wiring](#manual-wiring)
> instead: it references `@gala_gazelle` only as a string label in
> `gazelle_binary.languages` (resolved when the gazelle binary is built, not at
> BUILD-load time) and loads only `@rules_gala` (for `gala_imports_helper`) and
> `@gazelle`, both regular deps. Leaf consumers (apps no one depends on) are
> unaffected.

### Manual wiring

If you need full control — or you hit the dev_dependency caveat above — build
the pieces yourself. This keeps the toolchain-driven helper but loads only
`@gazelle` and `@rules_gala` (regular deps) and names `@gala_gazelle` solely as a
string label:

```starlark
load("@gazelle//:def.bzl", "gazelle", "gazelle_binary")
load("@rules_gala//gala:defs.bzl", "gala_imports_helper")

gazelle_binary(
    name = "gazelle_bin",
    languages = ["@gala_gazelle//gala"],   # handles GALA + Go
)

# Reproducible import helper from the registered GALA toolchain.
gala_imports_helper(name = "gala_imports")

# gazelle:gala_prefix github.com/you/project
gazelle(
    name = "gazelle",
    gazelle = ":gazelle_bin",
    data = [":gala_imports"],
    extra_args = ["-gala_helper=$(execpath :gala_imports)"],
)
```

Do **not** also list `@gazelle//language/go` — it would double-claim the `.go`
in mixed packages and collide. The composite already includes it.

Run it with `bazel run //:gazelle`.

The helper binary must be discoverable. By default the extension shells out to
`gala` on `PATH`; for reproducible generation, drive it from the registered GALA
toolchain with `gala_imports_helper` (what the macro does — see *Helper version*
below), or override with the `-gala_helper` flag / `# gazelle:gala_helper`
directive.

## What it generates

Per directory containing `.gala` files:

- **`gala_library`** for the non-test sources, with `importpath` derived from
  the configured prefix plus the directory's repo-relative path, and
  `visibility = ["//visibility:public"]`.
- **`gala_binary`** instead of a library when a source declares `package main`
  and defines a zero-argument `main()`. The target — library or binary — is
  named after the directory's base name, so put each `main` in its own
  `cmd/<binary>/main.gala` (Go convention) to get a `<binary>` target.
  `x_defs` and `visibility` are **not** synthesized; once added by hand they are
  preserved across regeneration (they are not in the rule's mergeable attrs).
- **`gala_test`** for each `*_test.gala` file. A test that declares the **same
  package as the library** (an internal / white-box test) is generated with
  `pkg = "<package>"` and `lib_srcs = [<the library's .gala>]` so it compiles
  against the library's sources, and its `deps` are the union of the test's and
  the library's imports. A standalone test (e.g. `package main`) keeps the plain
  `gala_test(srcs = [...])` form.

`srcs` are sorted; `deps` are resolved from each file's GALA imports.

### Mixed GALA/Go packages

A package may place additional Go sources (`.go` that gala did **not** generate
— i.e. not the `.gen.go` transpiler outputs) **alongside** `.gala` files,
whether hand-written or produced by another tool. `rules_gala`'s `gala_library`
compiles both kinds into one `go_library` via its `go_srcs` attribute, so the
extension folds those `.go` into a single `gala_library`:

```starlark
gala_library(
    name = "widgets",
    srcs = ["widgets.gala"],          # transpiled to .gen.go
    go_srcs = ["native.go"],          # extra Go, compiled in the same package
    importpath = "example.com/m/widgets",
    deps = [...],                     # union of the .gala and .go imports
)
```

`deps` are resolved from the **union** of the `.gala` imports and the `.go`
files' imports (Go stdlib and third-party Go imports the GALA resolver can't map
are dropped — add those by hand or with `# keep`). `_test.go` files and the
`.gen.go` outputs are never put in `go_srcs`. A mixed `package main` is the one
exception: `gala_binary` has no `go_srcs`, so the extension leaves it to manual
wiring.

No collision arises as long as you use only `@gala_gazelle//gala` (the composite
owns the whole directory and never lets the embedded Go language re-claim the
`.go`). The `.go` files' imports — Go stdlib, in-repo, and third-party — are
resolved via the embedded Go resolver, so a mixed package's external Go deps
(e.g. `@com_github_google_uuid`) land in `deps` automatically.

Internal (white-box) tests of a mixed package are supported: the extension
bundles the library's hand-written `.go` into the `gala_test` via `lib_go_srcs`
(alongside `lib_srcs` for the `.gala`), so the test sees the package's `.go`
symbols. Requires `rules_gala` ≥ 0.1.2.

### Known limitations

- **Transpiler-surfaced transitive deps.** The extension resolves `deps` from
  the **source-level** imports the helper reports. GALA's transpiler can emit a
  reference to a *transitive* package the source never imports — e.g. a test
  that dot-imports package `ui` calls a `ui` function returning a `session.*`
  type, so the generated `.go` imports `…/session` although no `.gala` names it.
  Gazelle can't see this, so the dep is missing. Keep it by hand with a
  `# keep` comment, which survives regeneration:

  ```starlark
  deps = [
      "//app/session",  # keep: transpiler surfaces session types via the ui dot-import
      ...
  ],
  ```

- **Mixed `package main`.** `gala_binary` has no `go_srcs`, so a `package main`
  directory that also holds hand-written `.go` can't be folded into one rule.
  The extension logs and skips it; wire it by hand.

## Dependency resolution

For every GALA import in a rule's sources:

- **Overridden imports** (`# gazelle:resolve gala <import-path> <label>`) take
  precedence and are written to **`gala_deps`**, not `deps`. This is how a
  cross-module GALA library is wired: its sources must be on the transpiler's
  search path, which `gala_deps` provides and `deps` (link-only) does not.
  Requires `gala_gazelle` ≥ 0.2.2.
- **In-repo packages** (under the `gala_prefix`) resolve to in-repo labels in
  `deps` — preferring an indexed `gala_library` with a matching `importpath`,
  otherwise `//<relpath>`.
- **GALA stdlib / external packages** (under `gala_stdlib_prefix`, default
  `martianoff/gala`) resolve to the matching in-repo package if one exists, and
  otherwise to `@<gala_stdlib_repo>//<relpath>` (default repo `gala`).
- **Go stdlib and other non-GALA imports** (`fmt`, `strings`, …) are skipped,
  except in a mixed package, where the `.go` files' third-party / in-repo Go
  imports are resolved to `deps` via the embedded Go resolver.
- **Macro-injected deps** (`martianoff/gala/std`, `martianoff/gala/test`) are
  skipped — the `gala_*` macros add them automatically, so emitting them in
  `deps` would be redundant.

## Directives

| Directive | Default | Meaning |
|-----------|---------|---------|
| `# gazelle:gala_prefix <path>` | `martianoff/gala` | Import-path prefix for in-repo packages. |
| `# gazelle:gala_helper <path>` | `gala` | Path to the import-extraction helper binary. |
| `# gazelle:gala_stdlib_prefix <path>` | `martianoff/gala` | Import namespace of the GALA standard library. |
| `# gazelle:gala_stdlib_repo <name>` | `gala` | Bazel external repo for out-of-repo stdlib imports. |
| `# gazelle:gala_implicit_dep <paths…>` | `martianoff/gala/std martianoff/gala/test` | Space-separated import paths the macros inject automatically (excluded from `deps`). `none` clears the set. |
| `# gazelle:gala_generation <on\|off>` | `on` | When `off`, the extension generates **no** GALA rules in this directory (inherited by subdirectories). Hands the subtree to manual wiring. Falsey spellings: `off`, `disabled`, `false`, `none`, `0`, `no`. |

Flags `-gala_prefix` and `-gala_helper` mirror the first two directives.

## Consumer setup — opting trees out

The extension only knows how to generate the standard `gala_library` /
`gala_binary` / `gala_test` shape. Some directories are hand-curated and the
extension must **not** touch them; mark each with the right directive:

- **Curated example / test fixtures** — trees of hand-authored `gala_exec_test`
  (with `expected=` / singular `src=`) or deliberate `importpath`s, and
  golden test-data (`.gala`/`.txt`) pairs. Put `# gazelle:gala_generation off`
  in the subtree root's `BUILD.bazel`. Without it, gazelle re-flows `src`→`srcs`,
  strips bespoke deps, and mints a spurious package-wide `gala_binary`.

- **Mixed GALA/Go packages** — these are generated **automatically**: the
  composite folds the hand-written `.go` into the `gala_library`'s `go_srcs` and
  resolves both source kinds' imports (see *Mixed GALA/Go packages* above), so
  no opt-out is needed in the common case. Opt out only if you want to
  hand-maintain a particular mixed package — `# gazelle:gala_generation off` in
  that directory hands the whole package (GALA and Go) to manual wiring.

- **Nested Bazel modules** (a subdirectory with its own `MODULE.bazel`) — add
  the directory to the **repo-root `.bazelignore`** so gazelle does not descend
  into and rewrite another module's BUILD files. This is gazelle's standard
  mechanism and applies to every language, not just GALA.

- **Anything gazelle should ignore wholesale** — `# gazelle:exclude <path>`
  (core directive) drops a file or directory from *all* languages.

- **Line endings** — commit a `.gitattributes` with `* text=auto eol=lf`.
  A Windows checkout (`autocrlf=true`) otherwise rewrites stored-LF BUILD files
  to CRLF, producing perpetual churn in gazelle's output.

- **Helper version** — the `gala` helper must support `gala imports --json`.
  An older binary fails every package with `--json unknown flag`. The default
  (`gala` on `PATH`) leaves BUILD generation at the mercy of whatever is
  installed, which is neither reproducible nor guaranteed to match the gala the
  toolchain transpiles with.

  **Recommended — drive the helper from the registered GALA toolchain.**
  `rules_gala` ships `gala_imports_helper`, which re-exports the toolchain's
  gala binary as a runnable. The helper that extracts imports is then *the same
  gala the toolchain builds with*, so generation is reproducible and never
  drifts from the gala version:

  ```starlark
  load("@rules_gala//gala:defs.bzl", "gala_imports_helper")

  gala_imports_helper(name = "gala_imports")

  gazelle(
      name = "gazelle",
      gazelle = ":gazelle_bin",
      data = [":gala_imports"],
      extra_args = ["-gala_helper=$(execpath :gala_imports)"],
  )
  ```

  Requires `rules_gala` ≥ 0.1.3.

  *Alternative* — pass any `$(execpath)` directly, e.g. a bazel-built
  `//cmd/gala:gala`. A relative `-gala_helper` is resolved against
  `BUILD_WORKSPACE_DIRECTORY` (which `bazel run //:gazelle` exports), so it
  points at the freshly built binary via the `bazel-out` convenience symlink
  (requires `gala_gazelle` ≥ 0.1.5). Use this only if you are not using the
  rules_gala toolchain.

## Helper contract

The extension invokes `<helper> imports --json <files…>` (working directory =
the package directory) and parses a JSON array:

```json
[
  {
    "file": "a.gala",
    "package": "main",
    "imports": [{"path": "fmt", "alias": "", "dot": false}],
    "error": ""
  }
]
```

Entries with a non-empty `"error"` are skipped (the helper could not parse that
file).

## Development

```sh
cd gazelle
go test ./...      # unit tests (testdata-driven Generate + Resolve)
```

Unit tests inject a fake helper that emits the JSON contract directly, so they
run without an installed `gala` binary.
