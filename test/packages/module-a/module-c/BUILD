load("@rules_haxe//:def.bzl", "haxe_executable", "haxe_project_definition")

haxe_project_definition(
    name = "haxe-def",
    srcs = glob(["src/main/haxe/**/*.hx"]),
    debug = True,
    library_name = "dist-test-c",
    resources = [],
    visibility = ["//visibility:public"],
    deps = [],
)

haxe_executable(
    name = "neko-bin",
    debug = True,
    main_class = "com.c.ModuleC",
    target = "neko",
    visibility = ["//visibility:public"],
    deps = ["//module-c:haxe-def"],
)
