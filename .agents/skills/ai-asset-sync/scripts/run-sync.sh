#!/usr/bin/env bash
# ai-asset-sync — single CI entrypoint (two packagings, one implementation).
#
# Resolves `.github/assets/ai-sync.yml`, short-circuits unchanged lockfile SHAs,
# AI-merges or overwrites changed entries, and opens one chore PR when the tree
# differs. Behaviour changes land HERE, not in the workflow/action wrappers.
#
# Usage:
#   run-sync.sh [--manifest PATH] [--lockfile PATH] [--dry-run]
#               [--entries-filter LIST] [--model ID] [--no-pr] [--repo-root DIR]
#
# Env (see AGENTS.md):
#   OPENCODE_AI_SYNC_PROVIDER / _MODEL_PRIMARY / _MODEL_SECONDARY / _CONFIG
#   OPENCODE_CLI_VERSION, OPENCODE_<PROVIDER>_API_KEY, GITHUB_TOKEN
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${SKILL_DIR}/scripts/lib"
PARSE_PY="${LIB_DIR}/parse_manifest.py"

MANIFEST_PATH="${AI_ASSET_SYNC_MANIFEST:-.github/assets/ai-sync.yml}"
LOCKFILE_PATH="${AI_ASSET_SYNC_LOCKFILE:-.github/assets/ai-sync.lock}"
DRY_RUN=0
NO_PR=0
ENTRIES_FILTER="${AI_ASSET_SYNC_ENTRIES_FILTER:-}"
MODEL_OVERRIDE="${AI_ASSET_SYNC_MODEL:-}"
REPO_ROOT="${AI_ASSET_SYNC_REPO_ROOT:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) MANIFEST_PATH="$2"; shift 2 ;;
    --lockfile) LOCKFILE_PATH="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-pr) NO_PR=1; shift ;;
    --entries-filter) ENTRIES_FILTER="$2"; shift 2 ;;
    --model) MODEL_OVERRIDE="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$REPO_ROOT"

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

need_cmd python3
need_cmd git

[ -f "$MANIFEST_PATH" ] || die "manifest not found: $MANIFEST_PATH"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-asset-sync.XXXXXX")"
REPORT_DIR="${WORKDIR}/report"
mkdir -p "$REPORT_DIR"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

python3 "$PARSE_PY" manifest "$MANIFEST_PATH" >"${REPORT_DIR}/manifest.json" \
  || die "failed to parse manifest"
if [ -f "$LOCKFILE_PATH" ]; then
  python3 "$PARSE_PY" lockfile "$LOCKFILE_PATH" >"${REPORT_DIR}/lock.json" \
    || die "failed to parse lockfile"
else
  printf '%s\n' '{"version":1,"entries":[]}' >"${REPORT_DIR}/lock.json"
fi

write_summary_empty() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## AI asset sync"
      echo ""
      echo "No entries to process."
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

export ENTRIES_FILTER
python3 - "${REPORT_DIR}/manifest.json" <<'PY'
import json, os, sys
path = sys.argv[1]
data = json.loads(open(path, encoding="utf-8").read())
filt = [p.strip() for p in os.environ.get("ENTRIES_FILTER", "").replace("\n", ",").split(",") if p.strip()]
if filt:
    data["entries"] = [
        e for e in data["entries"]
        if any(f in (e["source"] + " " + e["path"]) for f in filt)
    ]
open(path, "w", encoding="utf-8").write(json.dumps(data))
PY

ENTRY_COUNT="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1], encoding="utf-8"))["entries"]))' "${REPORT_DIR}/manifest.json")"
if [ "$ENTRY_COUNT" -eq 0 ]; then
  log "no entries to process"
  write_summary_empty
  exit 0
fi

resolve_sha() {
  local owner="$1" repo="$2" ref="$3"
  need_cmd gh
  export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  gh api "repos/${owner}/${repo}/commits/${ref}" --jq .sha
}

fetch_source() {
  local owner="$1" repo="$2" sha="$3" dest="$4"
  need_cmd gh
  export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  mkdir -p "$dest"
  # gh uses GH_TOKEN/GITHUB_TOKEN from the environment; the value never appears
  # on the command line (skill-secret-handling).
  if ! gh repo clone "${owner}/${repo}" "$dest" -- --filter=blob:none --depth 1 >/dev/null 2>&1; then
    die "clone failed: ${owner}/${repo}"
  fi
  if ! git -C "$dest" fetch --filter=blob:none --depth 1 origin "$sha" >/dev/null 2>&1; then
    git -C "$dest" fetch --depth 1 origin "$sha" >/dev/null 2>&1 \
      || die "fetch sha failed: ${owner}/${repo}@${sha}"
  fi
  git -C "$dest" checkout --detach "$sha" >/dev/null 2>&1 \
    || die "checkout failed: ${owner}/${repo}@${sha}"
}

