# Project

[![Skill Security Scan](https://github.com/generic-automation-and-it/smooth-devex-template/actions/workflows/skill-scan.yml/badge.svg)](https://github.com/generic-automation-and-it/smooth-devex-template/actions/workflows/skill-scan.yml)

> AI agent skills in `.agents/skills/` are scanned by [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) on pull requests that touch `.agents/skills/**` (or the workflow itself), once the PR is marked ready for review. A green badge means the latest scan found no HIGH/CRITICAL findings; results are published to the repository's **Security → Code scanning** tab.

> One-line description of what the service does and who it is for. _(Placeholder — update once the project is named.)_

`Project` is a **combined AI DevEx template** — a starting point for teams that want structured, tool-agnostic AI-assisted development from day one. It ships a ready-to-use AI agent toolchain (Claude Code, Cursor, GitHub Copilot, OpenAI Codex) wired up via a single `.agents/` directory, alongside a **.NET 10 / ASP.NET Core** reference implementation built with **Clean Architecture**.

> **⚠️ Template repository.** `Project` is a placeholder name used throughout the solution (`Project.slnx`, `src/Project.*`, `tests/Project.*`), the `.agents` tree, and this README. When the project is given a real name, rename every `Project`/`project` occurrence and update the descriptions below. See the Template Notice in [`AGENTS.md`](AGENTS.md) for the full checklist.

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

### Prerequisites

- **.NET 10 SDK**
- A container runtime — Docker Desktop, Rancher Desktop, Colima, or Podman (for PostgreSQL via Aspire)

### One-time AI-agent setup

The repository drives four AI coding agents from a single `.agents/` directory via symlinks (`.claude`, `.codex`, `.cursor` → `.agents`, `opencode.json` → `.agents/opencode.json`, and `GEMINI.md` → `AGENTS.md`). Run the setup script once after cloning so the agents can discover skills, hooks, and rules:

```bash
# Mac/Linux
bash .agents/setup/scripts/agents-setup.sh
```

```powershell
# Windows (requires admin; enable Developer Mode for symlink support)
powershell -ExecutionPolicy Bypass -File .agents/setup/scripts/agents-setup.ps1
```

> On Windows, enable Developer Mode (**Settings → System → For developers → Developer Mode**) so symlinks resolve.

### Build & Test

```bash
dotnet restore Project.slnx
dotnet build   Project.slnx --configuration Release
dotnet test    Project.slnx
```

Target a single test project directly when iterating, e.g. `dotnet test tests/Project.Domain.UnitTest`.

### Run locally

```bash
dotnet run --project src/Project.Host      # start the API
```

### Run in a container

The repo ships a multi-stage [`Dockerfile`](Dockerfile) and [`docker-compose.yml`](docker-compose.yml):

```bash
docker build -t project:local .     # or: docker compose build
docker compose up -d                # serves the Host on http://localhost:5080
```

The build stage uses `WORKDIR /build` (not `/src`) with `COPY src/ src/`, so restore/publish logs show clean
repo-root-relative `src/Project.*` paths — never a `/src/src/Project.*` double path. Keep the working directory
distinct from the copied `src/` folder if you edit the `Dockerfile`. `.dockerignore` keeps the build context to
`src/` plus the central build files (`Project.slnx`, `Directory.*.props`, `NuGet.Config`).

Once the stack is up:

| Interface | URL |
|---|---|
| Scalar API Docs | `/scalar/v1` on the Host |
| OpenAPI schema | `/openapi/v1.json` on the Host |

---

## Project Structure

```
.agents/                         # All AI tooling — single source of truth
  hooks/                         # PostToolUse / UserPromptSubmit automation
  prompts/                       # Reusable prompt templates
  roles/                         # Multi-agent role instructions (PO, Architect, QA, …)
  rules/                         # Per-file coding standards (auto-loaded by agents)
  skills/                        # Executable multi-file workflows
  setup/                         # One-time symlink / config setup scripts
  settings.json                  # Tool permissions, compile/test commands

Dockerfile                       # Multi-stage container build (WORKDIR /build — no /src/src)
docker-compose.yml               # Compose run (build: . + GHCR image:)
.dockerignore                    # Lean build context (src + central build files only)

src/
  Project.Domain/          # Entities, value objects, invariants — no external deps
  Project.Application/     # Vertical-slice use cases (Features/<Name>/) + Mediator handlers
  Project.Infrastructure/  # EF Core + PostgreSQL persistence, HTTP clients
  Project.Host/            # Minimal API composition, middleware, observability

tests/
  Project.*.UnitTest/          # L0 — no I/O, in-process
  Project.*.ComponentTest/     # L1 — in-memory EF Core / real isolated DB + Respawn
  Project.*.IntegrationTest/   # L2 — full stack, real PostgreSQL
  Project.TestFramework/       # Shared fixtures
  Project.TestFramework.Aspire/# Aspire dependency host (PostgreSQL + WireMock)
```

---

## Documentation

| Topic | Location |
|---|---|
| AI agent context & coding rules | [`AGENTS.md`](AGENTS.md) · [`.agents/`](.agents/) |
| Architecture & design | [`.docs/wiki/architecture.md`](.docs/wiki/architecture.md) |
| AI tooling setup | [`.docs/wiki/ai-tooling.md`](.docs/wiki/ai-tooling.md) |
| Testing strategy | [`.docs/wiki/testing.md`](.docs/wiki/testing.md) |
| CI/CD pipeline | [`.docs/wiki/ci.md`](.docs/wiki/ci.md) |
| AI asset sync (skills/rules) | [`.docs/wiki/ai-asset-sync.md`](.docs/wiki/ai-asset-sync.md) |
| Architecture decisions & NFRs | [`.docs/adr/`](.docs/adr/) · [`.docs/nfr/`](.docs/nfr/) |

---

## Use it in another repository

To pull the **agent skills** (`.agents/skills/`), **owned rules** (`.github/instructions/` subset),
and **owned hooks** (`.agents/hooks/` subset) from this template into an existing repository,
without copying the rest of the template, run the one-command installer. The installer is per-skill
**opt-out** — new catalogue entries default to `installed:true` — and keeps an editable manifest. It
never touches the calling repo's `src/` or `tests/` directories; with the default switches it writes
skills, the shared payload, the five owned rules under `.github/instructions/`, and the three owned
hooks.

```bash
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash -s -- -r -s -h
```

```powershell
$script = [scriptblock]::Create((irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1)); & $script -r -s -h
```

`-r` rules, `-s` skills, `-h` hooks — no switches means everything is on, so `-r -s -h` spells the
default out loud. Narrow with any subset (`-s` for skills only).

> **Risk callout.** A first run into an existing `.agents/skills/` **replaces every local skill folder**
> with the source's version — there is no confirmation prompt. Set `installed: false` in
> `_smooth-devex-shared/installation.json` for anything you want kept, before the first install, or
> back the folder up first.

State lives in `<your-repo>/.agents/_smooth-devex-shared/installation.json` (UTC stamp plus a
`name` / `installed` pair per skill). Flip a skill off by setting its `installed` flag to `false`; the
installer will leave it on disk but stop overwriting it on every run. Full contract and operator
documentation: [`scripts/SKILLS_INSTALLER.md`](scripts/SKILLS_INSTALLER.md).

### Owned set

The installer ships **exactly seven** skills: `ai-asset-sync`, `ai-ralph-loop`, `ai-template-sync`, `ai-terse`,
`create-hld`, `create-worktask`, `manage-rule-system`. Anything else in this template's
`.agents/skills/` — the `agile-github-*` pair, `context-load-*`, `git-commit*` / `git-sync`,
`ai-brain-dump`, `ai-understanding` — is treated as **local** to this template and never enters a
consumer's manifest. Skills owned by other repositories (the seven `mimisbrunnr-*` skills plus
`ai-review`, `git-commit-review-push`, etc., owned by `smooth-ai-product-context-memory`) are not
installed here either — install them with that repository's own installer.

### Scope

The installer ships only `.agents/skills/`. It does **not** carry:

- `.agents/rules/` (rules referenced by skill `SKILL.md` frontmatter)
- `.agents/templates/` (referenced by `create-worktask/SKILL.md`)
- `.agents/hooks/` (referenced by some `setup/scripts/` flows)

A consumer that runs the one-liner into an empty repo gets the skill folders but the cross-tree
references inside `SKILL.md` files (`Bash(.agents/rules/.../SKILL.md:*)`, etc.) point at paths that
do not exist. Skills that need rules or templates need a manual copy of those files alongside the
install. See `scripts/SKILLS_INSTALLER.md` for the per-skill dependency list.

### Supported roots

The installer accepts `.agents/skills/`, `.claude/skills/`, or `.codex/skills/` as the skills root.
A consumer that picks `.claude/skills/` or `.codex/skills/` as its root must create the canonical
symlink (`.claude/skills -> .agents/skills` / `.codex/skills -> .agents/skills`) for the skill
`SKILL.md` files to find their `scripts/` siblings at the canonical path.

---

## Contributing

- Work on a branch off `main`: `<type>/<ticket>-short-description` (e.g. `feat/1234-add-user-export`).
- Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org). See [`.agents/rules/git/`](.agents/rules/git/).
- Every PR should create or update at least one `*AGENTS.md` context file.
