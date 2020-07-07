load("@rules_haxe//:def.bzl", "haxe_toolchain")

# Get the executables tools.
filegroup(
    name = "tools",
    srcs = glob(["**/haxe{exe}", "**/haxelib{exe}", "**/neko{exe}", "**/GenMainTest.hx", "**/neko-*/*"]),
    visibility = ["//visibility:public"],
)

# Create a directory to store haxelibs.
genrule(
    name = "CreateHaxelibDirectory",
    outs = ["haxelib/haxelib_file"],
    cmd = "mkdir -p haxelib && touch $@",
)

# Instantiate the toolchain.
haxe_toolchain(
    name = "toolchain_impl",
    tools = [":tools", ":CreateHaxelibDirectory"],
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