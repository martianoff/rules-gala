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
