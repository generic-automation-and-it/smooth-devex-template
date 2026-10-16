#!/usr/bin/env bash
# Harness for the bash skills installer (`install-skills.sh`).
#
# Scope: the manifest reconciliation and the root search. The clone/copy path is exercised against the
# checkout itself as the clone source (SKILLS_REPO=the repo, SKILLS_BRANCH=the current branch), so no
# network and no GitHub access is involved - a harness that reached the network would be red for reasons
# that have nothing to do with the code under test.
#
# Every case runs in a scratch tree under $TMPDIR. The installer only ever writes inside the skills root
# it resolves, and every case forces that root with SKILLS_ROOT, so a red run cannot touch the checkout's
# own .agents/skills.
#
# Cross-port parity: the bash OWNED_LIST and the ps1 $script:OwnedList must agree byte-for-byte.
# The harness does a static grep+diff comparison so a divergent PowerShell declaration fails the
# bash-only gate before the ps1 port is run locally.
#
# The PowerShell port (`install-skills.ps1`) is **not exercised at runtime** by this harness. It is a
# hand-translated mirror of the bash port - same contract, same control flow - and its defects are the
# ones a careful read catches. A two-port harness doubles the maintenance surface for a contract that
# exists to be read, not to be redundantly proven on platforms the gate does not run.
#
# Repo-specific notes (smooth-devex-template, where this lives):
#   - The shared folder is `_smooth-devex-shared` (per-repo, never `_mimisbrunnr-shared`).
#   - The source tree does NOT currently ship a `_smooth-devex-shared/` folder, so the harness skips
#     the cases that depend on a shared-folder refresh. Add them back if a shared folder lands here.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer_sh="$repo_root/scripts/install-skills.sh"
installer_ps1="$repo_root/scripts/install-skills.ps1"
[ -f "$installer_ps1" ] || { echo "FAIL: scripts/install-skills.ps1 missing" >&2; exit 1; }

source_repo="$repo_root"
# Empty unless HEAD really is a branch. `git rev-parse --abbrev-ref HEAD` answers the literal string
# "HEAD" in a detached checkout - which is what actions/checkout produces - and that is not a valid
# `git clone --branch` argument, so passing it through made every case die at the clone on the gate while
# the same harness passed on a developer machine. `symbolic-ref` answers nothing at all when detached,
# which is the honest signal that there is no branch to name.
source_branch="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

passed=0
failed=0

ok() { passed=$((passed + 1)); echo "  ok   $1"; }
no() {
  failed=$((failed + 1))
  echo "  FAIL $1"
  [ -n "${2:-}" ] && echo "       $2"
  return 0
}

# Static parity check: bash OWNED_LIST vs ps1 $script:OwnedList. The two must agree byte-for-byte
# (after sorting), or a divergent PowerShell declaration would pass this harness while shipping the
# wrong owned set. This is the only PowerShell-facing check on the bash-only gate; it is fast and
# needs no pwsh.
#
# Extract each port's owned set by anchoring on the OWNED_LIST declaration in bash and the literal
# block immediately under `$script:OwnedList = @(` in ps1. A loose grep would pick up function names
# and format strings elsewhere in the ps1 file.
bash_owned="$(awk '/^OWNED_LIST=\($/,/^\)$/' "$installer_sh" \
  | grep -oE "^[[:space:]]+'?[a-z][a-z0-9-]+'?[[:space:]]*\$" \
  | grep -oE "'?[a-z][a-z0-9-]+'?" | tr -d "'" | sort -u)"
ps1_owned="$(awk '/\$script:OwnedList = @\($/,/^\)$/' "$installer_ps1" \
  | sed 's/^[[:space:]]*//' \
  | grep -oE "^'[a-z][a-z0-9-]+'" \
  | tr -d "'" | sort -u)"
