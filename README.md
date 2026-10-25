# rules_gala

Bazel rules and a bzlmod extension for the [GALA](https://github.com/martianoff/gala_simple) language.

This module also functions as a Bazel module registry that publishes `rules_gala` itself.

## Requirements

**Bazel 9 or newer**, declared as `bazel_compatibility` on the module so an
older Bazel fails with a clear message rather than a confusing one. That is
what rules_gala is developed and tested against.

It is also where the **repo contents cache** is on by default: a store of
*extracted* external repositories shared across workspaces. Before it,
`--repository_cache` cached only the downloaded archive, so every Bazel output
base unpacked its own copy of every external repo. Because Bazel keys the
output base on the *path* of the workspace, that means once per git worktree —
and the pinned Go SDK a GALA build needs is ~207 MB each time. A developer with
a handful of worktrees was paying gigabytes for one toolchain version.

The `--repo_contents_cache` flag does exist from Bazel 8.3, but there it
defaults to the empty string, and an empty string means *disabled* — so on 8.x
you get the saving only by passing the flag explicitly.

Use [Bazelisk](https://github.com/bazelbuild/bazelisk) and pin the version in a
`.bazelversion`; a directly installed `bazel` ignores that file.

## Setup

In your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_gala", version = "0.1.0")
bazel_dep(name = "gala", version = "1.0.0")

# Register the toolchain shipped by the `gala` language module.
register_toolchains("@gala//tools/toolchain:gala_toolchain")

# Optional: resolve GALA module deps from gala.mod.
gala = use_extension("@rules_gala//gala:extensions.bzl", "gala")
gala.from_file(gala_mod = "//:gala.mod")
```

In your `.bazelrc`:

```
common --registry=https://raw.githubusercontent.com/martianoff/rules-gala/main/
common --registry=https://bcr.bazel.build
```

The custom registry must come first so it wins for `rules_gala`.

## Rules

Load from `@rules_gala//gala:defs.bzl`:

| Rule                       | Purpose                                                                  |
|----------------------------|--------------------------------------------------------------------------|
| `gala_library`             | Build a GALA library (`go_library` under the hood).                      |
| `gala_binary`              | Build a GALA executable.                                                 |
| `gala_test`                | Test rule that auto-discovers `Test*` functions in `.gala` files.        |
| `gala_exec_test`           | Test rule that compares program stdout against a checked-in expected file. |
| `gala_unit_test`           | Wrap a `gala_binary` as a test (exit-code-only).                         |
| `gala_transpile`           | Transpile a single `.gala` file to `.go`.                                |
| `gala_transpile_package`   | Batch-transpile all `.gala` files in a package in one process.           |
| `gala_bootstrap_transpile` | Transpile with the bootstrap binary (stdlib use only).                   |

## Example

```starlark
load("@rules_gala//gala:defs.bzl", "gala_library", "gala_test")

gala_library(
    name = "mylib",
    srcs = ["mylib.gala"],
    importpath = "example.com/mylib",
    visibility = ["//visibility:public"],
)

gala_test(
    name = "mylib_test",
    srcs = ["mylib_test.gala"],
    deps = [":mylib"],
)
```

## Toolchain

The rules resolve everything through `@rules_gala//gala:toolchain_type`. The `gala` language module ships an implementation backed by its in-repo transpiler binaries, stdlib filegroup, and test framework. To provide your own toolchain, instantiate `gala_toolchain` from `@rules_gala//gala:toolchain.bzl`:

```starlark
load("@rules_gala//gala:toolchain.bzl", "gala_toolchain")

gala_toolchain(
    name = "my_gala_toolchain_impl",
    gala_binary       = "//path/to:gala",
    gala_worker       = "//path/to:gala_worker",
    gala_bootstrap    = "//path/to:gala_bootstrap",
    test_runner       = "//path/to:gala_test_runner",
    test_gen          = "//path/to:gala_test_gen",
    all_gala_sources  = "//:all_gala_sources",
    go_mod            = "//:go.mod",
)

toolchain(
    name = "my_gala_toolchain",
    toolchain = ":my_gala_toolchain_impl",
    toolchain_type = "@rules_gala//gala:toolchain_type",
)
```

## galop

[galop](https://github.com/martianoff/galop) is a parser generator written in
GALA: it reads ANTLR `.g4` grammars and generates fast Go parsers. Its command
line mirrors ANTLR's `antlr4` tool. `@rules_gala//galop` wraps it in a
`galop_parser` rule whose outputs drop straight into a `go_library`.

### Setup

In your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_gala", version = "<version>")

galop = use_extension("@rules_gala//galop:extensions.bzl", "galop")
galop.toolchain(version = "0.1.0")
use_repo(galop, "galop_toolchains")
register_toolchains("@galop_toolchains//:all")
```

This registers prebuilt galop release binaries for the platforms galop
publishes: **linux-amd64, darwin-arm64 and windows-amd64**. Only the binary for
the exec platform actually used is downloaded, and each is checked against the
SHA-256 table in [`galop/private/versions.bzl`](galop/private/versions.bzl).
On any other exec platform (e.g. linux-arm64, darwin-amd64) there is no
toolchain and `galop_parser` fails toolchain resolution; register your own
toolchain there (see below).

`galop.toolchain` also takes `sha256 = {"darwin_arm64": ..., "linux_amd64":
..., "windows_amd64": ...}`, to use a galop release this rules_gala version
does not list yet (hashes from the release's `checksums-sha256.txt`), and
`base_url`, to fetch from a mirror laid out as `<base_url>/<version>/<asset>`.
If the root module calls `galop.toolchain`, its version wins; otherwise the
highest version requested by any module is used.

### Usage

```starlark
load("@rules_go//go:def.bzl", "go_library")
load("@rules_gala//galop:defs.bzl", "galop_parser")

galop_parser(
    name = "calc_parser",
    grammar = "Calc.g4",
    package = "calc",
)

go_library(
    name = "calc",
    srcs = [":calc_parser"],
    importpath = "example.com/calc",
)
```

The rule runs

```
galop -o <dir> -Xexact-output-dir -Dlanguage=Go -Dflavor=<flavor> [-package <p>]
      -listener|-no-listener -visitor|-no-visitor [-D<k>=<v> ...] [galop_opts ...] <grammar>
```

| Attribute    | Default       | Meaning                                                                                                  |
|--------------|---------------|----------------------------------------------------------------------------------------------------------|
| `grammar`    | (required)    | The `.g4` file. Its base name must equal the grammar name (`Calc.g4` → `grammar Calc;`), as galop enforces. |
| `kind`       | `"combined"`  | `combined` (`grammar T;`), `lexer` (`lexer grammar TLexer;`) or `parser` (`parser grammar TParser;`).      |
| `package`    | `""`          | Go package of the generated code (`-package`); empty leaves galop's default.                             |
| `flavor`     | `"companion"` | `-Dflavor`: `companion` or `standalone`.                                                                  |
| `listener`   | `True`        | `-listener` / `-no-listener`.                                                                             |
| `visitor`    | `False`       | `-visitor` / `-no-visitor`.                                                                               |
| `defines`    | `{}`          | Extra `-D<key>=<value>` options. `language` and `flavor` are rejected: the rule sets them.               |
| `galop_opts` | `[]`          | Extra raw arguments (e.g. `["-Werror"]`), placed before the grammar.                                      |
| `imports`    | `[]`          | Other `.g4` / `.tokens` files the grammar imports or names in `tokenVocab`, declared as action inputs. galop does not support `import` or `tokenVocab` yet (it reports error 500), so this is for when it does. |

`kind` exists because Bazel must declare a rule's output files before the
action runs, and which files galop writes depends on the kind of grammar,
which the rule cannot see without reading the file.

### Output files

The prefix is the grammar name lowercased; for a `parser` grammar a trailing
`Parser` is trimmed, for a `lexer` grammar a trailing `Lexer` (as in ANTLR's
Go target). Files are written to a directory named after the target.

| Grammar                    | `companion`                                  | `standalone` adds (parser and combined grammars only)                                                 |
|----------------------------|----------------------------------------------|--------------------------------------------------------------------------------------------------------|
| `grammar Calc;`            | `calc_galop_parser.go`, `calc_galop_lexer.go` | `calc_listener.go`, `calc_base_listener.go` (with `listener`); `calc_visitor.go`, `calc_base_visitor.go` (with `visitor`) |
| `parser grammar CalcParser;` | `calc_galop_parser.go`                      | as above                                                                                               |
| `lexer grammar CalcLexer;` | `calc_galop_lexer.go`                        | nothing                                                                                                |

In the `companion` flavor the generated code sits next to ANTLR's own
generated package, which already has the listener and visitor, so those flags
add no files. The naming lives in one function,
[`galop/private/naming.bzl`](galop/private/naming.bzl) (also exported as
`galop_go_outputs` from `defs.bzl`).

### Why a prebuilt binary rather than building galop from source

The toolchain from the `galop` extension uses galop's **release binaries**, not
a `gala_binary` built from galop's sources. The GALA compiler is itself going
to generate its parser with galop, and in Bazel the `gala` module builds the
GALA compiler from source (`@gala//tools/toolchain:gala_toolchain`). If
`galop_parser` built galop from source, it would need the GALA toolchain, so
the GALA compiler, so the compiler's parser, so `galop_parser` again — a
dependency cycle. A prebuilt binary breaks that cycle. It also means projects
that only want a generated Go parser need no GALA (or Go) toolchain to run
galop, and it skips compiling galop on every clean build.

### Using galop built from source (or any other executable)

`galop_parser` only needs *a* toolchain of type
`@rules_gala//galop:toolchain_type`, so you can register your own instead of,
or ahead of, the extension's — for example in galop's own repository, which
builds `//cmd/galop` from source:

```starlark
load("@rules_gala//galop:toolchain.bzl", "galop_toolchain")

galop_toolchain(
    name = "galop_from_source_impl",
    galop = "//cmd/galop",  # any executable label
)

toolchain(
    name = "galop_from_source",
    toolchain = ":galop_from_source_impl",
    toolchain_type = "@rules_gala//galop:toolchain_type",
)
```

and `register_toolchains("//path/to:galop_from_source")` in `MODULE.bazel`.

### Status: waiting for the first galop release

galop has not published a release yet, so the checksum table in
`galop/private/versions.bzl` is empty and `galop.toolchain(version = ...)`
fails with a message listing exactly what to add. Before the extension works
out of the box:

1. galop publishes its first release (bare semver tag such as `0.1.0`, with
   `galop-linux-amd64`, `galop-darwin-arm64`, `galop-windows-amd64.exe` and
   `checksums-sha256.txt`).
2. Its three hashes are added to `GALOP_VERSIONS` in
   `galop/private/versions.bzl`.
3. A rules_gala release ships that table (see [RELEASING.md](RELEASING.md)).

Until then a custom toolchain, or `galop.toolchain(sha256 = {...})`, works.

The rule itself is tested in [`galop/tests`](galop/tests) against a fake galop
(`bazel test //galop/...`).

## License

Apache 2.0. See `LICENSE`.
