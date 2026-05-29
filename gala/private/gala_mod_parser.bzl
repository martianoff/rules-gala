"""Parse `gala.mod` and convert module paths to Bazel repo names."""

def _split_whitespace(s):
    return [p for p in s.split(" ") if p]

def parse_gala_mod(content):
    """Parse gala.mod content into a list of (path, version, is_go) tuples."""
    requires = []
    in_require_block = False

    for line in content.split("\n"):
        line = line.strip()

        if not line:
            continue

        is_go = "// go" in line

        if "//" in line:
            line = line[:line.index("//")].strip()

        if line == "require (" or line.startswith("require("):
            in_require_block = True
            continue

        if line == ")":
            in_require_block = False
            continue

        if line.startswith("require ") and "(" not in line:
            parts = _split_whitespace(line[8:])
            if len(parts) >= 2:
                requires.append((parts[0], parts[1], is_go))
            continue

        if in_require_block:
            parts = _split_whitespace(line)
            if len(parts) >= 2:
                requires.append((parts[0], parts[1], is_go))

    return requires

def module_path_to_repo_name(module_path):
    """Convert a module path to a valid Bazel repository name.

    Example: github.com/example/utils -> com_github_example_utils
    """
    name = module_path.replace(".", "_").replace("/", "_").replace("-", "_")
    parts = name.split("_")
    if len(parts) >= 2 and parts[0] in ["github", "gitlab", "bitbucket"]:
        parts = [parts[1], parts[0]] + parts[2:]
    return "_".join(parts)
