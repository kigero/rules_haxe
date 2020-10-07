"""Haxe build rules."""

load(":providers.bzl", "HaxeLibraryInfo", "HaxeProjectInfo")

def _determine_source_root(path):
    source_root = ""
    parts = path.split("/")
    for idx in range(len(parts)):
        if parts[idx] == "external":
            source_root += "external/{}/".format(parts[idx + 1])
    return source_root

def _find_direct_sources(ctx):
    rtrn = []
    if hasattr(ctx.files, "srcs"):
        rtrn += ctx.files.srcs

    for dep in ctx.attr.deps:
        haxe_dep = dep[HaxeProjectInfo]
        if haxe_dep == None:
            continue
        if hasattr(haxe_dep, "srcs"):
            rtrn += haxe_dep.srcs

    return rtrn

def _find_direct_resources(ctx):
    rtrn = []
    if hasattr(ctx.files, "resources"):
        rtrn += ctx.files.resources

    for dep in ctx.attr.deps:
        haxe_dep = dep[HaxeProjectInfo]
        if haxe_dep == None:
            continue
        if hasattr(haxe_dep, "resources"):
            rtrn += haxe_dep.resources

    return rtrn

def _find_library_name(ctx):
    if hasattr(ctx.attr, "library_name") and ctx.attr.library_name != "":
        return ctx.attr.library_name
    elif hasattr(ctx.attr, "executable_name") and ctx.attr.executable_name != "":
        return ctx.attr.executable_name
    else:
        for dep in ctx.attr.deps:
            haxe_dep = dep[HaxeProjectInfo]
            if haxe_dep == None:
                continue
            if haxe_dep.library_name != None and haxe_dep.library_name != "":
                return haxe_dep.library_name

    return ctx.attr.name

def _find_main_class(ctx):
    if hasattr(ctx.attr, "main_class") and ctx.attr.main_class != "":
        return ctx.attr.main_class
    else:
        for dep in ctx.attr.deps:
            haxe_dep = dep[HaxeProjectInfo]
            if haxe_dep == None:
                continue
            if haxe_dep.main_class != None and haxe_dep.main_class != "":
                return haxe_dep.main_class

    return None

def _create_hxml_map(ctx, for_test = False):
    """
    Create a dict containing haxe build parameters based on the input attributes from the calling rule.
    
    Args:
        ctx: Bazel context.
        for_test: True if build parameters for unit testing should be added, False otherwise.
    """
    hxml = {}

    hxml["for_test"] = for_test

    hxml["name"] = _find_library_name(ctx)
    hxml["target"] = ctx.attr.target if hasattr(ctx.attr, "target") else None
    hxml["debug"] = ctx.attr.debug if hasattr(ctx.attr, "debug") else False

    if for_test:
        hxml["main_class"] = "MainTest"
    else:
        hxml["main_class"] = _find_main_class(ctx)

    hxml["args"] = list()
    if hasattr(ctx.attr, "extra_args"):
        for arg in ctx.attr.extra_args:
            if not arg in hxml["args"]:
                hxml["args"].append(arg)

    hxml["libs"] = dict()
    if hxml["target"] == "java":
        hxml["libs"]["hxjava"] = "3.2.0"
    if hasattr(ctx.attr, "haxelibs"):
        for lib in ctx.attr.haxelibs:
            version = ctx.attr.haxelibs[lib]
            if version != None and version != "":
                if version.lower().find("http") == 0:
                    version = "git:{}".format(version)
                hxml["libs"][lib] = version
            else:
                fail("Explicit versioning is required for haxelibs.")

    hxml["classpaths"] = list()
    hxml["classpaths"].append("src/main/haxe")
    if for_test:
        hxml["classpaths"].append(ctx.var["BINDIR"])
        hxml["classpaths"].append("src/test/haxe")
    if hasattr(ctx.attr, "classpaths"):
        for p in ctx.attr.classpaths:
            hxml["classpaths"].append(p)

    hxml["source_files"] = list()
    for src in _find_direct_sources(ctx):
        hxml["source_files"].append(src.path)

    hxml["resources"] = dict()
    for resource in _find_direct_resources(ctx):
        name = resource.path
        name = name.replace("src/main/resources/", "")
        name = name.replace("src/test/resources/", "")
        parts = name.split("/")
        new_name = ""
        skip = False
        for idx in range(len(parts)):
            if skip:
                skip = False
                continue
            elif parts[idx] == "external":
                new_name = ""
                skip = True
            elif parts[idx] != "":
                if new_name != "":
                    new_name += "/"
                new_name += parts[idx]

        hxml["resources"][resource.path] = new_name

    hxml["c-args"] = list()
    if hxml["target"] == "java":
        if "haxe_java_target_version" in ctx.var:
            hxml["c-args"] += ["-source", ctx.var["haxe_java_target_version"], "-target", ctx.var["haxe_java_target_version"]]

    # Handle Dependencies
    for dep in ctx.attr.deps:
        haxe_dep = dep[HaxeLibraryInfo]
        if haxe_dep == None or haxe_dep.hxml == None:
            continue
        dep_hxml = haxe_dep.hxml
        for classpath in dep_hxml["classpaths"]:
            if classpath.startswith("external"):
                parts = classpath.split("/")
                new_classpath = ""
                for idx in range(len(parts)):
                    if parts[idx] == "external":
                        new_classpath = "external"
                    elif parts[idx] != "":
                        new_classpath += "/" + parts[idx]

                if not new_classpath in hxml["classpaths"]:
                    hxml["classpaths"].append(new_classpath)
            else:
                hxml["classpaths"].append("{}{}".format(_determine_source_root(dep_hxml["source_files"][0]), classpath))
        for lib in dep_hxml["libs"]:
            if not lib in hxml["libs"]:
                hxml["libs"][lib] = dep_hxml["libs"][lib]
        for resource in dep_hxml["resources"]:
            if not resource in hxml["resources"]:
                hxml["resources"][resource] = dep_hxml["resources"][resource]
        for arg in dep_hxml["args"]:
            if not arg in hxml["args"]:
                hxml["args"].append(arg)

    return hxml

