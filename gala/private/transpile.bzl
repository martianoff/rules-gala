"""Transpile rules: gala_transpile, gala_transpile_package, gala_bootstrap_transpile.

Two paths exist for the non-bootstrap rules: a persistent-worker rule
(default) and a genrule fallback. The worker path keeps one transpiler
process per worker_key alive across a build, amortising analyzer
cold-start over every per-package transpile. The genrule path is the
escape hatch for diagnosing worker bugs.

Toggle at the build level:

    bazel build --@rules_gala//gala:use_persistent_worker=false //...
"""

_TOOLCHAIN = "@rules_gala//gala:toolchain_type"

# ---- shared helpers --------------------------------------------------------

def _gala_sources_label(dep):
    """Translate a gala_library label to its `_gala_sources` filegroup."""
    if ":" in dep:
        return dep + "_gala_sources"
    name = dep.split("/")[-1]
    return dep + ":" + name + "_gala_sources"

def _dep_search_shell_prelude(gala_deps):
    """Shell snippet that derives --search entries from dep file locations.

    For each gala_dep, expand $(locations <_gala_sources>) at action time
    to the on-disk path, then take the parent dir (the dep package dir)
    and grandparent (typically the dep module root). Both are appended,
    comma-separated, to _dep_search.

    This is uniform for in-repo deps (paths like
    examples/cross_file_block_lambda/crossfile/methods.gala) and cross-
    module deps (paths like bazel-out/.../external/<repo>+/some_pkg/foo.gala)
    because Bazel resolves the locations to real filesystem paths inside
    the genrule sandbox.

    Returns (prelude, expansion); both empty when gala_deps is empty.
    """
    if not gala_deps:
        return "", ""

    parts = ["_dep_search=\"\""]
    for dep in gala_deps:
        src_label = _gala_sources_label(dep)
        parts.append("_locs=\"$(locations %s)\"" % src_label)
        parts.append("_first=\"$${_locs%% *}\"")
        parts.append("_pkg_dir=\"$${_first%/*}\"")
        parts.append("_dep_search=\"$${_dep_search},$${_pkg_dir},$${_pkg_dir%/*}\"")

    return " ; ".join(parts) + " ; ", "$${_dep_search}"

# ---- persistent-worker rule -----------------------------------------------

def _gala_transpile_worker_impl(ctx):
    info = ctx.toolchains[_TOOLCHAIN].galainfo

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    if ctx.attr.batch:
        args.add("transpile-package")
        in_paths = [f.path for f in ctx.files.srcs]
        out_paths = [f.path for f in ctx.outputs.outs]
        args.add("--inputs=" + ",".join(in_paths))
        args.add("--outputs=" + ",".join(out_paths))
        outputs = list(ctx.outputs.outs)
    else:
        args.add("transpile")
        args.add("--input=" + ctx.file.src.path)
        args.add("--output=" + ctx.outputs.out.path)
        if ctx.files.package_files:
            args.add("--package-files=" + ",".join([f.path for f in ctx.files.package_files]))
        outputs = [ctx.outputs.out]

    search_paths = []

    go_mod = info.go_mod
    if go_mod:
        proj_root = go_mod.dirname or "."
        search_paths.append(proj_root)

    for dep_target in ctx.attr.gala_deps:
        files = dep_target[DefaultInfo].files.to_list()
        if not files:
            continue
        first = files[0]
        pkg_dir = first.dirname
        mod_root = pkg_dir.rsplit("/", 1)[0] if "/" in pkg_dir else pkg_dir
        if pkg_dir not in search_paths:
            search_paths.append(pkg_dir)
        if mod_root not in search_paths:
            search_paths.append(mod_root)

    args.add("--search=" + ",".join(search_paths))

    goroot = ctx.configuration.default_shell_env.get("GOROOT", "")
    if goroot:
        args.add("--goroot=" + goroot)

    direct_inputs = list(ctx.files.srcs) + list(ctx.files.package_files) + list(ctx.files.extra_srcs)
    if go_mod:
        direct_inputs.append(go_mod)
    if not ctx.attr.batch:
        direct_inputs.append(ctx.file.src)

    transitive_inputs = [d[DefaultInfo].files for d in ctx.attr.gala_deps]
    transitive_inputs.append(info.all_gala_sources)

    inputs = depset(direct = direct_inputs, transitive = transitive_inputs)

    ctx.actions.run(
        executable = info.gala_worker,
        arguments = [args],
        inputs = inputs,
        outputs = outputs,
        mnemonic = "GalaTranspile",
        progress_message = "GalaTranspile %s" % ctx.label,
        execution_requirements = {
            "supports-workers": "1",
            "no-sandbox": "1",
        },
        # Inherit GOROOT/PATH the bazel client declared via --action_env so
        # go/importer can find the Go SDK. Without this the importer falls
        # back to `any` parameters on every Go callback and downstream
        # compilation breaks.
        use_default_shell_env = True,
        env = {"GOROOT": goroot} if goroot else {},
    )

    return [DefaultInfo(files = depset(outputs))]

