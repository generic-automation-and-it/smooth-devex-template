#requires -Version 7.2
<#
.SYNOPSIS
    Cross-platform skills installer for Windows / macOS / Linux (PowerShell 7.2+).

.DESCRIPTION
    One-liner:
      irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1 | iex

    Same contract as install-skills.sh:

      1. Finds the agent root in order: .agents -> .claude -> .codex, and errors
         when none exists. It never creates one: a folder the operator did not ask for is not an install.
         The skills root is <agent-root>/skills (override with SKILLS_ROOT, whose parent then counts
         as the agent root for state purposes). Missing category directories are created only when needed.
      2. Reads <agent-root>/_smooth-devex-shared/installation.json.
         - Missing  -> creates it with every skill on disk, installed:true, UTC timestamp.
         - Present  -> syncs: adds new skills, drops skills no longer on disk, keeps every
                       installed flag the operator already set. A corrupt file is a hard error,
                       never a silent reset of the whole manifest.
         A legacy manifest at the old <skills-root>/_smooth-devex-shared/installation.json location
         is ignored (fresh start): it is reported and otherwise left untouched.
      3. Updates only the skills marked installed:true, cloning the repo once and copying those folders
         (plus the shared payload, if the source ships one) out of it. Tests are pruned from these copies.
      4. Writes the updated installation.json back with a fresh UTC timestamp - after the update, so
         refreshing the shared payload cannot clobber the manifest that update read.
      5. Links every top-level shared-payload entry back to its canonical <agent-root> path
         (e.g. <agent-root>/setup -> _smooth-devex-shared/setup), so SKILL.md references to the
         canonical paths keep working. An existing real file or directory at the link path is
         never replaced: it is reported and skipped.

    Dependencies: PowerShell 7.2+ (LinkTarget requires .NET 6), git. No Python and no bash.

    Environment overrides:
      SKILLS_REPO    - git URL to clone from (default: the upstream GitHub repo)
      SKILLS_BRANCH  - branch to clone (default: main)
      SKILLS_ROOT    - force a specific skills root (skips the search)

.EXAMPLE
    ./install-skills.ps1
    ./install-skills.ps1 -SkillsRepo 'C:\repos\smooth-devex-template' -SkillsBranch main
