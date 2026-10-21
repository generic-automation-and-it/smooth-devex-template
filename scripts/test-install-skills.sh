#!/usr/bin/env bash
# Harness for the bash skills installer (`install-skills.sh`).
#
# Scope: the manifest reconciliation, the agent-root search, and the shared-payload refresh.
# The clone/copy path is exercised against the checkout itself as the clone source
# (SKILLS_REPO=the repo, SKILLS_BRANCH=the current branch), so no network and no GitHub access
# is involved - a harness that reached the network would be red for reasons that have nothing to do
# with the code under test.
#
# Every case runs in a scratch tree under $TMPDIR. The installer only ever writes inside the agent
# root it resolves, and every case forces that root via SKILLS_ROOT (pointed at <agent>/skills, so
# the shared dir under test is <agent>/_smooth-devex-shared), so a red run cannot touch the
# checkout's own .agents tree.
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
#   - The source tree ships `.agents/_smooth-devex-shared/` (cross-cutting, repo-owned payload:
#     currently setup/scripts), so the refresh, symlink, and sweep cases run against the real thing.
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

owned_n="$(printf '%s\n' "$bash_owned" | wc -l | tr -d ' ')"

# Same byte-for-byte gate for the owned rules and hooks lists. Rule entries contain slashes and
# dots, hook entries are filenames — one loose-enough pattern each, anchored on the declaration.
bash_rules="$(awk '/^OWNED_RULES=\($/,/^\)$/' "$installer_sh" \
  | grep -oE "^[[:space:]]+[A-Za-z0-9_./-]+\.instructions\.md|^[[:space:]]+AGENTS\.md" \
  | tr -d ' ' | sort -u)"
ps1_rules="$(awk '/\$script:OwnedRules = @\($/,/^\)$/' "$installer_ps1" \
  | grep -oE "'[A-Za-z0-9_./-]+'| 'AGENTS\.md'" \
  | tr -d "' " | sort -u)"
if [ "$bash_rules" = "$ps1_rules" ] && [ -n "$bash_rules" ]; then
  ok "cross-port: bash OWNED_RULES and ps1 \$script:OwnedRules agree ($(printf '%s\n' "$bash_rules" | paste -sd ',' -))"
else
  no "cross-port: bash OWNED_RULES and ps1 \$script:OwnedRules agree" \
    "bash='$(printf '%s\n' "$bash_rules" | paste -sd ',' -)' ps1='$(printf '%s\n' "$ps1_rules" | paste -sd ',' -)'"
fi
bash_hooks="$(awk '/^OWNED_HOOKS=\($/,/^\)$/' "$installer_sh" \
  | grep -oE "^[[:space:]]+[a-z0-9-]+\.(sh|py)" \
  | tr -d ' ' | sort -u)"
ps1_hooks="$(awk '/\$script:OwnedHooks = @\($/,/^\)$/' "$installer_ps1" \
  | grep -oE "'[a-z0-9-]+\.(sh|py)'" \
  | tr -d "'" | sort -u)"
if [ "$bash_hooks" = "$ps1_hooks" ] && [ -n "$bash_hooks" ]; then
  ok "cross-port: bash OWNED_HOOKS and ps1 \$script:OwnedHooks agree ($(printf '%s\n' "$bash_hooks" | paste -sd ',' -))"
else
  no "cross-port: bash OWNED_HOOKS and ps1 \$script:OwnedHooks agree" \
    "bash='$(printf '%s\n' "$bash_hooks" | paste -sd ',' -)' ps1='$(printf '%s\n' "$ps1_hooks" | paste -sd ',' -)'"
fi

# A fresh scratch agent root carrying $2 named skills, one SKILL.md each. Echoes the agent root;
# the skills root under test is <agent>/skills. Manifest helpers below take this agent root.
make_root() {
  local root="$scratch/case-$1/.agents"
  shift
  mkdir -p "$root/skills"
  local name
  for name in "$@"; do
    mkdir -p "$root/skills/$name"
    printf '# %s\n' "$name" >"$root/skills/$name/SKILL.md"
  done
  printf '%s\n' "$root"
}

# The installer clones from the checkout itself; SKILLS_BRANCH is empty in a detached checkout
# (the only honest answer there). SKILLS_ROOT points at <agent>/skills so the manifest under
# test lands at <agent>/_smooth-devex-shared/installation.json.
run_sh() {
  local root="$1"; shift
  SKILLS_ROOT="$root/skills" SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
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
# SKILLS_TEST_OWNED_EXTRA). An unowned skill like ai-brain-dump is in source but NOT in
# the catalogue - the contract this case pins.
names=" $(manifest_names "$root") "
for expected in alpha beta ai-terse create-hld agile-github-breakdown context-load-context git-sync; do
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

# Unowned check: ai-brain-dump ships in source but is NOT owned - must not enter the manifest.
# This is the contract this whole PR fixes; the unscoped installer pulled such names in.
case "$names" in
  *" ai-brain-dump "*) no "first run: unowned source skill is not in the manifest" "found: $names" ;;
  *) ok "first run: unowned source skill (ai-brain-dump) is not in the manifest" ;;
esac

ok "first run: manifest from owned source ∪ disk, all installed:true, ISO-8601 UTC stamp"

# No controlling terminal (CI, cron): /dev/tty is still world-readable there but cannot be opened, so
# a mode check alone lets the decision prompt through and `set -e` kills the run. setsid() in the
# child drops the harness's own terminal, which a developer machine has and the gate does not.
root="$(make_root "no-tty" alpha)"
if SKILLS_ROOT="$root/skills" SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
  SKILLS_TEST_OWNED_EXTRA="alpha" \
  python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
  bash "$installer_sh" >"$scratch/out" 2>"$scratch/err" </dev/null \
  && [ "$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['decisions_enabled'])" "$root/_smooth-devex-shared/installation.json")" = "False" ]; then
  ok "no controlling terminal: install succeeds and decisions default to disabled"
else
  no "no controlling terminal: install succeeds and decisions default to disabled" "$(tail -n 3 "$scratch/err")"
fi

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
rm -rf "$root/skills/gamma"
mkdir -p "$root/skills/delta"; printf '# delta\n' >"$root/skills/delta/SKILL.md"

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
# The manifest is written last, after the shared-payload refresh, so the refresh can never
# clobber the flags the update just read. If the manifest is missing at the end of a run,
# the write ordering regressed.

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
root="$scratch/emptyinstall/.codex"
mkdir -p "$root/skills"
run_sh "$root" >/dev/null 2>&1 || true
on_disk="$(find "$root/skills" -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
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
  if [ -d "$root/skills/$denied" ]; then
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
  if [ ! -d "$root/skills/$denied" ]; then
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
printf 'operator edit\n' >"$root/skills/ai-terse/SKILL.md"
run_sh "$root" >/dev/null 2>&1

if grep -q '^name:' "$root/skills/ai-terse/SKILL.md" 2>/dev/null; then
  ok "an installed:true skill is replaced from the clone source"
else
  no "an installed:true skill is replaced from the clone source" "SKILL.md still: $(head -1 "$root/skills/ai-terse/SKILL.md")"
fi
if [ -d "$root/skills/create-hld/scripts" ]; then
  ok "the copied skill carries its scripts folder"
else
  no "the copied skill carries its scripts folder"
fi

# Now the same run with one skill switched off: the off folder must be left exactly as it is.
# The manifest has to exist before it can be switched off, so this is a first run followed by an
# edit: that is the operator's actual sequence (install, then turn a skill off).
root2="$(make_root "update-off" ai-terse create-hld)"
printf 'operator edit\n' >"$root2/skills/ai-terse/SKILL.md"
run_sh "$root2" >/dev/null 2>&1
printf 'operator edit\n' >"$root2/skills/ai-terse/SKILL.md"
python3 - "$root2/_smooth-devex-shared/installation.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for entry in data["skills"]:
    entry["installed"] = False
json.dump(data, open(path, "w"), indent=2)
PYEOF
run_sh "$root2" >/dev/null 2>&1
if [ "$(cat "$root2/skills/ai-terse/SKILL.md")" = "operator edit" ]; then
  ok "an installed:false skill is never overwritten"
else
  no "an installed:false skill is never overwritten" "content is now: $(head -1 "$root2/skills/ai-terse/SKILL.md")"
fi

# 4b. An unowned skill present on disk (and in source) is left byte-identical and never enters the
# manifest. This is the bug the unscoped installer had - it pulled a foreign repo's local-only
# skills into its manifest and marked them installed:true. The owned-set gate stops that here.
#
# ai-brain-dump is in source but NOT in OWNED_LIST, so it is the unowned probe for this
# case. We plant it on disk with operator-local content (a non-source SKILL.md), run, and assert
# the disk content is unchanged AND the manifest has no such name.
root="$(make_root "update-unowned" ai-brain-dump)"
printf 'operator-local content\n' >"$root/skills/ai-brain-dump/SKILL.md"
run_sh "$root" >/dev/null 2>&1
if [ "$(cat "$root/skills/ai-brain-dump/SKILL.md")" = "operator-local content" ]; then
  ok "an unowned source skill left on disk is left byte-identical (not copied over)"
else
  no "an unowned source skill left on disk is left byte-identical" "now: $(cat "$root/skills/ai-brain-dump/SKILL.md")"
fi
case " $(manifest_names "$root") " in
  *" ai-brain-dump "*) no "an unowned source skill on disk is not listed in the manifest" "found in manifest" ;;
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
data["skills"].append({"name": "ai-brain-dump", "installed": True})
json.dump(data, open(path, "w"), indent=2)
PYEOF
run_sh "$root" >/dev/null 2>&1
if [ ! -d "$root/skills/ai-brain-dump" ]; then
  ok "reconcile: a hand-edited manifest's unowned entry is dropped, not copied"
else
  no "reconcile: a hand-edited manifest's unowned entry is dropped, not copied" "ai-brain-dump/ landed"
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
mkdir -p "$root/skills/ai-brain-dump"
printf 'operator-local content\n' >"$root/skills/ai-brain-dump/SKILL.md"
run_sh "$root" >/dev/null 2>&1
python3 - "$root/_smooth-devex-shared/installation.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["skills"].append({"name": "ai-brain-dump", "installed": True})
json.dump(data, open(path, "w"), indent=2)
PYEOF
# Set up the synthetic source with DIFFERENT content for the unowned skill.
INSTALL_TMP="$(mktemp -d)"
mkdir -p "$INSTALL_TMP/repo/.agents/skills"
mkdir -p "$INSTALL_TMP/repo/.agents/skills/ai-brain-dump"
printf 'upstream-source content\n' >"$INSTALL_TMP/repo/.agents/skills/ai-brain-dump/SKILL.md"
SKILLS_ROOT="$root/skills" SKILLS_TEST_OWNED_EXTRA="alpha beta gamma delta epsilon" \
  SKILLS_TEST_SKIP_RECONCILE=1 INSTALL_TMP="$INSTALL_TMP" \
  bash "$installer_sh" >/dev/null 2>&1 || true
rm -rf "$INSTALL_TMP"
if [ "$(cat "$root/skills/ai-brain-dump/SKILL.md")" = "operator-local content" ]; then
  ok "update-guard: a hand-edited unowned entry is refused by the updater loop (operator content preserved)"
else
  no "update-guard: a hand-edited unowned entry is refused by the updater loop" \
    "SKILL.md content is now: $(cat "$root/skills/ai-brain-dump/SKILL.md")"
