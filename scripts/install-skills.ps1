#requires -Version 7.0
<#
.SYNOPSIS
    Cross-platform skills installer for Windows / macOS / Linux (PowerShell 7).

.DESCRIPTION
    One-liner:
      irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1 | iex

    Same contract as install-skills.sh:

      1. Finds the agent root in order: .agents -> .claude -> .codex, and errors
         when none exists. It never creates one: a folder the operator did not ask for is not an install.
         The skills root is <agent-root>/skills (override with SKILLS_ROOT, whose parent then counts
         as the agent root for state purposes).
      2. Reads <agent-root>/_smooth-devex-shared/installation.json.
         - Missing  -> creates it with every skill on disk, installed:true, UTC timestamp.
         - Present  -> syncs: adds new skills, drops skills no longer on disk, keeps every
                       installed flag the operator already set. A corrupt file is a hard error,
                       never a silent reset of the whole manifest.
         A legacy manifest at the old <skills-root>/_smooth-devex-shared/installation.json location
         is ignored (fresh start): it is reported and otherwise left untouched.
      3. Updates only the skills marked installed:true, cloning the repo once and copying those folders
         (plus the shared payload, if the source ships one) out of it.
      4. Writes the updated installation.json back with a fresh UTC timestamp - after the update, so
         refreshing the shared payload cannot clobber the manifest that update read.
      5. Links every top-level shared-payload entry back to its canonical <agent-root> path
         (e.g. <agent-root>/setup -> _smooth-devex-shared/setup), so SKILL.md references to the
         canonical paths keep working. An existing real file or directory at the link path is
         never replaced: it is reported and skipped.

    Dependencies: PowerShell 7, git. No Python and no bash.

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
    [switch] $Hooks
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
# The owned set is deliberately small. This is a template repo, not a domain plugin; the few skills
# worth carrying to a consumer are the ones that operate on the template's own shape (asset sync,
# template sync, rule system) or that are useful in any consumer project (terse response, ralph
# review-fix loop, hld + worktask authoring).
#
# If a skill you want to distribute lands here, add it to this list and to the harness's owned
# set in test-install-skills.sh. Anything else stays local.
$script:OwnedList = @(
    'ai-asset-sync'
    'ai-ralph-loop'
    'ai-template-sync'
    'ai-terse'
    'create-hld'
    'create-worktask'
    'manage-rule-system'
)

# Rules the installer is allowed to carry across, as paths relative to .github/instructions/.
# The rules index (AGENTS.md) is NOT copied — install writes a generated index of the shipped
# subset instead. Mirrors OWNED_RULES in install-skills.sh (the harness holds the two byte-for-byte).
$script:OwnedRules = @(
    'code-review-standards.instructions.md'
    'git/git-policy.instructions.md'
    'meta/knowledge-conventional-contexts-quality.instructions.md'
    'meta/rules.instructions.md'
)

