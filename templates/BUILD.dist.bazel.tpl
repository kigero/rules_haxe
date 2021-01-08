load("@rules_haxe//:def.bzl", "haxe_toolchain")

# Get the executables tools.
filegroup(
    name = "tools",
    srcs = glob(["**/haxe{exe}", "**/haxelib{exe}", "**/neko{exe}", "**/Utils.hx", "**/run_haxe.sh", "**/haxelib_install.sh", "**/postprocess_hxcpp.sh", "**/neko-*/*", "**/haxelib_dir/haxelib_file", "**/postprocess_dox.py"]),
    visibility = ["//visibility:public"],
)

py_binary(
    name = "postprocess_dox",
    srcs = ["postprocess_dox.py"],
)

# Instantiate the toolchain.
haxe_toolchain(
    name = "toolchain_impl",
    tools = [":tools", ":postprocess_dox"],
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