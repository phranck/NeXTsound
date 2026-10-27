#!/bin/bash
# Diagnostic only, never merged: samples the workbench test process on the CI host when it hangs.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
select_xcode
bash "$root/Scripts/firmware.sh" >/dev/null 2>&1 || echo "firmware failed"
bash "$root/Scripts/bootstrap-picotool-usb.sh" >/dev/null 2>&1 || echo "picotool failed"
xcrun swift build --package-path "$root/App/Workbench" --build-tests >/dev/null 2>&1 || echo "build failed"
log=$(mktemp)
xcrun swift test --package-path "$root/App/Workbench" --skip-build >"$log" 2>&1 &
tester=$!
for i in $(seq 1 24); do kill -0 $tester 2>/dev/null || break; sleep 5; done
if kill -0 $tester 2>/dev/null; then
    echo "== still running after 120 s, sampling"
    for pid in $(pgrep -f 'swiftpm-testing|NeXTsoundWorkbenchPackageTests|xctest'); do
        echo "== process $pid: $(ps -o comm= -p $pid)"
        sample "$pid" 3 -mayDie 2>/dev/null | grep -vE '^\s*$' | head -400
    done
    kill -9 $tester 2>/dev/null
else
    echo "== tests finished"; tail -3 "$log"
fi
exit 1
