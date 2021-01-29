load("@rules_haxe//:def.bzl", "haxe_executable", "haxe_library", "haxe_project_definition")
load("@rules_java//java:defs.bzl", "java_library")

haxe_project_definition(
    name = "module-def",
    srcs = [],
    debug = True,
    library_name = "dist-test",
    main_class = "com.b.ModuleB",
    resources = [],
    visibility = ["//visibility:public"],
    deps = [
        "@test-module-a//:haxe-def",
        "@test-module-b//:haxe-def",
    ],
)

haxe_library(
    name = "module-lib",
    debug = True,
    tags = ["manual"],
    visibility = ["//visibility:public"],
    deps = ["//:module-def"],
)

haxe_executable(
    name = "module-bin",
    debug = True,
    main_class = "com.b.ModuleB",
    tags = ["manual"],
    visibility = ["//visibility:public"],
    deps = ["//:module-def"],
)

java_library(
    name = "module-jar",
    srcs = glob(["src/main/java/**/*.java"]),
    visibility = ["//visibility:public"],
    deps = [
        "@test-module-b//:java-lib",
    ],
)
