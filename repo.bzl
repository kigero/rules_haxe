"""
Contains rules to instantiate the haxe repository.
"""

def _setup(ctx, haxe_url, haxe_sha256, neko_url, neko_sha256, os, arch, build_tpl, gen_utils_tpl, _run_script, _haxelib_install_script, _postprocess_hxcpp_script, _copy_hxcpp_includes_script, _postprocess_dox_script):
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
        "RulesHaxeUtils.hx",
        gen_utils_tpl,
    )
    ctx.template(
        "run_haxe.sh",
        _run_script,
    )
    ctx.template(
        "haxelib_install.sh",
        _haxelib_install_script,
    )
    ctx.template(
        "postprocess_hxcpp.sh",
        _postprocess_hxcpp_script,
    )
    ctx.template(
        "copy_hxcpp_includes.sh",
        _copy_hxcpp_includes_script,
    )
    ctx.template(
        "postprocess_dox.py",
        _postprocess_dox_script,
    )

    # Create the haxelib directory...
    if os == "windows":
        ctx.execute(
            ["cmd", "/c", "mkdir", "haxelib_dir"],
        )
    else:
        ctx.execute(
            ["mkdir", "-p", "haxelib_dir"],
        )

    # ...and a file that can be used to find it in the toolchain.
    if os == "windows":
        ctx.execute(
            ["cmd", "/c", "copy", "NUL", "haxelib_dir\\haxelib_file"],
        )
    else:
        ctx.execute(
            ["touch", "haxelib_dir/haxelib_file"],
        )

def _haxe_download_impl(ctx):
    _setup(ctx, ctx.attr.haxe_url, ctx.attr.haxe_sha256, ctx.attr.neko_url, ctx.attr.neko_sha256, ctx.attr.os, ctx.attr.arch, ctx.attr._build_tpl, ctx.attr._gen_utils_tpl, ctx.attr._run_script, ctx.attr._haxelib_install_script, ctx.attr._postprocess_hxcpp_script, ctx.attr._copy_hxcpp_includes_script, ctx.attr._postprocess_dox_script)

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
            default = "@rules_haxe//:templates/RulesHaxeUtils.hx",
        ),
        "_run_script": attr.label(
            default = "@rules_haxe//:templates/run_haxe.sh",
        ),
        "_haxelib_install_script": attr.label(
            default = "@rules_haxe//:templates/haxelib_install.sh",
        ),
        "_postprocess_hxcpp_script": attr.label(
            default = "@rules_haxe//:templates/postprocess_hxcpp.sh",
        ),
        "_copy_hxcpp_includes_script": attr.label(
            default = "@rules_haxe//:templates/copy_hxcpp_includes.sh",
        ),
        "_postprocess_dox_script": attr.label(
            default = "@rules_haxe//:utilities/postprocess_dox.py",
        ),
    },
)

