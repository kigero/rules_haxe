"""Haxe build rules."""

load(":providers.bzl", "HaxeLibraryInfo", "HaxeProjectInfo")
load(":utils.bzl", "calc_provider_response", "create_build_hxml", "create_hxml_map", "find_direct_docsources", "find_direct_resources", "find_direct_sources")

def _haxe_library_impl(ctx):
    """
    Creates a haxe library using the given parameters.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    # Build the HXML file.
    hxml = create_hxml_map(ctx, toolchain)
    build_file = ctx.actions.declare_file("{}-build.hxml".format(ctx.attr.name))
    create_build_hxml(ctx, toolchain, hxml, build_file, "-intermediate")
    intermediate = ctx.actions.declare_directory(hxml["output_dir"])

    # Do the compilation.
    runfiles = []
    for i, d in enumerate(ctx.attr.srcs):
        for f in d.files.to_list():
            runfiles.append(f)

    for file in find_direct_sources(ctx):
        runfiles.append(file)

    toolchain.compile(
        ctx,
        hxml = build_file,
        runfiles = runfiles,
        deps = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
        out = intermediate,
    )

    # Post process the output file.
    output = ctx.actions.declare_file(hxml["output_dir"].replace("-intermediate", ""))
    output_file = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, hxml["output_file"])) if "output_file" in hxml else None

    if hxml["target"] == "java":
        toolchain.create_final_jar(
            ctx,
            find_direct_sources(ctx),
            intermediate,
            output,
            hxml["output_file"],
            ctx.attr.strip_haxe,
            output_file = output_file,
        )
    else:
        inputs = [intermediate]
        hxcpp_include_dir = None
        if hxml["target"] == "cpp":
            hxcpp_include_dir = ctx.actions.declare_directory("hxcpp_includes")
            toolchain.copy_cpp_includes(ctx, hxcpp_include_dir)
            inputs.append(hxcpp_include_dir)

        cmd = "mkdir -p {} && cp -r {}/* {}".format(output.path, intermediate.path, output.path)
        if hxcpp_include_dir != None:
            cmd += " && cp -r {}/* {}/{}/include".format(hxcpp_include_dir.path, output.path, hxml["name"])

        ctx.actions.run_shell(
            outputs = [output, output_file],
            inputs = inputs,
            command = cmd,
            use_default_shell_env = True,
        )
    return calc_provider_response(ctx, toolchain, hxml, output, output_file = output_file)

haxe_library = rule(
    doc = "Create a library.",
    implementation = _haxe_library_impl,
    toolchains = ["@rules_haxe//:toolchain_type"],
    fragments = ["cpp"],
    attrs = {
        "library_name": attr.string(
            doc = "The name of the library to create; if not provided the rule name will be used.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Haxe source code.  Must be included unless depending on a haxe_project_definition rule or other Haxe project.",
        ),
        "resources": attr.label_list(
            allow_files = True,
            doc = "Resources to include in the final build.",
        ),
        "target": attr.string(
            default = "neko",
            doc = "Target platform.",
        ),
        "haxelibs": attr.string_dict(
            doc = "A dict of haxelib names to versions or git repositories (either the version or git repo is required) that the library depends on.",
        ),
        "debug": attr.bool(
            doc = "If True, will compile the library with debug flags on.",
        ),
        "classpaths": attr.string_list(
            doc = "Any extra classpaths to add to the build file.",
        ),
        "strip_haxe": attr.bool(
            default = True,
            doc = "Whether to strip haxe classes from the resultant library.  Supported platforms: java",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library.",
        ),
        "extra_args": attr.string_list(
            doc = "Any extra HXML arguments to pass to the compiler.  Each entry in this array will be added on its own line.",
        ),
    },
)

###############################################################################

def _haxe_executable_impl(ctx):
    """
    Creates a haxe executable using the given parameters.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    # Build the HXML file.
    hxml = create_hxml_map(ctx, toolchain)
    build_file = ctx.actions.declare_file("{}-build.hxml".format(ctx.attr.name))
    create_build_hxml(ctx, toolchain, hxml, build_file, for_exec = True)
    dir = ctx.actions.declare_directory(hxml["output_dir"])

    # Do the compilation.
    runfiles = find_direct_sources(ctx) + find_direct_resources(ctx)

    toolchain.compile(
        ctx,
        hxml = build_file,
        runfiles = runfiles,
        deps = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
        out = dir,
    )

    # Generate a launcher file.
    launcher_file = ctx.actions.declare_file("run-{}.bat".format(ctx.attr.name))
    toolchain.create_run_script(
        ctx,
        hxml["target"],
        hxml["output_file"],
        launcher_file,
    )

    return calc_provider_response(ctx, toolchain, hxml, dir, launcher_file)

