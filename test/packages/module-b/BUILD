load("@rules_haxe//:def.bzl", "haxe_executable", "haxe_library", "haxe_project_definition")

haxe_project_definition(
    name = "haxe-def",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    library_name = "dist-test-b",
    resources = [],
    visibility = ["//visibility:public"],
    deps = [],
)

haxe_library(
    name = "neko-lib",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    tags = ["manual"],
    visibility = ["//visibility:public"],
    deps = ["@test-module-a//:haxe-def"],
)

haxe_executable(
    name = "java-bin",
    debug = True,
    target = "java",
    visibility = ["//visibility:public"],
    deps = ["//:haxe-def"],
)
