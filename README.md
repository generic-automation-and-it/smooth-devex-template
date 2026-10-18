# Project

[![Skill Security Scan](https://github.com/generic-automation-and-it/smooth-devex-template/actions/workflows/skill-scan.yml/badge.svg)](https://github.com/generic-automation-and-it/smooth-devex-template/actions/workflows/skill-scan.yml)

> AI agent skills in `.agents/skills/` are scanned by [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) on pull requests that touch `.agents/skills/**` (or the workflow itself), once the PR is marked ready for review. A green badge means the latest scan found no HIGH/CRITICAL findings; results are published to the repository's **Security → Code scanning** tab.

> One-line description of what the service does and who it is for. _(Placeholder — update once the project is named.)_

`Project` is a **combined AI DevEx template** — a starting point for teams that want structured, tool-agnostic AI-assisted development from day one. It ships a ready-to-use AI agent toolchain (Claude Code, Cursor, GitHub Copilot, OpenAI Codex) wired up via a single `.agents/` directory, alongside a **.NET 10 / ASP.NET Core** reference implementation built with **Clean Architecture**.

> **⚠️ Template repository.** `Project` is a placeholder name used throughout the solution (`Project.slnx`, `src/Project.*`, `tests/Project.*`), the `.agents` tree, and this README. When the project is given a real name, rename every `Project`/`project` occurrence and update the descriptions below. See the Template Notice in [`AGENTS.md`](AGENTS.md) for the full checklist.

---

## Install skills, rules and hooks into a brownfield repository

Reuse in another repo. One command — ships owned set only (7 skills, all owned rules, 2 hooks). Details and owned-set table: [`docs/wiki/reuse.md`](docs/wiki/reuse.md).

```bash
# Mac/Linux
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash -s -- -r -s -h
# Add -d to enable AI decision validation for ralph loop (no prompt):
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash -s -- -r -s -h -d
# Add -g to install the owned set globally for Codex (store at ~/.smooth-ai-devex, wired into ~/.codex):
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash -s -- -r -s -h -d -g
# Remove that global install (Codex + Claude skills, OpenCode commands):
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash -s -- -g --uninstall
```

```powershell
# Windows
$script = [scriptblock]::Create((irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1)); & $script -r -s -h
# Add -d to enable AI decision validation (no prompt):
$script = [scriptblock]::Create((irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1)); & $script -r -s -h -d
# Add -g to install the owned set globally for Codex (store + ~/.codex wiring):
$script = [scriptblock]::Create((irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1)); & $script -r -s -h -d -g
# Remove that global install:
$script = [scriptblock]::Create((irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1)); & $script -g --uninstall
```

| Switch | Meaning |
|---|---|
| `-r` | Install the owned rules (the template's `.github/instructions/` tree) |
| `-s` | Install the owned skills (`.agents/skills/` flat folders) |
| `-h` | Install the owned hooks (`.agents/hooks/`) |
| `-d` | Enable AI decision validation for the ralph loop — writes `SMOOTH_DEVEX_DECISIONS_*` env vars and sets `decisions_enabled: true` in `installation.json` |
| `-g` | Install the owned set **globally** — `~/.smooth-ai-devex/{skills,rules,hooks}` store, wired into Codex's `~/.codex/` (skills symlinks, `AGENTS.md` import, `hooks.json` merge), Claude's `~/.claude/skills` + `~/.claude/rules` (when Claude is installed), and OpenCode's `skills/` dir + `opencode.json` `instructions` (when OpenCode is installed) |
| `--uninstall` | Remove the global install (`-g --uninstall`) — removes only manifest-recorded links/edits, restores `smooth-devex-<datetime>` snapshots, leaves `.system/`, `gk` hooks, and the RTK line intact |
| _(none)_ | All of the above (rules + skills + hooks) — the default; decisions are then prompted for, or disabled with no terminal |

Switches filter the run only; nothing about the selection is persisted. `-d` is an opt-in flag (not a category) — it never defaults on. `-g` and `--uninstall` are a separate **global** mode: `-g` refuses to combine with `SKILLS_ROOT`, and `--uninstall` only applies together with `-g`.

A Claude Code plugin is also available for the owned skills — install it from a marketplace to add the seven skills to Claude Code directly. It installs **skills only**: unlike the installer script, it does **not** copy over rules or hooks.

---

## Tech Stack

### AI Toolchain

| Component | Technology |
|---|---|
| Agent scaffold | `.agents/` — single source of truth for all AI tools |
| Coding agents | Claude Code · GitHub Copilot · Cursor · OpenAI Codex |
| Skills | Executable multi-file workflows in `.agents/skills/` |
| Rules | Per-file coding standards in `.agents/rules/` |
| Prompts & roles | Reusable prompt templates and multi-agent role instructions |
| Hooks | `PostToolUse` / `UserPromptSubmit` automation via `.agents/hooks/` |

### .NET Reference Implementation

| Component | Technology |
|---|---|
| Framework | ASP.NET Core (.NET 10) |
| Architecture | Clean Architecture — `Domain` / `Application` / `Infrastructure` / `Host` |
| API style | Minimal API endpoints (`src/Project.Host`) |
| Mediator | [`martinothamar/Mediator`](https://github.com/martinothamar/Mediator) — source-gen CQRS dispatch |
| Validation | FluentValidation in a fail-fast Mediator pipeline |
| Persistence | EF Core + PostgreSQL (`Npgsql.EntityFrameworkCore.PostgreSQL`) |
| Observability | Serilog + OpenTelemetry, Scalar OpenAPI UI |
| Testing | xunit.v3 · Shouldly · Bogus · Respawn |

---

## Getting Started

| Step | Command |
|---|---|
| Prereqs | .NET 10 SDK + container runtime (Docker, Rancher, Colima, Podman) |
| Agent setup (once) | `bash .agents/setup/scripts/agents-setup.sh` |
| Build & test | `dotnet build Project.slnx` · `dotnet test Project.slnx` |
| Run API | `dotnet run --project src/Project.Host` |

Full setup, container run, and troubleshooting: [`docs/wiki/local-dev.md`](docs/wiki/local-dev.md).

---

## Project Structure

| Path | Purpose |
|---|---|
| `.agents/` | All AI tooling — skills, rules, hooks, prompts, roles, setup |
| `src/` | .NET reference implementation (`Domain` / `Application` / `Infrastructure` / `Host`) |
| `tests/` | L0 unit · L1 component · L2 integration + shared fixtures |
| `docs/` | Wiki, examples, ADRs, NFRs, HLDs |
| `scripts/` | Skills installer + test harness |

---

## Documentation

| Topic | Location |
|---|---|
| AI agent context & coding rules | [`AGENTS.md`](AGENTS.md) · [`.agents/`](.agents/) |
| Reuse skills/rules/hooks elsewhere | [`docs/wiki/reuse.md`](docs/wiki/reuse.md) |
| Local dev (setup, run, containers) | [`docs/wiki/local-dev.md`](docs/wiki/local-dev.md) |
| Architecture & design | [`docs/wiki/architecture.md`](docs/wiki/architecture.md) |
| AI tooling setup | [`docs/wiki/ai-tooling.md`](docs/wiki/ai-tooling.md) |
| Testing strategy | [`docs/wiki/testing.md`](docs/wiki/testing.md) |
| CI/CD pipeline | [`docs/wiki/ci.md`](docs/wiki/ci.md) |
| AI asset sync (skills/rules) | [`docs/wiki/ai-asset-sync.md`](docs/wiki/ai-asset-sync.md) |
| Architecture decisions & NFRs | [`docs/adr/`](docs/adr/) · [`docs/nfr/`](docs/nfr/) |

---

## Contributing

- Work on a branch off `main`: `<type>/<ticket>-short-description` (e.g. `feat/1234-add-user-export`).
- Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org). See [`.agents/rules/git/`](.agents/rules/git/).
- Every PR should create or update at least one `*AGENTS.md` context file.