def _haxe_download_universal_version(repository_ctx):
    data = {
        "windows": {
            "amd64": {
                "haxe": {
                    "4.1.2": {
                        "url": "https://github.com/HaxeFoundation/haxe/releases/download/4.1.2/haxe-4.1.2-win64.zip",
                        "sha256": "a75a685f7ab975fa4749ba990e8aeb395403ab2e977ffecfe5321fc9c6c7000b",
                    },
                    "4.2.5": {
                        "url": "https://github.com/HaxeFoundation/haxe/releases/download/4.2.5/haxe-4.2.5-win64.zip",
                        "sha256": "9e7913999eb3693d540926219b45107b3dc249feb44204c0378fcdc6a74a9132",
                    },
                    "4.3.1": {
                        "url": "https://github.com/HaxeFoundation/haxe/releases/download/4.3.1/haxe-4.3.1-win64.zip",
                        "sha256": "8f77bf1dc3fae88b3174e311c60e69ab25c02093a0801bd3e49b28609f465e1e",
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
                    "4.3.1": {
                        "url": "https://github.com/HaxeFoundation/haxe/releases/download/4.3.1/haxe-4.3.1-linux64.tar.gz",
                        "sha256": "4cd04df5edf10f7d15c401ceca83f96ec23b379292abc2ef0bfea1b60badf2a3",
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

    os = repository_ctx.os.name
    arch = repository_ctx.os.arch

    if "windows" in os:
        os_family = "windows"
    elif "linux" in os:
        os_family = "linux"
    else:
        fail("Unsupported os family '{}'; use the 'haxe_download' rule directly.".format(os), "_os")

    os_data = data[os_family]
    if os_data == None:
        fail("Unsupported os '{}'; use the 'haxe_download' rule directly.".format(os), "_os")

    arch_data = os_data[arch]
    if arch_data == None:
        fail("Unsupported arch '{}'; use the 'haxe_download' rule directly.".format(arch), "_arch")

    haxe_data = arch_data["haxe"][repository_ctx.attr.haxe_version]
    if haxe_data == None:
        fail("Unsupported haxe version '{}'; use the 'haxe_download' rule directly.".format(repository_ctx.attr.haxe_version), "haxe_version")

    neko_data = arch_data["neko"][repository_ctx.attr.neko_version]
    if neko_data == None:
        fail("Unsupported haxe version '{}'; use the 'haxe_download' rule directly.".format(repository_ctx.attr.neko_version), "neko_version")

    _setup(repository_ctx, haxe_data["url"], haxe_data["sha256"], neko_data["url"], neko_data["sha256"], os_family, arch, repository_ctx.attr._build_tpl, repository_ctx.attr._gen_utils_tpl, repository_ctx.attr._run_script, repository_ctx.attr._haxelib_install_script, repository_ctx.attr._postprocess_hxcpp_script, repository_ctx.attr._copy_hxcpp_includes_script, repository_ctx.attr._postprocess_dox_script)

haxe_download_universal = repository_rule(
    doc = "Downloads Haxe and Neko and sets up the repository for the current OS and architecture.  Not all versions are supported; use haxe_download directly for a specific unsupported version.",
    implementation = _haxe_download_universal_version,
    attrs = {
        "haxe_version": attr.string(
            default = "4.3.1",
            doc = "The haxe version to get.",
        ),
        "neko_version": attr.string(
            default = "2.3.0",
            doc = "The neko version to get.",
        ),
        "_build_tpl": attr.label(
            default = "@rules_haxe//:templates/BUILD.dist.bazel.tpl",
        ),
        "_gen_utils_tpl": attr.label(
            default = "@rules_haxe//:templates/RulesHaxeUtils.hx",
        ),
        "_run_script": attr.label(
            default = "@rules_haxe//:templates/run_haxe.sh",
        ),
        "_haxelib_install_script": attr.label(
            default = "@rules_haxe//:templates/haxelib_install.sh",
        ),
        "_postprocess_hxcpp_script": attr.label(
            default = "@rules_haxe//:templates/postprocess_hxcpp.sh",
        ),
        "_copy_hxcpp_includes_script": attr.label(
            default = "@rules_haxe//:templates/copy_hxcpp_includes.sh",
        ),
        "_postprocess_dox_script": attr.label(
            default = "@rules_haxe//:utilities/postprocess_dox.py",
        ),
    },
)

def _haxe_no_install(ctx):
    _setup(ctx, None, None, None, None, ctx.attr.os, ctx.attr.arch, ctx.attr._build_tpl, ctx.attr._gen_utils_tpl, ctx.attr._run_script, ctx.attr._haxelib_install_script, ctx.attr._postprocess_hxcpp_script, ctx.attr._copy_hxcpp_includes_script, ctx.attr._postprocess_dox_script)

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
            default = "@rules_haxe//:templates/RulesHaxeUtils.hx",
        ),
        "_run_script": attr.label(
            default = "@rules_haxe//:templates/run_haxe.sh",
        ),
        "_haxelib_install_script": attr.label(
            default = "@rules_haxe//:templates/haxelib_install.sh",
        ),
        "_postprocess_hxcpp_script": attr.label(
            default = "@rules_haxe//:templates/postprocess_hxcpp.sh",
        ),
        "_copy_hxcpp_includes_script": attr.label(
            default = "@rules_haxe//:templates/copy_hxcpp_includes.sh",
        ),
        "_postprocess_dox_script": attr.label(
            default = "@rules_haxe//:utilities/postprocess_dox.py",
        ),
    },
)
