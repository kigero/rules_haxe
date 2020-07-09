# Bazel Extension for Haxe

Contains Bazel rules for building and testing Haxe projects.  This project is very much in progress and there's a good
chance it won't work.

Based on the simple Go example [here](https://github.com/jayconrod/rules_go_simple).

Currently supports the neko and java targets.

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

Next, in the BUILD file you want to use the `haxe_library` and `haxe_test` rules to build libraries and test your code respectively.

```
load("@rules_haxe//:def.bzl", "haxe_library", "haxe_test")

haxe_library(
    name = "neko-lib",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    library_name = "validation",
)

haxe_test(
    name = "neko-test",
    srcs = glob([
        "src/main/haxe/**/*.hx",
        "src/test/haxe/**/*.hx",
    ]),
    haxelibs = ["hx3compat"],
)
```
Note that an appropriate haxelib will automatically be added to the haxelibs list for the current target; for example if
the target is "java", the "hxjava" haxelib will automatically be added.

## Windows

Windows is a bit of a pain; you'll need symlink support as described in the [Bazel
docs](https://docs.bazel.build/versions/master/windows.html#enable-symlink-support), as well as some variables passed
through from the shell.  At a minimum your .bazelrc or command line flags should have the following:
```
startup --windows_enable_symlinks
build --enable_runfiles --action_env=ComSpec --action_env=USERPROFILE
test --action_env=ComSpec --action_env=USERPROFILE
```

# Known Issues

* On windows (maybe other platforms, haven't tested it) running multiple builds at the same time can lead to an "Access
  is denied" error.  As best as I can tell, this happens when a haxelib is being installed for one build while another
  build attempts to use any haxelib in a compile, but the error is coming from the haxe compilation and gives no
  indication as to the underlying issue.  Typically this only happens the first time after a clean; running the same
  command again will complete OK.   