#>
[CmdletBinding()]
param(
    [string] $SkillsRepo = $(if ($null -ne $env:SKILLS_REPO -and $env:SKILLS_REPO -ne '') { $env:SKILLS_REPO } else { 'https://github.com/generic-automation-and-it/smooth-devex-template.git' }),
    # $null -ne rather than a truthiness test: an env var that is set but EMPTY is the "use the remote's
    # default branch" case, and `if ($env:SKILLS_BRANCH)` cannot tell it from an unset var — it would fall
    # back to 'main' and name a branch that may not exist on a fork or in a detached checkout.
    [string] $SkillsBranch = $(if ($null -ne $env:SKILLS_BRANCH) { $env:SKILLS_BRANCH } else { 'main' }),
    [string] $SkillsRoot = $env:SKILLS_ROOT,
    [Alias('r')]
    [switch] $Rules,
    [Alias('s')]
    [switch] $Skills,
    [Alias('h')]
    [switch] $Hooks,
    [Alias('d')]
    [switch] $Decisions,
    [Alias('g')]
    [switch] $Global,
    [switch] $Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Skills the installer is allowed to carry across to a consumer repo. The installer is scoped to
# this explicit allow list - a positive owned set, not a deny list - so the only skills that ever
# enter a consumer's manifest or land on disk are these.
#
# The rest of the source tree's `.agents/skills/` is treated as **local**: it lives in this template
# for use inside the template, and the installer ignores it on its way through. An unscoped installer
# pulled a target repo's local-only skills into its manifest as `installed:true` - that is the bug
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
$script:OwnedList = @(
    'agile-github-breakdown'
    'agile-github-task-from-diff'
    'ai-asset-sync'
    'ai-ralph-loop'
    'ai-template-sync'
    'ai-terse'
    'context-load-agents-context'
    'context-load-context'
    'create-hld'
    'create-worktask'
    'git-commit'
    'git-commit-push'
    'git-commit-push-pr'
    'git-sync'
    'manage-rule-system'
)

# Rules the installer is allowed to carry across, as paths relative to .github/instructions/.
# Every rule in this template is owned (it is the DevEx rules tree), so all of them ship. The
# rules index (AGENTS.md) is NOT copied — install writes a generated index of the shipped set.
# Mirrors OWNED_RULES in install-skills.sh (the harness holds the two byte-for-byte).
$script:OwnedRules = @(
    'ai-workflow-rules.instructions.md'
    'backend/api-mediator-validation.instructions.md'
    'backend/architecture-slices.instructions.md'
    'backend/backend-logging-conventions.instructions.md'
    'backend/collection-types.instructions.md'
    'backend/external-api-clients.instructions.md'
    'backend/migrations.instructions.md'
    'backend/project-overview.instructions.md'
    'backend/readonly-collections.instructions.md'
    'backend/solid-principles.instructions.md'
    'backend/wiremock-stubbing.instructions.md'
    'clean-code.instructions.md'
    'code-review-standards.instructions.md'
    'git/git-policy.instructions.md'
    'git/pr-standards.instructions.md'
    'meta/knowledge-conventional-contexts-quality.instructions.md'
    'meta/rules.instructions.md'
    'meta/understandings.instructions.md'
    'skills/skill-secret-handling.instructions.md'
    'skills/skillspector-pre-pr.instructions.md'
)

# Hooks the installer is allowed to carry across: a hook is owned iff an owned skill's SKILL.md
# references it AND its implementation ships with it. load-agents-context.sh is referenced by
# ai-template-sync and its implementation now ships (context-load-agents-context is owned), but it
# is a PostToolUse hook and -g registers hooks under UserPromptSubmit only, so it stays local until
# the installer can register a hook by its own event. Mirrors OWNED_HOOKS in install-skills.sh
# (harness-held byte-for-byte).
$script:OwnedHooks = @(
    'manage-rule-system-context.sh'
    'worktask-skill-trigger.sh'
)

# Mirror of is_owned_skill in install-skills.sh. The harness compares the two lists byte-for-byte;
# both must agree on which names are installable.
#
# A test-only override SKILLS_TEST_OWNED_EXTRA extends the owned list with synthetic names so the
# harness can exercise add/drop cases without planting real source-owned names. Production
# installers never set this. The override is merged into a single comparison surface, so the
# gate is one branch, not two loops that drift on every new gate.
function Test-OwnedSkill {
    param([string] $Name)
    $set = Get-OwnedSet
    # `-cmatch` is case-SENSITIVE — the owned set is an exact-name allowlist, and a folder
    # like `AI-TERSE` must not pass on a case-insensitive filesystem. Anchor on both sides with
    # spaces so partial-token matches (e.g. `ai-` against `ai-terse`) cannot pass.
    if ($set -cmatch ("(^| )([\s\S]*\s)?" + [regex]::Escape($Name) + "(\s|$)")) {
        return $true
    }
    return $false
}

function Get-OwnedSet {
    $out = $script:OwnedList -join ' '
    if ($null -ne $env:SKILLS_TEST_OWNED_EXTRA -and $env:SKILLS_TEST_OWNED_EXTRA -ne '') {
        $out = "$out $($env:SKILLS_TEST_OWNED_EXTRA)"
    }
    return $out
}

# Owned rules and hooks need no membership test: Install-OwnedRules/Hooks loop the allowlists
# directly, so an unowned name can never enter (unlike skills, where a hand-edited manifest needs
# the Test-OwnedSkill guard). No helpers, nothing to drift.

if (Get-Variable -Name PSNativeCommandArgumentPassing -ErrorAction SilentlyContinue) {
    $PSNativeCommandArgumentPassing = 'Standard'
}

function Write-Info { param([string] $Message) Write-Host "install-skills: $Message" }
# One line on stderr, matching the bash launcher. Write-Error renders a full error record - position,
# frame and all - which buries the one sentence the operator has to act on.
function Fail { param([string] $Message) [Console]::Error.WriteLine("install-skills: $Message"); exit 1 }

# ---------------------------------------------------------------------------
# Decision validation opt-in
# ---------------------------------------------------------------------------

function Test-DecisionsPropertyExists {
    # Returns $true if the decisions_enabled property exists in the JSON (regardless of value).
    param([object] $ExistingJson)
    if ($null -eq $ExistingJson) { return $false }
    $prop = $ExistingJson.psobject.Properties['decisions_enabled']
    return ($null -ne $prop)
}

function Get-DecisionsEnabled {
    # Returns the decisions_enabled value from existing JSON, or $null if not present.
    param([object] $ExistingJson)
    if ($null -eq $ExistingJson) { return $null }
    $prop = $ExistingJson.psobject.Properties['decisions_enabled']
    if ($null -eq $prop) { return $null }
    return [bool] $prop.Value
}

function Prompt-Decisions {
    # Ask the user whether to enable decision validation. Read-Host reads from the console, so the
    # question is asked even when stdin is redirected (a typical `irm | iex`). On a host with no
    # interactive terminal the read fails and we fall back to disabled.
    # Sets $script:DecisionsEnabled to $true or $false.
    try {
        Write-Host ''
        Write-Host '  Enable AI decision validation for ralph loop?'
        Write-Host '  (Evaluates each fix via local OpenJEV model; requires openjev at localhost:1234)'
        $answer = Read-Host '  [y/N]'
        if ($answer -match '^[yY]') {
            $script:DecisionsEnabled = $true
            Write-Info 'Decisions enabled'
        } else {
            $script:DecisionsEnabled = $false
            Write-Info 'Decisions disabled'
        }
    } catch {
        Write-Info 'No terminal available - decisions disabled by default'
        $script:DecisionsEnabled = $false
    }
}

function Write-DecisionsEnv {
    # Write SMOOTH_DEVEX_DECISIONS_* env vars to the user's PowerShell profile.
    # Idempotent: skips when the sentinel marker is already present.
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not $profilePath) {
        $profilePath = Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    }
    if ((Test-Path -LiteralPath $profilePath -PathType Leaf) -and
        (Select-String -LiteralPath $profilePath -Pattern 'SMOOTH_DEVEX_DECISIONS' -Quiet)) {
        Write-Info "Decision env vars already in $profilePath - skipped"
        return
    }
    $profileDir = Split-Path $profilePath -Parent
    if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    $envBlock = @"

# Smooth DevEx - AI Decision Validation (added by install-skills)
`$env:SMOOTH_DEVEX_DECISIONS_ENABLED = 'true'
`$env:SMOOTH_DEVEX_DECISIONS_BASE_URL = 'http://127.0.0.1:1234'
`$env:SMOOTH_DEVEX_DECISIONS_PATH = '/v1/systemone'
`$env:SMOOTH_DEVEX_DECISIONS_MODEL = 'openjev'
`$env:SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY = '0.60'
`$env:SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS = '3'
`$env:SMOOTH_DEVEX_DECISIONS_TIMEOUT = '60'
"@
    # Snapshot the shell profile before appending to it — it is operator-owned.
    $backup = Backup-Inplace -Path $profilePath
    # In global mode, track the edit so --uninstall can restore the profile.
    if ($script:DoGlobal) { Add-GlobalLink 'profile-edit' $profilePath $backup }
    Add-Content -LiteralPath $profilePath -Value $envBlock -Encoding UTF8
    Write-Info "Wrote decision env vars to $profilePath"
}

# ---------------------------------------------------------------------------
# 1. Find skills root
# ---------------------------------------------------------------------------

function Find-AgentRoot {
    # Returns an absolute path. The manifest lives at <agent-root>/_smooth-devex-shared/installation.json,
    # and a later `Set-Location` would silently change what that path resolves to. Resolving once
    # at discovery keeps every downstream join against the same root.
    foreach ($dir in @('.agents', '.claude', '.codex')) {
        if (Test-Path -LiteralPath $dir -PathType Container) {
            return (Resolve-Path -LiteralPath $dir).Path
        }
    }
    Fail 'no agent directory found - expected one of .agents, .claude, .codex (create one, or set SKILLS_ROOT)'
}

# ---------------------------------------------------------------------------
# 2. List skills (dirs with SKILL.md, excluding _smooth-devex-shared). One function serves
# both disk and clone-source: the only difference is the root directory.
# ---------------------------------------------------------------------------

function Read-InstallationJson {
    # Missing reads as $null (a first install). A *corrupt* file is an error, not a first install:
    # treating it as absent would rebuild the manifest with every skill enabled, silently re-adding
    # skills the operator had switched off - and it would do that on a file nobody could parse, which
    # is exactly the file that needs a human.
    #
    # ConvertFrom-Json on blank/whitespace input returns $null without throwing - the same trap as a
    # missing file. A blank manifest would otherwise be accepted as a first install and every catalogue
    # skill would silently default to installed:true, overwriting local folders.
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Fail "$Path is empty or whitespace-only; fix or delete it - not treating it as a first install"
    }
    try {
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Fail "$Path is not valid JSON ($($_.Exception.Message)); fix or delete it - not treating it as a first install"
    }
}

function Get-Skills {
    # One function for both disk and clone-source: the only thing they differ on is which
    # directory is the root, and the owned-set gate is the same either way.
    param([string] $Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    @(Get-ChildItem -LiteralPath $Root -Directory |
        Where-Object { $_.Name -ne '_smooth-devex-shared' } |
        Where-Object { Test-OwnedSkill -Name $_.Name } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        Select-Object -ExpandProperty Name)
}

function Build-InstallationJson {
    # Returns the merged manifest as one JSON string.
    #
    # Built by hand rather than with ConvertTo-Json on a hashtable, because PowerShell unrolls a
    # single-element array to a bare object: `skills` would come back as an object rather than an
    # array, and the next run - or any other reader - would be parsing two different shapes.
    param(
        [string] $Updated,
        [string[]] $DiskSkills,
        [string[]] $SourceSkills,
        [object[]] $ExistingSkills,
        [bool] $DecisionsEnabled = $false
    )

    # The catalogue is the union (source + disk) INTERSECTED with the owned set. Without the
    # intersection, an unowned skill that happens to be in source or disk would still enter the
    # manifest as installed:true - the unscoped installer pulled a foreign repo's local-only skills
    # into its manifest exactly that way.
    #
    # $DiskSkills and $SourceSkills are already owned-filtered by their getters, but defence-in-depth
    # here keeps a caller who reaches into this function with raw arrays from getting an unowned
    # name into the manifest.
    $catalog = @(
        $DiskSkills + $SourceSkills |
            Where-Object { Test-OwnedSkill -Name $_ } |
            Sort-Object -Unique
    )

    $existingMap = @{}
    if ($ExistingSkills) {
        foreach ($entry in $ExistingSkills) {
            $existingMap[$entry.name] = [bool] $entry.installed
        }
    }

    $items = @()
    foreach ($name in $catalog) {
        # A skill the manifest has never mentioned joins as true, same as the first-run rule. A skill it
        # already knows keeps the operator's flag either way.
        $installed = $true
        if ($existingMap.Count -gt 0 -and $existingMap.ContainsKey($name)) { $installed = $existingMap[$name] }
        $item = [ordered]@{ name = $name; installed = $installed }
        $items += '    ' + ($item | ConvertTo-Json -Compress -Depth 3)
    }

    # decisions_enabled is the resolved preference already computed by the caller (main) —
    # a -d override, a reused saved value, a prompt answer, or the no-terminal default. Write it
    # as-is so a -d override actually persists across re-installs.
    $decisionsJson = if ($DecisionsEnabled) { 'true' } else { 'false' }

    $updatedJson = $Updated | ConvertTo-Json -Compress
    $joined = $items -join ",`n"
    if ($joined) { $joined += "`n" }
    return "{`n  `"updated`": $updatedJson,`n  `"decisions_enabled`": $decisionsJson,`n  `"skills`": [`n$joined  ]`n}"
}

function Get-RealPath {
    param([string] $Path)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $pending = if ([System.IO.Path]::IsPathFullyQualified($Path)) { $Path } else { [System.IO.Path]::Combine($PWD.Path, $Path) }
    for ($hops = 0; $hops -lt 64; $hops++) {
        $root = [System.IO.Path]::GetPathRoot($pending)
        $parts = @($pending.Substring($root.Length).Split([char[]]@('/', '\'), [System.StringSplitOptions]::RemoveEmptyEntries))
        $current = $root
        $relinked = $false
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -eq '.') { continue }
            if ($parts[$i] -eq '..') {
                if ($current -ne $root) { $current = [System.IO.Path]::GetDirectoryName($current) }
                continue
            }
            $next = [System.IO.Path]::Combine($current, $parts[$i])
            $target = [System.IO.FileInfo]::new($next).LinkTarget
            if ($target) {
                $rest = if ($i + 1 -lt $parts.Count) { $parts[($i + 1)..($parts.Count - 1)] -join $sep } else { '' }
                $pending = [System.IO.Path]::Combine($current, $target, $rest)
                $relinked = $true
                break
            }
            $current = $next
        }
        if (-not $relinked) {
            if ($current -eq $root) { return $root }
            return $current.TrimEnd('/', '\')
        }
    }
    return $pending
}

function Remove-PathEntry {
    param([string] $Path)
    $existing = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $existing) { return }
    if ($existing.LinkTarget) { $existing.Delete() } else { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Assert-SharedRoot {
    param([string] $Source, [string] $Dest)
    if ([System.IO.FileInfo]::new($Dest).LinkTarget -or (Test-Path -LiteralPath $Dest -PathType Leaf)) {
        Fail "shared payload destination must be a real directory: $Dest"
    }
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $resolved = Get-RealPath $Source
    $parent = Get-RealPath (Split-Path -Parent $Source)
    $clone = Get-RealPath $script:TempRepo
    if (-not "$resolved$sep".StartsWith("$clone$sep", [System.StringComparison]::Ordinal) -or
        "$parent$sep".StartsWith("$resolved$sep", [System.StringComparison]::Ordinal) -or
        -not (Test-Path -LiteralPath $resolved -PathType Container) -or
        [System.IO.FileInfo]::new($resolved).LinkTarget) {
        Fail "shared payload root cannot be materialized inside the clone: $Source"
    }
}

$script:WetStack = @()
$script:CloneRoot = $null
function Copy-Wet {
    param([string] $Source, [string] $Dest)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if (-not $script:CloneRoot) { $script:CloneRoot = Get-RealPath $script:TempRepo }
    $item = Get-Item -LiteralPath $Source -Force
    if ($item.LinkTarget) {
        $resolved = Get-RealPath $Source
        $parent = Get-RealPath (Split-Path -Parent $Source)
        $inClone = "$resolved$sep".StartsWith("$($script:CloneRoot)$sep", [System.StringComparison]::Ordinal)
        $cyclic = @(@($script:WetStack) + $parent | Where-Object { "$_$sep".StartsWith("$resolved$sep", [System.StringComparison]::Ordinal) }).Count -gt 0
        if ($inClone -and (-not $cyclic) -and (Test-Path -LiteralPath $resolved)) {
            $saved = $script:WetStack
            $script:WetStack = @($script:WetStack) + $resolved
            try { Copy-Wet -Source $resolved -Dest $Dest } finally { $script:WetStack = $saved }
            return
        }
        Remove-PathEntry -Path $Dest
        try {
            New-Item -ItemType SymbolicLink -Path $Dest -Target $item.LinkTarget | Out-Null
            Write-Info "Kept link $Dest -> $($item.LinkTarget) (outside the source, dangling, or cyclic)"
        }
        catch {
            Write-Info "WARNING: cannot recreate link $Dest -> $($item.LinkTarget) (no symlink privilege) - skipped"
        }
        return
    }
    if ($item.PSIsContainer) {
        $existing = Get-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
        if ($existing -and ($existing.LinkTarget -or -not $existing.PSIsContainer)) { Remove-PathEntry -Path $Dest }
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
        foreach ($entry in Get-ChildItem -LiteralPath $Source -Force) {
            Copy-Wet -Source $entry.FullName -Dest (Join-Path $Dest $entry.Name)
        }
    }
    else {
        Remove-PathEntry -Path $Dest
        Copy-Item -LiteralPath $Source -Destination $Dest -Force
    }
}

function Remove-Tests {
    param([string] $Root)
    if ([System.IO.FileInfo]::new($Root).LinkTarget) { return }
    Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force |
        Where-Object { $_.Name -cin @('test', 'tests', '__tests__') } |
        ForEach-Object { if (Test-Path -LiteralPath $_.FullName) { Remove-Item -LiteralPath $_.FullName -Recurse -Force } }
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Where-Object { $_.Name -clike 'test_*' -or $_.Name -clike '*_test.*' -or $_.Name -clike '*.test.*' -or $_.Name -clike '*.Tests.ps1' } |
        Remove-Item -Force
}

function Remove-StaleEntries {
    # Remove from Dest everything Source does not have, recursively.
    #
    # The recursion is the point: a top-level-only sweep keeps every entry the source still has *as a
    # folder* while leaving the files inside it that the source dropped, which is where a retired
    # script actually goes.
    #
    # installation.json is spared wherever it is found, because it is this script's own state and not
    # anything the clone source carries: sweeping it away is what turns an interrupted run into a silent
    # reset of every installed flag on the next one.
    param([string] $Dest, [string] $Source)

    if ([System.IO.FileInfo]::new($Dest).LinkTarget) { return }
    foreach ($entry in Get-ChildItem -LiteralPath $Dest -Force) {
        if ($entry.Name -eq 'installation.json') { continue }
        $sourcePath = Join-Path $Source $entry.Name
        $hasSource = (Test-Path -LiteralPath $sourcePath) -or ($null -ne (Get-Item -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue))
        if ($hasSource -and $entry.PSIsContainer -and -not $entry.LinkTarget) {
            Remove-StaleEntries -Dest $entry.FullName -Source $sourcePath
        }
        elseif (-not $hasSource) {
            Remove-Item -LiteralPath $entry.FullName -Recurse -Force
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Update installed skills from the repo
# ---------------------------------------------------------------------------

function Invoke-SourceClone {
    # Cloned before the manifest is built, not inside the update: the manifest's catalogue is the
    # source's skill list, so a first install into an empty folder has to see the source before it can
    # decide there is anything to install. The clone happens exactly once per run either way.
    param([string] $Repo, [string] $Branch)

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('install-skills-' + [guid]::NewGuid().ToString('N'))
    $script:TempRepo = Join-Path $script:TempRoot 'repo'
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

    Write-Info "Cloning $Repo ($($Branch ? $Branch : 'default branch'))..."
    # git writes progress to stderr, and a 2>&1 redirect in PowerShell turns that into error records -
    # which $ErrorActionPreference = Stop would then throw on a successful clone.
    #
    # An empty $Branch means "whatever the remote's default is", and that case is load-bearing rather than
    # cosmetic: `git rev-parse --abbrev-ref HEAD` returns the literal string "HEAD" in a detached checkout
    # - exactly what actions/checkout produces - and `git clone --branch HEAD` is not valid, because HEAD is
    # not a branch or tag name.
    #
    # A relative local directory is normalised to file:// so --depth applies. git ignores --depth in a
    # local clone ("use file:// instead"), which is a quiet downgrade: the entire clone is taken instead
    # of one commit, and the clone fails outright when the local repository has no branch of that name -
    # the detached-HEAD case again, reported by git as "Remote branch main not found", naming neither the
    # cause nor the path.
    #
    # Only bare *relative* local paths get the prefix. Anything else - an https URL (scheme matches), an
    # absolute local path (matches `StartsWith('/')`), an scp-style SSH remote (`git@host:owner/repo.git`,
    # neither matches) - is passed through unchanged. The previous test (`-notmatch '://' -and -not
    # .StartsWith('/')`) matched the SSH case and rewrote it to `file:///$SSH_REMOTE`, which then failed
    # at git's "not a git repository". The new test re-checks existence so a missing relative path also
    # falls through (the clone will then fail at the git call with the real reason, not a mangled URL).
    $cloneUrl = $Repo -replace '\\', '/'
    if (-not ($cloneUrl -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') -and -not $cloneUrl.StartsWith('/') -and (Test-Path -LiteralPath $cloneUrl -PathType Container)) {
        # Resolve against the current directory first: "file:///$cloneUrl" would point at the
        # filesystem root, not the caller's tree (bash builds file://$PWD/<rel> for the same case).
        $cloneUrl = "file://$((Resolve-Path -LiteralPath $cloneUrl).Path -replace '\\', '/')"
    }
    if ($Branch) {
        $gitOutput = & git -c core.symlinks=true clone --depth 1 --branch $Branch $cloneUrl $script:TempRepo 2>&1
    }
    else {
        $gitOutput = & git -c core.symlinks=true clone --depth 1 $cloneUrl $script:TempRepo 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        # A machine without symlink privilege (Windows without Developer Mode or elevation) fails
        # the forced checkout outright. Retry plain with a warning instead of dying: the installer
        # only reads real directories out of the clone, and canonical links are created
        # filesystem-side afterwards (with the junction fallback where needed).
        Write-Info 'WARNING: symlink checkout failed - retrying without symlink support'
        if ($Branch) {
            $gitOutput = & git clone --depth 1 --branch $Branch $cloneUrl $script:TempRepo 2>&1
        }
        else {
            $gitOutput = & git clone --depth 1 $cloneUrl $script:TempRepo 2>&1
        }
    }
    if ($LASTEXITCODE -ne 0) {
        Fail "failed to clone $Repo - $($gitOutput -join ' ')"
    }
}

