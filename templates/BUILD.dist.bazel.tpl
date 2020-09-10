load("@rules_haxe//:def.bzl", "haxe_toolchain")

# Get the executables tools.
filegroup(
    name = "tools",
    srcs = glob(["**/haxe{exe}", "**/haxelib{exe}", "**/neko{exe}", "**/Utils.hx", "**/run_haxe.sh", "**/haxelib_install.sh", "**/neko-*/*", "**/haxelib_dir/haxelib_file"]),
    visibility = ["//visibility:public"],
)

# Instantiate the toolchain.
haxe_toolchain(
    name = "toolchain_impl",
    tools = [":tools"],
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