def _create_build_hxml(ctx, toolchain, hxml, out_file, suffix = "", for_exec = False):
    """
    Create the build.hxml file based on the input hxml dict.
    
    Any Haxelibs that are specified in the hxml will be installed at this time.
    
    Args:
        ctx: Bazel context.
        toolchain: The Haxe toolchain instance.
        hxml: A dict containing HXML parameters; should be generated from `_create_hxml_map`.
        out_file: The output file that the build.hxml should be written to.
        suffix: Optional suffix to append to the build parameters.
        for_exec: Whether this build HXML is intended for executing the result of the build; this can ignore some errors
        that aren't an issue during execution.
    """

    # Determine if we're in a dependant build, and if so what the correct source root is.
    # This is fairly toxic.
    if for_exec or len(hxml["source_files"]) == 0:
        is_dependent_build = True
        source_root = ""
    else:
        is_dependent_build = hxml["source_files"][0].startswith("external")
        source_root = _determine_source_root(hxml["source_files"][0])

    # source_root = "external/{}/".format(hxml["name"]) if is_dependent_build else ""

    content = ""

    # Target
    if hxml["target"] == "neko":
        content += "--neko {}/{}neko/{}{}.n\n".format(ctx.var["BINDIR"], source_root, hxml["name"], suffix)
        hxml["output"] = "neko/{}{}.n".format(hxml["name"], suffix)
    elif hxml["target"] == "java":
        content += "--java {}/{}java/{}{}\n".format(ctx.var["BINDIR"], source_root, hxml["name"], suffix)

        output = "java/{}{}".format(hxml["name"], suffix)
        if hxml["main_class"] != None:
            mc = hxml["main_class"]
            if "." in mc:
                mc = mc[mc.rindex(".") + 1:]

            output += "/{}{}".format(mc, suffix)
        else:
            output += "/{}{}".format(hxml["name"], suffix)

        if hxml["debug"] != None:
            output += "-Debug"

        hxml["output"] = output + ".jar"
    else:
        fail("Invalid target '{}'".format(hxml["target"]))

    # Debug
    if hxml["debug"] != None:
        content += "-debug\n"

    # Classpaths
    for classpath in hxml["classpaths"]:
        if not classpath.startswith("external"):
            classpath = "{}{}".format(source_root, classpath)
        content += "-p {}\n".format(classpath)

    # Compiler Args
    for c_arg in hxml["c-args"]:
        content += "--c-arg {}\n".format(c_arg)

    # User Args
    for arg in hxml["args"]:
        content += "{}\n".format(arg)

    # Resources
    for path in hxml["resources"]:
        content += "--resource {}@{}\n".format(path, hxml["resources"][path])

    # Source or Main files
    if hxml["main_class"] != None:
        content += "-m {}\n".format(hxml["main_class"])
    else:
        for path in hxml["source_files"]:
            if is_dependent_build:
                path = path[len(source_root):]
            for classpath in hxml["classpaths"]:
                if path.startswith(classpath):
                    path = path[len(classpath) + 1:]
                    break
            content += path.replace(".hx", "").replace("/", ".") + "\n"

    count = 1
    build_files = list()

    if hxml["for_test"]:
        build_prefix = "{}-build-test.hxml".format(ctx.attr.name)
        path_prefix = "{}-path-test".format(ctx.attr.name)
    else:
        build_prefix = "{}-build.hxml".format(ctx.attr.name)
        path_prefix = "{}-path".format(ctx.attr.name)

    build_file_1 = ctx.actions.declare_file("{}.{}".format(build_prefix, count))
    count += 1
    build_files.append(build_file_1)

    for lib in hxml["libs"]:
        version = hxml["libs"][lib]
        content += "-L {}:{}\n".format(lib, version)

        path_file = toolchain.haxelib_install(
            ctx,
            lib,
            version,
        )
        count += 1
        build_files.append(path_file)

    # Write to a temporary file, then use run_shell to generate the required output file so that all the previous tasks are complete.
    ctx.actions.write(
        output = build_file_1,
        content = content,
    )

    ctx.actions.run_shell(
        outputs = [out_file],
        inputs = build_files,
        command = "mv {} {}".format(build_file_1.path, out_file.path),
    )

