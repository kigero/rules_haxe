"""
Test that the build parameters for an external module are computed correctly.  Since the external module is defined
within the workspace of this project, the build should be in the 'external' section of the bazel work directory.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//:providers.bzl", "HaxeLibraryInfo")

def _external_module_a_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    asserts.equals(env, ["external/test-module-a/src/main/haxe/com/a/ModuleA.hx"], target_under_test[HaxeLibraryInfo].hxml["source_files"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/test-module-a/neko-lib", target_under_test[HaxeLibraryInfo].lib.path)

    return analysistest.end(env)

external_module_a_test = analysistest.make(_external_module_a_test_impl)

def test_external_module_a():
    external_module_a_test(
        name = "external_module_a_test",
        target_under_test = "@test-module-a//:neko-lib",
        size = "small",
    )
