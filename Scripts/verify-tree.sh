#!/bin/sh
# The privacy gate for swift-fieldwork: fails when a file a commit would publish names the machine it
# was made on, its owner, or the other work on it. Every pushed commit is public, so the commit is what
# it reads.
#
# Usage:  sh Scripts/verify-tree.sh [--rev <rev>]   scan the commit <rev> (default HEAD) of the checkout
#                                                   holding this script, plus its untracked files; with
#                                                   --rev, that commit's metadata and message too
#         sh Scripts/verify-tree.sh --names         print the discovered sibling names, scan nothing
#
# **What a clean verdict covers.** The gate reads the COMMIT, not the working tree: `git archive <rev>`
# unpacked into a temporary directory, plus every file git neither tracks nor ignores (a file nobody has
# added yet is one `git add` away from a commit, so it obeys the rules too). Edits to tracked files that
# are not yet committed are NOT read: they are read once committed. A push publishes every file in the
# commit, export-ignored or not, so a commit whose archive leaves out a file its tree holds (an
# `export-ignore` in its .gitattributes or in the repository's info/attributes) is refused rather than
# read in part. File contents and file paths are read through the same code.
#
# With --rev it also reads the commit itself: author name and email, committer name and email, and the
# full message (`git log -1 --format='%an%n%ae%n%cn%n%ce%n%B'`), with every needle that applies to file
# contents. A push publishes them with the tree. Without --rev (HEAD and the untracked files, as before a
# commit) they are not read. The pre-push hook passes --rev for every commit it publishes.
#
# **What it does not cover.** History. It reads one commit; a push publishes every commit it carries,
# and a name committed and later removed is still in the object database, where `git show` hands it to
# anyone who clones. It also does not read inside a binary file (only NUL-free, valid UTF-8 is read as
# text; any other file is a finding unless Scripts/allowed-binaries.txt pins its path and SHA-256 as
# reviewed), a sibling's name fused into a longer identifier (sibling names match whole words), a name
# broken across two lines, or anything git ignores.
#
# Needles, all matched case-insensitively:
#   (a) sibling names, DISCOVERED rather than written down: every directory beside home's primary
#       checkout, and one level into any such directory that is not itself a repository but holds some,
#       each in its joined, spaced, hyphenated and underscored spellings, whole-word. When the directory
#       holding the primary checkout is a product folder (outside any git work tree, every directory in
#       it a repository, at least one of them not home: `Tanager/{app,web}`), discovery runs one level
#       up instead, beside the product folder, and the one-level descent carries it back into the
#       product folder's other repositories. Less home's own name, home's product folder (the product
#       the public code belongs to), home's worktree directories, Scripts/public-names.txt, and an
#       optional external list in the same format, default ~/.config/fieldwork/public-names.txt,
#       overridable with FIELDWORK_PUBLIC_NAMES: the neighbours of one machine that are not private
#       projects, kept off the published list because together they describe that machine. An absent
#       external public list is fine (it can only add needles); one that exists but cannot be read is
#       refused.
#       Discovery is the point: a project created next month is covered by a check written today, and
#       the check never names what it protects — so no comment or string in this file may name a
#       private project either.
#   (b) Scripts/private-terms.txt, one ERE per line. A `#` starts a comment only at the start of a line;
#       an entry holding whitespace then `#` is refused, since it would be matched as part of the term.
#       The list is published with the rest, so it holds only terms that are safe to publish, and it is
#       the one file its own terms are not looked for in. Every other needle still reads it.
#   (c) an external list in the same format, default ~/.config/fieldwork/private-terms.txt, overridable
#       with FIELDWORK_PRIVATE_TERMS. Its terms are never printed: a finding cites its line number.
#   (d) the UDIDs of paired devices, if `xcrun devicectl` is available.
#   (e) the running user's $HOME (literal path) and login name (whole word: $USER, else $LOGNAME, else
#       `id -un`), skipped with a note when empty or `/`.
#   (f) any UUID-shaped string: 8-4-4-4-12 hex, or a physical device's `0000xxxx-` then 16 hex. (d)
#       finds a device only while devicectl still lists it, and a deleted simulator's UDID is listed
#       nowhere. Synthetic ids pass (`11111111-2222-3333-4444-` then 12 hex; `0000xxxx-` then 14 zeros
#       and 2 hex), as does every id Scripts/allowed-uuids.txt lists, after a person has checked it is a
#       hand-made placeholder. A finding names the line, never the id.
#
# Output: one line per finding, `path:line: <source>` (`path:path:` when the file's own path matches,
# `path:link:` for a symlink's target, `commit <short-sha>: author|committer|message line <n>: <source>`
# for the commit's metadata), then a count. Every refusal starts with `refused:`.
#
# Exit:  0  nothing found
#        1  findings, or a refusal: the gate could not establish what to look for or where (home's primary
#           checkout unresolvable, a list missing or unreadable, git failing, a file the archive leaves
#           out). A refusal is never a pass.
#        2  no siblings discovered: this machine has no neighbouring projects to learn names from. Only
#           reached once nothing else refused.
#
# Environment (tests only): FIELDWORK_GATE_HOME replaces home for discovery; FIELDWORK_GATE_NEIGHBOURS
# replaces the directory siblings are discovered in, with no product-folder step.
set -eu