haxe_executable = rule(
    doc = "Create a binary.",
    implementation = _haxe_executable_impl,
    executable = True,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "executable_name": attr.string(
            doc = "The name of the binary to create; if not provided the rule name will be used.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Haxe source code.  Must be included unless depending on a haxe_project_definition rule or other Haxe project.",
        ),
        "resources": attr.label_list(
            allow_files = True,
            doc = "Resources to include in the final build.",
        ),
        "target": attr.string(
            default = "neko",
            doc = "Target platform.",
        ),
        "haxelibs": attr.string_dict(
            doc = "A dict of haxelib names to versions or git repositories (either the version or git repo is required) that the library depends on.",
        ),
        "debug": attr.bool(
            doc = "If True, will compile the library with debug flags on.",
        ),
        "classpaths": attr.string_list(
            doc = "Any extra classpaths to add to the build file.",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library.",
        ),
        "extra_args": attr.string_list(
            doc = "Any extra HXML arguments to pass to the compiler.  Each entry in this array will be added on its own line.",
        ),
        "main_class": attr.string(
            doc = "Fully qualified class name of the main class to build; if not provided, it must be provided by a dependency.",
        ),
    },
)

###############################################################################

def _haxe_test_impl(ctx):
    """
    haxe_test implementation.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    test_file = ctx.actions.declare_file("MainTest.hx")
    toolchain.create_test_class(
        ctx,
        ctx.files.srcs,
        test_file,
    )

    hxml = create_hxml_map(ctx, toolchain, for_test = True)

    build_file = ctx.actions.declare_file("{}-build-test.hxml".format(ctx.attr.name))
    create_build_hxml(ctx, toolchain, hxml, build_file)

    dir = ctx.actions.declare_directory(hxml["output_dir"])

    # Do the compilation.
    runfiles = [test_file] + find_direct_sources(ctx) + find_direct_resources(ctx)

    toolchain.compile(
        ctx,
        hxml = build_file,
        runfiles = runfiles,
        deps = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
        out = dir,
    )

    launcher_file = ctx.actions.declare_file("{}-launcher.bat".format(ctx.attr.name))
    toolchain.create_run_script(
        ctx,
        hxml["target"],
        hxml["output_file"],
        launcher_file,
    )

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(files = ctx.files.srcs + ctx.files.resources + ctx.files.runtime_deps + toolchain.internal.tools + [dir, launcher_file]),
            executable = launcher_file,
        ),
        HaxeLibraryInfo(
            deps = depset(
                direct = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
                transitive = [dep[HaxeLibraryInfo].deps for dep in ctx.attr.deps],
            ),
        ),
        HaxeProjectInfo(
            hxml = hxml,
            srcs = ctx.files.srcs,
            resources = ctx.files.resources,
            library_name = ctx.attr.name,
            deps = depset(
                direct = [dep[HaxeProjectInfo] for dep in ctx.attr.deps],
                transitive = [dep[HaxeProjectInfo].deps for dep in ctx.attr.deps],
            ),
        ),
    ]

haxe_test = rule(
    doc = "Compile with Haxe and run unit tests.",
    implementation = _haxe_test_impl,
    test = True,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = "Haxe source code",
        ),
        "resources": attr.label_list(
            allow_files = True,
            doc = "Resources to embed within the Haxe test classes.",
        ),
        "runtime_deps": attr.label_list(
            allow_files = True,
            doc = "Any files or dependencies that should be made available to the test executor.",
        ),
        "target": attr.string(
            default = "neko",
            doc = "Target platform.",
        ),
        "haxelibs": attr.string_dict(
            doc = "A dict of haxelib names to versions or git repositories (either the version or git repo is required) that the unit tests depend on.",
        ),
        "classpaths": attr.string_list(
            doc = "Any extra classpaths to add to the build file.",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library",
        ),
        "extra_args": attr.string_list(
            doc = "Any extra HXML arguments to pass to the compiler.  Each entry in this array will be added on its own line.",
        ),
    },
)

###############################################################################

def _haxe_project_definition(ctx):
    """
    _haxe_source_definition implementation.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    # Build the HXML file.
    hxml = create_hxml_map(ctx, toolchain)

    return [
        DefaultInfo(
            files = depset(direct = ctx.files.srcs + ctx.files.doc_srcs + ctx.files.resources, transitive = [dep[DefaultInfo].files for dep in ctx.attr.deps]),
        ),
        HaxeProjectInfo(
            hxml = hxml,
            srcs = ctx.files.srcs if len(ctx.files.srcs) != 0 else find_direct_sources(ctx),
            doc_srcs = ctx.files.doc_srcs if len(ctx.files.doc_srcs) != 0 else find_direct_docsources(ctx),
            resources = ctx.files.resources if len(ctx.files.resources) != 0 else find_direct_resources(ctx),
            library_name = ctx.attr.library_name,
            main_class = ctx.attr.main_class,
            deps = depset(
                direct = [dep[HaxeProjectInfo] for dep in ctx.attr.deps],
                transitive = [dep[HaxeProjectInfo].deps for dep in ctx.attr.deps],
            ),
        ),
        HaxeLibraryInfo(
            hxml = hxml,
            deps = depset(
                direct = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
                transitive = [dep[HaxeLibraryInfo].deps for dep in ctx.attr.deps],
            ),
        ),
    ]