function Ensure-CanonicalLink {
    # Link <agent-root>/<name> at the shared payload entry so canonical .agents/setup/... style
    # references keep working. An existing real file or directory is never replaced.
    param([string] $AgentRoot, [string] $Name)
    $link = Join-Path $AgentRoot $Name
    $target = "_smooth-devex-shared/$Name"
    # A dangling symlink reads as absent to Test-Path; re-creating over it aborts under Stop.
    # Check the link itself first, same as the rules-link guard below.
    $linkTaken = Test-Path -LiteralPath $link
    if (-not $linkTaken) {
        $dangling = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        $linkTaken = ($null -ne $dangling) -and ($null -ne $dangling.LinkType)
    }
    if ($linkTaken) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.LinkType) {
            # A link is already there: ours (same payload, either link kind) or someone else's.
            # Junction targets resolve absolute, symlink targets stay as created - compare loosely.
            $ours = Join-Path $AgentRoot $target
            if (($item.Target -eq $target) -or ($item.Target -eq $ours)) { return }
        }
        Write-Info "WARNING: $link already exists - leaving it in place, shared copy stays under _smooth-devex-shared/$Name"
        return
    }
    try {
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
    }
    catch {
        # Symlinks need elevation or Developer Mode on Windows; a junction needs neither.
        New-Item -ItemType Junction -Path $link -Target (Join-Path $AgentRoot $target) | Out-Null
    }
    Write-Info "Linked $link -> $target"
}

function Update-InstalledSkills {
    param(
        [string] $SkillsRoot,
        [string] $AgentRoot,
        [string] $SharedDir,
        [object] $Manifest
    )

    $installedNames = @()
    if ($Manifest -and $Manifest.skills) {
        $installedNames = @($Manifest.skills | Where-Object { $_.installed } | Select-Object -ExpandProperty name)
    }

    if ($installedNames.Count -eq 0) {
        # NOT a hard return: the shared-folder refresh below is independent of skill flags, and the
        # contract says shared helpers must stay current even when no skill is installed:true. Fall
        # through.
        Write-Info 'No skills marked installed:true - nothing to copy for skills.'
    }

    $repoSkills = Join-Path $script:TempRepo '.agents/skills'
    foreach ($name in $installedNames) {
        # Belt-and-braces: the manifest already excluded unowned skills (built from the owned
        # intersection). Re-check here in case the caller hand-wrote the manifest and put an
        # unowned name back in with installed:true. Same rejection shape the source repo's PR
        # #245 added.
        if (-not (Test-OwnedSkill -Name $name)) {
            Write-Info "Skipping unowned skill: $name"
            continue
        }
        $source = Join-Path $repoSkills $name
        if (Test-Path -LiteralPath $source -PathType Container) {
            $dest = Join-Path $SkillsRoot $name
            Remove-PathEntry -Path $dest
            Copy-Wet -Source $source -Dest $dest
            Remove-Tests -Root $dest
            Remove-SkillContext -Path $dest
            Write-Info "Updated $name"
        } else {
            Write-Info "WARNING: $name not found in repo - left on disk untouched"
        }
    }

    # The shared payload is not a skill and all of it refreshes on every run, independently of
    # the flags. Only cross-cutting, repo-owned items live here (setup scripts, installer state):
    # skills, rules and hooks stay in their standard directories.
    #
    # Refreshed *by content*, with stale entries removed, rather than merged in (which would leave a
    # file deleted upstream alive forever - an updater that never forgets anything is not an updater)
    # and rather than replacing the folder outright (which would take the manifest sitting inside it
    # down with it, and a run interrupted between the two would leave the next run rebuilding every
    # flag from defaults). So: copy across, then delete exactly what the source does not have, except
    # the manifest.
    $sharedSource = Join-Path $script:TempRepo '.agents/_smooth-devex-shared'
    if ((Test-Path -LiteralPath $sharedSource -PathType Container) -or [System.IO.FileInfo]::new($sharedSource).LinkTarget) {
        $sharedDest = $SharedDir
        Assert-SharedRoot -Source $sharedSource -Dest $sharedDest
        Copy-Wet -Source $sharedSource -Dest $sharedDest
        Remove-Tests -Root $sharedDest
        Remove-StaleEntries -Dest $sharedDest -Source $sharedSource
        Write-Info 'Updated _smooth-devex-shared'
        # Link the payload back to canonical paths so .agents/setup/... references keep working.
        foreach ($entry in Get-ChildItem -LiteralPath $sharedDest -Force) {
            if ($entry.Name -ceq 'installation.json') { continue }
            Ensure-CanonicalLink -AgentRoot $AgentRoot -Name $entry.Name
        }
    }
}

function Ensure-ConsumerSymlinkSupport {
    # Best-effort: mark symlinks supported in the consumer repo, mirroring .agents/setup/scripts.
    # Filesystem links the installer creates work regardless; this only affects how git *records*
    # them on the consumer's next commit. Outside a git work tree it is silently skipped.
    param([string] $AgentRoot)
    & git -C $AgentRoot config core.symlinks true 2>$null
}

function Write-RulesIndex {
    # The template's own AGENTS.md catalogues rules that never ship and would clobber an
    # existing consumer index — so it is never copied. Missing index → write a generated one
    # we own; our generated file → refresh it; someone else's index → append our subset once
    # (marker-guarded), never rewrite it.
    param([string] $DestRules)
    $index = Join-Path $DestRules 'AGENTS.md'
    $table = @(
        '| Scope | Rules |',
        '| :---- | :---- |',
        '| `**` | `git/git-policy` |',
        '| `**/*.cs` | `code-review-standards` |',
        '| `**/*AGENTS.md` | `meta/knowledge-conventional-contexts-quality` |',
        '| `.agents/rules/**` | `meta/rules` |'
    ) -join "`n"
    $full = @(
        '# AGENTS.md - Rules (installed subset)',
        '',
        '<!-- installer-owned-rules-subset: regenerated by install-skills -->',
        '',
        'Rule index for the files the skills installer shipped. The template full index',
        'lives upstream; only the files below are present here.',
        '',
        '## Key Behaviors',
        '',
        $table,
        '',
        'File = `<name>.instructions.md` in this folder.'
    ) -join "`n"
    if (-not (Test-Path -LiteralPath $index -PathType Leaf)) {
        [System.IO.File]::WriteAllText($index, ($full + "`n"), [System.Text.UTF8Encoding]::new($false))
        Write-Info "Wrote generated rules index $index"
    }
    elseif ((Get-Content -LiteralPath $index -TotalCount 1) -eq '# AGENTS.md - Rules (installed subset)') {
        [System.IO.File]::WriteAllText($index, ($full + "`n"), [System.Text.UTF8Encoding]::new($false))
        Write-Info "Refreshed generated rules index $index"
    }
    elseif (Select-String -LiteralPath $index -Pattern 'installer-owned-rules-subset' -Quiet) {
        Write-Info 'Rules index already carries the installed subset — left untouched'
    }
    else {
        Add-Content -LiteralPath $index -Value ("`n## Installed subset (installer-owned-rules-subset)`n`n$table`n")
        Write-Info "Appended installed subset to existing rules index $index"
    }
}

function Install-OwnedRules {
    # Copies the owned rule files from the source's .github/instructions/ into <agent-root>/rules/,
    # preserving relative paths. Overwrites, never deletes.
    param([string] $AgentRoot)
    $sourceRules = Join-Path $script:TempRepo '.github/instructions'
    $destRules = Join-Path $AgentRoot 'rules'
    if (-not (Test-Path -LiteralPath $sourceRules -PathType Container)) {
        Write-Info 'No .github/instructions in source - nothing to install for rules'
        return
    }
    New-Item -ItemType Directory -Path (Get-RealPath $destRules) -Force | Out-Null
    foreach ($rel in $script:OwnedRules) {
        $source = Join-Path $sourceRules $rel
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $dest = Join-Path $destRules $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Wet -Source $source -Dest $dest
            Write-Info "Updated rule $rel"
        }
        else {
            Write-Info "WARNING: rule $rel not found in repo - left on disk untouched"
        }
    }
    Write-RulesIndex -DestRules $destRules
}

