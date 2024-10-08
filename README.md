# Bazel Extension for Haxe

Contains Bazel rules for building and testing Haxe projects. This project is very much in progress and there's a good
chance it won't work.

Based on the simple Go example [here](https://github.com/jayconrod/rules_go_simple).

A shell environment on Windows is required, due to the use of `run_shell`, which calls a bash environment. At this
point there isn't a better way to set the environment needed for Haxe to run properly. Either cygwin or minGW bash
(provided by Git for Windows) should work, but if you have one or both on your path it can cause problems. If needed,
set an explicit shell with the BAZEL_SH environment variable.

The haxelib directory is in the same directory as the downloaded Haxe distribution; this allows haxelibs to be reused
across builds within the same project. This also means that currently sandboxing is not supported - if every process
runs in its own sandbox, it won't have easy access to the common haxelibs. So for now the `--spawn_strategy=local`
parameter must be passed to bazel if sandboxing is supported on your platform.

# Usage

In your WORKSPACE file, first specify the Haxe distribution to install with either `haxe_download_windows_amd64` or a
specific version with `haxe_download`. Next register the toolchain. So a minimal WORKSPACE file would look like this:

```
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

git_repository(
    name = "rules_haxe",
    branch = "master",
    remote = "https://github.com/kigero/rules_haxe",
)

load("@rules_haxe//:def.bzl", "haxe_download_windows_amd64")

haxe_download_windows_amd64(
    name = "haxe_windows_amd64",
)

register_toolchains(
    "@haxe_windows_amd64//:toolchain",
)
```

Note that an appropriate haxelib will automatically be added to the haxelibs list for the current target; for example if
the target is "java", the "hxjava" haxelib will automatically be added.

## Build library

```
load("@rules_haxe//:def.bzl", "haxe_library")

haxe_library(
    name = "neko-lib",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    library_name = "validation",
)
```

An alternative way of defining the library is to use the `haxe_project_definition` rule:

```
load("@rules_haxe//:def.bzl", "haxe_library")

haxe_project_definition(
    name = "haxe-def",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
)

haxe_library(
    name = "neko-lib",
    library_name = "validation",
    deps = ["//:haxe-def"],
)
```

The benefits to this route are:

1. If you have rules to build libraries for multiple targets, you can define the project once and depend on it from
   those targets, allowing a common configuration to be used.
1. If you have downstream projects that depend on this project, they can depend directly on the project definition
   rather than a build artifact for a specific target. This speeds up compilation of the downstream targets, and reduces
   the amount of boilerplate when those downstream projects build for multiple targets.

## Build executable

```
load("@rules_haxe//:def.bzl", "haxe_library")

haxe_executable(
    name = "neko-lib",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    executable_name = "validation",
    main_class = "com.example.Main"
)
```

## Test

```
load("@rules_haxe//:def.bzl", "haxe_test")

haxe_test(
    name = "neko-test",
    srcs = glob(["src/test/haxe/**/*.hx"]),
    haxelibs = {"hx3compat": "1.0.3"},
    deps = ["//:neko-lib"],
)
```

Notice that only the test sources are included here; the library sources actually being tested are brought in through
the `//:neko-lib` dependency. Alternatively you can include the library sources directly in the `srcs` attribute.

## Generate HXML File

This is handy for working within VSCode. It generates a build.hxml file based off the current configuration that works
with VSHaxe. The file is generated within the `bazel-bin` directory; it's recommended to then link to this file from
the project directory with `ln` or `mklink` so that VSHaxe can find it easily.

```
load("@rules_haxe//:def.bzl", "haxe_library", "haxe_gen_hxml")

haxe_gen_hxml(
    name = "gen-neko-hxml",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    hxml_name = "build-neko.hxml",
    library_name = "validation",
    target = "neko",
    visibility = ["//visibility:public"]
)
```

You have to provide the path to the `bazel-myproject` symlink on the command line so that the proper relative paths _from
the symlinked HXML file_ can be generated:

```
bazel build //:gen-neko-hxml --define=bazel_project_dir=%cd%/bazel-validation
```

## Haxe Std Lib

Generates a standard library that can be used for downstream projects that may need Haxe code, especially if the
`strip_haxe` parameter is being used when creating libraries. Currently this is only really tested for Java - it's
unknown yet whether other targets need this feature or not. The intended use case is where you're building a reusable
library in Haxe that gets included into a downstream jar; in that case you need the standard library to provide access
to the core Haxe stuff. The best practice is to use the common target from this package as it reduces compilation times
for multi-haxe project builds.

```
haxe_library(
    name = "myjava-lib",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    strip_haxe = True,
    library_name = "myjava",
)

java_library(
    name = "final-lib",
    srcs = glob(["src/main/java/**/*.java"]),
    deps = [
        "//:myjava-lib",
        "@rules_haxe//:std-java",
    ],
)
```

You can instantiate the rule locally as well if necessary.

When using a local toolchain (`haxe_no_install`), this module will try to find the location of the Haxe installation
that contains the Haxe source code. It does this by running `which haxe`, and if found, the directory containing the
haxe executable will be used to locate the source code. This directory can also be overridden by passing the
`HAXE_HOME` environment variable via an `action_env` parameter.

## Haxelib Build

In some instances you need to compile a haxelib directly to a target language - similar to the standard lib above.
That's what this rule is for. This configuration would compile the _hx3compat_ lib to java.

```
haxe_haxelib_lib(
    name = "hx3compat",
    include = ["haxe.unit"],
    haxelib = "hx3compat",
    target = "java",
    version = "1.0.4",
)
```

# Haxelibs

Dependent haxelibs can be a bit tricky at times.

-   To avoid multiple installations of the same version of a haxelib, a locking mechanism is used. If a haxelib install
    fails, the next time the process is run you will encounter a timeout period; after this period, the lock will be
    cleared and the install can be tried again. The lock may also be manually cleared by removing the directory at
    `bazel-projectname/external/haxe_os_cpu/haxelib_install.sh.lib`.
-   If there are errors when changing versions, a `bazel clean` should handle the issue.

# Targets

The targets that are currently actively supported are listed below; other targets may work.

-   neko
-   java
-   php
-   python
-   cpp (at least on windows)

## Java

You can specify the target java version to compile to by adding a variable definition like this (for java 1.8):

```
--define=haxe_java_target_version=1.8
```

Setting this variable sets the `-source` and `-target` compiler options in the HXML file to the value set. This
propagates to dependencies as well, so if you usually compile for Java 11 but you have one pesky deployment target that
uses Java 1.8, setting this should compile all the dependencies with Java 1.8.

If not set, the default java toolchain will be used to get the source and target version.

## CPP

On Windows (Linux has not been tested), getting the right MSVC environment can be... problematic. The HXCPP toolchain
bat files that look for the various installations of MSVC tend to look in hardcoded paths, which can make it hard to
pass in a variable that works for all situations.

-   For MSVC 2015 and below, setting `HXCPP_MSVC` to the directory containing either `vsvars32.bat` or `vcvars32.bat` in
    your environment, and then passing `--action_env=HXCPP_MSVC` either on the command line or in a bazelrc file, should
    work for both 32 and 64 bit installs.
-   It looks like MSVC 2017 improved on this situation a bit by including a `vswhere` program, which HXCPP utilizes, to
    locate the installation root of Visual Studio. The problem with this is that the bat files use the
    `ProgramFiles(x86)` substitution, which seems to be not a real environment variable but something special done by the
    batch processor. This causes issues: HXCPP spawns a new `cmd` shell to examine these variables, and for whatever
    reason this shell can't process that special variable. So with MSVC 2017, the capability is there in the bat files,
    but something with the nightmare that is cmd->bazel->bash->cmd the ability to use the right substitution to find that
    program is lost. As it turns out though, if that substitution can be made, HXCPP seems to work properly. So... the
    horrible solution that is currently implemented in this project: if the HXCPP haxelib is installed, any bat files in
    the haxelib's toolchain directory relating to finding MSVC variables are postprocessed to remove the substitution and
    instead set the default path to this folder. See the `templates/postprocess_hxcpp.sh` file for the exact command.
    Yes, editing files after the fact is terrible, but at this time I don't have a better solution. The only advantage is
    that you shouldn't need to pass any special CLI parameters to locate the MSVC installation. If/when this causes a
    problem, I'll revisit it then.

A CPP compiled project can be used as a dependency for a downstream `cc_library` or `cc_binary` rule. This support is
very basic at this time, but generally it should be available - at least on windows with MSVC. Of course there are some
caveats:

-   To build a static library, include `extra_args = ["-D static_link"]` in the `haxe_library` rule. This generates a
    .lib output.
-   To build a dynamic library, include `extra_args = ["-D dll_export", "-D dll_link"]` in the `haxe_library` rule. This
    generates a .dll and a .lib output.
-   The response includes a `CcInfo` provider with the compilation and linking context. Currently this is a bit messy.
    -   Headers must be File objects that end in an appropriate extension (e.g. `.h`). Directories of results, which is
        what we have as the exact set of headers isn't known until Haxe compiles the code, are allowed as long as they
        have the right extension. So the compilation context copies the includes to a separate folder ending in `.h`.
    -   The linking context includes the static or dynamic libraries based on the Haxe defines.

The resultant rule can be used like this:

```
haxe_library(
    name = "mylib",
    extra_args = [
        "-D dll_export",
        "-D dll_link",
    ],
    target = "cpp",
    deps = ["//:haxe-def"],
)

cc_binary(
    name = "Project",
    srcs = ["//:sources"],
    deps = [":mylib"],
)
```

In the source code, include the following:

```
#include <HxcppConfig-19.h>
extern "C"
{
	extern const char *hxRunLibrary();
}
...
void MyClass::myInitFunc() {
    // Initialize haxe.
    hxRunLibrary();
}
```

# Windows

Windows is a bit of a pain; you'll need symlink support as described in the [Bazel
docs](https://docs.bazel.build/versions/master/windows.html#enable-symlink-support), as well as some variables passed
through from the shell. At a minimum your .bazelrc or command line flags should have the following:

```
startup --windows_enable_symlinks
build --enable_runfiles --action_env=ComSpec --action_env=USERPROFILE
test --action_env=ComSpec --action_env=USERPROFILE
```

Unfortunately the variable specified in `--action_env` is case sensitive; if you have a few different environments that provide an environment variable in different cases (e.g. CMD vs Cygin) it appears you can just pass the parameter twice in the .bazelrc. If you need to use a proxy, you should also add `--action_env=HTTP_PROXY --action_env=HTTPS_PROXY` and set those variables accordingly.

# Rule Documentation

Documentation can be generated by running `bazel build //docs:docs`.

# Unit Tests

Unit tests of the rules can be executed with `bazel test //test:test`, possibly with the `--cache_test_results=no`
option to force tests to be run.
