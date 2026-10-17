#!/bin/sh
# Self-test for Scripts/swift-test-gate.sh. PATH-stubbed `sift` and `swift` print canned answers and exit
# codes; nothing here runs a real test. Everything lives under one temporary directory removed on exit.
#
# Usage:  sh Scripts/test-swift-test-gate.sh      prints `all <N> cases passed` and exits 0 only then
set -u

HERE="$(cd "$(dirname "$0")" && pwd -P)"
GATE="$HERE/swift-test-gate.sh"
[ -f "$GATE" ] || { echo "FAIL: no gate at $GATE"; exit 1; }

T="$(mktemp -d)" || { echo "FAIL: cannot make a temporary directory"; exit 1; }
trap 'rm -rf "$T"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

CASES=0
FAILED=0

# Stubs. The sift stub prints $STUB_SIFT_OUT and exits $STUB_SIFT_RC; the swift stub prints a marker and
# exits $STUB_SWIFT_RC.
WITH="$T/with-sift"
WITHOUT="$T/without-sift"
mkdir -p "$WITH" "$WITHOUT"
cat > "$WITH/sift" << 'STUB'
#!/bin/sh
printf '%s\n' "$STUB_SIFT_OUT"
exit "${STUB_SIFT_RC:-0}"
STUB
cat > "$WITH/swift" << 'STUB'
#!/bin/sh
echo "plain swift ran"
exit "${STUB_SWIFT_RC:-0}"
STUB
cp "$WITH/swift" "$WITHOUT/swift"
chmod +x "$WITH/sift" "$WITH/swift" "$WITHOUT/swift"
# The gate runs with the stub directory plus the system directories, which do not hold sift.
SYSTEM_PATH="/usr/bin:/bin"

# run <path-dir>: runs the gate with the stub directory first; OUT and RC hold what it said.
run() {
    OUT="$(PATH="$1:$SYSTEM_PATH" sh "$GATE" 2>&1)"
    RC=$?
}

expect() {
    NAME="$1"
    WANT="$2"
    shift 2
    CASES=$((CASES + 1))
    PROBLEM=""
    [ "$RC" = "$WANT" ] || PROBLEM="exit $RC, expected $WANT"
    for LINE in "$@"; do
        printf '%s\n' "$OUT" | grep -qF -- "$LINE" || PROBLEM="${PROBLEM:+$PROBLEM; }missing: $LINE"
    done
    if [ -n "$PROBLEM" ]; then
        FAILED=$((FAILED + 1))
        echo "FAIL $NAME: $PROBLEM"
        printf '%s\n' "$OUT" | sed 's/^/    /'
    else
        echo "ok   $NAME"
    fi
}

export STUB_SIFT_OUT STUB_SIFT_RC STUB_SWIFT_RC
PATH="$SYSTEM_PATH" command -v sift > /dev/null 2>&1 && { echo "FAIL: sift is on the system path, so the no-sift case cannot run"; exit 1; }

STUB_SIFT_RC=0
STUB_SIFT_OUT="totals: passed
inventory: 12 declared, 12 reported"
run "$WITH"
expect "matched counts pass" 0 "swift-test-gate: ok, 12 of 12"

STUB_SIFT_OUT="inventory: 2504 declared, 2504 reported (2 outside this run's scope)"
run "$WITH"
expect "matched counts with tests outside the run's scope pass" 0 "swift-test-gate: ok, 2504 of 2504"

STUB_SIFT_OUT="inventory: 12 declared, 12 reported · 1 reported more than once: Suite/aTest()"
run "$WITH"
expect "matched counts that sift qualified otherwise fail" 1 "FAILED: counts match but sift qualified them"

STUB_SIFT_OUT="inventory: 10 declared, 10 reported (2 skipped, 1 outside this run's scope)"
run "$WITH"
expect "a scope note carrying anything but a number fails" 1 "FAILED: counts match but sift qualified them"

STUB_SIFT_OUT="inventory: 2479 declared, 2340 reported — test process crashed; 139 started and never ended"
run "$WITH"
expect "a mismatch fails" 1 "FAILED: 2479 tests declared but 2340 reported"

STUB_SIFT_OUT="inventory: not checked — the run was filtered"
run "$WITH"
expect "not checked fails, naming sift's reason" 1 "FAILED: inventory: not checked — the run was filtered"

STUB_SIFT_OUT="totals: passed"
run "$WITH"
expect "no inventory line fails" 1 "FAILED: sift printed no inventory line"

STUB_SIFT_RC=1
STUB_SIFT_OUT="inventory: 3 declared, 3 reported"
run "$WITH"
expect "sift's non-zero exit is passed through" 1 "exited 1"
STUB_SIFT_RC=7
run "$WITH"
expect "sift's exit code is the gate's own" 7 "exited 7"

STUB_SWIFT_RC=0
run "$WITHOUT"
expect "no sift: plain swift test runs, exit 0, one line says unchecked" 0 "plain swift ran" "inventory not checked: sift is not installed"
STUB_SWIFT_RC=3
run "$WITHOUT"
expect "no sift: swift's exit passes through" 3 "plain swift ran"

if [ "$FAILED" = "0" ] && [ "$CASES" -gt 0 ]; then
    echo "all $CASES cases passed"
    exit 0
fi
echo "$FAILED of $CASES cases failed"
exit 1
