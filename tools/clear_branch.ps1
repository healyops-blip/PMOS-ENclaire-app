# Clear a remote branch and leave only a README
# Usage:
#   1) Ensure you have push access via SSH or HTTPS (PAT). For HTTPS, set $env:GITHUB_TOKEN with repo scope.
#   2) Update $RepoUrl and $Branch below.
#   3) Run: powershell -ExecutionPolicy Bypass -File d:\hackathon_26\tools\clear_branch.ps1

param()

$ErrorActionPreference = 'Stop'

# Configure
$Branch  = 'CaffeineDeceit/data-construct'

# Require PAT via env var to avoid SSH config issues
if (-not $env:GITHUB_TOKEN) {
    Write-Error 'GITHUB_TOKEN env var is not set. Create a Personal Access Token (fine-grained, repo permissions) and set $env:GITHUB_TOKEN.'
    exit 1
}

$RepoUrl = 'https://oauth2:' + $env:GITHUB_TOKEN + '@github.com/healyops-blip/PMOS-ENclaire-app.git'

Write-Host "Repo: $RepoUrl" -ForegroundColor Cyan
Write-Host "Branch: $Branch" -ForegroundColor Cyan

Push-Location 'd:\hackathon_26'
try {
    if (-not (Test-Path '.git')) { git init | Out-Null }

    git remote remove origin 2>$null; git remote add origin $RepoUrl
    git fetch origin --prune

    # Create orphan branch (no history), checkout it
    git switch --orphan $Branch

    # Remove all files from index and working tree
    git rm -rf .

    # Create a minimal README
    $readme = @()
    $readme += '# Data Construct Branch'
    $readme += ''
    $readme += "This branch was reset on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') to contain only this README."
    $readme += ''
    $readme += 'Use this branch for data construction artifacts and scripts.'
    Set-Content -LiteralPath 'd:\hackathon_26\README.md' -Value ($readme -join [Environment]::NewLine) -Encoding UTF8

    git add README.md
    git commit -m "chore(branch): reset CaffeineDeceit/data-construct with README only"
    git push -f origin $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Push failed. Verify that GITHUB_TOKEN has correct permissions.'
        exit $LASTEXITCODE
    }
    Write-Host 'Branch reset and pushed successfully.' -ForegroundColor Green
}
finally {
    Pop-Location
}
