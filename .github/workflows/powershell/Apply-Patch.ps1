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
If ($LASTEXITCODE -ne 0) {
    # Real merge conflict (e.g. the same line changed on both sides since the
    # baseline) - clean up the working tree and fail with diagnostics.
    git reset --hard --quiet
    Write-Host ""
    Write-Host "Patch cannot be applied - please check the output below for the problematic parts"
    Write-Host "================================================================================="
    Write-Host ""
    git apply -v --reject $PatchFile --ignore-space-change --ignore-whitespace --check
    Exit 1
}

If (-not (git status --porcelain)) {
    Write-Host "Patch already applied === concluding the apply patch part"
    Exit 0
}

switch ($PipelineVendor) {
    "GITHUB" {
        git add *
        git commit -m "Adding cloud changes since deployment $LatestDeploymentId [skip ci]"
        git push
        $updatedSha = git rev-parse HEAD
        "updatedSha=$($updatedSha)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    }
    "AZUREDEVOPS" {
        git add --all
        git commit -m "Adding cloud changes since deployment $LatestDeploymentId [skip ci]"
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
