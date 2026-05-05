#!/usr/bin/env bash
# Re-sign the SwiftPM-built Abscido binary so Speech Recognition entitlements exist in the
# signature TCC evaluates. Plain `swift run` only embeds Swift’s debugger stub entitlement and
# can terminate with __TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__ on newer macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN="$(swift build "$@" --show-bin-path)/Abscido"

ENT="$ROOT/Abscido/LocalSigning.entitlements"
if [[ ! -f "$ENT" ]]; then
  echo "error: missing $ENT" >&2
  exit 1
fi

codesign --force --sign - --timestamp=none --entitlements "$ENT" "$BIN"

exec "$BIN"
