"""
Contains rules to instantiate the haxe repository.
"""

def _setup(ctx, haxe_url, haxe_sha256, neko_url, neko_sha256, os, arch, build_tpl, gen_utils_tpl):
    """
    Download the haxe and neko distributions, expand them, and then set up the rest of the repository.
    """
    if haxe_url != None:
        ctx.report_progress("Downloading Haxe distribution")
        ctx.download_and_extract(
            haxe_url,
            sha256 = haxe_sha256,
        )

    if neko_url != None:
        ctx.report_progress("Downloading Neko distribution")
        ctx.download_and_extract(
            neko_url,
            sha256 = neko_sha256,
        )

    ctx.report_progress("Generating repository build file")
    if os == "darwin":
        os_constraint = "@platforms//os:osx"
    elif os == "linux":
        os_constraint = "@platforms//os:linux"
    elif os == "windows":
        os_constraint = "@platforms//os:windows"
    else:
        fail("unsupported os: " + os)

    if arch == "amd64":
        arch_constraint = "@platforms//cpu:x86_64"
    else:
        fail("unsupported arch: " + arch)
    constraints = [os_constraint, arch_constraint]
    constraint_str = ",\n        ".join(['"%s"' % c for c in constraints])

    substitutions = {
        "{exe}": ".exe" if os == "windows" else "",
        "{exec_constraints}": constraint_str,
        "{target_constraints}": constraint_str,
        "{haxelib_path}": "{}".format(ctx.path("haxelib")),
    }
    ctx.template(
        "BUILD.bazel",
        build_tpl,
        substitutions = substitutions,
    )

    ctx.report_progress("Generating utility scripts")
    ctx.template(
        "Utils.hx",
        gen_utils_tpl,
    )

    # Create the haxelib directory...
    ctx.execute(
        ["mkdir", "-p", "haxelib_dir"],
    )

    # ...and a file that can be used to find it in the toolchain.
    ctx.execute(
        ["touch", "haxelib_dir/haxelib_file"],
    )

def _haxe_download_impl(ctx):
    _setup(ctx, ctx.attr.haxe_url, ctx.attr.haxe_sha256, ctx.attr.neko_url, ctx.attr.neko_sha256, ctx.attr.os, ctx.attr.arch, ctx.attr._build_tpl, ctx.attr._gen_utils_tpl)

haxe_download = repository_rule(
    doc = "Downloads Haxe and Neko and sets up the repository.",
    implementation = _haxe_download_impl,
    attrs = {
        "haxe_url": attr.string(
            mandatory = True,
            doc = "URL to get Haxe from.",
        ),
        "haxe_sha256": attr.string(
            mandatory = True,
            doc = "SHA256 hash of the Haxe distribution file.",
        ),
        "neko_url": attr.string(
            mandatory = True,
            doc = "URL to get Neko from.",
        ),
        "neko_sha256": attr.string(
            mandatory = True,
            doc = "SHA256 hash of the Neko distribution file.",
        ),
        "os": attr.string(
            mandatory = True,
            values = ["darwin", "linux", "windows"],
            doc = "Host operating system for the Haxe distribution",
        ),
        "arch": attr.string(
            mandatory = True,
            values = ["amd64"],
            doc = "Host architecture for the Haxe distribution",
        ),
        "_build_tpl": attr.label(
            default = "@rules_haxe//:templates/BUILD.dist.bazel.tpl",
        ),
        "_gen_utils_tpl": attr.label(
            default = "@rules_haxe//:templates/Utils.hx",
        ),
    },
)

