#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
select_xcode

bash "$root/Scripts/format.sh" --check
bash "$root/Scripts/format.sh" --fixtures
swift_files=()
while IFS= read -r -d '' relative; do
    swift_files+=("$root/$relative")
done < <(swift_sources)
"$root/.tools/bin/swiftlint" lint --strict --config "$root/.swiftlint.yml" "${swift_files[@]}"

bash "$root/Scripts/check-firmware-version.sh"
bash "$root/Scripts/test-app-version.sh"
bash "$root/Scripts/firmware.sh"
cmake -S "$root/Shared" -B "$root/.build/c-protocol" -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_COMPILER="$(xcrun --find clang)" -DNXS_TEST_FIRMWARE=ON
cmake --build "$root/.build/c-protocol"
ctest --test-dir "$root/.build/c-protocol" --output-on-failure
swift test --package-path "$root/Shared"
swift build --package-path "$root/Shared" --configuration release
bash "$root/Scripts/bootstrap-picotool-usb.sh"
xcrun swift test --package-path "$root/App/Workbench" --event-stream-output-path /dev/stderr --event-stream-version 0
xcrun swift build --package-path "$root/App/Workbench" --configuration release
bash "$root/Scripts/app.sh"
git -C "$root" diff --check
