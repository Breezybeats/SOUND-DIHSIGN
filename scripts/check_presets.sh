#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
mkdir -p .build/portable
compiler="${CXX:-g++}"
flags=(-std=c++17 -O2 -Wall -Wextra -Wpedantic)
if [[ "${SANITIZE:-0}" == "1" ]]; then
  flags=(-std=c++17 -O1 -g -Wall -Wextra -Wpedantic -fsanitize=address,undefined -fno-omit-frame-pointer)
fi
"$compiler" "${flags[@]}" -ISources/SoundCore/include \
  Sources/SoundCore/SerumPreset.cpp tests/SerumPresetTests.cpp -lz \
  -o .build/portable/serum-preset-tests
exec .build/portable/serum-preset-tests "$@"
