load("@rules_haxe//:def.bzl", "haxe_std_lib")

toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)

exports_files([
    "utilities/postprocess_dox.py",
    "def.bzl",
])

haxe_std_lib(
    name = "std-java",
    target = "java",
    visibility = ["//visibility:public"],
)
