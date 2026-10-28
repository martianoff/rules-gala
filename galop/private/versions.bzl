"""SHA-256 checksums of galop release binaries, keyed by version and platform.

Every galop release publishes, for tag `<version>` (bare semver, no `v`):

    https://github.com/martianoff/galop/releases/download/<version>/galop-linux-amd64
    https://github.com/martianoff/galop/releases/download/<version>/galop-linux-arm64
    https://github.com/martianoff/galop/releases/download/<version>/galop-darwin-amd64
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
    "darwin_amd64": struct(
        asset = "galop-darwin-amd64",
        exec_compatible_with = ["@platforms//os:macos", "@platforms//cpu:x86_64"],
    ),
    "darwin_arm64": struct(
        asset = "galop-darwin-arm64",
        exec_compatible_with = ["@platforms//os:macos", "@platforms//cpu:arm64"],
    ),
    "linux_amd64": struct(
        asset = "galop-linux-amd64",
        exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    ),
    "linux_arm64": struct(
        asset = "galop-linux-arm64",
        exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:arm64"],
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
    "0.2.2": {
        "darwin_arm64": "3ff844c6b935f13f0655720a9efd9507f5b8fe3c9078172634af4de54318d313",
        "linux_amd64": "7b382f37047b8f55468fa019ee0d5b7f835df9e196a2c88e4b5cc37fe0c03475",
        "windows_amd64": "5fc9e9f1d44ee7e5ac760232c3c4ae1607623d842df4bdb4aac48be29ecd23de",
    },
    "0.2.3": {
        "darwin_amd64": "323209ddd47668954f345cd2fe3abb526dff625fa060bf52a93bdf48120633a4",
        "darwin_arm64": "42f3b97adc5a9d7a48b8008842799d917266f47ef67cc1303ed75640f3593c78",
        "linux_amd64": "c7cc5c000b1d31c9e8cb3d6680b48d020fcb7b7b089278d160142a3b5f7662b4",
        "linux_arm64": "b1f8e849e8b15d746b558a029d5c1357d7640c199944e2b971ebef826602377b",
        "windows_amd64": "5de4c6e1d97f88467a1a738aa601d719bac2ed744a523fad0e0dee41726508db",
    },
    "0.2.4": {
        "darwin_amd64": "1a8294168f7e6e21d1e27284e1c07b754cc6145c8ecf14236e1ed78bf8ba60df",
        "darwin_arm64": "244c5a2827cee4b177f007df7d4a4693e65ece933e4beb144c9ba7f39ebeb65b",
        "linux_amd64": "557d041e23fc1d09c223edd11a983e6a8aad11ee8b8972db7c4e3bf6214490ec",
        "linux_arm64": "43e2e4e9fe50b845d64cd9c42ca89e4109391a4ffc157384e454aeb07940b90e",
        "windows_amd64": "11d69b0fc8a86038c8e61cbcd63f99d15db86ca2ceaf4ed9d0bb215a77cb13b4",
    },
}