haxe_project_definition = rule(
    doc = "Define the baseline project definition, which can be used in other projects to not depend specifically on a particular target output.",
    implementation = _haxe_project_definition,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "library_name": attr.string(
            doc = "The name of the library to create; if not provided the rule name will be used.",
        ),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = "Haxe source code.",
        ),
        "doc_srcs": attr.label_list(
            allow_files = True,
            doc = "Extra source files used to document the source code.  Feels like there should be a better way to do this.",
        ),
        "resources": attr.label_list(
            allow_files = True,
            doc = "Resources to include in the final build.",
        ),
        "target": attr.string(
            default = "neko",
            doc = "Target platform.",
        ),
        "haxelibs": attr.string_dict(
            doc = "A dict of haxelib names to versions or git repositories (either the version or git repo is required) that the library depends on.",
        ),
        "debug": attr.bool(
            doc = "If True, will compile the library with debug flags on.",
        ),
        "classpaths": attr.string_list(
            doc = "Any extra classpaths to add to the build file.",
        ),
        "strip_haxe": attr.bool(
            default = True,
            doc = "Whether to strip haxe classes from the resultant library.  Supported platforms: java",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo, HaxeProjectInfo],
            doc = "Direct dependencies of the library.",
        ),
        "extra_args": attr.string_list(
            doc = "Any extra HXML arguments to pass to the compiler.  Each entry in this array will be added on its own line.",
        ),
        "main_class": attr.string(
            doc = "Fully qualified class name of the main class to build.",
        ),
    },
)

###############################################################################

def _resolve_path(local_refs, workspace_path, path):
    if path.startswith("external"):
        parts = path.split("/")
        if parts[1] in local_refs:
            return "{}/{}".format(local_refs[parts[1]], "/".join(parts[2:]))
        else:
            return "{}/{}".format(workspace_path, path)

    return path