fi

# ---------------------------------------------------------------------------------------------
# 5. a corrupt manifest is an error, not a first install
# ---------------------------------------------------------------------------------------------

root="$(make_root "corrupt" alpha)"
mkdir -p "$root/_smooth-devex-shared"
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
mkdir -p "$root/_smooth-devex-shared"
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
SKILLS_ROOT="$root/skills" SKILLS_REPO="git@github.com:nonexistent-fake-host-9876543210/repo.git" SKILLS_BRANCH="main" \
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

# 5f. The shared payload refreshes from the source on every run. The source tree ships
# .agents/_smooth-devex-shared/ (setup/scripts, templates), so this is a real copy, not a no-op.
root="$(make_root "shared" alpha)"
run_sh "$root" >/dev/null 2>&1
if [ -f "$root/_smooth-devex-shared/setup/scripts/agents-setup.sh" ] \
  && [ -f "$root/_smooth-devex-shared/setup/scripts/agents-setup.ps1" ] \
  && [ -f "$root/_smooth-devex-shared/templates/TEMPLATE_AGENTS.md" ] \
  && [ -f "$root/_smooth-devex-shared/templates/AI_WORKTASK_PROMOTE_STANDALONE_TEMPLATE.md" ]; then
  ok "shared payload: source setup/scripts and templates land in <agent>/_smooth-devex-shared"
else
  no "shared payload: source setup/scripts and templates land in <agent>/_smooth-devex-shared" \
    "contents: $(ls "$root/_smooth-devex-shared" 2>/dev/null)"
fi

# 5g. Canonical links: the payload is linked back to <agent-root> paths so the
# .agents/setup/... and .agents/templates/... references keep working.
if [ -f "$root/setup/scripts/agents-setup.sh" ] && [ -L "$root/setup" ] \
  && [ -f "$root/templates/TEMPLATE_AGENTS.md" ] && [ -L "$root/templates" ]; then
  ok "canonical links: <agent>/setup and <agent>/templates resolve into _smooth-devex-shared"
else
  no "canonical links: <agent>/setup and <agent>/templates resolve into _smooth-devex-shared" "setup or templates missing or not a link"
fi

# 5h. Stale shared entries are swept: a file the source dropped does not survive.
mkdir -p "$root/_smooth-devex-shared/setup/scripts"
printf '# retired\n' >"$root/_smooth-devex-shared/setup/scripts/stale-retired.sh"
run_sh "$root" >/dev/null 2>&1
if [ ! -e "$root/_smooth-devex-shared/setup/scripts/stale-retired.sh" ] \
  && [ -f "$root/_smooth-devex-shared/setup/scripts/agents-setup.sh" ]; then
  ok "shared payload: stale entries are swept, live entries kept"
else
  no "shared payload: stale entries are swept, live entries kept" "stale survived or live lost"
fi

# 5i. A legacy manifest inside the skills root is ignored (fresh start), not migrated.
root="$(make_root "legacy" alpha)"
mkdir -p "$root/skills/_smooth-devex-shared"
printf '{"updated": "2020-01-01T00:00:00Z", "skills": [{"name": "alpha", "installed": false}]}' \
  >"$root/skills/_smooth-devex-shared/installation.json"
run_sh "$root" >/dev/null 2>&1
if [ "$(manifest_flag "$root" alpha)" = "true" ] \
  && [ "$(cat "$root/skills/_smooth-devex-shared/installation.json")" = '{"updated": "2020-01-01T00:00:00Z", "skills": [{"name": "alpha", "installed": false}]}' ]; then
  ok "legacy manifest inside skills root is ignored (fresh defaults, legacy untouched)"
else
  no "legacy manifest inside skills root is ignored" "alpha=$(manifest_flag "$root" alpha)"
fi

# 5j. An existing real directory at a canonical link path is never replaced.
root="$(make_root "reallink" alpha)"
mkdir -p "$root/setup"
printf 'operator-owned\n' >"$root/setup/keep.txt"
run_sh "$root" >/dev/null 2>&1
if [ ! -L "$root/setup" ] && [ "$(cat "$root/setup/keep.txt")" = "operator-owned" ] \
  && [ -f "$root/_smooth-devex-shared/setup/scripts/agents-setup.sh" ]; then
  ok "canonical link: an existing real directory is left in place"
else
  no "canonical link: an existing real directory is left in place" "real dir replaced or payload missing"
fi

# ---------------------------------------------------------------------------------------------
# 6. the root search, in the documented order
# ---------------------------------------------------------------------------------------------

