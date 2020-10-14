"""
Defines the Haxe toolchain.
"""

def _run_haxe(ctx, inputs, output, toolchain, haxe_cmd, mnemonic = None, ignore_output = False):
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
    """
    if ctx.var["TARGET_CPU"].upper().find("WINDOWS") >= 0:
        host = "WIN"
    else:
        host = "LIN"

    if ignore_output:
        redirect_output = "/dev/null"
    else:
        redirect_output = output.path

    ctx.actions.run_shell(
        outputs = [output],
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
        if hasattr(dep.info, "lib"):
            inputs.append(dep.info.lib)

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

    out = ctx.actions.declare_file("haxelib_path_{}".format(path_suffix))
    haxe_haxelib_path(ctx, haxelib, version, out, runfiles + [install_out], deps)
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

    if toolchain.internal.haxe_dir:
        command = toolchain.internal.haxe_dir + "/haxe"
    else:
        command = "haxe"

    command += " -p " + toolchain.internal.utils_file.dirname
    command += " --run Utils.hx genMainTest"
    for f in srcs:
        command += " " + f.path
    command += " > " + out.path

    ctx.actions.run_shell(
        outputs = [out],
        command = command,
    )

def haxe_create_final_jar(ctx, srcs, intermediate, output, jar_name, strip = True, include_sources = True):
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
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    if toolchain.internal.haxe_dir:
        command = toolchain.internal.haxe_dir + "/haxe"
    else:
        command = "haxe"
    command += " -p " + toolchain.internal.utils_file.dirname
    command += " --run Utils.hx createFinalJar {}/{} {}/{} {} {}".format(intermediate.path, jar_name, output.path, jar_name, "true" if strip else "false", "true" if include_sources else "false")
    for file in srcs:
        command += " " + file.path

    ctx.actions.run_shell(
        outputs = [output],
        inputs = [intermediate],
        command = command,
        use_default_shell_env = True,
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

    if toolchain.internal.neko_dir:
        neko_path = toolchain.internal.neko_dir + "/neko"
    else:
        neko_path = "neko"

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
            script_content += "{} {}/{}".format(neko_path, target, lib_name).replace("/", "\\")
        elif target == "java":
            script_content += "java -jar {}/{}".format(target, lib_name).replace("/", "\\")
        elif target == "python":
            script_content += "python {}/{}".format(target, lib_name).replace("/", "\\")
        elif target == "php":
            php_ini_var = ""
            if "PHP_INI" in ctx.var:
                php_ini_var = "-c {}".format(ctx.var["PHP_INI"])
            script_content += "php {} {}/{}/index.php".format(php_ini_var, target, lib_name).replace("/", "\\")
        else:
            fail("Invalid target {}".format(target))
        script_content += " %*"
    else:
        if toolchain.internal.haxe_dir:
            script_content += "set PATH={};$PATH\n".format(toolchain.internal.haxe_dir)
        if toolchain.internal.neko_dir:
            script_content += "set PATH={};$PATH\n".format(toolchain.internal.neko_dir)
        for e in toolchain.internal.env:
            script_content += "set {}={}\n".format(e, toolchain.internal.env[e])

        if target == "neko":
            script_content += "{} {}/{}".format(neko_path, target, lib_name)
        elif target == "java":
            script_content += "java -jar {}/{}".format(target, lib_name)
        elif target == "python":
            script_content += "python {}/{}".format(target, lib_name)
        elif target == "php":
            script_content += "php {}/{}".format(target, lib_name).replace("/", "\\")
        else:
            fail("Invalid target {}".format(target))
        script_content += " \"$@\""

    ctx.actions.write(
        output = out,
        content = script_content,
        is_executable = True,
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
    haxe_dir = None
    neko_dir = None

    for f in ctx.files.tools:
        if f.path.endswith("/haxe") or f.path.endswith("/haxe.exe"):
            haxe_cmd = f
        if f.path.endswith("/neko") or f.path.endswith("/neko.exe"):
            neko_cmd = f
        if f.path.endswith("/haxelib_file"):
            haxelib_file = f
        if f.path.endswith("/Utils.hx"):
            utils_file = f
        if f.path.endswith("/run_haxe.sh"):
            run_haxe_file = f
        if f.path.endswith("/haxelib_install.sh"):
            haxelib_install_file = f

    if haxe_cmd:
        haxe_dir = haxe_cmd.dirname
        # fail("could not locate haxe command")

    if neko_cmd:
        neko_dir = neko_cmd.dirname
        # fail("could not locate neko command")

    if not haxelib_file:
        fail("could not locate haxelib file")
    if not utils_file:
        fail("could not locate Utils.hx file")
    if not run_haxe_file:
        fail("could not locate run_haxe.sh file")
    if not haxelib_install_file:
        fail("could not locate haxelib_install.sh file")

    env = {
        "HAXELIB_PATH": haxelib_file.dirname,
    }

    return [platform_common.ToolchainInfo(
        # Public toolchain interface.
        compile = haxe_compile,
        haxelib_install = haxe_haxelib_install,
        create_test_class = haxe_create_test_class,
        create_run_script = haxe_create_run_script,
        create_final_jar = haxe_create_final_jar,

        # Internal data. Contents may change without notice.
        internal = struct(
            haxe_dir = haxe_dir,
            neko_dir = neko_dir,
            utils_file = utils_file,
            run_haxe_file = run_haxe_file,
            haxelib_install_file = haxelib_install_file,
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
    },
)
