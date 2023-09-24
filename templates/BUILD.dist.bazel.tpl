load("@rules_haxe//:def.bzl", "haxe_toolchain")

# Get the executables tools.
filegroup(
    name = "tools",
    srcs = glob(["**/haxe{exe}", "**/haxelib{exe}", "**/neko{exe}", "**/RulesHaxeUtils.hx", "**/run_haxe.sh", "**/haxelib_install.sh", "**/postprocess_hxcpp.sh",  "**/copy_hxcpp_includes.sh", "**/neko-*/*", "**/haxelib_dir/haxelib_file", "**/postprocess_dox.py"]),
    visibility = ["//visibility:public"],
)

py_binary(
    name = "postprocess_dox",
    srcs = ["postprocess_dox.py"],
)

# Instantiate the toolchain.
haxe_toolchain(
    name = "toolchain_impl",
    postprocess_dox = ":postprocess_dox",
    tools = [":tools"],
    cpp_toolchain = "@local_config_cc//:toolchain",
)

# Define the target toolchain; this is registered by users of this repository..
toolchain(
    name = "toolchain",
    exec_compatible_with = [
        {exec_constraints},
    ],
    target_compatible_with = [
        {target_constraints},
    ],
    toolchain = ":toolchain_impl",
    toolchain_type = "@rules_haxe//:toolchain_type",
)