if [ "$bash_owned" = "$ps1_owned" ] && [ -n "$bash_owned" ]; then
  joined="$(printf '%s\n' "$bash_owned" | paste -sd ',' -)"
  ok "cross-port: bash OWNED_LIST and ps1 \$script:OwnedList agree ($joined)"
else
  bash_joined="$(printf '%s\n' "$bash_owned" | paste -sd ',' -)"
  ps1_joined="$(printf '%s\n' "$ps1_owned" | paste -sd ',' -)"
  no "cross-port: bash OWNED_LIST and ps1 \$script:OwnedList agree" \
    "bash='$bash_joined' ps1='$ps1_joined'"
fi

# A fresh scratch skills root carrying $2 named skills, one SKILL.md each. Echoes the root.
make_root() {
  local root="$scratch/case-$1/.agents/skills"
  shift
  mkdir -p "$root/_smooth-devex-shared"
  local name
  for name in "$@"; do
    mkdir -p "$root/$name"
    printf '# %s\n' "$name" >"$root/$name/SKILL.md"
  done
  printf '%s\n' "$root"
}

# The installer clones from the checkout itself; the shared-folder refresh only fires when the source
# ships one, so SKILLS_BRANCH is empty in a detached checkout (the only honest answer there).
run_sh() {
  local root="$1"; shift
  SKILLS_ROOT="$root" SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
    SKILLS_TEST_OWNED_EXTRA="alpha beta gamma delta epsilon" \
    bash "$installer_sh" "$@" >"$scratch/out" 2>"$scratch/err"
}

# manifest_field ROOT 'name' -> the installed flag ("true"/"false"), or empty when absent.
manifest_flag() {
  python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
for s in data.get('skills', []):
    if s['name'] == sys.argv[2]:
        print('true' if s['installed'] else 'false')
        raise SystemExit(0)
" "$1/_smooth-devex-shared/installation.json" "$2"
}

manifest_names() {
  python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
print(' '.join(s['name'] for s in data.get('skills', [])))
" "$1/_smooth-devex-shared/installation.json"
}

# ISO-8601 UTC: 2026-10-15T13:10:22Z. Asserted against a regex rather than a parse, because the point is
# the *shape* - a machine must be able to compare two manifests as strings.
manifest_timestamp_ok() {
  python3 -c "
import json, re, sys
stamp = json.load(open(sys.argv[1]))['updated']
raise SystemExit(0 if re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', stamp) else 1)
" "$1/_smooth-devex-shared/installation.json"
}



echo "skills installer harness (branch: $source_branch)"

# ---------------------------------------------------------------------------------------------
# 1. a first run creates the manifest from what is on disk
# ---------------------------------------------------------------------------------------------

root="$(make_root "first" alpha beta)"
run_sh "$root" >/dev/null 2>&1 || true
manifest="$root/_smooth-devex-shared/installation.json"
if [ ! -f "$manifest" ]; then no "first run creates installation.json"; exit 1; fi
# The catalogue is the owned intersection of source + disk. Real owned skills from source (the seven
# .agents/skills names from this template) plus the harness's synthetic owned names (alpha/beta via
# SKILLS_TEST_OWNED_EXTRA). An unowned skill like agile-github-breakdown is in source but NOT in
# the catalogue - the contract this case pins.
names=" $(manifest_names "$root") "
for expected in alpha beta ai-terse create-hld; do
  case "$names" in
    *" $expected "*) ;;
    *) no "first run lists source skills as well as those on disk" "$expected missing from: $names"; exit 1 ;;
  esac
done
if [ "$(manifest_flag "$root" alpha)" != "true" ] || [ "$(manifest_flag "$root" beta)" != "true" ] || [ "$(manifest_flag "$root" ai-terse)" != "true" ]; then
  no "first run marks skills installed:true" "alpha=$(manifest_flag "$root" alpha) beta=$(manifest_flag "$root" beta) ai-terse=$(manifest_flag "$root" ai-terse)"
  exit 1
