load("@rules_haxe//:def.bzl", "haxe_executable", "haxe_library", "haxe_project_definition")

haxe_project_definition(
    name = "haxe-def",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    library_name = "dist-test-a",
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
)

haxe_executable(
    name = "java-bin",
    debug = True,
    target = "java",
    visibility = ["//visibility:public"],
    deps = ["//:haxe-def"],
)

haxe_executable(
    name = "java-bin-ac",
    debug = True,
    target = "java",
    visibility = ["//visibility:public"],
    deps = [
        "//:haxe-def",
        "//module-c:haxe-def",
    ],
)

haxe_executable(
    name = "neko-bin-c",
    debug = True,
    main_class = "com.c.ModuleC",
    target = "neko",
    visibility = ["//visibility:public"],
    deps = [
        "//module-c:haxe-def",
    ],
)
