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

    # On Windows, haxelib cannot be a symlink or the shell spawned by the haxe command won't be able to run it.  Since
    # the tools directories are symlinked in, haxe can't run haxelib even though it's on the path.  Copy it to the local
    # directory if it doesn't already exist.
    haxelib_exe_out = ctx.actions.declare_file("haxelib_exe_out")
    ctx.actions.run_shell(
        outputs = [haxelib_exe_out],
        command = "rsync -q {} . > {}".format(toolchain.internal.haxelib_cmd.path, haxelib_exe_out.path),
        use_default_shell_env = True,
    )

    # Create a new haxelib repo in the execroot.  This is needed to get the haxelib shell used by the haxe command to be
    # able to access the haxelib repo, but unfortunately means a) every time the project is cleaned the libs will get
    # removed and must be redownloaded, and b) every project will have its own cache of the haxelibs for that project.
    haxelib_out = ctx.actions.declare_file("haxelib_repo")
    ctx.actions.run_shell(
        outputs = [haxelib_out],
        command = "haxelib newrepo > {}".format(haxelib_out.path),
        use_default_shell_env = True,
    )

    # Set up the PATH to include the toolchain directories.
    command = " export PATH={}:$PATH".format(toolchain.internal.env["PATH"])

    # Set the absolute path to the local haxelib repo.
    command += " && export HAXELIB_REPO=`pwd`/.haxelib"

    # Add the haxe command.
    command += " && {}".format(haxe_cmd)

    # Finally run the command.
    ctx.actions.run_shell(
        outputs = outputs,
        inputs = inputs + [haxelib_exe_out, haxelib_out],
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
        haxe_cmd = "haxe {}".format(hxml.path),
        mnemonic = "HaxeCompile",
    )

def _haxe_haxelib(ctx, haxelib, action, out, runfiles = None, deps = []):
    """
    Perform a haxelib action on some haxelib.
    
    Args:
        ctx: Bazel context.
        haxelib: The haxelib to perform the action on.
        action: The action to perform.
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
        haxe_cmd = "haxelib {} {} > {}".format(action, haxelib, out.path),
        mnemonic = "Haxelib",
    )

def haxe_haxelib_install(ctx, haxelib, out, deps = []):
    """
    Install a haxelib.  
    
    The output of this command will always be the result of `haxelib path <haxelib>`.  An error is not thrown if the 
    haxelib is already installed.
    
    Args:
        ctx: Bazel context.
        haxelib: The haxelib to install.
        out: A file that captures the "path" information of the haxelib command.
        deps: Any deps needed by the compilation.
    """
    install_out = ctx.actions.declare_file("haxelib_install_out-{}".format(haxelib))
    _haxe_haxelib(ctx, haxelib, "install", install_out, deps)
    _haxe_haxelib(ctx, haxelib, "path", out, [install_out], deps)

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
    command += " -p " + toolchain.internal.gen_main_test_file.dirname
    command += " --run GenMainTest.hx"
    for i, d in enumerate(srcs):
        for f in d.files.to_list():
            command += " " + f.path
    command += " > " + out.path

    ctx.actions.run_shell(
        outputs = [out],
        command = command,
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
    gen_main_test_file = None
    for f in ctx.files.tools:
        if f.path.endswith("/haxe") or f.path.endswith("/haxe.exe"):
            haxe_cmd = f
        if f.path.endswith("/haxelib") or f.path.endswith("/haxelib.exe"):
            haxelib_cmd = f
        if f.path.endswith("/neko") or f.path.endswith("/neko.exe"):
            neko_cmd = f
        if f.path.endswith("/haxelib_file"):
            haxelib_file = f
        if f.path.endswith("/GenMainTest.hx"):
            gen_main_test_file = f

    if not haxe_cmd:
        fail("could not locate haxe command")
    if not haxelib_cmd:
        fail("could not locate haxelib command")
    if not neko_cmd:
        fail("could not locate neko command")
    if not haxelib_file:
        fail("could not locate haxelib file")
    if not gen_main_test_file:
        fail("could not locate GenMainTest file")

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

        # Internal data. Contents may change without notice.
        internal = struct(
            haxe_cmd = haxe_cmd,
            haxelib_cmd = haxelib_cmd,
            neko_cmd = neko_cmd,
            gen_main_test_file = gen_main_test_file,
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