refuse() {
    echo "refused: $*"
    exit 1
}

# Every git call below names its repository with -C. An inherited GIT_DIR or GIT_WORK_TREE — set by a
# git hook, say — would silently override that and point the gate at another repository.
for VAR in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$VAR"
done

# A system-wide attributes file could mark a path export-ignore that the committed .gitattributes does
# not; the gate reads attributes from the commit alone (and core.attributesFile is cleared per call).
GIT_ATTR_NOSYSTEM=1
export GIT_ATTR_NOSYSTEM

NAMES_ONLY=0
REV="HEAD"
REV_GIVEN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --names) NAMES_ONLY=1 ;;
        --rev)
            [ "$#" -ge 2 ] && [ -n "$2" ] || refuse "--rev needs a revision"
            REV="$2"
            REV_GIVEN=1
            shift
            ;;
        *) refuse "unknown argument $1 (usage: sh Scripts/verify-tree.sh [--names] [--rev <rev>])" ;;
    esac
    shift
done

LISTS="$(cd "$(dirname "$0")" && pwd -P)" || refuse "cannot resolve the directory holding this script"
TERMS="$LISTS/private-terms.txt"
PUBLIC="$LISTS/public-names.txt"
ALLOWED_BINARIES="$LISTS/allowed-binaries.txt"
ALLOWED_UUIDS="$LISTS/allowed-uuids.txt"
EXTERNAL="${FIELDWORK_PRIVATE_TERMS:-$HOME/.config/fieldwork/private-terms.txt}"
EXTERNAL_PUBLIC="${FIELDWORK_PUBLIC_NAMES:-$HOME/.config/fieldwork/public-names.txt}"
for LIST in "$TERMS" "$PUBLIC" "$ALLOWED_BINARIES" "$ALLOWED_UUIDS"; do
    [ -f "$LIST" ] && [ -r "$LIST" ] || refuse "$LIST is missing or unreadable"
done

SCRATCH="$(mktemp -d)" || refuse "cannot make a temporary directory"
trap 'rm -rf "$SCRATCH"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

TAB="$(printf '\t')"

# The lines of a list that carry an entry: comments and blank lines dropped, whitespace trimmed, CRs
# removed. Prints `<line number><TAB><entry>`, so a finding can cite the line without the entry.
entries() {
    LC_ALL=C awk '{ sub(/\r$/, ""); line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
                    if (line == "" || substr(line, 1, 1) == "#") next
                    printf "%d\t%s\n", NR, line }' "$1"
}

lower() {
    printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'
}

# Physical path of a directory, or nothing when it does not exist.
physical() {
    (cd "$1" 2>/dev/null && pwd -P) || true
}

# ---------------------------------------------------------------------------------------------------
# Home, its primary checkout, and the neighbours.

if [ -n "${FIELDWORK_GATE_HOME:-}" ]; then
    HOME_DIR="$(physical "$FIELDWORK_GATE_HOME")"
    [ -n "$HOME_DIR" ] || refuse "FIELDWORK_GATE_HOME=$FIELDWORK_GATE_HOME is not a directory"
else
    HOME_DIR="$(git -C "$LISTS" rev-parse --show-toplevel 2>/dev/null)" \
        || refuse "$LISTS is not inside a git checkout, so there is no home to read"
    HOME_DIR="$(physical "$HOME_DIR")"
fi

# The common git directory is shared by every worktree of a repository, so a linked worktree resolves
# the same primary checkout — and learns the same names — as the primary does.
COMMON="$(git -C "$HOME_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || refuse "git will not say where $HOME_DIR keeps its repository"
case "$COMMON" in
    */.git) PRIMARY="$(physical "${COMMON%/.git}")" ;;
    *) refuse "$HOME_DIR's repository lives at $COMMON, which is not a checkout's .git, so its primary checkout is unknown" ;;
esac
[ -n "$PRIMARY" ] || refuse "home's primary checkout ${COMMON%/.git} does not exist"
PRIMARY_TOP="$(git -C "$PRIMARY" rev-parse --show-toplevel 2>/dev/null)" \
    || refuse "$PRIMARY, home's primary checkout, is not a git working tree"
[ "$(physical "$PRIMARY_TOP")" = "$PRIMARY" ] || refuse "$PRIMARY is not the top of its own working tree"

