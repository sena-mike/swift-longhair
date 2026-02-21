#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_DIR="$ROOT_DIR/overlays/CLonghair"
SUBMODULE_DIR="$ROOT_DIR/Sources/CLonghair"

if [[ ! -d "$SUBMODULE_DIR" ]]; then
  echo "error: missing submodule directory: $SUBMODULE_DIR" >&2
  exit 1
fi

cp "$OVERLAY_DIR/module.modulemap" "$SUBMODULE_DIR/module.modulemap"
cp "$OVERLAY_DIR/CLonghair.apinotes" "$SUBMODULE_DIR/CLonghair.apinotes"

echo "Synced CLonghair overlay files into submodule checkout."