copy_tree() {
  local src="$1" dest="$2"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    return
  fi
  [ -d "$src" ] || die "remote path missing after fetch: $src"
  command -v rsync >/dev/null 2>&1 || die "rsync required to sync directory ${src}"
  mkdir -p "$dest"
  rsync -a --delete "$src"/ "$dest"/
}

provider_id_for() {
  case "$1" in
    GEMINI) echo gemini ;;
    COPILOT) echo github-copilot ;;
    OPENAI) echo openai ;;
    ANTHROPIC) echo anthropic ;;
    OPENCODE-GO-OPENAI) echo go-openai ;;
    OPENCODE-GO-ANTHROPIC) echo go-anthropic ;;
    OPEN_ROUTER) echo openrouter ;;
    *) die "unknown OPENCODE_AI_SYNC_PROVIDER='$1'" ;;
  esac
}

key_var_for() {
  case "$1" in
    GEMINI) echo OPENCODE_GEMINI_API_KEY ;;
    COPILOT) echo OPENCODE_COPILOT_API_KEY ;;
    OPENAI) echo OPENCODE_OPENAI_API_KEY ;;
    ANTHROPIC) echo OPENCODE_ANTHROPIC_API_KEY ;;
    OPENCODE-GO-OPENAI) echo OPENCODE_GO_OPENAI_API_KEY ;;
    OPENCODE-GO-ANTHROPIC) echo OPENCODE_GO_ANTHROPIC_API_KEY ;;
    OPEN_ROUTER) echo OPENCODE_OPENROUTER_API_KEY ;;
  esac
}

OPENCODE_READY=0
ensure_opencode() {
  if [ "${OPENCODE_READY}" = "1" ]; then
    return
  fi
  bash "${LIB_DIR}/install-opencode.sh"
  local cfg="${OPENCODE_AI_SYNC_CONFIG:-}"
  if [ -n "$cfg" ]; then
    [ -f "$cfg" ] || die "OPENCODE_AI_SYNC_CONFIG not a file: $cfg"
    export OPENCODE_CONFIG="$cfg"
  else
    export OPENCODE_CONFIG="${SKILL_DIR}/assets/opencode.json"
  fi
  export OPENCODE_DISABLE_CLAUDE_CODE="${OPENCODE_DISABLE_CLAUDE_CODE:-1}"
  OPENCODE_READY=1
}

extract_sidecar() {
  local raw="$1" dest="$2" source="$3"
  python3 - "$raw" "$dest" "$source" <<'PY'
import json, re, sys
raw_path, dest, source = sys.argv[1:4]
text = open(raw_path, encoding="utf-8").read()
obj = None
# Prefer a fenced json block, else first {...} object.
fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.S)
blob = fence.group(1) if fence else None
if blob is None:
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end > start:
        blob = text[start : end + 1]
if blob:
    try:
        obj = json.loads(blob)
    except json.JSONDecodeError:
        obj = None
if not isinstance(obj, dict):
    obj = {
        "source": source,
        "action": "skipped-blocker",
        "conflicts": [],
        "gaps": [],
        "issues": ["model output was not valid sidecar JSON"],
        "blockers": ["unparseable model output; local tree left untouched"],
        "notes": "parser fallback",
    }
action = obj.get("action") or "no-op"
if action not in {"applied", "merged", "skipped-blocker", "no-op"}:
    action = "skipped-blocker"
    obj["blockers"] = list(obj.get("blockers") or []) + [f"invalid action '{obj.get('action')}'"]
obj["action"] = action
obj["source"] = source
for key in ("conflicts", "gaps", "issues", "blockers"):
    val = obj.get(key) or []
    if isinstance(val, str):
        val = [val]
    obj[key] = [str(x) for x in val]
obj["notes"] = str(obj.get("notes") or "")
open(dest, "w", encoding="utf-8").write(json.dumps(obj))
PY
}