function Install-OwnedHooks {
    # Copies the owned hook files from the source's .agents/hooks/ into the consumer's.
    # Overwrites, never deletes. Registration (settings.json) is out of scope.
    param([string] $AgentRoot)
    $sourceHooks = Join-Path $script:TempRepo '.agents/hooks'
    $destHooks = Join-Path $AgentRoot 'hooks'
    if (-not (Test-Path -LiteralPath $sourceHooks -PathType Container)) {
        Write-Info 'No .agents/hooks in source - nothing to install for hooks'
        return
    }
    New-Item -ItemType Directory -Path (Get-RealPath $destHooks) -Force | Out-Null
    foreach ($name in $script:OwnedHooks) {
        $source = Join-Path $sourceHooks $name
        if (Test-Path -LiteralPath $source) {
            Copy-Wet -Source $source -Dest (Join-Path $destHooks $name)
            Write-Info "Updated hook $name"
        }
        else {
            Write-Info "WARNING: hook $name not found in repo - left on disk untouched"
        }
    }
    # Hooks run as commands; a lost exec bit is a silently dead hook. .NET copy does not
    # guarantee unix mode bits, so best-effort chmod on unix only — per owned file, never a
    # wildcard that would flip operator-owned scripts sharing the directory. Preserve the
    # source bit, don't invent one.
    if ($IsLinux -or $IsMacOS) {
        foreach ($name in $script:OwnedHooks) {
            if ($name -like '*.sh') {
                $src = Join-Path $sourceHooks $name
                $dst = Join-Path $destHooks $name
                if (Test-Path -LiteralPath $src) {
                    & test -x $src; if ($LASTEXITCODE -eq 0) { & chmod +x $dst 2>$null }
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Global install (-g): a ~/.smooth-ai-devex central store wired into Codex.
#
# The per-repo install above scopes everything to <agent-root> in the repo you
# are standing in. -g instead installs the same owned set once, machine-wide,
# into a store and wires it into Codex's config dir (~/.codex by default, or
# $CODEX_HOME): skills symlinked into its skills dir (coexisting with .system/),
# rules copied into the store with a compact index of them (path, scope, description) in a
# delimited block of ~/.codex/AGENTS.md - Codex does not resolve @-imports and caps combined
# AGENTS.md content at 32 KiB - and a command-approval policy generated from git-policy as
# ~/.codex/rules/smooth-devex.rules (Codex .rules files are Starlark prefix_rule()s, not
# instructions), and hooks JSON-merged into
# ~/.codex/hooks.json (UserPromptSubmit only). A manifest at
# $GLB_ROOT/installation.json records every link and edit, and -g --uninstall
# removes exactly that — never .system/, the gk hooks, or the operator's RTK
# @-import line. The same manifest carries skills[], rules[] and hooks[], each entry
# {name, installed}; installed:false on a rule or hook switches that one item off (not
# copied, and removed from the AGENTS.md import, ~/.claude/rules, opencode.json
# instructions or hooks.json it was wired into; the store copy stays).
# harnesses{} (claude-code, codex, opencode; missing = true) switches a whole tool off: nothing is
# installed into it and everything already there is removed, found on disk rather than from links[];
# -g --uninstall ignores it. Symlink records carry `enabled`, a status recomputed each run, not a control.
# Every pre-existing config file the installer appends to
# (~/.codex/AGENTS.md, ~/.codex/hooks.json, and the shell profile when decision
# env vars are written) is snapshotted once as <file>.smooth-devex-<UTC datetime>
# before modification, and --uninstall restores it. $SMOOTH_DEVEX_HOME overrides
# the store location and $CODEX_HOME overrides Codex's config dir (both are how
# test harnesses isolate a run).
# ---------------------------------------------------------------------------

$script:GlbRoot = if ($env:SMOOTH_DEVEX_HOME) { $env:SMOOTH_DEVEX_HOME } else { Join-Path $HOME '.smooth-ai-devex' }
$script:GlobalManifest = Join-Path $script:GlbRoot 'installation.json'
$script:GlobalMarker = 'installer-owned-global-instructions'
$script:CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$script:OpenCodeConfig = if ($env:OPENCODE_CONFIG) { $env:OPENCODE_CONFIG } else { Join-Path $HOME '.config/opencode' }
$script:ClaudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$script:Links = [System.Collections.Generic.List[string]]::new()
# Per-item state for the rules and hooks categories, resolved from the manifest by
# Invoke-GlobalInstall: the reconciled {name, installed} lists ($null when the run does not
# cover the category, so the manifest carries the previous list forward), and the names
# carrying each installed flag.
$script:GlbRules = $null
$script:GlbHooks = $null
$script:RulesOn = @()
$script:RulesOff = @()
$script:HooksOn = @()
$script:HooksOff = @()
# The three harnesses the installer can wire into, resolved from the manifest's harnesses object
# by Invoke-GlobalInstall. $true = install into it, $false = do not, and remove what is there.
$script:GlbHarnesses = $null
$script:HarnessClaude = $true
$script:HarnessCodex = $true
$script:HarnessOpencode = $true

function Build-Harnesses {
    # The manifest's harnesses object: exactly the three harnesses the installer can wire into, in a
    # fixed order. A harness the manifest has not seen joins as true; the value the operator set is
    # kept, false included; any other key is dropped. Mirrors reconcile_harnesses in the bash port.
    param([object] $Existing)
    $found = $null
    if ($null -ne $Existing -and $Existing.PSObject.Properties['harnesses']) { $found = $Existing.harnesses }
    $out = [ordered]@{}
    foreach ($name in 'claude-code', 'codex', 'opencode') {
        $value = $true
        if ($null -ne $found -and $found.PSObject.Properties[$name]) { $value = [bool] $found.PSObject.Properties[$name].Value }
        $out[$name] = $value
    }
    return $out
}

function Remove-StoreLinks {
    # Remove every symlink under Dir (recursively) that points into the store's Subdir. Found by where
    # a link points, not by what the manifest recorded, so a link whose record was lost goes too. A real
    # file, and a link to anywhere else, is never touched.
    param([string] $Dir, [string] $Subdir)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return }
    $prefix = (Join-Path $script:GlbRoot $Subdir) + [System.IO.Path]::DirectorySeparatorChar
    foreach ($item in @(Get-ChildItem -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue)) {
        if ($item.LinkType -and $item.Target -and ([string] $item.Target).StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $item.FullName -Force
            Write-Info "Unlinked $($item.FullName) (harness turned off)"
        }
    }
}

# The delimited block this installer keeps in ~/.codex/AGENTS.md opens with a line carrying
# GlobalMarker and closes with a line carrying CodexBlockEnd. An older install wrote only the marker
# line and one @-line after it (no closing line); that legacy form is recognised too. Mirrors
# codex_agents_block in the bash port.
$script:CodexBlockEnd = 'end of install-skills global rules'

function Get-CodexBlockSpan {
    # Where our block sits in an array of lines: @{ Start; Stop; Legacy }, or $null when there is none.
    param([string[]] $Lines)
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Contains($script:GlobalMarker)) { $start = $i; break }
    }
    if ($start -lt 0) { return $null }
    $stop = -1
    for ($j = $start + 1; $j -lt $Lines.Count; $j++) {
        if ($Lines[$j].Contains($script:GlobalMarker)) { break }
        if ($Lines[$j].Contains($script:CodexBlockEnd)) { $stop = $j; break }
    }
    $legacy = $false
    if ($stop -lt 0) {
        $legacy = $true
        $stop = $start
        if (($start + 1) -lt $Lines.Count -and $Lines[$start + 1].StartsWith('@')) { $stop = $start + 1 }
    }
    return @{ Start = $start; Stop = $stop; Legacy = $legacy }
}

function Get-CodexBlockState {
    # none | block | legacy
    param([string] $File)
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return 'none' }
    $text = Get-Content -LiteralPath $File -Raw
    if ([string]::IsNullOrEmpty($text)) { return 'none' }
    $span = Get-CodexBlockSpan -Lines ($text -split "`n")
    if ($null -eq $span) { return 'none' }
    if ($span.Legacy) { return 'legacy' }
    return 'block'
}

function Set-CodexBlock {
    # Replace our block in File in place, or append one when there is none; nothing around it is
    # touched. Returns same | changed | appended.
    param([string] $File, [string] $Body)
    $begin = "<!-- $($script:GlobalMarker) (added by install-skills): regenerated on every run -->"
    $end = "<!-- $($script:CodexBlockEnd) -->"
    $block = @($begin) + @($Body.TrimEnd("`n") -split "`n") + @($end)
    $text = ''
    if (Test-Path -LiteralPath $File -PathType Leaf) {
        $raw = Get-Content -LiteralPath $File -Raw
        if ($null -ne $raw) { $text = $raw }
    }
    $lines = $text -split "`n"
    $span = Get-CodexBlockSpan -Lines $lines
    if ($null -eq $span) {
        $prefix = $text
        if ($prefix -and -not $prefix.EndsWith("`n")) { $prefix += "`n" }
        if ($prefix) { $prefix += "`n" }
        $result = $prefix + ($block -join "`n") + "`n"
        $outcome = 'appended'
    } else {
        $current = @($lines[$span.Start..$span.Stop] | ForEach-Object { $_.TrimEnd("`r") })
        if (-not $span.Legacy -and ($current -join "`n") -ceq ($block -join "`n")) { return 'same' }
        $before = @()
        if ($span.Start -gt 0) { $before = $lines[0..($span.Start - 1)] }
        $after = @()
        if (($span.Stop + 1) -lt $lines.Count) { $after = $lines[($span.Stop + 1)..($lines.Count - 1)] }
        $result = (@($before) + $block + @($after)) -join "`n"
        $outcome = 'changed'
    }
    [System.IO.File]::WriteAllText($File, $result, [System.Text.UTF8Encoding]::new($false))
    return $outcome
}

function Remove-CodexImport {
    # Codex is off: remove our block (and the blank line before it) from File. No snapshot is taken
    # (one was, at install). A file this installer created that now holds nothing else is removed, the
    # exact inverse of creating it; one that pre-dates the install (it has a snapshot) stays.
    param([string] $File, [string] $RtkLine = '')
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return }
    $text = Get-Content -LiteralPath $File -Raw
    if ([string]::IsNullOrEmpty($text)) { return }
    $lines = $text -split "`n"
    $span = Get-CodexBlockSpan -Lines $lines
    if ($null -eq $span) { return }
    $kept = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $span.Start; $i++) { $kept.Add($lines[$i]) }
    if ($kept.Count -gt 0 -and $kept[$kept.Count - 1].TrimEnd("`r") -eq '') { $kept.RemoveAt($kept.Count - 1) }
    for ($i = $span.Stop + 1; $i -lt $lines.Count; $i++) { $kept.Add($lines[$i]) }
    $result = $kept -join "`n"
    [System.IO.File]::WriteAllText($File, $result, [System.Text.UTF8Encoding]::new($false))
    Write-Info "Removed the global rules block from $File (codex turned off)"
    $remaining = $result.Trim()
    if (($remaining -eq '' -or $remaining -eq $RtkLine) -and -not (Test-InstallSnapshot -Path $File)) {
        Remove-Item -LiteralPath $File -Force
        Write-Info "Removed $File (the installer created it and nothing else is in it)"
    }
}

function Format-RulesIndex {
    # The text Codex is given in place of the rule files. Codex does not resolve @-imports and caps
    # combined AGENTS.md content at 32 KiB, so the rule bodies cannot travel in it; this lists each
    # enabled rule's path, scope and one-line description instead. Mirrors render_rules_index.
    $root = Join-Path $script:GlbRoot 'rules'
    $groups = [ordered]@{}
    foreach ($rel in $script:RulesOn) {
        $path = Join-Path $root $rel
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $text = Get-Content -LiteralPath $path -Raw
        $front = ''
        $rest = $text
        $fm = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---\r?\n')
        if ($fm.Success) { $front = $fm.Groups[1].Value; $rest = $text.Substring($fm.Length) }
        $read = {
            param([string] $Key)
            $f = [regex]::Match($front, '(?m)^' + $Key + ':\s*(.+?)\s*$')
            if (-not $f.Success) { return '' }
            $v = $f.Groups[1].Value.Trim()
            if ($v.Length -ge 2 -and $v[0] -eq $v[$v.Length - 1] -and ($v[0] -eq [char]39 -or $v[0] -eq [char]34)) {
                $v = $v.Substring(1, $v.Length - 2)
            }
            return $v
        }
        $scope = & $read 'applyTo'
        if (-not $scope) { $scope = & $read 'globs' }
        if (-not $scope) { $scope = '**' }
        $summary = & $read 'description'
        if (-not $summary) {
            $h = [regex]::Match($rest, '(?m)^#\s+(.+)$')
            $summary = if ($h.Success) { $h.Groups[1].Value.Trim() } else { [System.IO.Path]::GetFileName($path) }
        }
        if ($summary.Length -gt 100) { $summary = $summary.Substring(0, 99).TrimEnd() + [char]0x2026 }
        if (-not $groups.Contains($scope)) { $groups[$scope] = New-Object System.Collections.Generic.List[string] }
        $groups[$scope].Add('- ' + ($path -replace '\\', '/') + ' - ' + $summary)
    }
    if ($groups.Count -eq 0) { return 'No global rules are installed.' }
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('Codex does not import files from AGENTS.md, so the rules below are NOT loaded for you.')
    $out.Add('Open the ones that apply with your file tools before you work, and follow them.')
    if ($groups.Contains('**')) {
        $out.Add('')
        $out.Add('Read at the start of every task:')
        foreach ($entry in $groups['**']) { $out.Add($entry) }
        $groups.Remove('**')
    }
    foreach ($scope in @($groups.Keys)) {
        $out.Add('')
        $out.Add('When editing files matching `' + $scope + '`:')
        foreach ($entry in $groups[$scope]) { $out.Add($entry) }
    }
    return ($out -join "`n")
}

function Build-GlobalItems {
    # The manifest's per-item list for one category (rules or hooks). The catalogue is the owned
    # allowlist, so a name outside it can never enter or survive a hand edit; a name the manifest
    # has not seen joins as installed:true; the flag the operator already set is kept, false
    # included. Same rule Build-InstallationJson applies to skills. Sorted ordinally, so the order
    # matches the bash port rather than the host culture's collation.
    param([string[]] $Catalog, [object] $Existing)
    $known = @{}
    foreach ($entry in @($Existing)) {
        if ($null -ne $entry -and $entry.PSObject.Properties['name'] -and $entry.name -is [string]) {
            $flag = $false
            if ($entry.PSObject.Properties['installed']) { $flag = [bool] $entry.installed }
            $known[$entry.name] = $flag
        }
    }
    $names = [string[]] @($Catalog | Select-Object -Unique)
    [Array]::Sort($names, [System.StringComparer]::Ordinal)
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $names) {
        $installed = $true
        if ($known.ContainsKey($name)) { $installed = $known[$name] }
        $items.Add([ordered]@{ name = $name; installed = $installed })
    }
    return , $items
}

function Get-GlobalItemNames {
    param([object] $Items, [bool] $Installed)
    @($Items | Where-Object { [bool] $_.installed -eq $Installed } | ForEach-Object { $_.name })
}

