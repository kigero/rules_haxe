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

def _find_direct_docsources(ctx):
    rtrn = []
    if hasattr(ctx.files, "doc_srcs"):
        rtrn += ctx.files.doc_srcs

    for dep in ctx.attr.deps:
        haxe_dep = dep[HaxeProjectInfo]
        if haxe_dep == None:
            continue
        if hasattr(haxe_dep, "doc_srcs"):
            rtrn += haxe_dep.doc_srcs

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
    elif hxml["target"] == "cpp":
        hxml["libs"]["hxcpp"] = "4.1.15"
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
    if for_exec or len(hxml["source_files"]) == 0 or len(ctx.files.srcs) == 0:
        is_dependent_build = True
        source_root = ""
    else:
        is_dependent_build = hxml["source_files"][0].startswith("external")
        source_root = _determine_source_root(hxml["source_files"][0])

    # source_root = "external/{}/".format(hxml["name"]) if is_dependent_build else ""

    content = ""

    # Target
    hxml["output_dir"] = "{}{}".format(ctx.attr.name, suffix)
    if hxml["target"] == "neko":
        content += "--neko {}/{}{}/{}.n\n".format(ctx.var["BINDIR"], source_root, hxml["output_dir"], hxml["name"])
        hxml["output_file"] = "{}.n".format(hxml["name"], suffix)
    elif hxml["target"] == "python":
        content += "--python {}/{}{}/{}.py\n".format(ctx.var["BINDIR"], source_root, hxml["output_dir"], hxml["name"])
        hxml["output_file"] = "{}.py".format(hxml["name"], suffix)
    elif hxml["target"] == "php":
        content += "--php {}/{}{}/{}\n".format(ctx.var["BINDIR"], source_root, hxml["output_dir"], hxml["name"])
        hxml["output_file"] = "{}".format(hxml["name"], suffix)
    elif hxml["target"] == "cpp":
        content += "--cpp {}/{}{}/{}\n".format(ctx.var["BINDIR"], source_root, hxml["output_dir"], hxml["name"])
        output = "{}".format(hxml["name"])
        if hxml["main_class"] != None:
            mc = hxml["main_class"]
            if "." in mc:
                mc = mc[mc.rindex(".") + 1:]

            output += "/{}".format(mc)
        else:
            output += "/{}".format(hxml["name"])

        if hxml["debug"] != None:
            output += "-Debug"

        hxml["output_file"] = output + ".exe"
    elif hxml["target"] == "java":
        content += "--java {}/{}{}/{}\n".format(ctx.var["BINDIR"], source_root, hxml["output_dir"], hxml["name"])

        output = "{}".format(hxml["name"])
        if hxml["main_class"] != None:
            mc = hxml["main_class"]
            if "." in mc:
                mc = mc[mc.rindex(".") + 1:]

            output += "/{}".format(mc)
        else:
            output += "/{}".format(hxml["name"])

        if hxml["debug"] != None:
            output += "-Debug"

        hxml["output_file"] = output + ".jar"

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

