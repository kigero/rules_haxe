"""
Defines the Haxe toolchain.
"""

def _run_haxe(ctx, inputs, output, toolchain, haxe_cmd, mnemonic = None, ignore_output = False, additional_outputs = []):
    """
    Runs a Haxe command using run_shell.  
    
    Some preliminary environment is set up before running the command.
    
    Args:
        ctx: Bazel context.
        inputs: Any inputs needed by run_shell.
        output: The single file to direct output to.
        toolchain: The haxe toolchain instance.
        haxe_cmd: The actual haxe command to run; may be a haxe or haxelib command, e.g. `haxe build.hxml` or `haxelib install hx3compat`.
        mnemonic: The mnemonic to pass to run_shell.
        ignore_output: True if output should be sent to /dev/null, False if output should be redirected to outout (e.g. for haxelib path commands).
        additional_outputs: Any other outputs that are created by haxe_cmd that should be included in the outputs.
    """
    if ctx.var["TARGET_CPU"].upper().find("WINDOWS") >= 0:
        host = "WIN"
    else:
        host = "LIN"

    if ignore_output:
        redirect_output = "{}.log".format(output.path)
    else:
        redirect_output = output.path

    ctx.actions.run_shell(
        outputs = [output] + additional_outputs,
        inputs = inputs,
        command = "{} $@".format(toolchain.internal.run_haxe_file.path),
        arguments = [toolchain.internal.neko_dir, toolchain.internal.haxe_dir, toolchain.internal.env["HAXELIB_PATH"], host, redirect_output, haxe_cmd],
        use_default_shell_env = True,
        mnemonic = mnemonic,
    )

def haxe_compile(ctx, hxml, out, runfiles = None, deps = []):
    """
    Compile some code using Haxe.  
    
    Arbitrary command line options cannot be passed; only a single HXML file.
    
    Args:
        ctx: Bazel context.
        hxml: The build HXML to run.
        out: The expected output of the compilation.
        runfiles: Any runfiles needed by the compilation.
        deps: Any deps needed by the compilation.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    args = ctx.actions.args()
    args.add(hxml.path)

    inputs = [hxml] + toolchain.internal.tools
    for dep in deps:
        if hasattr(dep, "lib"):
            inputs.append(dep.lib)

    if runfiles != None:
        inputs += runfiles

    _run_haxe(
        ctx,
        inputs = inputs,
        output = out,
        toolchain = toolchain,
        ignore_output = True,
        haxe_cmd = "haxe {}".format(hxml.path),
        mnemonic = "HaxeCompile",
    )

def _haxe_haxelib(ctx, cmd, out, runfiles = None, deps = []):
    """
    Perform a haxelib action on some haxelib.
    
    Args:
        ctx: Bazel context.
        cmd: The haxelib command to run.
        out: A file that captures the output of the haxelib command.
        runfiles: Any runfiles needed by the compilation.
        deps: Any deps needed by the compilation.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    inputs = (
        [dep.info.archive for dep in deps] +
        toolchain.internal.tools
    )
    if runfiles != None:
        inputs += runfiles

    _run_haxe(
        ctx,
        inputs = inputs,
        output = out,
        toolchain = toolchain,
        haxe_cmd = "haxelib {}".format(cmd),
        mnemonic = "Haxelib",
    )

def haxe_haxelib_path(ctx, haxelib, version, out, runfiles = [], deps = []):
    """
    Get the path information for a haxelib.
    
    Args:
        ctx: Bazel context.
        haxelib: The haxelib to install.
        version: The haxelib version to check.
        out: A file that captures the "path" information of the haxelib command.
        runfiles: Any runfiles needed by the compilation.
        deps: Any deps needed by the compilation.
    """
    _haxe_haxelib(ctx, "path {}:{}".format(haxelib, version), out, runfiles, deps)

