#!/bin/sh
# Writes the Homebrew formula for the Fieldwork tools: SwiftSure and SimWalk installed together.
#
# Usage:  sh Scripts/homebrew/make-formula.sh <tag> <out-dir>   writes <out-dir>/fieldwork.rb
#
# <tag> is a bare release tag, N.N.N, of this repository. The formula's url is that tag's source archive on
# GitHub and its sha256 is that archive's, downloaded with curl; with FIELDWORK_ARCHIVE=<file> set, the script
# hashes that local file instead and downloads nothing. The tag names the archive, and brew reads the version
# from the url, so the formula carries no version line.
set -eu

TEMPLATE="$(cd "$(dirname "$0")" && pwd -P)/fieldwork.rb.template"

if [ "$#" -ne 2 ]; then
    echo "make-formula: usage: make-formula.sh <tag> <out-dir>" >&2
    exit 2
fi
TAG="$1"
OUT="$2"

case "$TAG" in
    *[!0-9.]* | .* | *. | *..* | "" | *.*.*.*)
        echo "make-formula: '$TAG' is not a tag of the form N.N.N" >&2
        exit 2
        ;;
esac
case "$TAG" in
    *.*.*) ;;
    *)
        echo "make-formula: '$TAG' is not a tag of the form N.N.N" >&2
        exit 2
        ;;
esac
[ -d "$OUT" ] || { echo "make-formula: '$OUT' is not a directory" >&2; exit 2; }
[ -f "$TEMPLATE" ] || { echo "make-formula: no template at $TEMPLATE" >&2; exit 1; }

URL="https://github.com/Agulhas-Labs/swift-fieldwork/archive/refs/tags/$TAG.tar.gz"

WORK="$(mktemp -d)" || { echo "make-formula: cannot make a temporary directory" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "${FIELDWORK_ARCHIVE:-}" ]; then
    [ -f "$FIELDWORK_ARCHIVE" ] || { echo "make-formula: no archive at $FIELDWORK_ARCHIVE" >&2; exit 1; }
    ARCHIVE="$FIELDWORK_ARCHIVE"
else
    ARCHIVE="$WORK/archive.tar.gz"
    curl --fail --silent --show-error --location --output "$ARCHIVE" "$URL" || {
        echo "make-formula: cannot download $URL" >&2
        exit 1
    }
fi
SUM="$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)"
[ "${#SUM}" -eq 64 ] || { echo "make-formula: cannot hash $ARCHIVE" >&2; exit 1; }

sed -e "s|@URL@|$URL|" -e "s|@SHA256@|$SUM|" "$TEMPLATE" > "$WORK/fieldwork.rb"
mv "$WORK/fieldwork.rb" "$OUT/fieldwork.rb"
echo "make-formula: wrote $OUT/fieldwork.rb for $TAG ($SUM)"
