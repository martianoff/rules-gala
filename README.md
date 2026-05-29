# rules_gala

Bazel rules and a bzlmod extension for the [GALA](https://github.com/martianoff/gala_simple) language.

This module also functions as a Bazel module registry that publishes `rules_gala` itself.

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

## License

Apache 2.0. See `LICENSE`.