def _haxe_gen_hxml(ctx):
    """
    _haxe_gen_hxml implementation.
    
    Args:
        ctx: Bazel context.
    """
    if "bazel_project_dir" not in ctx.var:
        fail("Must set the absolute path to the bazel project directory (e.g. 'bazel-myproject') with --define=bazel_project_dir=`pwd`/bazel-myproject or --define=bazel_project_dir=%cd%/bazel-myproject")

    bazel_workspace_path = ctx.var["bazel_project_dir"]
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    # Build the HXML file.
    hxml = create_hxml_map(ctx, toolchain)

    # Update references to external resources.
    temp_classpaths = []
    for classpath in hxml["classpaths"]:
        new_classpath = _resolve_path(ctx.attr.local_references, bazel_workspace_path, classpath)
        temp_classpaths.append(new_classpath)
        if new_classpath.find("external") == -1 and new_classpath.endswith("src/main/haxe"):
            temp_classpaths.append(new_classpath.replace("src/main/haxe", "src/test/haxe"))
    hxml["classpaths"] = temp_classpaths

    temp_resources = {}
    for resource_path in hxml["resources"]:
        new_res_path = _resolve_path(ctx.attr.local_references, bazel_workspace_path, resource_path)
        temp_resources[new_res_path] = hxml["resources"][resource_path]
    hxml["resources"] = temp_resources

    hxml["source_files"] = []

    build_file_name = ctx.attr.hxml_name if hasattr(ctx.attr, "hxml_name") and ctx.attr.hxml_name != "" else "{}.hxml".format(ctx.attr.name)
    build_file = ctx.actions.declare_file(build_file_name)
    create_build_hxml(ctx, toolchain, hxml, build_file)

    return [
        DefaultInfo(
            files = depset([build_file]),
        ),
    ]

haxe_gen_hxml = rule(
    doc = "Generate an HXML file for a particular configuration.  This is useful to configure the VSHaxe plugin of VSCode.",
    implementation = _haxe_gen_hxml,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "hxml_name": attr.string(
            doc = "The name of the hxml to create; if not provided the rule name will be used.",
        ),
        "library_name": attr.string(
            doc = "The name of the library to use within the hxml file; if not provided the rule name will be used.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Haxe source code.  Must be included unless depending on a haxe_project_definition rule or other Haxe project.",
        ),
        "target": attr.string(
            default = "neko",
            doc = "Target platform.",
        ),
        "haxelibs": attr.string_dict(
            doc = "A dict of haxelib names to versions or git repositories (either the version or git repo is required) that the library depends on.",
        ),
        "debug": attr.bool(
            doc = "If True, will include the debug flag.",
        ),
        "classpaths": attr.string_list(
            doc = "Any extra classpaths to add to the build file.",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library.",
        ),
        "local_references": attr.string_dict(
            doc = "A list of directories that should use local references instead of 'external' references.",
        ),
    },
)

###############################################################################

