load(":rules_test.bzl", "haxe_rules_test_suite")

toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)

exports_files([
    "utilities/postprocess_dox.py",
    "def.bzl",
])

haxe_rules_test_suite(
    name = "haxe_rules_test",
)