invoke_ai_merge() {
  local local_path="$1" remote_path="$2" source="$3" sidecar="$4" base_note="$5"
  ensure_opencode
  local provider
  provider="$(printf '%s' "${OPENCODE_AI_SYNC_PROVIDER:-GEMINI}" | tr '[:lower:]' '[:upper:]')"
  local pid key_var
  pid="$(provider_id_for "$provider")"
  key_var="$(key_var_for "$provider")"
  [ -n "${!key_var:-}" ] || die "$provider selected but $key_var is empty/unset"
  local primary secondary
  primary="${MODEL_OVERRIDE:-${OPENCODE_AI_SYNC_MODEL_PRIMARY:-gemini-3.1-pro-preview}}"
  secondary="${OPENCODE_AI_SYNC_MODEL_SECONDARY:-gemini-2.5-pro}"
  local prompt="${WORKDIR}/prompt.md"
  cat >"$prompt" <<EOF
You are an AI developer-experience expert reconciling an upstream AI asset with the consumer repo's local copy.

Source: ${source}
Local path (consumer, write here if merging): ${local_path}
Remote path (read-only upstream snapshot): ${remote_path}
${base_note}

Rules:
- Read local and remote trees before deciding.
- If local is absent or identical in intent to remote with no meaningful local adaptation, copy remote onto local (action: applied).
- If local has adaptations that still compose with upstream, write a merged result to the local path preserving local intent and taking upstream fixes (action: merged).
- If divergence is a blocker (heavy rewrite, incompatible contract, unresolved conflict), leave the local path UNTOUCHED (action: skipped-blocker).
- If upstream SHA changed but local is already equivalent or better, leave local UNTOUCHED (action: no-op).
- Never invent files outside the local path.
- Never print secrets or environment values.

When finished, print ONLY this JSON object (no markdown fence required):
{
  "source": "${source}",
  "action": "applied|merged|skipped-blocker|no-op",
  "conflicts": [],
  "gaps": [],
  "issues": [],
  "blockers": [],
  "notes": "one paragraph"
}
Arrays of strings. Empty arrays if none.
EOF
  local raw="${WORKDIR}/opencode.out"
  local rc=1
  set +e
  opencode run --agent sync --model "${pid}/${primary}" --format default --log-level WARN \
    <"$prompt" >"$raw" 2>"${WORKDIR}/opencode.err"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && [ -n "$secondary" ] && [ "$secondary" != "$primary" ]; then
    log "primary model failed; trying secondary ${secondary}"
    set +e
    opencode run --agent sync --model "${pid}/${secondary}" --format default --log-level WARN \
      <"$prompt" >"$raw" 2>"${WORKDIR}/opencode.err"
    rc=$?
    set -e
  fi
  extract_sidecar "$raw" "$sidecar" "$source"
}

RESULTS="${REPORT_DIR}/results.jsonl"
: >"$RESULTS"

export REPORT_DIR
python3 - "${REPORT_DIR}/manifest.json" "${REPORT_DIR}/lock.json" "${REPORT_DIR}/work-list.txt" <<'PY'
import json, sys
manifest = json.loads(open(sys.argv[1], encoding="utf-8").read())
lock = json.loads(open(sys.argv[2], encoding="utf-8").read())
idx = {e["source"]: e for e in lock.get("entries") or []}
lines = []
for i, e in enumerate(manifest["entries"]):
    locked = idx.get(e["source"], {})
    lines.append("\t".join([
        str(i),
        e["owner"],
        e["repo"],
        e["ref"],
        e["path"],
        e["source"],
        e["strategy"],
        locked.get("resolved_sha") or "",
    ]))
open(sys.argv[3], "w", encoding="utf-8").write("\n".join(lines) + ("\n" if lines else ""))
PY

CLONES="${WORKDIR}/clones"
mkdir -p "$CLONES"

append_result() {
  python3 - "$RESULTS" <<'PY'
import json, os, sys
row = json.loads(os.environ["AI_SYNC_ROW"])
open(sys.argv[1], "a", encoding="utf-8").write(json.dumps(row) + "\n")
PY
}