# Run the installer in $1 (a scratch directory), with SKILLS_ROOT deliberately unset so the search runs.
# Echoes the exit status instead of failing the harness, so a case can assert on it.
run_in_dir_searched() {
  local dir="$1"
  # SKILLS_ROOT="" so a leaked operator env var cannot force a fixed root and
  # silently short-circuit the agent-root search this helper exists to test.
  ( cd "$dir" && SKILLS_ROOT="" SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" bash "$installer_sh" ) >/dev/null 2>&1
}

# A tree with .claude/skills and .codex/skills but no .agents: the search must land on
# .claude, in the documented order, and must not create anything.
base="$scratch/search"
mkdir -p "$base/.claude/skills" "$base/.codex/skills"
if ! run_in_dir_searched "$base"; then
  no "root search: the run succeeds" "see the run above"
elif [ -f "$base/.claude/_smooth-devex-shared/installation.json" ] && [ ! -e "$base/.codex/_smooth-devex-shared" ]; then
  ok "root search: .claude wins over .codex"
else
  no "root search: .claude wins over .codex" "the manifest landed in the wrong root"
fi
if [ -e "$base/.agents" ]; then
  no "root search: creates no agent directory" "it created .agents"
else
  ok "root search: creates no agent directory"
fi

# A found agent root is the opt-in; missing category directories are created as needed.
noskills="$scratch/noskills"
mkdir -p "$noskills/.agents"
if ! run_in_dir_searched "$noskills"; then
  no "agent without skills installs into created category directories" "run failed"
elif [ -f "$noskills/.agents/skills/ai-terse/SKILL.md" ] \
  && [ -d "$noskills/.agents/hooks" ] && [ -d "$noskills/.agents/rules" ]; then
  ok "agent without skills installs into created category directories"
else
  no "agent without skills installs into created category directories" "a category is missing"
fi

# A tree with no agent directory at all: a hard error, and still nothing created.
empty="$scratch/empty"
mkdir -p "$empty"
if run_in_dir_searched "$empty"; then
  no "no agent directory exits non-zero" "expected failure, got success"
else
  ok "no agent directory exits non-zero"
fi
if [ ! -d "$empty/.agents" ] && [ ! -d "$empty/.claude" ] && [ ! -d "$empty/.codex" ]; then
  ok "no agent directory: creates nothing"
else
  no "no agent directory: creates nothing" "it created an agent directory"
fi

# ---------------------------------------------------------------------------------------------
# 7. category switches (-r rules, -s skills, -h hooks; none = everything)
# ---------------------------------------------------------------------------------------------
# Rules and hooks payloads live in committed source files (.github/instructions, .agents/hooks),
# so these cases are green even before the layout commit — unlike the shared-payload cases above.

# 7a. -s only: skills install, rules and hooks untouched, manifest written.
root="$(make_root "cat-skills" alpha)"
run_sh "$root" -s >/dev/null 2>&1
if [ -f "$root/_smooth-devex-shared/installation.json" ] \
  && [ ! -e "$root/rules" ] && [ ! -e "$root/hooks" ]; then
  ok "-s only: skills install, no rules, no hooks"
else
  no "-s only: skills install, no rules, no hooks" "rules or hooks leaked in"
fi

# 7b. -r only: every owned rule lands in the agent root, with no topology symlink, no
# skills, no manifest.
root="$(make_root "cat-rules" alpha)"
run_sh "$root" -r >/dev/null 2>&1
rules_ok=1
for rel in code-review-standards.instructions.md ai-workflow-rules.instructions.md \
  clean-code.instructions.md backend/architecture-slices.instructions.md \
  git/git-policy.instructions.md meta/rules.instructions.md \
  skills/skill-secret-handling.instructions.md; do
  [ -f "$root/rules/$rel" ] || rules_ok=0
done
# The template's own index is never copied: a generated index of the shipped set ships instead,
# referencing the owned rules.
if [ -f "$root/rules/AGENTS.md" ] \
  && grep -q "installed subset" "$root/rules/AGENTS.md" \
  && grep -q "backend/architecture-slices" "$root/rules/AGENTS.md"; then
  :
else
  rules_ok=0
fi
if [ "$rules_ok" = "1" ] && [ ! -L "$root/rules" ] && [ ! -e "$root/../.github" ] \
  && [ ! -e "$root/skills/ai-terse" ] && [ ! -f "$root/_smooth-devex-shared/installation.json" ]; then
  ok "-r only: owned rules land in agent rules directory, no skills, no manifest"
else
  no "-r only: owned rules land in agent rules directory, no skills, no manifest" "rules_ok=$rules_ok"
fi

# 7c. The two owned hooks land executable; unowned and operator files are untouched.
# load-agents-context.sh is deliberately NOT owned (dead without its unowned implementation).
root="$(make_root "cat-hooks" alpha)"
mkdir -p "$root/hooks"
printf '#!/bin/sh\n' >"$root/hooks/operator.sh"
chmod 644 "$root/hooks/operator.sh"
run_sh "$root" -h >/dev/null 2>&1
if [ -f "$root/hooks/worktask-skill-trigger.sh" ] \
  && [ -f "$root/hooks/manage-rule-system-context.sh" ] \
  && [ -x "$root/hooks/worktask-skill-trigger.sh" ] \
  && [ ! -e "$root/hooks/load-agents-context.sh" ] \
  && [ ! -e "$root/hooks/slnx-docs-sync.py" ] \
  && [ ! -x "$root/hooks/operator.sh" ] \
  && [ ! -e "$root/skills/ai-terse" ] \
  && [ ! -f "$root/_smooth-devex-shared/installation.json" ]; then
  ok "-h only: owned hooks land executable, unowned and operator files untouched, no skills, no manifest"
else
  no "-h only: owned hooks land executable, unowned and operator files untouched, no skills, no manifest" "wrong hook set or operator file touched"
fi

# 7d. -r -h combined: rules and hooks, still no skills and no manifest.
root="$(make_root "cat-rules-hooks" alpha)"
run_sh "$root" -r -h >/dev/null 2>&1
if [ -f "$root/rules/git/git-policy.instructions.md" ] \
  && [ -f "$root/hooks/worktask-skill-trigger.sh" ] \
  && [ ! -e "$root/skills/ai-terse" ] \
  && [ ! -f "$root/_smooth-devex-shared/installation.json" ]; then
  ok "-r -h: rules and hooks install, skills skipped"
else
  no "-r -h: rules and hooks install, skills skipped" "wrong category set"
fi

# 7e. All template rules are owned, so each lands; an operator's own rule file survives
# (overwrite, never delete, no sweep).
root="$(make_root "cat-owned" alpha)"
run_sh "$root" -r >/dev/null 2>&1
mkdir -p "$root/rules/backend"
printf 'operator rule\n' >"$root/rules/backend/operator.instructions.md"
run_sh "$root" -r >/dev/null 2>&1
if [ -e "$root/rules/backend/api-mediator-validation.instructions.md" ] \
  && [ "$(cat "$root/rules/backend/operator.instructions.md")" = "operator rule" ]; then
  ok "-r: owned rules land, operator rules never swept"
else
  no "-r: owned rules land, operator rules never swept" "owned missing or operator lost"
fi

# 7f. An existing real rules directory receives owned files without replacing operator content.
root="$(make_root "cat-realrules" alpha)"
mkdir -p "$root/rules"
printf 'operator index\n' >"$root/rules/AGENTS.md"
run_sh "$root" -r >/dev/null 2>&1 || true
if [ ! -L "$root/rules" ] && [ -f "$root/rules/git/git-policy.instructions.md" ] \
  && grep -q "operator index" "$root/rules/AGENTS.md"; then
  ok "-r: an existing real rules entry is never replaced"
else
  no "-r: an existing real rules entry is never replaced" "real dir replaced by link"
fi

# 7j. An existing consumer rules index is merged, not clobbered: the installed subset is
# appended once, operator content survives, and a second run does not duplicate the section.
root="$(make_root "cat-indexmerge" alpha)"
mkdir -p "$root/rules"
printf '# AGENTS.md - Operator rules\n' >"$root/rules/AGENTS.md"
run_sh "$root" -r >/dev/null 2>&1
run_sh "$root" -r >/dev/null 2>&1
if [ "$(grep -c "installer-owned-rules-subset" "$root/rules/AGENTS.md")" = "1" ] \
  && grep -q "Operator rules" "$root/rules/AGENTS.md" \
  && grep -q "code-review-standards" "$root/rules/AGENTS.md"; then
  ok "-r: existing consumer index is appended once, never rewritten"
else
  no "-r: existing consumer index is appended once, never rewritten" "clobbered or duplicated"
fi
# 7g. An unknown switch is a hard error.
root="$(make_root "cat-badflag" alpha)"
st=0
run_sh "$root" -x >/dev/null 2>&1 || st=$?
if [ "$st" -ne 0 ]; then
  ok "unknown switch exits non-zero"
else
  no "unknown switch exits non-zero" "expected failure, got success"
fi

# 7h. Inside a git work tree the run marks symlinks supported (consumer-side recording);
# outside one (every other case in this harness) the step is silently skipped.
root="$(make_root "cat-symlinkcfg" alpha)"
git -C "$(dirname "$root")" init -q 2>/dev/null
run_sh "$root" >/dev/null 2>&1
if [ "$(git -C "$root" config core.symlinks 2>/dev/null)" = "true" ]; then
  ok "consumer repo gets core.symlinks=true"
else
  no "consumer repo gets core.symlinks=true" "config missing or false"
fi

# 7i. A relative SKILLS_ROOT resolves against the cwd: state lands beside skills, not inside
# them, and rules land in the agent root — never nested under the skills dir.
relroot="$scratch/relroot"
mkdir -p "$relroot/.agents/skills/alpha"
printf '# alpha\n' >"$relroot/.agents/skills/alpha/SKILL.md"
( cd "$relroot" && SKILLS_ROOT=.agents/skills SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
  SKILLS_TEST_OWNED_EXTRA="alpha" bash "$installer_sh" -s -r ) >/dev/null 2>&1
if [ -f "$relroot/.agents/_smooth-devex-shared/installation.json" ] \
  && [ ! -e "$relroot/.agents/skills/_smooth-devex-shared" ] \
  && [ -f "$relroot/.agents/rules/git/git-policy.instructions.md" ]; then
  ok "relative SKILLS_ROOT resolves against the cwd"
else
  no "relative SKILLS_ROOT resolves against the cwd" "state or rules nested inside skills/"
fi

# ---------------------------------------------------------------------------------------------
# 8. global install (-g): ~/.smooth-ai-devex store wired into Codex
# ---------------------------------------------------------------------------------------------
# Each case runs against an isolated temp HOME (so ~/.smooth-ai-devex and
# ~/.codex both resolve inside it) with CODEX_HOME pinned to the same path. No
# SKILLS_ROOT is passed — -g explicitly refuses it. The clone source is the
# checkout itself, so no network.

# run_sh_global GHOME ARGS... — run the installer in global mode (always -g).
run_sh_global() {
  local ghome="$1"; shift
  # Pin the store/config overrides to the temp home and clear inherited SKILLS_ROOT,
  # so an operator's SMOOTH_DEVEX_HOME / OPENCODE_CONFIG / SKILLS_ROOT env vars cannot
  # leak into an isolated run (and a leaked SKILLS_ROOT would trip -g's refusal).
  HOME="$ghome" CODEX_HOME="$ghome/.codex" SMOOTH_DEVEX_HOME="$ghome/.smooth-ai-devex" \
    OPENCODE_CONFIG="$ghome/.config/opencode" SKILLS_ROOT="" \
    SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
    SKILLS_TEST_OWNED_EXTRA="alpha beta gamma delta epsilon" \
    bash "$installer_sh" -g "$@" >"$scratch/out" 2>"$scratch/err"
}

# A fresh temp HOME with the real-ish Codex shape: a .system/ dir under
# .codex/skills (which the installer must never touch), plus zero or more real
# skill directories occupying the link path so the foreign-skip case has
# something to protect.
make_ghome() {
  local ghome="$scratch/global-$1"
  shift
  mkdir -p "$ghome/.codex/skills/.system"
  printf '# Codex system\n' >"$ghome/.codex/skills/.system/cfg.md"
  local name
  for name in "$@"; do
    mkdir -p "$ghome/.codex/skills/$name"
    printf 'operator %s\n' "$name" >"$ghome/.codex/skills/$name/keep.txt"
  done
  printf '%s\n' "$ghome"
}

glb_root() { printf '%s\n' "$1/.smooth-ai-devex"; }
global_manifest() { printf '%s\n' "$(glb_root "$1")/installation.json"; }

# 8a. First global install builds the store, wires skills/rules/hooks into
# Codex, and records the manifest — without touching .system/.
ghome="$(make_ghome "first")"
run_sh_global "$ghome" >/dev/null 2>&1
groot="$(glb_root "$ghome")"
gok=1
for d in skills rules hooks; do [ -d "$groot/$d" ] || gok=0; done
for s in $bash_owned; do
  [ -e "$groot/skills/$s" ] || gok=0
  [ -L "$ghome/.codex/skills/$s" ] || gok=0
  [ "$(readlink "$ghome/.codex/skills/$s")" = "$groot/skills/$s" ] || gok=0
done
[ -f "$ghome/.codex/skills/.system/cfg.md" ] || gok=0
[ -L "$ghome/.codex/skills/.system" ] && gok=0
for r in code-review-standards.instructions.md git/git-policy.instructions.md \
  meta/knowledge-conventional-contexts-quality.instructions.md meta/rules.instructions.md; do
  [ -f "$groot/rules/$r" ] || gok=0
done
grep -q "$groot/rules/code-review-standards.instructions.md" "$groot/AGENTS.md" || gok=0
grep -q 'installer-owned-global-instructions' "$ghome/.codex/AGENTS.md" || gok=0
# Codex does not resolve @-imports, so its AGENTS.md carries the index itself, never an @ line.
grep -q "$groot/rules/code-review-standards.instructions.md" "$ghome/.codex/AGENTS.md" || gok=0
grep -q "^@$groot" "$ghome/.codex/AGENTS.md" "$groot/AGENTS.md" && gok=0
grep -q "$groot/hooks/manage-rule-system-context.sh" "$ghome/.codex/hooks.json" || gok=0
grep -q "$groot/hooks/worktask-skill-trigger.sh" "$ghome/.codex/hooks.json" || gok=0
[ -f "$(global_manifest "$ghome")" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global first install: store, skills, rules, hooks, AGENTS import, manifest (.system untouched)"
else
  no "global first install: store, skills, rules, hooks, AGENTS import, manifest" "$(tail -n 5 "$scratch/err")"
fi

# 8j. Skill AGENTS.md owner-context files are not copied over; SKILL.md and the
# runnable payload are.
ghome="$(make_ghome "no-agents-md")"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
for s in ai-ralph-loop create-worktask manage-rule-system ai-terse; do
  [ -e "$(glb_root "$ghome")/skills/$s/AGENTS.md" ] && gok=0
  [ -e "$(glb_root "$ghome")/skills/$s/SKILL.md" ] || gok=0
done
if [ "$gok" = "1" ]; then
  ok "global skill copy strips AGENTS.md, keeps SKILL.md and payload"
else
  no "global skill copy strips AGENTS.md, keeps SKILL.md and payload" "$(find "$(glb_root "$ghome")/skills" -name 'AGENTS.md' 2>/dev/null)"
fi

# 8k. OpenCode wiring: owned skills are symlinked into OpenCode's own skills dir
# (~/.config/opencode/skills/<name>), so OpenCode loads the full skill (SKILL.md +
# scripts) via the native skill tool. Removed on uninstall.
ghome="$(make_ghome "opencode")"
mkdir -p "$ghome/.config/opencode"
OPENCODE_CONFIG="$ghome/.config/opencode" run_sh_global "$ghome" >/dev/null 2>&1
gok=1
for s in ai-ralph-loop ai-terse create-worktask; do
  [ -L "$ghome/.config/opencode/skills/$s" ] || gok=0
  [ "$(readlink "$ghome/.config/opencode/skills/$s")" = "$(glb_root "$ghome")/skills/$s" ] || gok=0
done
if [ "$gok" = "1" ]; then
  ok "global OpenCode wiring: skills symlinked into OpenCode's skills dir"
else
  no "global OpenCode wiring: skills symlinked into OpenCode's skills dir" "$(find "$ghome/.config/opencode" -maxdepth 2 2>/dev/null | sed "s|$ghome|HOME|")"
fi
OPENCODE_CONFIG="$ghome/.config/opencode" run_sh_global "$ghome" --uninstall >/dev/null 2>&1
if [ "$(ls "$ghome/.config/opencode/skills" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then
  ok "global OpenCode skills removed on uninstall"
else
  no "global OpenCode skills removed on uninstall" "$(ls "$ghome/.config/opencode/skills" 2>/dev/null)"
fi

# 8q. OpenCode opencode.json gets one instructions entry per installed store rule
# (a per-file path, not a glob, so a single rule can be switched off) after a backup,
# so OpenCode loads the global rules; restored on uninstall.
ghome="$(make_ghome "opencode-instr")"
mkdir -p "$ghome/.config/opencode"
printf '{"$schema":"https://opencode.ai/config.json","provider":{"name":"x"}}\n' >"$ghome/.config/opencode/opencode.json"
OPENCODE_CONFIG="$ghome/.config/opencode" run_sh_global "$ghome" >/dev/null 2>&1
gok=1
python3 -c "import json,sys; d=json.load(open('$ghome/.config/opencode/opencode.json')); i=d.get('instructions',[]); r='$(glb_root "$ghome")/rules/'; sys.exit(0 if r+'code-review-standards.instructions.md' in i and r+'backend/architecture-slices.instructions.md' in i and not any('*' in g for g in i) else 1)" || gok=0
ls "$ghome"/.config/opencode/opencode.json.smooth-devex-* >/dev/null 2>&1 || gok=0
OPENCODE_CONFIG="$ghome/.config/opencode" run_sh_global "$ghome" --uninstall >/dev/null 2>&1
python3 -c "import json,sys; d=json.load(open('$ghome/.config/opencode/opencode.json')); sys.exit(0 if not any('$(glb_root "$ghome")/rules/' in g for g in d.get('instructions',[])) else 1)" || gok=0
if [ "$gok" = "1" ]; then
  ok "global OpenCode opencode.json: store-rule instructions added with a backup, restored on uninstall"
else
  no "global OpenCode opencode.json: store-rule instructions added with a backup, restored on uninstall" "$(cat "$ghome/.config/opencode/opencode.json" 2>/dev/null)"
fi

# 8l. -g -d tracks the shell-profile edit and restores it on uninstall (backup first).
# write_decisions_env writes to .zshrc on macOS and .bashrc on Linux — mirror that
# so the case is platform-agnostic (the PR-gate runner is Ubuntu).
ghome="$(make_ghome "profiledit")"
mkdir -p "$ghome/.config/opencode"
case "$(uname -s)" in
  Darwin) profile="$ghome/.zshrc" ;;
  *)      profile="$ghome/.bashrc" ;;
esac
printf '# operator shell\nexport MY_CHECK=1\n' >"$profile"
HOME="$ghome" CODEX_HOME="$ghome/.codex" SMOOTH_DEVEX_HOME="$ghome/.smooth-ai-devex" \
  OPENCODE_CONFIG="$ghome/.config/opencode" SKILLS_ROOT="" SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
  SKILLS_TEST_OWNED_EXTRA="alpha beta gamma delta epsilon" bash "$installer_sh" -g -d >/dev/null 2>&1
gok=1
grep -q 'SMOOTH_DEVEX_DECISIONS' "$profile" || gok=0
ls "$profile".smooth-devex-* >/dev/null 2>&1 || gok=0
HOME="$ghome" CODEX_HOME="$ghome/.codex" SMOOTH_DEVEX_HOME="$ghome/.smooth-ai-devex" \
  OPENCODE_CONFIG="$ghome/.config/opencode" SKILLS_ROOT="" SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
  bash "$installer_sh" -g --uninstall >/dev/null 2>&1
grep -q 'SMOOTH_DEVEX_DECISIONS' "$profile" && gok=0
grep -q 'MY_CHECK=1' "$profile" || gok=0
if [ "$gok" = "1" ]; then
  ok "global -g -d tracks + restores the shell profile on uninstall"
else
  no "global -g -d tracks + restores the shell profile on uninstall" "$(cat "$profile" 2>/dev/null)"
fi

# 8b. A re-run converges: no duplicated hook group, no doubled marker, and the
# links history is preserved (not wiped by the assumption that nothing changed).
links_after_first="$(python3 -c "import json;print(len(json.load(open('$(global_manifest "$ghome")'))['links']))")"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ "$(grep -c 'installer-owned-global-instructions' "$ghome/.codex/AGENTS.md")" = "1" ] || gok=0
ups_groups="$(python3 -c "import json;print(len(json.load(open('$ghome/.codex/hooks.json'))['hooks']['UserPromptSubmit']))")"
[ "$ups_groups" = "1" ] || gok=0
[ "$(python3 -c "import json;print(len(json.load(open('$(global_manifest "$ghome")'))['links']))")" = "$links_after_first" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global re-run converges (no dupes, links preserved)"
else
  no "global re-run converges (no dupes, links preserved)" "groups=$ups_groups links=$links_after_first"
fi

# 8c. A foreign real directory at a Codex skills link path is never replaced;
# the free sibling gets linked. .system/ is again left alone.
ghome="$(make_ghome "foreign")"
mkdir -p "$ghome/.codex/skills/ai-terse"
printf 'operator ai-terse\n' >"$ghome/.codex/skills/ai-terse/keep.txt"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ -d "$ghome/.codex/skills/ai-terse" ] && [ ! -L "$ghome/.codex/skills/ai-terse" ] || gok=0
[ "$(cat "$ghome/.codex/skills/ai-terse/keep.txt")" = "operator ai-terse" ] || gok=0
[ -L "$ghome/.codex/skills/create-hld" ] || gok=0
grep -q 'already exists — left untouched' "$scratch/err" || gok=0
if [ "$gok" = "1" ]; then
  ok "global foreign link: real skill dir kept, link skipped, free sibling linked"
