#!/usr/bin/env pwsh
# ai-template-sync — deterministic file-sync (Sections A–E). Windows/pwsh counterpart of sync.sh.
#
# All DECISIONS stay with the agent; this script carries out decisions passed as parameters.
# Overwrite note: supports global (clobber) and none (additive). True per-file selective
# overwrite is the agent's job — copy approved files first, then run with -Overwrite none.
[CmdletBinding()]
param(
  [string]$Template = "",
  [string]$TemplateUrl = "",
  [Parameter(Mandatory)][string]$Landing,
  [string]$Tools = "",
  [switch]$Dotnet,
  [ValidateSet("global", "none")][string]$Overwrite = "none"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Landing)) { throw "landing dir does not exist: $Landing" }
function Test-Tool([string]$t) { return (($Tools -split ',') -contains $t) }

# Resolve the template source: -TemplateUrl (clone) XOR -Template XOR default (git toplevel).
$CloneDir = $null
if ($TemplateUrl) {
  if ($Template) { throw "-Template and -TemplateUrl are mutually exclusive" }
  $CloneDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()))
  Write-Host "==> cloning template: $TemplateUrl"
  git clone --depth 1 $TemplateUrl $CloneDir.FullName
  $Template = $CloneDir.FullName
}
elseif (-not $Template) {
  $Template = (git rev-parse --show-toplevel)
}
if (-not (Test-Path (Join-Path $Template ".agents"))) {
  throw "template does not look like the scaffold (no .agents/): $Template"
}

try {

# Section A — .agents base tree
Write-Host "==> Section A: syncing .agents/ tree"
$landAgents = Join-Path $Landing ".agents"
New-Item -ItemType Directory -Force -Path $landAgents | Out-Null
if ($Overwrite -eq "global") {
  Copy-Item (Join-Path $Template ".agents\*") $landAgents -Recurse -Force
}
else {
  # additive: copy only items that do not already exist
  Get-ChildItem (Join-Path $Template ".agents") -Recurse | ForEach-Object {
    $dest = $_.FullName.Replace((Join-Path $Template ".agents"), $landAgents)
    if (-not (Test-Path $dest)) {
      if ($_.PSIsContainer) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
      else { Copy-Item $_.FullName $dest -Force }
    }
  }
}

Set-Location $Landing
try { git config core.symlinks true } catch {}

if (Test-Tool "claude") {
  Write-Host "==> Section B: Claude Code symlinks (also lays the Cursor symlink — same scaffold)"
  New-Item -ItemType SymbolicLink -Name .claude   -Target .agents   -Force | Out-Null
  New-Item -ItemType SymbolicLink -Name .cursor   -Target .agents   -Force | Out-Null
  New-Item -ItemType SymbolicLink -Name CLAUDE.md -Target AGENTS.md -Force | Out-Null
  New-Item -ItemType SymbolicLink -Name GEMINI.md -Target AGENTS.md -Force | Out-Null
}
if (Test-Tool "codex") {
  Write-Host "==> Section C: Codex symlink"
  New-Item -ItemType SymbolicLink -Name .codex -Target .agents -Force | Out-Null
}
if (Test-Tool "copilot") {
  Write-Host "==> Section D: Copilot rules dir + instructions"
  New-Item -ItemType Directory -Path .github -Force | Out-Null
  if ($Overwrite -eq "global" -or -not (Test-Path .github\instructions)) {
    Remove-Item .github\instructions -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $Template ".github\instructions") .github\instructions -Recurse -Force
  }
  Remove-Item .agents\rules -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType SymbolicLink -Name .agents\rules -Target ..\.github\instructions -Force | Out-Null
  if ($Overwrite -eq "global" -or -not (Test-Path .github\copilot-instructions.md)) {
    Copy-Item (Join-Path $Template ".github\copilot-instructions.md") .github\copilot-instructions.md -Force
  }
}
if ($Dotnet) {
  Write-Host "==> Section E: .NET solutioning"
  $hasSln = @(Get-ChildItem -Path $Landing -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.slnx', '.sln' }).Count -gt 0
  if ($hasSln) {
    Write-Host "    skipped: landing repo already has a solution file"
  }
  else {
    foreach ($item in "Directory.Build.props", "Directory.Packages.props", "NuGet.Config", "src", "tests") {
      $p = Join-Path $Template $item
      if (Test-Path $p) { Copy-Item $p (Join-Path $Landing $item) -Recurse -Force }
    }
    Get-ChildItem $Template -Filter *.slnx | ForEach-Object { Copy-Item $_.FullName $Landing }
    Write-Host "    NOTE: rename Project.* -> <ActualProjectName> in names/namespaces afterwards"
  }
}
Write-Host "==> sync complete"

}
finally {
  if ($CloneDir) { Remove-Item $CloneDir.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}