while IFS=$'\t' read -r idx owner repo ref path source strategy locked_sha; do
  [ -n "${source:-}" ] || continue
  log "==> ${source}"
  sha="$(resolve_sha "$owner" "$repo" "$ref")" || die "cannot resolve ${owner}/${repo}@${ref}"

  if [ -n "$locked_sha" ] && [ "$locked_sha" = "$sha" ]; then
    log "    lockfile SHA match (${sha:0:12}) — skip, no model"
    AI_SYNC_ROW="$(python3 -c 'import json,sys; print(json.dumps({"source":sys.argv[1],"action":"up-to-date","resolved_sha":sys.argv[2],"advance_lock":False,"conflicts":[],"gaps":[],"issues":[],"blockers":[],"notes":"lockfile SHA match"}))' "$source" "$sha")"
    export AI_SYNC_ROW
    append_result
    continue
  fi

  dest="${CLONES}/${idx}"
  fetch_source "$owner" "$repo" "$sha" "$dest"
  remote_asset="${dest}/${path}"
  local_asset="${REPO_ROOT}/${path}"

  if [ ! -e "$remote_asset" ]; then
    die "upstream path '${path}' does not exist in ${owner}/${repo}@${sha}"
  fi

  if [ ! -e "$local_asset" ] || [ "$strategy" = "overwrite" ]; then
    local_existed=0
    [ -e "$local_asset" ] && local_existed=1
    copy_tree "$remote_asset" "$local_asset"
    note="applied upstream without model (${strategy})"
    if [ "$local_existed" -eq 0 ]; then
      note="copied upstream onto absent local path"
    fi
    AI_SYNC_ROW="$(python3 -c 'import json,sys; print(json.dumps({"source":sys.argv[1],"action":"applied","resolved_sha":sys.argv[2],"advance_lock":True,"conflicts":[],"gaps":[],"issues":[],"blockers":[],"notes":sys.argv[3]}))' "$source" "$sha" "$note")"
    export AI_SYNC_ROW
    append_result
    continue
  fi

  sidecar="${REPORT_DIR}/sidecar-${idx}.json"
  snap="${WORKDIR}/local-snap-${idx}"
  if [ -d "$local_asset" ]; then
    cp -a "$local_asset" "$snap"
  else
    mkdir -p "$(dirname "$snap")"
    cp "$local_asset" "$snap"
  fi
  invoke_ai_merge "$local_asset" "$remote_asset" "$source" "$sidecar" "Lockfile previous SHA: ${locked_sha:-none}"
  action="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["action"])' "$sidecar")"
  if [ "$action" = "skipped-blocker" ] || [ "$action" = "no-op" ]; then
    rm -rf "$local_asset"
    mkdir -p "$(dirname "$local_asset")"
    if [ -d "$snap" ]; then
      cp -a "$snap" "$local_asset"
    else
      cp "$snap" "$local_asset"
    fi
  fi
  python3 - "$sidecar" "$sha" "$RESULTS" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1], encoding="utf-8").read())
data["resolved_sha"] = sys.argv[2]
data["advance_lock"] = data["action"] in {"applied", "merged"}
open(sys.argv[3], "a", encoding="utf-8").write(json.dumps(data) + "\n")
PY
done <"${REPORT_DIR}/work-list.txt"

python3 - "${REPORT_DIR}/manifest.json" "${LOCKFILE_PATH}" <<'PY' >"${REPORT_DIR}/watch-paths.txt"
import json, sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for e in manifest["entries"]:
    print(e["path"])
print(sys.argv[2])
PY
ANY_FILE_CHANGE=0
while IFS= read -r watch; do
  [ -n "$watch" ] || continue
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain -- "$watch")" ]; then
    ANY_FILE_CHANGE=1
    break
  fi
done <"${REPORT_DIR}/watch-paths.txt"

export PARSE_PY RESULTS
python3 - "${REPORT_DIR}/lock.json" "${REPORT_DIR}/manifest.json" "${RESULTS}" "${REPORT_DIR}/lock.next.yml" <<'PY'
import importlib.util, json, sys
from pathlib import Path
lock_path, manifest_path, results_path, out_path = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("pm", __import__("os").environ["PARSE_PY"])
pm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pm)
lock = json.loads(Path(lock_path).read_text(encoding="utf-8"))
idx = {e["source"]: e for e in lock.get("entries") or []}
results = []
text = Path(results_path).read_text(encoding="utf-8")
if text.strip():
    results = [json.loads(line) for line in text.splitlines() if line.strip()]
for row in results:
    if row.get("advance_lock"):
        idx[row["source"]] = {
            "source": row["source"],
            "resolved_sha": row["resolved_sha"],
            "synced_at": "",
        }
manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
ordered, seen = [], set()
for e in manifest["entries"]:
    src = e["source"]
    if src in idx:
        ordered.append(idx[src])
        seen.add(src)
for src, e in idx.items():
    if src not in seen:
        ordered.append(e)
Path(out_path).write_text(pm.dump_lockfile(ordered), encoding="utf-8")
PY

