"""
Public rule definitions for the Haxe repositorry.

Documentation for these rules are in their respective rule definitions.
"""

load("//:rules.bzl", _haxe_library = "haxe_library", _haxe_test = "haxe_test", _haxelib_install = "haxelib_install")
load("//:providers.bzl", _HaxeLibraryInfo = "HaxeLibraryInfo")
load("//:toolchain.bzl", _haxe_toolchain = "haxe_toolchain")
load("//:repo.bzl", _haxe_download = "haxe_download", _haxe_download_linux_amd64 = "haxe_download_linux_amd64", _haxe_download_windows_amd64 = "haxe_download_windows_amd64")

# Build rules.
haxe_library = _haxe_library
haxe_test = _haxe_test
haxelib_install = _haxelib_install

# Repository rules.
haxe_download = _haxe_download
haxe_download_windows_amd64 = _haxe_download_windows_amd64
haxe_download_linux_amd64 = _haxe_download_linux_amd64

# Toolchain/providers.
haxe_toolchain = _haxe_toolchain
HaxeLibraryInfo = _HaxeLibraryInfo