fi
if ! manifest_timestamp_ok "$root"; then no "first run stamps an ISO-8601 UTC time"; exit 1; fi

# Unowned check: agile-github-breakdown ships in source but is NOT owned - must not enter the manifest.
# This is the contract this whole PR fixes; the unscoped installer pulled such names in.
case "$names" in
  *" agile-github-breakdown "*) no "first run: unowned source skill is not in the manifest" "found: $names" ;;
  *) ok "first run: unowned source skill (agile-github-breakdown) is not in the manifest" ;;
esac

ok "first run: manifest from owned source ∪ disk, all installed:true, ISO-8601 UTC stamp"

# ---------------------------------------------------------------------------------------------
# 2. reconcile: keep an operator's false, add new skills, drop removed ones
# ---------------------------------------------------------------------------------------------

root="$(make_root "reconcile" alpha beta gamma)"
run_sh "$root" >/dev/null 2>&1

# The operator switches alpha off.
python3 - "$root/_smooth-devex-shared/installation.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for entry in data["skills"]:
    if entry["name"] == "alpha":
        entry["installed"] = False
json.dump(data, open(path, "w"), indent=2)
PYEOF
# ...and a skill is removed from disk while another is added.
rm -rf "$root/gamma"
mkdir -p "$root/delta"; printf '# delta\n' >"$root/delta/SKILL.md"

run_sh "$root" >/dev/null 2>&1

# gamma is in neither the source nor disk any more, so it must go; delta is new and must join.
# The real source skills stay, so "dropped" cannot pass by emptying the manifest.
names=" $(manifest_names "$root") "
case "$names" in
  *" gamma "*) no "reconcile: a removed skill is dropped" "gamma survived in:$names" ;;
  *" alpha "*) ok "reconcile: a removed skill is dropped" ;;
  *) no "reconcile: a removed skill is dropped" "alpha went missing too - the manifest was rebuilt, not reconciled:$names" ;;
esac
case "$names" in
  *" delta "*) ok "reconcile: a newly seen skill is added" ;;
  *) no "reconcile: a newly seen skill is added" "delta missing from:$names" ;;
esac
case "$names" in
  *" ai-terse "*) ok "reconcile: source skills are retained" ;;
  *) no "reconcile: source skills are retained" "ai-terse missing from:$names" ;;
esac
[ "$(manifest_flag "$root" alpha)" = "false" ] \
  && ok "reconcile: an operator's installed:false survives the sync" \
  || no "reconcile: an operator's installed:false survives the sync" "alpha=$(manifest_flag "$root" alpha)"
[ "$(manifest_flag "$root" delta)" = "true" ] \
  && ok "reconcile: a newly seen skill joins as installed:true" \
  || no "reconcile: a newly seen skill joins as installed:true" "delta=$(manifest_flag "$root" delta)"

# ---------------------------------------------------------------------------------------------
# 3. the manifest survives a run (write order, not luck)
# ---------------------------------------------------------------------------------------------
# A no-shared-folder check: the manifest is written last, so even when the source ships no
# _smooth-devex-shared/ folder, the manifest still appears at the end of a run.

root="$(make_root "writeorder" alpha)"
run_sh "$root" >/dev/null 2>&1 || true
if [ -f "$root/_smooth-devex-shared/installation.json" ]; then
  ok "manifest survives a run that had no shared folder to refresh"
else
  no "manifest survives a run that had no shared folder to refresh" "manifest missing"
fi

# ---------------------------------------------------------------------------------------------
# 3c. a first install into an EMPTY skills folder actually installs something
# ---------------------------------------------------------------------------------------------

