#!/bin/sh
# Self-test for Scripts/homebrew/make-formula.sh, offline: a small fixture archive stands in for the release
# tarball (FIELDWORK_ARCHIVE), made in a temporary directory removed on exit.
#
# Usage:  sh Scripts/homebrew/test-make-formula.sh      prints `all <N> cases passed` and exits 0 only then
set -u

HERE="$(cd "$(dirname "$0")" && pwd -P)"
MAKE="$HERE/make-formula.sh"
[ -f "$MAKE" ] || { echo "FAIL: no script at $MAKE"; exit 1; }

# A script run from a git hook inherits GIT_* variables; none of this suite's commands should see them.
for VAR in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$VAR"; done

TMP="$(mktemp -d)" || { echo "FAIL: cannot make a temporary directory"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir "$TMP/fixture" "$TMP/out"
echo "fixture" > "$TMP/fixture/README.md"
tar -czf "$TMP/archive.tar.gz" -C "$TMP" fixture
SUM="$(shasum -a 256 "$TMP/archive.tar.gz" | cut -d ' ' -f 1)"

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "FAIL: $1"; }

FORMULA="$TMP/out/fieldwork.rb"
FIELDWORK_ARCHIVE="$TMP/archive.tar.gz" sh "$MAKE" 1.2.3 "$TMP/out" > "$TMP/stdout" 2>&1
[ $? -eq 0 ] && pass || fail "generation exits 0: $(cat "$TMP/stdout")"

expect_line() {
    if grep -qxF -- "$1" "$FORMULA"; then pass; else fail "formula lacks the line: $1"; fi
}
expect_line '  url "https://github.com/Agulhas-Labs/swift-fieldwork/archive/refs/tags/1.2.3.tar.gz"'
expect_line "  sha256 \"$SUM\""
expect_line '  depends_on "agulhas-labs/tap/simwalk"'
expect_line '  depends_on "agulhas-labs/tap/swift-sure"'
expect_line '  license "Apache-2.0"'
expect_line 'class Fieldwork < Formula'
if grep -q '@[A-Z0-9]*@' "$FORMULA"; then fail "a placeholder is left in the formula"; else pass; fi

if command -v ruby > /dev/null 2>&1; then
    ruby -c "$FORMULA" > /dev/null 2>&1 && pass || fail "ruby -c rejects the formula"
else
    fail "ruby is not installed, so the formula's syntax is unchecked"
fi

# refused <case> <message> <command...>: the command exits non-zero, and what it prints contains the message.
refused() {
    NAME="$1"
    MESSAGE="$2"
    shift 2
    OUTPUT="$("$@" 2>&1)"
    STATUS=$?
    case "$OUTPUT" in
        *"$MESSAGE"*) SAID=yes ;;
        *) SAID=no ;;
    esac
    if [ "$STATUS" -ne 0 ] && [ "$SAID" = yes ]; then pass; else fail "$NAME: exit $STATUS, output '$OUTPUT', expected '$MESSAGE'"; fi
}
export FIELDWORK_ARCHIVE="$TMP/archive.tar.gz"
refused "no arguments" "usage: make-formula.sh" sh "$MAKE"
refused "one argument" "usage: make-formula.sh" sh "$MAKE" 1.2.3
refused "three arguments" "usage: make-formula.sh" sh "$MAKE" 1.2.3 "$TMP/out" extra
refused "missing out-dir" "is not a directory" sh "$MAKE" 1.2.3 "$TMP/nowhere"
refused "tag with a v" "is not a tag" sh "$MAKE" v1.2.3 "$TMP/out"
refused "two-part tag" "is not a tag" sh "$MAKE" 1.2 "$TMP/out"
refused "four-part tag" "is not a tag" sh "$MAKE" 1.2.3.4 "$TMP/out"
refused "empty tag" "is not a tag" sh "$MAKE" "" "$TMP/out"
refused "tag with a suffix" "is not a tag" sh "$MAKE" 1.2.3-rc1 "$TMP/out"
refused "empty component" "is not a tag" sh "$MAKE" 1..3 "$TMP/out"
FIELDWORK_ARCHIVE="$TMP/absent.tar.gz" refused "missing archive" "no archive at" sh "$MAKE" 1.2.3 "$TMP/out"

if [ "$FAILED" -ne 0 ]; then
    echo "$FAILED of $((PASSED + FAILED)) cases failed"
    exit 1
fi
echo "all $PASSED cases passed"
