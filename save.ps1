# The routine backup, run as gem-save. Prints one line per git repository under DEV and per linked
# worktree of one that lives elsewhere (such as an agent's), pushes every branch whose upstream
# lacks some of its commits, records the GitHub repositories in repos.txt for restore.cmd, refreshes
# the cloud export, then commits and pushes this overlay. Uncommitted work in other repositories is
# reported, never committed for you.
#   gem-save            (pwsh save.ps1)
#   gem-save -DryRun    show what it would do; nothing is pushed, written or committed
# Exits 1 while any repository still has work that exists only on this PC, or when a push failed,
# so the next run is a reminder.
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'

$overlay = $PSScriptRoot
$dev = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($env:DEV ? $env:DEV : (Split-Path -Parent $overlay)))
$kit = Join-Path $dev 'gem-setting'

if (-not (Get-Command git -ErrorAction Ignore)) {
    Write-Host 'save: git is not installed' -ForegroundColor Red
    exit 1
}

function Test-SamePath([string]$A, [string]$B) {
    [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($A)) -eq [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($B))
}

# A repository's own subfolders are not searched: its .git internals, submodules and nested
# worktrees belong to it.
function Find-Repositories([string]$Dir, [int]$Depth) {
    foreach ($child in Get-ChildItem -LiteralPath $Dir -Directory -ErrorAction Ignore | Sort-Object Name) {
        if (Test-Path -LiteralPath (Join-Path $child.FullName '.git')) { $child.FullName }
        elseif ($Depth -gt 1) { Find-Repositories $child.FullName ($Depth - 1) }
    }
}

function Get-DisplayName([string]$Repo) {
    $relative = [IO.Path]::GetRelativePath($dev, $Repo)
    $relative.StartsWith('..') ? $Repo : $relative
}

function Format-Count([int]$Count, [string]$One, [string]$Many) { $Count -eq 1 ? "1 $One" : "$Count $Many" }

# A branch with an upstream is compared with it (as of the last fetch, so nothing goes over the
# network); a branch without one, or whose upstream was deleted, is compared with every remote,
# because its commits may already be pushed on another branch. -WorktreeOnly: another worktree of a
# repository already checked, which shares its branches, remotes and stashes.
function Get-RepositoryState([string]$Repo, [switch]$WorktreeOnly) {
    $state = [pscustomobject]@{ Error = $null; Changes = 0; HasRemote = $true; Pushes = @(); LocalOnly = @(); Detached = 0; Stashes = 0 }
    $status = @(git -C $Repo status --porcelain 2>$null)
    if ($LASTEXITCODE) {
        $state.Error = "$(git -C $Repo status 2>&1 | Select-Object -First 1)"
        return $state
    }
    $state.Changes = $status.Count
    if (-not $WorktreeOnly) {
        $state.HasRemote = [bool]@(git -C $Repo remote).Count
        $state.Stashes = @(git -C $Repo stash list 2>$null).Count
    }
    if (-not $state.HasRemote) { return $state }

    $format = '%(refname)%09%(upstream:remotename)%09%(upstream:remoteref)%09%(upstream:track,nobracket)'
    foreach ($line in $WorktreeOnly ? @() : @(git -C $Repo for-each-ref "--format=$format" refs/heads)) {
        $ref, $remote, $remoteRef, $track = $line -split "`t"
        $branch = $ref -replace '^refs/heads/', ''
        if ($remote -and $remote -ne '.' -and $track -ne 'gone') {
            if ($track -match 'ahead (\d+)') {
                $state.Pushes += [pscustomobject]@{ Branch = $branch; Ref = $ref; Remote = $remote; RemoteRef = $remoteRef; Ahead = [int]$Matches[1] }
            }
        } else {
            $count = [int](git -C $Repo rev-list --count $ref --not --remotes 2>$null)
            if ($count) { $state.LocalOnly += "$branch +$count ($($remote ? 'upstream deleted' : 'no upstream'))" }
        }
    }
    git -C $Repo symbolic-ref -q HEAD *> $null
    if ($LASTEXITCODE) { $state.Detached = [int](git -C $Repo rev-list --count HEAD --not --branches --remotes 2>$null) }
    $state
}

$hints = [Collections.Generic.HashSet[string]]::new()

