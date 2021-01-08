"""
Unit test suite.
"""

load("//test:external_module_a.bzl", "test_external_module_a")
load("//test:internal_module_a.bzl", "test_internal_module_a")
load("//test:haxe_executable_dependency.bzl", "test_haxe_executable_dependency")
load("//test:haxe_library_dependency.bzl", "test_haxe_library_dependency")
load("//test:haxe_executable_subpackage.bzl", "test_haxe_executable_subpackage_from_root", "test_haxe_executable_subpackage_from_subpackage")

###############################################################################

def haxe_rules_test_suite(name):
    """
    Test suite for haxe rules.
        
    Args:
        name: The name of the test suite rule.
    """
    test_external_module_a()
    test_internal_module_a()
    test_haxe_library_dependency()
    test_haxe_executable_dependency()
    test_haxe_executable_subpackage_from_root()
    test_haxe_executable_subpackage_from_subpackage()

    native.test_suite(
        name = name,
        tests = [
            ":external_module_a_test",
            ":internal_module_a_test",
            ":haxe_library_dependency_test",
            ":haxe_executable_dependency_test",
            ":haxe_executable_subpackage_from_root_test",
            ":haxe_executable_subpackage_from_subpackage_test",
        ],
    )
