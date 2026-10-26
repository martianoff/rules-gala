# galop end-to-end check

Runs `galop_parser` from this checkout with a **real galop release**, the one
`MODULE.bazel` names, downloaded and verified through the `galop` extension
and the checksums in [`galop/private/versions.bzl`](../../galop/private/versions.bzl).
rules_gala's own tests use a fake galop; this check is what shows that the
declared outputs and the generated code match the real tool.

It is a separate Bazel module, and the root `.bazelignore` skips `e2e/`, so
`bazel test //...` at the repository root stays hermetic. Run it by hand from
this directory:

```shell
cd e2e/galop
bazel test //...
```

| Target             | Flavor   | Checks                                                                                           |
|--------------------|----------|--------------------------------------------------------------------------------------------------|
| `calc_native_test` | `native` | The generated lexer and parser compile with no dependencies, parse `1 + 22 - 3` and report a syntax error. |
| `calc_antlr_test`  | `antlr`  | galop writes `calc_galop_parser.go` and `calc_galop_lexer.go` in package `calc`. They are not compiled, because they need ANTLR's Go runtime and ANTLR's own generated parser in the same package. |

`Calc.g4` has no left recursion because galop does not support left-recursive
rules yet.

When `versions.bzl` gains a galop release, bump `galop.toolchain(version = ...)`
in `MODULE.bazel` and run this check before releasing rules_gala.