if [ -n "${FIELDWORK_GATE_NEIGHBOURS:-}" ]; then
    NEIGHBOURS="$(physical "$FIELDWORK_GATE_NEIGHBOURS")"
    [ -n "$NEIGHBOURS" ] || refuse "FIELDWORK_GATE_NEIGHBOURS=$FIELDWORK_GATE_NEIGHBOURS is not a directory"
else
    NEIGHBOURS="$(dirname "$PRIMARY")"
fi

# A product folder groups one product's repositories, home among them. Its siblings are the other
# products, so discovery moves up to its parent; the folder's own name is the product's, and stays out.
is_product_folder() {
    [ "$(git -C "$1" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ] || return 1
    OTHER_REPOSITORY=0
    for CHILD in "$1"/*; do
        [ -d "$CHILD" ] || continue
        [ -e "$CHILD/.git" ] || return 1
        [ "$(physical "$CHILD")" = "$PRIMARY" ] || OTHER_REPOSITORY=1
    done
    [ "$OTHER_REPOSITORY" = "1" ]
}
PRODUCT=""
if [ -z "${FIELDWORK_GATE_NEIGHBOURS:-}" ] && is_product_folder "$NEIGHBOURS"; then
    PRODUCT="$NEIGHBOURS"
    NEIGHBOURS="$(dirname "$PRODUCT")"
fi

# What discovery leaves out: home's own name, home's product folder, the directories that are home's
# worktrees, and the public names.
OWN_NAME="$(lower "$(basename "$PRIMARY")")"
EXCLUDED_DIRS="$SCRATCH/excluded-dirs"
git -C "$HOME_DIR" worktree list --porcelain > "$SCRATCH/worktrees" 2>/dev/null \
    || refuse "git worktree list failed in $HOME_DIR"
sed -n 's/^worktree //p' "$SCRATCH/worktrees" | while IFS= read -r WT; do
    physical "$WT"
done > "$EXCLUDED_DIRS"
grep -qxF -- "$PRIMARY" "$EXCLUDED_DIRS" || refuse "git worktree list in $HOME_DIR does not name its primary checkout"
[ -z "$PRODUCT" ] || printf '%s\n' "$PRODUCT" >> "$EXCLUDED_DIRS"
# Every stage writes a file and is checked: in a pipeline only the last stage's failure is seen, so an
# earlier one failing would quietly drop its lines (and a finding with them).
public_names() {
    entries "$1" > "$SCRATCH/public.1" || refuse "awk failed reading $1"
    LC_ALL=C cut -f2 "$SCRATCH/public.1" > "$SCRATCH/public.2" || refuse "cut failed on the entries of $1"
    LC_ALL=C sed 's/[[:space:]]*#.*$//' "$SCRATCH/public.2" > "$SCRATCH/public.3" || refuse "sed failed on the entries of $1"
    LC_ALL=C tr '[:upper:]' '[:lower:]' < "$SCRATCH/public.3" >> "$SCRATCH/public" || refuse "tr failed on the entries of $1"
}
: > "$SCRATCH/public"
public_names "$PUBLIC"
if [ -e "$EXTERNAL_PUBLIC" ]; then
    [ -f "$EXTERNAL_PUBLIC" ] && [ -r "$EXTERNAL_PUBLIC" ] \
        || refuse "the external public-names list $EXTERNAL_PUBLIC exists but is unreadable (FIELDWORK_PUBLIC_NAMES names another)"
    public_names "$EXTERNAL_PUBLIC"
fi

SIBLINGS="$SCRATCH/siblings"
: > "$SIBLINGS"
consider() {
    CANDIDATE_NAME="$(basename "$1")"
    case "$CANDIDATE_NAME" in .*) return 0 ;; esac
    [ "$(lower "$CANDIDATE_NAME")" != "$OWN_NAME" ] || return 0
    grep -qxF -- "$(physical "$1")" "$EXCLUDED_DIRS" && return 0
    grep -qxF -- "$(lower "$CANDIDATE_NAME")" "$SCRATCH/public" && return 0
    printf '%s\n' "$CANDIDATE_NAME" >> "$SIBLINGS"
}
holds_repositories() {
    for CHILD in "$1"/*; do
        [ -e "$CHILD/.git" ] && return 0
    done
    return 1
}
for ENTRY in "$NEIGHBOURS"/*; do
    [ -d "$ENTRY" ] || continue
    consider "$ENTRY"
    case "$(basename "$ENTRY")" in .*) continue ;; esac
    if [ ! -e "$ENTRY/.git" ] && holds_repositories "$ENTRY"; then
        for CHILD in "$ENTRY"/*; do
            [ -d "$CHILD" ] && consider "$CHILD"
        done
    fi
done
LC_ALL=C sort -u "$SIBLINGS" -o "$SIBLINGS"
DISCOVERED="$(wc -l < "$SIBLINGS" | tr -d ' ')"

if [ "$NAMES_ONLY" = "1" ]; then
    cat "$SIBLINGS"
    [ "$DISCOVERED" != "0" ] || { echo "no siblings discovered beside $PRIMARY" >&2; exit 2; }
    exit 0
fi

# ---------------------------------------------------------------------------------------------------
# The needle table: `<ERE><TAB><source>` per line. Every needle is an ERE, matched with grep -iE.

NEEDLES="$SCRATCH/needles"
: > "$NEEDLES"

# Escapes a literal for use inside an ERE.
ere_literal() {
    printf '%s\n' "$1" | sed 's/[][\\.*^$+?(){}|]/\\&/g'
}

# A name's words: separators become spaces, and a space goes in at each CamelCase and acronym boundary.
words() {
    printf '%s\n' "$1" | sed -e 's/[-_. ][-_. ]*/ /g' \
        -e 's/\([a-z0-9]\)\([A-Z]\)/\1 \2/g' \
        -e 's/\([A-Z]\)\([A-Z][a-z]\)/\1 \2/g' \
        -e 's/^ *//' -e 's/ *$//' -e 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/'
}

WORD_LEFT='(^|[^[:alnum:]_])'
WORD_RIGHT='([^[:alnum:]_]|$)'
while IFS= read -r NAME; do
    SPACED="$(words "$NAME")"
    ALTERNATIVES=""
    for SPELLING in "$(lower "$NAME")" \
        "$(printf '%s' "$SPACED" | tr -d ' ')" \
        "$SPACED" \
        "$(printf '%s' "$SPACED" | tr ' ' '-')" \
        "$(printf '%s' "$SPACED" | tr ' ' '_')"; do
        ESCAPED="$(ere_literal "$SPELLING")"
        case "|$ALTERNATIVES|" in *"|$ESCAPED|"*) continue ;; esac
        ALTERNATIVES="${ALTERNATIVES:+$ALTERNATIVES|}$ESCAPED"
    done
    printf '%s(%s)%s\t%s\n' "$WORD_LEFT" "$ALTERNATIVES" "$WORD_RIGHT" "sibling $NAME" >> "$NEEDLES"
