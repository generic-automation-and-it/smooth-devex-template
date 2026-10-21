#!/bin/bash
# Cross-platform skills installer for macOS/Linux (bash).
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash
#
# Contract:
#   1. Finds the agent root in order: .agents → .claude → .codex, and errors
#      when none exists. It never creates one: a folder the operator did not ask for is not an install.
#      The skills root is <agent-root>/skills (override with SKILLS_ROOT, whose parent then counts
#      as the agent root for state purposes). Missing category directories are created only when needed.
#   2. Category switches -r (rules), -s (skills), -h (hooks) select what this run installs.
#      No switches means everything is on. Switches filter the run only; nothing is persisted.
#   3. Skills: reads <agent-root>/_smooth-devex-shared/installation.json.
#      - Missing  → creates it with every skill on disk, installed:true, UTC timestamp.
#      - Present  → syncs: adds new skills, drops skills no longer on disk, keeps every
#                   installed flag the operator already set. A corrupt file is a hard error,
#                   never a silent reset of the whole manifest.
#      A legacy manifest at the old <skills-root>/_smooth-devex-shared/installation.json location
#      is ignored (fresh start): it is reported on stderr and otherwise left untouched.
#   4. Updates only the skills marked installed:true, cloning the repo once and copying those folders
#      (plus the shared payload, if the source ships one) out of it. Tests are pruned from these copies.
#   5. Rules (-r): copies the owned rule files (see OWNED_RULES) from the source's
#      .github/instructions/ into <agent-root>/rules/, preserving relative paths and writing through
#      an operator's rules symlink. Overwrites, never deletes: an operator's own rules are never swept.
#   6. Hooks (-h): copies the owned hook files (see OWNED_HOOKS) from the source's .agents/hooks/
#      into <agent-root>/hooks/. Overwrites, never deletes. Hook *registration* (settings.json)
#      is deliberately out of scope — the consumer wires what it wants.
#   7. Links every top-level shared-payload entry back to its canonical <agent-root> path
#      (e.g. <agent-root>/setup → _smooth-devex-shared/setup), so SKILL.md references to the
#      canonical paths keep working. An existing real file or directory at the link path is
#      never replaced: it is reported and skipped.
#   The temp clone forces `-c core.symlinks=true`; the consumer repo gets
#   `core.symlinks=true` best-effort (silently skipped outside git). See SKILLS_INSTALLER.md.
#   8. Writes the updated installation.json back with a fresh UTC timestamp — after the update, so
#      refreshing the shared payload cannot clobber the manifest that update read. Only written
#      when the skills category ran.
#
# Dependencies: bash, git, python3 (already a dependency of most skills shipped here).
#
# Environment overrides:
#   SKILLS_REPO    — git URL to clone from (default: the upstream GitHub repo)
#   SKILLS_BRANCH  — branch to clone (default: main)
#   SKILLS_ROOT    — force a specific skills root (skips the agent-root search; the
#                    parent directory of SKILLS_ROOT then counts as the agent root,
#                    so <parent>/_smooth-devex-shared holds the manifest)

set -euo pipefail

SKILLS_REPO="${SKILLS_REPO:-https://github.com/generic-automation-and-it/smooth-devex-template.git}"
# `-` not `:-`, and that single character is load-bearing. `:-` substitutes the default for an EMPTY
# value as well as an unset one, so `SKILLS_BRANCH=''` — which means "whatever the remote's default is",
# and is the only honest answer in a detached checkout where there is no branch name to pass — silently
# became "main" and then failed on any source that has no main branch. `-` substitutes only when unset.
SKILLS_BRANCH="${SKILLS_BRANCH-main}"

# Skills the installer is allowed to carry across to a consumer repo. The installer is scoped to
# this explicit allow list — a positive owned set, not a deny list — so the only skills that ever
# enter a consumer's manifest or land on disk are these.
#
# The rest of the source tree's `.agents/skills/` is treated as **local**: it lives in this template
# for use inside the template, and the installer ignores it on its way through. An unscoped installer
# pulled a target repo's local-only skills into its manifest as `installed:true` — that is the bug
# PR #245 fixed in `smooth-ai-product-context-memory`, and the same shape applies here.
#
# The owned set is deliberately explicit. This is a template repo, not a domain plugin; the skills
# worth carrying to a consumer are the ones that operate on the template's own shape (asset sync,
# template sync, rule system, context loading) or that are useful in any consumer project (terse
# response, ralph review-fix loop, hld + worktask authoring, GitHub issue breakdown, git commit/sync
# workflow). Session-scoped skills (ai-brain-dump, ai-understanding) stay local.
#
# If a skill you want to distribute lands here, add it to this list and to the harness's owned
# set in test-install-skills.sh. Anything else stays local.
OWNED_LIST=(
  agile-github-breakdown
  agile-github-task-from-diff
  ai-asset-sync
  ai-ralph-loop
  ai-template-sync
  ai-terse
  context-load-agents-context
  context-load-context
  create-hld
  create-worktask
  git-commit
  git-commit-push
  git-commit-push-pr
  git-sync
  manage-rule-system
)

# Rules the installer is allowed to carry across, as paths relative to .github/instructions/.
# Every rule in this template is owned — it is the DevEx rules tree, so all of them ship to a
# consumer (the generated rules-index AGENTS.md is the one file excluded; install_rules writes a
# generated index of the shipped set instead). Same positive owned-set shape as skills: never a
# deny list. Keep in sync with $script:OwnedRules (the harness holds the two byte-for-byte).
OWNED_RULES=(
  ai-workflow-rules.instructions.md
  backend/api-mediator-validation.instructions.md
  backend/architecture-slices.instructions.md
  backend/backend-logging-conventions.instructions.md
  backend/collection-types.instructions.md
  backend/external-api-clients.instructions.md
  backend/migrations.instructions.md
  backend/project-overview.instructions.md
  backend/readonly-collections.instructions.md
  backend/solid-principles.instructions.md
  backend/wiremock-stubbing.instructions.md
  clean-code.instructions.md
  code-review-standards.instructions.md
  git/git-policy.instructions.md
  git/pr-standards.instructions.md
  meta/knowledge-conventional-contexts-quality.instructions.md
  meta/rules.instructions.md
  meta/understandings.instructions.md
  skills/skill-secret-handling.instructions.md
  skills/skillspector-pre-pr.instructions.md
)

# Hooks the installer is allowed to carry across. Derived the same way: a hook is owned iff an
# owned skill's SKILL.md references it AND its implementation ships with it.
#
#   manage-rule-system-context.sh referenced by manage-rule-system (delegates into the owned skill)
#   worktask-skill-trigger.sh     referenced by create-worktask (self-contained router)
#
# load-agents-context.sh is referenced by ai-template-sync and its implementation now ships
# (context-load-agents-context is owned), but it is a PostToolUse hook and -g registers hooks under
# UserPromptSubmit only — registering it there would fire it on the wrong event. It stays local until
# the installer can register a hook by its own event. The rest (slnx-docs-sync.py,
# agentmd-create-update.sh, code-review-standards-context.sh, knowledge-rule-enforce.sh) is
# template-local and stays.
OWNED_HOOKS=(
  manage-rule-system-context.sh
  worktask-skill-trigger.sh
)

die() { echo "install-skills: $*" >&2; exit 1; }
log() { echo "install-skills: $*" >&2; }

# ---------------------------------------------------------------------------
# Decision validation opt-in
# ---------------------------------------------------------------------------

# check_decisions_enabled JSON — returns "true", "false", or "missing" from the decisions_enabled field.
# "missing" means the property is not present (prompt needed); "true"/"false" means saved preference.
check_decisions_enabled() {
  local json="$1"
  if [ -z "$json" ]; then
    printf 'missing'
    return
  fi
  printf '%s' "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'decisions_enabled' not in data:
    print('missing')
elif data['decisions_enabled']:
    print('true')
else:
    print('false')
"
}

# prompt_decisions — ask the user whether to enable decision validation.
# Reads from the controlling terminal (/dev/tty), so the question is asked even when
# stdin is piped (a typical `curl | bash`). Falls back to disabled when no terminal
# exists (CI, cron). Sets DECISIONS_ENABLED to "true" or "false".
prompt_decisions() {
  local answer=""
  # `-r` only checks the file mode: /dev/tty is world-readable on a CI runner that has no controlling
  # terminal, and opening it there fails with ENXIO. Open it for real before trusting it, then guard
  # the read itself — a failed open, a failed read, or EOF all fall back to disabled (never abort
  # the install under `set -e`).
  if ! { : < /dev/tty; } 2>/dev/null; then
    log "No terminal available — decisions disabled by default"
    DECISIONS_ENABLED="false"
    return
  fi
  echo ""
  echo "  Enable AI decision validation for ralph loop?"
  echo "  (Evaluates each fix via local OpenJEV model; requires openjev at localhost:1234)"
  printf "  [y/N] "
  if ! read -r answer < /dev/tty 2>/dev/null; then
    log "Could not read terminal — decisions disabled by default"
    DECISIONS_ENABLED="false"
    return
  fi
  case "$answer" in
    [yY]|[yY][eE][sS])
      DECISIONS_ENABLED="true"
      log "Decisions enabled"
      ;;
    *)
      DECISIONS_ENABLED="false"
      log "Decisions disabled"
      ;;
  esac
}

# write_decisions_env — write SMOOTH_DEVEX_DECISIONS_* env vars to the user's shell profile.
# Idempotent: skips when the sentinel marker is already present.
write_decisions_env() {
  local profile="" backup_path
  case "$(uname -s)" in
    Darwin) profile="$HOME/.zshrc" ;;
    Linux)  profile="$HOME/.bashrc" ;;
    *)      log "Unknown OS — env vars not written to profile"; return 0 ;;
  esac
  if grep -q "SMOOTH_DEVEX_DECISIONS" "$profile" 2>/dev/null; then
    log "Decision env vars already in $profile — skipped"
    return 0
  fi
  # Snapshot the shell profile before appending to it — it is operator-owned.
  backup_path="$(backup_inplace "$profile")"
  # In global mode, track the edit so --uninstall can restore the profile.
  if [ "$DO_GLOBAL" = "1" ]; then
    record_link "profile-edit" "$profile" "$backup_path"
  fi
  cat >> "$profile" <<'ENVEOF'

# Smooth DevEx — AI Decision Validation (added by install-skills)
export SMOOTH_DEVEX_DECISIONS_ENABLED=true
export SMOOTH_DEVEX_DECISIONS_BASE_URL=http://127.0.0.1:1234
export SMOOTH_DEVEX_DECISIONS_PATH=/v1/systemone
export SMOOTH_DEVEX_DECISIONS_MODEL=openjev
export SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY=0.60
export SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS=3
export SMOOTH_DEVEX_DECISIONS_TIMEOUT=60
ENVEOF
  log "Wrote decision env vars to $profile"
}

# The owned set is the single source of truth for what this installer carries across. Mirrors
# $script:OwnedList in install-skills.ps1 byte-for-byte (the harness compares the two).
#
# A test-only override SKILLS_TEST_OWNED_EXTRA extends the owned list with synthetic names so the
# harness can exercise add/drop cases without planting real source-owned names. Production
# installers never set this. The override is parsed once and merged into a single comparison
# surface, so the gate is one case statement, not two loops that drift on every new gate.
is_owned_skill() {
  local name="$1"
  case " $(owned_set) " in
    *" $name "*) return 0 ;;
  esac
  return 1
}

# owned_set prints the production owned list plus any test-only extras, one space-separated
# line. The caller is `is_owned_skill` above, which anchors the value on both sides with spaces
# so partial-token matches (e.g. `ai-` against `ai-terse`) cannot pass.
owned_set() {
  local out="${OWNED_LIST[*]}"
  [ -n "${SKILLS_TEST_OWNED_EXTRA:-}" ] && out="$out ${SKILLS_TEST_OWNED_EXTRA}"
  printf '%s' "$out"
}

