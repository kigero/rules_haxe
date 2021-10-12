"""
Haxe utility functions.
"""

load(":providers.bzl", "HaxeLibraryInfo", "HaxeProjectInfo")

def determine_source_root(path):
    """
    Determine the source root for a given path, based on whether the path is in the external directory.

    Args:
        path: The path to check.

    Returns:
        The source root for the path.
    """
    source_root = ""
    parts = path.split("/")
    for idx in range(len(parts)):
        if parts[idx] == "external":
            source_root += "external/{}/".format(parts[idx + 1])
    return source_root

def _determine_classpath(classpaths, path):
    classpath = determine_source_root(path)
    if classpath == "":
        for cp in classpaths:
            cp_idx = path.find(cp)
            if cp_idx > 0:
                classpath = path[0:cp_idx]
    return classpath

def find_direct_sources(ctx):
    """
    Finds the direct sources of the given context.

    Args:
        ctx: The bazel context.

    Returns:
        An array of source files.
    """
    rtrn = []
    if hasattr(ctx.files, "srcs"):
        rtrn += ctx.files.srcs

    if hasattr(ctx.attr, "deps"):
        for dep in ctx.attr.deps:
            haxe_dep = dep[HaxeProjectInfo]
            if haxe_dep == None:
                continue
            if hasattr(haxe_dep, "srcs"):
                rtrn += haxe_dep.srcs

    return rtrn

def find_direct_docsources(ctx):
    """
    Finds the direct document sources of the given context.

    Args:
        ctx: The bazel context.

    Returns:
        An array of document source files.
    """
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

def find_direct_resources(ctx):
    """
    Finds the direct resources of the given context.

    Args:
        ctx: The bazel context.

    Returns:
        An array of resource files.
    """
    rtrn = []
    if hasattr(ctx.files, "resources"):
        rtrn += ctx.files.resources

    if hasattr(ctx.attr, "deps"):
        for dep in ctx.attr.deps:
            haxe_dep = dep[HaxeProjectInfo]
            if haxe_dep == None:
                continue
            if hasattr(haxe_dep, "resources"):
                rtrn += haxe_dep.resources

    return rtrn

def find_library_name(ctx):
    """
    Determines the library name, taking into account any dependent HaxeProjectInfos.

    Args:
        ctx: The bazel context.

    Returns:
        The specified library name.
    """
    if hasattr(ctx.attr, "library_name") and ctx.attr.library_name != "":
        return ctx.attr.library_name
    elif hasattr(ctx.attr, "executable_name") and ctx.attr.executable_name != "":
        return ctx.attr.executable_name
    elif hasattr(ctx.attr, "deps"):
        for dep in ctx.attr.deps:
            haxe_dep = dep[HaxeProjectInfo]
            if haxe_dep == None:
                continue
            if haxe_dep.library_name != None and haxe_dep.library_name != "":
                return haxe_dep.library_name

    return ctx.attr.name

def find_main_class(ctx):
    """
    Determines the main class, taking into account any dependant HaxeProjectInfos.

    Args:
        ctx: The bazel context.

    Returns:
        The specified main class.
    """
    if hasattr(ctx.attr, "main_class") and ctx.attr.main_class != "":
        return ctx.attr.main_class
    else:
        for dep in ctx.attr.deps:
            haxe_dep = dep[HaxeProjectInfo]
            if haxe_dep == None:
                continue
            if hasattr(haxe_dep, "main_class") and haxe_dep.main_class != "":
                return haxe_dep.main_class

    return None