def haxe_haxelib_install(ctx, haxelib, version, runfiles = [], deps = []):
    """
    Install a haxelib.  
    
    The output of this command will always be the result of `haxelib path <haxelib>`.  An error is not thrown if the 
    haxelib is already installed.
    
    Args:
        ctx: Bazel context.
        haxelib: The haxelib to install.
        version: The version of the haxelib to perform the action on; specify "git:<repo_url>" to use a git repository.
        runfiles: Any runfiles needed by the compilation.
        deps: Any deps needed by the compilation.
    
    Returns:
        The output file of the install process, which can be used to ensure that a haxelib is installed before continuing on.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    if version.startswith("git:"):
        path_suffix = "{}_git".format(haxelib)
    else:
        path_suffix = "{}_{}".format(haxelib, version)

    install_out = ctx.actions.declare_file("haxelib_install_{}".format(path_suffix))
    inputs = (
        [dep.info.archive for dep in deps] +
        toolchain.internal.tools
    )
    if runfiles != None:
        inputs += runfiles

    if ctx.var["TARGET_CPU"].upper().find("WINDOWS") >= 0:
        host = "WIN"
    else:
        host = "LIN"

    ctx.actions.run_shell(
        outputs = [install_out],
        inputs = inputs,
        command = "{} $@".format(toolchain.internal.haxelib_install_file.path),
        arguments = [toolchain.internal.neko_dir, toolchain.internal.haxe_dir, toolchain.internal.env["HAXELIB_PATH"], host, install_out.path, haxelib, version],
        use_default_shell_env = True,
        mnemonic = "HaxelibInstall",
    )

    # OK... this is bad.  Really bad.  But I can't find any other way of getting this variable passed through to the
    # haxe environment.  See the readme for better discussion.  Postprocess the HXCPP install.
    path_runfiles = []
    for f in runfiles:
        path_runfiles.append(f)

    if haxelib == "hxcpp" and ctx.var["TARGET_CPU"].upper().find("WINDOWS") >= 0:
        postprocess_out = ctx.actions.declare_file("haxelib_install_{}_postprocess".format(path_suffix))
        ctx.actions.run_shell(
            outputs = [postprocess_out],
            inputs = [install_out],
            command = "{} $@".format(toolchain.internal.postprocess_hxcpp_script.path),
            arguments = [toolchain.internal.env["HAXELIB_PATH"], postprocess_out.path],
            use_default_shell_env = True,
            mnemonic = "HaxelibHxcppPostProcess",
        )
        path_runfiles.append(postprocess_out)
    else:
        path_runfiles.append(install_out)

    out = ctx.actions.declare_file("haxelib_path_{}".format(path_suffix))
    haxe_haxelib_path(ctx, haxelib, version, out, path_runfiles, deps)
    return out

def haxe_create_test_class(ctx, srcs, out):
    """
    Create the main test class for a set of unit test files.
    
    Args:
        ctx: Bazel context.
        srcs: The sources to search for unit test files.
        out: The MainTest.hx file that calls the individual unit tests.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    if toolchain.internal.haxe_dir != ".":
        command = toolchain.internal.haxe_dir + "/haxe"
    else:
        command = "haxe"

    command += " -p " + toolchain.internal.utils_file.dirname
    command += " --run RulesHaxeUtils.hx genMainTest"
    for f in srcs:
        command += " " + f.path
    command += " > " + out.path

    ctx.actions.run_shell(
        outputs = [out],
        command = command,
    )

