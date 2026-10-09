#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
swift_compiler="${SWIFTC:-$(command -v swiftc || true)}"
if [[ -z "$swift_compiler" ]]; then
  printf '%s\n' 'Swift is required. Set SWIFTC to a Swift 5.9+ compiler.' >&2
  exit 1
fi
mkdir -p .build/portable/library-module .build/portable/swift-module-cache
cat > .build/portable/library-module/module.modulemap <<MODULE
module SoundCore {
  header "${repo_dir}/Sources/SoundCore/include/SoundCore.h"
  header "${repo_dir}/Sources/SoundCore/include/SerumPreset.h"
  export *
}
MODULE
compiler="${CXX:-g++}"
"$compiler" -std=c++17 -O2 -Wall -Wextra -Wpedantic \
  -ISources/SoundCore/include -c Sources/SoundCore/SerumPreset.cpp \
  -o .build/portable/library-serum-preset.o
cpp_library='-lstdc++'
if [[ "$(uname -s)" == 'Darwin' ]]; then cpp_library='-lc++'; fi
"$swift_compiler" -swift-version 5 -O -D SOUND_DIHSIGN_TESTING \
  -module-cache-path .build/portable/swift-module-cache \
  -I .build/portable/library-module Shared/Patch.swift Shared/PresetLibrary.swift \
  tests/PresetLibraryTests.swift .build/portable/library-serum-preset.o \
  -Xlinker "$cpp_library" -Xlinker -lz -o .build/portable/preset-library-tests
library_test_dir="$(mktemp -d /tmp/sound-dihsign-library.XXXXXX)"
trap 'rm -rf -- "$library_test_dir"' EXIT
SOUND_DIHSIGN_TEST_LIBRARY_PATH="$library_test_dir" .build/portable/preset-library-tests "$@"
