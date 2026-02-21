#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.swift-format"

usage() {
  cat <<'USAGE'
Usage: scripts/swift-style.sh <format|lint|check> [path ...]

Commands:
  format  Format Swift files in place.
  lint    Lint Swift files.
  check   Verify formatting by comparing each file to swift-format output.
USAGE
}

default_targets=("$ROOT_DIR/Sources" "$ROOT_DIR/Tests" "$ROOT_DIR/Package.swift")

run_format() {
  if [[ "$#" -gt 0 ]]; then
    swift format format --configuration "$CONFIG_FILE" --in-place "$@"
  else
    swift format format --configuration "$CONFIG_FILE" --in-place --recursive "${default_targets[@]}"
  fi
}

run_lint() {
  if [[ "$#" -gt 0 ]]; then
    swift format lint --configuration "$CONFIG_FILE" --strict "$@"
  else
    swift format lint --configuration "$CONFIG_FILE" --strict --recursive "${default_targets[@]}"
  fi
}

run_check() {
  mapfile -t swift_files < <(
    {
      printf '%s\n' "$ROOT_DIR/Package.swift"
      find "$ROOT_DIR/Sources" "$ROOT_DIR/Tests" -type f -name '*.swift'
    } | sort
  )

  local failures=0
  for file in "${swift_files[@]}"; do
    local tmp
    tmp="$(mktemp)"
    swift format format --configuration "$CONFIG_FILE" "$file" > "$tmp"
    if ! cmp -s "$file" "$tmp"; then
      echo "Formatting mismatch: ${file#$ROOT_DIR/}"
      failures=1
    fi
    rm -f "$tmp"
  done

  if [[ "$failures" -ne 0 ]]; then
    echo "Swift formatting check failed. Run: scripts/swift-style.sh format"
    exit 1
  fi
}

command="${1:-}"
if [[ -z "$command" ]]; then
  usage
  exit 1
fi
shift || true

case "$command" in
  format)
    run_format "$@"
    ;;
  lint)
    run_lint "$@"
    ;;
  check)
    run_check
    ;;
  *)
    usage
    exit 1
    ;;
esac