def create_hxml_map(ctx, toolchain, for_test = False, for_std_build = False):
    """
    Create a dict containing haxe build parameters based on the input attributes from the calling rule.

    Args:
        ctx: Bazel context.
        toolchain: The Haxe toolchain instance.
        for_test: True if build parameters for unit testing should be added, False otherwise.
        for_std_build: True if build parameters for the standard build should be added, False otherwise.

    Returns:
        A dict containing the HXML properties.
    """
    hxml = {}

    package = ctx.label.package + "/" if ctx.label.package != "" else ""
    hxml["package"] = package

    hxml["for_test"] = for_test

    hxml["target"] = ctx.attr.target if hasattr(ctx.attr, "target") else None
    hxml["debug"] = ctx.attr.debug if hasattr(ctx.attr, "debug") else False
    hxml["name"] = "std-{}".format(hxml["target"]) if for_std_build else find_library_name(ctx)

    if for_test:
        hxml["main_class"] = "MainTest"
    elif for_std_build:
        hxml["main_class"] = "StdBuild"
    else:
        hxml["main_class"] = find_main_class(ctx)

    hxml["args"] = list()
    if hasattr(ctx.attr, "extra_args"):
        for arg in ctx.attr.extra_args:
            if not arg in hxml["args"]:
                hxml["args"].append(arg)

    hxml["libs"] = dict()
    if hxml["target"] == "java":
        hxml["libs"]["hxjava"] = toolchain.haxelib_language_versions["hxjava"]
    elif hxml["target"] == "cpp":
        hxml["libs"]["hxcpp"] = toolchain.haxelib_language_versions["hxcpp"]
        if ctx.var["TARGET_CPU"].startswith("x64") and not "-D HXCPP_M64" in hxml["args"]:
            hxml["args"].append("-D HXCPP_M64")

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
        hxml["classpaths"].append("{}/{}".format(ctx.var["BINDIR"], package))
        hxml["classpaths"].append("src/test/haxe")
        hxml["classpaths"].append("{}src/test/haxe".format(package))
    if hasattr(ctx.attr, "classpaths"):
        for p in ctx.attr.classpaths:
            hxml["classpaths"].append(p)

    hxml["source_files"] = list()
    for src in find_direct_sources(ctx):
        hxml["source_files"].append(src.path)

    hxml["resources"] = dict()
    for resource in find_direct_resources(ctx):
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
    if hasattr(ctx.attr, "deps"):
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
                    calculated_classpath = _determine_classpath(dep_hxml["classpaths"], dep_hxml["source_files"][0]) if len(dep_hxml["source_files"]) != 0 else ""
                    if calculated_classpath == dep_hxml["package"]:
                        calculated_classpath = ""
                    hxml["classpaths"].append("{}{}{}".format(calculated_classpath, dep_hxml["package"], classpath))
            for lib in dep_hxml["libs"]:
                if not lib in hxml["libs"]:
                    hxml["libs"][lib] = dep_hxml["libs"][lib]
            for resource in dep_hxml["resources"]:
                if not resource in hxml["resources"]:
                    hxml["resources"][resource] = dep_hxml["resources"][resource]
            for arg in dep_hxml["args"]:
                if not arg in hxml["args"]:
                    hxml["args"].append(arg)

    is_external = ctx.label.workspace_root.startswith("external")
    hxml["external_dir"] = "external/{}/".format(hxml["name"]) if is_external else ""

    return hxml

def create_build_hxml(ctx, toolchain, hxml, out_file, suffix = "", for_exec = False):
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

    # Determine if we're in a dependant build.
    if for_exec or len(hxml["source_files"]) == 0 or len(ctx.files.srcs) == 0:
        is_dependent_build = True
    else:
        is_dependent_build = hxml["source_files"][0].startswith("external")

    # An empty source root seems to cover the use cases that are currently in use; this may need to be revisited, but
    # will require unit test cases!
    source_root = ""

    content = ""

    package = ctx.label.package + "/" if ctx.label.package != "" else ""

    # Target

    hxml["output_dir"] = "{}{}".format(ctx.attr.name, suffix)
    hxml["build_file"] = "{}/{}{}{}/{}".format(ctx.var["BINDIR"], hxml["external_dir"], package, hxml["output_dir"], hxml["name"])
    ext = ""
    if hxml["target"] != "":
        if hxml["target"] == "neko":
            ext = ".n"
            hxml["output_file"] = "{}.n".format(hxml["name"], suffix)
        elif hxml["target"] == "python":
            ext = ".py"
            hxml["output_file"] = "{}.py".format(hxml["name"], suffix)
        elif hxml["target"] == "php":
            hxml["output_file"] = "{}".format(hxml["name"], suffix)
        elif hxml["target"] == "cpp":
            output = "{}/".format(hxml["name"])
            output_file = ""
            if not for_exec:
                output_file += "lib"

            if hxml["main_class"] != None:
                mc = hxml["main_class"]
                if "." in mc:
                    mc = mc[mc.rindex(".") + 1:]

                output_file += "{}".format(mc)
            else:
                output_file += "{}".format(hxml["name"])

            if hxml["debug"] != None:
                output_file += "-debug"

            found_output_file = False
            for arg in hxml["args"]:
                if arg.lower().startswith("-d haxe_output_file"):
                    found_output_file = True
            if not found_output_file:
                hxml["args"].append("-D HAXE_OUTPUT_FILE={}".format(output_file))

            if for_exec:
                output_file += ".exe"
            elif "-D dll_link" in hxml["args"]:
                output_file += ".dll"
            else:
                output_file += ".lib"

            hxml["output_file"] = output + output_file
        elif hxml["target"] == "java":
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
        elif hxml["target"] == "js":
            ext = ".js"
            hxml["output_file"] = "{}.js".format(hxml["name"], suffix)

        content += "--{} {}{}\n".format(hxml["target"], hxml["build_file"], ext)

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

