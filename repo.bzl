"""
Contains rules to instantiate the haxe repository.
"""

def _haxe_download_impl(ctx):
    """
    Download the haxe and neko distributions, expand them, and then set up the rest of the repository.
    """
    ctx.report_progress("Downloading Haxe distribution")
    ctx.download_and_extract(
        ctx.attr.haxe_url,
        sha256 = ctx.attr.haxe_sha256,
    )

    ctx.report_progress("Downloading Neko distribution")
    ctx.download_and_extract(
        ctx.attr.neko_url,
        sha256 = ctx.attr.neko_sha256,
    )

    ctx.report_progress("Generating repository build file")
    if ctx.attr.os == "darwin":
        os_constraint = "@platforms//os:osx"
    elif ctx.attr.os == "linux":
        os_constraint = "@platforms//os:linux"
    elif ctx.attr.os == "windows":
        os_constraint = "@platforms//os:windows"
    else:
        fail("unsupported os: " + ctx.attr.os)

    if ctx.attr.arch == "amd64":
        arch_constraint = "@platforms//cpu:x86_64"
    else:
        fail("unsupported arch: " + ctx.attr.arch)
    constraints = [os_constraint, arch_constraint]
    constraint_str = ",\n        ".join(['"%s"' % c for c in constraints])

    substitutions = {
        "{exe}": ".exe" if ctx.attr.os == "windows" else "",
        "{exec_constraints}": constraint_str,
        "{target_constraints}": constraint_str,
        "{haxelib_path}": "{}".format(ctx.path("haxelib")),
    }
    ctx.template(
        "BUILD.bazel",
        ctx.attr._build_tpl,
        substitutions = substitutions,
    )

    ctx.report_progress("Generating test generator")
    ctx.template(
        "GenMainTest.hx",
        ctx.attr._gen_main_test_tpl,
    )

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
        "_gen_main_test_tpl": attr.label(
            default = "@rules_haxe//:templates/GenMainTest.hx",
        ),
    },
)

haxe_download_windows_amd64 = repository_rule(
    doc = "Downloads Haxe 4.1.2 and Neko 2.3.0 for Windows and sets up the repository.",
    implementation = _haxe_download_impl,
    attrs = {
        "haxe_url": attr.string(
            default = "https://build.haxe.org/builds/haxe/windows64/haxe_2020-06-30_development_8ef3be1.zip",
        ),
        "haxe_sha256": attr.string(
            default = "4180efbdd23f2a5a3b2230b8ed6edb59945ff35b71df9820176e1b3ece2cad77",
        ),
        "neko_url": attr.string(
            default = "https://github.com/HaxeFoundation/neko/releases/download/v2-3-0/neko-2.3.0-win64.zip",
        ),
        "neko_sha256": attr.string(
            default = "d09fdf362cd2e3274f6c8528be7211663260c3a5323ce893b7637c2818995f0b",
        ),
        "os": attr.string(
            default = "windows",
        ),
        "arch": attr.string(
            default = "amd64",
        ),
        "_build_tpl": attr.label(
            default = "@rules_haxe//:templates/BUILD.dist.bazel.tpl",
        ),
        "_gen_main_test_tpl": attr.label(
            default = "@rules_haxe//:templates/GenMainTest.hx",
        ),
    },
)
