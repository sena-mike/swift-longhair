# Swift-Longhair

A Swift Package Wrapper around [Longhair](https://github.com/catid/longhair) for Cauchy 256 encoding and decoding.

## Xcode

1. Add this package to your Xcode project by going to `File` > `Add Packages...` and entering the URL of this repository.
2. In Xcode project settings pre-processor macros for your target, add `GF256_TARGET_MOBILE=1`.

## Setup

Run the setup script to initialize the Longhair submodule and apply local overlay files (`module.modulemap` and `CLonghair.apinotes`):

```bash
./scripts/setup.sh
```

If you resync submodules later, re-apply overlays with:

```bash
./scripts/sync-clonghair-overlay.sh
```

## Style checks

Format Swift code:

```bash
./scripts/swift-style.sh format
```

Lint Swift code:

```bash
./scripts/swift-style.sh lint
```

Verify formatting exactly (used in CI):

```bash
./scripts/swift-style.sh check
```

The formatter configuration is in `.swift-format` and uses 2-space indentation.