gala_transpile_worker_single = rule(
    implementation = _gala_transpile_worker_impl,
    toolchains = [_TOOLCHAIN],
    attrs = {
        "src": attr.label(allow_single_file = [".gala"], mandatory = True),
        "out": attr.output(mandatory = True),
        "srcs": attr.label_list(allow_files = [".gala"]),  # unused
        "package_files": attr.label_list(allow_files = [".gala"], default = []),
        "extra_srcs": attr.label_list(allow_files = True, default = []),
        "gala_deps": attr.label_list(default = []),
        "batch": attr.bool(default = False),
    },
)

gala_transpile_worker_batch = rule(
    implementation = _gala_transpile_worker_impl,
    toolchains = [_TOOLCHAIN],
    attrs = {
        "src": attr.label(allow_single_file = [".gala"]),  # unused
        "srcs": attr.label_list(allow_files = [".gala"], mandatory = True),
        "outs": attr.output_list(mandatory = True),
        "package_files": attr.label_list(allow_files = [".gala"], default = []),
        "extra_srcs": attr.label_list(allow_files = True, default = []),
        "gala_deps": attr.label_list(default = []),
        "batch": attr.bool(default = True),
    },
)

# ---- public macros ---------------------------------------------------------

def gala_transpile(name, src, out = None, package_files = [], extra_srcs = [], gala_deps = [], use_worker = True):
    """Transpile a single .gala file to Go.

    Args:
        name: Target name.
        src: The .gala source file.
        out: Output .go file name (defaults to `<name>.go`).
        package_files: Sibling .gala files in the same package, needed
            for cross-file type resolution within the package.
        extra_srcs: Additional sources made available during transpile
            (e.g., hand-written Go files in the same package).
        gala_deps: Other gala_library labels. Their `_gala_sources`
            filegroups are auto-included so the transpiler can resolve
            types from those packages.
        use_worker: If True (default), use the persistent-worker rule.
            Set False to fall back to the genrule path.
    """
    if not out:
        out = name + ".go"

    if use_worker:
        dep_src_labels = [_gala_sources_label(d) for d in gala_deps]
        gala_transpile_worker_single(
            name = name,
            src = src,
            out = out,
            package_files = package_files,
            extra_srcs = extra_srcs,
            gala_deps = dep_src_labels,
            visibility = ["//visibility:public"],
        )
        return

    _gala_transpile_genrule(
        name = name,
        src = src,
        out = out,
        package_files = package_files,
        extra_srcs = extra_srcs,
        gala_deps = gala_deps,
    )

def gala_transpile_package(name, srcs, outs = None, extra_srcs = [], gala_deps = [], use_worker = True):
    """Transpile every .gala file in a package in one transpiler invocation.

    Faster than per-file because the analyzer cache is shared across
    files (no redundant re-analysis of imports).
    """
    if not outs:
        outs = [s.replace(".gala", ".gen.go") for s in srcs]

    if len(srcs) != len(outs):
        fail("gala_transpile_package: srcs and outs must have the same length")

    if use_worker:
        dep_src_labels = [_gala_sources_label(d) for d in gala_deps]
        gala_transpile_worker_batch(
            name = name,
            srcs = srcs,
            outs = outs,
            extra_srcs = extra_srcs,
            gala_deps = dep_src_labels,
            visibility = ["//visibility:public"],
        )
        return

    _gala_transpile_package_genrule(
        name = name,
        srcs = srcs,
        outs = outs,
        extra_srcs = extra_srcs,
        gala_deps = gala_deps,
    )

# ---- genrule fallback ------------------------------------------------------
#
# The genrule path is opt-out (use_worker = False on either macro).
# It uses native.genrule directly and reaches into the toolchain via a
# trampoline rule (_gala_tool_paths) that exposes paths as
# make-variables, because genrules cannot resolve toolchains.

def _gala_tool_paths_impl(ctx):
    info = ctx.toolchains[_TOOLCHAIN].galainfo
    gala_exec = info.gala_binary.executable
    go_mod = info.go_mod
    runfiles = ctx.runfiles(files = [gala_exec] + ([go_mod] if go_mod else []) + info.all_gala_sources.to_list())
    return [
        DefaultInfo(
            files = depset([gala_exec] + ([go_mod] if go_mod else [])),
            runfiles = runfiles,
        ),
        platform_common.TemplateVariableInfo({
            "GALA_BINARY": gala_exec.path,
            "GALA_GOMOD": go_mod.path if go_mod else "",
        }),
    ]

_gala_tool_paths = rule(
    implementation = _gala_tool_paths_impl,
    toolchains = [_TOOLCHAIN],
)

