# Releasing a new version of rules_gala

The repo serves as both the source of `rules_gala` and a Bazel module
registry that publishes it. Releasing a version is a four-step manual
process.

## Versions vs. tags

Git tags in this repo are a **single shared namespace** across every
module it publishes (`rules_gala`, `gala_gazelle`, …), so the next free
tag is usually *not* equal to the next `rules_gala` version. Earlier
releases let the two diverge — module `0.1.2` shipped from tag `0.2.1`,
`0.1.3` from tag `0.2.3` — because `git tag <version>` collided with a
tag already taken by a `gala_gazelle` release.

**Going forward, keep them equal:** pick the next tag that is free across
*all* modules and use that same number as both the new module version
and the release tag (e.g. `0.2.6` shipped as module version `0.2.6` from
tag `0.2.6`). Find the highest tag in use with:

```bash
git tag --list | sort -V | tail
```

In the steps below, `<version>` is the new `rules_gala` module version
and `<tag>` is the git tag — equal for new releases.

## Steps

1. **Bump the version in `MODULE.bazel`** at the repo root to `<version>`.

2. **Create a registry entry** under `modules/rules_gala/<version>/`:

   ```bash
   cp -r modules/rules_gala/<previous version> modules/rules_gala/<version>
   cp MODULE.bazel modules/rules_gala/<version>/MODULE.bazel
   # Edit modules/rules_gala/<version>/source.json:
   #   - url          -> .../archive/refs/tags/<tag>.tar.gz
   #   - strip_prefix -> rules-gala-<tag>
   #   - leave integrity empty for now
   ```

   Add `<version>` to `modules/rules_gala/metadata.json`'s `"versions"`
   array.

3. **Commit, tag, and push.** Push the branch and the single new tag
   explicitly — avoid `git push --tags`, which would push every stray
   local tag:

   ```bash
   git add -A
   git commit -m "Release rules_gala <version>"
   git tag <tag>
   git push origin main
   git push origin <tag>
   ```

4. **Compute the integrity hash and update source.json**:

   ```bash
   curl -L -o /tmp/release.tar.gz \
     https://github.com/martianoff/rules-gala/archive/refs/tags/<tag>.tar.gz
   echo "sha256-$(openssl dgst -sha256 -binary /tmp/release.tar.gz | base64)"
   ```

   Paste the result into `modules/rules_gala/<version>/source.json`
   under `"integrity"`. Commit and push:

   ```bash
   git commit -am "Pin integrity for rules_gala <version>"
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