done < "$SIBLINGS"

# A pattern grep cannot compile is refused before the scan. Its text is never printed: for the external
# list that text is the secret.
add_list() {
    LIST_FILE="$1"
    LABEL="$2"
    entries "$LIST_FILE" > "$SCRATCH/entries"
    [ -s "$SCRATCH/entries" ] || refuse "$LIST_FILE holds no terms"
    while IFS="$TAB" read -r LINE_NO TERM; do
        # `term  # reason` would become a pattern demanding the comment too, so it would never match.
        if printf '%s\n' "$TERM" | LC_ALL=C grep -q '[[:space:]]#'; then
            refuse "$LIST_FILE line $LINE_NO holds an inline comment (whitespace then #), which would be matched as part of the term: put the reason on a line of its own"
        fi
        printf '' | LC_ALL=C grep -E -e "$TERM" > /dev/null 2>&1 && STATUS=0 || STATUS=$?
        [ "$STATUS" -le 1 ] || refuse "$LIST_FILE line $LINE_NO is not a valid extended regular expression"
        printf '%s\t%s\n' "$TERM" "$LABEL$LINE_NO" >> "$NEEDLES"
    done < "$SCRATCH/entries"
}
add_list "$TERMS" "private-terms.txt:"
[ -f "$EXTERNAL" ] && [ -r "$EXTERNAL" ] \
    || refuse "the external list $EXTERNAL is missing or unreadable (set FIELDWORK_PRIVATE_TERMS to its path)"
add_list "$EXTERNAL" "external list line "