else
  no "global foreign link: real skill dir kept, link skipped, free sibling linked" "$(grep 'already exists' "$scratch/err" | head -1)"
fi

# 8d. .system/ and .DS_Store are never iterated or replaced.
ghome="$(make_ghome "system")"
run_sh_global "$ghome" >/dev/null 2>&1
if [ -d "$ghome/.codex/skills/.system" ] && [ ! -L "$ghome/.codex/skills/.system" ] \
  && [ -f "$ghome/.codex/skills/.system/cfg.md" ]; then
  ok "global .system/ is never touched"
else
  no "global .system/ is never touched" "$(ls -la "$ghome/.codex/skills" 2>/dev/null)"
fi

# 8e. A corrupt global manifest is a hard error, never a silent reset.
ghome="$(make_ghome "corrupt")"
mkdir -p "$(glb_root "$ghome")"
printf '{ not json' >"$(global_manifest "$ghome")"
st=0
run_sh_global "$ghome" >/dev/null 2>&1 || st=$?
if [ "$st" -ne 0 ] && [ "$(cat "$(global_manifest "$ghome")")" = "{ not json" ]; then
  ok "global corrupt manifest is refused, non-zero exit, left untouched"
else
  no "global corrupt manifest is refused, non-zero exit, left untouched" "st=$st content=$(cat "$(global_manifest "$ghome")")"
fi

# 8f. -g refuses SKILLS_ROOT (the global store owns the agent root, not a per-repo one).
ghome="$(make_ghome "refuse-skillsroot")"
st=0
HOME="$ghome" CODEX_HOME="$ghome/.codex" SKILLS_ROOT="$ghome/.codex/skills" \
  SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
  bash "$installer_sh" -g >/dev/null 2>&1 || st=$?
if [ "$st" -ne 0 ]; then
  ok "global -g refuses being combined with SKILLS_ROOT"
else
  no "global -g refuses being combined with SKILLS_ROOT" "expected failure, got success"
fi

# 8g. --uninstall is meaningless without -g, and is refused.
ghome="$(make_ghome "refuse-uninstall")"
st=0
HOME="$ghome" CODEX_HOME="$ghome/.codex" SKILLS_REPO="$source_repo" SKILLS_BRANCH="$source_branch" \
  bash "$installer_sh" --uninstall >/dev/null 2>&1 || st=$?
if [ "$st" -ne 0 ]; then
  ok "--uninstall without -g is refused"
else
  no "--uninstall without -g is refused" "expected failure, got success"
fi

# 8h. Uninstall removes exactly what the install recorded: the Codex skill links,
# the marker-guarded AGENTS import, and the hooked chunks — restoring the
# pre-install operator content byte-for-byte and retiring the snapshots that
# enabled the restore (so a later install snapshots fresh). .system/ and the store
# directory are left alone.
ghome="$(make_ghome "uninstall")"
printf '@%s/.codex/RTK.md\n\noperator line 1\noperator line 2\n' "$ghome" >"$ghome/.codex/AGENTS.md"
printf '# RTK\n' >"$ghome/.codex/RTK.md"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"gk ai hook run --host codex","type":"command"}],"matcher":""}]}}\n' >"$ghome/.codex/hooks.json"
# Capture the operator's original content; the snapshots are retired on uninstall,
# so compare against these rather than the (now-deleted) backup files.
cp "$ghome/.codex/AGENTS.md" "$scratch/orig-8h-agents.md"
cp "$ghome/.codex/hooks.json" "$scratch/orig-8h-hooks.json"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
backup_agents="$(ls "$ghome"/.codex/AGENTS.md.smooth-devex-* 2>/dev/null | head -n 1)"
backup_hooks="$(ls "$ghome"/.codex/hooks.json.smooth-devex-* 2>/dev/null | head -n 1)"
[ -n "$backup_agents" ] || gok=0
[ -n "$backup_hooks" ] || gok=0
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
for s in ai-asset-sync ai-terse create-hld; do [ -e "$ghome/.codex/skills/$s" ] && gok=0; done
[ -d "$(glb_root "$ghome")/skills" ] || gok=0
grep -q 'installer-owned-global-instructions' "$ghome/.codex/AGENTS.md" && gok=0
grep -q "$(glb_root "$ghome")/rules/" "$ghome/.codex/AGENTS.md" && gok=0
# AGENTS.md is restored to the operator's earlier content, byte-for-byte.
cmp -s "$scratch/orig-8h-agents.md" "$ghome/.codex/AGENTS.md" || gok=0
grep -q 'gk ai hook run --host codex' "$ghome/.codex/hooks.json" || gok=0
grep -q "$(glb_root "$ghome")/hooks/" "$ghome/.codex/hooks.json" && gok=0
# The snapshots used for restore are retired (a later install snapshots fresh).
[ -e "$backup_agents" ] && gok=0
[ -e "$backup_hooks" ] && gok=0
[ -f "$ghome/.codex/skills/.system/cfg.md" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global uninstall restores operator content byte-for-byte, retires snapshots, keeps RTK + .system"
else
  no "global uninstall restores operator content byte-for-byte, retires snapshots, keeps RTK + .system" "$(tail -n 6 "$scratch/err")"
fi

# 8m. install → uninstall → reinstall → uninstall never loses an operator's
# pre-existing AGENTS.md. The first uninstall restores it and retires the
# snapshot; the reinstall snapshots the operator's current content fresh and
# records the new snapshot, so the second uninstall still restores (never deletes
# as installer-created).
ghome="$(make_ghome "cycle")"
printf '@%s/.codex/RTK.md\n\noperator line 1\noperator line 2\n' "$ghome" >"$ghome/.codex/AGENTS.md"
printf '# RTK\n' >"$ghome/.codex/RTK.md"
run_sh_global "$ghome" >/dev/null 2>&1
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
run_sh_global "$ghome" >/dev/null 2>&1
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
expected="$(printf '@%s/.codex/RTK.md\n\noperator line 1\noperator line 2\n' "$ghome")"
actual="$(cat "$ghome/.codex/AGENTS.md")"
if [ "$actual" = "$expected" ] && [ -f "$ghome/.codex/AGENTS.md" ]; then
  ok "global install/uninstall cycle preserves an operator's pre-existing AGENTS.md"
else
  no "global install/uninstall cycle preserves an operator's pre-existing AGENTS.md" "after 2nd uninstall: $(cat "$ghome/.codex/AGENTS.md" 2>/dev/null)"
fi

# 8n. A global manifest entry set to installed:false is not refreshed in the store
# (operator local edits preserved, honoring the update opt-out), and remains
# discoverable — the flag only stops updates, it does not remove the skill.
ghome="$(make_ghome "disabled-skill")"
run_sh_global "$ghome" >/dev/null 2>&1
printf 'local edit\n' >"$(glb_root "$ghome")/skills/ai-terse/SKILL.md"   # operator-local edit in the store
python3 - "$(global_manifest "$ghome")" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for s in d['skills']:
    if s['name'] == 'ai-terse':
        s['installed'] = False
json.dump(d, open(p, 'w'), indent=2)
PYEOF
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
# The installed:false skill keeps its local edit in the store (not overwritten).
[ "$(cat "$(glb_root "$ghome")/skills/ai-terse/SKILL.md")" = "local edit" ] || gok=0
# It stays discoverable (the flag stops updates, not exposure).
[ -L "$ghome/.codex/skills/ai-terse" ] || gok=0
# An installed:true sibling is still exposed.
[ -L "$ghome/.codex/skills/create-hld" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global installed:false skill is preserved (not refreshed) but stays discoverable"
else
  no "global installed:false skill is preserved (not refreshed) but stays discoverable" "$(cat "$(glb_root "$ghome")/skills/ai-terse/SKILL.md" 2>/dev/null)"
fi

# 8o. Uninstall snapshots the current (post-install) state of content files before
# restoring/removing them, so an operator edit made after install is not lost.
ghome="$(make_ghome "uninstall-preserve")"
printf '@%s/.codex/RTK.md\n\noperator AGENTS\n' "$ghome" >"$ghome/.codex/AGENTS.md"
printf '# RTK\n' >"$ghome/.codex/RTK.md"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"gk ai hook run --host codex","type":"command"}],"matcher":""}]}}\n' >"$ghome/.codex/hooks.json"
run_sh_global "$ghome" >/dev/null 2>&1
# Operator edits AGENTS.md after install, before uninstall.
printf '@%s/.codex/RTK.md\n\noperator AGENTS\nPOST-INSTALL EDIT\n' "$ghome" >"$ghome/.codex/AGENTS.md"
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
gok=1
unbak="$(ls "$ghome"/.codex/AGENTS.md.smooth-devex-uninstall-* 2>/dev/null | head -n 1)"
[ -n "$unbak" ] || gok=0
grep -q 'POST-INSTALL EDIT' "$unbak" 2>/dev/null || gok=0
# The restore still returned the operator's pre-install content to the live file.
grep -q 'POST-INSTALL EDIT' "$ghome/.codex/AGENTS.md" && gok=0
if [ "$gok" = "1" ]; then
  ok "global uninstall snapshots current state before restore (post-install edit preserved)"
