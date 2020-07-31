"""Haxe build rules."""

load(":providers.bzl", "HaxeLibraryInfo")

def _determine_source_root(path):
    source_root = ""
    parts = path.split("/")
    for idx in range(len(parts)):
        if parts[idx] == "external":
            source_root += "external/{}/".format(parts[idx + 1])
    return source_root

def _create_hxml_map(ctx, for_test = False):
    """
    Create a dict containing haxe build parameters based on the input attributes from the calling rule.
    
    Args:
        ctx: Bazel context.
        for_test: True if build parameters for unit testing should be added, False otherwise.
    """
    hxml = {}

    hxml["for_test"] = for_test

    hxml["name"] = ctx.attr.library_name if hasattr(ctx.attr, "library_name") else ctx.attr.name
    hxml["target"] = ctx.attr.target if hasattr(ctx.attr, "target") else None
    hxml["debug"] = ctx.attr.debug if hasattr(ctx.attr, "debug") else False

    if hasattr(ctx.attr, "main_class"):
        hxml["main_class"] = ctx.attr.main_class
    elif for_test:
        hxml["main_class"] = "MainTest"
    else:
        hxml["main_class"] = None

    hxml["libs"] = list()
    if hxml["target"] == "java":
        hxml["libs"].append("hxjava")
    if hasattr(ctx.attr, "haxelibs"):
        for lib in ctx.attr.haxelibs:
            version = ctx.attr.haxelibs[lib]
            if version != None and version != "":
                if version.lower().find("http") == 0:
                    version = "git:{}".format(version)
                hxml["libs"].append("{}:{}".format(lib, version))
            else:
                hxml["libs"].append(lib)

    hxml["classpaths"] = list()
    hxml["classpaths"].append("src/main/haxe")
    if for_test:
        hxml["classpaths"].append(ctx.var["BINDIR"])
        hxml["classpaths"].append("src/test/haxe")
    if hasattr(ctx.attr, "classpaths"):
        for p in ctx.attr.classpaths:
            hxml["classpaths"].append(p)

    hxml["source_files"] = list()
    if hasattr(ctx.attr, "srcs"):
        for i, d in enumerate(ctx.attr.srcs):
            for f in d.files.to_list():
                hxml["source_files"].append(f.path)

    # Handle Dependencies
    for dep in ctx.attr.deps:
        dep_hxml = dep[HaxeLibraryInfo].hxml
        if dep_hxml == None:
            continue
        for classpath in dep_hxml["classpaths"]:
            hxml["classpaths"].append("{}{}".format(_determine_source_root(dep_hxml["source_files"][0]), classpath))
        for lib in dep_hxml["libs"]:
            if not lib in hxml["libs"]:
                hxml["libs"].append(lib)

    return hxml

def _create_build_hxml(ctx, toolchain, hxml, out_file, suffix = ""):
    """
    Create the build.hxml file based on the input hxml dict.
    
    Any Haxelibs that are specified in the hxml will be installed at this time.
    
    Args:
        ctx: Bazel context.
        toolchain: The Haxe toolchain instance.
        hxml: A dict containing HXML parameters; should be generated from `_create_hxml_map`.
        out_file: The output file that the build.hxml should be written to.
        suffix: Optional suffix to append to the build parameters.
    """

    # Determine if we're in a dependant build, and if so what the correct source root is.
    # This is fairly toxic.
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
        content += "-L {}\n".format(lib)
        colon_idx = lib.find(":")
        version = None
        if colon_idx > 0:
            version = lib[colon_idx + 1:]
            lib = lib[:colon_idx]
        path_file = ctx.actions.declare_file("{}.{}".format(path_prefix, count))
        toolchain.haxelib_install(
            ctx,
            lib,
            version,
            path_file,
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
            ctx.attr.srcs,
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
    ]

    # This allows java targets to use the results of this rule.
    if hxml["target"] == "java":
        rtrn.append(JavaInfo(
            output_jar = output,
            compile_jar = output,
            deps = [dep[JavaInfo] for dep in ctx.attr.deps],
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
            mandatory = True,
            allow_files = True,
            doc = "Haxe source code.",
        ),
        "target": attr.string(
            default = "neko",
            doc = "Target platform.",
        ),
        "haxelibs": attr.string_dict(
            doc = "A dict of haxelib names to optional versions that the library depends on.",
        ),
        "debug": attr.bool(
            doc = "If True, will compile the library with debug flags on.",
        ),
        "classpaths": attr.string_list(
            doc = "Any extra classpaths to add to the build file.",
        ),
        "strip_haxe": attr.bool(
            default = False,
            doc = "Whether to strip haxe classes from the resultant library.  Supported platforms: java",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library.",
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
            runfiles = ctx.runfiles(files = ctx.files.srcs + toolchain.internal.tools + [lib, launcher_file]),
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
        "target": attr.string(
            default = "neko",
            doc = "Target platform.",
        ),
        "haxelibs": attr.string_dict(
            doc = "A dict of haxelib names to optional versions or git repositories that the unit tests depend on.",
        ),
        "classpaths": attr.string_list(
            doc = "Any extra classpaths to add to the build file.",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library",
        ),
    },
)
