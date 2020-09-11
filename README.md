# Bazel Extension for Haxe

Contains Bazel rules for building and testing Haxe projects.  This project is very much in progress and there's a good
chance it won't work.

Based on the simple Go example [here](https://github.com/jayconrod/rules_go_simple).

Currently supports the neko and java targets.

On Windows, CYGWIN is required!  This is due to the use of `run_shell`, which calls a bash environment.  At this point
there isn't a better way to set the environment needed for Haxe to run properly.  

The haxelib directory is in the same directory as the downloaded Haxe distribution; this allows haxelibs to be reused
across builds within the same project.  This also means that currently sandboxing is not supported - if every process
runs in its own sandbox, it won't have easy access to the common haxelibs.  So for now the `--spawn_strategy=local`
parameter must be passed to bazel if sandboxing is supported on your platform.

# Usage

In your WORKSPACE file, first specify the Haxe distribution to install with either `haxe_download_windows_amd64` or a
specific version with `haxe_download`.  Next register the toolchain.  So a minimal WORKSPACE file would look like this:
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

## Test

```
load("@rules_haxe//:def.bzl", "haxe_test")

haxe_test(
    name = "neko-test",
    srcs = glob([
        "src/main/haxe/**/*.hx",
        "src/test/haxe/**/*.hx",
    ]),
    haxelibs = {"hx3compat": "1.0.3"},
)
```

## Generate HXML File

This is handy for working within VSCode.  It generates a build.hxml file based off the current configuration that works
with VSHaxe.  The file is generated within the `bazel-bin` directory; it's recommended to then link to this file from
the project directory with `ln` or `mklink` so that VSHaxe can find it easily.

```
load("@rules_haxe//:def.bzl", "haxe_library", "haxe_gen_hxml")

haxe_gen_hxml(
    name = "gen-neko-hxml",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    bazel_workspace_path = "bazel-validation",
    debug = True,
    hxml_name = "build-neko.hxml",
    library_name = "validation",
    target = "neko",
    visibility = ["//visibility:public"]
)
```


## Windows

Windows is a bit of a pain; you'll need symlink support as described in the [Bazel
docs](https://docs.bazel.build/versions/master/windows.html#enable-symlink-support), as well as some variables passed
through from the shell.  At a minimum your .bazelrc or command line flags should have the following:
```
startup --windows_enable_symlinks
build --enable_runfiles --action_env=ComSpec --action_env=USERPROFILE
test --action_env=ComSpec --action_env=USERPROFILE
```
Unfortunately the variable specified in `--action_env` is case sensitive; if you have a few different environments that provide an environment variable in different cases (e.g. CMD vs Cygin) it appears you can just pass the parameter twice in the .bazelrc.