else
  no "global uninstall snapshots current state before restore (post-install edit preserved)" "$(ls "$ghome"/.codex/*.smooth-devex-uninstall-* 2>/dev/null)"
fi

# 8p. Claude wiring: owned skills are symlinked into ~/.claude/skills when
# Claude's config dir exists; removed on uninstall; skipped when absent.
ghome="$(make_ghome "claude")"
mkdir -p "$ghome/.claude"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
for s in ai-ralph-loop ai-terse create-worktask; do
  [ -L "$ghome/.claude/skills/$s" ] || gok=0
  [ "$(readlink "$ghome/.claude/skills/$s")" = "$(glb_root "$ghome")/skills/$s" ] || gok=0
done
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
[ "$(ls "$ghome/.claude/skills" 2>/dev/null | wc -l | tr -d ' ')" = "0" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global Claude wiring: skills symlinked into ~/.claude/skills, removed on uninstall"
else
  no "global Claude wiring: skills symlinked into ~/.claude/skills, removed on uninstall" "$(ls "$ghome/.claude/skills" 2>/dev/null)"
fi

# 8r. Claude global rules: owned rules are symlinked into ~/.claude/rules when
# Claude is installed; removed on uninstall.
ghome="$(make_ghome "claude-rules")"
mkdir -p "$ghome/.claude"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
# The store ships the FULL template rules tree, so backend/ and the flat rules
# land too, not just the owned subset (git, meta).
[ -e "$(glb_root "$ghome")/rules/backend/architecture-slices.instructions.md" ] || gok=0
for r in code-review-standards.instructions.md git/git-policy.instructions.md \
  backend/architecture-slices.instructions.md meta/rules.instructions.md; do
  [ -L "$ghome/.claude/rules/$r" ] || gok=0
  [ "$(readlink "$ghome/.claude/rules/$r")" = "$(glb_root "$ghome")/rules/$r" ] || gok=0
done
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
[ "$(find "$ghome/.claude/rules" -type l 2>/dev/null | wc -l | tr -d ' ')" = "0" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global Claude rules: full rule tree (incl. backend/) symlinked into ~/.claude/rules, removed on uninstall"
else
  no "global Claude rules: full rule tree (incl. backend/) symlinked into ~/.claude/rules, removed on uninstall" "$(find "$ghome/.claude/rules" -type l 2>/dev/null)"
fi

# Per-item installed flags for rules[] and hooks[] (cases 8s-8x). The manifest carries the
# same {name, installed} entries for them that it does for skills, so one rule or one hook
# can be switched off without touching the rest.

# global_item_flag GHOME KEY NAME -> "true"/"false", or empty when the manifest has no such entry.
global_item_flag() {
  python3 -c "
import json, sys
for entry in json.load(open(sys.argv[1])).get(sys.argv[2], []):
    if entry['name'] == sys.argv[3]:
        print('true' if entry['installed'] else 'false')
        raise SystemExit(0)
" "$(global_manifest "$1")" "$2" "$3"
}

# set_global_item_flag GHOME KEY NAME true|false -- the operator's hand edit of the manifest.
set_global_item_flag() {
  python3 - "$(global_manifest "$1")" "$2" "$3" "$4" <<'PYEOF'
import json, sys
path, key, name, value = sys.argv[1:5]
data = json.load(open(path))
for entry in data[key]:
    if entry['name'] == name:
        entry['installed'] = (value == 'true')
json.dump(data, open(path, 'w'), indent=2)
PYEOF
}

# global_item_names GHOME KEY -> the manifest's names for KEY, sorted, one per line.
global_item_names() {
  python3 -c "
import json, sys
print('\n'.join(sorted(e['name'] for e in json.load(open(sys.argv[1])).get(sys.argv[2], []))))
" "$(global_manifest "$1")" "$2"
}

opencode_instr_has() { # GHOME ENTRY
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d.get('instructions',[]) else 1)" \
    "$1/.config/opencode/opencode.json" "$2"
}

# 8s. A first global install records every owned rule and hook in the manifest as
# installed:true, next to skills[] -- the list is the owned allowlist, nothing more.
ghome="$(make_ghome "items-shape")"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ "$(global_item_names "$ghome" rules)" = "$bash_rules" ] || gok=0
[ "$(global_item_names "$ghome" hooks)" = "$bash_hooks" ] || gok=0
python3 - "$(global_manifest "$ghome")" <<'PYEOF' || gok=0
import json, sys
d = json.load(open(sys.argv[1]))
assert d['skills'], 'skills[] missing'
for key in ('rules', 'hooks'):
    assert d[key] and all(e['installed'] is True for e in d[key]), key
PYEOF
if [ "$gok" = "1" ]; then
  ok "global manifest: rules[] and hooks[] list every owned item as installed:true beside skills[]"
else
  no "global manifest: rules[] and hooks[] list every owned item as installed:true beside skills[]" "$(python3 -c "import json;d=json.load(open('$(global_manifest "$ghome")'));print(list(d))")"
fi

# 8t. Reconciliation matches skills: the operator's flag survives a re-run, a name outside the
# owned allowlist is dropped (it can never be installed), and a missing owned name rejoins as true.
ghome="$(make_ghome "items-reconcile")"
run_sh_global "$ghome" >/dev/null 2>&1
set_global_item_flag "$ghome" rules clean-code.instructions.md false
set_global_item_flag "$ghome" hooks worktask-skill-trigger.sh false
python3 - "$(global_manifest "$ghome")" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d['rules'] = [e for e in d['rules'] if e['name'] != 'meta/rules.instructions.md']
d['rules'].append({'name': 'ghost.instructions.md', 'installed': True})
json.dump(d, open(p, 'w'), indent=2)
PYEOF
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ "$(global_item_flag "$ghome" rules clean-code.instructions.md)" = "false" ] || gok=0
[ "$(global_item_flag "$ghome" hooks worktask-skill-trigger.sh)" = "false" ] || gok=0
[ "$(global_item_flag "$ghome" hooks manage-rule-system-context.sh)" = "true" ] || gok=0
[ -z "$(global_item_flag "$ghome" rules ghost.instructions.md)" ] || gok=0
[ "$(global_item_flag "$ghome" rules meta/rules.instructions.md)" = "true" ] || gok=0
[ "$(global_item_names "$ghome" rules)" = "$bash_rules" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global manifest: an operator's rule/hook installed:false survives a re-run, unowned names drop, missing ones rejoin"
else
  no "global manifest: an operator's rule/hook installed:false survives a re-run, unowned names drop, missing ones rejoin" "clean-code=$(global_item_flag "$ghome" rules clean-code.instructions.md) ghost=$(global_item_flag "$ghome" rules ghost.instructions.md)"
fi

# 8u. A rule set to installed:false is switched off everywhere it was wired -- the generated
# AGENTS.md import, the ~/.claude/rules link, the opencode.json entry -- while its store copy keeps
# any local edit and every sibling rule stays wired. Flipping it back rewires it and refreshes it.
ghome="$(make_ghome "rule-off")"
mkdir -p "$ghome/.claude" "$ghome/.config/opencode"
printf '{"provider":{"name":"x"}}\n' >"$ghome/.config/opencode/opencode.json"
run_sh_global "$ghome" >/dev/null 2>&1
groot="$(glb_root "$ghome")"
rule="clean-code.instructions.md"
sibling="git/git-policy.instructions.md"
gok=1
[ -L "$ghome/.claude/rules/$rule" ] || gok=0
grep -q "$groot/rules/$rule" "$groot/AGENTS.md" || gok=0
opencode_instr_has "$ghome" "$groot/rules/$rule" || gok=0
printf 'local edit\n' >"$groot/rules/$rule"
set_global_item_flag "$ghome" rules "$rule" false
run_sh_global "$ghome" >/dev/null 2>&1
[ -e "$ghome/.claude/rules/$rule" ] || [ -L "$ghome/.claude/rules/$rule" ] && gok=0
grep -q "$rule" "$groot/AGENTS.md" && gok=0
opencode_instr_has "$ghome" "$groot/rules/$rule" && gok=0
[ "$(cat "$groot/rules/$rule")" = "local edit" ] || gok=0
[ -L "$ghome/.claude/rules/$sibling" ] || gok=0
grep -q "$groot/rules/$sibling" "$groot/AGENTS.md" || gok=0
opencode_instr_has "$ghome" "$groot/rules/$sibling" || gok=0
set_global_item_flag "$ghome" rules "$rule" true
run_sh_global "$ghome" >/dev/null 2>&1
[ -L "$ghome/.claude/rules/$rule" ] || gok=0
grep -q "$groot/rules/$rule" "$groot/AGENTS.md" || gok=0
opencode_instr_has "$ghome" "$groot/rules/$rule" || gok=0
[ "$(cat "$groot/rules/$rule")" != "local edit" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global installed:false rule is unwired (AGENTS import, Claude link, OpenCode entry), store edit kept, re-enable rewires"
else
  no "global installed:false rule is unwired (AGENTS import, Claude link, OpenCode entry), store edit kept, re-enable rewires" "claude=$(ls "$ghome/.claude/rules" 2>/dev/null | tr '\n' ' ') agents=$(grep -c "$rule" "$groot/AGENTS.md")"
fi

# 8v. A hook set to installed:false has its command removed from ~/.codex/hooks.json (the group it
# alone filled goes with it) while the other owned hook and the operator's gk hook stay; the store
# copy stays; flipping it back registers it again.
ghome="$(make_ghome "hook-off")"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"gk ai hook run --host codex","type":"command"}],"matcher":""}]}}\n' >"$ghome/.codex/hooks.json"
run_sh_global "$ghome" >/dev/null 2>&1
groot="$(glb_root "$ghome")"
hook="worktask-skill-trigger.sh"
other="manage-rule-system-context.sh"
gok=1
grep -q "$groot/hooks/$hook" "$ghome/.codex/hooks.json" || gok=0
set_global_item_flag "$ghome" hooks "$hook" false
run_sh_global "$ghome" >/dev/null 2>&1
grep -q "$groot/hooks/$hook" "$ghome/.codex/hooks.json" && gok=0
grep -q "$groot/hooks/$other" "$ghome/.codex/hooks.json" || gok=0
grep -q 'gk ai hook run --host codex' "$ghome/.codex/hooks.json" || gok=0
[ -f "$groot/hooks/$hook" ] || gok=0
python3 - "$ghome/.codex/hooks.json" <<'PYEOF' || gok=0
import json, sys
groups = json.load(open(sys.argv[1]))['hooks']['UserPromptSubmit']
assert all(g.get('hooks') for g in groups), 'an emptied group was left behind'
PYEOF
set_global_item_flag "$ghome" hooks "$hook" true
run_sh_global "$ghome" >/dev/null 2>&1
grep -q "$groot/hooks/$hook" "$ghome/.codex/hooks.json" || gok=0
if [ "$gok" = "1" ]; then
  ok "global installed:false hook is removed from hooks.json (gk and sibling kept, store copy kept), re-enable registers it"