###############################################################################

def _haxe_library_impl(ctx):
    """
    Creates a haxe library using the given parameters.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    # Build the HXML file.
    hxml = _create_hxml_map(ctx)
    build_file = ctx.actions.declare_file("{}-build.hxml".format(ctx.attr.name))
    _create_build_hxml(ctx, toolchain, hxml, build_file, "-intermediate")
    intermediate = ctx.actions.declare_file(hxml["output"])

    # Do the compilation.
    runfiles = []
    for i, d in enumerate(ctx.attr.srcs):
        for f in d.files.to_list():
            runfiles.append(f)

    toolchain.compile(
        ctx,
        hxml = build_file,
        runfiles = runfiles,
        deps = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
        out = intermediate,
    )

    # Post process the output file.
    output = ctx.actions.declare_file(hxml["output"].replace("-intermediate", ""))

    if hxml["target"] == "java":
        toolchain.create_final_jar(
            ctx,
            _find_direct_sources(ctx),
            intermediate,
            output,
            ctx.attr.strip_haxe,
        )
    else:
        ctx.actions.run_shell(
            outputs = [output],
            inputs = [intermediate],
            command = "cp {} {}".format(intermediate.path, output.path),
            use_default_shell_env = True,
        )

    # Figure out the return from the rule.
    rtrn = [
        DefaultInfo(
            files = depset([output]),
            runfiles = ctx.runfiles(files = runfiles),
        ),
        HaxeLibraryInfo(
            info = struct(
                lib = output,
            ),
            hxml = hxml,
            deps = depset(
                direct = [dep[HaxeLibraryInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeLibraryInfo].deps for dep in ctx.attr.deps],
            ),
        ),
        HaxeProjectInfo(
            info = struct(),
            hxml = hxml,
            srcs = ctx.files.srcs,
            resources = ctx.files.resources,
            library_name = ctx.attr.library_name,
            deps = depset(
                direct = [dep[HaxeProjectInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeProjectInfo].deps for dep in ctx.attr.deps],
            ),
        ),
    ]

    # This allows java targets to use the results of this rule.
    if hxml["target"] == "java":
        java_deps = []
        for dep in ctx.attr.deps:
            if hasattr(dep, "JavaInfo"):
                java_deps.append(dep[JavaInfo])
        rtrn.append(JavaInfo(
            output_jar = output,
            compile_jar = output,
            deps = java_deps,
        ))

    return rtrn

haxe_library = rule(
    doc = "Create a library.",
    implementation = _haxe_library_impl,
    toolchains = ["@rules_haxe//:toolchain_type"],
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
    hxml = _create_hxml_map(ctx)
    build_file = ctx.actions.declare_file("{}-build.hxml".format(ctx.attr.name))
    _create_build_hxml(ctx, toolchain, hxml, build_file, for_exec = True)
    output = ctx.actions.declare_file(hxml["output"])

    # Do the compilation.
    runfiles = _find_direct_sources(ctx) + _find_direct_resources(ctx)

    toolchain.compile(
        ctx,
        hxml = build_file,
        runfiles = runfiles,
        deps = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
        out = output,
    )

    # Generate a launcher file.
    launcher_file = ctx.actions.declare_file("run-{}.bat".format(ctx.attr.name))
    toolchain.create_run_script(
        ctx,
        hxml["target"],
        output,
        launcher_file,
    )

    # Figure out the return from the rule.
    rtrn = [
        DefaultInfo(
            runfiles = ctx.runfiles(files = toolchain.internal.tools + [output, launcher_file]),
            executable = launcher_file,
        ),
        HaxeLibraryInfo(
            info = struct(
                lib = output,
            ),
            hxml = hxml,
            deps = depset(
                direct = [dep[HaxeLibraryInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeLibraryInfo].deps for dep in ctx.attr.deps],
            ),
        ),
        HaxeProjectInfo(
            info = struct(),
            hxml = hxml,
            srcs = ctx.files.srcs,
            resources = ctx.files.resources,
            library_name = ctx.attr.executable_name,
            deps = depset(
                direct = [dep[HaxeProjectInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeProjectInfo].deps for dep in ctx.attr.deps],
            ),
        ),
    ]

    # This allows java targets to use the results of this rule.
    if hxml["target"] == "java":
        java_deps = []
        for dep in ctx.attr.deps:
            if hasattr(dep, "JavaInfo"):
                java_deps.append(dep[JavaInfo])
        rtrn.append(JavaInfo(
            output_jar = output,
            compile_jar = output,
            deps = java_deps,
        ))

    return rtrn

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

def _haxelib_install_impl(ctx):
    """
    haxelib_install implementation.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    out_file = ctx.actions.declare_file("out.txt")

    toolchain.haxelib_install(
        ctx,
        ctx.attr.haxelib,
        ctx.attr.version,
        out_file,
    )

    return [
        DefaultInfo(
            files = depset([out_file]),
            runfiles = ctx.runfiles(collect_data = True),
        ),
        HaxeLibraryInfo(
            info = struct(
                out_file = out_file,
            ),
            deps = depset(
                direct = [dep[HaxeLibraryInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeLibraryInfo].deps for dep in ctx.attr.deps],
            ),
        ),
        HaxeProjectInfo(
            info = struct(),
            deps = depset(
                direct = [dep[HaxeProjectInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeProjectInfo].deps for dep in ctx.attr.deps],
            ),
        ),
    ]

