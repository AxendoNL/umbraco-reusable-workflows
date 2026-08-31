param (
    [Parameter(Position=0)]
    [string]
    $PatchFile,

    [Parameter(Position=1)]
    [string]
    $LatestDeploymentId,

    [Parameter(Position=3)]
    [string]
    $PipelineVendor,

    [Parameter(Position=3)]
    [string]
    $GitUserName,

    [Parameter(Position=4)]
    [string]
    $GitUserEmail
)

git config user.name $GitUserName
git config user.email $GitUserEmail

If ($PipelineVendor -eq "AZUREDEVOPS"){
    git checkout $env:BUILD_SOURCEBRANCHNAME
}

# The diff from cloud is cumulative: it is calculated against the latest deployment
# done through the CICD API, and that baseline only moves when a new deployment is
# pushed to cloud. When the sync runs standalone (no deployment afterwards), the next
# patch overlaps with hunks that are already committed on this branch.
# --3way handles all cases: it performs a plain apply when the context matches, and
# falls back to a 3-way merge that skips already-applied hunks when it does not.
# Requires the pre-image blobs in the object database, hence fetch-depth: 0.
Write-Host "Applying the patch (3-way)"
Write-Host "=========================="
git apply $PatchFile --3way --ignore-space-change --ignore-whitespace
$autoResolved = @()
If ($LASTEXITCODE -ne 0) {
    # Real merge conflict (e.g. the same line changed on both sides since the
    # baseline). For the files below such a conflict is almost always a cloud
    # package bump whose hunk overlaps lines an earlier sync already committed
    # on this branch; cloud only ever bumps versions upward, so the cloud side
    # is safe to take automatically. Every other file still fails hard so that
    # local work is never overwritten silently.
    $autoResolvableFiles = @('Directory.Packages.props')

    $conflicted = @(git diff --name-only --diff-filter=U)
    $manual = @($conflicted | Where-Object { $_ -notin $autoResolvableFiles })

    If ($conflicted.Count -gt 0 -and $manual.Count -eq 0) {
        ForEach ($file in $conflicted) {
            # git merge-file --theirs resolves only the conflicting regions to
            # the cloud side and keeps local changes elsewhere in the file;
            # 'git checkout --theirs' would replace the whole file and discard
            # those local changes. The stage blobs go through git unpack-file
            # to keep the content byte-exact (no PowerShell text re-encoding).
            $stages = @{}
            ForEach ($entry in @(git ls-files -u -- $file)) {
                # format: <mode> <sha> <stage>\t<path>
                $meta = ($entry -split "`t")[0] -split ' '
                $stages[$meta[2]] = $meta[1]
            }
            If (-not ($stages['2'] -and $stages['3'])) {
                Write-Host "Cannot auto-resolve ${file}: merge stages missing"
                git reset --hard --quiet
                Exit 1
            }
            $oursFile   = git unpack-file $stages['2']
            $theirsFile = git unpack-file $stages['3']
            $baseFile   = If ($stages['1']) { git unpack-file $stages['1'] }
                          Else { (New-Item -ItemType File ".merge_file_base").Name }
            git merge-file --theirs $oursFile $baseFile $theirsFile
            If ($LASTEXITCODE -lt 0) {
                Write-Host "Cannot auto-resolve ${file}: git merge-file failed"
                git reset --hard --quiet
                Exit 1
            }
            Copy-Item $oursFile $file -Force
            Remove-Item $oursFile, $baseFile, $theirsFile -Force
            git add $file
            $autoResolved += $file
            Write-Host "Auto-resolved conflict in $file (cloud version kept)"
        }
    }
    Else {
        # Only the paths git left unmerged need attention - report those while
        # the conflict state still exists, then clean up.
        # Do not fall back to a plain 'git apply --check': without --3way the
        # context of every file in the cumulative patch mismatches, so it flags
        # all of them and hides which file actually conflicts.
        Write-Host ""
        Write-Host "Patch cannot be applied - merge conflict in the file(s) below"
        Write-Host "============================================================"
        If ($conflicted.Count -gt 0) {
            Write-Host "Conflicting files ($($conflicted.Count)):"
            $conflicted | ForEach-Object { Write-Host " - $_" }
            ForEach ($file in $conflicted) {
                Write-Host ""
                Write-Host "--- conflict in $file ---"
                git diff -- $file
            }
            Write-Host ""
            Write-Host "Resolve by hand: apply the cloud change from the git-patch artifact to the"
            Write-Host "file(s) above on this branch, commit, then rerun the sync."
        }
        Else {
            Write-Host "git reported no unmerged paths - see the apply output above."
        }
        git reset --hard --quiet
        Exit 1
    }
}

If (-not (git status --porcelain)) {
    Write-Host "Patch already applied === concluding the apply patch part"
    Exit 0
}

# Mention auto-resolved conflicts in the commit body so they stay visible in
# the history even though the sync no longer fails on them.
$commitArgs = @('-m', "Adding cloud changes since deployment $LatestDeploymentId [skip ci]")
If ($autoResolved.Count -gt 0) {
    $commitArgs += @('-m', "Auto-resolved conflicts (cloud version kept): $($autoResolved -join ', ')")
}

switch ($PipelineVendor) {
    "GITHUB" {
        git add *
        git commit @commitArgs
        git push
        $updatedSha = git rev-parse HEAD
        "updatedSha=$($updatedSha)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    }
    "AZUREDEVOPS" {
        git add --all
        git commit @commitArgs
        git push --set-upstream origin $env:BUILD_SOURCEBRANCHNAME
        $updatedSha = git rev-parse HEAD
        Write-Host "##vso[task.setvariable variable=updatedSha;isOutput=true]$($updatedSha)"
    }
    "TESTRUN" {
        Write-Host $PipelineVendor
    }
    Default {
        Write-Host "Please use one of the supported Pipeline Vendors or enhance script to fit your needs"
        Write-Host "Currently supported are: GITHUB and AZUREDEVOPS"
        Exit 1
    }
}

Write-Host "Changes are applied successfully"
Write-Host ""
Write-Host "Updated SHA: $updatedSha"
Exit 0
