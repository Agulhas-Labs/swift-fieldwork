#!/bin/sh
# The pre-push's `swift test`, with the count checked: a plain `swift test` proves exit 0 and nothing
# about how many tests ran, and its thousands of lines push any count out of view.
#
# Usage:  sh Scripts/swift-test-gate.sh [swift test args...]   (run unfiltered: a filtered run prints no inventory)
#
# With sift on PATH it runs `sift run -- swift test`, prints sift's answer and fails unless sift exited 0 and
# the answer holds `inventory: N declared, M reported` with N == M. A `not checked` line, no inventory line
# and a mismatch all fail, each naming why in one line. Without sift it runs plain `swift test`, passes its
# exit through and says in one line that the count was not checked.
set -u

if ! command -v sift > /dev/null 2>&1; then
    swift test "$@"
    STATUS=$?
    echo "swift-test-gate: inventory not checked: sift is not installed, so only swift test's exit status ($STATUS) decides"
    exit "$STATUS"
fi

ANSWER="$(mktemp)" || { echo "swift-test-gate: cannot make a temporary file"; exit 1; }
trap 'rm -f "$ANSWER"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

sift run -- swift test "$@" > "$ANSWER" 2>&1
STATUS=$?
cat "$ANSWER"

if [ "$STATUS" -ne 0 ]; then
    echo "swift-test-gate: FAILED: sift run -- swift test exited $STATUS"
    exit "$STATUS"
fi

LINE="$(LC_ALL=C grep -E '^inventory: ' "$ANSWER" | LC_ALL=C head -1)"
case "$LINE" in
    "")
        echo "swift-test-gate: FAILED: sift printed no inventory line, so the test count is unchecked"
        exit 1
        ;;
    "inventory: not checked"*)
        echo "swift-test-gate: FAILED: $LINE"
        exit 1
        ;;
esac
DECLARED="$(printf '%s\n' "$LINE" | sed -n -E 's/^inventory: ([0-9]+) declared, ([0-9]+) reported.*/\1/p')"
REPORTED="$(printf '%s\n' "$LINE" | sed -n -E 's/^inventory: ([0-9]+) declared, ([0-9]+) reported.*/\2/p')"
if [ -z "$DECLARED" ] || [ -z "$REPORTED" ]; then
    echo "swift-test-gate: FAILED: unrecognised inventory line: $LINE"
    exit 1
fi
if [ "$DECLARED" != "$REPORTED" ]; then
    echo "swift-test-gate: FAILED: $DECLARED tests declared but $REPORTED reported"
    exit 1
fi
# Declared tests in another package's scope (a nested package the run did not build) are a note, not a gap;
# the note is matched whole, so it carries a number and nothing else.
OUTSIDE="$(printf '%s\n' "$LINE" | sed -n -E "s/^inventory: [0-9]+ declared, [0-9]+ reported \(([0-9]+) outside this run's scope\)\$/\1/p")"
case "$LINE" in
    "inventory: $DECLARED declared, $REPORTED reported") ;;
    "inventory: $DECLARED declared, $REPORTED reported ($OUTSIDE outside this run's scope)")
        [ -n "$OUTSIDE" ] || {
            echo "swift-test-gate: FAILED: counts match but sift qualified them: $LINE"
            exit 1
        }
        ;;
    *)
        echo "swift-test-gate: FAILED: counts match but sift qualified them: $LINE"
        exit 1
        ;;
esac
echo "swift-test-gate: ok, $REPORTED of $DECLARED tests reported"
exit 0
