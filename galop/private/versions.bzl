"""SHA-256 checksums of galop release binaries, keyed by version and platform.

Every galop release publishes, for tag `<version>` (bare semver, no `v`):

    https://github.com/martianoff/galop/releases/download/<version>/galop-linux-amd64
    https://github.com/martianoff/galop/releases/download/<version>/galop-darwin-arm64
    https://github.com/martianoff/galop/releases/download/<version>/galop-windows-amd64.exe
    https://github.com/martianoff/galop/releases/download/<version>/checksums-sha256.txt

To support a new galop release, copy the three hashes from its
checksums-sha256.txt into a new GALOP_VERSIONS entry, e.g.

    "0.1.0": {
        "darwin_arm64": "<sha256 of galop-darwin-arm64>",
        "linux_amd64": "<sha256 of galop-linux-amd64>",
        "windows_amd64": "<sha256 of galop-windows-amd64.exe>",
    },

and publish a rules_gala release. Until then consumers can pass the hashes
themselves with `galop.toolchain(version = ..., sha256 = {...})`.
"""

# Platform key -> release asset name and the exec constraints of its toolchain.
PLATFORMS = {
    "darwin_arm64": struct(
        asset = "galop-darwin-arm64",
        exec_compatible_with = ["@platforms//os:macos", "@platforms//cpu:arm64"],
    ),
    "linux_amd64": struct(
        asset = "galop-linux-amd64",
        exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    ),
    "windows_amd64": struct(
        asset = "galop-windows-amd64.exe",
        exec_compatible_with = ["@platforms//os:windows", "@platforms//cpu:x86_64"],
    ),
}

DEFAULT_BASE_URL = "https://github.com/martianoff/galop/releases/download"

# version -> platform key -> sha256 (hex). Empty until the first galop release.
GALOP_VERSIONS = {
}