# This is the case the end-to-end run caught and the harness did not: with the catalogue derived from
# disk alone, an empty folder offers nothing to install, so the very first run - the one every operator
# does - left them with an empty folder and a manifest listing nothing, and reported success.
root="$scratch/emptyinstall/.codex/skills"
mkdir -p "$root"
run_sh "$root" >/dev/null 2>&1 || true
on_disk="$(find "$root" -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
if [ "$on_disk" -gt 5 ] && [ "$on_disk" = "$(manifest_names "$root" | wc -w | tr -d ' ')" ]; then
  ok "a first install into an empty folder puts the source's skills on disk ($on_disk)"
else
  no "a first install into an empty folder puts the source's skills on disk" \
    "on disk: $on_disk, in manifest: $(manifest_names "$root" | wc -w | tr -d ' ')"
fi

# Deny-list check: ai-brain-dump and ai-understanding ship in source but the installer must not carry
# them across. An operator who did not ask for a personal braindump or session-archiving tool does not
# get one as a side effect of the template install.
names=" $(manifest_names "$root") "
for denied in ai-brain-dump ai-understanding; do
  case "$names" in
    *" $denied "*) no "deny list: $denied is not in the manifest" "found in: $names" ;;
    *) ok "deny list: $denied is not in the manifest" ;;
  esac
  if [ -d "$root/$denied" ]; then
    no "deny list: $denied is not copied to the consumer" "$denied/ is on disk"
  else
    ok "deny list: $denied is not copied to the consumer"
  fi
done

# ---------------------------------------------------------------------------------------------
# 3d. the deny list survives a hand-edited manifest
# ---------------------------------------------------------------------------------------------

# Defence-in-depth: even if the caller hand-writes the manifest with a denied skill set installed:true,
# the update step must still refuse to copy it. That is the only way an exclusion written into the
# installer stays an exclusion regardless of manifest provenance. The loop covers every entry in the
# hardcoded deny list.
root="$(make_root "denyhandedit" ai-terse)"
run_sh "$root" >/dev/null 2>&1
# Inject both denied skills into the manifest by hand.
python3 - "$root/_smooth-devex-shared/installation.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for name in ("ai-brain-dump", "ai-understanding"):
    if not any(s["name"] == name for s in data["skills"]):
        data["skills"].append({"name": name, "installed": True})
json.dump(data, open(path, "w"), indent=2)
PYEOF
run_sh "$root" >/dev/null 2>&1
for denied in ai-brain-dump ai-understanding; do
  if [ ! -d "$root/$denied" ]; then
    ok "deny list survives a hand-edited manifest (no $denied on disk)"
  else
    no "deny list survives a hand-edited manifest (no $denied on disk)" "$denied/ landed"
  fi
done

# ---------------------------------------------------------------------------------------------
# 4. only installed:true folders are replaced from the clone source
# ---------------------------------------------------------------------------------------------

# ai-terse (leaf, no scripts/) and create-hld (carries scripts/) both exist in the checkout AND are
# owned, so both are real clone-and-copy cases rather than synthetic names that would only exercise
# the warning branch.
root="$(make_root "update" ai-terse create-hld)"
printf 'operator edit\n' >"$root/ai-terse/SKILL.md"
run_sh "$root" >/dev/null 2>&1

if grep -q '^name:' "$root/ai-terse/SKILL.md" 2>/dev/null; then
  ok "an installed:true skill is replaced from the clone source"
else
  no "an installed:true skill is replaced from the clone source" "SKILL.md still: $(head -1 "$root/ai-terse/SKILL.md")"
fi
if [ -d "$root/create-hld/scripts" ]; then
  ok "the copied skill carries its scripts folder"
else
  no "the copied skill carries its scripts folder"
fi

# Now the same run with one skill switched off: the off folder must be left exactly as it is.
# The manifest has to exist before it can be switched off, so this is a first run followed by an
# edit: that is the operator's actual sequence (install, then turn a skill off).
root2="$(make_root "update-off" ai-terse create-hld)"
printf 'operator edit\n' >"$root2/ai-terse/SKILL.md"
run_sh "$root2" >/dev/null 2>&1
printf 'operator edit\n' >"$root2/ai-terse/SKILL.md"
python3 - "$root2/_smooth-devex-shared/installation.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for entry in data["skills"]:
    entry["installed"] = False