def haxe_create_std_build(ctx, target, out):
    """
    Create the main file for compiling the standard build.
    
    Args:
        ctx: Bazel context.
        target: The target of the build.
        out: The StdBuild.hx file that calls the individual unit tests.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    if toolchain.internal.haxe_dir != ".":
        command = toolchain.internal.haxe_dir + "/haxe"
    else:
        command = "haxe"

    command += " -p " + toolchain.internal.utils_file.dirname
    command += " --run RulesHaxeUtils.hx genStdBuild "
    if toolchain.internal.haxe_dir != ".":
        command += toolchain.internal.haxe_dir
    else:
        command += "."
    command += " " + target + " > " + out.path

    ctx.actions.run_shell(
        outputs = [out],
        command = command,
        use_default_shell_env = True,
    )

def haxe_create_haxelib_build(ctx, haxelib, version, target, out, includes = None):
    """
    Create the main file for compiling a haxelib build.
    
    Args:
        ctx: Bazel context.
        haxelib: The name of the haxelib.
        version: The version of the haxelib.
        target: The target of the build.
        out: The HaxelibBuild.hx file that calls the individual classes.
        includes: Optional classpath includes.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    # Make sure the lib is installed.
    install_out = haxe_haxelib_install(ctx, haxelib, version)

    if toolchain.internal.haxe_dir != ".":
        command = toolchain.internal.haxe_dir + "/haxe"
    else:
        command = "haxe"

    command += " -p " + toolchain.internal.utils_file.dirname
    command += " --run RulesHaxeUtils.hx genHaxelibBuild "
    command += toolchain.internal.env["HAXELIB_PATH"] + " "
    command += haxelib + " "
    command += version
    command += " " + target
    if includes != None:
        for inc in includes:
            command += " " + inc
    command += " > " + out.path

    ctx.actions.run_shell(
        inputs = [install_out],
        outputs = [out],
        command = command,
        use_default_shell_env = True,
    )

def haxe_create_final_jar(ctx, srcs, intermediate, output, jar_name, strip = True, include_sources = True, output_file = None):
    """
    Create the final jar file, which strips out haxe classes and adds source files.
    
    Args:
        ctx: Bazel context.
        srcs: The sources to search for unit test files.
        intermediate: The intermediate jar file's directory.
        output: The final jar file's directory.
        jar_name: The name of the jar in the intermediate/output directories.
        strip: Strip out haxe classes.
        include_sources: Include the Java sources in the jar.
        output_file: The output file to create.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    if toolchain.internal.haxe_dir != ".":
        command = toolchain.internal.haxe_dir + "/haxe"
    else:
        command = "haxe"
    command += " -p " + toolchain.internal.utils_file.dirname
    command += " --run RulesHaxeUtils.hx createFinalJar {}/{} {}/{} {} {}".format(intermediate.path, jar_name, output.path, jar_name, "true" if strip else "false", "true" if include_sources else "false")
    for file in srcs:
        command += " " + file.path

    ctx.actions.run_shell(
        outputs = [output, output_file],
        inputs = [intermediate],
        command = command,
        use_default_shell_env = True,
    )

def haxe_copy_cpp_includes(ctx, to_dir):
    """
    Copy the HXCPP includes to a new directory so they can be included in the outputs.
    
    Args:
        ctx: Bazel context.
        to_dir: The directory to copy the HXCPP includes to.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    cmd = "cp -r `haxelib libpath hxcpp`include/* " + to_dir.path

    path_file = toolchain.haxelib_install(ctx, "hxcpp", toolchain.haxelib_language_versions["hxcpp"])
    copy_file = ctx.actions.declare_file("hxcpp_copy")

    ctx.actions.run_shell(
        outputs = [copy_file, to_dir],
        inputs = [path_file],
        command = "{} $@".format(toolchain.internal.copy_hxcpp_includes_script.path),
        arguments = [toolchain.internal.env["HAXELIB_PATH"], to_dir.path, copy_file.path],
        use_default_shell_env = True,
        mnemonic = "CopyHxCppIncludes",
    )

