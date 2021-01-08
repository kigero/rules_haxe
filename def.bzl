"""
Public rule definitions for the Haxe repositorry.

Documentation for these rules are in their respective rule definitions.
"""

load("//:rules.bzl", _haxe_dox = "haxe_dox", _haxe_executable = "haxe_executable", _haxe_gather_doc_srcs = "haxe_gather_doc_srcs", _haxe_gen_docs_from_dox = "haxe_gen_docs_from_dox", _haxe_gen_hxml = "haxe_gen_hxml", _haxe_library = "haxe_library", _haxe_project_definition = "haxe_project_definition", _haxe_test = "haxe_test")
load("//:providers.bzl", _HaxeLibraryInfo = "HaxeLibraryInfo")
load("//:toolchain.bzl", _haxe_toolchain = "haxe_toolchain")
load("//:repo.bzl", _haxe_download = "haxe_download", _haxe_download_linux_amd64 = "haxe_download_linux_amd64", _haxe_download_windows_amd64 = "haxe_download_windows_amd64", _haxe_no_install = "haxe_no_install")

# Build rules.
haxe_library = _haxe_library
haxe_executable = _haxe_executable
haxe_project_definition = _haxe_project_definition
haxe_test = _haxe_test
haxe_gen_hxml = _haxe_gen_hxml
haxe_dox = _haxe_dox
haxe_gather_doc_srcs = _haxe_gather_doc_srcs
haxe_gen_docs_from_dox = _haxe_gen_docs_from_dox

# Repository rules.
haxe_download = _haxe_download
haxe_download_windows_amd64 = _haxe_download_windows_amd64
haxe_download_linux_amd64 = _haxe_download_linux_amd64
haxe_no_install = _haxe_no_install

# Toolchain/providers.
haxe_toolchain = _haxe_toolchain
HaxeLibraryInfo = _HaxeLibraryInfo