# Pushes what can be pushed and returns the status line. -CommitPlan: in a dry run, what save would
# commit in the overlay, so those changes are not reported as unsaved.
function Save-Repository([string]$Repo, [string]$CommitPlan, [switch]$WorktreeOnly) {
    $state = Get-RepositoryState $Repo -WorktreeOnly:$WorktreeOnly
    $notes = [Collections.Generic.List[string]]::new()
    $details = [Collections.Generic.List[string]]::new()
    $unsaved = $failed = $false
    if ($state.Error) {
        $notes.Add("git error: $($state.Error)")
        $unsaved = $true
    }
    if ($CommitPlan) {
        $notes.Add("would commit $CommitPlan$($state.HasRemote ? ' and push' : '')")
    } elseif ($state.Changes) {
        $notes.Add("uncommitted changes ($(Format-Count $state.Changes 'file' 'files'))")
        $unsaved = $true
        $hints.Add('Uncommitted changes: commit them in that repository (or ask an agent to), then run gem-save again.') | Out-Null
    }
    if (-not $state.Error -and -not $state.HasRemote) {
        $notes.Add('no remote')
        $unsaved = $true
        $hints.Add('No remote: make a private GitHub repository for it, in that folder:  gh repo create <name> --private --source . --push') | Out-Null
    }
    foreach ($push in $state.Pushes) {
        $what = "$($push.Branch) +$($push.Ahead)"
        if ($DryRun) {
            $notes.Add("commits not pushed: $what (would push)")
            continue
        }
        $output = @(git -C $Repo push --quiet $push.Remote "$($push.Ref):$($push.RemoteRef)" 2>&1)
        if ($LASTEXITCODE) {
            $notes.Add("commits not pushed: $what (push failed)")
            $output | ForEach-Object { $details.Add("$_") }
            $failed = $true
            $hints.Add('Push failed: read the git message under that line; when the remote has newer commits, run  git pull  there first.') | Out-Null
        } else { $notes.Add("pushed $what") }
    }
    foreach ($branch in $state.LocalOnly) {
        $notes.Add("commits not pushed: $branch")
        $unsaved = $true
        $hints.Add('No upstream: in that repository,  git push -u origin <branch>  (or merge the branch and delete it).') | Out-Null
    }
    if ($state.Detached) {
        $notes.Add("$(Format-Count $state.Detached 'commit' 'commits') on a detached HEAD")
        $unsaved = $true
        $hints.Add('Detached HEAD: in that repository,  git switch -c <new-branch>  keeps those commits on a branch.') | Out-Null
    }
    if ($state.Stashes) {
        $notes.Add("$(Format-Count $state.Stashes 'stash' 'stashes') (not backed up)")
        $unsaved = $true
        $hints.Add('Stashes: git stash list shows them; apply and commit them, or drop them.') | Out-Null
    }
    if (-not $notes.Count) { $notes.Add('clean and pushed') }
    [pscustomobject]@{ Name = Get-DisplayName $Repo; Text = $notes -join '; '; Details = $details; Unsaved = $unsaved; Failed = $failed }
}

function Show-Result($Result, [int]$Width) {
    $color = $Result.Failed ? 'Red' : ($Result.Unsaved ? 'Yellow' : 'Green')
    Write-Host ("  {0}  {1}" -f $Result.Name.PadRight($Width), $Result.Text) -ForegroundColor $color
    $Result.Details | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
}

# Linked worktrees the search does not reach, such as Claude Code's <repo>\.claude\worktrees\* or
# folders an agent keeps elsewhere: their branches are counted with the repository, but their
# uncommitted changes would otherwise go unreported.
function Find-OtherWorktrees([string[]]$Repos) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($repo in $Repos) {
        $seen.Add([IO.Path]::GetFullPath($repo)) | Out-Null
        # git lists worktrees by their resolved path, which differs when DEV is reached through a junction.
        $top = "$(git -C $repo rev-parse --show-toplevel 2>$null)"
        if ($top) { $seen.Add([IO.Path]::GetFullPath($top)) | Out-Null }
    }
    foreach ($repo in $Repos) {
        foreach ($entry in (@(git -C $repo worktree list --porcelain 2>$null) -join "`n") -split "`n`n") {
            $fields = $entry -split "`n"
            if (-not $fields[0].StartsWith('worktree ') -or $fields -contains 'bare') { continue }
            $path = [IO.Path]::GetFullPath($fields[0].Substring(9))
            if ((Test-Path -LiteralPath $path -PathType Container) -and $seen.Add($path)) { $path }
        }
    }
}

