"""
Unit tests.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//:providers.bzl", "HaxeLibraryInfo")
load("//:utils.bzl", "determine_source_root")
load("//:def.bzl", "haxe_library")

###############################################################################
# Test that the build parameters for an external module are computed correctly.  Since the external module is defined
# within the workspace of this project, the build should be in the 'external' section of the bazel work directory.
###############################################################################
def _external_module_a_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    asserts.equals(env, ["external/test-module-a/src/main/haxe/com/a/ModuleA.hx"], target_under_test[HaxeLibraryInfo].hxml["source_files"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/test-module-a/neko-lib", target_under_test[HaxeLibraryInfo].lib.path)

    return analysistest.end(env)

external_module_a_test = analysistest.make(_external_module_a_test_impl)

def _test_external_module_a():
    external_module_a_test(
        name = "external_module_a_test",
        target_under_test = "@test-module-a//:neko-lib",
        size = "small",
    )

###############################################################################
# Test that the build parameters for an internal source directory are computed correctly.  The build should be within
# this bazel work directory.
###############################################################################

def _internal_module_a_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    asserts.equals(env, ["test/standalone/module-a/src/main/haxe/com/a/ModuleA.hx"], target_under_test[HaxeLibraryInfo].hxml["source_files"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/test/module-a-lib", target_under_test[HaxeLibraryInfo].lib.path)

    return analysistest.end(env)

internal_module_a_test = analysistest.make(_internal_module_a_test_impl)

def _test_internal_module_a():
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

###############################################################################
# Test that the build parameters for external modules with dependencies are computed correctly.
###############################################################################

def _haxe_library_dependency_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    ######
    ## ARE THESE VALUES RIGHT???
    ######

    hxml = target_under_test[HaxeLibraryInfo].hxml
    asserts.equals(env, 2, len(hxml["source_files"]))
    asserts.equals(env, "module-lib-intermediate", hxml["output_dir"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/test-module-dist/module-lib", target_under_test[HaxeLibraryInfo].lib.path)
    asserts.equals(env, "external/test-module-a/", determine_source_root(hxml["source_files"][0]))

    return analysistest.end(env)

haxe_library_dependency_test = analysistest.make(_haxe_library_dependency_test_impl)

def _test_haxe_library_dependency():
    haxe_library_dependency_test(
        name = "haxe_library_dependency_test",
        target_under_test = "@test-module-dist//:module-lib",
        size = "small",
    )

def _haxe_executable_dependency_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    ######
    ## ARE THESE VALUES RIGHT???
    ######

    hxml = target_under_test[HaxeLibraryInfo].hxml
    asserts.equals(env, 2, len(hxml["source_files"]))
    asserts.equals(env, "module-bin", hxml["output_dir"])
    asserts.equals(env, "bazel-out/x64_windows-fastbuild/bin/external/test-module-dist/module-bin", target_under_test[HaxeLibraryInfo].lib.path)
    asserts.equals(env, "external/test-module-a/", determine_source_root(hxml["source_files"][0]))

    return analysistest.end(env)

haxe_executable_dependency_test = analysistest.make(_haxe_executable_dependency_test_impl)

def _test_haxe_executable_dependency():
    haxe_executable_dependency_test(
        name = "haxe_executable_dependency_test",
        target_under_test = "@test-module-dist//:module-bin",
        size = "small",
    )

###############################################################################

def haxe_rules_test_suite(name):
    """
    Test suite for haxe rules.
        
    Args:
        name: The name of the test suite rule.
    """
    _test_external_module_a()
    _test_internal_module_a()
    _test_haxe_library_dependency()
    _test_haxe_executable_dependency()

    native.test_suite(
        name = name,
        tests = [
            ":external_module_a_test",
            ":internal_module_a_test",
            ":haxe_library_dependency_test",
            ":haxe_executable_dependency_test",
        ],
    )
