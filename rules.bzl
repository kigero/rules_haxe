"""Haxe build rules."""

load(":providers.bzl", "HaxeLibraryInfo")

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
            hxml["libs"].append(lib)

    hxml["classpaths"] = list()
    hxml["classpaths"].append(ctx.var["BINDIR"])
    hxml["classpaths"].append("src/main/haxe")
    if for_test:
        hxml["classpaths"].append("src/test/haxe")
    if hasattr(ctx.attr, "classpaths"):
        for p in ctx.attr.classpaths:
            hxml["classpaths"].append(p)

    hxml["source_files"] = list()
    if hasattr(ctx.attr, "srcs"):
        for i, d in enumerate(ctx.attr.srcs):
            for f in d.files.to_list():
                hxml["source_files"].append(f.path)

    return hxml

def _create_build_hxml(ctx, toolchain, hxml, out_file):
    """
    Create the build.hxml file based on the input hxml dict.
    
    Any Haxelibs that are specified in the hxml will be installed at this time.
    
    Args:
        ctx: Bazel context.
        toolchain: The Haxe toolchain instance.
        hxml: A dict containing HXML parameters; should be generated from `_create_hxml_map`.
        out_file: The output file that the build.hxml should be written to.
    """
    content = ""

    # Target
    if hxml["target"] == "neko":
        content += "--neko {}/neko/{}.n\n".format(ctx.var["BINDIR"], hxml["name"])
        hxml["output"] = "neko/{}.n".format(hxml["name"])
    elif hxml["target"] == "java":
        content += "--java {}/java/{}\n".format(ctx.var["BINDIR"], hxml["name"])

        output = "java/{}".format(hxml["name"])
        if hxml["main_class"] != None:
            mc = hxml["main_class"]
            if "." in mc:
                mc = mc[mc.rindex(".") + 1:]

            output += "/{}".format(mc)
        else:
            output += "/{}".format(hxml["name"])

        if hxml["debug"] != None:
            output += "-Debug"
        output += ".jar"

        hxml["output"] = output
    else:
        fail("Invalid target '{}'".format(hxml["target"]))

    # Debug
    if hxml["debug"] != None:
        content += "-debug\n"

    # Classpaths
    for classpath in hxml["classpaths"]:
        content += "-p {}\n".format(classpath)

    # Source or Main files
    if hxml["main_class"] != None:
        content += "-m {}\n".format(hxml["main_class"])
    else:
        for path in hxml["source_files"]:
            content += path.replace("src/main/haxe/", "").replace(".hx", "").replace("/", ".")
            content += "\n"

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
        path_file = ctx.actions.declare_file("{}.{}".format(path_prefix, count))
        toolchain.haxelib_install(
            ctx,
            lib,
            path_file,
        )

        lib_file = ctx.actions.declare_file("{}.{}".format(build_prefix, count))
        count += 1
        ctx.actions.run_shell(
            inputs = [path_file],
            outputs = [lib_file],
            command = "sed '/^-/! s/^/-p /' {} > {}".format(path_file.path, lib_file.path),
        )
        build_files.append(lib_file)

    ctx.actions.write(
        output = build_file_1,
        content = content,
    )

    command = "cat "
    for build_file in build_files:
        command += build_file.path
        command += " "
    command += "> "
    command += out_file.path

    ctx.actions.run_shell(
        outputs = [out_file],
        inputs = build_files,
        command = command,
    )

def _haxe_library_impl(ctx):
    """
    haxe_library implementation.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    hxml = _create_hxml_map(ctx)
    build_file = ctx.actions.declare_file("{}-build.hxml".format(ctx.attr.name))
    _create_build_hxml(ctx, toolchain, hxml, build_file)
    lib = ctx.actions.declare_file(hxml["output"])

    toolchain.compile(
        ctx,
        hxml = build_file,
        # importpath = ctx.attr.importpath,
        deps = [dep[HaxeLibraryInfo] for dep in ctx.attr.deps],
        out = lib,
    )

    return [
        DefaultInfo(
            files = depset([lib]),
            runfiles = ctx.runfiles(collect_data = True),
        ),
        HaxeLibraryInfo(
            info = struct(
                lib = lib,
            ),
            deps = depset(
                direct = [dep[HaxeLibraryInfo].info for dep in ctx.attr.deps],
                transitive = [dep[HaxeLibraryInfo].deps for dep in ctx.attr.deps],
            ),
        ),
    ]

def _haxelib_install_impl(ctx):
    """
    haxelib_install implementation.
    
    Args:
        ctx: Bazel context.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    out_file = ctx.actions.declare_file("out.txt")

    toolchain.haxelib(
        ctx,
        ctx.attr.haxelib,
        "install",
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
        "haxelibs": attr.string_list(
            doc = "A list of haxelibs that the library depends on.",
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
    },
)

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
        "haxelibs": attr.string_list(
            doc = "A list of haxelibs that the unit tests depend on.",
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

haxelib_install = rule(
    doc = "Install a haxelib.",
    implementation = _haxelib_install_impl,
    toolchains = ["@rules_haxe//:toolchain_type"],
    attrs = {
        "haxelib": attr.string(
            mandatory = True,
            doc = "The haxelib to install.",
        ),
        "deps": attr.label_list(
            providers = [HaxeLibraryInfo],
            doc = "Direct dependencies of the library",
        ),
    },
)