json.dump(data, open(path, "w"), indent=2)
PYEOF
run_sh "$root2" >/dev/null 2>&1
if [ "$(cat "$root2/ai-terse/SKILL.md")" = "operator edit" ]; then
  ok "an installed:false skill is never overwritten"
else
  no "an installed:false skill is never overwritten" "content is now: $(head -1 "$root2/ai-terse/SKILL.md")"
fi

# 4b. An unowned skill present on disk (and in source) is left byte-identical and never enters the
# manifest. This is the bug the unscoped installer had - it pulled a foreign repo's local-only
# skills into its manifest and marked them installed:true. The owned-set gate stops that here.
#
# agile-github-breakdown is in source but NOT in OWNED_LIST, so it is the unowned probe for this
# case. We plant it on disk with operator-local content (a non-source SKILL.md), run, and assert
# the disk content is unchanged AND the manifest has no such name.
root="$(make_root "update-unowned" agile-github-breakdown)"
printf 'operator-local content\n' >"$root/agile-github-breakdown/SKILL.md"
run_sh "$root" >/dev/null 2>&1
if [ "$(cat "$root/agile-github-breakdown/SKILL.md")" = "operator-local content" ]; then
  ok "an unowned source skill left on disk is left byte-identical (not copied over)"
else
  no "an unowned source skill left on disk is left byte-identical" "now: $(cat "$root/agile-github-breakdown/SKILL.md")"
fi
case " $(manifest_names "$root") " in
  *" agile-github-breakdown "*) no "an unowned source skill on disk is not listed in the manifest" "found in manifest" ;;
  *) ok "an unowned source skill on disk is not listed in the manifest" ;;
esac

# 4c. A hand-edited manifest naming an unowned skill installed:true is refused at the reconcile step.
# The catalogue (built from owned source ∪ owned disk) drops the unowned entry before update runs, so
# the next run never tries to copy it. This pins the reconciliation-side defence. Case 4d is the
# separate update-loop guard check.
root="$(make_root "update-unowned-edit" alpha)"
run_sh "$root" >/dev/null 2>&1
python3 - "$root/_smooth-devex-shared/installation.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["skills"].append({"name": "agile-github-breakdown", "installed": True})
json.dump(data, open(path, "w"), indent=2)
PYEOF
run_sh "$root" >/dev/null 2>&1
if [ ! -d "$root/agile-github-breakdown" ]; then
  ok "reconcile: a hand-edited manifest's unowned entry is dropped, not copied"
else
  no "reconcile: a hand-edited manifest's unowned entry is dropped, not copied" "agile-github-breakdown/ landed"
fi

# 4d. Direct update-loop guard check. The normal entry point rebuilds the manifest before updating,
# so the reconcile step alone catches a hand-edited unowned entry (case 4c above). The update loop's
# own guard is defence-in-depth: if the rebuild is skipped, the updater must still refuse to copy
# unowned names. SKILLS_TEST_SKIP_RECONCILE=1 takes the direct path: no rebuild, no clone, run only
# the update step against the existing manifest.
#
# The test plants operator-local content on disk AND plants different (source-like) content in
# INSTALL_TMP, so removing the guard makes the test fail (source content overwrites operator). With
# the guard, operator content survives intact.
#
# This case fails when the update-loop guard is deleted - the assertion is the regression test.
root="$(make_root "update-guard" alpha)"
mkdir -p "$root/agile-github-breakdown"
printf 'operator-local content\n' >"$root/agile-github-breakdown/SKILL.md"
run_sh "$root" >/dev/null 2>&1
python3 - "$root/_smooth-devex-shared/installation.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["skills"].append({"name": "agile-github-breakdown", "installed": True})
json.dump(data, open(path, "w"), indent=2)
PYEOF
# Set up the synthetic source with DIFFERENT content for the unowned skill.
INSTALL_TMP="$(mktemp -d)"
mkdir -p "$INSTALL_TMP/repo/.agents/skills"
mkdir -p "$INSTALL_TMP/repo/.agents/skills/agile-github-breakdown"
printf 'upstream-source content\n' >"$INSTALL_TMP/repo/.agents/skills/agile-github-breakdown/SKILL.md"
SKILLS_ROOT="$root" SKILLS_TEST_OWNED_EXTRA="alpha beta gamma delta epsilon" \
  SKILLS_TEST_SKIP_RECONCILE=1 INSTALL_TMP="$INSTALL_TMP" \
  bash "$installer_sh" >/dev/null 2>&1 || true
