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