def _haxe_download_version(ctx):
    data = {
        "windows": {
            "amd64": {
                "haxe": {
                    "4.1.2": {
                        "url": "https://build.haxe.org/builds/haxe/windows64/haxe_2020-06-30_development_8ef3be1.zip",
                        "sha256": "4180efbdd23f2a5a3b2230b8ed6edb59945ff35b71df9820176e1b3ece2cad77",
                    },
                },
                "neko": {
                    "2.3.0": {
                        "url": "https://github.com/HaxeFoundation/neko/releases/download/v2-3-0/neko-2.3.0-win64.zip",
                        "sha256": "d09fdf362cd2e3274f6c8528be7211663260c3a5323ce893b7637c2818995f0b",
                    },
                },
            },
        },
        "linux": {
            "amd64": {
                "haxe": {
                    "4.1.2": {
                        "url": "https://github.com/HaxeFoundation/haxe/releases/download/4.1.2/haxe-4.1.2-linux64.tar.gz",
                        "sha256": "c82f9d72e4a2c2ae228284d55a7f1bf6c7e6410e127bf1061a0152683edd1d48",
                    },
                },
                "neko": {
                    "2.3.0": {
                        "url": "https://github.com/HaxeFoundation/neko/releases/download/v2-3-0/neko-2.3.0-linux64.tar.gz",
                        "sha256": "26dda28d0a51407f26218ba9c2c355c8eb23cf2b0b617274b00e4b9170fe69eb",
                    },
                },
            },
        },
    }

    os_data = data[ctx.attr._os]
    if os_data == None:
        fail("Unsupported os '{}'; use the 'haxe_download' rule directly.".format(ctx.attr._os), "_os")

    arch_data = os_data[ctx.attr._arch]
    if arch_data == None:
        fail("Unsupported arch '{}'; use the 'haxe_download' rule directly.".format(ctx.attr._arch), "_arch")

    haxe_data = arch_data["haxe"][ctx.attr.haxe_version]
    if haxe_data == None:
        fail("Unsupported haxe version '{}'; use the 'haxe_download' rule directly.".format(ctx.attr.haxe_version), "haxe_version")

    neko_data = arch_data["neko"][ctx.attr.neko_version]
    if neko_data == None:
        fail("Unsupported haxe version '{}'; use the 'haxe_download' rule directly.".format(ctx.attr.neko_version), "neko_version")

    _setup(ctx, haxe_data["url"], haxe_data["sha256"], neko_data["url"], neko_data["sha256"], ctx.attr._os, ctx.attr._arch, ctx.attr._build_tpl, ctx.attr._gen_utils_tpl)

haxe_download_windows_amd64 = repository_rule(
    doc = "Downloads Haxe and Neko for Windows and sets up the repository.  Not all versions are supported; use haxe_download directly for a specific unsupported version.",
    implementation = _haxe_download_version,
    attrs = {
        "haxe_version": attr.string(
            default = "4.1.2",
            doc = "The haxe version to get.",
        ),
        "neko_version": attr.string(
            default = "2.3.0",
            doc = "The neko version to get.",
        ),
        "_os": attr.string(
            default = "windows",
        ),
        "_arch": attr.string(
            default = "amd64",
        ),
        "_build_tpl": attr.label(
            default = "@rules_haxe//:templates/BUILD.dist.bazel.tpl",
        ),
        "_gen_utils_tpl": attr.label(
            default = "@rules_haxe//:templates/Utils.hx",
        ),
    },
)

haxe_download_linux_amd64 = repository_rule(
    doc = "Downloads Haxe and Neko for Linux and sets up the repository.  Not all versions are supported; use haxe_download directly for a specific unsupported version.",
    implementation = _haxe_download_version,
    attrs = {
        "haxe_version": attr.string(
            default = "4.1.2",
            doc = "The haxe version to get.",
        ),
        "neko_version": attr.string(
            default = "2.3.0",
            doc = "The neko version to get.",
        ),
        "_os": attr.string(
            default = "linux",
        ),
        "_arch": attr.string(
            default = "amd64",
        ),
        "_build_tpl": attr.label(
            default = "@rules_haxe//:templates/BUILD.dist.bazel.tpl",
        ),
        "_gen_utils_tpl": attr.label(
            default = "@rules_haxe//:templates/Utils.hx",
        ),
    },
)

def _haxe_no_install(ctx):
    _setup(ctx, None, None, None, None, ctx.attr.os, ctx.attr.arch, ctx.attr._build_tpl, ctx.attr._gen_utils_tpl)

haxe_no_install = repository_rule(
    doc = "Use a local installation of haxe.",
    implementation = _haxe_no_install,
    attrs = {
        "os": attr.string(
            default = "linux",
        ),
        "arch": attr.string(
            default = "amd64",
        ),
        "_build_tpl": attr.label(
            default = "@rules_haxe//:templates/BUILD.dist.bazel.tpl",
        ),
        "_gen_utils_tpl": attr.label(
            default = "@rules_haxe//:templates/Utils.hx",
        ),
    },
)