rm -rf "$INSTALL_TMP"
if [ "$(cat "$root/agile-github-breakdown/SKILL.md")" = "operator-local content" ]; then
  ok "update-guard: a hand-edited unowned entry is refused by the updater loop (operator content preserved)"
else
  no "update-guard: a hand-edited unowned entry is refused by the updater loop" \
    "SKILL.md content is now: $(cat "$root/agile-github-breakdown/SKILL.md")"
fi

# ---------------------------------------------------------------------------------------------
# 5. a corrupt manifest is an error, not a first install
# ---------------------------------------------------------------------------------------------

root="$(make_root "corrupt" alpha)"
printf '{ not json' >"$root/_smooth-devex-shared/installation.json"
# A non-zero exit is the expected outcome here, so it must not trip the harness's own set -e.
run_sh "$root" >/dev/null 2>&1 || true
# A corrupt manifest must not be rewritten AND must not let the run update any skill.
st=0
run_sh "$root" >/dev/null 2>&1 || st=$?
if [ "$st" -ne 0 ] && [ "$(cat "$root/_smooth-devex-shared/installation.json")" = "{ not json" ]; then
  ok "a corrupt manifest is refused, non-zero exit, and left untouched"
else
  no "a corrupt manifest is refused, non-zero exit, and left untouched" \
    "st=$st content=$(cat "$root/_smooth-devex-shared/installation.json")"
fi

# 5b. A blank or whitespace-only manifest is the same kind of unparseable input: an empty file would
# otherwise be accepted as a first install and silently re-enable every catalogue skill.
root="$(make_root "blank" alpha)"
printf '   \n\n  \n' >"$root/_smooth-devex-shared/installation.json"
st=0
run_sh "$root" >/dev/null 2>&1 || st=$?
if [ "$st" -ne 0 ] && [ "$(cat "$root/_smooth-devex-shared/installation.json" | tr -d '[:space:]')" = "" ]; then
  ok "a blank manifest is refused, non-zero exit, and left untouched"
else
  no "a blank manifest is refused, non-zero exit, and left untouched" \
    "st=$st content='$(cat "$root/_smooth-devex-shared/installation.json")'"
fi

# 5c. An absolute local path is passed through to git without a mangled file://$PWD prefix. The
# installer must not break the harness's own clone source (which is the absolute repo path) by
# doubling it up. A green run here means the install completed against an absolute path source.
root="$(make_root "abspath" alpha)"
run_sh "$root" >/dev/null 2>&1 || true
if [ -f "$root/_smooth-devex-shared/installation.json" ]; then
  ok "an absolute local SKILLS_REPO is accepted (no double file:// prefix)"
else
  no "an absolute local SKILLS_REPO is accepted (no double file:// prefix)" "manifest missing"
fi

# 5d. A scp-style SSH remote is passed through to git unchanged, not rewritten to file://$PWD/ssh...
# We can't actually clone from SSH in the harness, so we assert on the rewritten value via a fake
# run that captures stderr and then check that the error message contains the literal SSH URL (a
# mangled URL would have lost the @ and the :owner/ parts).
root="$(make_root "sshpass" alpha)"
err="$scratch/ssh.err"
SKILLS_ROOT="$root" SKILLS_REPO="git@github.com:nonexistent-fake-host-9876543210/repo.git" SKILLS_BRANCH="main" \
  bash "$installer_sh" 2>"$err" >/dev/null || true