function Add-GlobalLink {
    # Record a link/edit for --uninstall. Tabs separate fields; a tab cannot
    # appear in a path on any supported OS, so the split is unambiguous.
    param([string] $Type, [string] $Path, [string] $Detail = '')
    if ($Detail) { $script:Links.Add("$Type`t$Path`t$Detail") } else { $script:Links.Add("$Type`t$Path") }
}

function Test-InstallSnapshot {
    # True when an install-time snapshot (<FILE>.smooth-devex-<digits>) of Path already exists. Only
    # numeric install-time snapshots count; an uninstall-time one (smooth-devex-uninstall-*) must not
    # suppress a fresh install backup on the next run. Matched by regex: -Filter understands only *
    # and ?, so a [0-9] class there is taken literally, never finds the earlier snapshot, and a
    # re-run would then snapshot our own already-modified file as if it were the operator's.
    param([string] $Path)
    $dir = Split-Path -Parent $Path
    $snapshotPattern = '^' + [regex]::Escape([System.IO.Path]::GetFileName($Path) + '.smooth-devex-') + '[0-9]'
    $prior = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $snapshotPattern }
    return [bool] $prior
}

function Backup-Inplace {
    # Snapshot an operator-owned file the installer is about to append to, as
    # <FILE>.smooth-devex-<UTC YYYYMMDD-HHMMSS>, exactly once. Echoes the backup
    # path, or nothing when there is no pre-existing file to protect (a file the
    # installer is about to create is not snapshotted, and a file already
    # snapshotted by an earlier run is not re-snapshotted — so --uninstall
    # restores the genuinely pre-install content, never our own earlier append).
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    if (Test-InstallSnapshot -Path $Path) { return '' }
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $backup = "$Path.smooth-devex-$stamp"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    return $backup
}

function Remove-SkillContext {
    # Delete the AGENTS.md files inside an installed skill folder. A skill's
    # AGENTS.md documents the owner repo's local-dev context and improvements; it
    # is not part of the runnable payload a consumer should inherit, so the
    # installer removes it from the copy while leaving the source's in place.
    param([string] $Path)
    if ([System.IO.FileInfo]::new($Path).LinkTarget) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File |
        Where-Object { $_.Name -eq 'AGENTS.md' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}

function Read-GlobalManifest {
    # Missing reads as $null (a first global install). A *corrupt* file is a hard
    # error, never a silent reset from defaults — same rule as the repo manifest.
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Fail "$Path is empty or whitespace-only; fix or delete it - not treating it as a first install"
    }
    try { return ($raw | ConvertFrom-Json) }
    catch {
        Fail "$Path is not valid JSON ($($_.Exception.Message)); fix or delete it - not treating it as a first install"
    }
}

function Link-SkillInto {
    # Link the store's copy of NAME into DestDir/NAME (Codex and Claude both call
    # this). An existing correct link is kept; a real file/dir or a foreign link at
    # the path is reported and left untouched. On Windows without symlink
    # privilege, falls back to a junction (degraded: git records the junction
    # target's contents as real files).
    param([string] $DestDir, [string] $Name, [string] $LinkType)
    $link = Join-Path $DestDir $Name
    $target = Join-Path (Join-Path $script:GlbRoot 'skills') $Name
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Info "WARNING: $target missing - no global skill symlink for $Name"
        return
    }
    $linkTaken = Test-Path -LiteralPath $link
    if (-not $linkTaken) {
        $dangling = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        $linkTaken = ($null -ne $dangling) -and ($null -ne $dangling.LinkType)
    }
    if ($linkTaken) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.LinkType) {
            if ($item.Target -eq $target) { Write-Info "Global skill $Name already linked into $(Split-Path -Leaf $DestDir)"; return }
            Write-Info "WARNING: $link is a link to somewhere else - left untouched"
            return
        }
        Write-Info "WARNING: $link already exists - left untouched"
        return
    }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    try { New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null }
    catch { New-Item -ItemType Junction -Path $link -Target $target | Out-Null }
    Add-GlobalLink $LinkType $link $target
    Write-Info "Linked global skill $Name -> $target"
}

function Sync-GlobalSkill {
    param([string] $Name)
    Link-SkillInto -DestDir (Join-Path $script:CodexHome 'skills') -Name $Name -LinkType 'skill-link'
}

function Sync-GlobalClaude {
    param([string] $Name)
    Link-SkillInto -DestDir (Join-Path $script:ClaudeHome 'skills') -Name $Name -LinkType 'claude-skill'
}

function Install-GlobalClaude {
    # Symlink each installed owned skill into Claude Code's skills dir for global
    # availability, when Claude's config dir exists. Wired in addition to
    # Codex/OpenCode, never instead of.
    param([object] $Manifest)
    if (-not $script:HarnessClaude) {
        Remove-StoreLinks -Dir (Join-Path $script:ClaudeHome 'skills') -Subdir 'skills'
        return
    }
    if (-not (Test-Path -LiteralPath $script:ClaudeHome -PathType Container)) {
        Write-Info "Claude Code config not found ($($script:ClaudeHome)) - skipping global Claude wiring"
        return
    }
    if (-not $Manifest -or -not $Manifest.skills) { return }
    foreach ($skill in $Manifest.skills) {
        if ($skill.installed -and (Test-OwnedSkill -Name $skill.name)) {
            Sync-GlobalClaude -Name $skill.name
        }
    }
}

function Install-GlobalClaudeRules {
    # Symlink every store rule into Claude Code's global rules dir (~/.claude/rules)
    # so Claude Code loads them across sessions.
    if (-not $script:HarnessClaude) {
        Remove-StoreLinks -Dir (Join-Path $script:ClaudeHome 'rules') -Subdir 'rules'
        return
    }
    if (-not (Test-Path -LiteralPath $script:ClaudeHome -PathType Container)) {
        Write-Info "Claude Code config not found ($($script:ClaudeHome)) - skipping global Claude rules"
        return
    }
    foreach ($rel in $script:RulesOn) {
        $target = Join-Path (Join-Path $script:GlbRoot 'rules') $rel
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $link = Join-Path (Join-Path $script:ClaudeHome 'rules') $rel
            Link-StoreFile -DestLink $link -Target $target -LinkType 'claude-rule'
        }
    }
    # A rule flipped to installed:false is unwired too, so the flag turns it off rather than only
    # stopping updates. The store copy stays (operator edits preserved).
    foreach ($rel in $script:RulesOff) {
        Unlink-StoreFile -DestLink (Join-Path (Join-Path $script:ClaudeHome 'rules') $rel) `
            -Target (Join-Path (Join-Path $script:GlbRoot 'rules') $rel)
    }
}

function Unlink-StoreFile {
    # Remove DestLink only when it is the symlink this installer made (it points at Target). A real
    # file or a foreign link is never touched.
    param([string] $DestLink, [string] $Target)
    $item = Get-Item -LiteralPath $DestLink -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and $item.LinkType -and $item.Target -eq $Target) {
        Remove-Item -LiteralPath $DestLink -Force
        Write-Info "Unlinked disabled rule $DestLink"
    }
}

function Link-StoreFile {
    # Symlink a store file at $DestLink. Kept when a correct link exists; a real
    # file/dir or a foreign link at the path is reported and left untouched.
    # Records the link for --uninstall. Used for OpenCode commands, where the link
    # points at a skill's SKILL.md (command filename = command name).
    param([string] $DestLink, [string] $Target, [string] $LinkType)
    $linkTaken = Test-Path -LiteralPath $DestLink
    if (-not $linkTaken) {
        $dangling = Get-Item -LiteralPath $DestLink -Force -ErrorAction SilentlyContinue
        $linkTaken = ($null -ne $dangling) -and ($null -ne $dangling.LinkType)
    }
    if ($linkTaken) {
        $item = Get-Item -LiteralPath $DestLink -Force
        if ($item.LinkType) {
            if ($item.Target -eq $Target) { Write-Info "Already linked: $DestLink -> $Target"; return }
            Write-Info "WARNING: $DestLink is a link to somewhere else - left untouched"; return
        }
        Write-Info "WARNING: $DestLink already exists - left untouched"; return
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $DestLink) -Force | Out-Null
    try { New-Item -ItemType SymbolicLink -Path $DestLink -Target $Target | Out-Null }
    catch { New-Item -ItemType Junction -Path $DestLink -Target $Target | Out-Null }
    Add-GlobalLink $LinkType $DestLink $Target
    Write-Info "Linked $DestLink -> $Target"
}

function Install-GlobalOpencode {
    # Symlink each installed owned skill into OpenCode's own skills dir so OpenCode
    # loads the full skill (SKILL.md + scripts) via the native skill tool. Skipped
    # when OpenCode's config dir is absent.
    param([object] $Manifest)
    if (-not $script:HarnessOpencode) {
        Remove-StoreLinks -Dir (Join-Path $script:OpenCodeConfig 'skills') -Subdir 'skills'
        return
    }
    if (-not (Test-Path -LiteralPath $script:OpenCodeConfig -PathType Container)) {
        Write-Info "OpenCode config not found ($($script:OpenCodeConfig)) - skipping global OpenCode wiring"
        return
    }
    if ($Manifest -and $Manifest.skills) {
        foreach ($skill in $Manifest.skills) {
            if ($skill.installed -and (Test-OwnedSkill -Name $skill.name)) {
                Link-SkillInto -DestDir (Join-Path $script:OpenCodeConfig 'skills') -Name $skill.name -LinkType 'opencode-skill'
            }
        }
    }
}

function Install-GlobalOpencodeConfig {
    # Make the operator's opencode.json `instructions` list exactly the installed:true store rules,
    # one absolute path per rule. Per-file entries (not a rules/** glob) are what let a single rule
    # be switched off. Entries under the store's rules dir that are no longer wanted - a disabled
    # rule, or the glob pair an earlier install wrote - are dropped; everything else the operator
    # put there is kept. Snapshots the file, records the edit for --uninstall. instructions must
    # stay a JSON array (a List<string>, never a bare string), and paths use forward slashes on
    # every platform.
    $config = Join-Path $script:OpenCodeConfig 'opencode.json'
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
        Write-Info "opencode.json not found ($config) - skipping global rules instructions"
        return
    }
    $prefix = ((Join-Path $script:GlbRoot 'rules') -replace '\\', '/') + '/'
    # A harness that is off wants no entries; with none of ours present there is nothing to remove,
    # and snapshotting the file for no edit would leave a stray first snapshot behind.
    $wantedRules = $script:RulesOn
    if (-not $script:HarnessOpencode) {
        $wantedRules = @()
        if (-not (Get-Content -LiteralPath $config -Raw).Contains($prefix)) {
            Write-Info "OpenCode is off and $config holds no store rules - nothing to remove"
            return
        }
    }
    $backup = Backup-Inplace -Path $config
    if ($backup) { Write-Info "Backed up $config -> $backup" }
    $data = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json -AsHashtable
    $inst = [System.Collections.Generic.List[string]]::new()
    if ($data.ContainsKey('instructions')) {
        foreach ($g in @($data['instructions'])) { if ($g) { $inst.Add([string]$g) } }
    }
    $wanted = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in $wantedRules) { $wanted.Add($prefix + $rel) }
    $wantedSet = [System.Collections.Generic.HashSet[string]]::new([string[]] $wanted.ToArray(), [System.StringComparer]::Ordinal)
    $kept = [System.Collections.Generic.List[string]]::new()
    foreach ($g in $inst) {
        if ($g.StartsWith($prefix, [System.StringComparison]::Ordinal) -and -not $wantedSet.Contains($g)) { continue }
        $kept.Add($g)
    }
    $changed = ($kept.Count -ne $inst.Count)
    foreach ($w in $wanted) {
        if (-not $kept.Contains($w)) { $kept.Add($w); $changed = $true }
    }
    if ($changed) {
        if ($kept.Count -gt 0) { $data['instructions'] = @($kept) } else { $data.Remove('instructions') }
        [System.IO.File]::WriteAllText($config, (($data | ConvertTo-Json -Depth 10) + "`n"), [System.Text.UTF8Encoding]::new($false))
        Add-GlobalLink 'opencode-config' $config $backup
        Write-Info "Updated global rules instructions in $config"
    } else {
        Write-Info "OpenCode instructions already match the installed rules in $config"
    }
}