# The committed list's path in the tree, when home holds it: the one file its own terms are not looked for in.
TERMS_IN_TREE=""
case "$TERMS" in "$HOME_DIR"/*) TERMS_IN_TREE="${TERMS#"$HOME_DIR"/}" ;; esac

if command -v xcrun > /dev/null 2>&1 && xcrun --find devicectl > /dev/null 2>&1; then
    if xcrun devicectl list devices --json-output "$SCRATCH/devices.json" > /dev/null 2>&1; then
        sed -n -E 's/.*"(udid|identifier)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2/p' "$SCRATCH/devices.json" > "$SCRATCH/udids.1" \
            || refuse "sed failed reading the device list"
        LC_ALL=C sort -u "$SCRATCH/udids.1" > "$SCRATCH/udids" || refuse "sort failed on the device list"
        while IFS= read -r UDID; do
            if [ -n "$UDID" ]; then printf '%s\t%s\n' "$(ere_literal "$UDID")" "device udid" >> "$NEEDLES"; fi
        done < "$SCRATCH/udids"
    else
        echo "note: xcrun devicectl failed, so paired devices' UDIDs are not checked"
    fi
else
    echo "note: xcrun devicectl is not available, so paired devices' UDIDs are not checked"
fi

# Check (f): every UUID-shaped string, less the synthetic ones and those allowed-uuids.txt lists.
UUID_RE='[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{16})'
entries "$ALLOWED_UUIDS" > "$SCRATCH/uuid-entries"
# A first line no id can equal, so awk's first file is never empty.
echo "#" > "$SCRATCH/allowed-uuids"
while IFS="$TAB" read -r LINE_NO ENTRY; do
    if printf '%s\n' "$ENTRY" | LC_ALL=C grep -q '[[:space:]]#'; then
        refuse "$ALLOWED_UUIDS line $LINE_NO holds an inline comment (whitespace then #): put the reason on a line of its own"
    fi
    ALLOWED_ID="$(printf '%s\n' "$ENTRY" | LC_ALL=C awk '{ print $1 }')"
    REASON="$(printf '%s\n' "$ENTRY" | LC_ALL=C awk '{ print $2 }')"
    printf '%s\n' "$ALLOWED_ID" | LC_ALL=C grep -qxE "$UUID_RE" && [ -n "$REASON" ] \
        || refuse "$ALLOWED_UUIDS line $LINE_NO is not \`<uuid> <reason>\`"
    lower "$ALLOWED_ID" >> "$SCRATCH/allowed-uuids"
done < "$SCRATCH/uuid-entries"

# uuid_lines: reads grep -n -o output (`<line>:<id>`) and prints, once each, the line numbers holding an
# id that is neither synthetic nor allowed.
uuid_lines() {
    LC_ALL=C awk -F: '
        NR == FNR { allowed[$0] = 1; next }
        {
            id = tolower($2)
            if (id ~ /^11111111-2222-3333-4444-/ || id ~ /^0000[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-00000000000000/) next
            if (id in allowed || $1 in seen) next
            seen[$1] = 1
            print $1
        }' "$SCRATCH/allowed-uuids" -
}

# The running user: the path of their home and their login name.
if [ -n "${HOME:-}" ] && [ "$HOME" != "/" ]; then
    printf '%s\t%s\n' "$(ere_literal "$HOME")" "home path" >> "$NEEDLES"
else
    echo "note: HOME is empty or /, so the running user's home path is not checked"
fi
# A login shell sets USER, but a hook or a launchd job may not: LOGNAME, then the account itself.
USER_NAME="${USER:-${LOGNAME:-$(id -un 2>/dev/null || true)}}"
if [ -n "$USER_NAME" ] && [ "$USER_NAME" != "/" ]; then
    printf '%s%s%s\t%s\n' "$WORD_LEFT" "$(ere_literal "$USER_NAME")" "$WORD_RIGHT" "user name" >> "$NEEDLES"
else
    echo "note: USER, LOGNAME and id -un are all empty or /, so the running user's name is not checked"
fi

# ---------------------------------------------------------------------------------------------------
# The files: the commit's archive, checked against its tree, plus the untracked ones.

# Git in home, reading attributes from nowhere but the repository (core.attributesFile cleared).
hgit() {
    git -C "$HOME_DIR" -c core.quotePath=false -c core.attributesFile=/dev/null "$@"
}

# Even with quotePath off, git quotes a path holding a newline or a control character, and a quoted path
# is not the path: this would read the wrong file, or none.
no_quoted_paths() {
    if grep -q '^"' "$1"; then
        refuse "a path in $HOME_DIR holds a character this gate cannot pass through: $(grep '^"' "$1" | head -1)"
    fi
}

# list_dir <dir> <out>: every file and symlink under <dir>, relative and sorted, into <out>. A name
# holding a newline is refused: it would read as two paths.
NEWLINE='
'
list_dir() {
    (cd "$1" && find . -name "*$NEWLINE*" -print) > "$2.newline" || refuse "find failed in $1"
    [ ! -s "$2.newline" ] || refuse "a path in $1 holds a newline, which this gate cannot pass through"
    (cd "$1" && find . \( -type f -o -type l \) -print) > "$2.found" || refuse "find failed in $1"
    LC_ALL=C sed 's|^\./||' "$2.found" > "$2.stripped" || refuse "sed failed on the listing of $1"
    LC_ALL=C sort -u "$2.stripped" > "$2" || refuse "sort failed on the listing of $1"
}

# home_tree: home's commit $REV, unpacked into $EXPORT by `git archive`, plus every untracked,
# non-ignored file. Each git call is its own simple command so a failure is caught rather than swallowed
# by a pipeline.
home_tree() {
    REV_SHA="$(hgit rev-parse --verify --quiet "$REV^{commit}" 2>/dev/null)" || refuse "$REV is not a commit in $HOME_DIR"

    hgit ls-tree -r --full-tree "$REV_SHA" > "$SCRATCH/home.tree" 2>/dev/null || refuse "git ls-tree failed for $REV"
    LC_ALL=C awk -F"$TAB" '{ split($1, meta, " "); if (meta[2] == "blob") print $2 }' "$SCRATCH/home.tree" > "$SCRATCH/home.tracked"
    LC_ALL=C awk -F"$TAB" '{ split($1, meta, " "); if (meta[2] != "blob") print $2 }' "$SCRATCH/home.tree" > "$SCRATCH/home.other"
    while IFS= read -r P; do
        echo "note: $P is not a file in $REV (a submodule?), so nothing under it is read"
    done < "$SCRATCH/home.other"
    hgit ls-files --others --exclude-standard > "$SCRATCH/home.untracked" 2>/dev/null \
        || refuse "git ls-files failed in $HOME_DIR"
    no_quoted_paths "$SCRATCH/home.tracked"
    no_quoted_paths "$SCRATCH/home.untracked"
    LC_ALL=C sort -u "$SCRATCH/home.tracked" -o "$SCRATCH/home.tracked"
    LC_ALL=C sort -u "$SCRATCH/home.untracked" -o "$SCRATCH/home.untracked"
    [ -s "$SCRATCH/home.tracked" ] || refuse "$REV holds no files"

    EXPORT="$SCRATCH/export"
    mkdir "$EXPORT" || refuse "cannot make $EXPORT"
    hgit archive --format=tar -o "$SCRATCH/export.tar" "$REV_SHA" 2>/dev/null || refuse "git archive failed for $REV"
    tar -x -f "$SCRATCH/export.tar" -C "$EXPORT" 2>/dev/null || refuse "cannot unpack git archive of $REV"
    rm -f "$SCRATCH/export.tar"
    list_dir "$EXPORT" "$SCRATCH/home.archived"
    LC_ALL=C comm -13 "$SCRATCH/home.tracked" "$SCRATCH/home.archived" > "$SCRATCH/home.unexpected"
    [ ! -s "$SCRATCH/home.unexpected" ] \
        || refuse "git archive of $REV holds a path its tree does not: $(head -1 "$SCRATCH/home.unexpected")"
    # A push publishes the whole tree, so a file the archive leaves out would be published unread.
    LC_ALL=C comm -23 "$SCRATCH/home.tracked" "$SCRATCH/home.archived" > "$SCRATCH/home.left-out"
    [ ! -s "$SCRATCH/home.left-out" ] \
        || refuse "git archive of $REV leaves out $(head -1 "$SCRATCH/home.left-out") (export-ignored?), which a push publishes, so it would go unread"

    # An untracked file is one `git add` from a commit, so it goes into the export to be read with the rest.
    LC_ALL=C comm -23 "$SCRATCH/home.untracked" "$SCRATCH/home.tracked" > "$SCRATCH/home.untracked-only"
    while IFS= read -r P; do
        mkdir -p "$EXPORT/$(dirname "$P")" && cp -P "$HOME_DIR/$P" "$EXPORT/$P" \
            || refuse "cannot copy the untracked $P into the export"
    done < "$SCRATCH/home.untracked-only"
}

home_tree
list_dir "$EXPORT" "$SCRATCH/target.kept"

# With --rev, the commit's own text: author, committer and message, one field per line, so a match's line
# number says which field it is in. Log settings that would add lines (a signature) are turned off.
META="$SCRATCH/meta"
if [ "$REV_GIVEN" = "1" ]; then
    hgit -c log.showSignature=false log -1 --format='%an%n%ae%n%cn%n%ce%n%B' "$REV_SHA" > "$META" 2>/dev/null \
        || refuse "git log failed reading the metadata of $REV"
    SHORT_SHA="$(hgit rev-parse --short "$REV_SHA" 2>/dev/null)" || refuse "git rev-parse failed abbreviating $REV_SHA"
fi

# ---------------------------------------------------------------------------------------------------
# The scan.

cd "$EXPORT"
FILES="$SCRATCH/files"
LINKS="$SCRATCH/links"
: > "$FILES"
: > "$LINKS"
while IFS= read -r P; do
    if [ -L "$P" ]; then
        printf '%s\n' "$P" >> "$LINKS"
    elif [ -f "$P" ]; then
        printf '%s\n' "$P" >> "$FILES"
    else
        echo "note: $P is not a regular file or a symlink (a submodule?), so its contents are not read"
    fi
done < "$SCRATCH/target.kept"

FINDINGS="$SCRATCH/findings"
: > "$FINDINGS"
finding() {
    printf '%s:%s: %s\n' "$1" "$2" "$3" | tee -a "$FINDINGS"
}

# meta_findings <source>: reads the line numbers of matches in $META and prints one finding per field
# they fall in. Lines 1-2 are the author's name and email, 3-4 the committer's, the rest the message.
meta_findings() {
    LC_ALL=C awk '{ n = $1 + 0
                    if (n <= 2) field = "author"; else if (n <= 4) field = "committer"; else field = "message line " (n - 4)
                    if (!(field in seen)) { seen[field] = 1; print field } }' "$SCRATCH/meta-lines" > "$SCRATCH/meta-fields" \
        || refuse "awk failed on the metadata matches for $1"
    while IFS= read -r FIELD; do
        printf 'commit %s: %s: %s\n' "$SHORT_SHA" "$FIELD" "$1" | tee -a "$FINDINGS"
    done < "$SCRATCH/meta-fields"
}

# Binary files. grep cannot be trusted to read a file holding a NUL, or one in UTF-16 or compressed, so
# only NUL-free, valid UTF-8 is text; every other file is refused unless Scripts/allowed-binaries.txt
# pins it, by path and SHA-256, as reviewed.
entries "$ALLOWED_BINARIES" > "$SCRATCH/binary-entries"
: > "$SCRATCH/binaries"
while IFS="$TAB" read -r LINE_NO ENTRY; do
    PINNED_SHA="${ENTRY##* }"
    PINNED_PATH="${ENTRY% *}"
    printf '%s\n' "$PINNED_SHA" | LC_ALL=C grep -qxE '[0-9a-f]{64}' && [ "$PINNED_PATH" != "$ENTRY" ] \
        || refuse "$ALLOWED_BINARIES line $LINE_NO is not \`<path> <lowercase sha256>\`"
    printf '%s\t%s\n' "$PINNED_PATH" "$PINNED_SHA" >> "$SCRATCH/binaries"
done < "$SCRATCH/binary-entries"
TEXT="$SCRATCH/text"
: > "$TEXT"
while IFS= read -r P; do
    # No pipe: cmp exiting early would break tr's pipe ("tr: stdout: Broken pipe") and hide a tr failure.
    LC_ALL=C tr -d '\000' < "$P" > "$SCRATCH/without-nul" || refuse "tr failed reading $P for NUL bytes"
    cmp -s "$SCRATCH/without-nul" "$P" && STATUS=0 || STATUS=$?
    [ "$STATUS" -le 1 ] || refuse "cmp failed comparing $P with its NUL-free copy"
    if [ "$STATUS" = "0" ] && iconv -f UTF-8 -t UTF-8 < "$P" > /dev/null 2>&1; then
        printf '%s\n' "$P" >> "$TEXT"
        continue
    fi
    PINNED_SHA="$(LC_ALL=C awk -F"$TAB" -v p="$P" '$1 == p { print $2; exit }' "$SCRATCH/binaries")"
    if [ -z "$PINNED_SHA" ]; then
        finding "$P" binary "binary file not in allowed-binaries.txt"
    else
        shasum -a 256 "$P" > "$SCRATCH/sha" || refuse "shasum failed reading $P"
        ACTUAL_SHA="$(LC_ALL=C cut -d' ' -f1 "$SCRATCH/sha")" || refuse "cut failed on the sha256 of $P"
        if [ "$ACTUAL_SHA" != "$PINNED_SHA" ]; then
            finding "$P" binary "binary file whose sha256 is not the one allowed-binaries.txt pins"
        fi
    fi
done < "$FILES"

# The text files go in as positional parameters, read from a file rather than a pipe so the loop runs
# in this shell, and quoted so a path holding a space stays whole.
set --
while IFS= read -r P; do
    set -- ${1+"$@"} "$P"
done < "$TEXT"

while IFS="$TAB" read -r RE SOURCE; do
    # The paths themselves.
    LC_ALL=C grep -i -E -e "$RE" -- "$SCRATCH/target.kept" > "$SCRATCH/hits" 2>/dev/null && STATUS=0 || STATUS=$?
    [ "$STATUS" -le 1 ] || refuse "grep failed on the path list for needle $SOURCE"
    while IFS= read -r P; do finding "$P" path "$SOURCE"; done < "$SCRATCH/hits"

    # Symlinks: what the commit carries is the link text, not what it points at.
    while IFS= read -r P; do
        readlink "$P" > "$SCRATCH/linktext" || refuse "readlink failed on $P"
        LC_ALL=C grep -q -i -E -e "$RE" "$SCRATCH/linktext" 2>/dev/null && STATUS=0 || STATUS=$?
        [ "$STATUS" -le 1 ] || refuse "grep failed on the link text of $P for needle $SOURCE"
        if [ "$STATUS" = "0" ]; then finding "$P" link "$SOURCE"; fi
    done < "$LINKS"

    # The commit's metadata and message (--rev). The committed list's exemption is for its own file only.
    if [ "$REV_GIVEN" = "1" ]; then
        LC_ALL=C grep -n -a -i -E -e "$RE" -- "$META" > "$SCRATCH/numbered" 2>/dev/null && STATUS=0 || STATUS=$?
        [ "$STATUS" -le 1 ] || refuse "grep failed on the metadata of $REV for needle $SOURCE"
        LC_ALL=C cut -d: -f1 "$SCRATCH/numbered" > "$SCRATCH/meta-lines" || refuse "cut failed on the metadata matches for needle $SOURCE"
        meta_findings "$SOURCE"
    fi

    # File contents, text only.
    [ "$#" -gt 0 ] || continue
    LC_ALL=C grep -l -a -i -E -e "$RE" -- "$@" > "$SCRATCH/hits" 2>/dev/null && STATUS=0 || STATUS=$?
    [ "$STATUS" -le 1 ] || refuse "grep could not read the tree for needle $SOURCE"
    while IFS= read -r P; do
        # The committed list spells its own terms because that is what it is: the mechanism, not a
        # reference. Every other needle still reads it.
        case "$SOURCE" in
            "private-terms.txt:"*) [ "$P" != "$TERMS_IN_TREE" ] || continue ;;
        esac
        LC_ALL=C grep -n -a -i -E -e "$RE" -- "$P" > "$SCRATCH/numbered" 2>/dev/null \
            || refuse "grep could not reread $P for needle $SOURCE"
        LC_ALL=C cut -d: -f1 "$SCRATCH/numbered" > "$SCRATCH/lines" || refuse "cut failed on the matches in $P for needle $SOURCE"
        while IFS= read -r LINE_NO; do finding "$P" "$LINE_NO" "$SOURCE"; done < "$SCRATCH/lines"
    done < "$SCRATCH/hits"
done < "$NEEDLES"

# Check (f), UUIDs: in the paths, the symlinks' text and the text files' contents, like the needles above.
LC_ALL=C grep -n -o -a -E -e "$UUID_RE" -- "$SCRATCH/target.kept" > "$SCRATCH/numbered" 2>/dev/null && STATUS=0 || STATUS=$?
[ "$STATUS" -le 1 ] || refuse "grep failed on the path list for UUIDs"
uuid_lines < "$SCRATCH/numbered" > "$SCRATCH/lines" || refuse "awk failed on the UUID matches"
while IFS= read -r LINE_NO; do finding "$(sed -n "${LINE_NO}p" "$SCRATCH/target.kept")" path uuid; done < "$SCRATCH/lines"
while IFS= read -r P; do
    readlink "$P" > "$SCRATCH/linktext" || refuse "readlink failed on $P"
    LC_ALL=C grep -n -o -E -e "$UUID_RE" "$SCRATCH/linktext" > "$SCRATCH/numbered" 2>/dev/null && STATUS=0 || STATUS=$?
    [ "$STATUS" -le 1 ] || refuse "grep failed on the link text of $P for UUIDs"
    uuid_lines < "$SCRATCH/numbered" > "$SCRATCH/lines" || refuse "awk failed on the UUIDs in the link text of $P"
    if [ -s "$SCRATCH/lines" ]; then finding "$P" link uuid; fi
done < "$LINKS"
if [ "$REV_GIVEN" = "1" ]; then
    LC_ALL=C grep -n -o -a -E -e "$UUID_RE" -- "$META" > "$SCRATCH/numbered" 2>/dev/null && STATUS=0 || STATUS=$?
    [ "$STATUS" -le 1 ] || refuse "grep failed on the metadata of $REV for UUIDs"
    uuid_lines < "$SCRATCH/numbered" > "$SCRATCH/meta-lines" || refuse "awk failed on the UUIDs in the metadata of $REV"
    meta_findings uuid
fi
if [ "$#" -gt 0 ]; then
    LC_ALL=C grep -l -a -E -e "$UUID_RE" -- "$@" > "$SCRATCH/hits" 2>/dev/null && STATUS=0 || STATUS=$?
    [ "$STATUS" -le 1 ] || refuse "grep could not read the tree for UUIDs"
    while IFS= read -r P; do
        LC_ALL=C grep -n -o -a -E -e "$UUID_RE" -- "$P" > "$SCRATCH/numbered" 2>/dev/null \
            || refuse "grep could not reread $P for UUIDs"
        uuid_lines < "$SCRATCH/numbered" > "$SCRATCH/lines" || refuse "awk failed on the UUID matches"
        while IFS= read -r LINE_NO; do finding "$P" "$LINE_NO" uuid; done < "$SCRATCH/lines"
    done < "$SCRATCH/hits"
fi

COUNT="$(wc -l < "$FINDINGS" | tr -d ' ')"
CHECKED="$(($(wc -l < "$FILES" | tr -d ' ') + $(wc -l < "$LINKS" | tr -d ' ')))"
echo "$COUNT findings in $CHECKED files ($DISCOVERED sibling names)"
[ "$COUNT" = "0" ] || exit 1
# Findings outrank this: they are about the tree, and this is about the machine.
if [ "$DISCOVERED" = "0" ]; then
    echo "refused: no siblings discovered beside $PRIMARY (in $NEIGHBOURS), so there were no names to look for"
    exit 2
fi
exit 0
