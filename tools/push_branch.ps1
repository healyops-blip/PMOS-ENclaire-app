param()
$ErrorActionPreference = 'Stop'

Push-Location 'd:\hackathon_26'
try {
    $Branch = 'CaffeineDeceit/data-construct'

    if (-not $env:GITHUB_TOKEN) {
        Write-Error 'GITHUB_TOKEN is not set. Please create a GitHub Personal Access Token with repo contents: read/write and set $env:GITHUB_TOKEN before running.'
        exit 1
    }

    $RepoUrl = "https://oauth2:$($env:GITHUB_TOKEN)@github.com/healyops-blip/PMOS-ENclaire-app.git"
    git remote remove origin 2>$null
    git remote add origin $RepoUrl

    # Ensure we are committing latest changes
    git add -A
    git commit -m "泛化四种病例类型的基本功能" 2>$null

    # Create/update local branch and push
    git checkout -B $Branch
    git push -u origin $Branch
    Write-Host ("Pushed branch {0} successfully." -f $Branch) -ForegroundColor Green
}
finally {
    Pop-Location
}