function Install-GlobalSkills {
    # Copy the enabled owned skills into the central store, then symlink each.
    # Only installed:true entries are refreshed AND symlinked, so an
    # installed:false skill is neither overwritten (local edits preserved) nor
    # exposed to Codex; the owned-name guard still applies.
    param([object] $Manifest)
    $repoSkills = Join-Path $script:TempRepo '.agents/skills'
    $enabled = @()
    if ($Manifest -and $Manifest.skills) {
        $enabled = @($Manifest.skills | Where-Object { $_.installed } | Select-Object -ExpandProperty name)
    }
    foreach ($name in $enabled) {
        if (-not (Test-OwnedSkill -Name $name)) { continue }
        $source = Join-Path $repoSkills $name
        if (Test-Path -LiteralPath $source -PathType Container) {
            $dest = Join-Path (Join-Path $script:GlbRoot 'skills') $name
            Remove-PathEntry -Path $dest
            Copy-Wet -Source $source -Dest $dest
            Remove-Tests -Root $dest
            Remove-SkillContext -Path $dest
            Write-Info "Stored global skill $name"
        } else {
            Write-Info "WARNING: skill $name not found in repo - not stored"
        }
    }
    if ($script:HarnessCodex) {
        foreach ($name in $enabled) {
            if (Test-OwnedSkill -Name $name) { Sync-GlobalSkill -Name $name }
        }
    } else {
        Remove-StoreLinks -Dir (Join-Path $script:CodexHome 'skills') -Subdir 'skills'
    }
}

function Install-GlobalRules {
    # Copy the installed:true rule files into the store, preserving relative paths. Overwrite,
    # never delete: an installed:false rule is neither refreshed (operator edits in the store
    # survive) nor wired.
    $sourceRules = Join-Path $script:TempRepo '.github/instructions'
    if (-not (Test-Path -LiteralPath $sourceRules -PathType Container)) {
        Write-Info 'No .github/instructions in source - nothing to install for global rules'
        return
    }
    foreach ($rel in $script:RulesOn) {
        $source = Join-Path $sourceRules $rel
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $dest = Join-Path (Join-Path $script:GlbRoot 'rules') $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Wet -Source $source -Dest $dest
            Write-Info "Stored global rule $rel"
        } else {
            Write-Info "WARNING: rule $rel not found in repo - not stored"
        }
    }
}

function Write-GlobalAgents {
    # Generate the store-level AGENTS.md: the rule index (see Format-RulesIndex). It is the same text
    # Install-GlobalInstructions inlines into ~/.codex/AGENTS.md; this copy is for people and for tools
    # that read the store directly.
    $file = Join-Path $script:GlbRoot 'AGENTS.md'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Smooth DevEx - installed global instructions')
    $lines.Add('# (managed by install-skills -g; do not edit)')
    $lines.Add('')
    $lines.Add("<!-- $($script:GlobalMarker): regenerated by install-skills -->")
    $lines.Add('')
    $lines.Add((Format-RulesIndex))
    $lines.Add('')
    [System.IO.File]::WriteAllLines($file, $lines, [System.Text.UTF8Encoding]::new($false))
    Write-Info "Wrote global rules index $file"
}

function Install-GlobalInstructions {
    # Keep one delimited block in $CODEX_HOME/AGENTS.md holding the rule index. Codex does not resolve
    # @-imports, so the index is inlined, not imported. The block is replaced in place on every run (it
    # follows the installed:false flags) and an older two-line @-import block is migrated by the same
    # replacement. Anything outside the block, notably an operator's @.../RTK.md line, is never
    # touched. A missing AGENTS.md is created with an RTK-preserving header.
    Write-GlobalAgents
    $codexAgents = Join-Path $script:CodexHome 'AGENTS.md'
    $rtk = Join-Path $script:CodexHome 'RTK.md'
    $rtkLine = ''
    if (Test-Path -LiteralPath $rtk -PathType Leaf) { $rtkLine = '@' + ($rtk -replace '\\', '/') }
    if (-not $script:HarnessCodex) {
        Remove-CodexImport -File $codexAgents -RtkLine $rtkLine
        return
    }
    $index = Format-RulesIndex
    if (-not (Test-Path -LiteralPath $codexAgents -PathType Leaf)) {
        $seed = ''
        if ($rtkLine) { $seed = $rtkLine + "`n" }
        [System.IO.File]::WriteAllText($codexAgents, $seed, [System.Text.UTF8Encoding]::new($false))
        [void] (Set-CodexBlock -File $codexAgents -Body $index)
        Add-GlobalLink 'agents-import' $codexAgents
        Write-Info "Created $codexAgents with the global rules index"
        return
    }
    if ((Get-CodexBlockState -File $codexAgents) -eq 'none') {
        # We are about to add to a pre-existing operator-owned file: snapshot it first so --uninstall
        # restores the operator's content. Only here: a file that already holds our block either has
        # its snapshot from the first install or was created by us, and a snapshot of that would
        # capture our own block.
        $backup = Backup-Inplace -Path $codexAgents
        if ($backup) { Write-Info "Backed up $codexAgents -> $backup" }
        [void] (Set-CodexBlock -File $codexAgents -Body $index)
        Add-GlobalLink 'agents-import' $codexAgents $backup
        Write-Info "Appended the global rules index to $codexAgents"
        return
    }
    if ((Set-CodexBlock -File $codexAgents -Body $index) -eq 'changed') {
        Write-Info "Updated the global rules index in $codexAgents"
    } else {
        Write-Info "Global rules index already current in $codexAgents"
    }
}

$script:CodexRulesHeader = '# installer-owned-global-rules (generated by install-skills -g; do not edit)'

function Install-GlobalCodexRules {
    # Keep ~/.codex/rules/smooth-devex.rules, a Codex command-approval policy derived from the
    # git/git-policy rule. Codex .rules files are Starlark prefix_rule()s that gate which commands run
    # outside the sandbox; they cannot carry instructions, which is why the other rules travel as an
    # AGENTS.md index. A file of our own, never default.rules: Codex appends the operator's permanent
    # approvals there. Written only while codex is on and git-policy is installed:true; otherwise
    # removed, but only when it is ours (first line carries the header). Mirrors the bash port.
    $file = Join-Path (Join-Path $script:CodexHome 'rules') 'smooth-devex.rules'
    $want = $script:HarnessCodex -and ($script:RulesOn -contains 'git/git-policy.instructions.md')
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        $first = Get-Content -LiteralPath $file -TotalCount 1
        if ($first -ne $script:CodexRulesHeader) {
            Write-Info "WARNING: $file exists and is not ours - left untouched"
            return
        }
    }
    if (-not $want) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force
            Write-Info "Removed $file"
        }
        return
    }
    $body = @'
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
'@
    $content = $script:CodexRulesHeader + "`n" + ($body -replace "`r`n", "`n").TrimEnd("`n")
    if ((Test-Path -LiteralPath $file -PathType Leaf) -and ((Get-Content -LiteralPath $file -Raw).TrimEnd("`r", "`n") -ceq $content)) {
        Write-Info "Codex rules already current in $file"
        return
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
    [System.IO.File]::WriteAllText($file, $content + "`n", [System.Text.UTF8Encoding]::new($false))
    Add-GlobalLink 'codex-rules' $file
    Write-Info "Wrote $file - restart Codex to load it"
}

function Install-GlobalHooks {
    # Copy the owned hooks into the store, then JSON-merge them into
    # ~/.codex/hooks.json under UserPromptSubmit only, with absolute store
    # commands, deduped by exact command match. Preserves the gk and
    # code-review-graph entries that already live there. Backs the file up once
    # (only when this run is the first to modify a file that already existed), so
    # --uninstall can restore the pre-install state. UserPromptSubmit is a
    # matcher-ignored event, so the new chunk omits matcher.
    $hooksFile = Join-Path $script:CodexHome 'hooks.json'
    $sourceHooks = Join-Path $script:TempRepo '.agents/hooks'
    $ownedCmds = New-Object System.Collections.Generic.List[string]
    $disabledCmds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (-not (Test-Path -LiteralPath $sourceHooks -PathType Container)) {
        Write-Info 'No .agents/hooks in source - nothing to install for global hooks'
        return
    }
    foreach ($name in $script:HooksOn) {
        $source = Join-Path $sourceHooks $name
        $dest = Join-Path (Join-Path $script:GlbRoot 'hooks') $name
        if (Test-Path -LiteralPath $source) {
            Copy-Wet -Source $source -Dest $dest
            # Preserve the source exec bit per owned file, never a wildcard over the
            # directory. `test -x` is portable across Unix; UnixFileMode is not.
            if ($name -like '*.sh' -and ($IsLinux -or $IsMacOS)) {
                & test -x $source; if ($LASTEXITCODE -eq 0) { & chmod +x $dest 2>$null }
            }
            Write-Info "Stored global hook $name"
        } else {
            Write-Info "WARNING: hook $name not found in repo - not stored"
        }
    }
    foreach ($name in $script:HooksOn) {
        $dest = Join-Path (Join-Path $script:GlbRoot 'hooks') $name
        if (Test-Path -LiteralPath $dest -PathType Leaf) { $ownedCmds.Add($dest) }
    }
    # A disabled hook's command is removed from hooks.json (it stays in the store), so the flag
    # turns the hook off rather than only stopping updates.
    foreach ($name in $script:HooksOff) {
        [void] $disabledCmds.Add((Join-Path (Join-Path $script:GlbRoot 'hooks') $name))
    }
    # Codex off: register nothing, and remove every command under the store's hooks dir. They are
    # matched by that prefix, so a hook that is no longer owned goes too.
    $purgePrefix = ''
    if (-not $script:HarnessCodex) {
        $ownedCmds.Clear()
        $purgePrefix = (Join-Path $script:GlbRoot 'hooks') + [System.IO.Path]::DirectorySeparatorChar
    }
    if ($ownedCmds.Count -eq 0 -and $disabledCmds.Count -eq 0 -and -not $purgePrefix) { Write-Info 'No owned hooks to register globally'; return }

    $data = $null
    if (Test-Path -LiteralPath $hooksFile -PathType Leaf) {
        $raw = Get-Content -LiteralPath $hooksFile -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try { $data = $raw | ConvertFrom-Json -AsHashtable }
            catch { Fail "$hooksFile is not valid JSON ($($_.Exception.Message)); fix or delete it" }
        }
    }
    if ($null -eq $data) { $data = @{} }
    if (-not $data.ContainsKey('hooks')) { $data['hooks'] = @{} }
    $hooks = $data['hooks']
    $ups = if ($hooks.ContainsKey('UserPromptSubmit')) { $hooks['UserPromptSubmit'] } else { @() }
    # Drop the commands of disabled hooks. Only a group this empties is dropped; a group the
    # operator shares with other commands keeps them.
    $removed = 0
    $upsList = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($ups)) {
        if ($group -is [hashtable] -and $group.ContainsKey('hooks') -and $null -ne $group['hooks']) {
            $all = @($group['hooks'])
            $keep = @($all | Where-Object {
                $dropIt = $_ -is [hashtable] -and $_.ContainsKey('command') -and
                    ($disabledCmds.Contains([string]$_['command']) -or
                     ($purgePrefix -and ([string]$_['command']).StartsWith($purgePrefix, [System.StringComparison]::Ordinal)))
                -not $dropIt
            })
            $dropped = $all.Count - $keep.Count
            if ($dropped -gt 0) {
                $removed += $dropped
                if ($keep.Count -eq 0) { continue }
                $group['hooks'] = $keep
            }
        }
        $upsList.Add($group)
    }
    $existing = @{}
    foreach ($group in $upsList) {
        if ($group -is [hashtable] -and $group.ContainsKey('hooks')) {
            foreach ($h in @($group['hooks'])) {
                if ($h -is [hashtable] -and $h.ContainsKey('command')) { $existing[[string]$h['command']] = $true }
            }
        }
    }
    $new = @()
    foreach ($cmd in $ownedCmds) {
        if (-not $existing.ContainsKey([string]$cmd)) { $new += @{ command = $cmd; type = 'command' } }
    }
    $changed = ($new.Count -gt 0) -or ($removed -gt 0)
    $backupPath = ''
    if ($changed -and (Test-Path -LiteralPath $hooksFile -PathType Leaf)) {
        $backupPath = Backup-Inplace -Path $hooksFile
    }
    if ($changed) {
        if ($new.Count -gt 0) { $upsList.Add(@{ hooks = $new }) }
        $hooks['UserPromptSubmit'] = $upsList
        [System.IO.File]::WriteAllText($hooksFile, (($data | ConvertTo-Json -Depth 10) + "`n"), [System.Text.UTF8Encoding]::new($false))
    }
    if ($backupPath) { Write-Info "Backed up $hooksFile -> $backupPath" }
    if ($changed) {
        Add-GlobalLink 'hooks-merge' $hooksFile $backupPath
        if ($new.Count -gt 0) { Write-Info "Registered $($new.Count) owned hook(s) in $hooksFile" }
        if ($removed -gt 0) { Write-Info "Unregistered $removed disabled hook(s) from $hooksFile" }
    } else {
        Write-Info "Owned hooks already match the installed set in $hooksFile"
    }
    if ($script:HarnessCodex) { Write-Info 'Trust the newly registered Codex hooks with: /hooks' }
}

