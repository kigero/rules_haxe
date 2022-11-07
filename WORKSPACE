workspace(name = "rules_haxe")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

# Allow these rules to be used within unit tests.
load("//:def.bzl", "haxe_download_windows_amd64", "haxe_no_install")

haxe_download_windows_amd64(
    name = "haxe_windows_amd64",
)

haxe_no_install(
    name = "haxe_no_install",
)

register_toolchains(
    "@haxe_windows_amd64//:toolchain",
    "@haxe_no_install//:toolchain",
)

# Skylib, for unit testing.
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

# Stardoc, for documentation generation.
git_repository(
    name = "io_bazel_stardoc",
    remote = "https://github.com/bazelbuild/stardoc.git",
    tag = "0.4.0",
)

load("@io_bazel_stardoc//:setup.bzl", "stardoc_repositories")

stardoc_repositories()

# Unit test repositories.
local_repository(
    name = "test-module-a",
    path = "test/packages/module-a",
)

local_repository(
    name = "test-module-b",
    path = "test/packages/module-b",
)

local_repository(
    name = "test-module-dist",
    path = "test/packages/module-dist",
)
