#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -x "$ROOT/flutter_sdk/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$ROOT/flutter_sdk"
fi

export PATH="$ROOT/flutter_sdk/bin:$PATH"
flutter config --enable-web --no-analytics
flutter pub get
flutter build web --release