function Write-GlobalManifest {
    # Write the global manifest. SKILLS_JSON is the reconciled skills document
    # (or an existing one for a rules/hooks-only run); 'updated' is refreshed, the
    # recorded links are merged with the previous run's so a re-run never wipes
    # the uninstall history, and the links array is attached.
    param([string] $SkillsJson)
    $linksJson = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $script:Links) {
        $parts = $line -split "`t"
        $entry = [ordered]@{ type = $parts[0]; path = $parts[1] }
        if ($parts.Count -gt 2 -and $parts[2]) { $entry['detail'] = $parts[2] }
        $linksJson.Add($entry)
    }
    $existing = $null
    if (Test-Path -LiteralPath $script:GlobalManifest -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $script:GlobalManifest -Raw
            if ($raw.Trim()) { $existing = $raw | ConvertFrom-Json -AsHashtable }
        } catch { $existing = $null }
    }
    $data = $null
    if ($SkillsJson) {
        try { $data = $SkillsJson | ConvertFrom-Json -AsHashtable } catch { $data = $null }
    }
    if ($null -eq $data) { $data = $existing }
    if ($null -eq $data) { $data = @{} }
    if (-not $data.ContainsKey('skills')) {
        $data['skills'] = @()
    }
    if (-not $data.ContainsKey('decisions_enabled')) {
        $data['decisions_enabled'] = $false
    }
    # A category this run covered brings its reconciled list; one it did not keeps the list the
    # previous run recorded (absent until that category has run once).
    $perItem = [ordered]@{ rules = $script:GlbRules; hooks = $script:GlbHooks }
    foreach ($key in $perItem.Keys) {
        if ($null -ne $perItem[$key]) {
            $data[$key] = $perItem[$key]
        } elseif (-not $data.ContainsKey($key) -and $null -ne $existing -and $existing.ContainsKey($key)) {
            $data[$key] = $existing[$key]
        }
    }
    if ($null -ne $script:GlbHarnesses) {
        $data['harnesses'] = $script:GlbHarnesses
    } elseif (-not $data.ContainsKey('harnesses') -and $null -ne $existing -and $existing.ContainsKey('harnesses')) {
        $data['harnesses'] = $existing['harnesses']
    }
    # Merge links: carry forward the previous run's records, upsert new ones by
    # (type, path) so a re-run updates in place instead of accumulating.
    $merged = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    if ($existing -and $existing.ContainsKey('links')) {
        foreach ($link in @($existing['links'])) {
            $merged.Add($link)
            $seen["$($link.type)|$($link.path)"] = $true
        }
    }
    foreach ($link in $linksJson) {
        $key = "$($link.type)|$($link.path)"
        if ($seen.ContainsKey($key)) {
            for ($i = 0; $i -lt $merged.Count; $i++) {
                if ($merged[$i].type -eq $link.type -and $merged[$i].path -eq $link.path) {
                    # A re-run that edits the same file again (a rule or hook flipped off)
                    # snapshots nothing, because the first run already did. Its record has no
                    # detail, and must not overwrite the one that points at the snapshot
                    # --uninstall restores from.
                    if (-not $link.Contains('detail') -and $merged[$i] -is [System.Collections.IDictionary] -and $merged[$i].Contains('detail')) {
                        $link['detail'] = $merged[$i]['detail']
                    }
                    $merged[$i] = $link
                    break
                }
            }
        } else {
            $merged.Add($link)
            $seen[$key] = $true
        }
    }
    # `enabled` is a status the installer recomputes every run, not a control: true exactly when the
    # symlink is on disk and points where the record says. A link the installer unwired (its item or
    # its harness turned off) stays recorded, as enabled:false, so --uninstall and a re-enable still
    # know about it. Config-edit records (agents-import, hooks-merge, ...) carry no such field. Every
    # record is rewritten with a fixed key order (type, path, detail, enabled).
    $symlinkTypes = 'skill-link', 'claude-skill', 'opencode-skill', 'claude-rule'
    for ($i = 0; $i -lt $merged.Count; $i++) {
        $rec = $merged[$i]
        if ($symlinkTypes -contains [string] $rec['type']) {
            $item = Get-Item -LiteralPath ([string] $rec['path']) -Force -ErrorAction SilentlyContinue
            $rec['enabled'] = ($null -ne $item) -and [bool] $item.LinkType -and (([string] $item.Target) -eq [string] $rec['detail'])
        }
        $ordered = [ordered]@{}
        foreach ($k in 'type', 'path', 'detail', 'enabled') { if ($rec.Contains($k)) { $ordered[$k] = $rec[$k] } }
        foreach ($k in $rec.Keys) { if (-not $ordered.Contains($k)) { $ordered[$k] = $rec[$k] } }
        $merged[$i] = $ordered
    }
    $data['updated'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $data['links'] = $merged
    $out = [ordered]@{}
    foreach ($k in 'updated', 'decisions_enabled', 'harnesses', 'skills', 'rules', 'hooks', 'links') {
        if ($data.ContainsKey($k)) { $out[$k] = $data[$k] }
    }
    foreach ($k in $data.Keys) { if (-not $out.Contains($k)) { $out[$k] = $data[$k] } }
    [System.IO.File]::WriteAllText($script:GlobalManifest, (($out | ConvertTo-Json -Depth 10) + "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Info "Wrote global manifest $($script:GlobalManifest)"
}

function Invoke-GlobalInstall {
    # The -g entry point: build the central store, wire skills, rules/instructions
    # and hooks into Codex, and write the manifest last.
    New-Item -ItemType Directory -Path (Join-Path $script:GlbRoot 'skills') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:GlbRoot 'rules') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:GlbRoot 'hooks') -Force | Out-Null
    New-Item -ItemType Directory -Path $script:CodexHome -Force | Out-Null

    Invoke-SourceClone -Repo $SkillsRepo -Branch $SkillsBranch

    $existing = Read-GlobalManifest -Path $script:GlobalManifest
    $newJson = ''

    # Which harnesses to wire into. Resolved whatever categories this run covers: a harness the
    # manifest has not seen joins as on, and an off one is not installed into and is cleaned of
    # anything this installer put there.
    $script:GlbHarnesses = Build-Harnesses -Existing $existing
    $script:HarnessClaude = [bool] $script:GlbHarnesses['claude-code']
    $script:HarnessCodex = [bool] $script:GlbHarnesses['codex']
    $script:HarnessOpencode = [bool] $script:GlbHarnesses['opencode']
    if (-not $script:HarnessClaude) { Write-Info 'Harness claude-code is off - not installing, removing what is wired' }
    if (-not $script:HarnessCodex) { Write-Info 'Harness codex is off - not installing, removing what is wired' }
    if (-not $script:HarnessOpencode) { Write-Info 'Harness opencode is off - not installing, removing what is wired' }

    # Rules and hooks carry the same per-item installed flag skills do. Only a category this run
    # covers is reconciled; the others keep what the manifest already says.
    if ($script:DoRules) {
        $existingRules = if ($existing -and $existing.PSObject.Properties['rules']) { $existing.rules } else { $null }
        $script:GlbRules = Build-GlobalItems -Catalog $script:OwnedRules -Existing $existingRules
        $script:RulesOn = @(Get-GlobalItemNames -Items $script:GlbRules -Installed $true)
        $script:RulesOff = @(Get-GlobalItemNames -Items $script:GlbRules -Installed $false)
    }
    if ($script:DoHooks) {
        $existingHooks = if ($existing -and $existing.PSObject.Properties['hooks']) { $existing.hooks } else { $null }
        $script:GlbHooks = Build-GlobalItems -Catalog $script:OwnedHooks -Existing $existingHooks
        $script:HooksOn = @(Get-GlobalItemNames -Items $script:GlbHooks -Installed $true)
        $script:HooksOff = @(Get-GlobalItemNames -Items $script:GlbHooks -Installed $false)
    }

    if ($script:DoSkills) {
        $hasPref = Test-DecisionsPropertyExists -ExistingJson $existing
        if ($script:DoDecisions) {
            $script:DecisionsEnabled = $true
            Write-Info 'Decisions enabled via -d'
        } elseif ($hasPref) {
            $script:DecisionsEnabled = [bool] (Get-DecisionsEnabled -ExistingJson $existing)
            Write-Info "Decisions preference saved ($($script:DecisionsEnabled)) - skipping prompt"
        } else {
            Prompt-Decisions
        }
        if ($script:DecisionsEnabled) { Write-DecisionsEnv }

        $diskSkills = @(Get-Skills -Root (Join-Path $script:GlbRoot 'skills'))
        $sourceSkills = @(Get-Skills -Root (Join-Path $script:TempRepo '.agents/skills'))
        # The global manifest may hold only harnesses{} (an operator pre-seeded it before a first
        # install), and strict mode throws on a property that is absent.
        $existingSkills = @()
        if ($existing -and $existing.PSObject.Properties['skills'] -and $existing.skills) { $existingSkills = @($existing.skills) }
        $newJson = Build-InstallationJson -Updated ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH\:mm\:ssZ')) `
            -DiskSkills $diskSkills -SourceSkills $sourceSkills -ExistingSkills $existingSkills `
            -DecisionsEnabled $script:DecisionsEnabled

        Write-Info 'Storing and wiring global skills...'
        Install-GlobalSkills -Manifest ($newJson | ConvertFrom-Json)
        Write-Info 'Registering global OpenCode commands...'
        Install-GlobalOpencode -Manifest ($newJson | ConvertFrom-Json)
        Write-Info 'Registering global Claude skills...'
        Install-GlobalClaude -Manifest ($newJson | ConvertFrom-Json)
    }

    if ($script:DoRules) {
        Write-Info 'Storing global rules...'
        Install-GlobalRules
        Write-Info 'Writing global instructions...'
        Install-GlobalInstructions
        Write-Info 'Wiring Claude global rules...'
        Install-GlobalClaudeRules
        Write-Info 'Adding global rules to OpenCode instructions...'
        Install-GlobalOpencodeConfig
        Write-Info 'Writing Codex command-approval rules...'
        Install-GlobalCodexRules
    }

    if ($script:DoHooks) {
        Write-Info 'Registering global hooks...'
        Install-GlobalHooks
    }

    Write-Info 'Writing global manifest...'
    Write-GlobalManifest -SkillsJson $newJson
}

function Uninstall-Global {
    # Remove only what the manifest recorded, and restore the hooks backup if the
    # installer made one. Leaves Codex's .system/, the gk hooks, and the
    # operator's RTK @-import line alone. The store itself is left in place.
    if (-not (Test-Path -LiteralPath $script:GlobalManifest -PathType Leaf)) {
        Write-Info "No global install manifest at $($script:GlobalManifest) - nothing to uninstall"
        return
    }
    $data = Get-Content -LiteralPath $script:GlobalManifest -Raw | ConvertFrom-Json
    foreach ($link in @($data.links)) {
        $typ = $link.type
        $path = $link.path
        # agents-import records carry no detail; a StrictMode dot-access on a
        # missing property throws, so read it through the property collection.
        $detail = if ($link.PSObject.Properties['detail']) { $link.detail } else { '' }
        # Before uninstall restores or removes a content file, snapshot its current
        # (post-install, possibly operator-edited) state so the removal is
        # reversible and post-install edits are not lost. Symlinks are excluded:
        # their content lives in the preserved store.
        if (($typ -eq 'agents-import' -or $typ -eq 'hooks-merge' -or $typ -eq 'profile-edit') -and
            (Test-Path -LiteralPath $path -PathType Leaf)) {
            $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
            $bak = "$path.smooth-devex-uninstall-$stamp"
            Copy-Item -LiteralPath $path -Destination $bak -Force
            Write-Info "Snapshotted pre-uninstall $bak"
        }
        if ($typ -eq 'skill-link' -or $typ -eq 'opencode-command' -or $typ -eq 'opencode-commands-link' -or $typ -eq 'opencode-skill' -or $typ -eq 'claude-skill' -or $typ -eq 'claude-rule') {
            $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and $item.LinkType -and $item.Target -eq $detail) {
                Remove-Item -LiteralPath $path -Force
            }
        } elseif ($typ -eq 'opencode-config') {
            if ($detail -and (Test-Path -LiteralPath $detail -PathType Leaf)) {
                Copy-Item -LiteralPath $detail -Destination $path -Force
                Remove-Item -LiteralPath $detail -Force
            } elseif (Test-Path -LiteralPath $path -PathType Leaf) {
                $data3 = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
                if ($data3.ContainsKey('instructions')) {
                    $glbRules = (Join-Path $script:GlbRoot 'rules') -replace '\\', '/'
                    $rawInstr = @($data3['instructions'])
                    $kept = @($rawInstr | Where-Object { $_ -and -not ([string]$_).StartsWith($glbRules) })
                    if ($kept.Count -eq 0) { $data3.Remove('instructions') } else { $data3['instructions'] = $kept }
                    [System.IO.File]::WriteAllText($path, (($data3 | ConvertTo-Json -Depth 10) + "`n"), [System.Text.UTF8Encoding]::new($false))
                }
            }
        } elseif ($typ -eq 'profile-edit') {
            if ($detail -and (Test-Path -LiteralPath $detail -PathType Leaf)) {
                Copy-Item -LiteralPath $detail -Destination $path -Force
                # Retire the snapshot so a later reinstall snapshots the operator's
                # current content fresh rather than reusing an obsolete backup.
                Remove-Item -LiteralPath $detail -Force
            } elseif (Test-Path -LiteralPath $path -PathType Leaf) {
                # No snapshot: drop the marker-guarded decision env block.
                $lines = Get-Content -LiteralPath $path
                $output = New-Object System.Collections.Generic.List[string]
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -like '*Smooth DevEx — AI Decision Validation*') {
                        if ($output.Count -gt 0 -and $output[$output.Count - 1].Trim() -eq '') { $output.RemoveAt($output.Count - 1) }
                        $i++
                        while ($i -lt $lines.Count -and ($lines[$i] -like '*SMOOTH_DEVEX_DECISIONS*' -or $lines[$i].Trim() -eq '')) { $i++ }
                        $i--
                        continue
                    }
                    $output.Add($lines[$i])
                }
                [System.IO.File]::WriteAllLines($path, $output, [System.Text.UTF8Encoding]::new($false))
            }
        } elseif ($typ -eq 'agents-import') {
            if ($detail -and (Test-Path -LiteralPath $detail -PathType Leaf)) {
                # Restore the pre-append snapshot: strictly the operator's earlier
                # content, never our own append.
                Copy-Item -LiteralPath $detail -Destination $path -Force
                # Retire the snapshot so a later reinstall snapshots the operator's
                # current content fresh rather than reusing an obsolete backup.
                Remove-Item -LiteralPath $detail -Force
            } elseif (Test-Path -LiteralPath $path -PathType Leaf) {
                # No snapshot means the installer created the file from nothing;
                # removing it is the exact inverse of the install (a splice would
                # leave an empty AGENTS.md behind with our RTK header).
                Remove-Item -LiteralPath $path -Force
            }
        } elseif ($typ -eq 'codex-rules') {
            # A file this installer wrote, never a snapshot: remove it only while it still carries
            # our header, so a file the operator replaced it with is left alone.
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $first = Get-Content -LiteralPath $path -TotalCount 1
                if ($first -and $first.Contains('installer-owned-global-rules')) { Remove-Item -LiteralPath $path -Force }
            }
        } elseif ($typ -eq 'hooks-merge') {
            if ($detail -and (Test-Path -LiteralPath $detail -PathType Leaf)) {
                Copy-Item -LiteralPath $detail -Destination $path -Force
                # Retire the snapshot so a later reinstall snapshots the operator's
                # current content fresh rather than reusing an obsolete backup.
                Remove-Item -LiteralPath $detail -Force
            } elseif (Test-Path -LiteralPath $path -PathType Leaf) {
                $data2 = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
                $hooks2 = $data2['hooks']
                $ups2 = @($hooks2['UserPromptSubmit'])
                $kept = @()
                foreach ($group in $ups2) {
                    $cmds = @($group['hooks']) | ForEach-Object { if ($_['command']) { [string]$_['command'] } }
                    if ($cmds.Count -gt 0 -and ($cmds | Where-Object { -not $_.StartsWith((Join-Path $script:GlbRoot 'hooks')) }) -eq $null) { continue }
                    $kept += $group
                }
                $hooks2['UserPromptSubmit'] = $kept
                [System.IO.File]::WriteAllText($path, (($data2 | ConvertTo-Json -Depth 10) + "`n"), [System.Text.UTF8Encoding]::new($false))
            }
        }
    }
    Write-Info "Uninstalled global install - store left at $($script:GlbRoot) (remove it to reclaim space)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Category switches. No switches means everything is on; any switch narrows the run to