# Owned rules and hooks need no membership test: the install loops below iterate the
# allowlists directly, so an unowned name can never enter (unlike skills, where a hand-edited
# manifest needs the is_owned_skill guard). No helpers, nothing to drift.

# Category switches. No switches means everything is on; any switch narrows the run to exactly
# what was named. Switches filter the run only — nothing about the selection is persisted.
# -d "decision validation" is a separate opt-in flag, not a category: it does not default on and
# is not part of the "no switches = all categories" rule.
DO_RULES=0
DO_SKILLS=0
DO_HOOKS=0
DO_DECISIONS=0
DO_GLOBAL=0
DO_UNINSTALL=0

parse_categories() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -r) DO_RULES=1 ;;
      -s) DO_SKILLS=1 ;;
      -h) DO_HOOKS=1 ;;
      -d) DO_DECISIONS=1 ;;
      -g) DO_GLOBAL=1 ;;
      --uninstall) DO_UNINSTALL=1 ;;
      *) die "unknown option: $arg (use -r for rules, -s for skills, -h for hooks, -d for decisions, -g for a global install to ~/.smooth-ai-devex, --uninstall to remove it)" ;;
    esac
  done
  if [ "$DO_RULES$DO_SKILLS$DO_HOOKS" = "000" ] && [ "$DO_UNINSTALL" = "0" ]; then
    DO_RULES=1
    DO_SKILLS=1
    DO_HOOKS=1
  fi
}

# ---------------------------------------------------------------------------
# 1. Find agent root and skills root
# ---------------------------------------------------------------------------

