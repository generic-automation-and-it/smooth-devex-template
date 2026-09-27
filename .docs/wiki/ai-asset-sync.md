# AI Asset Sync

Dependabot-style reconciler for AI assets (skills, rules). A scheduled workflow checks `.github/assets/ai-sync.yml`, uses OpenCode as an AI-DevEx expert to merge upstream changes with local adaptations, and opens one chore PR per run when the tree differs.

Implementation lives in `.agents/skills/ai-asset-sync/scripts/run-sync.sh`. The reusable workflow and composite action are thin wrappers — change sync behaviour in the script.

## Consumer setup

1. Copy [`.docs/examples/ai-asset-sync-caller.yml`](../examples/ai-asset-sync-caller.yml) to `.github/workflows/pipeline-ai-asset-sync.yml`.
2. Add `.github/assets/ai-sync.yml`:

```yaml
version: 1
entries:
  - source: generic-automation-and-it/smooth-devex-template@main:.agents/skills/ai-brain-dump
  - source: generic-automation-and-it/smooth-devex-template@v1:.github/instructions/git
    strategy: overwrite
```

3. Set the selected provider's `OPENCODE_<PROVIDER>_API_KEY` secret and (recommended) pin `OPENCODE_CLI_VERSION`.
4. Optional Variables: `OPENCODE_AI_SYNC_PROVIDER` (default `GEMINI`), `OPENCODE_AI_SYNC_MODEL_PRIMARY` / `_SECONDARY`, `OPENCODE_AI_SYNC_CONFIG`.

Same-org callers may use `secrets: inherit`. Cross-org callers must map keys explicitly (GitHub rejects cross-org inherit).

## Triggers

Consumer side: `schedule` (cron) + `workflow_dispatch` only. The reusable workflow itself is `workflow_call` + `workflow_dispatch` (no push/pull_request).

## What happens on a run

| Situation | Model? | Files? | PR? | Lockfile |
|-----------|--------|--------|-----|----------|
| Upstream SHA == lockfile | no | no | no | unchanged |
| Local missing or `strategy: overwrite` | no | copy upstream | yes if diff | advances in the PR |
| Local present, mergeable | yes | merged/applied | yes if diff | advances in the PR |
| Heavy divergence | yes | **untouched** | yes only if *other* entries changed | that entry not advanced |
| AI says local already equivalent | yes | no | **no** | unchanged (re-analyse next run) |

Branch: `chore/ai-sync-{UTC YYYYMMDD-HHMM}-{run id}` (fresh each run, collision-safe). Title: `chore[NO-TICKET]: sync AI assets` (override: `pr_title` input / `AI_ASSET_SYNC_PR_TITLE`). Body: repo PR template + provenance table + Conflicts / Gaps / Issues / Blockers.

## Packaging

| Shape | When |
|-------|------|
| Reusable `workflow_call` | Caller YAML in `.docs/examples/ai-asset-sync-caller.yml`. Skill fetched at `github.job_workflow_sha` if not installed locally. |
| `workflow_dispatch` in this template | Same workflow file, in-repo skill, no side checkout. |
| Skill installed locally | Skip side checkout; `run-sync.sh` from the consumer tree. |
| Composite action `.github/actions/ai-asset-sync` | Copy-install / local-job packaging; still calls `run-sync.sh`. |

## Auth and limitations

`GITHUB_TOKEN` only (open source). Known GitHub restriction: PRs opened with `GITHUB_TOKEN` do **not** trigger downstream `pull_request` workflows (your PR gate will not run on the sync PR). Re-run checks after review.

Private source repos work only where that token can read them (same repo/org). Cross-org private sources are out of scope. No PAT / GitHub App token.

## Credential isolation

The ai-merge model reads upstream content someone else controls, so it is treated as a prompt-injection target and kept away from every credential:

| Measure | Where |
|---------|-------|
| Model process gets only the selected `OPENCODE_<PROVIDER>_API_KEY` — no `GITHUB_TOKEN`, OIDC or other keys (env allowlist) | `run-sync.sh` |
| `sync` agent cannot read or edit `.git/**` (credentials, hooks) or `.env*` | `assets/opencode.json` |
| Checkout uses `persist-credentials: false`. If a checkout still persisted the token in `.git/config`, it is **set aside** (backed up outside the repo) while the model runs and restored byte-for-byte before push | reusable workflow + `run-sync.sh` |
| Git hooks disabled for every git command the script runs; push uses a one-shot `gh` credential helper | `run-sync.sh` |
| Provider keys mapped on the sync step only, never job-wide | reusable workflow |

**Composite action users:** no change is required: a default checkout keeps working, because the script sets the persisted token aside for the model phase. `persist-credentials: false` is still recommended (the token then never touches disk):

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
    persist-credentials: false
- uses: generic-automation-and-it/smooth-devex-template/.github/actions/ai-asset-sync@main
```

`.git/config` is never committed. The risk is the model **reading** the token there and copying it into a file or PR description it writes. A token typed into a remote URL (`https://token@github.com/…`) is not rewritten: an ai-merge run refuses to start until it is removed.

## Non-goals

Move/rename (remote path ≠ local path), one-PR-per-entry, auto-merge of the sync PR.

## Related

- Skill: `.agents/skills/ai-asset-sync/`
- Example caller: `.docs/examples/ai-asset-sync-caller.yml`
- [CI](ci.md) · [AI tooling](ai-tooling.md)