# git prints UTF-8, and branch names and paths read from it are handed back to git; decoded in the
# Korean console code page (949), a branch named in Hangul fails to push. The console is shared
# with the shell that started this script, so its encoding is put back on the way out.
$consoleEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
try {
    if ($DryRun) { Write-Host 'save: dry run, nothing is changed' -ForegroundColor Yellow }
    $repos = @(Find-Repositories $dev 2 | Where-Object { -not (Test-SamePath $_ $overlay) })
    $worktrees = @(Find-OtherWorktrees (@($repos) + $overlay))
    # Worktrees outside DEV show their full path, which would widen every line.
    $width = (@($repos + $overlay | ForEach-Object { (Get-DisplayName $_).Length }) | Measure-Object -Maximum).Maximum
    Write-Host "save: $(Format-Count $repos.Count 'repository' 'repositories') under $dev, then the overlay"
    $checked = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $results = @(foreach ($repo in $repos) {
        $commonDir = "$(git -C $repo rev-parse --path-format=absolute --git-common-dir 2>$null)"
        $result = Save-Repository $repo -WorktreeOnly:(-not $checked.Add($commonDir))
        Show-Result $result $width
        $result
    })
    $results += @(foreach ($worktree in $worktrees) {
        $result = Save-Repository $worktree -WorktreeOnly
        Show-Result $result $width
        $result
    })

    $list = Join-Path $overlay 'repos.txt'
    $old = (Test-Path -LiteralPath $list) ? [IO.File]::ReadAllText($list).Replace("`r", '') : ''
    # The comment block at the top of repos.txt is kept as it is; only the entries are rewritten.
    $header = foreach ($line in $old -split "`n") { if ($line.StartsWith('#')) { $line } else { break } }
    $header ??= '# Repositories that restore.cmd clones on a new PC: owner/name relative\path\under\DEV'
    $entries = [ordered]@{}
    foreach ($repo in $repos) {
        if (Test-SamePath $repo $kit) { continue }
        # A linked worktree shares its main repository's origin, which is listed once from there.
        $gitDirs = @(git -C $repo rev-parse --path-format=absolute --git-dir --git-common-dir 2>$null)
        if ($gitDirs.Count -eq 2 -and $gitDirs[0] -ne $gitDirs[1]) { continue }
        $url = "$(git -C $repo config --get remote.origin.url)"
        if ($url -notmatch '^(?:(?:https?|ssh|git)://(?:[^@/]+@)?github\.com(?::\d+)?/|[^@/:]+@github\.com:)([\w.-]+)/([\w.-]+?)(?:\.git)?/?$') { continue }
        $name = "$($Matches[1])/$($Matches[2])"
        if ($Matches[2] -in 'gem-setting', 'gem-overlay' -or $entries.Contains($name)) { continue }
        $entries[$name] = [IO.Path]::GetRelativePath($dev, $repo)
    }
    $lines = $entries.GetEnumerator() | Sort-Object Value | ForEach-Object { "$($_.Key) $($_.Value)" }
    $new = (@($header) + @($lines)) -join "`n"
    $new += "`n"
    $planned = [Collections.Generic.List[string]]::new()
    Write-Host ''
    if ($new -ceq $old) {
        Write-Host "repos.txt: up to date ($(Format-Count $entries.Count 'repository' 'repositories'))"
    } elseif ($DryRun) {
        Write-Host "repos.txt: would write $(Format-Count $entries.Count 'repository' 'repositories')"
        $lines | ForEach-Object { Write-Host "  $_" }
        $planned.Add('the new repos.txt')
    } else {
        [IO.File]::WriteAllText($list, $new)
        Write-Host "repos.txt: written ($(Format-Count $entries.Count 'repository' 'repositories'))"
        $lines | ForEach-Object { Write-Host "  $_" }
    }

    Write-Host 'cloud export: setup.d\40-cloud-export.ps1'
    $env:DEV = $dev
    $exportArgs = $DryRun ? @('-DryRun') : @()
    & pwsh -NoProfile -File (Join-Path $overlay 'setup.d\40-cloud-export.ps1') @exportArgs
    # In a dry run the export exits 2 when it would write something.
    $exportCode = $LASTEXITCODE
    if ($DryRun -and $exportCode -eq 2) {
        $planned.Add('the refreshed cloud\ files')
        $exportCode = 0
    }
    $exportFailed = [bool]$exportCode

    Write-Host ''
    $commitFailed = $false
    $pending = @(git -C $overlay status --porcelain 2>$null)
    if ($pending.Count -and -not $DryRun) {
        # safecrlf=false: the line ending notices for files .gitattributes converts are not news here.
        git -C $overlay -c core.safecrlf=false add -A
        git -C $overlay commit --quiet -m 'chore: save workstation state'
        $commitFailed = [bool]$LASTEXITCODE
    }
    $plan = @(if ($pending.Count) { Format-Count $pending.Count 'changed file' 'changed files' }) + $planned
    $overlayResult = Save-Repository $overlay -CommitPlan ($DryRun ? ($plan -join ', ') : '')
    if ($commitFailed) {
        $overlayResult.Text = "commit failed; $($overlayResult.Text)"
        $overlayResult.Failed = $true
    }
    Show-Result $overlayResult $width

    $all = @($results) + $overlayResult
    Write-Host ''
    if ($exportFailed) {
        Write-Host 'save: the cloud export did not finish; see its message above.' -ForegroundColor Red
        $hints.Add('Cloud export: after a change in rules\, run gem-setup, then gem-save again.') | Out-Null
    }
    if ($exportFailed -or ($all | Where-Object { $_.Unsaved -or $_.Failed })) {
        Write-Host 'save: some work is still only on this PC:' -ForegroundColor Yellow
        $hints | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        exit 1
    }
    Write-Host ($DryRun ? 'save: dry run finished; run gem-save to do it.' : 'save: everything is on GitHub.') -ForegroundColor Green
    exit 0
} finally {
    [Console]::OutputEncoding = $consoleEncoding
}
