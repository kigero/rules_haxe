load(":rules_test.bzl", "haxe_rules_test_suite")
load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")

toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)

exports_files([
    "utilities/postprocess_dox.py",
])

haxe_rules_test_suite(
    name = "haxe_rules_test",
)

stardoc(
    name = "docs",
    out = "haxe_rules_doc.md",
    input = "def.bzl",
)
