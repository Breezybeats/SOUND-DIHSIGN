#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
mkdir -p .build/portable
compiler="${CXX:-g++}"
flags=(-std=c++17 -O2 -Wall -Wextra -Wpedantic -pthread)
if [[ "${SANITIZE:-0}" == "1" ]]; then
  flags=(-std=c++17 -O1 -g -Wall -Wextra -Wpedantic -pthread -fsanitize=address,undefined -fno-omit-frame-pointer)
fi
"$compiler" "${flags[@]}" -ISources/SoundCore/include \
  Sources/SoundCore/SoundCore.cpp tests/SoundCoreTests.cpp \
  -o .build/portable/soundcore-tests
exec .build/portable/soundcore-tests "$@"
