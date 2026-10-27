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

# version -> platform key -> sha256 (hex), copied from each release's checksums-sha256.txt.
GALOP_VERSIONS = {
    "0.1.0": {
        "darwin_arm64": "6ff95a23e22eae16d22eb70a2c354e26d55ae389c63fe9244ee2ae1f4c4b22be",
        "linux_amd64": "3f611410a7aa55cf762b9adba3fb7ce87e73724f98fbd499e09d0ba2e668f3e5",
        "windows_amd64": "70447a5472b94602006be4e5203c1fc57696185a006a7ade8701bc007c7d941d",
    },
    "0.2.0": {
        "darwin_arm64": "f446bf84f8b495fd85e14c34342d4821fd4e139d3e411b7314d938c1b41d4015",
        "linux_amd64": "b54a10a784fc2a27571377c0545dec704734544e3d31a3a9ed328ec108253d74",
        "windows_amd64": "5e58e4d68c7a3d0c5f17ba0fcb2af7f18e83952fa03d5fa34c8fbc9fa33d412f",
    },
    "0.2.1": {
        "darwin_arm64": "0f5d38d498cf3185906c4064432958f6b9028875d7c2f5edd41d65d6f84686ab",
        "linux_amd64": "321ad31e557731ed39105c09b5e10e70f251efd1b0fc521f47cc5c7a59415ad4",
        "windows_amd64": "3611b5281c1e3f75fc05164811af9ab4fbc236654f3d9be81b2ed6d6613d84e9",
    },
}
