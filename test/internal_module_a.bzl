"""
Test that the build parameters for an internal source directory are computed correctly.  The build should be within
this bazel work directory.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//:providers.bzl", "HaxeLibraryInfo")
load("//:def.bzl", "haxe_library")

def _internal_module_a_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    asserts.equals(env, ["test/standalone/module-a/src/main/haxe/com/a/ModuleA.hx"], target_under_test[HaxeLibraryInfo].hxml["source_files"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/test/module-a-lib", target_under_test[HaxeLibraryInfo].lib.path)

    return analysistest.end(env)

internal_module_a_test = analysistest.make(_internal_module_a_test_impl)

def test_internal_module_a():
    haxe_library(
        name = "module-a-lib",
        srcs = native.glob(["standalone/module-a/src/main/haxe/**/*.hx"]),
        debug = True,
        tags = ["manual"],
    )

    internal_module_a_test(
        name = "internal_module_a_test",
        target_under_test = ":module-a-lib",
        size = "small",
    )