haxelib_install = rule(
    doc = "Install a haxelib.",
    implementation = _haxelib_install_impl,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "haxelib": attr.string(
            mandatory = True,
            doc = "The haxelib to install.",
        ),
        "version": attr.string(
            doc = "The version or git repository of the haxelib to install.",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library",
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
        ctx.attr.srcs,
        test_file,
    )

    hxml = _create_hxml_map(ctx, for_test = True)

    build_file = ctx.actions.declare_file("{}-build-test.hxml".format(ctx.attr.name))
    _create_build_hxml(ctx, toolchain, hxml, build_file)

    lib = ctx.actions.declare_file(hxml["output"])
    toolchain.compile(
        ctx,
        hxml = build_file,
        runfiles = [test_file] + ctx.files.srcs,
        deps = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
        out = lib,
    )

    launcher_file = ctx.actions.declare_file("{}-launcher.bat".format(ctx.attr.name))
    toolchain.create_run_script(
        ctx,
        hxml["target"],
        lib,
        launcher_file,
    )

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(files = ctx.files.srcs + ctx.files.resources + ctx.files.runtime_deps + toolchain.internal.tools + [lib, launcher_file]),
            executable = launcher_file,
        ),
        HaxeLibraryInfo(
            info = struct(
            ),
            deps = depset(
                direct = [dep[HaxeLibraryInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeLibraryInfo].deps for dep in ctx.attr.deps],
            ),
        ),
        HaxeProjectInfo(
            info = struct(),
            hxml = hxml,
            srcs = ctx.files.srcs,
            resources = ctx.files.resources,
            library_name = ctx.attr.name,
            deps = depset(
                direct = [dep[HaxeProjectInfo].info for dep in ctx.attr.deps],
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
    hxml = _create_hxml_map(ctx)

    return [
        DefaultInfo(
            files = depset(direct = ctx.files.srcs + ctx.files.resources),
        ),
        HaxeProjectInfo(
            info = struct(),
            hxml = hxml,
            srcs = ctx.files.srcs if len(ctx.files.srcs) != 0 else _find_direct_sources(ctx),
            resources = ctx.files.resources if len(ctx.files.resources) != 0 else _find_direct_resources(ctx),
            library_name = ctx.attr.library_name,
            main_class = ctx.attr.main_class,
            deps = depset(
                direct = [dep[HaxeProjectInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeProjectInfo].deps for dep in ctx.attr.deps],
            ),
        ),
        HaxeLibraryInfo(
            info = struct(),
            hxml = hxml,
            deps = depset(
                direct = [dep[HaxeLibraryInfo].info for dep in ctx.attr.deps],
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
    hxml = _create_hxml_map(ctx)

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

    build_file_name = ctx.attr.hxml_name if hasattr(ctx.attr, "hxml_name") and ctx.attr.hxml_name != "" else "{}.hxml".format(ctx.attr.name)
    build_file = ctx.actions.declare_file(build_file_name)
    _create_build_hxml(ctx, toolchain, hxml, build_file)

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
            doc = """
            A list of directories that should use local references instead of 'external' references.
            
            Imagine you're creating a local 
            """,
        ),
    },
)