else
  no "global installed:false hook is removed from hooks.json (gk and sibling kept, store copy kept), re-enable registers it" "$(cat "$ghome/.codex/hooks.json" 2>/dev/null)"
fi

# 8w. An opencode.json written by an earlier install (the rules/*.instructions.md glob pair) is
# migrated to per-file entries -- the globs would keep loading a disabled rule -- and the operator's
# own entries survive. A rules-only run (-g -r) is enough to do it.
ghome="$(make_ghome "opencode-legacy")"
groot="$(glb_root "$ghome")"
mkdir -p "$ghome/.config/opencode"
printf '{"instructions":["operator/own.md","%s/rules/*.instructions.md","%s/rules/**/*.instructions.md"]}\n' "$groot" "$groot" \
  >"$ghome/.config/opencode/opencode.json"
run_sh_global "$ghome" -r >/dev/null 2>&1
gok=1
opencode_instr_has "$ghome" "operator/own.md" || gok=0
opencode_instr_has "$ghome" "$groot/rules/code-review-standards.instructions.md" || gok=0
python3 - "$ghome/.config/opencode/opencode.json" "$(printf '%s\n' "$bash_rules" | wc -l | tr -d ' ')" <<'PYEOF' || gok=0
import json, sys
inst = json.load(open(sys.argv[1]))['instructions']
assert not any('*' in g for g in inst), 'a legacy glob survived'
assert len([g for g in inst if '/rules/' in g]) == int(sys.argv[2]), inst
PYEOF
if [ "$gok" = "1" ]; then
  ok "global OpenCode: a legacy rules glob pair becomes per-file entries (operator entries kept), via -g -r alone"
else
  no "global OpenCode: a legacy rules glob pair becomes per-file entries (operator entries kept), via -g -r alone" "$(cat "$ghome/.config/opencode/opencode.json" 2>/dev/null)"
fi

# 8x. A category-only run reconciles only its own list and carries the others forward: -g -r
# writes rules[] without inventing hooks[], and a later -g -h adds hooks[] without disturbing rules[].
ghome="$(make_ghome "items-carry")"
run_sh_global "$ghome" -r >/dev/null 2>&1
gok=1
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'rules' in d and 'hooks' not in d else 1)" "$(global_manifest "$ghome")" || gok=0
set_global_item_flag "$ghome" rules clean-code.instructions.md false
run_sh_global "$ghome" -h >/dev/null 2>&1
[ "$(global_item_names "$ghome" hooks)" = "$bash_hooks" ] || gok=0
[ "$(global_item_flag "$ghome" rules clean-code.instructions.md)" = "false" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global manifest: -g -r and -g -h each reconcile only their own list and carry the other forward"
else
  no "global manifest: -g -r and -g -h each reconcile only their own list and carry the other forward" "$(python3 -c "import json;print(list(json.load(open('$(global_manifest "$ghome")'))))")"
fi

# 8y. Switching items off after install must not cost the operator their pre-install files back:
# the second edit of opencode.json / hooks.json snapshots nothing (the first run did), and its link
# record must not overwrite the one that points at that snapshot -- so --uninstall still restores
# both files byte-for-byte.
ghome="$(make_ghome "flip-then-uninstall")"
mkdir -p "$ghome/.claude" "$ghome/.config/opencode"
printf '{"provider":{"name":"x"}}\n' >"$ghome/.config/opencode/opencode.json"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"gk ai hook run --host codex","type":"command"}],"matcher":""}]}}\n' >"$ghome/.codex/hooks.json"
cp "$ghome/.config/opencode/opencode.json" "$scratch/opencode.orig"
cp "$ghome/.codex/hooks.json" "$scratch/hooks.orig"
run_sh_global "$ghome" >/dev/null 2>&1
set_global_item_flag "$ghome" rules clean-code.instructions.md false
set_global_item_flag "$ghome" hooks worktask-skill-trigger.sh false
run_sh_global "$ghome" >/dev/null 2>&1
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
gok=1
cmp -s "$ghome/.config/opencode/opencode.json" "$scratch/opencode.orig" || gok=0
cmp -s "$ghome/.codex/hooks.json" "$scratch/hooks.orig" || gok=0
if [ "$gok" = "1" ]; then
  ok "global uninstall after flipping rules/hooks off restores opencode.json and hooks.json byte-for-byte"
else
  no "global uninstall after flipping rules/hooks off restores opencode.json and hooks.json byte-for-byte" "$(cat "$ghome/.config/opencode/opencode.json" 2>/dev/null) | $(cat "$ghome/.codex/hooks.json" 2>/dev/null)"
fi

# 8i. A global install that created ~/.codex/AGENTS.md from nothing removes it on
# uninstall — no RTK-only leftover — while .system/ and the store stay.
ghome="$(make_ghome "uninstall-fresh")"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ -f "$ghome/.codex/AGENTS.md" ] || gok=0
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
[ -f "$ghome/.codex/AGENTS.md" ] && gok=0
[ -d "$(glb_root "$ghome")/skills" ] || gok=0
[ -f "$ghome/.codex/skills/.system/cfg.md" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global uninstall removes an installer-created AGENTS.md from nothing (no leftover)"
else
  no "global uninstall removes an installer-created AGENTS.md from nothing (no leftover)" "$(ls -la "$ghome/.codex" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------------------------
# 9. harnesses{} and link `enabled`: switch a whole harness (claude-code, codex, opencode) off
# ---------------------------------------------------------------------------------------------
# harnesses{} in the global manifest turns a whole harness off: nothing is installed into it, and
# anything this installer put there is removed -- found on disk, not only in links[]. Each symlink
# record carries `enabled`, the installer's own status (is the link on disk right now).

# set_harness GHOME NAME true|false -- the operator's hand edit of harnesses{}.
set_harness() {
  python3 - "$(global_manifest "$1")" "$2" "$3" <<'PYEOF'
import json, sys
path, name, value = sys.argv[1:4]
data = json.load(open(path))
data['harnesses'][name] = (value == 'true')
json.dump(data, open(path, 'w'), indent=2)
PYEOF
}

# link_enabled GHOME TYPE -> the distinct enabled values on that link type ("true", "false", "false true", or empty).
link_enabled() {
  python3 -c "
import json, sys
vals = sorted({str(l['enabled']).lower() for l in json.load(open(sys.argv[1]))['links'] if l['type'] == sys.argv[2] and 'enabled' in l})
print(' '.join(vals))
" "$(global_manifest "$1")" "$2"
}

# count_links DIR -> how many symlinks sit under DIR (0 when DIR is absent).
count_links() { find -H "$1" -type l 2>/dev/null | wc -l | tr -d ' '; }

# A temp HOME with every harness present and an operator-owned file in each place the installer edits.
make_wired_ghome() {
  local gh
  gh="$(make_ghome "$1")"
  mkdir -p "$gh/.claude" "$gh/.config/opencode"
  printf '{"provider":{"name":"x"},"instructions":["operator/own.md"]}\n' >"$gh/.config/opencode/opencode.json"
  printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"gk ai hook run --host codex","type":"command"}],"matcher":""}]}}\n' >"$gh/.codex/hooks.json"
  printf '@%s/.codex/RTK.md\n\noperator line\n' "$gh" >"$gh/.codex/AGENTS.md"
  printf '# RTK\n' >"$gh/.codex/RTK.md"
  printf '%s\n' "$gh"
}

# 9a. A first install records harnesses{} (all true, fixed order) and `enabled` on exactly the four
# symlink record types; a missing harness key is added back as true and an operator false is kept.
ghome="$(make_wired_ghome "harness-shape")"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
python3 - "$(global_manifest "$ghome")" <<'PYEOF' || gok=0
import json, sys
d = json.load(open(sys.argv[1]))
assert list(d['harnesses'].items()) == [('claude-code', True), ('codex', True), ('opencode', True)], d['harnesses']
assert list(d)[:4] == ['updated', 'decisions_enabled', 'harnesses', 'skills'], list(d)
by_type = {}
for link in d['links']:
    by_type.setdefault(link['type'], []).append(link)
for kind in ('skill-link', 'claude-skill', 'opencode-skill', 'claude-rule'):
    assert by_type[kind] and all(l['enabled'] is True for l in by_type[kind]), kind
    assert list(by_type[kind][0]) == ['type', 'path', 'detail', 'enabled'], list(by_type[kind][0])
for kind in ('agents-import', 'hooks-merge', 'opencode-config'):
    assert by_type[kind] and all('enabled' not in l for l in by_type[kind]), kind
PYEOF
python3 - "$(global_manifest "$ghome")" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
del d['harnesses']['opencode']
d['harnesses']['claude-code'] = False
d['harnesses']['cursor'] = True
json.dump(d, open(p, 'w'), indent=2)
PYEOF
run_sh_global "$ghome" >/dev/null 2>&1
python3 -c "
import json, sys
h = json.load(open(sys.argv[1]))['harnesses']
assert list(h.items()) == [('claude-code', False), ('codex', True), ('opencode', True)], h
" "$(global_manifest "$ghome")" || gok=0
if [ "$gok" = "1" ]; then
  ok "global harnesses{}: all true by default, missing key re-added true, operator false kept, unknown key dropped; enabled only on symlink records"
else
  no "global harnesses{}: all true by default, missing key re-added true, operator false kept, unknown key dropped; enabled only on symlink records" "$(python3 -c "import json;d=json.load(open('$(global_manifest "$ghome")'));print(d.get('harnesses'), list(d))")"
fi

