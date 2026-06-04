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
bazel_dep(name = "gala_gazelle", version = "0.1.0")
```

Then build a `gazelle_binary` that bundles the GALA language alongside any
others you use, and an invocation target, in a `BUILD.bazel`:

```starlark
load("@gazelle//:def.bzl", "gazelle", "gazelle_binary")

gazelle_binary(
    name = "gazelle_bin",
    languages = [
        "@gazelle//language/go",      # optional: keep Go support
        "@gala_gazelle//gala",        # GALA support
    ],
)

# gazelle:gala_prefix github.com/you/project
gazelle(
    name = "gazelle",
    gazelle = ":gazelle_bin",
)
```

Run it with `bazel run //:gazelle`.

The helper binary must be discoverable. By default the extension shells out to
`gala` on `PATH`; override with the `-gala_helper` flag or the
`# gazelle:gala_helper` directive (see below).

## What it generates

Per directory containing `.gala` files:

- **`gala_library`** for the non-test sources, with `importpath` derived from
  the configured prefix plus the directory's repo-relative path, and
  `visibility = ["//visibility:public"]`.
- **`gala_binary`** instead of a library when a source declares `package main`
  and defines a zero-argument `main()`.
- **`gala_test`** for the directory's `*_test.gala` files.

`srcs` are sorted; `deps` are resolved from each file's GALA imports.

### Mixed GALA/Go packages

A package that places hand-written Go sources (`.go`, not the generated
`.gen.go` outputs) **alongside** `.gala` files cannot be expressed as a plain
`gala_library`: rules_gala compiles it by transpiling each `.gala` to `.gen.go`
(`gala_bootstrap_transpile`) and bundling the generated Go together with the
hand-written `.go` in a single `go_library`. That composite wiring is outside
what this extension generates.

When the extension sees a hand-written `.go` file in a directory, it therefore
**does not** emit a `gala_library`/`gala_binary` for that package (doing so would
silently drop the `.go` sources and collide with the `go_library` on the same
directory-base name). It logs that the package is mixed and leaves the library
to manual wiring. Pure-GALA `*_test.gala` framework tests are unaffected and are
still managed.

## Dependency resolution

For every GALA import in a rule's sources:

- **In-repo packages** (under the `gala_prefix`) resolve to in-repo labels —
  preferring an indexed `gala_library` with a matching `importpath`, otherwise
  `//<relpath>`.
- **GALA stdlib / external packages** (under `gala_stdlib_prefix`, default
  `martianoff/gala`) resolve to the matching in-repo package if one exists, and
  otherwise to `@<gala_stdlib_repo>//<relpath>` (default repo `gala`).
- **Go stdlib and other non-GALA imports** (`fmt`, `strings`, …) are skipped.
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

- **Mixed GALA/Go packages** — a package whose `.gala` is transpiled to
  `.gen.go` (`gala_bootstrap_transpile`) and bundled with hand-written `.go`
  into one `go_library`. The extension already skips emitting a `gala_library`
  when it sees a hand-written `.go` (see *Mixed GALA/Go packages* above), but
  the `go_library`'s hand-authored `deps` reference generated sources gazelle
  can't see — so also keep the **Go** language from re-resolving them, e.g.
  `# gazelle:exclude **/*.gen.go` or `# gazelle:gala_generation off` plus a Go
  directive, or hand-maintain the package and exclude it entirely.

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
  An older binary fails every package with `--json unknown flag`.

  Rather than depend on whatever `gala` is on `PATH`, drive the helper from a
  bazel-built binary (the gala toolchain's output) so the version always
  matches the tree. Pass its `$(execpath)` to the `gazelle` rule and add it to
  `data`:

  ```starlark
  gazelle(
      name = "gazelle",
      gazelle = ":gazelle_bin",
      extra_args = ["-gala_helper=$(execpath //cmd/gala:gala)"],
      data = ["//cmd/gala:gala"],
  )
  ```

  A relative `-gala_helper` like this is resolved against
  `BUILD_WORKSPACE_DIRECTORY` (which `bazel run //:gazelle` exports), so it
  points at the freshly built binary via the `bazel-out` convenience symlink.
  Requires `gala_gazelle` ≥ 0.1.5.

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
