"""
Test that the build parameters for external modules with dependencies are computed correctly.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//:providers.bzl", "HaxeLibraryInfo")
load("//:utils.bzl", "determine_source_root")

# This test runss a target in the root package that depends on a target in the subpackage.
def _haxe_executable_subpackage_from_root_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    hxml = target_under_test[HaxeLibraryInfo].hxml
    asserts.equals(env, 1, len(hxml["source_files"]))
    asserts.equals(env, "neko-bin-c", hxml["output_dir"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/test-module-a/neko-bin-c", target_under_test[HaxeLibraryInfo].lib.path)
    asserts.equals(env, "external/test-module-a/", determine_source_root(hxml["source_files"][0]))

    # The directory portion 'external/dist-test-c/' in this test comes from the fact that the test is being loaded via a
    # dependent module below, in the target_under_test parameter.  When run in the test directory itself, the value is
    # correct, without the 'external/dist-test-c/'.
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/dist-test-c/neko-bin-c/dist-test-c", hxml["build_file"])

    return analysistest.end(env)

haxe_executable_subpackage_from_root_test = analysistest.make(_haxe_executable_subpackage_from_root_test_impl)

def test_haxe_executable_subpackage_from_root():
    haxe_executable_subpackage_from_root_test(
        name = "haxe_executable_subpackage_from_root_test",
        target_under_test = "@test-module-a//:neko-bin-c",
        size = "small",
    )

# This test runs a target in a subpackage from the root package.
def _haxe_executable_subpackage_from_subpackage_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    hxml = target_under_test[HaxeLibraryInfo].hxml
    asserts.equals(env, 1, len(hxml["source_files"]))
    asserts.equals(env, "neko-bin", hxml["output_dir"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/test-module-a/module-c/neko-bin", target_under_test[HaxeLibraryInfo].lib.path)
    asserts.equals(env, "external/test-module-a/", determine_source_root(hxml["source_files"][0]))
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/dist-test-c/module-c/neko-bin/dist-test-c", hxml["build_file"])

    return analysistest.end(env)

haxe_executable_subpackage_from_subpackage_test = analysistest.make(_haxe_executable_subpackage_from_subpackage_test_impl)

def test_haxe_executable_subpackage_from_subpackage():
    haxe_executable_subpackage_from_subpackage_test(
        name = "haxe_executable_subpackage_from_subpackage_test",
        target_under_test = "@test-module-a//module-c:neko-bin",
        size = "small",
    )