# 9b. claude-code false removes every store symlink under ~/.claude -- including one no record names --
# and leaves foreign links, real directories, Codex and OpenCode alone; the Claude link records stay as
# enabled:false. Switching it back on relinks them.
ghome="$(make_wired_ghome "harness-claude")"
run_sh_global "$ghome" >/dev/null 2>&1
groot="$(glb_root "$ghome")"
ln -s "$groot/skills/ai-terse" "$ghome/.claude/skills/stray-alias"
ln -s "$scratch" "$ghome/.claude/skills/foreign"
mkdir -p "$ghome/.claude/skills/operator-skill"
set_harness "$ghome" claude-code false
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ "$(count_links "$ghome/.claude/rules")" = "0" ] || gok=0
[ -L "$ghome/.claude/skills/foreign" ] || gok=0
[ -d "$ghome/.claude/skills/operator-skill" ] || gok=0
[ -e "$ghome/.claude/skills/stray-alias" ] || [ -L "$ghome/.claude/skills/stray-alias" ] && gok=0
[ "$(count_links "$ghome/.claude/skills")" = "1" ] || gok=0
[ "$(count_links "$ghome/.codex/skills")" = "$owned_n" ] || gok=0
[ "$(count_links "$ghome/.config/opencode/skills")" = "$owned_n" ] || gok=0
[ "$(link_enabled "$ghome" claude-skill)" = "false" ] || gok=0
[ "$(link_enabled "$ghome" claude-rule)" = "false" ] || gok=0
[ "$(link_enabled "$ghome" skill-link)" = "true" ] || gok=0
[ "$(link_enabled "$ghome" opencode-skill)" = "true" ] || gok=0
set_harness "$ghome" claude-code true
run_sh_global "$ghome" >/dev/null 2>&1
[ "$(count_links "$ghome/.claude/rules")" = "$(printf '%s\n' "$bash_rules" | wc -l | tr -d ' ')" ] || gok=0
[ "$(link_enabled "$ghome" claude-skill)" = "true" ] || gok=0
[ "$(link_enabled "$ghome" claude-rule)" = "true" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global claude-code:false removes every store symlink under ~/.claude (even unrecorded), spares foreign ones and other harnesses; true relinks"
else
  no "global claude-code:false removes every store symlink under ~/.claude (even unrecorded), spares foreign ones and other harnesses; true relinks" "claude links: $(find -H "$ghome/.claude" -type l 2>/dev/null | sed "s|$ghome|HOME|" | head -3 | tr '\n' ' ')"
fi

# 9c. codex false removes the skill links, the AGENTS.md import block (operator lines stay) and the store
# hook commands (the gk hook stays), leaves Claude and OpenCode wired, keeps the store, and true restores it.
ghome="$(make_wired_ghome "harness-codex")"
run_sh_global "$ghome" >/dev/null 2>&1
groot="$(glb_root "$ghome")"
set_harness "$ghome" codex false
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ "$(count_links "$ghome/.codex/skills")" = "0" ] || gok=0
[ -f "$ghome/.codex/skills/.system/cfg.md" ] || gok=0
grep -q 'installer-owned-global-instructions' "$ghome/.codex/AGENTS.md" && gok=0
grep -q 'operator line' "$ghome/.codex/AGENTS.md" || gok=0
grep -q "@$ghome/.codex/RTK.md" "$ghome/.codex/AGENTS.md" || gok=0
[ -f "$groot/AGENTS.md" ] || gok=0
grep -q "$groot/hooks/" "$ghome/.codex/hooks.json" && gok=0
grep -q 'gk ai hook run --host codex' "$ghome/.codex/hooks.json" || gok=0
python3 - "$ghome/.codex/hooks.json" <<'PYEOF' || gok=0
import json, sys
groups = json.load(open(sys.argv[1]))['hooks']['UserPromptSubmit']
assert all(g.get('hooks') for g in groups), 'an emptied group was left behind'
PYEOF
[ -f "$groot/hooks/worktask-skill-trigger.sh" ] || gok=0
[ -f "$groot/skills/ai-terse/SKILL.md" ] || gok=0
[ "$(count_links "$ghome/.claude/skills")" = "$owned_n" ] || gok=0
[ "$(count_links "$ghome/.config/opencode/skills")" = "$owned_n" ] || gok=0
opencode_instr_has "$ghome" "$groot/rules/clean-code.instructions.md" || gok=0
[ "$(link_enabled "$ghome" skill-link)" = "false" ] || gok=0
[ "$(link_enabled "$ghome" claude-skill)" = "true" ] || gok=0
set_harness "$ghome" codex true
run_sh_global "$ghome" >/dev/null 2>&1
[ "$(count_links "$ghome/.codex/skills")" = "$owned_n" ] || gok=0
[ "$(grep -c 'installer-owned-global-instructions' "$ghome/.codex/AGENTS.md")" = "1" ] || gok=0
grep -q "$groot/hooks/worktask-skill-trigger.sh" "$ghome/.codex/hooks.json" || gok=0
[ "$(link_enabled "$ghome" skill-link)" = "true" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global codex:false removes skill links, the AGENTS import (operator lines kept) and store hooks (gk kept); true restores them"
else
  no "global codex:false removes skill links, the AGENTS import (operator lines kept) and store hooks (gk kept); true restores them" "agents=$(cat "$ghome/.codex/AGENTS.md" | tr '\n' '|')"
fi

# 9d. opencode false removes the OpenCode skill links and every store entry from opencode.json
# instructions (the operator's own entry stays); Claude and Codex stay wired; true restores it.
ghome="$(make_wired_ghome "harness-opencode")"
run_sh_global "$ghome" >/dev/null 2>&1
groot="$(glb_root "$ghome")"
set_harness "$ghome" opencode false
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ "$(count_links "$ghome/.config/opencode/skills")" = "0" ] || gok=0
python3 - "$ghome/.config/opencode/opencode.json" "$groot" <<'PYEOF' || gok=0
import json, sys
d = json.load(open(sys.argv[1]))
assert d['instructions'] == ['operator/own.md'], d['instructions']
assert d['provider'] == {'name': 'x'}, d
PYEOF
[ "$(count_links "$ghome/.claude/skills")" = "$owned_n" ] || gok=0
[ "$(count_links "$ghome/.codex/skills")" = "$owned_n" ] || gok=0
[ "$(link_enabled "$ghome" opencode-skill)" = "false" ] || gok=0
set_harness "$ghome" opencode true
run_sh_global "$ghome" >/dev/null 2>&1
[ "$(count_links "$ghome/.config/opencode/skills")" = "$owned_n" ] || gok=0
opencode_instr_has "$ghome" "operator/own.md" || gok=0
opencode_instr_has "$ghome" "$groot/rules/clean-code.instructions.md" || gok=0
[ "$(link_enabled "$ghome" opencode-skill)" = "true" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global opencode:false removes the OpenCode skill links and store instructions (operator entry kept); true restores them"
else
  no "global opencode:false removes the OpenCode skill links and store instructions (operator entry kept); true restores them" "$(cat "$ghome/.config/opencode/opencode.json" 2>/dev/null)"
fi

# 9e. A harness that is false from the very first run is never installed into: no links, no import, no
# hook commands, no records -- the operator's files are byte-identical -- while the store is still filled
# and the other harnesses are wired.
ghome="$(make_wired_ghome "harness-off-first")"
groot="$(glb_root "$ghome")"
mkdir -p "$groot"
printf '{"harnesses":{"codex":false}}\n' >"$(global_manifest "$ghome")"
cp "$ghome/.codex/AGENTS.md" "$scratch/agents.first"
cp "$ghome/.codex/hooks.json" "$scratch/hooks.first"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
[ "$(count_links "$ghome/.codex/skills")" = "0" ] || gok=0
cmp -s "$ghome/.codex/AGENTS.md" "$scratch/agents.first" || gok=0
cmp -s "$ghome/.codex/hooks.json" "$scratch/hooks.first" || gok=0
python3 - "$(global_manifest "$ghome")" <<'PYEOF' || gok=0
import json, sys
d = json.load(open(sys.argv[1]))
assert d['harnesses'] == {'claude-code': True, 'codex': False, 'opencode': True}, d['harnesses']
kinds = {l['type'] for l in d['links']}
assert not kinds & {'skill-link', 'agents-import', 'hooks-merge'}, kinds
assert {'claude-skill', 'claude-rule', 'opencode-skill', 'opencode-config'} <= kinds, kinds
PYEOF
[ -f "$groot/skills/ai-terse/SKILL.md" ] || gok=0
[ -f "$groot/rules/clean-code.instructions.md" ] || gok=0
[ -f "$groot/hooks/manage-rule-system-context.sh" ] || gok=0
[ "$(count_links "$ghome/.claude/skills")" = "$owned_n" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "global harness false from the first run: nothing installed into it (files untouched, no records), store filled, others wired"
else
  no "global harness false from the first run: nothing installed into it (files untouched, no records), store filled, others wired" "$(python3 -c "import json;print(json.load(open('$(global_manifest "$ghome")')).get('harnesses'))" 2>&1)"
fi

# 9f. --uninstall is not gated by harnesses{} or `enabled`: with claude-code set to false and no re-run,
# the Claude links are still removed; and after harnesses were toggled off and on, uninstall still restores
# opencode.json, hooks.json and ~/.codex/AGENTS.md byte-for-byte.
ghome="$(make_wired_ghome "harness-uninstall")"
cp "$ghome/.config/opencode/opencode.json" "$scratch/oc.h9"
cp "$ghome/.codex/hooks.json" "$scratch/hk.h9"
cp "$ghome/.codex/AGENTS.md" "$scratch/ag.h9"
run_sh_global "$ghome" >/dev/null 2>&1
set_harness "$ghome" codex false
set_harness "$ghome" opencode false
run_sh_global "$ghome" >/dev/null 2>&1
set_harness "$ghome" codex true
set_harness "$ghome" opencode true
run_sh_global "$ghome" >/dev/null 2>&1
set_harness "$ghome" claude-code false
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
gok=1
[ "$(count_links "$ghome/.claude")" = "0" ] || gok=0
[ "$(count_links "$ghome/.codex/skills")" = "0" ] || gok=0
[ "$(count_links "$ghome/.config/opencode/skills")" = "0" ] || gok=0
cmp -s "$ghome/.config/opencode/opencode.json" "$scratch/oc.h9" || gok=0
cmp -s "$ghome/.codex/hooks.json" "$scratch/hk.h9" || gok=0
cmp -s "$ghome/.codex/AGENTS.md" "$scratch/ag.h9" || gok=0
if [ "$gok" = "1" ]; then
  ok "global --uninstall ignores harnesses{}/enabled and restores every edited file byte-for-byte after harness toggles"
else
  no "global --uninstall ignores harnesses{}/enabled and restores every edited file byte-for-byte after harness toggles" "links=$(find -H "$ghome/.claude" "$ghome/.codex/skills" "$ghome/.config/opencode/skills" -type l 2>/dev/null | wc -l | tr -d ' ') agents=$(cat "$ghome/.codex/AGENTS.md" | tr '\n' '|')"
fi

# ---------------------------------------------------------------------------------------------
# 10. Codex: the rule index in ~/.codex/AGENTS.md and the ~/.codex/rules/smooth-devex.rules policy
# ---------------------------------------------------------------------------------------------
# Codex does not resolve @-imports and caps combined AGENTS.md content at 32 KiB, so the global rules
# reach it as a compact index inside a delimited block, never as @ lines or inlined bodies. Codex's
# own .rules files are a command-approval policy (prefix_rule), so one is generated from git-policy.

# codex_decision RULESFILE CMD... -> the execpolicy decision (prompt / forbidden / none), or "skip"
# when the codex binary is not installed (CI): those assertions then fall back to the file's text.
codex_decision() {
  command -v codex >/dev/null 2>&1 || { echo skip; return 0; }
  local rules="$1"
  shift
  codex execpolicy check --rules "$rules" -- "$@" 2>/dev/null | python3 -c "
import json, sys
print(json.load(sys.stdin).get('decision', 'none'))"
}

# 10a. The block holds the index: no @ rule lines, every enabled rule's path, its scope, under 8 KiB,
# exactly one block after two runs, and the operator's own lines untouched.
ghome="$(make_wired_ghome "codex-index")"
run_sh_global "$ghome" >/dev/null 2>&1
run_sh_global "$ghome" >/dev/null 2>&1
groot="$(glb_root "$ghome")"
agents="$ghome/.codex/AGENTS.md"
gok=1
[ "$(grep -c 'installer-owned-global-instructions' "$agents")" = "1" ] || gok=0
[ "$(grep -c 'end of install-skills global rules' "$agents")" = "1" ] || gok=0
grep -q "^@$groot" "$agents" && gok=0
for r in $bash_rules; do grep -qF "$groot/rules/$r" "$agents" || gok=0; done
grep -qF 'Read at the start of every task:' "$agents" || gok=0
grep -qF 'When editing files matching `**/*.cs`:' "$agents" || gok=0
grep -q 'operator line' "$agents" || gok=0
grep -q "^@$ghome/.codex/RTK.md" "$agents" || gok=0
[ "$(wc -c <"$agents" | tr -d ' ')" -lt 8192 ] || gok=0
if [ "$gok" = "1" ]; then
  ok "codex AGENTS.md: one delimited block holding the rule index (paths + scopes, no @ lines, < 8 KiB), operator lines intact"
else
  no "codex AGENTS.md: one delimited block holding the rule index (paths + scopes, no @ lines, < 8 KiB), operator lines intact" "bytes=$(wc -c <"$agents" | tr -d ' ') blocks=$(grep -c 'installer-owned-global-instructions' "$agents")"
fi

# 10b. The block follows the per-item flags: a rule set to installed:false leaves the index (its siblings
# stay), and returns when switched back on - the block is replaced in place, never duplicated.
ghome="$(make_wired_ghome "codex-index-flip")"
run_sh_global "$ghome" >/dev/null 2>&1
groot="$(glb_root "$ghome")"
agents="$ghome/.codex/AGENTS.md"
rule="clean-code.instructions.md"
gok=1
set_global_item_flag "$ghome" rules "$rule" false
run_sh_global "$ghome" >/dev/null 2>&1
grep -qF "$groot/rules/$rule" "$agents" && gok=0
grep -qF "$groot/rules/git/git-policy.instructions.md" "$agents" || gok=0
[ "$(grep -c 'installer-owned-global-instructions' "$agents")" = "1" ] || gok=0
set_global_item_flag "$ghome" rules "$rule" true
run_sh_global "$ghome" >/dev/null 2>&1
grep -qF "$groot/rules/$rule" "$agents" || gok=0
[ "$(grep -c 'installer-owned-global-instructions' "$agents")" = "1" ] || gok=0
grep -q 'operator line' "$agents" || gok=0
if [ "$gok" = "1" ]; then
  ok "codex AGENTS.md: a rule set to installed:false leaves the index, siblings stay, switching it back returns it (one block)"
else
  no "codex AGENTS.md: a rule set to installed:false leaves the index, siblings stay, switching it back returns it (one block)" "$(tr '\n' '|' <"$agents" | cut -c1-300)"
fi

# 10c. An AGENTS.md written by the earlier installer (marker line + one @-line, no closing line) is migrated
# to the index block; the operator's lines around it survive.
ghome="$(make_wired_ghome "codex-index-legacy")"
groot="$(glb_root "$ghome")"
agents="$ghome/.codex/AGENTS.md"
mkdir -p "$groot"
printf '@%s/.codex/RTK.md\n\noperator line\n\n# installer-owned-global-instructions (added by install-skills)\n@%s/AGENTS.md\n' "$ghome" "$groot" >"$agents"
run_sh_global "$ghome" >/dev/null 2>&1
gok=1
grep -qxF '# installer-owned-global-instructions (added by install-skills)' "$agents" && gok=0
grep -q "^@$groot" "$agents" && gok=0
grep -qF "$groot/rules/git/git-policy.instructions.md" "$agents" || gok=0
[ "$(grep -c 'installer-owned-global-instructions' "$agents")" = "1" ] || gok=0
grep -q 'operator line' "$agents" || gok=0
grep -q "^@$ghome/.codex/RTK.md" "$agents" || gok=0
if [ "$gok" = "1" ]; then
  ok "codex AGENTS.md: the legacy marker + @-line block is migrated to the index block, operator lines kept"
else
  no "codex AGENTS.md: the legacy marker + @-line block is migrated to the index block, operator lines kept" "$(tr '\n' '|' <"$agents" | cut -c1-300)"
fi

# 10d. codex:false removes the block (operator lines stay) and the .rules file; true restores both.
ghome="$(make_wired_ghome "codex-off-rules")"
run_sh_global "$ghome" >/dev/null 2>&1
rf="$ghome/.codex/rules/smooth-devex.rules"
agents="$ghome/.codex/AGENTS.md"
gok=1
[ -f "$rf" ] || gok=0
set_harness "$ghome" codex false
run_sh_global "$ghome" >/dev/null 2>&1
[ -e "$rf" ] && gok=0
grep -q 'installer-owned-global-instructions' "$agents" && gok=0
grep -q 'end of install-skills global rules' "$agents" && gok=0
grep -q 'operator line' "$agents" || gok=0
set_harness "$ghome" codex true
run_sh_global "$ghome" >/dev/null 2>&1
[ -f "$rf" ] || gok=0
[ "$(grep -c 'installer-owned-global-instructions' "$agents")" = "1" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "codex:false removes the rules block and smooth-devex.rules (operator lines kept); true restores both"
else
  no "codex:false removes the rules block and smooth-devex.rules (operator lines kept); true restores both" "rules=$([ -e "$rf" ] && echo present || echo absent) agents=$(tr '\n' '|' <"$agents" | cut -c1-200)"
fi

# 10e. smooth-devex.rules: ours (header), valid and behaving as intended (commit/push prompt, a leading force
# flag is forbidden, other git commands unmatched), gone while git-policy is installed:false, never replacing
# a file that is not ours, and never creating default.rules (Codex appends the operator's approvals there).
ghome="$(make_wired_ghome "codex-rules-file")"
run_sh_global "$ghome" >/dev/null 2>&1
rf="$ghome/.codex/rules/smooth-devex.rules"
gok=1
[ "$(head -n 1 "$rf")" = "# installer-owned-global-rules (generated by install-skills -g; do not edit)" ] || gok=0
d_commit="$(codex_decision "$rf" git commit -m x)"
d_push="$(codex_decision "$rf" git push origin main)"
d_force="$(codex_decision "$rf" git push --force origin main)"
d_status="$(codex_decision "$rf" git status)"
if [ "$d_commit" = "skip" ]; then
  grep -qF 'pattern = ["git", "commit"],' "$rf" || gok=0
  grep -qF 'decision = "forbidden"' "$rf" || gok=0
else
  [ "$d_commit" = "prompt" ] && [ "$d_push" = "prompt" ] && [ "$d_force" = "forbidden" ] && [ "$d_status" = "none" ] || gok=0
fi
[ -e "$ghome/.codex/rules/default.rules" ] && gok=0
set_global_item_flag "$ghome" rules git/git-policy.instructions.md false
run_sh_global "$ghome" >/dev/null 2>&1
[ -e "$rf" ] && gok=0
set_global_item_flag "$ghome" rules git/git-policy.instructions.md true
run_sh_global "$ghome" >/dev/null 2>&1
[ -f "$rf" ] || gok=0
printf 'operator rules\n' >"$rf"
run_sh_global "$ghome" >/dev/null 2>&1
[ "$(cat "$rf")" = "operator rules" ] || gok=0
if [ "$gok" = "1" ]; then
  ok "smooth-devex.rules: header, prompt/forbidden/unmatched ($d_commit/$d_push/$d_force/$d_status), off with git-policy, a foreign file untouched, no default.rules"
else
  no "smooth-devex.rules: header, prompt/forbidden/unmatched, off with git-policy, a foreign file untouched, no default.rules" "commit=$d_commit push=$d_push force=$d_force status=$d_status"
fi

# 10f. --uninstall removes smooth-devex.rules and restores ~/.codex/AGENTS.md byte-for-byte, even after the
# block was rewritten by a flag flip in between.
ghome="$(make_wired_ghome "codex-uninstall")"
cp "$ghome/.codex/AGENTS.md" "$scratch/agents.h10"
run_sh_global "$ghome" >/dev/null 2>&1
set_global_item_flag "$ghome" rules clean-code.instructions.md false
run_sh_global "$ghome" >/dev/null 2>&1
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
gok=1
[ -e "$ghome/.codex/rules/smooth-devex.rules" ] && gok=0
[ -e "$ghome/.codex/rules/default.rules" ] && gok=0
cmp -s "$ghome/.codex/AGENTS.md" "$scratch/agents.h10" || gok=0
if [ "$gok" = "1" ]; then
  ok "global --uninstall removes smooth-devex.rules and restores ~/.codex/AGENTS.md byte-for-byte after a rewrite"
else
  no "global --uninstall removes smooth-devex.rules and restores ~/.codex/AGENTS.md byte-for-byte after a rewrite" "$(tr '\n' '|' <"$ghome/.codex/AGENTS.md" | cut -c1-200)"
fi

# 10g. A ~/.codex/AGENTS.md the installer created from nothing holds only the RTK header and our block, so
# switching codex off removes the file outright (the exact inverse of creating it), switching it on creates
# it again, and --uninstall removes it. A file that pre-dates the install is never removed (cases 9c, 10d).
ghome="$(make_ghome "codex-created")"
printf '# RTK\n' >"$ghome/.codex/RTK.md"
agents="$ghome/.codex/AGENTS.md"
gok=1
run_sh_global "$ghome" >/dev/null 2>&1
[ -f "$agents" ] || gok=0
grep -q "^@$ghome/.codex/RTK.md" "$agents" || gok=0
[ "$(grep -c 'installer-owned-global-instructions' "$agents")" = "1" ] || gok=0
set_harness "$ghome" codex false
run_sh_global "$ghome" >/dev/null 2>&1
[ -e "$agents" ] && gok=0
set_harness "$ghome" codex true
run_sh_global "$ghome" >/dev/null 2>&1
[ -f "$agents" ] || gok=0
[ "$(grep -c 'installer-owned-global-instructions' "$agents")" = "1" ] || gok=0
# A plain re-run must not snapshot the file: it holds only our own block, and --uninstall would then
# "restore" that snapshot instead of removing the file.
run_sh_global "$ghome" >/dev/null 2>&1
ls "$agents".smooth-devex-[0-9]* >/dev/null 2>&1 && gok=0
run_sh_global "$ghome" --uninstall >/dev/null 2>&1
[ -e "$agents" ] && gok=0
if [ "$gok" = "1" ]; then
  ok "codex AGENTS.md created by the installer: removed outright by codex:false and by --uninstall (even after a re-run), recreated by true"
else
  no "codex AGENTS.md created by the installer: removed outright by codex:false and by --uninstall (even after a re-run), recreated by true" "agents=$([ -e "$agents" ] && tr '\n' '|' <"$agents" | cut -c1-160 || echo absent)"
fi

# ---------------------------------------------------------------------------------------------

if python3 "$repo_root/scripts/test-installer-payload.py"; then
  ok "payload regressions: pruning, WET copies, category roots and global parity"
else
  no "payload regressions: pruning, WET copies, category roots and global parity"
fi

echo
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