def haxe_create_run_script(ctx, target, lib_name, out):
    """
    Create a run script usable by Bazel for running executables (e.g. unit tests).
    
    Args:
        ctx: Bazel context.
        target: The target platform.
        lib_name: The name of the executable.
        out: The path to the run script.  Regardless of the file name, a platform appropriate script will be generated.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    if toolchain.internal.neko_dir != ".":
        neko_path = toolchain.internal.neko_dir + "/neko"
    else:
        neko_path = "neko"

    package = ctx.label.package + "/" if ctx.label.package != "" else ""

    script_content = ""
    if ctx.var["TARGET_CPU"].upper().find("WINDOWS") >= 0:
        script_content += "@echo off\n"
        if toolchain.internal.haxe_dir:
            script_content += "SET PATH={};%PATH%\n".format(toolchain.internal.haxe_dir).replace("/", "\\")
        if toolchain.internal.neko_dir:
            script_content += "SET PATH={};%PATH%\n".format(toolchain.internal.neko_dir).replace("/", "\\")
        for e in toolchain.internal.env:
            script_content += "SET {}={}\n".format(e, toolchain.internal.env[e]).replace("/", "\\")

        if target == "neko":
            script_content += "{} {}{}/{}".format(neko_path, package, ctx.attr.name, lib_name).replace("/", "\\")
        elif target == "java":
            script_content += "java -jar {}{}/{}".format(package, ctx.attr.name, lib_name).replace("/", "\\")
        elif target == "python":
            script_content += "python{} {}/{}".format(package, ctx.attr.name, lib_name).replace("/", "\\")
        elif target == "php":
            php_ini_var = ""
            if "PHP_INI" in ctx.var:
                php_ini_var = "-c {}".format(ctx.var["PHP_INI"])
            script_content += "php {} {}{}/{}/index.php".format(php_ini_var, package, ctx.attr.name, lib_name).replace("/", "\\")
        elif target == "cpp":
            lib_name = lib_name.replace(".lib", ",exe")
            script_content += "{}{}/{}".format(package, ctx.attr.name, lib_name).replace("/", "\\")
        else:
            fail("Invalid target {}".format(target))
        script_content += " %*"
    else:
        if toolchain.internal.haxe_dir:
            script_content += "export PATH={}:$PATH\n".format(toolchain.internal.haxe_dir)
        if toolchain.internal.neko_dir:
            script_content += "export PATH={}:$PATH\n".format(toolchain.internal.neko_dir)
        for e in toolchain.internal.env:
            script_content += "export {}={}\n".format(e, toolchain.internal.env[e])

        if target == "neko":
            script_content += "{} {}{}/{}".format(neko_path, package, ctx.attr.name, lib_name)
        elif target == "java":
            script_content += "java -jar {}{}/{}".format(package, ctx.attr.name, lib_name)
        elif target == "python":
            script_content += "python {}{}/{}".format(package, ctx.attr.name, lib_name)
        elif target == "php":
            php_ini_var = ""
            if "PHP_INI" in ctx.var:
                php_ini_var = "-c {}".format(ctx.var["PHP_INI"])
            script_content += "php {} {}{}/{}/index.php".format(php_ini_var, package, ctx.attr.name, lib_name)
        elif target == "cpp":
            script_content += "{}{}/{}".format(package, ctx.attr.name, lib_name)
        else:
            fail("Invalid target {}".format(target))
        script_content += " \"$@\""

    ctx.actions.write(
        output = out,
        content = script_content,
        is_executable = True,
    )

def haxe_postprocess_dox(ctx, out_dir):
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]
    ctx.actions.run_shell(
        inputs = [toolchain.internal.postprocess_dox_tool, ctx.file.dox_file],
        outputs = [out_dir],
        command = "{} {} {} {}".format(toolchain.internal.postprocess_dox_tool.path, ctx.file.dox_file.path, out_dir.path, ctx.attr.root_pkg),
        mnemonic = "ProcessDox",
    )

def _haxe_toolchain_impl(ctx):
    """
    Haxe toolchain implementation.
    
    Args:
        ctx: Bazel context.
    """

    # Find important files and paths.
    haxe_cmd = None
    haxelib_file = None
    neko_cmd = None
    utils_file = None
    run_haxe_file = None
    haxelib_install_file = None
    postprocess_hxcpp_script = None
    copy_hxcpp_includes_script = None
    haxe_dir = None
    neko_dir = None
    postprocess_dox_tool = None

    for f in ctx.files.tools:
        if f.path.endswith("/haxe") or f.path.endswith("/haxe.exe"):
            haxe_cmd = f
        if f.path.endswith("/neko") or f.path.endswith("/neko.exe"):
            neko_cmd = f
        if f.path.endswith("/haxelib_file"):
            haxelib_file = f
        if f.path.endswith("/RulesHaxeUtils.hx"):
            utils_file = f
        if f.path.endswith("/run_haxe.sh"):
            run_haxe_file = f
        if f.path.endswith("/haxelib_install.sh"):
            haxelib_install_file = f
        if f.path.endswith("/postprocess_hxcpp.sh"):
            postprocess_hxcpp_script = f
        if f.path.endswith("/copy_hxcpp_includes.sh"):
            copy_hxcpp_includes_script = f
        if f.path.endswith("/postprocess_dox") or f.path.endswith("/postprocess_dox.exe"):
            postprocess_dox_tool = f

    if haxe_cmd:
        haxe_dir = haxe_cmd.dirname
    else:
        haxe_dir = "."

    if neko_cmd:
        neko_dir = neko_cmd.dirname
    else:
        neko_dir = "."

    if not haxelib_file:
        fail("could not locate haxelib file")
    if not utils_file:
        fail("could not locate RulesHaxeUtils.hx file")
    if not run_haxe_file:
        fail("could not locate run_haxe.sh file")
    if not haxelib_install_file:
        fail("could not locate haxelib_install.sh file")
    if not postprocess_hxcpp_script:
        fail("could not locate postprocess_hxcpp.sh file")
    if not copy_hxcpp_includes_script:
        fail("could not locate copy_hxcpp_includes.sh file")
    if not postprocess_dox_tool:
        fail("could not locate postprocess_dox_tool")

    env = {
        "HAXELIB_PATH": haxelib_file.dirname,
    }

    haxelib_language_versions = {
        "hxcpp": "4.3.12",
        "hxjava": "4.2.0",
    }

    if platform_common.ToolchainInfo in ctx.attr.cpp_toolchain:
        haxe_cpp_toolchain = ctx.attr.cpp_toolchain[platform_common.ToolchainInfo]
    else:
        haxe_cpp_toolchain = ctx.attr.cpp_toolchain[cc_common.CcToolchainInfo]

    return [platform_common.ToolchainInfo(
        # Public toolchain interface.
        compile = haxe_compile,
        haxelib_install = haxe_haxelib_install,
        create_test_class = haxe_create_test_class,
        create_std_build = haxe_create_std_build,
        create_haxelib_build = haxe_create_haxelib_build,
        create_run_script = haxe_create_run_script,
        create_final_jar = haxe_create_final_jar,
        copy_cpp_includes = haxe_copy_cpp_includes,
        postprocess_dox = haxe_postprocess_dox,
        haxelib_language_versions = haxelib_language_versions,
        haxe_cpp_toolchain = haxe_cpp_toolchain,

        # Internal data. Contents may change without notice.
        internal = struct(
            haxe_dir = haxe_dir,
            neko_dir = neko_dir,
            utils_file = utils_file,
            run_haxe_file = run_haxe_file,
            haxelib_install_file = haxelib_install_file,
            postprocess_hxcpp_script = postprocess_hxcpp_script,
            copy_hxcpp_includes_script = copy_hxcpp_includes_script,
            postprocess_dox_tool = postprocess_dox_tool,
            env = env,
            tools = ctx.files.tools,
        ),
    )]

haxe_toolchain = rule(
    doc = "Haxe toolchain implementation.",
    implementation = _haxe_toolchain_impl,
    attrs = {
        "tools": attr.label_list(
            mandatory = True,
            doc = "Tools needed from the Haxe/Neko installation.",
        ),
        "cpp_toolchain": attr.label(
            mandatory = True,
            doc = "C++ toolchain to use for downstream C++ dependencies.",
        ),
    },
)
