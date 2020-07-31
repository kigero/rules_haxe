"""
Defines the Haxe toolchain.
"""

def _run_haxe(ctx, inputs, outputs, toolchain, haxe_cmd, mnemonic = None):
    """
    Runs a Haxe command using run_shell.  
    
    Some preliminary environment is set up before running the command.
    
    Args:
        ctx: Bazel context.
        inputs: Any inputs needed by run_shell.
        outputs: Any outputs needed by run_shell.
        toolchain: The haxe toolchain instance.
        haxe_cmd: The actual haxe command to run; may be a haxe or haxelib command, e.g. `haxe build.hxml` or `haxelib install hx3compat`.
        mnemonic: The mnemonic to pass to run_shell.
    """
    path = ""
    path += "`pwd`/{}:".format(toolchain.internal.haxe_cmd.dirname)
    path += "`pwd`/{}:".format(toolchain.internal.neko_cmd.dirname)
    path += "$PATH"

    # Set up the PATH to include the toolchain directories.
    command = " export PATH={}".format(path)

    # Set the absolute path to the local haxelib repo.
    command += " && export HAXELIB_PATH=`pwd`/{}".format(toolchain.internal.env["HAXELIB_PATH"])

    # If on windows, the HAXELIB_PATH needs to be a windows path.
    if ctx.var["TARGET_CPU"].upper().index("WINDOWS") >= 0:
        command += " && export HAXELIB_PATH=`cygpath -w $HAXELIB_PATH`"

    # Add the haxe command.  Redirecting stdout to /dev/null seems OK - warnings and errors still show up on the screen.
    command += " && {} > /dev/null".format(haxe_cmd)

    # Finally run the command.
    ctx.actions.run_shell(
        outputs = outputs,
        inputs = inputs,
        command = command,
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

    inputs = (
        [hxml] +
        [dep.info.lib for dep in deps] +
        toolchain.internal.tools
    )

    if runfiles != None:
        inputs += runfiles

    _run_haxe(
        ctx,
        inputs = inputs,
        outputs = [out],
        toolchain = toolchain,
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
        outputs = [out],
        toolchain = toolchain,
        haxe_cmd = "haxelib {} > {}".format(cmd, out.path),
        mnemonic = "Haxelib",
    )

def haxe_haxelib_path(ctx, haxelib, out, runfiles = [], deps = []):
    """
    Get the path information for a haxelib.
    
    Args:
        ctx: Bazel context.
        haxelib: The haxelib to install.
        out: A file that captures the "path" information of the haxelib command.
        runfiles: Any runfiles needed by the compilation.
        deps: Any deps needed by the compilation.
    """
    _haxe_haxelib(ctx, "path {}".format(haxelib), out, runfiles, deps)

def haxe_haxelib_install(ctx, haxelib, version, out, runfiles = [], deps = []):
    """
    Install a haxelib.  
    
    The output of this command will always be the result of `haxelib path <haxelib>`.  An error is not thrown if the 
    haxelib is already installed.
    
    Args:
        ctx: Bazel context.
        haxelib: The haxelib to install.
        version: The version of the haxelib to perform the action on; specify "git:<repo_url>" to use a git repository.
        out: A file that captures the "path" information of the haxelib command.
        runfiles: Any runfiles needed by the compilation.
        deps: Any deps needed by the compilation.
    """
    install_out = ctx.actions.declare_file("haxelib_install_out-{}".format(haxelib))
    if version != None and version != "":
        if version.startswith("git:"):
            cmd = "git {} {}".format(haxelib, version[4:])
        else:
            cmd = "install {} {}".format(haxelib, version)
    else:
        cmd = "install {}".format(haxelib)

    _haxe_haxelib(ctx, cmd, install_out, runfiles, deps)
    haxe_haxelib_path(ctx, haxelib, out, runfiles + [install_out], deps)

def haxe_create_test_class(ctx, srcs, out):
    """
    Create the main test class for a set of unit test files.
    
    Args:
        ctx: Bazel context.
        srcs: The sources to search for unit test files.
        out: The MainTest.hx file that calls the individual unit tests.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    command = toolchain.internal.haxe_cmd.path
    command += " -p " + toolchain.internal.utils_file.dirname
    command += " --run Utils.hx genMainTest"
    for i, d in enumerate(srcs):
        for f in d.files.to_list():
            command += " " + f.path
    command += " > " + out.path

    ctx.actions.run_shell(
        outputs = [out],
        command = command,
    )

def haxe_create_final_jar(ctx, srcs, intermediate, output, strip = True, include_sources = True):
    """
    Create the final jar file, which strips out haxe classes and adds source files.
    
    Args:
        ctx: Bazel context.
        srcs: The sources to search for unit test files.
        intermediate: The intermediate jar file.
        output: The final jar file.
        strip: Strip out haxe classes.
        include_sources: Include the Java sources in the jar.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    command = toolchain.internal.haxe_cmd.path
    command += " -p " + toolchain.internal.utils_file.dirname
    command += " --run Utils.hx createFinalJar {} {} {} {}".format(intermediate.path, output.path, "true" if strip else "false", "true" if include_sources else "false")
    for i, d in enumerate(srcs):
        for f in d.files.to_list():
            command += " " + f.path

    ctx.actions.run_shell(
        outputs = [output],
        inputs = [intermediate],
        command = command,
        use_default_shell_env = True,
    )

def haxe_create_run_script(ctx, target, lib, out):
    """
    Create a run script usable by Bazel for running the unit tests.
    
    Args:
        ctx: Bazel context.
        target: The target platform.
        lib: The path to the compiled unit test library.
        out: The path to the run script.  If this path ends in '.bat' a Windows bat script will be generated, otherwise 
        a bash script is generated.
    """
    toolchain = ctx.toolchains["@rules_haxe//:toolchain_type"]

    lib_path = lib.dirname[lib.dirname.rindex("/") + 1:] + "/" + lib.basename

    script_content = ""
    if out.path.endswith(".bat"):
        for e in toolchain.internal.env:
            if e.lower() == "path":
                script_content += "SET PATH={};%PATH%\n".format(toolchain.internal.env[e]).replace("/", "\\")
            else:
                script_content += "SET {}={}\n".format(e, toolchain.internal.env[e]).replace("/", "\\")

        if target == "neko":
            script_content += "{} {}".format(toolchain.internal.neko_cmd.path, lib_path).replace("/", "\\")
        elif target == "java":
            script_content += "java -jar java/{}".format(lib_path).replace("/", "\\")
        else:
            fail("Invalid target {}".format(target))
    else:
        script_content += "{} {}".format(toolchain.internal.neko_cmd.path, lib_path)

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
    haxelib_cmd = None
    haxelib_file = None
    neko_cmd = None
    utils_file = None
    for f in ctx.files.tools:
        if f.path.endswith("/haxe") or f.path.endswith("/haxe.exe"):
            haxe_cmd = f
        if f.path.endswith("/haxelib") or f.path.endswith("/haxelib.exe"):
            haxelib_cmd = f
        if f.path.endswith("/neko") or f.path.endswith("/neko.exe"):
            neko_cmd = f
        if f.path.endswith("/haxelib_file"):
            haxelib_file = f
        if f.path.endswith("/Utils.hx"):
            utils_file = f

    if not haxe_cmd:
        fail("could not locate haxe command")
    if not haxelib_cmd:
        fail("could not locate haxelib command")
    if not neko_cmd:
        fail("could not locate neko command")
    if not haxelib_file:
        fail("could not locate haxelib file")
    if not utils_file:
        fail("could not locate Utils.hx file")

    env = {
        "PATH": haxe_cmd.dirname + ":" + neko_cmd.dirname,
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
            haxe_cmd = haxe_cmd,
            haxelib_cmd = haxelib_cmd,
            neko_cmd = neko_cmd,
            utils_file = utils_file,
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