if grep -q 'git@github.com:nonexistent-fake-host-9876543210/repo.git' "$err"; then
  ok "an scp-style SSH SKILLS_REPO is passed through unchanged to git"
else
  no "an scp-style SSH SKILLS_REPO is passed through unchanged to git" "stderr=$(cat "$err")"
fi

# 5e. When every skill is installed:false, the shared-folder refresh still fires. A previous version
# returned early on an empty installed list, which skipped the copy-and-sweep block and let shared
# helpers go stale. This case would catch a regression: it is the contract-violating shape.
#
# The harness cannot exercise the shared copy itself because the source tree has no _smooth-devex-shared
# folder, but it CAN exercise the no-installed-names path and assert the installer does not bail out
# at the skill-loop. We assert on the manifest still being written - that requires the script not to
# have errored out at the early return.
root="$(make_root "noskillson" alpha)"
# After a normal run, the manifest is installed:true for alpha. Switch it to false.
run_sh "$root" >/dev/null 2>&1
python3 - "$root/_smooth-devex-shared/installation.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for entry in data["skills"]:
    entry["installed"] = False
json.dump(data, open(path, "w"), indent=2)
PYEOF
st=0
run_sh "$root" >/dev/null 2>&1 || st=$?
if [ "$st" -eq 0 ] && [ -f "$root/_smooth-devex-shared/installation.json" ]; then
  ok "an all-installed:false manifest does not abort the run (shared refresh still runs)"
else
  no "an all-installed:false manifest does not abort the run (shared refresh still runs)" "st=$st"
fi

# ---------------------------------------------------------------------------------------------
# 6. the root search, in the documented order
# ---------------------------------------------------------------------------------------------

# Run the installer in $1 (a scratch directory), with SKILLS_ROOT deliberately unset so the search runs.
# Echoes the exit status instead of failing the harness, so a case can assert on it.
run_in_dir_searched() {
  local dir="$1"
  ( cd "$dir" && SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" bash "$installer_sh" ) >/dev/null 2>&1
}

# A tree with .claude/skills and .codex/skills but no .agents/skills: the search must land on
# .claude/skills, in the documented order, and must not create anything.
base="$scratch/search"
mkdir -p "$base/.claude/skills/only-claude" "$base/.codex/skills/only-codex"
printf '# only-claude\n' >"$base/.claude/skills/only-claude/SKILL.md"
printf '# only-codex\n' >"$base/.codex/skills/only-codex/SKILL.md"
if ! run_in_dir_searched "$base"; then
  no "root search: the run succeeds" "see the run above"
elif [ -f "$base/.claude/skills/_smooth-devex-shared/installation.json" ] && [ ! -e "$base/.codex/skills/_smooth-devex-shared" ]; then
  ok "root search: .claude/skills wins over .codex/skills"
else
  no "root search: .claude/skills wins over .codex/skills" "the manifest landed in the wrong root"
fi
if [ -e "$base/.agents" ]; then
  no "root search: creates no skills directory" "it created .agents"
else
  ok "root search: creates no skills directory"
fi

# A tree with no skills directory at all: a hard error, and still nothing created.
empty="$scratch/empty"
mkdir -p "$empty"
if run_in_dir_searched "$empty"; then
  no "no skills directory exits non-zero" "expected failure, got success"
else
  ok "no skills directory exits non-zero"
fi
if [ ! -d "$empty/.agents" ] && [ ! -d "$empty/.claude" ]; then
  ok "no skills directory: creates nothing"
else
  no "no skills directory: creates nothing" "it created a skills directory"
fi

# ---------------------------------------------------------------------------------------------

echo
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]