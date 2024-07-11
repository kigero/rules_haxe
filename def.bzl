"""
Public rule definitions for the Haxe repositorry.

Documentation for these rules are in their respective rule definitions.
"""

load("//:providers.bzl", _HaxeLibraryInfo = "HaxeLibraryInfo")
load("//:repo.bzl", _haxe_download = "haxe_download", _haxe_download_linux_amd64 = "haxe_download_linux_amd64", _haxe_download_windows_amd64 = "haxe_download_windows_amd64", _haxe_no_install = "haxe_no_install")
load("//:rules.bzl", _haxe_dox = "haxe_dox", _haxe_executable = "haxe_executable", _haxe_gather_doc_srcs = "haxe_gather_doc_srcs", _haxe_gen_docs_from_dox = "haxe_gen_docs_from_dox", _haxe_gen_hxml = "haxe_gen_hxml", _haxe_haxelib_lib = "haxe_haxelib_lib", _haxe_library = "haxe_library", _haxe_project_definition = "haxe_project_definition", _haxe_std_lib = "haxe_std_lib", _haxe_test = "haxe_test")
load("//:toolchain.bzl", _haxe_toolchain = "haxe_toolchain")

# Build rules.
haxe_library = _haxe_library
haxe_executable = _haxe_executable
haxe_project_definition = _haxe_project_definition
haxe_test = _haxe_test
haxe_gen_hxml = _haxe_gen_hxml
haxe_dox = _haxe_dox
haxe_gather_doc_srcs = _haxe_gather_doc_srcs
haxe_gen_docs_from_dox = _haxe_gen_docs_from_dox
haxe_std_lib = _haxe_std_lib
haxe_haxelib_lib = _haxe_haxelib_lib

# Repository rules.
haxe_download = _haxe_download
haxe_download_windows_amd64 = _haxe_download_windows_amd64
haxe_download_linux_amd64 = _haxe_download_linux_amd64
haxe_no_install = _haxe_no_install

# Toolchain/providers.
haxe_toolchain = _haxe_toolchain
HaxeLibraryInfo = _HaxeLibraryInfo

# Extensions.
def _haxe_install(ctx):
    for mod in ctx.modules:
        for no_install in mod.tags.no_install:
            haxe_no_install(name = no_install.name)
        for install_windows_amd64 in mod.tags.install_windows_amd64:
            haxe_download_windows_amd64(name = install_windows_amd64.name)
        for install_linux_amd64 in mod.tags.install_linux_amd64:
            haxe_download_linux_amd64(name = install_linux_amd64.name)

_no_install = tag_class(attrs = {"name": attr.string()})
_install_windows_amd64 = tag_class(attrs = {"name": attr.string()})
_install_linux_amd64 = tag_class(attrs = {"name": attr.string()})
haxe_install_ext = module_extension(
    implementation = _haxe_install,
    tag_classes = {"no_install": _no_install, "install_windows_amd64": _install_windows_amd64, "install_linux_amd64": _install_linux_amd64},
)
