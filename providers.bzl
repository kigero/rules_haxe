"""
Provider definitions.
"""

HaxeLibraryInfo = provider(
    doc = "Contains information about a Haxe library",
    fields = {
        "lib": "The haxe library path.",
        "deps": "A depset of info structs for this library's dependencies.",
        "hxml": "HXML file from the previous build.",
    },
)

HaxeProjectInfo = provider(
    doc = "Contains information about a Haxe project definition.",
    fields = {
        "deps": "A depset of info structs for this library's dependencies.",
        "hxml": "HXML file from the previous build.",
        "srcs": "Source files that must be included directly in a downstream project.",
        "doc_srcs": "Document source files that must be included directly in a downstream project.",
        "library_name": "Explicit library or binary name that should be set in a downstream project.",
        "resources": "Resource files that must be included directly in a downstream project.",
        "main_class": "Main class of the project to build.",
    },
)
