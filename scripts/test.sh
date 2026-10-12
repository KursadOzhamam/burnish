#!/bin/bash
# Runs every package's tests, then SwiftLint.
#
#   ./scripts/test.sh          run everything
#   ./scripts/test.sh --clean  wipe .build first
#
# Use --clean after changing a local package's public API. SwiftPM caches a dependency's
# module across packages and will otherwise compile against the previous interface, which
# surfaces as "cannot find X in scope" or as tests failing on code that is actually correct.

set -uo pipefail
cd "$(dirname "$0")/.."

CLEAN=false
[ "${1:-}" = "--clean" ] && CLEAN=true

PACKAGES=(
    Packages/CoreKit
    Packages/CoreKitMac
    Packages/ScanEngine
    Packages/SafetyKit
    Packages/SafetyKitMac
    Packages/Licensing
    Packages/DesignSystem
    Packages/SystemMonitor
    Packages/Features/Dashboard
    Packages/Features/SmartScan
    Packages/Features/Cleanup
)

total=0
failed=()

for package in "${PACKAGES[@]}"; do
    name=$(basename "$package")
    [ "$CLEAN" = true ] && rm -rf "$package/.build"

    output=$(cd "$package" && swift test 2>&1)
    summary=$(echo "$output" | tail -1)
    count=$(echo "$summary" | grep -oE '[0-9]+ tests' | head -1 | grep -oE '[0-9]+')

    if echo "$summary" | grep -q passed; then
        printf "  ✓ %-16s %4s\n" "$name" "${count:-0}"
        total=$((total + ${count:-0}))
    else
        printf "  ✗ %-16s FAILED\n" "$name"
        echo "$output" | grep -E "error:|✘ Test" | head -5 | sed 's/^/      /'
        failed+=("$name")
    fi
done

echo "  ────────────────────────────"
printf "  %d tests\n" "$total"

if command -v swiftlint >/dev/null; then
    echo "  $(swiftlint lint --no-cache 2>&1 | tail -1)"
fi

if [ ${#failed[@]} -gt 0 ]; then
    echo "  failed: ${failed[*]}"
    exit 1
fi
