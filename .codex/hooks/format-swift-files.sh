#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"

mapfile -t changed_swift_files < <(git -C "$ROOT_DIR" diff --name-only -- '*.swift')

if [[ "${#changed_swift_files[@]}" -eq 0 ]]; then
  exit 0
fi

for i in "${!changed_swift_files[@]}"; do
  changed_swift_files[$i]="$ROOT_DIR/${changed_swift_files[$i]}"
done

"$ROOT_DIR/scripts/swift-style.sh" format "${changed_swift_files[@]}"
