# Local Development

## Prerequisites

- **.NET 10 SDK**
- A container runtime — Docker Desktop, Rancher Desktop, Colima, or Podman (for PostgreSQL via Aspire)

## One-time AI-agent setup

The repository drives four AI coding agents from a single `.agents/` directory via symlinks
(`.claude`, `.codex`, `.cursor` → `.agents`, `opencode.json` → `.agents/opencode.json`, and
`GEMINI.md` → `AGENTS.md`). Run the setup script once after cloning so the agents can discover
skills, hooks, and rules:

```bash
# Mac/Linux
bash .agents/setup/scripts/agents-setup.sh
```

```powershell
# Windows (requires admin; enable Developer Mode for symlink support)
powershell -ExecutionPolicy Bypass -File .agents/setup/scripts/agents-setup.ps1
```

> On Windows, enable Developer Mode (**Settings → System → For developers → Developer Mode**) so symlinks resolve.

## Build & Test

```bash
dotnet restore Project.slnx
dotnet build   Project.slnx --configuration Release
dotnet test    Project.slnx
```

Target a single test project directly when iterating, e.g. `dotnet test tests/Project.Domain.UnitTest`.
Test levels and container fixtures: [Testing Strategy](testing.md).

## Run locally

```bash
dotnet run --project src/Project.Host      # start the API
```

## Run in a container

The repo ships a multi-stage [`Dockerfile`](../../Dockerfile) and
[`docker-compose.yml`](../../docker-compose.yml):

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