def _haxe_dox(ctx):
    """
    _haxe_dox implementation.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    # Build the HXML file.
    hxml = create_hxml_map(ctx, toolchain)

    xml_file = ctx.actions.declare_file("{}.xml".format(hxml["name"]))
    hxml["target"] = ""
    hxml["args"].append("--xml {}".format(xml_file.path))
    hxml["args"].append("-D doc-gen")
    hxml["libs"]["dox"] = "1.5.0"

    build_file_name = ctx.attr.hxml_name if hasattr(ctx.attr, "hxml_name") and ctx.attr.hxml_name != "" else "{}.hxml".format(ctx.attr.name)
    build_file = ctx.actions.declare_file(build_file_name)
    create_build_hxml(ctx, toolchain, hxml, build_file)

    # Do the compilation.
    runfiles = find_direct_sources(ctx) + find_direct_resources(ctx)

    toolchain.compile(
        ctx,
        hxml = build_file,
        runfiles = runfiles,
        deps = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
        out = xml_file,
    )

    return [
        DefaultInfo(
            files = depset(direct = [xml_file]),
        ),
    ]

haxe_dox = rule(
    doc = "Generate the DOX XML configuration file for a project.",
    implementation = _haxe_dox,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "hxml_name": attr.string(
            doc = "The name of the hxml to create; if not provided the rule name will be used.",
        ),
        "library_name": attr.string(
            doc = "The name of the library to use within the hxml file; if not provided the rule name will be used.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Haxe source code.  Must be included unless depending on a haxe_project_definition rule or other Haxe project.",
        ),
        "haxelibs": attr.string_dict(
            doc = "A dict of haxelib names to versions or git repositories (either the version or git repo is required) that the library depends on.",
        ),
        "debug": attr.bool(
            doc = "If True, will include the debug flag.",
        ),
        "classpaths": attr.string_list(
            doc = "Any extra classpaths to add to the build file.",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library.",
        ),
    },
)

###############################################################################
def _haxe_gen_docs_from_dox(ctx):
    """
    _haxe_gen_docs_from_dox implementation.
    
    Args:
        ctx: Bazel context.
    """
    out_dir = ctx.actions.declare_directory("{}-docs".format(ctx.file.dox_file.basename))
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    toolchain.postprocess_dox(ctx, out_dir)

    return [
        DefaultInfo(
            files = depset(direct = [out_dir]),
        ),
    ]

haxe_gen_docs_from_dox = rule(
    doc = "Generate java files from a Dox file; this is useful when using a multi-project/language documentation gneerator that doesn't directly support Haxe (e.g. doxygen).",
    implementation = _haxe_gen_docs_from_dox,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "dox_file": attr.label(
            allow_single_file = True,
            doc = "The path to the dox file to generate from.",
        ),
        "root_pkg": attr.string(
            doc = "Root package to generate documentation for.",
            default = "*",
        ),
    },
)

###############################################################################

def _haxe_gather_doc_srcs(ctx):
    """
    _haxe_gather_doc_srcs implementation.
    
    Args:
        ctx: Bazel context.
    """
    docs = find_direct_docsources(ctx)

    return [
        DefaultInfo(
            files = depset(direct = docs),
        ),
    ]

haxe_gather_doc_srcs = rule(
    doc = "Gather any documentation files defined in the project or its dependencies.",
    implementation = _haxe_gather_doc_srcs,
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library.",
        ),
    },
)

###############################################################################

def _haxe_std_lib(ctx):
    """
    _haxe_std_lib implementation.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    build_source_file = ctx.actions.declare_file("StdBuild.hx")
    toolchain.create_std_build(
        ctx,
        ctx.attr.target,
        build_source_file,
    )

    hxml = create_hxml_map(ctx, toolchain, for_std_build = True)
    hxml["classpaths"].append(build_source_file.dirname)
    hxml["args"].append("--dce no")

    # Handle the case where we're building in an external directory.
    if hxml["external_dir"] != "":
        ext_idx = build_source_file.path.find("external/")
        hxml["external_dir"] = build_source_file.path[ext_idx:-11]

    build_file = ctx.actions.declare_file("{}-std-build.hxml".format(ctx.attr.name))
    create_build_hxml(ctx, toolchain, hxml, build_file, suffix = "-intermediate")

    intermediate = ctx.actions.declare_directory(hxml["output_dir"])

    # Do the compilation.
    runfiles = [build_source_file] + find_direct_sources(ctx) + find_direct_resources(ctx)

    toolchain.compile(
        ctx,
        hxml = build_file,
        runfiles = runfiles,
        out = intermediate,
    )

    # Post process the output file.
    output = ctx.actions.declare_file(hxml["output_dir"].replace("-intermediate", ""))
    output_file = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, hxml["output_file"])) if "output_file" in hxml else None

    if hxml["target"] == "java":
        toolchain.create_final_jar(
            ctx,
            find_direct_sources(ctx),
            intermediate,
            output,
            hxml["output_file"],
            False,
            output_file = output_file,
        )
    else:
        inputs = [intermediate]
        hxcpp_include_dir = None
        if hxml["target"] == "cpp":
            hxcpp_include_dir = ctx.actions.declare_directory("hxcpp_includes")
            toolchain.copy_cpp_includes(ctx, hxcpp_include_dir)
            inputs.append(hxcpp_include_dir)

        cmd = "mkdir -p {} && cp -r {}/* {}".format(output.path, intermediate.path, output.path)
        if hxcpp_include_dir != None:
            cmd += " && cp -r {}/* {}/{}/include".format(hxcpp_include_dir.path, output.path, hxml["name"])

        ctx.actions.run_shell(
            outputs = [output, output_file],
            inputs = inputs,
            command = cmd,
            use_default_shell_env = True,
        )
    return calc_provider_response(ctx, toolchain, hxml, output, output_file = output_file, library_name = "StdBuild")

haxe_std_lib = rule(
    doc = "Generate the haxe standard library such that it can be used as a dependency.",
    implementation = _haxe_std_lib,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "target": attr.string(
            default = "neko",
            doc = "Target platform.",
        ),
    },
)