# exactly what was named. Switches filter the run only — nothing is persisted.
# -d "decision validation" is a separate opt-in flag, not a category: it does not default on.
$script:DoRules = [bool]$Rules
$script:DoSkills = [bool]$Skills
$script:DoHooks = [bool]$Hooks
$script:DoDecisions = [bool]$Decisions
$script:DoGlobal = [bool]$Global
$script:DoUninstall = [bool]$Uninstall
if (-not ($script:DoRules -or $script:DoSkills -or $script:DoHooks -or $script:DoUninstall)) {
    $script:DoRules = $true
    $script:DoSkills = $true
    $script:DoHooks = $true
}
if ($script:DoUninstall) {
    if (-not $script:DoGlobal) { Fail '--uninstall only applies to the global install — use: install-skills -g --uninstall' }
    if ($SkillsRoot) { Fail "-g cannot be combined with SKILLS_ROOT — the global install owns $($script:GlbRoot)" }
    Uninstall-Global
    Write-Info 'Done.'
    exit 0
}
if ($script:DoGlobal) {
    if ($SkillsRoot) { Fail '-g cannot be combined with SKILLS_ROOT — use the per-repo install (no -g) or unset SKILLS_ROOT' }
    Invoke-GlobalInstall
    Write-Info 'Done.'
    exit 0
}
if ($SkillsRoot) {
    if (-not (Test-Path -LiteralPath $SkillsRoot -PathType Container)) { Fail "SKILLS_ROOT '$SkillsRoot' does not exist" }
    $script:SkillsRootPath = (Resolve-Path -LiteralPath $SkillsRoot).Path
    # The parent of an explicitly forced skills root counts as the agent root, whatever it
    # is named: the shared dir is always a sibling of the skills dir, never inside it.
    $script:AgentRootPath = Split-Path -Parent $script:SkillsRootPath
}
else {
    $script:AgentRootPath = Find-AgentRoot
    $script:SkillsRootPath = Join-Path $script:AgentRootPath 'skills'
    if ($script:DoSkills -and (-not (Test-Path -LiteralPath $script:SkillsRootPath -PathType Container))) {
        New-Item -ItemType Directory -Path $script:SkillsRootPath -Force | Out-Null
    }
}

$sharedDir = Join-Path $script:AgentRootPath '_smooth-devex-shared'
$jsonPath = Join-Path $sharedDir 'installation.json'

Write-Info "Agent root: $($script:AgentRootPath)"
if ($script:DoSkills) { Write-Info "Skills root: $($script:SkillsRootPath)" }

# The clone happens before the manifest is built, because the manifest's catalogue is the source's skill
# list. Derived from disk alone, a first install into an empty folder would decide there was nothing to
# install - an empty folder and a manifest listing nothing, on the operator's very first run.
# `-c core.symlinks=true` on the clone forces symlink checkout in the temp clone regardless of the
# operator's global git config; without it a Windows-default git materializes the source's committed
# symlinks as text files and the payload copy would copy file-blobs instead of directories.
Invoke-SourceClone -Repo $SkillsRepo -Branch $SkillsBranch
Ensure-ConsumerSymlinkSupport -AgentRoot $script:AgentRootPath

if ($script:DoSkills) {
    New-Item -ItemType Directory -Path $sharedDir -Force | Out-Null

    # Fresh start across the layout move: a manifest at the legacy location inside the skills
    # root is ignored, not migrated. The notice tells the operator where to look.
    $legacyJson = Join-Path $script:SkillsRootPath '_smooth-devex-shared/installation.json'
    if (($legacyJson -ne $jsonPath) -and (Test-Path -LiteralPath $legacyJson -PathType Leaf)) {
        Write-Info "Ignoring legacy manifest at $legacyJson - delete it to silence this notice"
    }

    $existing = Read-InstallationJson -Path $jsonPath
    $existingSkills = @()
    if ($existing -and $existing.skills) { $existingSkills = @($existing.skills) }

    # Decision validation opt-in. Prompt only when the preferences entry is missing and -d is not
    # given — a saved true or false is reused without re-asking (idempotent). -d forces decisions on
    # (no prompt, overrides a saved false). Read-Host reads from the console, so the prompt is asked
    # even on a piped `irm | iex` run; falls back to disabled if no host.
    $hasDecisionsPref = Test-DecisionsPropertyExists -ExistingJson $existing
    if ($script:DoDecisions) {
        $script:DecisionsEnabled = $true
        Write-Info 'Decisions enabled via -d'
    } elseif ($hasDecisionsPref) {
        $script:DecisionsEnabled = [bool] (Get-DecisionsEnabled -ExistingJson $existing)
        Write-Info "Decisions preference saved ($($script:DecisionsEnabled)) - skipping prompt"
    } else {
        Prompt-Decisions
    }
    if ($script:DecisionsEnabled) {
        Write-DecisionsEnv
    }

    $diskSkills = @(Get-Skills -Root $script:SkillsRootPath)
    $sourceSkills = @(Get-Skills -Root (Join-Path $script:TempRepo '.agents/skills'))
    # Escaped colons are deliberate. 'T' is a .NET custom-format *modifier* (time designator), so an
    # unescaped 'HH:mm:ss' follows the designator and ':' then renders as the culture's time separator -
    # which is '.' under one locale and ':' under another, producing a timestamp the bash port and this
    # port cannot agree on.
    $newJson = Build-InstallationJson -Updated ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH\:mm\:ssZ')) `
        -DiskSkills $diskSkills -SourceSkills $sourceSkills -ExistingSkills $existingSkills `
        -DecisionsEnabled $script:DecisionsEnabled

    Write-Info 'Syncing installation.json...'
    Write-Info 'Updating installed skills...'
    # The update reads the *merged* manifest, not the pre-existing one. On a first install the old value is
    # $null, so passing it would update nothing on the very run that was supposed to install the skills —
    # the manifest would say installed:true while the folders on disk stayed at whatever was there.
    Update-InstalledSkills -SkillsRoot $script:SkillsRootPath -AgentRoot $script:AgentRootPath -SharedDir $sharedDir -Manifest ($newJson | ConvertFrom-Json)

    Write-Info 'Writing installation.json...'
    [System.IO.File]::WriteAllText($jsonPath, ($newJson + "`n"), [System.Text.UTF8Encoding]::new($false))
}

if ($script:DoRules) {
    Write-Info 'Updating owned rules...'
    Install-OwnedRules -AgentRoot $script:AgentRootPath
}

if ($script:DoHooks) {
    Write-Info 'Updating owned hooks...'
    Install-OwnedHooks -AgentRoot $script:AgentRootPath
}

# The clone temp dir is removed last: a failure part-way through the update must leave it for nothing,
# and removing it here rather than in a finally means a clone that never happened leaves no litter.
if (Test-Path -LiteralPath $script:TempRoot) { Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue }

Write-Info 'Done.'