find_agent_root() {
  # Returns an absolute path. The manifest lives at <agent-root>/_smooth-devex-shared/installation.json,
  # and a later `cd` would silently change what that path resolves to. Resolving once at discovery
  # keeps every downstream join against the same root.
  local dir
  for dir in ".agents" ".claude" ".codex"; do
    if [ -d "$dir" ]; then
      printf '%s\n' "$(cd "$dir" && pwd -P)"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# 2. List skills (dirs with SKILL.md, excluding the shared folder)
# ---------------------------------------------------------------------------

# One function for both the disk and the clone source: the only thing they differ on
# is which directory is the root, and the owned-set gate is the same either way. The
# previous duplication (list_disk_skills / list_source_skills) was a copy-paste that
# drifted on every new gate, so the test had to cover two near-identical shapes.
list_skills() {
  local root="$1" dir name
  for dir in "$root"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    [ "$name" = "_smooth-devex-shared" ] && continue
    is_owned_skill "$name" || continue
    if [ -f "$dir/SKILL.md" ]; then
      printf '%s\n' "$name"
    fi
  done
}

# ---------------------------------------------------------------------------
# 3. JSON helpers (python3 — already a repo dependency)
# ---------------------------------------------------------------------------

json_read() {
  # Missing file reads as empty (a first install). A *corrupt* file is an error, not a first install:
  # treating it as empty would rewrite the manifest to installed:true for everything, which silently
  # re-enables skills the operator had turned off.
  python3 -c "
import json, sys, os
if not os.path.exists(sys.argv[1]):
    print('')
    raise SystemExit(0)
try:
    with open(sys.argv[1]) as f:
        print(json.dumps(json.load(f)))
except json.JSONDecodeError as exc:
    sys.stderr.write('install-skills: %s is not valid JSON (%s); fix or delete it — not treating it as a first install\n' % (sys.argv[1], exc))
    raise SystemExit(2)
" "$1"
}

json_write() {
  python3 -c "
import json, sys
data = json.loads(sys.argv[2])
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$1" "$2"
}

# ---------------------------------------------------------------------------
# 4. Sync installation.json with disk
# ---------------------------------------------------------------------------

build_installation_json() {
  # Emits the merged manifest on stdout; the caller writes it after the update.
  #
  # $2 is the clone source's skill list, NOT just what is on disk. Deriving the manifest from disk alone
  # makes a first install into an empty skills folder a no-op — there is nothing on disk, so there is
  # nothing to install, and the operator's very first run leaves them with an empty folder and a
  # manifest listing nothing. The source is the catalogue; disk is what is already there.
  local skills_root="$1" existing_json="$2" source_skills_json="$3"
  local decisions_enabled="${4:-false}"
  local disk_skills_json

  disk_skills_json="$(list_skills "$skills_root" | python3 -c "
import json, sys
skills = sorted(line.strip() for line in sys.stdin if line.strip())
print(json.dumps(skills))
")"
  # Owned union for the python reconciliation step: production OWNED_LIST plus the test-only
  # SKILLS_TEST_OWNED_EXTRA env var (set by scripts/test-install-skills.sh). Without the union
  # here, the manifest builder's intersection step would silently drop the synthetic names the
  # harness uses for add/drop cases.
  owned_json="$( { printf '%s\n' "${OWNED_LIST[@]}"; [ -n "${SKILLS_TEST_OWNED_EXTRA:-}" ] && printf '%s\n' ${SKILLS_TEST_OWNED_EXTRA}; } | python3 -c "
import json, sys
print(json.dumps(sorted(line.strip() for line in sys.stdin if line.strip())))
")"

  python3 - "$disk_skills_json" "$existing_json" "$source_skills_json" "$owned_json" "$decisions_enabled" <<'PYEOF'
import json, sys
from datetime import datetime, timezone

# Catalogue is source union disk INTERSECTED with the owned set. Without the intersection, a skill
# in source or disk that is not owned would still enter the manifest as installed:true (the unscoped
# installer pulled a foreign repo's local-only skills into its manifest exactly that way).
disk_skills = set(json.loads(sys.argv[1])) & set(json.loads(sys.argv[4]))
existing_raw = sys.argv[2].strip()
source_skills = set(json.loads(sys.argv[3])) & set(json.loads(sys.argv[4]))
decisions_enabled = sys.argv[5] == "true"

# The catalogue is the union: what the source offers, plus anything already here. A skill the operator
# added by hand is in neither the source nor the manifest until it has a SKILL.md, and dropping it would
# delete state the operator owns.
catalog = source_skills | disk_skills

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

if not existing_raw:
    # First run: every skill in the catalogue is what the operator asked for, so it installs. Defaulting
    # to false here would make a first run a no-op - the operator would have to hand-edit the manifest
    # before anything could ever update.
    data = {
        "updated": now,
        "decisions_enabled": decisions_enabled,
        "skills": [{"name": s, "installed": True} for s in sorted(catalog)],
    }
else:
    existing = json.loads(existing_raw)
    existing_map = {e["name"]: e.get("installed", False) for e in existing.get("skills", [])}
    # Drop what is gone from both the source and disk (the requirement is to remove removed skills), and
    # preserve every flag the operator already set, including false. A new skill joins as true, same as
    # the first-run rule.
    merged = []
    for name in sorted(catalog):
        merged.append({"name": name, "installed": existing_map.get(name, True)})
    # decisions_enabled is the resolved preference already computed by the caller (main) —
    # -d override, a reused saved value, a prompt answer, or the no-terminal default. Write it
    # as-is so a -d override actually persists across re-installs.
    data = {
        "updated": now,
        "decisions_enabled": decisions_enabled,
        "skills": merged,
    }

print(json.dumps(data))
PYEOF
}

# The skills the clone source offers. (see list_skills above)

# sweep_stale_entries DEST SOURCE — remove from DEST everything SOURCE does not have, recursively.
#
# `installation.json` is spared wherever it is found, because it is this script's own state and not
# anything the clone source carries: sweeping it away is what turns an interrupted run into a silent
# reset of every installed flag on the next one.
sweep_stale_entries() {
  local dest="$1" source="$2"
  [ ! -L "$dest" ] || return 0
  local entry name
  for entry in "$dest"/* "$dest"/.[!.]* "$dest"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="$(basename "$entry")"
    [ "$name" = "installation.json" ] && continue
    if [ ! -L "$entry" ] && [ -d "$source/$name" ] && [ -d "$entry" ]; then
      sweep_stale_entries "$entry" "$source/$name"
    elif [ ! -e "$source/$name" ] && [ ! -L "$source/$name" ]; then
      rm -rf "$entry"
    fi
  done
}

realpath_of() {
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

validate_shared_root() {
  local src="$1" dest="$2" resolved parent clone
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -d "$dest" ]; }; then
    die "shared payload destination must be a real directory: $dest"
  fi
  resolved="$(realpath_of "$src")"
  parent="$(realpath_of "$(dirname "$src")")"
  clone="$(realpath_of "$INSTALL_TMP/repo")"
  case "$resolved/" in
    "$clone"/*) ;;
    *) die "shared payload root must resolve inside the clone: $src" ;;
  esac
  if [ ! -d "$resolved" ] || [ -L "$resolved" ]; then
    die "shared payload root cannot be materialized: $src"
  fi
  case "$parent/" in
    "$resolved/"*) die "shared payload root cannot point to an ancestor: $src" ;;
  esac
}

WET_STACK=""
CLONE_ROOT=""
copy_wet() {
  local src="$1" dest="$2" resolved parent entry
  : "${CLONE_ROOT:=$(realpath_of "$INSTALL_TMP/repo")}"
  if [ -L "$src" ]; then
    resolved="$(realpath_of "$src")"
    parent="$(realpath_of "$(dirname "$src")")"
    case "$resolved/" in
      "$CLONE_ROOT"/*)
        case "$WET_STACK|$parent/" in
          *"|$resolved|"* | *"|$resolved/"*) ;;
          *)
            if [ -e "$resolved" ]; then
              local saved="$WET_STACK"
              WET_STACK="$WET_STACK|$resolved|"
              copy_wet "$resolved" "$dest"
              WET_STACK="$saved"
              return 0
            fi
            ;;
        esac
        ;;
    esac
    rm -rf "$dest"
    cp -P "$src" "$dest"
    log "Kept link $dest -> $(readlink "$src") (outside the source, dangling, or cyclic)"
    return 0
  fi
  if [ -d "$src" ]; then
    if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -d "$dest" ]; }; then rm -rf "$dest"; fi
    mkdir -p "$dest"
    for entry in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      copy_wet "$entry" "$dest/$(basename "$entry")"
    done
  else
    rm -rf "$dest"
    cp -p "$src" "$dest"
  fi
}

prune_tests() {
  [ ! -L "$1" ] || return 0
  find "$1" -type d \( -name test -o -name tests -o -name __tests__ \) -prune -exec rm -rf {} +
  find "$1" -type f \( -name 'test_*' -o -name '*_test.*' -o -name '*.test.*' -o -name '*.Tests.ps1' \) -exec rm -f {} +
}

# ---------------------------------------------------------------------------
# 5. Update installed skills from the repo
# ---------------------------------------------------------------------------

clone_source() {
  # Cloned before the manifest is built, not inside the update: the manifest's catalogue is the source's
  # skill list, so a first install into an empty folder has to see the source before it can decide there
  # is anything to install. The clone happens exactly once per run either way.
  #
  # The temp dir is a global, not a local, because the EXIT trap runs after this function has returned:
  # a trap closing over a `local` reads it under `set -u` and aborts the script on the way out, after
  # every real work had already succeeded.
  INSTALL_TMP="$(mktemp -d)"
  trap 'rm -rf "${INSTALL_TMP:-}"' EXIT INT TERM HUP

  log "Cloning $SKILLS_REPO (${SKILLS_BRANCH:-default branch})…"
  # SKILLS_BRANCH is optional, and that is not a convenience: `git rev-parse --abbrev-ref HEAD` returns
  # the literal string "HEAD" in a detached checkout, which is exactly what actions/checkout produces.
  # `git clone --branch HEAD` is not valid — HEAD is not a branch or tag name — so a harness or an
  # operator that passed the obvious-looking value got a run that died at the clone with the branch name
  # printed in its own error. An empty branch means "whatever the remote's default is", which is what
  # HEAD means everywhere else in this comment.
  # A relative local path is normalised to file:// so --depth applies. git ignores --depth in a local clone
  # ("use file:// instead"), which is a quiet downgrade — the whole clone is taken instead of one commit —
  # and the clone fails outright when the local repository has no branch of that name, which is exactly the
  # detached-HEAD case this whole branch of the logic exists to handle.
  #
  # Only bare *relative* local paths get the prefix. Anything else — an https URL (scheme matches), an
  # absolute local path (matches `/*`), an scp-style SSH remote (`git@host:owner/repo.git`, neither matches)
  # — is passed through unchanged. The previous test (`*://* | /*`) matched the SSH case and rewrote it
  # to `file://$PWD/git@host:owner/repo.git`, which then failed at git's "not a git repository". The new
  # test re-checks existence so a missing relative path also falls through (the clone will then fail at
  # the git call with the real reason, not a mangled URL).
  clone_url="$SKILLS_REPO"
  case "$clone_url" in
    *://* | /*) ;;
    *) [ -d "$clone_url" ] && clone_url="file://$PWD/$clone_url" ;;
  esac

  # `-c core.symlinks=true` forces symlink checkout in the temp clone regardless of the
  # operator's global git config. Without it, a Windows-default git materializes the source's
  # committed symlinks (.agents/setup/scripts, .agents/templates) as plain text files, and the
  # payload copy below would copy file-blobs instead of directories. On a machine without symlink
  # privilege (Windows without Developer Mode or elevation) the forced checkout fails outright —
  # so fall back to a plain clone with a warning instead of dying. The fallback is complete: the
  # installer only reads real directories out of the clone (skills, hooks, _smooth-devex-shared,
  # .github/instructions); canonical links are created filesystem-side afterwards.
  if [ -n "$SKILLS_BRANCH" ]; then
    git -c core.symlinks=true clone --depth 1 --branch "$SKILLS_BRANCH" "$clone_url" "$INSTALL_TMP/repo" >/dev/null 2>&1 \
      || { log "WARNING: symlink checkout failed — retrying without symlink support"; git clone --depth 1 --branch "$SKILLS_BRANCH" "$clone_url" "$INSTALL_TMP/repo" >/dev/null 2>&1; } \
      || die "Failed to clone $SKILLS_REPO (branch '$SKILLS_BRANCH' — set SKILLS_BRANCH empty for the default)"
  else
    git -c core.symlinks=true clone --depth 1 "$clone_url" "$INSTALL_TMP/repo" >/dev/null 2>&1 \
      || { log "WARNING: symlink checkout failed — retrying without symlink support"; git clone --depth 1 "$clone_url" "$INSTALL_TMP/repo" >/dev/null 2>&1; } \
      || die "Failed to clone $SKILLS_REPO"
  fi
}

# Best-effort: mark symlinks supported in the consumer repo, mirroring .agents/setup/scripts.
# Filesystem links the installer creates work regardless; this only affects how git *records*
# them on the consumer's next commit. Outside a git work tree (or when git is missing) it is
# silently skipped — never a failure.
ensure_consumer_symlink_support() {
  local agent_root="$1"
  git -C "$agent_root" config core.symlinks true 2>/dev/null || true
}

# ensure_canonical_link AGENT_ROOT NAME — link <agent-root>/<name> at the shared payload entry.
#
# SKILL.md files reference canonical paths (.agents/setup/..., .agents/hooks/..., ...). The payload
# lives under _smooth-devex-shared/, so the installer links each top-level payload entry back to its
# canonical path. An existing real file or directory is never replaced: it is reported and skipped,
# and the payload stays reachable under _smooth-devex-shared/ either way.
ensure_canonical_link() {
  local agent_root="$1" shared_dir="$2" name="$3"
  local link="$agent_root/$name" target="_smooth-devex-shared/$name"
  if [ -L "$link" ]; then
    if [ "$(readlink "$link")" = "$target" ]; then
      return 0
    fi
    log "WARNING: $link is a symlink to somewhere else — left untouched"
    return 0
  fi
  if [ -e "$link" ]; then
    log "WARNING: $link already exists — leaving the real entry in place, shared copy stays under $shared_dir/$name"
    return 0
  fi
  ln -s "$target" "$link"
  log "Linked $link -> $target"
}

# strip_skill_context DIR — delete the AGENTS.md files inside an installed skill
# folder. A skill's AGENTS.md documents the owner repo's local-dev context and
# improvements; it is not part of the runnable payload a consumer should inherit,
# so the installer removes it from the copy while leaving the source's in place.
strip_skill_context() {
  local dir="$1"
  [ ! -L "$dir" ] || return 0
  [ -d "$dir" ] || return 0
  find "$dir" -type f -name 'AGENTS.md' -delete 2>/dev/null || true
}

update_installed_skills() {
  local installation_json="$1" skills_root="$2" agent_root="$3" shared_dir="$4"
  local installed_names

  installed_names="$(printf '%s' "$installation_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for s in data.get('skills', []):
    if s.get('installed'):
        print(s['name'])
")"

  if [ -z "$installed_names" ]; then
    # NOT a hard return: the shared-folder refresh below is independent of skill flags, and the
    # contract says shared helpers must stay current even when no skill is installed:true. Fall
    # through.
    log "No skills marked installed:true — nothing to copy for skills."
  fi

  local name
  if [ -n "$installed_names" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      # Belt-and-braces: the manifest already excluded unowned skills (built from the owned
      # intersection). Re-check here in case the caller hand-wrote the manifest and put an unowned
      # name back in with installed:true. Same rejection shape the source repo's PR #245 added.
      is_owned_skill "$name" || { log "Skipping unowned skill: $name"; continue; }
      if [ -d "$INSTALL_TMP/repo/.agents/skills/$name" ]; then
        rm -rf "$skills_root/$name"
        copy_wet "$INSTALL_TMP/repo/.agents/skills/$name" "$skills_root/$name"
        prune_tests "$skills_root/$name"
        strip_skill_context "$skills_root/$name"
        log "Updated $name"
      else
        log "WARNING: $name not found in repo — left on disk untouched"
      fi
    done <<< "$installed_names"
  fi

  # The shared payload is not a skill and all of it refreshes on every run, independently of
  # the skill flags. Only cross-cutting, repo-owned infra lives here (setup scripts, templates,
  # installer state): skills, rules and hooks each have their own installer category and their
  # own standard directories.
  #
  # Refreshed *by content*, with stale entries removed, rather than merged in (which would leave a file
  # deleted upstream alive forever — an updater that never forgets anything is not an updater) and
  # rather than replacing the folder outright (which would take the manifest sitting inside it down with
  # it, and a run interrupted between the two would leave the next run rebuilding every flag from
  # defaults). So: copy across, then delete exactly what the source does not have, except the manifest.
  local shared_source="$INSTALL_TMP/repo/.agents/_smooth-devex-shared"
  if [ -d "$shared_source" ] || [ -L "$shared_source" ]; then
    local shared_dest="$shared_dir"
    validate_shared_root "$shared_source" "$shared_dest"
    copy_wet "$shared_source" "$shared_dest"
    prune_tests "$shared_dest"
    # Recursive, and that recursion is the point: a top-level-only sweep keeps every entry the source
    # still has *as a folder* while leaving the files inside it that the source dropped, which is where
    # a retired script actually goes.
    sweep_stale_entries "$shared_dest" "$shared_source"
    log "Updated _smooth-devex-shared"
    # Link the payload back to canonical paths so .agents/setup/... references keep working.
    local entry name
    for entry in "$shared_source"/*; do
      [ -e "$entry" ] || continue
      name="$(basename "$entry")"
      ensure_canonical_link "$agent_root" "$shared_dir" "$name"
    done
  fi
}

# ---------------------------------------------------------------------------
# 6. Rules and hooks (owned only, overwrite, never delete)
# ---------------------------------------------------------------------------

# The shipped-rules table, shared by the full-file and append paths below. Scopes mirror the
# template's own index for the owned subset only.
rules_index_table() {
  cat <<'EOF'
| Scope | Rules |
| :---- | :---- |
| `**` | `ai-workflow-rules` · `clean-code` |
| `**/*.cs` | `code-review-standards` · `backend/project-overview` · `backend/solid-principles` · `backend/api-mediator-validation` · `backend/architecture-slices` · `backend/backend-logging-conventions` · `backend/collection-types` · `backend/external-api-clients` · `backend/readonly-collections` |
| `src/*.Infrastructure/Persistence/Migrations/**/*.cs` | `backend/migrations` |
| `tests/*.TestFramework.Aspire/**/*.cs` | `backend/wiremock-stubbing` |
| `**` | `git/git-policy` · `git/pr-standards` |
| `**/*AGENTS.md` | `meta/knowledge-conventional-contexts-quality` |
| `.agents/rules/**` | `meta/rules` |
| `**/*understanding.md` | `meta/understandings` |
| `.agents/skills/**` | `skills/skill-secret-handling` · `skills/skillspector-pre-pr` |
EOF
}

write_rules_index() {
  # The template's own AGENTS.md catalogues rules that never ship (dangling refs on a fresh
  # install) and would clobber an existing consumer index — so it is never copied. Instead:
  # missing index → write a generated one we own; our generated file → refresh it;
  # someone else's index → append our subset once (marker-guarded), never rewrite it.
  local dest_rules="$1" index="$1/AGENTS.md" table
  table="$(rules_index_table)"
  if [ ! -f "$index" ]; then
    {
      printf '# AGENTS.md - Rules (installed subset)\n\n'
      printf '<!-- installer-owned-rules-subset: regenerated by install-skills -->\n\n'
      printf 'Rule index for the files the skills installer shipped. The template full index\n'
      printf 'lives upstream; only the files below are present here.\n\n'
      printf '## Key Behaviors\n\n%s\n' "$table"
      printf '\nFile = `<name>.instructions.md` in this folder.\n'
    } > "$index"
    log "Wrote generated rules index $index"
  elif [ "$(head -n 1 "$index")" = "# AGENTS.md - Rules (installed subset)" ]; then
    {
      printf '# AGENTS.md - Rules (installed subset)\n\n'
      printf '<!-- installer-owned-rules-subset: regenerated by install-skills -->\n\n'
      printf 'Rule index for the files the skills installer shipped. The template full index\n'
      printf 'lives upstream; only the files below are present here.\n\n'
      printf '## Key Behaviors\n\n%s\n' "$table"
      printf '\nFile = `<name>.instructions.md` in this folder.\n'
    } > "$index"
    log "Refreshed generated rules index $index"
  elif grep -q "installer-owned-rules-subset" "$index"; then
    log "Rules index already carries the installed subset — left untouched"
  else
    {
      printf '\n## Installed subset (installer-owned-rules-subset)\n\n%s\n' "$table"
    } >> "$index"
    log "Appended installed subset to existing rules index $index"
  fi
}

install_rules() {
  local agent_root="$1"
  local source_rules dest_rules rel
  source_rules="$INSTALL_TMP/repo/.github/instructions"
  dest_rules="$agent_root/rules"
  if [ ! -d "$source_rules" ]; then
    log "No .github/instructions in source — nothing to install for rules"
    return 0
  fi
  mkdir -p "$(realpath_of "$dest_rules")"
  for rel in "${OWNED_RULES[@]}"; do
    if [ -f "$source_rules/$rel" ]; then
      mkdir -p "$(dirname "$dest_rules/$rel")"
      copy_wet "$source_rules/$rel" "$dest_rules/$rel"
      log "Updated rule $rel"
    else
      log "WARNING: rule $rel not found in repo — left on disk untouched"
    fi
  done
  write_rules_index "$dest_rules"
}

install_hooks() {
  local agent_root="$1"
  local source_hooks dest_hooks name
  source_hooks="$INSTALL_TMP/repo/.agents/hooks"
  dest_hooks="$agent_root/hooks"
  if [ ! -d "$source_hooks" ]; then
    log "No .agents/hooks in source — nothing to install for hooks"
    return 0
  fi
  mkdir -p "$(realpath_of "$dest_hooks")"
  for name in "${OWNED_HOOKS[@]}"; do
    if [ -e "$source_hooks/$name" ]; then
      copy_wet "$source_hooks/$name" "$dest_hooks/$name"
      # Exec bit per owned file only: a wildcard chmod would also flip operator-owned
      # scripts sharing the directory. Preserve the source bit, don't invent one.
      case "$name" in
        *.sh) [ -x "$source_hooks/$name" ] && chmod +x "$dest_hooks/$name" ;;
      esac
      log "Updated hook $name"
    else
      log "WARNING: hook $name not found in repo — left on disk untouched"
    fi
  done
}

# ---------------------------------------------------------------------------
# Global install (-g): a ~/.smooth-ai-devex central store wired into Codex.
#
# The per-repo install above scopes everything to <agent-root> in the repo you
# are standing in. -g instead installs the same owned set once, machine-wide,
# into a store and then wires it into Codex's own config dir (~/.codex by
# default, or $CODEX_HOME):
#   - skills:  copied into the store and symlinked into ~/.codex/skills/<name>,
#              which coexists with Codex's own .system/ (never touched).
#   - rules:   copied into the store, and ~/.codex/AGENTS.md carries a compact
#              index of them (path, scope, one-line description) in a delimited
#              block. Codex does not resolve @-imports and caps combined AGENTS.md
#              content at 32 KiB, so neither @-lines nor the rule bodies can go
#              there. No *.instructions.md is written into ~/.codex/rules/: Codex
#              .rules files are a Starlark prefix_rule() command-approval policy.
#              One is generated from git-policy as ~/.codex/rules/smooth-devex.rules.
#   - hooks:   JSON-merged into ~/.codex/hooks.json (UserPromptSubmit only) with
#              absolute store commands; relative .agents/... commands would
#              break outside the repo and from subdirectories.
# A manifest at $GLB_ROOT/installation.json records every link and edit, and
# `-g --uninstall` removes exactly that -- never .system/, the gk hooks, or the
# operator's RTK @-import line.
#
# The same manifest carries skills[], rules[] and hooks[], each entry {name,
# installed}. installed:false on a rule or hook switches that one item off: it is
# not copied, and is removed from the AGENTS.md import, ~/.claude/rules,
# opencode.json instructions or hooks.json it was wired into. Its store copy stays.
#
# harnesses{} (claude-code, codex, opencode; missing = true) switches a whole tool off: nothing
# is installed into it, and every store symlink / import / hook / instructions entry already
# there is removed, found on disk rather than from links[]. --uninstall ignores it. Symlink
# records carry `enabled`, a status recomputed each run (is the link on disk), not a control.
#
# The store is HOME-scoped and per-machine, like the consumer manifest is
# per-repo: two machines cannot confuse two installers' state. $SMOOTH_DEVEX_HOME
# overrides the store location and $CODEX_HOME overrides Codex's config dir
# (both are how the test harness isolates a run from a real ~/.codex).
# ---------------------------------------------------------------------------

GLB_ROOT="${SMOOTH_DEVEX_HOME:-$HOME/.smooth-ai-devex}"
GLOBAL_MANIFEST="$GLB_ROOT/installation.json"
GLOBAL_MARKER="installer-owned-global-instructions"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
LINKS=()
# Per-item state for the rules and hooks categories, resolved from the manifest by
# run_global_install: the reconciled JSON arrays, and the names carrying each
# installed flag as newline-separated lists (the same shape the skills loops read).
GLB_RULES_JSON=""
GLB_HOOKS_JSON=""
RULES_ON=""
RULES_OFF=""
HOOKS_ON=""
HOOKS_OFF=""
# The three harnesses the installer can wire into, resolved from the manifest's harnesses
# object by run_global_install. 1 = install into it, 0 = do not, and remove what is there.
GLB_HARNESSES_JSON=""
HARNESS_CLAUDE=1
HARNESS_CODEX=1
HARNESS_OPENCODE=1

# record_link TYPE PATH [DETAIL] — append a link/edit record for the uninstall
# manifest. A tab cannot appear in a path on any supported OS, so the tab split
# is unambiguous.
record_link() {
  if [ -n "${3:-}" ]; then
    LINKS+=("$1	$2	$3")
  else
    LINKS+=("$1	$2")
  fi
}

# backup_inplace FILE — snapshot an operator-owned file the installer is about to
# append to, as <FILE>.smooth-devex-<UTC YYYYMMDD-HHMMSS>. Snaps exactly once per
# file (a re-run sees the first snapshot and leaves it), so what --uninstall
# restores is the genuinely pre-install content — never our own earlier append.
# Echoes the backup path, or nothing when there is no pre-existing file to
# protect (a file the installer is about to create is not snapshotted).
backup_inplace() {
  local file="$1" b
  [ -e "$file" ] || return 0
  # Only the numeric install-time snapshots count as "already backed up"; an
  # uninstall-time snapshot (smooth-devex-uninstall-*) must not suppress a fresh
  # install backup on the next run.
  for b in "$file".smooth-devex-[0-9]*; do
    [ -e "$b" ] && return 0
  done
  local stamp
  stamp="$(date -u +%Y%m%d-%H%M%S)"
  cp "$file" "$file.smooth-devex-$stamp"
  printf '%s\n' "$file.smooth-devex-$stamp"
}

ensure_global_store() {
  mkdir -p "$GLB_ROOT/skills" "$GLB_ROOT/rules" "$GLB_ROOT/hooks"
}

# reconcile_global_items KEY EXISTING_JSON NAME... — the manifest's per-item list for
# one category (rules or hooks), as a JSON array of {name, installed}. The catalogue is
# the owned allowlist, so a name outside it can never enter or survive a hand edit; a
# name the manifest has not seen joins as installed:true; the flag the operator already
# set is kept, false included. Same rule build_installation_json applies to skills.
reconcile_global_items() {
  local key="$1" existing="$2"
  shift 2
  python3 - "$key" "$existing" "$@" <<'PYEOF'
import json, sys
key, raw = sys.argv[1], sys.argv[2]
catalog = sorted(set(sys.argv[3:]))
known = {}
if raw.strip():
    data = json.loads(raw)
    items = data.get(key, []) if isinstance(data, dict) else []
    if isinstance(items, list):
        for entry in items:
            if isinstance(entry, dict) and isinstance(entry.get("name"), str):
                known[entry["name"]] = bool(entry.get("installed", False))
print(json.dumps([{"name": n, "installed": known.get(n, True)} for n in catalog]))
PYEOF
}

# global_items_flagged ITEMS_JSON true|false — names carrying that installed flag, one per line.
global_items_flagged() {
  printf '%s' "$1" | python3 -c "
import json, sys
want = sys.argv[1] == 'true'
for entry in json.load(sys.stdin):
    if bool(entry.get('installed')) == want:
        print(entry['name'])
" "$2"
}

# unlink_store_file DESTLINK TARGET — remove DESTLINK only when it is the symlink this
# installer made (it points at TARGET). A real file or a foreign link is never touched.
unlink_store_file() {
  local destlink="$1" target="$2"
  if [ -L "$destlink" ] && [ "$(readlink "$destlink")" = "$target" ]; then
    rm -f "$destlink"
    log "Unlinked disabled rule $destlink"
  fi
}

# reconcile_harnesses EXISTING_JSON — the manifest's harnesses object: exactly the three
# harnesses the installer can wire into, in a fixed order. A harness the manifest has not
# seen joins as true; the value the operator set is kept, false included; any other key
# is dropped.
reconcile_harnesses() {
  python3 - "$1" <<'PYEOF'
import json, sys
raw = sys.argv[1]
known = {}
if raw.strip():
    data = json.loads(raw)
    found = data.get("harnesses") if isinstance(data, dict) else None
    if isinstance(found, dict):
        known = found
print(json.dumps({h: bool(known.get(h, True)) for h in ("claude-code", "codex", "opencode")}))
PYEOF
}

# harness_flag HARNESSES_JSON NAME — prints 1 when the harness is on, 0 when off.
harness_flag() {
  printf '%s' "$1" | python3 -c "
import json, sys
print(1 if json.load(sys.stdin).get(sys.argv[1], True) else 0)
" "$2"
}

# purge_store_links DIR SUBDIR — remove every symlink under DIR (recursively) that points
# into the store's SUBDIR. Found by where a link points, not by what the manifest recorded,
# so a link whose record was lost goes too. A real file, and a link to anywhere else, is
# never touched.
purge_store_links() {
  local dir="$1" subdir="$2" link
  [ -d "$dir" ] || return 0
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    case "$(readlink "$link")" in
      "$GLB_ROOT/$subdir/"*)
        rm -f "$link"
        log "Unlinked $link (harness turned off)"
        ;;
    esac
  done < <(find -H "$dir" -type l 2>/dev/null)
}

# The delimited block this installer keeps in ~/.codex/AGENTS.md opens with a line carrying
# GLOBAL_MARKER and closes with a line carrying CODEX_BLOCK_END. An older install wrote only the
# marker line and one @-line after it (no closing line); that legacy form is recognised too.
CODEX_BLOCK_END="end of install-skills global rules"

# codex_agents_block FILE MODE [ARG] — edit only our block in FILE, never anything around it.
#   state          print none | block | legacy
#   apply  BODY    replace our block in place (or append one) with BODY; print same | changed | appended
#   remove RTKLINE delete our block and the blank line before it; print none | removed | removed-empty
#                  (removed-empty: nothing but ARG, the RTK header line, is left)
codex_agents_block() {
  python3 - "$1" "$GLOBAL_MARKER" "$CODEX_BLOCK_END" "$2" "${3:-}" <<'PYEOF'
import os, sys
path, marker, end_token, mode, arg = sys.argv[1:6]
begin = '<!-- ' + marker + ' (added by install-skills): regenerated on every run -->'
end = '<!-- ' + end_token + ' -->'
text = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
lines = text.split('\n')

start = next((i for i, line in enumerate(lines) if marker in line), None)
stop = None
legacy = False
if start is not None:
    for j in range(start + 1, len(lines)):
        if marker in lines[j]:
            break
        if end_token in lines[j]:
            stop = j
            break
    if stop is None:
        legacy = True
        stop = start + 1 if start + 1 < len(lines) and lines[start + 1].startswith('@') else start

if mode == 'state':
    print('none' if start is None else ('legacy' if legacy else 'block'))
elif mode == 'apply':
    block = [begin] + arg.rstrip('\n').split('\n') + [end]
    if start is None:
        prefix = text
        if prefix and not prefix.endswith('\n'):
            prefix += '\n'
        if prefix:
            prefix += '\n'
        result, outcome = prefix + '\n'.join(block) + '\n', 'appended'
    elif lines[start:stop + 1] == block:
        result, outcome = text, 'same'
    else:
        result, outcome = '\n'.join(lines[:start] + block + lines[stop + 1:]), 'changed'
    if outcome != 'same':
        with open(path, 'w', encoding='utf-8') as f:
            f.write(result)
    print(outcome)
elif mode == 'remove':
    if start is None:
        print('none')
    else:
        kept = lines[:start]
        if kept and kept[-1] == '':
            kept.pop()
        kept += lines[stop + 1:]
        result = '\n'.join(kept)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(result)
        print('removed-empty' if result.strip() in ('', arg) else 'removed')
PYEOF
}

# strip_codex_import FILE RTKLINE — codex is off: remove our block from FILE. No snapshot is taken
# (one was, at install). A file that was created by this installer and now holds nothing else is
# removed, the exact inverse of creating it; one that pre-dates the install (it has a snapshot) stays.
strip_codex_import() {
  local file="$1" rtk_line="${2:-}" outcome
  [ -f "$file" ] || return 0
  outcome="$(codex_agents_block "$file" remove "$rtk_line")"
  case "$outcome" in
    removed*) log "Removed the global rules block from $file (codex turned off)" ;;
  esac
  if [ "$outcome" = "removed-empty" ] && ! ls "$file".smooth-devex-[0-9]* >/dev/null 2>&1; then
    rm -f "$file"
    log "Removed $file (the installer created it and nothing else is in it)"
  fi
}

# render_rules_index — the text Codex is given in place of the rule files. Codex does not resolve
# @-imports and caps combined AGENTS.md content at 32 KiB, so the 20 rule bodies cannot travel
# in it; this lists each enabled rule's path, scope and one-line description instead.
render_rules_index() {
  python3 - "$GLB_ROOT/rules" "$RULES_ON" <<'PYEOF'
import os, re, sys
root, enabled = sys.argv[1], [r for r in sys.argv[2].splitlines() if r]


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in '\'"':
        value = value[1:-1]
    return value


def describe(path):
    text = open(path, encoding='utf-8').read()
    match = re.match(r'^---\r?\n(.*?)\r?\n---\r?\n', text, re.S)
    front = match.group(1) if match else ''

    def field(key):
        found = re.search(r'^%s:\s*(.+?)\s*$' % key, front, re.M)
        return unquote(found.group(1)) if found else ''

    scope = field('applyTo') or field('globs') or '**'
    summary = field('description')
    if not summary:
        heading = re.search(r'^#\s+(.+)$', text[match.end():] if match else text, re.M)
        summary = heading.group(1).strip() if heading else os.path.basename(path)
    if len(summary) > 100:
        summary = summary[:99].rstrip() + '…'
    return scope, summary


groups = {}
for rel in enabled:
    path = os.path.join(root, rel)
    if os.path.isfile(path):
        scope, summary = describe(path)
        groups.setdefault(scope, []).append('- %s - %s' % (path, summary))

if not groups:
    print('No global rules are installed.')
    raise SystemExit(0)
print('Codex does not import files from AGENTS.md, so the rules below are NOT loaded for you.')
print('Open the ones that apply with your file tools before you work, and follow them.')
if '**' in groups:
    print('\nRead at the start of every task:')
    print('\n'.join(groups.pop('**')))
for scope, entries in groups.items():
    print('\nWhen editing files matching `%s`:' % scope)
    print('\n'.join(entries))
PYEOF
}

# link_skill_into DEST_DIR NAME LINKTYPE — link the store's copy of NAME into
# DEST_DIR/NAME (Codex and Claude both call this). Keeps a correct existing link;
# a real file/dir or a foreign link at the path is reported and left untouched.
# Never aborts the run for one failed link; records the link for --uninstall.
link_skill_into() {
  local destdir="$1" name="$2" linktype="$3"
  local link="$destdir/$name"
  local target="$GLB_ROOT/skills/$name"
  if [ ! -e "$target" ]; then
    log "WARNING: $target missing — no global skill symlink for $name"
    return 0
  fi
  if [ -L "$link" ]; then
    if [ "$(readlink "$link")" = "$target" ]; then
      log "Global skill $name already linked into $(basename "$destdir")"
      return 0
    fi
    log "WARNING: $link is a symlink to somewhere else — left untouched"
    return 0
  fi
  if [ -e "$link" ]; then
    log "WARNING: $link already exists — left untouched"
    return 0
  fi
  mkdir -p "$destdir"
  if ! ln -s "$target" "$link"; then
    log "WARNING: could not create symlink $link -> $target — left untouched (or it appeared between the check and the create)"
    return 0
  fi
  record_link "$linktype" "$link" "$target"
  log "Linked global skill $name -> $target"
}

# symlink_global_skill NAME — link the store's copy of NAME into Codex's skills dir.
symlink_global_skill() {
  link_skill_into "$CODEX_HOME/skills" "$1" "skill-link"
}

# symlink_global_claude NAME — link the store's copy of NAME into Claude Code's
# skills dir (~/.claude/skills).
symlink_global_claude() {
  link_skill_into "$CLAUDE_HOME/skills" "$1" "claude-skill"
}

# install_global_claude MANIFEST_JSON — symlink each installed owned skill into
# Claude Code's skills dir for global availability, when Claude's config dir
# exists. Wired in addition to Codex/OpenCode, never instead of.
install_global_claude() {
  local manifest="$1"
  if [ "$HARNESS_CLAUDE" != "1" ]; then
    purge_store_links "$CLAUDE_HOME/skills" skills
    return 0
  fi
  if [ ! -d "$CLAUDE_HOME" ]; then
    log "Claude Code config not found ($CLAUDE_HOME) — skipping global Claude wiring"
    return 0
  fi
  local installed name
  installed="$(printf '%s' "$manifest" | python3 -c "
import json, sys
for s in json.load(sys.stdin).get('skills', []):
    if s.get('installed'):
        print(s['name'])
")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    is_owned_skill "$name" || continue
    symlink_global_claude "$name"
  done <<< "$installed"
}

# install_global_claude_rules — symlink the owned rules into Claude Code's global
# rules dir (~/.claude/rules) so Claude Code loads them across sessions.
install_global_claude_rules() {
  if [ "$HARNESS_CLAUDE" != "1" ]; then
    purge_store_links "$CLAUDE_HOME/rules" rules
    return 0
  fi
  if [ ! -d "$CLAUDE_HOME" ]; then
    log "Claude Code config not found ($CLAUDE_HOME) — skipping global Claude rules"
    return 0
  fi
  local rel target link
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    target="$GLB_ROOT/rules/$rel"
    [ -f "$target" ] || continue
    link="$CLAUDE_HOME/rules/$rel"
    link_store_file "$link" "$target" "claude-rule"
  done <<< "$RULES_ON"
  # A rule flipped to installed:false is unwired too, so the flag turns it off rather
  # than only stopping updates. The store copy stays (operator edits preserved).
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    unlink_store_file "$CLAUDE_HOME/rules/$rel" "$GLB_ROOT/rules/$rel"
  done <<< "$RULES_OFF"
}

# link_store_file DESTLINK TARGET LINKTYPE — symlink a store file at DESTLINK.
# Kept when a correct link already exists; a real file/dir or a foreign link at
# the path is reported and left untouched (never a replacement). Records the link
# for --uninstall. Used for OpenCode commands, where the link points at a skill's
# SKILL.md (a command is a markdown file, so the filename is the command name).
link_store_file() {
  local destlink="$1" target="$2" linktype="$3"
  if [ -L "$destlink" ]; then
    if [ "$(readlink "$destlink")" = "$target" ]; then
      log "Already linked: $destlink -> $target"
      return 0
    fi
    log "WARNING: $destlink is a symlink to somewhere else — left untouched"
    return 0
  fi
  if [ -e "$destlink" ]; then
    log "WARNING: $destlink already exists — left untouched"
    return 0
  fi
  mkdir -p "$(dirname "$destlink")"
  if ! ln -s "$target" "$destlink"; then
    log "WARNING: could not create symlink $destlink -> $target — left untouched"
    return 0
  fi
  record_link "$linktype" "$destlink" "$target"
  log "Linked $destlink -> $target"
}

# install_global_opencode MANIFEST_JSON — register each installed owned skill as
# an OpenCode command. OpenCode already discovers the owned skills through the
# Claude/agents interface, so we do NOT copy them into ~/.config/opencode/skills/;
# instead we reference each skill's SKILL.md from the commands folder (filename =
# command name). Skipped when OpenCode's config dir is absent.
# install_global_opencode MANIFEST_JSON — symlink each installed owned skill into
# OpenCode's own skills dir (~/.config/opencode/skills), so OpenCode loads the full
# skill (SKILL.md + scripts) via the native skill tool. Skipped when OpenCode's
# config dir is absent.
install_global_opencode() {
  local manifest="$1"
  if [ "$HARNESS_OPENCODE" != "1" ]; then
    purge_store_links "$OPENCODE_CONFIG/skills" skills
    return 0
  fi
  if [ ! -d "$OPENCODE_CONFIG" ]; then
    log "OpenCode config not found ($OPENCODE_CONFIG) — skipping global OpenCode wiring"
    return 0
  fi
  local installed name
  installed="$(printf '%s' "$manifest" | python3 -c "
import json, sys
for s in json.load(sys.stdin).get('skills', []):
    if s.get('installed'):
        print(s['name'])
")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    is_owned_skill "$name" || continue
    link_skill_into "$OPENCODE_CONFIG/skills" "$name" "opencode-skill"
  done <<< "$installed"
}

# install_global_opencode_config — make the operator's opencode.json `instructions`
# list exactly the installed:true store rules, one absolute path per rule. Per-file
# entries (not a rules/** glob) are what let a single rule be switched off. Entries
# under the store's rules dir that are no longer wanted -- a disabled rule, or the
# glob pair an earlier install wrote -- are dropped; everything else the operator
# put there is kept. Snapshots the file before writing, records the edit for
# --uninstall.
install_global_opencode_config() {
  local config="$OPENCODE_CONFIG/opencode.json"
  if [ ! -f "$config" ]; then
    log "opencode.json not found ($config) — skipping global rules instructions"
    return 0
  fi
  # A harness that is off wants no entries; with none of ours present there is nothing to
  # remove, and snapshotting the file for no edit would leave a stray first snapshot behind.
  local wanted_rules="$RULES_ON"
  if [ "$HARNESS_OPENCODE" != "1" ]; then
    wanted_rules=""
    if ! grep -qF "$GLB_ROOT/rules/" "$config"; then
      log "OpenCode is off and $config holds no store rules — nothing to remove"
      return 0
    fi
  fi
  local backup_path altered
  backup_path="$(backup_inplace "$config")"
  [ -n "$backup_path" ] && log "Backed up $config -> $backup_path"
  altered="$(python3 - "$config" "$GLB_ROOT" "$wanted_rules" <<'PYEOF'
import json, sys
path, glb_root = sys.argv[1], sys.argv[2]
enabled = [rel for rel in sys.argv[3].splitlines() if rel]
data = json.load(open(path, encoding='utf-8'))
inst = data.get('instructions', [])
if not isinstance(inst, list):
    inst = []
prefix = glb_root + '/rules/'
wanted = [prefix + rel for rel in enabled]
kept = [g for g in inst if not (isinstance(g, str) and g.startswith(prefix) and g not in wanted)]
added = [w for w in wanted if w not in kept]
changed = kept != inst or bool(added)
if changed:
    result = kept + added
    if result:
        data['instructions'] = result
    else:
        data.pop('instructions', None)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
print('1' if changed else '0')
PYEOF
)"
  if [ "$altered" = "1" ]; then
    record_link "opencode-config" "$config" "$backup_path"
    log "Updated global rules instructions in $config"
  else
    log "OpenCode instructions already match the installed rules in $config"
  fi
}

# install_global_skills MANIFEST_JSON — copy the owned skills into the central
# store, then symlink each installed:true owned skill into Codex's skills dir.
install_global_skills() {
  local installation_json="$1" name installed
  # Only installed:true entries are refreshed into the store AND symlinked, so an
  # installed:false skill is neither overwritten (local edits preserved) nor
  # exposed to Codex. The owned-name guard still applies to every entry.
  installed="$(printf '%s' "$installation_json" | python3 -c "
import json, sys
for s in json.load(sys.stdin).get('skills', []):
    if s.get('installed'):
        print(s['name'])
")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    is_owned_skill "$name" || continue
    if [ -d "$INSTALL_TMP/repo/.agents/skills/$name" ]; then
      rm -rf "$GLB_ROOT/skills/$name"
      copy_wet "$INSTALL_TMP/repo/.agents/skills/$name" "$GLB_ROOT/skills/$name"
      prune_tests "$GLB_ROOT/skills/$name"
      strip_skill_context "$GLB_ROOT/skills/$name"
      log "Stored global skill $name"
    else
      log "WARNING: skill $name not found in repo — not stored"
    fi
  done <<< "$installed"
  if [ "$HARNESS_CODEX" = "1" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      is_owned_skill "$name" || continue
      symlink_global_skill "$name"
    done <<< "$installed"
  else
    purge_store_links "$CODEX_HOME/skills" skills
  fi
}

# install_global_rules — copy the installed:true rule files into the store,
# preserving relative paths. Overwrite, never delete: an installed:false rule is
# neither refreshed (operator edits in the store survive) nor wired.
install_global_rules() {
  local source_rules="$INSTALL_TMP/repo/.github/instructions"
  if [ ! -d "$source_rules" ]; then
    log "No .github/instructions in source — nothing to install for global rules"
    return 0
  fi
  # The global install sends the FULL template rules tree machine-wide (every
  # rule in this template is owned). The generated AGENTS.md index is excluded
  # (it is not an .instructions.md rule and the installer writes its own).
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ -f "$source_rules/$rel" ]; then
      mkdir -p "$(dirname "$GLB_ROOT/rules/$rel")"
      copy_wet "$source_rules/$rel" "$GLB_ROOT/rules/$rel"
      log "Stored global rule $rel"
    else
      log "WARNING: rule $rel not found in repo — not stored"
    fi
  done <<< "$RULES_ON"
}

# write_global_agents — generate the store-level AGENTS.md: the rule index (see
# render_rules_index). It is the same text install_global_instructions inlines into
# ~/.codex/AGENTS.md; this copy is for people and for tools that read the store directly.
write_global_agents() {
  local file="$GLB_ROOT/AGENTS.md"
  {
    printf '# Smooth DevEx — installed global instructions\n'
    printf '# (managed by install-skills -g; do not edit)\n\n'
    printf '<!-- %s: regenerated by install-skills -->\n\n' "$GLOBAL_MARKER"
    render_rules_index
    printf '\n'
  } > "$file"
  log "Wrote global rules index $file"
}

# install_global_instructions — keep one delimited block in $CODEX_HOME/AGENTS.md holding the rule
# index. Codex does not resolve @-imports, so the index is inlined, not imported. The block is
# replaced in place on every run (it follows the installed:false flags) and an older two-line
# @-import block is migrated by the same replacement. Anything outside the block, notably an
# operator's @.../RTK.md line, is never touched. A missing AGENTS.md is created with an
# RTK-preserving header.
install_global_instructions() {
  write_global_agents
  local codex_agents="$CODEX_HOME/AGENTS.md" rtk_line="" backup_path outcome index
  if [ -f "$CODEX_HOME/RTK.md" ]; then
    rtk_line="@$CODEX_HOME/RTK.md"
  fi
  if [ "$HARNESS_CODEX" != "1" ]; then
    strip_codex_import "$codex_agents" "$rtk_line"
    return 0
  fi
  index="$(render_rules_index)"
  if [ ! -f "$codex_agents" ]; then
    if [ -n "$rtk_line" ]; then
      printf '%s\n' "$rtk_line" > "$codex_agents"
    else
      : > "$codex_agents"
    fi
    codex_agents_block "$codex_agents" apply "$index" >/dev/null
    record_link "agents-import" "$codex_agents"
    log "Created $codex_agents with the global rules index"
    return 0
  fi
  if [ "$(codex_agents_block "$codex_agents" state)" = "none" ]; then
    # We are about to add to a pre-existing operator-owned file: snapshot it first so
    # --uninstall can restore the operator's content. Only here: a file that already holds our
    # block either has its snapshot from the first install or was created by us, and a snapshot
    # of that would capture our own block.
    backup_path="$(backup_inplace "$codex_agents")"
    if [ -n "$backup_path" ]; then
      log "Backed up $codex_agents -> $backup_path"
    fi
    codex_agents_block "$codex_agents" apply "$index" >/dev/null
    record_link "agents-import" "$codex_agents" "$backup_path"
    log "Appended the global rules index to $codex_agents"
    return 0
  fi
  outcome="$(codex_agents_block "$codex_agents" apply "$index")"
  if [ "$outcome" = "changed" ]; then
    log "Updated the global rules index in $codex_agents"
  else
    log "Global rules index already current in $codex_agents"
  fi
}

# install_global_codex_rules — keep ~/.codex/rules/smooth-devex.rules, a Codex command-approval
# policy derived from the git/git-policy rule. Codex .rules files are Starlark prefix_rule()s that
# gate which commands run outside the sandbox; they cannot carry instructions, which is why the
# other rules travel as an AGENTS.md index. A file of our own, never default.rules: Codex appends
# the operator's permanent approvals there. Written only while codex is on and git-policy is
# installed:true; otherwise removed, but only when it is ours (first line carries the header).
CODEX_RULES_HEADER="# installer-owned-global-rules (generated by install-skills -g; do not edit)"
install_global_codex_rules() {
  local file="$CODEX_HOME/rules/smooth-devex.rules" want=0
  if [ "$HARNESS_CODEX" = "1" ] && printf '%s\n' "$RULES_ON" | grep -qx 'git/git-policy.instructions.md'; then
    want=1
  fi
  if [ -e "$file" ] && [ "$(head -n 1 "$file")" != "$CODEX_RULES_HEADER" ]; then
    log "WARNING: $file exists and is not ours — left untouched"
    return 0
  fi
  if [ "$want" != "1" ]; then
    if [ -e "$file" ]; then
      rm -f "$file"
      log "Removed $file"
    fi
    return 0
  fi
  local content
  content="$(cat <<RULESEOF
$CODEX_RULES_HEADER
# Command-approval policy derived from the git/git-policy rule; Codex reads it at startup.
# Prefix matching only: "git -C <dir> commit" is not matched, and "git push origin x --force"
# is prompted by the push rule rather than forbidden. Keep your own rules in another file;
# default.rules belongs to Codex.

prefix_rule(
    pattern = ["git", "commit"],
    decision = "prompt",
    justification = "git-policy: never commit unless the user explicitly asks",
    match = [["git", "commit", "-m", "message"]],
    not_match = [["git", "status"]],
)

prefix_rule(
    pattern = ["git", "push"],
    decision = "prompt",
    justification = "git-policy: never push unless the user explicitly asks",
    match = [["git", "push", "origin", "main"]],
    not_match = [["git", "pull"]],
)

prefix_rule(
    pattern = ["git", "push", ["--force", "-f", "--force-with-lease"]],
    decision = "forbidden",
    justification = "git-policy: no force-push; ask the user to do it themselves",
    match = [["git", "push", "--force", "origin", "main"]],
    not_match = [["git", "push", "origin", "main"]],
)
RULESEOF
)"
  if [ -e "$file" ] && [ "$(cat "$file")" = "$content" ]; then
    log "Codex rules already current in $file"
    return 0
  fi
  mkdir -p "$CODEX_HOME/rules"
  printf '%s\n' "$content" > "$file"
  record_link "codex-rules" "$file"
  log "Wrote $file — restart Codex to load it"
}

# install_global_hooks — JSON-merge the owned hooks into $CODEX_HOME/hooks.json
# under UserPromptSubmit only, with absolute store commands, deduped by exact
# command match. Preserves the gk and code-review-graph entries that already
# live there. Backs the file up once (as <file>.smooth-devex-<UTC datetime>) so
# --uninstall can restore the pre-install state. UserPromptSubmit is a
# matcher-ignored event per the Codex hooks docs, so the new chunk omits matcher.
install_global_hooks() {
  local hooks_file="$CODEX_HOME/hooks.json"
  local source_hooks="$INSTALL_TMP/repo/.agents/hooks"
  local enabled_cmds="" disabled_cmds="" name
  if [ -d "$source_hooks" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if [ -e "$source_hooks/$name" ]; then
        copy_wet "$source_hooks/$name" "$GLB_ROOT/hooks/$name"
        case "$name" in
          *.sh) [ -x "$source_hooks/$name" ] && chmod +x "$GLB_ROOT/hooks/$name" ;;
        esac
        log "Stored global hook $name"
      else
        log "WARNING: hook $name not found in repo — not stored"
      fi
    done <<< "$HOOKS_ON"
  else
    log "No .agents/hooks in source — nothing to install for global hooks"
    return 0
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -f "$GLB_ROOT/hooks/$name" ]; then
      enabled_cmds="$enabled_cmds$GLB_ROOT/hooks/$name"$'\n'
    else
      log "WARNING: owned hook $name not in store — not registered"
    fi
  done <<< "$HOOKS_ON"
  # A disabled hook's command is removed from hooks.json (it stays in the store), so
  # the flag turns the hook off rather than only stopping updates.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    disabled_cmds="$disabled_cmds$GLB_ROOT/hooks/$name"$'\n'
  done <<< "$HOOKS_OFF"
  # Codex off: register nothing, and remove every command under the store's hooks dir. They
  # are matched by that prefix, so a hook that is no longer owned goes too.
  local purge_prefix=""
  if [ "$HARNESS_CODEX" != "1" ]; then
    enabled_cmds=""
    purge_prefix="$GLB_ROOT/hooks/"
  fi
  if [ -z "$enabled_cmds" ] && [ -z "$disabled_cmds" ] && [ -z "$purge_prefix" ]; then
    log "No owned hooks to register globally"
    return 0
  fi
  local result added removed backup
  result="$(python3 - "$hooks_file" "$enabled_cmds" "$disabled_cmds" "$purge_prefix" <<'PYEOF'
import json, sys, os, shutil, glob
from datetime import datetime, timezone
path = sys.argv[1]
cmds = [c for c in sys.argv[2].splitlines() if c]
disabled = set(c for c in sys.argv[3].splitlines() if c)
purge_prefix = sys.argv[4]


def is_dropped(entry):
    if not isinstance(entry, dict):
        return False
    command = entry.get('command')
    if command in disabled:
        return True
    return bool(purge_prefix) and isinstance(command, str) and command.startswith(purge_prefix)


data = {}
if os.path.exists(path):
    raw = open(path, encoding='utf-8').read()
    if raw.strip():
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            sys.stderr.write('install-skills: %s is not valid JSON (%s); fix or delete it\n' % (path, exc))
            raise SystemExit(2)
hooks = data.setdefault('hooks', {})
if not isinstance(hooks, dict):
    hooks = {}
    data['hooks'] = hooks
ups = hooks.setdefault('UserPromptSubmit', [])
if not isinstance(ups, list):
    ups = []
    hooks['UserPromptSubmit'] = ups
# Drop the commands of disabled hooks. Only a group this empties is dropped; a group
# the operator shares with other commands keeps them.
removed = 0
pruned = []
for group in ups:
    if isinstance(group, dict) and isinstance(group.get('hooks'), list):
        keep = [h for h in group['hooks'] if not is_dropped(h)]
        dropped = len(group['hooks']) - len(keep)
        if dropped:
            removed += dropped
            if not keep:
                continue
            group = dict(group, hooks=keep)
    pruned.append(group)
ups = pruned
hooks['UserPromptSubmit'] = ups
existing = set()
for group in ups:
    if isinstance(group, dict) and isinstance(group.get('hooks'), list):
        for h in group['hooks']:
            if isinstance(h, dict) and 'command' in h:
                existing.add(h['command'])
new = [{'command': c, 'type': 'command'} for c in cmds if c not in existing]
# Snapshot a pre-existing file we are about to modify, as
# <file>.smooth-devex-<UTC YYYYMMDD-HHMMSS>, once: on a re-run the dedupe above
# makes new empty, so we never snapshot our own earlier hooks (which would make
# --uninstall restore our own change). A file we created from nothing has no
# pre-install state to capture and is left for surgical removal at uninstall.
backup_path = ''
changed = bool(new) or removed > 0
if changed and os.path.exists(path) and not glob.glob(path + '.smooth-devex-[0-9]*'):
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
    backup_path = path + '.smooth-devex-' + stamp
    shutil.copyfile(path, backup_path)
if changed:
    if new:
        # UserPromptSubmit is a matcher-ignored event, so the new chunk omits matcher.
        ups.append({'hooks': new})
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
print('%s\t%s\t%s' % (len(new), removed, backup_path))
PYEOF
)"
  IFS=$'\t' read -r added removed backup <<< "$result"
  if [ -n "${backup:-}" ]; then
    log "Backed up $hooks_file -> $backup"
  fi
  if [ "${added:-0}" -gt 0 ] || [ "${removed:-0}" -gt 0 ]; then
    record_link "hooks-merge" "$hooks_file" "$backup"
    if [ "${added:-0}" -gt 0 ]; then
      log "Registered $added owned hook(s) in $hooks_file"
    fi
    if [ "${removed:-0}" -gt 0 ]; then
      log "Unregistered $removed disabled hook(s) from $hooks_file"
    fi
  else
    log "Owned hooks already match the installed set in $hooks_file"
  fi
  if [ "$HARNESS_CODEX" = "1" ]; then
    log "Trust the newly registered Codex hooks with: /hooks"
  fi
}

# write_global_manifest SKILLS_JSON RULES_JSON HOOKS_JSON HARNESSES_JSON — write the
# global manifest. SKILLS_JSON is the reconciled skills document (or an existing one for a
# rules/hooks-only run); RULES_JSON / HOOKS_JSON are the reconciled per-item arrays
# for a category this run covered, or empty to carry the existing ones forward;
# HARNESSES_JSON is the reconciled harnesses object. 'updated' is refreshed and the links
# array is attached, each symlink record carrying `enabled` (is it on disk right now).
write_global_manifest() {
  local skills_json="$1" rules_json="${2:-}" hooks_json="${3:-}" harnesses_json="${4:-}"
  local links_json
  links_json="$(python3 -c '
import json, sys
links = []
for line in sys.argv[1:]:
    if line == "":
        continue
    parts = line.split("\t")
    entry = {"type": parts[0], "path": parts[1]}
    if len(parts) > 2 and parts[2]:
        entry["detail"] = parts[2]
    links.append(entry)
print(json.dumps(links))
' ${LINKS[@]+"${LINKS[@]}"})" || links_json="[]"
  python3 - "$GLOBAL_MANIFEST" "$skills_json" "$links_json" "$rules_json" "$hooks_json" "$harnesses_json" <<'PYEOF'
import json, sys, os
from datetime import datetime, timezone
path, skills_json, links_json = sys.argv[1], sys.argv[2], sys.argv[3]
rules_json, hooks_json, harnesses_json = sys.argv[4], sys.argv[5], sys.argv[6]
SYMLINK_TYPES = ('skill-link', 'claude-skill', 'opencode-skill', 'claude-rule')
KEY_ORDER = ('updated', 'decisions_enabled', 'harnesses', 'skills', 'rules', 'hooks', 'links')
new_links = json.loads(links_json)
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
# The existing manifest carries the links[] recorded on earlier runs. A re-run
# where nothing new was linked must not wipe that history (uninstall reads it),
# so links are merged: existing entries keep their order, new ones upsert in
# place by (type, path). json_read already rejected a corrupt manifest upstream.
existing = {}
if os.path.exists(path):
    try:
        with open(path, encoding='utf-8') as f:
            raw = f.read()
        if raw.strip():
            loaded = json.loads(raw)
            if isinstance(loaded, dict):
                existing = loaded
    except json.JSONDecodeError:
        existing = {}
data = {}
if skills_json:
    try:
        data = json.loads(skills_json)
    except json.JSONDecodeError:
        data = {}
    if not isinstance(data, dict):
        data = {}
else:
    data = existing
if 'skills' not in data:
    data['skills'] = existing.get('skills', [])
if 'decisions_enabled' not in data:
    data['decisions_enabled'] = existing.get('decisions_enabled', False)
# A category this run covered brings its reconciled list; one it did not keeps the
# list the previous run recorded (absent until that category has run once).
for key, raw in (('rules', rules_json), ('hooks', hooks_json)):
    if raw:
        data[key] = json.loads(raw)
    elif key not in data and key in existing:
        data[key] = existing[key]
if harnesses_json:
    data['harnesses'] = json.loads(harnesses_json)
elif 'harnesses' not in data and 'harnesses' in existing:
    data['harnesses'] = existing['harnesses']
merged = []
seen = set()
for link in existing.get('links', []):
    merged.append(link)
    seen.add((link.get('type'), link.get('path')))
for link in new_links:
    key = (link.get('type'), link.get('path'))
    if key in seen:
        for i, m in enumerate(merged):
            if (m.get('type'), m.get('path')) == key:
                # A re-run that edits the same file again (a rule or hook flipped off)
                # snapshots nothing, because the first run already did. Its record has
                # no detail, and must not overwrite the one that points at the snapshot
                # --uninstall restores from.
                if 'detail' not in link and 'detail' in m:
                    link = dict(link, detail=m['detail'])
                merged[i] = link
                break
    else:
        merged.append(link)
        seen.add(key)
# `enabled` is a status the installer recomputes every run, not a control: true exactly when the
# symlink is on disk and points where the record says. A link the installer unwired (its item or
# its harness turned off) stays recorded, as enabled:false, so --uninstall and a re-enable still
# know about it. Config-edit records (agents-import, hooks-merge, ...) carry no such field.
for link in merged:
    if link.get('type') in SYMLINK_TYPES:
        link_path = link.get('path', '')
        link['enabled'] = os.path.islink(link_path) and os.readlink(link_path) == link.get('detail')
data['updated'] = now
data['links'] = merged
data = dict([(k, data[k]) for k in KEY_ORDER if k in data] + [(k, v) for k, v in data.items() if k not in KEY_ORDER])
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF
  log "Wrote global manifest $GLOBAL_MANIFEST"
}

# run_global_install — the -g entry point: build the central store, wire skills,
# rules/instructions and hooks into Codex, and write the manifest last.
run_global_install() {
  local existing_json new_json
  ensure_global_store
  # The wiring below writes into Codex's config dir; ensure it exists even on a
  # bare -g -h / -g -r run against a fresh machine (Codex normally creates it).
  mkdir -p "$CODEX_HOME"
  clone_source

  # A corrupt global manifest is a hard error in every category run, never a
  # silent reset from defaults — same rule as the per-repo manifest.
  existing_json="$(json_read "$GLOBAL_MANIFEST")" \
    || die "cannot read $GLOBAL_MANIFEST — fix or delete it, then re-run"

  # Which harnesses to wire into. Resolved whatever categories this run covers: a harness the
  # manifest has not seen joins as on, and an off one is not installed into and is cleaned of
  # anything this installer put there.
  GLB_HARNESSES_JSON="$(reconcile_harnesses "$existing_json")"
  HARNESS_CLAUDE="$(harness_flag "$GLB_HARNESSES_JSON" claude-code)"
  HARNESS_CODEX="$(harness_flag "$GLB_HARNESSES_JSON" codex)"
  HARNESS_OPENCODE="$(harness_flag "$GLB_HARNESSES_JSON" opencode)"
  if [ "$HARNESS_CLAUDE" != "1" ]; then log "Harness claude-code is off — not installing, removing what is wired"; fi
  if [ "$HARNESS_CODEX" != "1" ]; then log "Harness codex is off — not installing, removing what is wired"; fi
  if [ "$HARNESS_OPENCODE" != "1" ]; then log "Harness opencode is off — not installing, removing what is wired"; fi

  # Rules and hooks carry the same per-item installed flag skills do. Only a category
  # this run covers is reconciled; the others keep what the manifest already says.
  if [ "$DO_RULES" = "1" ]; then
    GLB_RULES_JSON="$(reconcile_global_items rules "$existing_json" "${OWNED_RULES[@]}")"
    RULES_ON="$(global_items_flagged "$GLB_RULES_JSON" true)"
    RULES_OFF="$(global_items_flagged "$GLB_RULES_JSON" false)"
  fi
  if [ "$DO_HOOKS" = "1" ]; then
    GLB_HOOKS_JSON="$(reconcile_global_items hooks "$existing_json" "${OWNED_HOOKS[@]}")"
    HOOKS_ON="$(global_items_flagged "$GLB_HOOKS_JSON" true)"
    HOOKS_OFF="$(global_items_flagged "$GLB_HOOKS_JSON" false)"
  fi

  if [ "$DO_SKILLS" = "1" ]; then
    local existing_decisions
    existing_decisions="$(check_decisions_enabled "$existing_json")"
    if [ "$DO_DECISIONS" = "1" ]; then
      DECISIONS_ENABLED="true"
      log "Decisions enabled via -d"
    elif [ "$existing_decisions" != "missing" ]; then
      DECISIONS_ENABLED="$existing_decisions"
      log "Decisions preference saved ($DECISIONS_ENABLED) — skipping prompt"
    else
      prompt_decisions
    fi
    if [ "$DECISIONS_ENABLED" = "true" ]; then
      write_decisions_env
    fi

    log "Syncing global installation.json…"
    new_json="$(build_installation_json "$GLB_ROOT/skills" "$existing_json" \
      "$(list_skills "$INSTALL_TMP/repo/.agents/skills" | python3 -c "
import json, sys
print(json.dumps(sorted(line.strip() for line in sys.stdin if line.strip())))
")" "$DECISIONS_ENABLED")"

    log "Storing and wiring global skills…"
    install_global_skills "$new_json"
    log "Registering global OpenCode commands…"
    install_global_opencode "$new_json"
    log "Registering global Claude skills…"
    install_global_claude "$new_json"
  fi

  if [ "$DO_RULES" = "1" ]; then
    log "Storing global rules…"
    install_global_rules
    log "Writing global instructions…"
    install_global_instructions
    log "Wiring Claude global rules…"
    install_global_claude_rules
    log "Adding global rules to OpenCode instructions…"
    install_global_opencode_config
    log "Writing Codex command-approval rules…"
    install_global_codex_rules
  fi

  if [ "$DO_HOOKS" = "1" ]; then
    log "Registering global hooks…"
    install_global_hooks
  fi

  log "Writing global manifest…"
  if [ "$DO_SKILLS" = "1" ]; then
    write_global_manifest "$new_json" "$GLB_RULES_JSON" "$GLB_HOOKS_JSON" "$GLB_HARNESSES_JSON"
  else
    write_global_manifest "$existing_json" "$GLB_RULES_JSON" "$GLB_HOOKS_JSON" "$GLB_HARNESSES_JSON"
  fi
}

# unglobalize — remove only what the manifest recorded, and restore the hooks
# backup if the installer made one. Leaves Codex's .system/, the gk hooks, and
# the operator's RTK @-import line alone. The store itself is left in place; an
# operator who wants it gone removes ~/.smooth-ai-devex.
unglobalize() {
  [ -f "$GLOBAL_MANIFEST" ] || { log "No global install manifest at $GLOBAL_MANIFEST — nothing to uninstall"; return 0; }
  python3 - "$GLB_ROOT" "$GLOBAL_MANIFEST" <<'PYEOF'
import json, sys, os, shutil, datetime
glb_root, manifest_path = sys.argv[1:3]
data = json.load(open(manifest_path, encoding='utf-8'))
links = data.get('links', [])
for link in links:
    typ = link.get('type')
    path = link.get('path', '')
    detail = link.get('detail', '')
    # Before uninstall restores or removes a content file, snapshot its *current*
    # state (post-install, possibly operator-edited) as a smooth-devex-uninstall-
    # <stamp> backup so the removal is reversible and post-install edits are not
    # lost. Symlinks (skill-link / opencode-command) are excluded: their content
    # lives in the preserved store, so removing the link loses nothing.
    if typ in ('agents-import', 'hooks-merge', 'profile-edit') and os.path.exists(path) and os.path.isfile(path):
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')
        bak = path + '.smooth-devex-uninstall-' + stamp
        shutil.copyfile(path, bak)
        print('snapshotted pre-uninstall', bak)
    if typ in ('skill-link', 'opencode-command', 'opencode-commands-link', 'opencode-skill', 'claude-skill', 'claude-rule'):
        if os.path.islink(path) and os.readlink(path) == detail:
            os.unlink(path)
            print('removed link', path)
    elif typ == 'opencode-config':
        if detail and os.path.exists(detail):
            with open(detail, 'rb') as f:
                content = f.read()
            with open(path, 'wb') as f:
                f.write(content)
            os.remove(detail)
            print('restored opencode config backup', path)
        elif os.path.exists(path):
            # No snapshot: drop the store-rule instruction globs we added.
            with open(path, encoding='utf-8') as f:
                data3 = json.load(f)
            inst = data3.get('instructions', [])
            data3['instructions'] = [g for g in inst if not g.startswith(glb_root + '/rules/')]
            if not data3['instructions']:
                data3.pop('instructions', None)
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(data3, f, indent=2)
                f.write('\n')
            print('removed opencode instructions', path)
    elif typ == 'profile-edit':
        if detail and os.path.exists(detail):
            # Restore the pre-append profile snapshot, then retire it so a later
            # reinstall snapshots the operator's current content fresh rather than
            # reusing an obsolete backup that leaves the file indistinguishable
            # from an installer-created one.
            with open(detail, 'rb') as f:
                content = f.read()
            with open(path, 'wb') as f:
                f.write(content)
            os.remove(detail)
            print('restored profile backup', path)
        elif os.path.exists(path):
            # No snapshot: drop the marker-guarded decision env block we appended.
            with open(path, encoding='utf-8') as f:
                lines = f.readlines()
            out = []
            i = 0
            while i < len(lines):
                if 'Smooth DevEx — AI Decision Validation' in lines[i]:
                    if out and out[-1].strip() == '':
                        out.pop()
                    i += 1
                    while i < len(lines) and ('SMOOTH_DEVEX_DECISIONS' in lines[i] or lines[i].strip() == ''):
                        i += 1
                    continue
                out.append(lines[i])
                i += 1
            with open(path, 'w', encoding='utf-8') as f:
                f.writelines(out)
            print('removed decision env block', path)
    elif typ == 'agents-import':
        if detail and os.path.exists(detail):
            # Restore the pre-append snapshot, which is strictly the operator's
            # earlier content (never our own append), then retire it so a later
            # reinstall snapshots the operator's current content fresh.
            with open(detail, 'rb') as f:
                content = f.read()
            with open(path, 'wb') as f:
                f.write(content)
            os.remove(detail)
            print('restored agents import backup', path)
        elif os.path.exists(path):
            # No snapshot means the installer created the file from nothing, so
            # removing it is the exact inverse of the install — not a splice that
            # leaves behind an empty AGENTS.md with our RTK header.
            os.remove(path)
            print('removed agents import file created by installer', path)
    elif typ == 'codex-rules':
        # A file this installer wrote, never a snapshot: remove it only while it still carries
        # our header, so a file the operator replaced it with is left alone.
        if os.path.isfile(path):
            with open(path, encoding='utf-8') as f:
                first = f.readline()
            if 'installer-owned-global-rules' in first:
                os.remove(path)
                print('removed codex rules', path)
    elif typ == 'hooks-merge':
        if detail and os.path.exists(detail):
            with open(detail, 'rb') as f:
                content = f.read()
            with open(path, 'wb') as f:
                f.write(content)
            os.remove(detail)
            print('restored hooks backup', path)
        elif os.path.exists(path):
            with open(path, encoding='utf-8') as f:
                data2 = json.load(f)
            hooks2 = data2.setdefault('hooks', {})
            ups2 = hooks2.get('UserPromptSubmit', [])
            kept = []
            for group in ups2:
                cmds = [h.get('command', '') for h in group.get('hooks', []) if isinstance(h, dict)]
                if cmds and all(c.startswith(glb_root + '/hooks/') for c in cmds):
                    continue
                kept.append(group)
            hooks2['UserPromptSubmit'] = kept
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(data2, f, indent=2)
                f.write('\n')
            print('removed owned hooks', path)
PYEOF
  log "Uninstalled global install — store left at $GLB_ROOT (remove it to reclaim space)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_categories "$@"

  if [ "$DO_UNINSTALL" = "1" ]; then
    [ "$DO_GLOBAL" = "1" ] || die "--uninstall only applies to the global install — use: install-skills -g --uninstall"
    if [ -n "${SKILLS_ROOT:-}" ]; then
      die "-g cannot be combined with SKILLS_ROOT — the global install owns $HOME/.smooth-ai-devex"
    fi
    unglobalize
    log "Done."
    return 0
  fi

  if [ "$DO_GLOBAL" = "1" ]; then
    if [ -n "${SKILLS_ROOT:-}" ]; then
      die "-g cannot be combined with SKILLS_ROOT — use the per-repo install (no -g) or unset SKILLS_ROOT"
    fi
    run_global_install
    log "Done."
    return 0
  fi

  local agent_root skills_root shared_dir json_path legacy_json existing_json new_json

  if [ -n "${SKILLS_ROOT:-}" ]; then
    [ -d "$SKILLS_ROOT" ] || die "SKILLS_ROOT '$SKILLS_ROOT' does not exist"
    # Resolve to absolute first: a relative SKILLS_ROOT (e.g. `.` from inside the skills dir)
    # would make dirname return the skills dir itself, nesting state inside skills/ and
    # misplacing rules. The parent of the absolute path is the agent root, whatever it is named.
    skills_root="$(cd "$SKILLS_ROOT" && pwd -P)"
    # The parent of an explicitly forced skills root counts as the agent root, whatever it
    # is named: the shared dir is always a sibling of the skills dir, never inside it.
    agent_root="$(cd "$(dirname "$skills_root")" && pwd -P)"
  else
    agent_root="$(find_agent_root)" \
      || die "no agent directory found — expected one of .agents, .claude, .codex (create one, or set SKILLS_ROOT)"
    skills_root="$agent_root/skills"
    if [ "$DO_SKILLS" = "1" ]; then
      mkdir -p "$skills_root"
    fi
  fi

  shared_dir="$agent_root/_smooth-devex-shared"
  json_path="$shared_dir/installation.json"

  log "Agent root: $agent_root"
  [ "$DO_SKILLS" = "1" ] && log "Skills root: $skills_root"

  clone_source
  ensure_consumer_symlink_support "$agent_root"

  if [ "$DO_SKILLS" = "1" ]; then
    mkdir -p "$shared_dir"

    # Fresh start across the layout move: a manifest at the legacy location inside the skills
    # root is ignored, not migrated. Migrating would silently re-apply flags the operator may
    # have set under a different contract; the notice tells them where to look.
    legacy_json="$skills_root/_smooth-devex-shared/installation.json"
    if [ "$legacy_json" != "$json_path" ] && [ -f "$legacy_json" ]; then
      log "Ignoring legacy manifest at $legacy_json — delete it to silence this notice"
    fi

    # A non-zero status here is the corrupt-manifest case; json_read has already said why.
    # Swallowing it would rebuild the manifest from defaults and re-enable skills the operator
    # had switched off.
    existing_json="$(json_read "$json_path")" \
      || die "cannot read $json_path — fix or delete it, then re-run"

    # Decision validation opt-in. Prompt only when the preferences entry is missing and -d is not
    # given — a saved true or false is reused without re-asking (idempotent). -d forces decisions on
    # (no prompt, overrides a saved false). The prompt reads from /dev/tty, so it is asked even on a
    # piped `curl | bash` run; falls back to disabled when no terminal.
    local existing_decisions
    existing_decisions="$(check_decisions_enabled "$existing_json")"
    if [ "$DO_DECISIONS" = "1" ]; then
      DECISIONS_ENABLED="true"
      log "Decisions enabled via -d"
    elif [ "$existing_decisions" != "missing" ]; then
      DECISIONS_ENABLED="$existing_decisions"
      log "Decisions preference saved ($DECISIONS_ENABLED) — skipping prompt"
    else
      prompt_decisions
    fi
    if [ "$DECISIONS_ENABLED" = "true" ]; then
      write_decisions_env
    fi

    log "Syncing installation.json…"
    new_json="$(build_installation_json "$skills_root" "$existing_json" \
      "$(list_skills "$INSTALL_TMP/repo/.agents/skills" | python3 -c "
import json, sys
print(json.dumps(sorted(line.strip() for line in sys.stdin if line.strip())))
")" "$DECISIONS_ENABLED")"

    log "Updating installed skills…"
    update_installed_skills "$new_json" "$skills_root" "$agent_root" "$shared_dir"

    # Written last: the shared-folder refresh happens during the update, and the manifest lives inside it.
    json_write "$json_path" "$new_json"
  fi

  if [ "$DO_RULES" = "1" ]; then
    log "Updating owned rules…"
    install_rules "$agent_root"
  fi

  if [ "$DO_HOOKS" = "1" ]; then
    log "Updating owned hooks…"
    install_hooks "$agent_root"
  fi

  log "Done."
}

# Test-only entry point. SKILLS_TEST_SKIP_RECONCILE=1 lets the harness exercise the update-loop guard
# directly with a hand-crafted manifest: it skips the manifest rebuild AND the clone step. The
# harness is responsible for setting INSTALL_TMP/repo/.agents/skills/ with whatever source it wants
# the test to see; the installer does NOT mirror from disk (mirroring would defeat the test by
# making disk and source identical for the unowned skill). Production installers never set this.
#
# The flag is needed because the reconcile step drops any unowned entries from the manifest BEFORE
# update runs, so a hand-edited manifest cannot reach the guard through the normal entry point. The
# direct path proves the guard is what catches the entry, not the reconcile.
main_skip_reconcile() {
  local skills_root="$SKILLS_ROOT"
  [ -d "$skills_root" ] || die "SKILLS_ROOT '$skills_root' does not exist (required for uninstall)"
  local agent_root shared_dir json_path existing_json
  agent_root="$(cd "$(dirname "$skills_root")" && pwd -P)"
  shared_dir="$agent_root/_smooth-devex-shared"
  json_path="$shared_dir/installation.json"
  existing_json="$(json_read "$json_path")" \
    || die "cannot read $json_path — fix or delete it, then re-run"
  # The test sets INSTALL_TMP externally so disk and source can differ; verify it exists.
  [ -n "${INSTALL_TMP:-}" ] || die "INSTALL_TMP must be set externally for skip-reconcile mode"
  [ -d "$INSTALL_TMP/repo/.agents/skills" ] || die "INSTALL_TMP/repo/.agents/skills must exist externally"
  trap 'rm -rf "${INSTALL_TMP:-}"' EXIT INT TERM HUP
  log "Updating installed skills (skip-reconcile mode)…"
  update_installed_skills "$existing_json" "$skills_root" "$agent_root" "$shared_dir"
  log "Done. State (untouched): $json_path"
}

if [ "${SKILLS_TEST_SKIP_RECONCILE:-}" = "1" ]; then
  main_skip_reconcile
else
  main "$@"
fi