def calc_provider_response(ctx, toolchain, hxml, out_dir, launcher_file = None, output_file = None, library_name = None):
    """
    Determine an appropriate provider response based on the input context and the compilation target.

    Args:
        ctx: The bazel context.
        toolchain: The Haxe toolchain.
        hxml: The HXML dictionary.
        out_dir: The output directory.
        launcher_file: The launcher file to run, if there is one.
        output_file: The output file, if there is one.
        library_name: The name of the library, overrides the ctx variables.

    Returns:
        An array of providers.
    """
    runfiles = [out_dir]
    if launcher_file != None:
        runfiles.append(launcher_file)
        runfiles += toolchain.internal.tools

    haxe_deps_lib_direct = []
    haxe_deps_lib_transitive = []
    haxe_deps_proj_direct = []
    haxe_deps_proj_transitive = []
    if hasattr(ctx.attr, "deps"):
        haxe_deps_lib_direct = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps]
        haxe_deps_lib_transitive = [dep[HaxeLibraryInfo].deps for dep in ctx.attr.deps]
        haxe_deps_proj_direct = [dep[HaxeProjectInfo] for dep in ctx.attr.deps]
        haxe_deps_proj_transitive = [dep[HaxeProjectInfo].deps for dep in ctx.attr.deps]

    srcs = []
    if hasattr(ctx.files, "srcs"):
        srcs = ctx.files.srcs

    resources = []
    if hasattr(ctx.files, "resources"):
        resources = ctx.files.resources

    rtrn = [
        DefaultInfo(
            files = depset([out_dir] + find_direct_sources(ctx)),
            runfiles = ctx.runfiles(files = runfiles),
            executable = launcher_file,
        ),
        HaxeLibraryInfo(
            lib = out_dir,
            hxml = hxml,
            deps = depset(
                direct = haxe_deps_lib_direct,
                transitive = haxe_deps_lib_transitive,
            ),
        ),
        HaxeProjectInfo(
            hxml = hxml,
            srcs = srcs,
            resources = resources,
            library_name = library_name if library_name != None else (ctx.attr.executable_name if hasattr(ctx.attr, "executable_name") else ctx.attr.library_name),
            deps = depset(
                direct = haxe_deps_proj_direct,
                transitive = haxe_deps_proj_transitive,
            ),
        ),
    ]

    cpp_files = []

    # Create target-specific responses
    if hxml["target"] == "java":
        java_out = ctx.actions.declare_file("java-deps/{}/{}".format(hxml["output_dir"], hxml["output_file"]))
        ctx.actions.run_shell(
            outputs = [java_out],
            inputs = [out_dir],
            command = "cp {}/{} {}".format(out_dir.path, hxml["output_file"], java_out.path),
            use_default_shell_env = True,
            mnemonic = "CopyJavaTargetToOutput",
        )

        java_deps = []
        if hasattr(ctx.attr, "deps"):
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
    elif hxml["target"] == "cpp":
        # To get includes to be added to a downstream cc_library, they need to be added to the output.  But since we
        # don't have the File objects for each include, a tree result needs to be added.  This tree result needs to be
        # named such that cc_library will accept it - so it needs to end in '.h'.  Copy the includes folder to a new
        # folder with an appropriate name.
        inc = ctx.actions.declare_directory("{}_includes_dir.h".format(ctx.label.name))
        ctx.actions.run_shell(
            outputs = [inc],
            inputs = [out_dir],
            command = "cp -r -t {} {}/{}/include/* {}/{}/HxcppConfig-19.h".format(inc.path, out_dir.path, ctx.label.name, out_dir.path, ctx.label.name),
        )

        # Create an appropriate library object depending on whether the library is static or dynamic.
        library_to_link = None
        if output_file != None:
            if output_file.path.lower().endswith(".dll"):
                # Create a copy of the .lib file associated with the .dll so we have a File reference to it.
                lib_file = ctx.actions.declare_file("{}/{}/lib{}-debug.lib".format(out_dir.path, hxml["name"], hxml["name"]))
                ctx.actions.run_shell(
                    outputs = [lib_file],
                    inputs = [out_dir],
                    command = "cp {}/{}/obj/lib/lib{}-debug.lib {}".format(out_dir.path, hxml["name"], hxml["name"], lib_file.path),
                )

                library_to_link = cc_common.create_library_to_link(
                    actions = ctx.actions,
                    dynamic_library = output_file,
                    interface_library = lib_file,
                    feature_configuration = cc_common.configure_features(ctx = ctx, cc_toolchain = toolchain.haxe_cpp_toolchain),
                    cc_toolchain = toolchain.haxe_cpp_toolchain,
                )

                cpp_files.append(output_file)
                cpp_files.append(lib_file)

            elif output_file.path.lower().endswith(".lib"):
                library_to_link = cc_common.create_library_to_link(
                    actions = ctx.actions,
                    static_library = output_file,
                    feature_configuration = cc_common.configure_features(ctx = ctx, cc_toolchain = toolchain.haxe_cpp_toolchain),
                    cc_toolchain = toolchain.haxe_cpp_toolchain,
                )

                cpp_files.append(output_file)

        # Finally create the compilation context and add it to the response.
        linking_context = None
        if library_to_link != None:
            linking_context = cc_common.create_linking_context(
                linker_inputs = depset([cc_common.create_linker_input(
                    owner = ctx.label,
                    libraries = depset([library_to_link]),
                )]),
            )

        rtrn.append(CcInfo(
            compilation_context = cc_common.create_compilation_context(
                includes = depset([inc.path]),
                headers = depset([inc]),
            ),
            linking_context = linking_context,
        ))

    if output_file != None:
        rtrn.append(OutputGroupInfo(
            output_file = [output_file],
            cpp_files = cpp_files,
        ))

    return rtrn
