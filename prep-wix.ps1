[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$RepoDir = $PWD.ToString()
)

$ErrorActionPreference = 'Stop'

[string]$DepsDir = Join-Path $RepoDir 'build-deps'
[string]$WixDir = Join-Path $DepsDir 'wix-3.14.1'
[string]$WixZip = Join-Path $DepsDir 'wix314-binaries.zip'
[string]$WixgenJar = Join-Path $DepsDir 'wixgen.jar'

if (Test-Path -Path $WixDir -PathType Container) {
    Remove-Item -LiteralPath $WixDir -Recurse -Force
}

New-Item -ItemType Directory -Path $DepsDir -Force | Out-Null
New-Item -ItemType Directory -Path $WixDir -Force | Out-Null

Write-Host "Downloading and extracting WiX package..." -ForegroundColor Yellow -BackgroundColor Cyan

Invoke-WebRequest -UseBasicParsing `
    -Uri 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip' `
    -OutFile $WixZip

Unblock-File -LiteralPath $WixZip

Expand-Archive -LiteralPath $WixZip -DestinationPath $WixDir -Force

Write-Host "Checking if all Wix files from the package are valid..." -ForegroundColor Yellow -BackgroundColor Cyan
Get-Item -LiteralPath @(
    "$WixDir\candle.exe"
    "$WixDir\light.exe"
    "$WixDir\WixUIExtension.dll"
) -ErrorAction Stop | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_.FullName -PathType Leaf)) {
        throw "Required file is missing: $($_.FullName)"
    }
}

# Download wixgen.jar
Write-Host "Downloading WixGen..." -ForegroundColor Yellow -BackgroundColor Cyan
Invoke-WebRequest -UseBasicParsing `
    -Uri 'https://github.com/akashche/wixgen/releases/download/1.7/wixgen.jar' `
    -OutFile $WixgenJar

$ExpectedHash = '57E68A91C46A2F4B1B41A3F93793E331D62D6D151DDC222FA4D3EC9CE876F967'
$ActualHash = (Get-FileHash -LiteralPath $WixgenJar -Algorithm SHA256).Hash

if ($ActualHash -ne $ExpectedHash) {
    throw 'wixgen.jar checksum does not match the repository CI checksum.'
}

Write-Host ' -- wixgen.jar verified --' -ForegroundColor Green -BackgroundColor White

# Verify the toolset
Write-Host "Verifying the entire toolset..." -ForegroundColor Yellow -BackgroundColor Cyan
& "$WixDir\candle.exe" '-?'
if ($LASTEXITCODE -ne 0) {
    throw 'WiX candle.exe failed.'
}

& "$WixDir\light.exe" '-?'
if ($LASTEXITCODE -ne 0) {
    throw 'WiX light.exe failed.'
}

& 'C:\cygwin64\zulu8\bin\java.exe' -version
if ($LASTEXITCODE -ne 0) {
    throw 'Java verification failed.'
}

Write-Host "DONE!" -ForegroundColor Green -BackgroundColor White

exit $LASTEXITCODE
