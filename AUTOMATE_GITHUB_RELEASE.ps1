param(
    [string]$RepoUrl = "https://github.com/JoeKurwa/MusicSelektor",
    [string]$Version = "v1.2.0",
    [string]$AuthorName = "Joe Kurwa",
    [string]$AuthorEmail = "",
    [switch]$NoOpenReleasePage
)

$ErrorActionPreference = "Stop"

function Get-GitExecutable {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Git\cmd\git.exe"),
        (Join-Path $env:LocalAppData "Programs\Git\cmd\git.exe")
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    throw "Git introuvable. Installe Git for Windows puis relance."
}

function Invoke-Git {
    param(
        [string]$GitExe,
        [string[]]$GitArgs,
        [switch]$AllowFailure
    )
    & $GitExe @GitArgs
    $code = $LASTEXITCODE
    if (-not $AllowFailure -and $code -ne 0) {
        throw "Commande git echouee: git $($GitArgs -join ' ') (exit $code)"
    }
    return $code
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }
Set-Location $scriptDir

if ([string]::IsNullOrWhiteSpace($AuthorEmail)) {
    $AuthorEmail = Read-Host "Email Git (recommande: noreply GitHub)"
}
if ([string]::IsNullOrWhiteSpace($AuthorEmail)) {
    throw "Email requis."
}

$git = Get-GitExecutable
Write-Host "Git detecte: $git" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath ".git")) {
    Write-Host "Initialisation du depot git..." -ForegroundColor Yellow
    Invoke-Git -GitExe $git -GitArgs @("init") | Out-Null
}

Invoke-Git -GitExe $git -GitArgs @("branch", "-M", "main") | Out-Null
Invoke-Git -GitExe $git -GitArgs @("config", "user.name", $AuthorName) | Out-Null
Invoke-Git -GitExe $git -GitArgs @("config", "user.email", $AuthorEmail) | Out-Null

# .gitattributes pro (line endings)
$gitattributesPath = Join-Path $scriptDir ".gitattributes"
$gitattributes = @(
    "* text=auto",
    "*.bat text eol=crlf",
    "*.ps1 text eol=crlf",
    "*.xaml text eol=crlf",
    "*.md text eol=lf"
) -join "`r`n"
[System.IO.File]::WriteAllText($gitattributesPath, $gitattributes + "`r`n")

# Assure un .gitignore compatible release
$gitignorePath = Join-Path $scriptDir ".gitignore"
if (-not (Test-Path -LiteralPath $gitignorePath)) {
    [System.IO.File]::WriteAllText($gitignorePath, "")
}
$gitignoreRaw = Get-Content -LiteralPath $gitignorePath -Raw -Encoding UTF8
if ($gitignoreRaw -notmatch '(?m)^MusicSelektor\.exe$') {
    Add-Content -LiteralPath $gitignorePath -Value "`r`nMusicSelektor.exe"
}

# Nettoyage des artefacts trackes
Invoke-Git -GitExe $git -GitArgs @("rm", "-r", "--cached", "--ignore-unmatch", "reports") -AllowFailure | Out-Null
$trackedToUnstage = @(
    "Library.json",
    "MusicSelektor_config.json",
    "CoverSearchCache.json",
    "AutoCoverReport.json",
    ".next-cover-target.txt",
    "LastAutoCoverTiming.json",
    "MusicSelektor.write-actions.log",
    "Lanceur_Invisible.vbs",
    "copier",
    "MusicSelektor.exe"
)
foreach ($f in $trackedToUnstage) {
    Invoke-Git -GitExe $git -GitArgs @("rm", "--cached", "--ignore-unmatch", $f) -AllowFailure | Out-Null
}

Invoke-Git -GitExe $git -GitArgs @("add", "-A") | Out-Null

# Commit seulement si changements indexes
$diffCode = Invoke-Git -GitExe $git -GitArgs @("diff", "--cached", "--quiet") -AllowFailure
if ($diffCode -eq 1) {
    Invoke-Git -GitExe $git -GitArgs @("commit", "-m", "chore: release hygiene and publish v1.2.0 prep") | Out-Null
    Write-Host "Commit cree." -ForegroundColor Green
} else {
    Write-Host "Aucun changement a commit." -ForegroundColor Yellow
}

# Remote
$remoteCode = Invoke-Git -GitExe $git -GitArgs @("remote", "get-url", "origin") -AllowFailure
if ($remoteCode -ne 0) {
    $normalized = if ($RepoUrl.EndsWith(".git")) { $RepoUrl } else { "$RepoUrl.git" }
    Invoke-Git -GitExe $git -GitArgs @("remote", "add", "origin", $normalized) | Out-Null
    Write-Host "Remote origin ajoute: $normalized" -ForegroundColor Green
}

# Push branche
Invoke-Git -GitExe $git -GitArgs @("push", "-u", "origin", "main") | Out-Null

# Tag (si absent)
$tagExistsOutput = & $git tag --list $Version
if ([string]::IsNullOrWhiteSpace(($tagExistsOutput | Out-String).Trim())) {
    Invoke-Git -GitExe $git -GitArgs @("tag", "-a", $Version, "-m", "MusicSelektor $Version") | Out-Null
    Write-Host "Tag cree: $Version" -ForegroundColor Green
} else {
    Write-Host "Tag deja present: $Version" -ForegroundColor Yellow
}
Invoke-Git -GitExe $git -GitArgs @("push", "--tags") | Out-Null

if (-not $NoOpenReleasePage) {
    $releaseUrl = "$RepoUrl/releases/new?tag=$Version"
    Write-Host "Ouverture de la page release: $releaseUrl" -ForegroundColor Cyan
    Start-Process $releaseUrl
}

Write-Host ""
Write-Host "Publication automatisee terminee." -ForegroundColor Green
