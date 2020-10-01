"""
Provider definitions.
"""

HaxeLibraryInfo = provider(
    doc = "Contains information about a Haxe library",
    fields = {
        "info": """
        Library information.
        
        Has the following fields:
            lib: The haxe library path.
        """,
        "deps": """
        A depset of info structs for this library's dependencies.
        """,
        "hxml": "HXML file from the previous build.",
    },
)

HaxeProjectInfo = provider(
    doc = "Contains information about a Haxe project definition.",
    fields = {
        "info": """
        Library information.
        
        Has no fields.
        """,
        "deps": """
        A depset of info structs for this library's dependencies.
        """,
        "hxml": "HXML file from the previous build.",
        "srcs": "Source files that must be included directly in a downstream project.",
        "library_name": "Explicit library name that should be set in a downstream project.",
        "resources": "Resource files that must be included directly in a downstream project.",
    },
)