SHOULD_PR=0
if [ "$ANY_FILE_CHANGE" -eq 1 ]; then
  SHOULD_PR=1
  mkdir -p "$(dirname "$LOCKFILE_PATH")"
  cp "${REPORT_DIR}/lock.next.yml" "$LOCKFILE_PATH"
fi

python3 - "$RESULTS" "${REPORT_DIR}/summary.md" <<'PY'
import json, sys
from pathlib import Path
rows = []
text = Path(sys.argv[1]).read_text(encoding="utf-8")
if text.strip():
    rows = [json.loads(line) for line in text.splitlines() if line.strip()]
lines = ["## AI asset sync", ""]
if not rows:
    lines += ["No entries processed.", ""]
else:
    lines += ["| Source | Action | SHA |", "|---|---|---|"]
    for r in rows:
        sha = (r.get("resolved_sha") or "")[:12]
        lines.append(f"| `{r['source']}` | {r['action']} | `{sha}` |")
    lines.append("")
    for section, key in [("Conflicts", "conflicts"), ("Gaps", "gaps"), ("Issues", "issues"), ("Blockers", "blockers")]:
        items = []
        for r in rows:
            for item in r.get(key) or []:
                items.append(f"- `{r['source']}`: {item}")
        lines += [f"### {section}", "", "\n".join(items) if items else "_None._", ""]
Path(sys.argv[2]).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "${REPORT_DIR}/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
cat "${REPORT_DIR}/summary.md"

if [ "$DRY_RUN" -eq 1 ] || [ "$NO_PR" -eq 1 ]; then
  log "dry-run/no-pr: skipping PR (file changes=${ANY_FILE_CHANGE})"
  exit 0
fi

if [ "$SHOULD_PR" -ne 1 ]; then
  log "no file diff after analysis — no PR (lockfile left unchanged; will re-analyse next run)"
  exit 0
fi

need_cmd gh
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
DATETIME="$(date -u +%Y%m%d-%H%M)"
BRANCH="chore/ai-sync-${DATETIME}"
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo main)"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -b "$BRANCH"

# Stage manifest asset paths + lockfile only (not the whole workspace).
# The model may write files under those paths that are not in CHANGED_PATHS.
python3 - "${REPORT_DIR}/manifest.json" "${LOCKFILE_PATH}" "${REPORT_DIR}/stage-paths.txt" <<'PY'
import json, sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
lines = [e["path"] for e in manifest["entries"]]
lines.append(sys.argv[2])
Path(sys.argv[3]).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
while IFS= read -r p; do
  [ -n "$p" ] || continue
  git add -- "$p" 2>/dev/null || true
done <"${REPORT_DIR}/stage-paths.txt"

if git diff --cached --quiet; then
  log "nothing staged after add — no PR"
  exit 0
fi

git commit -m "chore: sync AI assets"

TEMPLATE="${REPO_ROOT}/.github/pull_request_template.md"
python3 - "$TEMPLATE" "${REPORT_DIR}/summary.md" "${REPORT_DIR}/pr-body.md" <<'PY'
from pathlib import Path
import sys
template, summary, dest = sys.argv[1:4]
body = Path(template).read_text(encoding="utf-8") if Path(template).exists() else ""
body = body.replace("- [ ] Chore —", "- [x] Chore —")
body = body.replace("- [ ] No tests required —", "- [x] No tests required —")
body = body.replace(
    "- [ ] `*AGENTS.md` context files updated to reflect changes",
    "- [x] `*AGENTS.md` context files updated to reflect changes",
)
desc = (
    "Dependabot-style AI asset sync. Upstream sources in `.github/assets/ai-sync.yml` "
    "were reconciled by the OpenCode DevEx agent.\n"
)
if "## Description" in body:
    body = body.replace("## Description", "## Description\n\n" + desc, 1)
else:
    body = desc + "\n" + body
body += "\n" + Path(summary).read_text(encoding="utf-8")
body += (
    "\n## Provenance\n\n"
    "See the table above (`owner/repo@resolvedSHA:path` per entry).\n\n"
    "**Note:** this PR is opened with `GITHUB_TOKEN`, so downstream `pull_request` "
    "workflows will not run on it (GitHub restriction). Re-run required checks after "
    "review if needed.\n"
)
Path(dest).write_text(body, encoding="utf-8")
PY

git push origin "$BRANCH"
gh pr create \
  --title "chore: sync AI assets" \
  --body-file "${REPORT_DIR}/pr-body.md" \
  --base "$DEFAULT_BRANCH"

log "✓ opened chore PR on ${BRANCH}"