def _gala_transpile_genrule(name, src, out, package_files, extra_srcs, gala_deps):
    tools_target = name + "_tools"
    _gala_tool_paths(name = tools_target, visibility = ["//visibility:private"])

    pf_flag = ""
    if package_files:
        pf_flag = " --package-files " + ",".join(["$(location %s)" % f for f in package_files])

    dep_srcs = [_gala_sources_label(d) for d in gala_deps]
    dep_prelude, dep_search_expansion = _dep_search_shell_prelude(gala_deps)

    native.genrule(
        name = name,
        srcs = [src] + package_files + extra_srcs + dep_srcs,
        outs = [out],
        cmd = "{prelude}$(GALA_BINARY) --input $(location {src}) --output $@ --search $$(dirname $(GALA_GOMOD)){dep_search}{pf} --goroot=$${{GOROOT:-}}".format(
            prelude = dep_prelude,
            src = src,
            dep_search = dep_search_expansion,
            pf = pf_flag,
        ),
        toolchains = [":" + tools_target],
        tools = [":" + tools_target],
        visibility = ["//visibility:public"],
        tags = ["no-sandbox"],
    )

def _gala_transpile_package_genrule(name, srcs, outs, extra_srcs, gala_deps):
    tools_target = name + "_tools"
    _gala_tool_paths(name = tools_target, visibility = ["//visibility:private"])

    dep_srcs = [_gala_sources_label(d) for d in gala_deps]
    dep_prelude, dep_search_expansion = _dep_search_shell_prelude(gala_deps)
    inputs_flag = ",".join(["$(location %s)" % s for s in srcs])
    outputs_flag = ",".join(["$(location %s)" % o for o in outs])

    native.genrule(
        name = name,
        srcs = srcs + extra_srcs + dep_srcs,
        outs = outs,
        cmd = "{prelude}$(GALA_BINARY) transpile-package --inputs {inputs} --outputs {outputs} --search $$(dirname $(GALA_GOMOD)){dep_search} --goroot=$${{GOROOT:-}}".format(
            prelude = dep_prelude,
            inputs = inputs_flag,
            outputs = outputs_flag,
            dep_search = dep_search_expansion,
        ),
        toolchains = [":" + tools_target],
        tools = [":" + tools_target],
        visibility = ["//visibility:public"],
        tags = ["no-sandbox"],
    )

# ---- bootstrap -------------------------------------------------------------

def _gala_bootstrap_transpile_impl(ctx):
    info = ctx.toolchains[_TOOLCHAIN].galainfo
    if not info.gala_bootstrap:
        fail("gala_bootstrap_transpile requires a toolchain whose " +
             "`gala_bootstrap` attribute is set. The toolchain in use " +
             "does not provide one.")

    args = ctx.actions.args()
    args.add("--input", ctx.file.src)
    args.add("--output", ctx.outputs.out)

    go_mod = info.go_mod
    search_path = (go_mod.dirname or ".") if go_mod else "."
    args.add("--search", search_path)

    if ctx.files.package_files:
        args.add("--package-files", ",".join([f.path for f in ctx.files.package_files]))

    goroot = ctx.configuration.default_shell_env.get("GOROOT", "")
    if goroot:
        args.add("--goroot=" + goroot)

    direct_inputs = [ctx.file.src] + list(ctx.files.package_files)
    if go_mod:
        direct_inputs.append(go_mod)
    inputs = depset(direct = direct_inputs, transitive = [info.all_gala_sources])

    ctx.actions.run(
        executable = info.gala_bootstrap,
        arguments = [args],
        inputs = inputs,
        outputs = [ctx.outputs.out],
        mnemonic = "GalaBootstrapTranspile",
        progress_message = "GalaBootstrapTranspile %s" % ctx.label,
        execution_requirements = {"no-sandbox": "1"},
        use_default_shell_env = True,
        env = {"GOROOT": goroot} if goroot else {},
    )

    return [DefaultInfo(files = depset([ctx.outputs.out]))]

_gala_bootstrap_transpile = rule(
    implementation = _gala_bootstrap_transpile_impl,
    toolchains = [_TOOLCHAIN],
    attrs = {
        "src": attr.label(allow_single_file = [".gala"], mandatory = True),
        "out": attr.output(mandatory = True),
        "package_files": attr.label_list(allow_files = [".gala"], default = []),
    },
)

def gala_bootstrap_transpile(name, src, out = None, package_files = []):
    """Transpile a .gala file with the bootstrap binary.

    Used only when building the stdlib itself, to avoid the chicken-and-
    egg dependency between the full transpiler and the stdlib it links
    against. Most consumers should never need this.
    """
    if not out:
        out = name + ".go"
    _gala_bootstrap_transpile(
        name = name,
        src = src,
        out = out,
        package_files = package_files,
        visibility = ["//visibility:public"],
    )
