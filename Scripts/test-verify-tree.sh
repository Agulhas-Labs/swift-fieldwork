#!/bin/sh
# Self-test for Scripts/verify-tree.sh. Builds throwaway neighbourhoods — a home repository with the
# gate copied in, beside invented sibling projects — under one temporary directory it removes on exit,
# and asserts the gate's exit code and finding lines case by case. Every term, name and id here is
# invented, and every id is put together at run time, so this file passes the gate it tests.
#
# Usage:  sh Scripts/test-verify-tree.sh      prints `all <N> cases passed` and exits 0 only then
set -u

HERE="$(cd "$(dirname "$0")" && pwd -P)"
GATE="$HERE/verify-tree.sh"
[ -f "$GATE" ] || { echo "FAIL: no gate at $GATE"; exit 1; }

# The gate and every git call here run on repositories this script made: an inherited GIT_DIR (from a
# hook, say) would point them at the repository being worked on instead.
for VAR in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$VAR"
done

T="$(mktemp -d)" || { echo "FAIL: cannot make a temporary directory"; exit 1; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

CASES=0
FAILED=0

# A stand-in for `xcrun` first on the gate's PATH, so no case depends on the devices paired with this
# machine: `xcrun --find devicectl` succeeds and `devicectl list devices` reports the one invented device
# in STUB_UDID. Nothing in the gate knows about it; a real run finds the real xcrun.
STUB_BIN="$T/bin"
UDID_TAIL="ABCDEF0123456789"
STUB_UDID="00001234-$UDID_TAIL"

# Invented ids for check (f), each joined from two halves so no whole id is written in this file: one no
# list knows, one the fixture's allowed-uuids.txt lists, and a physical device's that no list knows.
UNKNOWN_TAIL="2D7B0C4E8A13"
UNKNOWN_UUID="C3A1F07E-5B2D-4E8A-9F61-$UNKNOWN_TAIL"
ALLOWED_TAIL="000000000001"
ALLOWED_UUID="9E7F0C2A-0000-4000-8000-$ALLOWED_TAIL"
PHONE_TAIL="001A2B3C4D5E6F70"
PHONE_UDID="00008132-$PHONE_TAIL"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/xcrun" << 'STUB'
#!/bin/sh
case "$1" in
    --find) [ "$2" = devicectl ] && { echo /usr/bin/true; exit 0; }; exit 1 ;;
    devicectl)
        while [ $# -gt 0 ]; do
            if [ "$1" = --json-output ]; then
                printf '{\n "identifier" : "%s",\n "udid" : "%s"\n}\n' "$STUB_UDID" "$STUB_UDID" > "$2"
                exit 0
            fi
            shift
        done
        exit 1 ;;
esac
exit 1
STUB
chmod +x "$STUB_BIN/xcrun"

inside() {
    case "$1" in
        "$T"/*) ;;
        *) echo "FAIL: refusing to write outside $T: $1"; exit 1 ;;
    esac
}

g() {
    git -c user.name=gate-test -c user.email=gate-test@example.invalid -c core.hooksPath=/dev/null \
        -c init.defaultBranch=main -c commit.gpgSign=false "$@"
}

# fresh <case>: a neighbourhood NB holding the home repository H (named HomeTool), a plain sibling
# FooBar, a group directory that is not a repository but holds one (ZipZap), a public name and a
# dot-directory. The external list EXT holds one invented term.
fresh() {
    CASE_DIR="$T/$1"
    NB="$CASE_DIR/nb"
    H="$NB/HomeTool"
    inside "$H"
    mkdir -p "$NB/FooBar" "$NB/Group/ZipZap" "$NB/PublicThing" "$NB/.hidden"
    g init -q "$NB/Group/ZipZap"
    home_repository
}

# portfolio <case>: a portfolio ROOT whose product folder Product holds the home repository H (named
# Home) and a second repository Sibling, beside a repository Other and a group directory that is not a
# repository but holds one (Inner). Product also holds a dot-directory and a plain file, which leave it
# a product folder. No neighbourhood override: discovery finds all of it.
portfolio() {
    CASE_DIR="$T/$1"
    ROOT="$CASE_DIR/root"
    H="$ROOT/Product/Home"
    inside "$H"
    mkdir -p "$ROOT/Product/Sibling" "$ROOT/Product/.hidden" "$ROOT/Other" "$ROOT/Group/Inner"
    printf 'notes\n' > "$ROOT/Product/notes.txt"
    g init -q "$ROOT/Product/Sibling"
    g init -q "$ROOT/Other"
    g init -q "$ROOT/Group/Inner"
    home_repository
}

# home_repository: H made a repository holding a copy of the gate and its lists, with an external list
# EXT, an external public list EXT_PUBLIC that does not exist until a case writes it, a fake home and
# user, and no overrides. Scripts/ is excluded in the repository's info/exclude, so
# the gate's own text is not read as part of the tree (no .gitignore a case rewrites can undo that).
home_repository() {
    EXT="$CASE_DIR/external.txt"
    EXT_PUBLIC="$CASE_DIR/external-public.txt"
    FAKE_HOME="$CASE_DIR/fakehome"
    FAKE_USER="gatetester"
    GATE_NEIGHBOURS=""
    GATE_SCRIPT=""
    mkdir -p "$FAKE_HOME" "$H/Scripts"
    g init -q "$H"
    printf '/Scripts/\n' >> "$H/.git/info/exclude"
    cp "$GATE" "$H/Scripts/verify-tree.sh"
    cp "$HERE/allowed-binaries.txt" "$H/Scripts/allowed-binaries.txt"
    printf '# invented ids\n%s a hand-typed id for this test\n' "$ALLOWED_UUID" > "$H/Scripts/allowed-uuids.txt"
    printf '# invented terms\nquuxplonk\n(^|[^[:alnum:]_])zed-ring([^[:alnum:]_]|$)\n' > "$H/Scripts/private-terms.txt"
    printf 'PublicThing  # public in this test\n' > "$H/Scripts/public-names.txt"
    printf 'CHANGELOG.md merge=union\n' > "$H/.gitattributes"
    printf '# HomeTool\n\nHomeTool talks to PublicThing. Nothing else.\n' > "$H/README.md"
    printf '# invented external terms\n\nsnorfwiggle\n' > "$EXT"
    commit "start"
}

commit() {
    inside "$H"
    g -C "$H" add -A && g -C "$H" commit -q -m "$1"
}

# gate [args...]: runs home's copy of the gate (or GATE_SCRIPT) as an invented user, FAKE_HOME and
# FAKE_USER, with the devicectl stand-in and GATE_NEIGHBOURS as the neighbourhood override (empty: none).
# OUT and RC hold what it said. FAIL_BIN, when set, is a directory of tool stubs put ahead of everything.
gate() {
    OUT="$(HOME="$FAKE_HOME" USER="$FAKE_USER" LOGNAME="$FAKE_USER" PATH="${FAIL_BIN:+$FAIL_BIN:}$STUB_BIN:$PATH" STUB_UDID="$STUB_UDID" \
        FIELDWORK_GATE_NEIGHBOURS="$GATE_NEIGHBOURS" FIELDWORK_PRIVATE_TERMS="$EXT" FIELDWORK_PUBLIC_NAMES="$EXT_PUBLIC" \
        sh "${GATE_SCRIPT:-$H/Scripts/verify-tree.sh}" "$@" 2>&1)"
    RC=$?
}

# expect <case> <exit> [line...]: the gate's exit code, and each line present verbatim in its output.
expect() {
    NAME="$1"
    WANT="$2"
    shift 2
    CASES=$((CASES + 1))
    PROBLEM=""
    [ "$RC" = "$WANT" ] || PROBLEM="exit $RC, expected $WANT"
    for LINE in "$@"; do
        printf '%s\n' "$OUT" | grep -qxF -- "$LINE" || PROBLEM="${PROBLEM:+$PROBLEM; }missing line: $LINE"
    done
    if [ -n "$PROBLEM" ]; then
        FAILED=$((FAILED + 1))
        echo "FAIL $NAME: $PROBLEM"
        printf '%s\n' "$OUT" | sed 's/^/    /'
    else
        echo "ok   $NAME"
    fi
}

# names_are <case> <name...>: `--names` exited 0 and printed exactly these names, in this order.
names_are() {
    NAME="$1"
    shift
    CASES=$((CASES + 1))
    WANT_NAMES="$(printf '%s\n' "$@")"
    if [ "$RC" = "0" ] && [ "$OUT" = "$WANT_NAMES" ]; then
        echo "ok   $NAME"
    else
        FAILED=$((FAILED + 1))
        echo "FAIL $NAME: exit $RC, expected exactly: $*"
        printf '%s\n' "$OUT" | sed 's/^/    /'
    fi
}

# not_said <case> <text>: the output must not contain <text> (a private term the gate must not print).
not_said() {
    CASES=$((CASES + 1))
    if printf '%s\n' "$OUT" | grep -qF -- "$2"; then
        FAILED=$((FAILED + 1))
        echo "FAIL $1: the output prints the term itself"
    else
        echo "ok   $1"
    fi
}

fresh clean
gate
expect "clean tree" 0 "0 findings in 2 files (3 sibling names)"

fresh spaced-sibling
printf 'Notes\nWe borrowed this from Foo Bar.\n' > "$H/notes.md"
commit "notes"
gate
expect "tracked file names a sibling, spaced" 1 "notes.md:2: sibling FooBar" "1 findings in 3 files (3 sibling names)"

fresh path-sibling
mkdir -p "$H/docs"
printf 'nothing here\n' > "$H/docs/foo-bar.txt"
commit "path"
gate
expect "a file's path names a sibling" 1 "docs/foo-bar.txt:path: sibling FooBar"

fresh untracked-term
printf 'a zed-ring note\n' > "$H/scratch.txt"
gate
expect "untracked, not ignored, private term" 1 "scratch.txt:1: private-terms.txt:3"
printf 'scratch.txt\n' > "$H/.gitignore"
gate
expect "the same file, ignored" 0
rm "$H/.gitignore"
printf '/scratch.txt export-ignore\n' >> "$H/.gitattributes"
gate
expect "the same file, export-ignored only by an uncommitted .gitattributes" 1 "scratch.txt:1: private-terms.txt:3"
g -C "$H" add .gitattributes && g -C "$H" commit -q -m "export-ignore scratch"
gate
expect "the same file, export-ignored by the commit: still read, since a push publishes it once added" 1 \
    "scratch.txt:1: private-terms.txt:3"

# The gate reads the commit: three ways the working tree can differ from it.
fresh uncommitted-attribute
printf 'a zed-ring note\n' > "$H/leak.md"
commit "leak"
printf '/leak.md export-ignore\n' >> "$H/.gitattributes"
gate
expect "home: a committed leak export-ignored only in the working tree" 1 "leak.md:1: private-terms.txt:3"

fresh edited-clean
printf 'a zed-ring note\n' > "$H/leak.md"
commit "leak"
printf 'nothing here\n' > "$H/leak.md"
gate
expect "home: a committed leak edited clean on disk" 1 "leak.md:1: private-terms.txt:3"

fresh deleted-on-disk
printf 'a zed-ring note\n' > "$H/leak.md"
commit "leak"
rm "$H/leak.md"
gate
expect "home: a committed leak deleted on disk" 1 "leak.md:1: private-terms.txt:3"

fresh rev
printf 'a zed-ring note\n' > "$H/leak.md"
commit "leak"
rm "$H/leak.md"
commit "no leak"
gate
expect "home: the tip, whose leak was removed" 0
gate --rev HEAD~1
expect "home: --rev names the commit that holds the leak" 1 "leak.md:1: private-terms.txt:3"

fresh info-attributes
mkdir -p "$H/.git/info"
printf '/README.md export-ignore\n' > "$H/.git/info/attributes"
gate
expect "home: an export-ignore in the repository's own info/attributes" 1 \
    "refused: git archive of HEAD leaves out README.md (export-ignored?), which a push publishes, so it would go unread"

# A push publishes every file in the commit, so one its archive leaves out is a refusal, not a pass.
fresh tracked-export-ignore
printf 'a zed-ring note\n' > "$H/leak.md"
printf '/leak.md export-ignore\n' >> "$H/.gitattributes"
commit "leak, export-ignored"
gate
expect "home: a committed file the commit's .gitattributes export-ignores" 1 \
    "refused: git archive of HEAD leaves out leak.md (export-ignored?), which a push publishes, so it would go unread"

# The committed term list is published too: its own terms are not looked for in it, every other needle is.
fresh committed-list
inside "$H/Scripts/private-terms.txt"
g -C "$H" add -f Scripts/private-terms.txt && g -C "$H" commit -q -m "list"
gate
expect "the committed term list, holding its own terms" 0 "0 findings in 3 files (3 sibling names)"
printf '# snorfwiggle is too private for this list\n' >> "$H/Scripts/private-terms.txt"
g -C "$H" add -f Scripts/private-terms.txt && g -C "$H" commit -q -m "list"
gate
expect "the committed term list naming an external term" 1 "Scripts/private-terms.txt:4: external list line 3"

fresh external-term
printf 'line one\nsnorfwiggle was here\n' > "$H/leak.txt"
gate
expect "external list term" 1 "leak.txt:2: external list line 3"
not_said "external list term is never printed" "snorfwiggle"

fresh inline-comment
printf '# invented external terms\nsnorfwiggle  # an invented reason\n' > "$EXT"
printf 'snorfwiggle was here\n' > "$H/leak.txt"
gate
expect "a term list entry with an inline comment" 1 \
    "refused: $EXT line 2 holds an inline comment (whitespace then #), which would be matched as part of the term: put the reason on a line of its own"
not_said "the refused entry is never printed" "snorfwiggle"

fresh missing-external
EXT="$CASE_DIR/no-such-list.txt"
gate
expect "external list missing" 1 \
    "refused: the external list $EXT is missing or unreadable (set FIELDWORK_PRIVATE_TERMS to its path)"

# The external public list: optional, read like the committed one, and refused when it cannot be read.
fresh external-public
printf '# machine-local\nFooBar  # a generic folder on this machine\n' > "$EXT_PUBLIC"
gate --names
names_are "the external public list leaves its names out of discovery" Group ZipZap
printf 'We borrowed this from Foo Bar.\n' > "$H/notes.md"
commit "notes"
gate
expect "a name the external public list holds is not a finding" 0 "0 findings in 3 files (2 sibling names)"
rm "$EXT_PUBLIC"
mkdir "$EXT_PUBLIC"
gate
expect "an external public list that exists but cannot be read" 1 \
    "refused: the external public-names list $EXT_PUBLIC exists but is unreadable (FIELDWORK_PUBLIC_NAMES names another)"

# --rev reads the commit's metadata and message too, citing the field and never an external term.
fresh metadata
printf 'more\n' >> "$H/README.md"
inside "$H"
g -C "$H" add -A && g -C "$H" commit -q --author="Foo Bar <someone@example.invalid>" -m "tidy"
SHORT="$(g -C "$H" rev-parse --short HEAD)"
gate --rev HEAD
expect "a commit authored under a sibling's name" 1 "commit $SHORT: author: sibling FooBar" \
    "1 findings in 2 files (3 sibling names)"
printf 'more\n' >> "$H/README.md"
g -C "$H" add -A && g -C "$H" -c user.email=zed-ring@example.invalid commit -q -m "tidy"
SHORT="$(g -C "$H" rev-parse --short HEAD)"
gate --rev HEAD
expect "a commit whose committer email holds a private term" 1 "commit $SHORT: committer: private-terms.txt:3"
printf 'more\n' >> "$H/README.md"
g -C "$H" add -A && g -C "$H" commit -q -m "tidy" -m "Borrowed from ZipZap." -m "snorfwiggle was here."
SHORT="$(g -C "$H" rev-parse --short HEAD)"
gate --rev HEAD
expect "a commit message naming a sibling and an external term" 1 "commit $SHORT: message line 3: sibling ZipZap" \
    "commit $SHORT: message line 5: external list line 3" "2 findings in 2 files (3 sibling names)"
not_said "an external term in a message is never printed" "snorfwiggle"
printf 'more\n' >> "$H/README.md"
g -C "$H" add -A && g -C "$H" commit -q -m "tidy" -m "Nothing to see."
gate --rev HEAD
expect "a clean commit" 0 "0 findings in 2 files (3 sibling names)"

# --rev on an annotated tag reads the tag's own tagger and message as well as its commit.
fresh tags
g -C "$H" tag -a -m "Borrowed from ZipZap." v-msg
gate --rev v-msg
expect "a tag whose message names a sibling" 1 "tag v-msg: tag line 6: sibling ZipZap"
g -C "$H" -c user.email=zed-ring@example.invalid tag -a -m "Nothing to see." v-email
gate --rev v-email
expect "a tag whose tagger email holds a private term" 1 "tag v-email: tag line 4: private-terms.txt:3"
g -C "$H" tag -a -m "Nothing to see." v-clean
gate --rev v-clean
expect "a clean annotated tag" 0 "0 findings in 2 files (3 sibling names)"

fresh no-neighbours
mkdir -p "$CASE_DIR/empty"
GATE_NEIGHBOURS="$CASE_DIR/empty"
gate
expect "empty neighbours" 2 \
    "refused: no siblings discovered beside $H (in $CASE_DIR/empty), so there were no names to look for"

fresh worktree
inside "$NB/HomeTool-wt"
g -C "$H" worktree add -q -b wt "$NB/HomeTool-wt" > /dev/null 2>&1
# The gate is not committed (info/exclude), so the worktree gets its own copy.
cp -R "$H/Scripts" "$NB/HomeTool-wt/Scripts"
gate --names
FROM_PRIMARY="$OUT"
expect "names from the primary checkout" 0 "FooBar" "Group" "ZipZap"
GATE_SCRIPT="$NB/HomeTool-wt/Scripts/verify-tree.sh"
gate --names
CASES=$((CASES + 1))
if [ "$RC" = "0" ] && [ "$OUT" = "$FROM_PRIMARY" ] && [ "$OUT" = "$(printf 'FooBar\nGroup\nZipZap')" ]; then
    echo "ok   names from a linked worktree match the primary's"
else
    FAILED=$((FAILED + 1))
    echo "FAIL names from a linked worktree match the primary's: exit $RC"
    printf 'primary:\n%s\nworktree:\n%s\n' "$FROM_PRIMARY" "$OUT" | sed 's/^/    /'
fi

# A product folder: discovery runs beside it, and comes back into it for its other repositories.
portfolio product-folder
gate --names
names_are "names from beside a product folder, less the product and home" Group Inner Other Sibling
printf 'Built beside Other.\n' > "$H/notes.md"
commit "notes"
gate
expect "a file naming a product beside home's product folder" 1 "notes.md:1: sibling Other" \
    "1 findings in 3 files (4 sibling names)"
printf 'Part of Product.\n' > "$H/notes.md"
commit "notes"
gate
expect "a file naming home's own product folder" 0 "0 findings in 3 files (4 sibling names)"

# Each way the directory above home is not a product folder: discovery stays in it, as without one.
portfolio not-product-plain
mkdir -p "$ROOT/Product/Plain"
gate --names
names_are "a directory beside home holding no repository: not a product folder" Plain Sibling

portfolio not-product-work-tree
g init -q "$ROOT/Product"
gate --names
names_are "a directory above home inside a git work tree: not a product folder" Sibling

portfolio not-product-alone
inside "$ROOT/Product/Sibling"
rm -rf "$ROOT/Product/Sibling"
gate --names
expect "home alone in the directory above it: not a product folder" 2 "no siblings discovered beside $H"

portfolio product-folder-override
GATE_NEIGHBOURS="$ROOT/Product"
gate --names
names_are "FIELDWORK_GATE_NEIGHBOURS skips the product-folder step" Sibling

fresh binaries
printf 'a\000b\n' > "$H/blob.bin"
commit "blob"
gate
expect "a file holding a NUL" 1 "blob.bin:binary: binary file not in allowed-binaries.txt"
rm "$H/blob.bin"
printf '\377\376z\000e\000d\000-\000r\000i\000n\000g\000\n\000' > "$H/wide.txt"
commit "wide"
gate
expect "a UTF-16 file holding a term" 1 "wide.txt:binary: binary file not in allowed-binaries.txt"
rm "$H/wide.txt"
# NUL-free but not UTF-8 (Latin-1): only the UTF-8 half of the text check sees it. Read as text instead,
# the file's invalid byte stops the line-numbering step and the term goes unreported: 0 findings.
printf 'quuxplonk caf\351\n' > "$H/latin1.txt"
commit "latin-1"
gate
expect "a Latin-1 file holding a term" 1 "latin1.txt:binary: binary file not in allowed-binaries.txt"
rm "$H/latin1.txt"
printf 'a\000b\n' > "$H/blob.bin"
printf 'blob.bin %s\n' "$(shasum -a 256 "$H/blob.bin" | cut -d' ' -f1)" > "$H/Scripts/allowed-binaries.txt"
commit "pinned blob"
gate
expect "a binary file pinned with its SHA-256" 0
printf 'a\000c\n' > "$H/blob.bin"
commit "changed blob"
gate
expect "a pinned binary file whose SHA-256 changed" 1 \
    "blob.bin:binary: binary file whose sha256 is not the one allowed-binaries.txt pins"

fresh user-needles
printf 'placeholder /Users/x/Library\n' > "$H/notes.md"
commit "notes"
gate
expect "a placeholder home path" 0
printf 'path /home/fakeperson/dev\n' >> "$H/notes.md"
commit "notes"
FAKE_HOME=/home/fakeperson
gate
expect "the runner's home path" 1 "notes.md:2: home path"

fresh user-name
printf 'written by fakeperson\n' > "$H/notes.md"
commit "notes"
FAKE_USER=fakeperson
gate
expect "the runner's login name" 1 "notes.md:1: user name"
printf 'fakepersonal notes\n' > "$H/notes.md"
commit "notes"
gate
expect "the login name inside a longer word" 0
printf 'written by fakeperson\n' > "$H/notes.md"
commit "notes"
OUT="$(env -u USER HOME="$FAKE_HOME" LOGNAME=fakeperson PATH="$STUB_BIN:$PATH" STUB_UDID="$STUB_UDID" \
    FIELDWORK_PRIVATE_TERMS="$EXT" FIELDWORK_PUBLIC_NAMES="$EXT_PUBLIC" sh "$H/Scripts/verify-tree.sh" 2>&1)"
RC=$?
expect "no USER: the login name from LOGNAME" 1 "notes.md:1: user name"

fresh device-udid
printf 'paired with %s\n' "$STUB_UDID" > "$H/notes.md"
commit "notes"
gate
expect "a paired device's UDID (the devicectl stand-in)" 1 "notes.md:1: device udid"

# Check (f): a UUID no list knows is a finding even when no device lists it (a deleted simulator's).
fresh uuids
printf 'sim %s booted\n' "$UNKNOWN_UUID" > "$H/notes.md"
commit "notes"
gate
expect "a UUID no list knows" 1 "notes.md:1: uuid" "1 findings in 3 files (3 sibling names)"
not_said "the UUID is never printed" "C3A1F07E"
printf 'sim 11111111-2222-3333-4444-0000000000AB booted\n' > "$H/notes.md"
commit "notes"
gate
expect "a synthetic UUID" 0
printf 'sim %s booted\n' "$(printf '%s' "$ALLOWED_UUID" | tr '[:upper:]' '[:lower:]')" > "$H/notes.md"
commit "notes"
gate
expect "an allowed UUID, in another case" 0
printf 'phone %s paired\n' "$PHONE_UDID" > "$H/notes.md"
commit "notes"
gate
expect "a physical device's UDID no list knows" 1 "notes.md:1: uuid"
printf 'phone 00008160-00000000000000AA paired\n' > "$H/notes.md"
commit "notes"
gate
expect "a synthetic physical UDID" 0
mkdir -p "$H/runs"
printf 'x\n' > "$H/runs/$UNKNOWN_UUID.log"
commit "run"
gate
expect "a file's path holding a UUID" 1 "runs/$UNKNOWN_UUID.log:path: uuid"

fresh uuid-inline-comment
printf '%s a placeholder  # inline\n' "$ALLOWED_UUID" > "$H/Scripts/allowed-uuids.txt"
gate
expect "an allowed-uuids.txt entry with an inline comment" 1 \
    "refused: $H/Scripts/allowed-uuids.txt line 1 holds an inline comment (whitespace then #): put the reason on a line of its own"
printf '%s\n' "$ALLOWED_UUID" > "$H/Scripts/allowed-uuids.txt"
gate
expect "an allowed-uuids.txt entry without a reason" 1 \
    "refused: $H/Scripts/allowed-uuids.txt line 1 is not \`<uuid> <reason>\`"

# A pipeline stage that fails must refuse, not drop its findings. Each stub fails only for the one call a
# case aims at, and runs the real tool for every other.
fresh failing-stage
FAIL_BIN="$CASE_DIR/failbin"
mkdir -p "$FAIL_BIN"
printf '#!/bin/sh\ncase "$*" in *-d:*) exit 1 ;; esac\nexec /usr/bin/cut "$@"\n' > "$FAIL_BIN/cut"
chmod +x "$FAIL_BIN/cut"
printf 'a quuxplonk here\n' >> "$H/README.md"
commit "term"
gate
expect "a cut that fails while numbering a finding refuses" 1 "refused: cut failed on the matches in README.md for needle private-terms.txt:2"
printf '#!/bin/sh\ncase "$*" in *000*) exit 1 ;; esac\nexec /usr/bin/tr "$@"\n' > "$FAIL_BIN/tr"
chmod +x "$FAIL_BIN/tr"
rm "$FAIL_BIN/cut"
gate
expect "a tr that fails in the NUL check refuses" 1 "refused: tr failed reading .gitattributes for NUL bytes"
FAIL_BIN=""

# cmp stops at the first differing byte; a tr still writing into its pipe then reports a broken pipe,
# but only where SIGPIPE is ignored (as under many harnesses), so the case ignores it for the gate's run.
fresh broken-pipe
{ printf '\000'; head -c 3000000 /dev/urandom; } > "$H/big.bin"
commit "big"
trap '' PIPE
gate
trap - PIPE
expect "a large file whose NUL comes first" 1 "big.bin:binary: binary file not in allowed-binaries.txt"
not_said "no broken pipe from the NUL check" "Broken pipe"

if [ "$FAILED" = "0" ] && [ "$CASES" -gt 0 ]; then
    echo "all $CASES cases passed"
    exit 0
fi
echo "$FAILED of $CASES cases failed"
exit 1