# Hooks the installer is allowed to carry across: a hook is owned iff an owned skill's SKILL.md
# references it AND its implementation ships with it. load-agents-context.sh is referenced by
# ai-template-sync but delegates to an unowned skill that never ships — copying the wrapper alone
# installs a silently dead hook, so it stays local. Mirrors OWNED_HOOKS in install-skills.sh
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
        [object[]] $ExistingSkills
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

    $updatedJson = $Updated | ConvertTo-Json -Compress
    $joined = $items -join ",`n"
    if ($joined) { $joined += "`n" }
    return "{`n  `"updated`": $updatedJson,`n  `"skills`": [`n$joined  ]`n}"
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

    foreach ($entry in Get-ChildItem -LiteralPath $Dest -Force) {
        if ($entry.Name -eq 'installation.json') { continue }
        $sourcePath = Join-Path $Source $entry.Name
        $hasSource = Test-Path -LiteralPath $sourcePath
        if ($hasSource -and $entry.PSIsContainer) {
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
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            Copy-Item -LiteralPath $source -Destination $dest -Recurse -Force
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
    if (Test-Path -LiteralPath $sharedSource -PathType Container) {
        $sharedDest = $SharedDir
        New-Item -ItemType Directory -Path $sharedDest -Force | Out-Null
        Copy-Item -Path (Join-Path $sharedSource '*') -Destination $sharedDest -Recurse -Force
        Remove-StaleEntries -Dest $sharedDest -Source $sharedSource
        Write-Info 'Updated _smooth-devex-shared'
        # Link the payload back to canonical paths so .agents/setup/... references keep working.
        foreach ($entry in Get-ChildItem -LiteralPath $sharedSource -Force) {
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
        '| `**` | `code-review-standards` · `git/git-policy` |',
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
        'File = `<name>.instructions.md` in `.github/instructions/`.'
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
    # Copies the owned rule files from the source's .github/instructions/ into the consumer's,
    # preserving relative paths. Overwrites, never deletes.
    param([string] $AgentRoot)
    $repoRoot = Split-Path -Parent $AgentRoot
    $sourceRules = Join-Path $script:TempRepo '.github/instructions'
    $destRules = Join-Path $repoRoot '.github/instructions'
    if (-not (Test-Path -LiteralPath $sourceRules -PathType Container)) {
        Write-Info 'No .github/instructions in source - nothing to install for rules'
        return
    }
    New-Item -ItemType Directory -Path $destRules -Force | Out-Null
    foreach ($rel in $script:OwnedRules) {
        $source = Join-Path $sourceRules $rel
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $dest = Join-Path $destRules $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $dest -Force
            Write-Info "Updated rule $rel"
        }
        else {
            Write-Info "WARNING: rule $rel not found in repo - left on disk untouched"
        }
    }
    # Topology: <agent-root>/rules -> ../.github/instructions, but only when nothing is there.
    # A dangling symlink reads as absent to Test-Path, so check the link itself: re-creating over
    # an existing path aborts the run under $ErrorActionPreference = Stop.
    $rulesLink = Join-Path $AgentRoot 'rules'
    $rulesLinkTaken = Test-Path -LiteralPath $rulesLink
    if (-not $rulesLinkTaken) {
        $existing = Get-Item -LiteralPath $rulesLink -Force -ErrorAction SilentlyContinue
        $rulesLinkTaken = ($null -ne $existing) -and ($null -ne $existing.LinkType)
    }
    if (-not $rulesLinkTaken) {
        try {
            New-Item -ItemType SymbolicLink -Path $rulesLink -Target '../.github/instructions' | Out-Null
        }
        catch {
            New-Item -ItemType Junction -Path $rulesLink -Target (Join-Path $repoRoot '.github/instructions') | Out-Null
        }
        Write-Info "Linked $rulesLink -> ../.github/instructions"
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
    New-Item -ItemType Directory -Path $destHooks -Force | Out-Null
    foreach ($name in $script:OwnedHooks) {
        $source = Join-Path $sourceHooks $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $destHooks $name) -Recurse -Force
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
                if ((Test-Path -LiteralPath $src) -and ((Get-Item $src).UnixFileMode -band [System.IO.UnixFileMode]::ExecuteUser)) {
                    & chmod +x $dst 2>$null
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Category switches. No switches means everything is on; any switch narrows the run to
# exactly what was named. Switches filter the run only — nothing is persisted.
$script:DoRules = [bool]$Rules
$script:DoSkills = [bool]$Skills
$script:DoHooks = [bool]$Hooks
if (-not ($script:DoRules -or $script:DoSkills -or $script:DoHooks)) {
    $script:DoRules = $true
    $script:DoSkills = $true
    $script:DoHooks = $true
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
    # The skills directory is only required when the skills category runs: a rules-only or
    # hooks-only run must work in a tree that has no skills at all.
    if ($script:DoSkills -and (-not (Test-Path -LiteralPath $script:SkillsRootPath -PathType Container))) {
        Fail "no skills directory found - expected $($script:SkillsRootPath) (create it, or set SKILLS_ROOT)"
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

    $diskSkills = @(Get-Skills -Root $script:SkillsRootPath)
    $sourceSkills = @(Get-Skills -Root (Join-Path $script:TempRepo '.agents/skills'))
    # Escaped colons are deliberate. 'T' is a .NET custom-format *modifier* (time designator), so an
    # unescaped 'HH:mm:ss' follows the designator and ':' then renders as the culture's time separator -
    # which is '.' under one locale and ':' under another, producing a timestamp the bash port and this
    # port cannot agree on.
    $newJson = Build-InstallationJson -Updated ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH\:mm\:ssZ')) `
        -DiskSkills $diskSkills -SourceSkills $sourceSkills -ExistingSkills $existingSkills

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