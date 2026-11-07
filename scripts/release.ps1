# Build and push a multi-architecture release to Docker Hub, then tag it in git.
# Usage: scripts\release.ps1 [-Bump patch|minor|major|X.Y.Z]   (default: patch; run `docker login` first)
# Keep in sync with scripts/release.sh.
[CmdletBinding()]
param([string]$Bump = 'patch')

$ErrorActionPreference = 'Stop'

$Image = 'sriramiyer/pg-restic'
$Platforms = 'linux/amd64,linux/arm64'
$Builder = 'pg-restic-multiarch'
$VersionPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
$Usage = 'Usage: scripts\release.ps1 [-Bump patch|minor|major|X.Y.Z]'

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

# Native commands don't stop the script on failure, so check each exit code
function Invoke-Checked([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($Bump -notin 'patch', 'minor', 'major' -and $Bump -notmatch $VersionPattern) { Fail $Usage }

# Run from the repo root without changing the caller's current directory
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')

if (git -C $Root status --porcelain) { Fail 'The working tree has uncommitted changes.' }
if ((git -C $Root branch --show-current) -ne 'main') { Fail 'Releases are made from main.' }
Invoke-Checked { git -C $Root fetch --quiet --tags origin main }
if ((git -C $Root rev-parse HEAD) -ne (git -C $Root rev-parse origin/main)) { Fail 'main does not match origin/main. Push or pull first.' }

$Latest = git -C $Root tag --list 'v*' |
    ForEach-Object { $_.Substring(1) } |
    Where-Object { $_ -match $VersionPattern } |
    ForEach-Object { [version]$_ } |
    Sort-Object -Descending |
    Select-Object -First 1
if (-not $Latest -and $Bump -notmatch $VersionPattern) {
    Fail 'No vX.Y.Z git tag found. Tag the current release first, or pass -Bump X.Y.Z.'
}

$Next = switch ($Bump) {
    'patch' { [version]::new($Latest.Major, $Latest.Minor, $Latest.Build + 1) }
    'minor' { [version]::new($Latest.Major, $Latest.Minor + 1, 0) }
    'major' { [version]::new($Latest.Major + 1, 0, 0) }
    default { [version]$Bump }
}
$Version = $Next.ToString()
$Tag = "v$Version"

if ($Latest -and $Next -le $Latest) { Fail "Version $Version is not higher than the latest release $Latest." }
if (git -C $Root tag --list $Tag) { Fail "Git tag $Tag already exists." }
if (git -C $Root ls-remote --tags origin "refs/tags/$Tag") { Fail "Git tag $Tag already exists on origin." }

$LatestText = if ($Latest) { $Latest } else { 'none' }
$Answer = Read-Host "Release $Version (latest is $LatestText)? [y/N]"
if ($Answer -ne 'y') { Fail 'Cancelled.' }

# The default docker driver can't build several platforms at once
docker buildx inspect $Builder *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-Checked { docker buildx create --name $Builder --driver docker-container > $null }
}

Invoke-Checked {
    docker buildx build --builder $Builder --platform $Platforms `
        -t "${Image}:$Version" -t "${Image}:latest" --push $Root
}

Invoke-Checked { git -C $Root tag -a $Tag -m "Release $Version" }
Invoke-Checked { git -C $Root push origin $Tag }

Write-Host "Released ${Image}:$Version ($Platforms) and tagged $Tag."
