workspace(name = "rules_haxe")

load("//:def.bzl", "haxe_download_windows_amd64")

haxe_download_windows_amd64(
    name = "haxe_windows_amd64",
)

register_toolchains(
    "@haxe_windows_amd64//:toolchain",
)

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "bazel_skylib",
    sha256 = "1c531376ac7e5a180e0237938a2536de0c54d93f5c278634818e0efc952dd56c",
    urls = [
        "https://github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
    ],
)

load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")

bazel_skylib_workspace()

local_repository(
    name = "test-module-a",
    path = "test-resources/packages/module-a",
)

local_repository(
    name = "test-module-b",
    path = "test-resources/packages/module-b",
)

local_repository(
    name = "test-module-dist",
    path = "test-resources/packages/module-dist",
)
