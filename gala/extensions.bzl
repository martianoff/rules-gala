"""Bzlmod extension for GALA dependency management.

Loads GALA module deps declared in a `gala.mod` file:

    gala = use_extension("@rules_gala//gala:extensions.bzl", "gala")
    gala.from_file(gala_mod = "//:gala.mod")
    use_repo(gala, "com_github_example_utils")

Go deps declared in `gala.mod` (lines marked `// go`) are skipped — they
are managed by Gazelle's `go_deps` extension reading the generated
`go.mod`. Run `gala mod tidy` to regenerate `go.mod` from `gala.mod`.
"""

load("//gala:repositories.bzl", "gala_module")
load("//gala/private:gala_mod_parser.bzl", "module_path_to_repo_name", "parse_gala_mod")

def _gala_extension_impl(module_ctx):
    root_direct_deps = []
    root_direct_dev_deps = []

    for mod in module_ctx.modules:
        for from_file in mod.tags.from_file:
            gala_mod_content = module_ctx.read(from_file.gala_mod)
            deps = parse_gala_mod(gala_mod_content)

            for path, version, is_go in deps:
                if is_go:
                    continue

                repo_name = module_path_to_repo_name(path)

                gala_module(
                    name = repo_name,
                    module_path = path,
                    version = version,
                )

                if mod.is_root:
                    root_direct_deps.append(repo_name)

        for dep in mod.tags.dependency:
            if dep.go:
                continue

            repo_name = module_path_to_repo_name(dep.path)

            gala_module(
                name = repo_name,
                module_path = dep.path,
                version = dep.version,
                sum = dep.sum if hasattr(dep, "sum") else None,
            )

            if mod.is_root:
                if dep.dev:
                    root_direct_dev_deps.append(repo_name)
                else:
                    root_direct_deps.append(repo_name)

    return module_ctx.extension_metadata(
        root_module_direct_deps = root_direct_deps,
        root_module_direct_dev_deps = root_direct_dev_deps,
    )

_from_file = tag_class(
    attrs = {
        "gala_mod": attr.label(
            mandatory = True,
            doc = "Label to the gala.mod file.",
        ),
    },
    doc = "Load GALA dependencies from a gala.mod file.",
)

_dependency = tag_class(
    attrs = {
        "path": attr.string(
            mandatory = True,
            doc = "Module path (e.g., github.com/example/utils).",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Version (e.g., v1.2.3).",
        ),
        "sum": attr.string(
            doc = "Expected hash from gala.sum (optional).",
        ),
        "go": attr.bool(
            default = False,
            doc = "If true, this is a Go dependency (handled by go_deps).",
        ),
        "dev": attr.bool(
            default = False,
            doc = "If true, this is a dev-only dependency.",
        ),
    },
    doc = "Declare a single GALA dependency.",
)

gala = module_extension(
    implementation = _gala_extension_impl,
    tag_classes = {
        "from_file": _from_file,
        "dependency": _dependency,
    },
    doc = """GALA dependency management extension.

Load dependencies from gala.mod:

    gala = use_extension("@rules_gala//gala:extensions.bzl", "gala")
    gala.from_file(gala_mod = "//:gala.mod")
    use_repo(gala, "com_github_example_utils")

Or declare them inline:

    gala.dependency(path = "github.com/example/utils", version = "v1.2.3")
""",
)
