# Releasing a new version of rules_gala

The repo serves as both the source of `rules_gala` and a Bazel module
registry that publishes it. Releasing a version is a four-step manual
process.

## Steps

1. **Bump the version in `MODULE.bazel`** at the repo root.

2. **Create a registry entry** under `modules/rules_gala/<new version>/`:

   ```bash
   cp -r modules/rules_gala/<previous version> modules/rules_gala/<new version>
   cp MODULE.bazel modules/rules_gala/<new version>/MODULE.bazel
   # Edit modules/rules_gala/<new version>/source.json:
   #   - url should reference the new tag tarball
   #   - strip_prefix should be `rules-gala-<new version>`
   #   - leave integrity empty for now
   ```

   Add the new version to `modules/rules_gala/metadata.json`'s
   `"versions"` array.

3. **Commit, tag, and push**:

   ```bash
   git add -A
   git commit -m "Release <new version>"
   git tag <new version>
   git push origin main --tags
   ```

4. **Compute the integrity hash and update source.json**:

   ```bash
   curl -L -o /tmp/release.tar.gz \
     https://github.com/martianoff/rules-gala/archive/refs/tags/<new version>.tar.gz
   echo "sha256-$(openssl dgst -sha256 -binary /tmp/release.tar.gz | base64)"
   ```

   Paste the result into `modules/rules_gala/<new version>/source.json`
   under `"integrity"`. Commit and push:

   ```bash
   git commit -m "Pin integrity for <new version>"
   git push origin main
   ```

That's it. Consumers point their `.bazelrc` at the registry:

```
common --registry=https://raw.githubusercontent.com/martianoff/rules-gala/main/
common --registry=https://bcr.bazel.build
```

…and `bazel_dep(name = "rules_gala", version = "<new version>")` will
resolve transparently.

---

# Publishing a new gala (language) version

The same registry also publishes the `gala` language module (the
transpiler binaries, stdlib, and toolchain registration that
`@gala//...` references resolve against). The `modules/gala/` directory
holds the version entries.

Run this after each new release tag in
[`martianoff/gala`](https://github.com/martianoff/gala).

## Steps

1. **Create a registry entry** under `modules/gala/<new version>/`:

   ```bash
   mkdir -p modules/gala/<new version>
   # Copy the MODULE.bazel from the gala_simple checkout at the tag:
   cp /path/to/gala/MODULE.bazel modules/gala/<new version>/MODULE.bazel
   ```

   Create `modules/gala/<new version>/source.json`:

   ```json
   {
       "url": "https://github.com/martianoff/gala/archive/refs/tags/<new version>.tar.gz",
       "integrity": "",
       "strip_prefix": "gala-<new version>"
   }
   ```

   Add the new version to `modules/gala/metadata.json`'s `"versions"`
   array.

2. **Compute and pin the integrity hash**:

   ```bash
   curl -L -o /tmp/gala.tar.gz \
     https://github.com/martianoff/gala/archive/refs/tags/<new version>.tar.gz
   echo "sha256-$(openssl dgst -sha256 -binary /tmp/gala.tar.gz | base64)"
   ```

   Paste into `modules/gala/<new version>/source.json` under
   `"integrity"`.

3. **Commit and push**:

   ```bash
   git add modules/gala/
   git commit -m "Publish gala <new version> to registry"
   git push origin main
   ```

Consumers can then write:

```starlark
bazel_dep(name = "gala", version = "<new version>")
register_toolchains("@gala//tools/toolchain:gala_toolchain")
register_toolchains("@gala//tools/toolchain:gala_bootstrap_toolchain")
```

## Note on the first entry

The `0.50.0` tag predates the `//tools/toolchain` package that
`register_toolchains(...)` references. The first gala version published
to this registry must be the first tag cut **after** the
`rules_gala` extraction landed in `martianoff/gala`. The `modules/gala/`
directory ships empty until that release.

---

# Publishing a new gala_gazelle (Gazelle extension) version

`gala_gazelle` is the Gazelle language extension that generates and
maintains GALA `BUILD` targets. Unlike `rules_gala`, it lives in a
**subdirectory** of this repo (`gazelle/`) and is published as its own
bzlmod module, so the registry entry's `source.json` references the
`rules-gala` release tarball with a `gazelle`-scoped `strip_prefix`.

## Steps

1. **Create a registry entry** under `modules/gala_gazelle/<new version>/`:

   ```bash
   mkdir -p modules/gala_gazelle/<new version>
   cp gazelle/MODULE.bazel modules/gala_gazelle/<new version>/MODULE.bazel
   ```

   The `MODULE.bazel` in the registry entry must be byte-identical to
   `gazelle/MODULE.bazel` in the tagged tree.

   Create `modules/gala_gazelle/<new version>/source.json`, pointing at
   the `rules-gala` tag tarball that contains this `gazelle/` tree and
   stripping into the subdirectory:

   ```json
   {
       "url": "https://github.com/martianoff/rules-gala/archive/refs/tags/<rules-gala tag>.tar.gz",
       "integrity": "",
       "strip_prefix": "rules-gala-<rules-gala tag>/gazelle"
   }
   ```

   Add the new version to `modules/gala_gazelle/metadata.json`'s
   `"versions"` array.

2. **Compute and pin the integrity hash** after the `rules-gala` tag is
   pushed:

   ```bash
   curl -L -o /tmp/rules-gala.tar.gz \
     https://github.com/martianoff/rules-gala/archive/refs/tags/<rules-gala tag>.tar.gz
   echo "sha256-$(openssl dgst -sha256 -binary /tmp/rules-gala.tar.gz | base64)"
   ```

   Paste into `modules/gala_gazelle/<new version>/source.json` under
   `"integrity"`, then commit and push.

Consumers then add the extension and build a `gazelle_binary` that lists
the GALA language among its `languages`:

```starlark
bazel_dep(name = "gala_gazelle", version = "<new version>")
```

```starlark
load("@gazelle//:def.bzl", "gazelle_binary")

gazelle_binary(
    name = "gazelle_bin",
    languages = [
        "@gazelle//language/go",
        "@gala_gazelle//gala",
    ],
)
```

## Note on the first entry

The `0.1.0` `source.json` ships with an empty `integrity` and a
placeholder `rules-gala` tag; pin both once the first `rules-gala` tag
that includes `gazelle/` is cut.
