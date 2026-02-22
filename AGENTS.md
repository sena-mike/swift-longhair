# A Swift Package Wrapper around Longhair

Longhair implements the cauchy 256 algorithm for encoding and decoding, this is a swift convenience wrapper.

Build with `swift build`
Run tests with `swift test`

## Submodule overlay policy
- Do not commit changes inside the `Sources/CLonghair` submodule.
- Keep `module.modulemap` and `CLonghair.apinotes` in `overlays/CLonghair/` in this repo.
- After `git submodule update --init --recursive`, run `./scripts/sync-clonghair-overlay.sh` (or `./scripts/setup.sh`) to copy those files into the submodule checkout for local builds.