def _calc_provider_response(ctx, toolchain, hxml, out_dir, launcher_file = None):
    runfiles = [out_dir]
    if launcher_file != None:
        runfiles.append(launcher_file)
        runfiles += toolchain.internal.tools

    rtrn = [
        DefaultInfo(
            files = depset([out_dir] + _find_direct_sources(ctx)),
            runfiles = ctx.runfiles(files = runfiles),
            executable = launcher_file,
        ),
        HaxeLibraryInfo(
            info = struct(
                lib = out_dir,
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
            library_name = ctx.attr.executable_name if hasattr(ctx.attr, "executable_name") else ctx.attr.library_name,
            deps = depset(
                direct = [dep[HaxeProjectInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeProjectInfo].deps for dep in ctx.attr.deps],
            ),
        ),
    ]

    # Create target-specific responses
    if hxml["target"] == "java":
        java_out = ctx.actions.declare_file("java-deps/{}/{}".format(hxml["output_dir"], hxml["output_file"]))
        ctx.actions.run_shell(
            outputs = [java_out],
            inputs = [out_dir],
            command = "cp {}/{} {}".format(out_dir.path, hxml["output_file"], java_out.path),
            use_default_shell_env = True,
        )

        java_deps = []
        for dep in ctx.attr.deps:
            if hasattr(dep, "JavaInfo"):
                java_deps.append(dep[JavaInfo])
        rtrn.append(JavaInfo(
            output_jar = java_out,
            compile_jar = java_out,
            deps = java_deps,
        ))
    elif hxml["target"] == "python":
        rtrn.append(PyInfo(
            transitive_sources = depset([out_dir]),
        ))

    return rtrn

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
    intermediate = ctx.actions.declare_directory(hxml["output_dir"])

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
    output = ctx.actions.declare_file(hxml["output_dir"].replace("-intermediate", ""))

    if hxml["target"] == "java":
        toolchain.create_final_jar(
            ctx,
            _find_direct_sources(ctx),
            intermediate,
            output,
            hxml["output_file"],
            ctx.attr.strip_haxe,
        )
    else:
        ctx.actions.run_shell(
            outputs = [output],
            inputs = [intermediate],
            command = "cp -r {} {}".format(intermediate.path, output.path),
            use_default_shell_env = True,
        )

    return _calc_provider_response(ctx, toolchain, hxml, output)

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
    dir = ctx.actions.declare_directory(hxml["output_dir"])

    # Do the compilation.
    runfiles = _find_direct_sources(ctx) + _find_direct_resources(ctx)

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

    return _calc_provider_response(ctx, toolchain, hxml, dir, launcher_file)

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
        ctx.files.srcs,
        test_file,
    )

    hxml = _create_hxml_map(ctx, for_test = True)

    build_file = ctx.actions.declare_file("{}-build-test.hxml".format(ctx.attr.name))
    _create_build_hxml(ctx, toolchain, hxml, build_file)

    dir = ctx.actions.declare_directory(hxml["output_dir"])

    # Do the compilation.
    runfiles = [test_file] + _find_direct_sources(ctx) + _find_direct_resources(ctx)

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
            files = depset(direct = ctx.files.srcs + ctx.files.doc_srcs + ctx.files.resources, transitive = [dep[DefaultInfo].files for dep in ctx.attr.deps]),
        ),
        HaxeProjectInfo(
            info = struct(),
            hxml = hxml,
            srcs = ctx.files.srcs if len(ctx.files.srcs) != 0 else _find_direct_sources(ctx),
            doc_srcs = ctx.files.doc_srcs if len(ctx.files.doc_srcs) != 0 else _find_direct_docsources(ctx),
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

    hxml["source_files"] = []

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

###############################################################################

def _haxe_dox(ctx):
    """
    _haxe_dox implementation.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    # Build the HXML file.
    hxml = _create_hxml_map(ctx)

    xml_file = ctx.actions.declare_file("{}.xml".format(hxml["name"]))
    hxml["target"] = ""
    hxml["args"].append("--xml {}".format(xml_file.path))
    hxml["args"].append("-D doc-gen")
    hxml["libs"]["dox"] = "1.5.0"

    build_file_name = ctx.attr.hxml_name if hasattr(ctx.attr, "hxml_name") and ctx.attr.hxml_name != "" else "{}.hxml".format(ctx.attr.name)
    build_file = ctx.actions.declare_file(build_file_name)
    _create_build_hxml(ctx, toolchain, hxml, build_file)

    # Do the compilation.
    runfiles = _find_direct_sources(ctx) + _find_direct_resources(ctx)

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

    ctx.actions.run_shell(
        inputs = [ctx.file.dox_file],
        outputs = [out_dir],
        command = "python3 {} {} {} {}".format(ctx.file._postprocess_dox_py.path, ctx.file.dox_file.path, out_dir.path, ctx.attr.root_pkg),
        mnemonic = "ProcessDox",
    )

    return [
        DefaultInfo(
            files = depset(direct = [out_dir]),
        ),
    ]

haxe_gen_docs_from_dox = rule(
    doc = "Generate java files from a Dox file; this is useful when using a multi-project/language documentation gneerator that doesn't directly support Haxe (e.g. doxygen).",
    implementation = _haxe_gen_docs_from_dox,
    attrs = {
        "dox_file": attr.label(
            allow_single_file = True,
            doc = "The path to the dox file to generate from.",
        ),
        "root_pkg": attr.string(
            doc = "Root package to generate documentation for.",
            default = "*",
        ),
        "_postprocess_dox_py": attr.label(
            allow_single_file = True,
            doc = "Python file for post processing DOX files.",
            default = "//:utilities/postprocess_dox.py",
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
    docs = _find_direct_docsources(ctx)

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
