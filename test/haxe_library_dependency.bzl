"""
Test that the build parameters for external modules with dependencies are computed correctly.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//:providers.bzl", "HaxeLibraryInfo")
load("//:utils.bzl", "determine_source_root")

def _haxe_library_dependency_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    hxml = target_under_test[HaxeLibraryInfo].hxml
    asserts.equals(env, 2, len(hxml["source_files"]))
    asserts.equals(env, "module-lib-intermediate", hxml["output_dir"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/test-module-dist/module-lib", target_under_test[HaxeLibraryInfo].lib.path)
    asserts.equals(env, "external/test-module-a/", determine_source_root(hxml["source_files"][0]))

    return analysistest.end(env)

haxe_library_dependency_test = analysistest.make(_haxe_library_dependency_test_impl)

def test_haxe_library_dependency():
    haxe_library_dependency_test(
        name = "haxe_library_dependency_test",
        target_under_test = "@test-module-dist//:module-lib",
        size = "small",
    )
