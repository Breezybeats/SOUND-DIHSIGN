#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
swift_compiler="${SWIFTC:-$(command -v swiftc || true)}"
if [[ -z "$swift_compiler" ]]; then
  printf '%s\n' 'Swift is required. Set SWIFTC to a Swift 5.9+ compiler.' >&2
  exit 1
fi
swift_compiler="$(command -v "$swift_compiler")"
swift_driver="${SWIFT:-$(dirname -- "$swift_compiler")/swift}"
mkdir -p .build/portable/swift-module-cache
build_arguments=(
  --package-path "$repo_dir"
  --scratch-path "$repo_dir/.build/portable/library-package"
  --cache-path "$repo_dir/.build/portable/swiftpm-cache"
  --config-path "$repo_dir/.build/portable/swiftpm-config"
  --security-path "$repo_dir/.build/portable/swiftpm-security"
  --manifest-cache local
  --configuration release
  --jobs 2
  -Xswiftc -module-cache-path
  -Xswiftc "$repo_dir/.build/portable/swift-module-cache"
)
# Use the package's real umbrella header and SwiftPM-generated module map.
# A hand-written map listing both headers would conceal missing public exports.
SWIFTPM_MODULECACHE_OVERRIDE="$repo_dir/.build/portable/swift-module-cache" \
  "$swift_driver" build "${build_arguments[@]}" --target SoundCore
package_bin="$(SWIFTPM_MODULECACHE_OVERRIDE="$repo_dir/.build/portable/swift-module-cache" \
  "$swift_driver" build "${build_arguments[@]}" --show-bin-path)"
module_dir="$package_bin/SoundCore.build"
if [[ ! -f "$module_dir/module.modulemap" ]]; then
  printf '%s\n' 'SwiftPM did not generate the SoundCore module map.' >&2
  exit 1
fi
native_objects=("$module_dir/SoundCore.cpp.o" "$module_dir/SerumPreset.cpp.o")
for object in "${native_objects[@]}"; do
  if [[ ! -f "$object" ]]; then
    printf 'SwiftPM native object is missing: %s\n' "$object" >&2
    exit 1
  fi
done
cpp_library='-lstdc++'
if [[ "$(uname -s)" == 'Darwin' ]]; then cpp_library='-lc++'; fi
"$swift_compiler" -swift-version 5 -O -D SOUND_DIHSIGN_TESTING \
  -module-cache-path .build/portable/swift-module-cache \
  -I "$module_dir" Shared/Patch.swift Shared/PresetLibrary.swift \
  tests/PresetLibraryTests.swift "${native_objects[@]}" \
  -Xlinker "$cpp_library" -Xlinker -lz -o .build/portable/preset-library-tests
library_test_dir="$(mktemp -d /tmp/sound-dihsign-library.XXXXXX)"
trap 'rm -rf -- "$library_test_dir"' EXIT
SOUND_DIHSIGN_TEST_LIBRARY_PATH="$library_test_dir" .build/portable/preset-library-tests "$@"
