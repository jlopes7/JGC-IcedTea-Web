#Requires -Version 5.1

[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
    [Parameter(Position = 0, ParameterSetName = 'Build')]
    [Alias('JavaHome')]
    [ValidateNotNullOrEmpty()]
    [string]$JdkHome = 'C:\cygwin64\zulu8',

    [Parameter(ParameterSetName = 'Build')]
    [ValidateNotNullOrEmpty()]
    [string]$Toolchain = 'stable-x86_64-pc-windows-msvc',

    [Parameter(Mandatory, ParameterSetName = 'Sign')]
    [switch]$SignOnly,

    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [switch]$VerifyOnly,

    [Parameter(Mandatory, ParameterSetName = 'Check')]
    [switch]$CheckSigning,

    [Parameter(Mandatory, ParameterSetName = 'Sign')]
    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Files,

    [string]$SigningThumbprint = $(
        if ($env:ITW_SIGNING_THUMBPRINT) {
            $env:ITW_SIGNING_THUMBPRINT
        }
        else {
            '49B48FE61D2959F117DFDACECC6C03226084FAF0'
        }
    ),

    [string]$SignTool = $env:ITW_SIGNTOOL,

    [AllowEmptyString()]
    [string]$TimestampUrl = $(
        if (Test-Path Env:ITW_TIMESTAMP_URL) {
            $env:ITW_TIMESTAMP_URL
        }
        else {
            'http://timestamp.digicert.com'
        }
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoDir = $PSScriptRoot
$BuildDir = Join-Path $RepoDir 'build-native'
$DistDir = Join-Path $RepoDir 'dist-native'
$BinDir = Join-Path $DistDir 'bin'
$ShareDir = Join-Path $DistDir 'share\icedtea-web'
$DepsDir = Join-Path $DistDir 'win-deps-runtime'
$Manifest = Join-Path $RepoDir 'rust-launcher\Cargo.toml'
$Target = 'x86_64-pc-windows-msvc'

$Launchers = @(
    @{
        Name = 'javaws'
        MainClass = 'net.sourceforge.jnlp.runtime.Boot'
    }
    @{
        Name = 'itweb-settings'
        MainClass = 'net.sourceforge.jnlp.controlpanel.CommandLine'
    }
    @{
        Name = 'policyeditor'
        MainClass = 'net.sourceforge.jnlp.security.policyeditor.PolicyEditor'
    }
)

function Invoke-JgcCodeSigning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SignTool,

        [Parameter(Mandatory)]
        [string] $Thumbprint,

        [Parameter(Mandatory)]
        [string[]] $Files,

        [string] $TimestampUrl
    )

    foreach ($file in $Files) {
        $resolvedFile = (
            Resolve-Path -LiteralPath $file -ErrorAction Stop
        ).ProviderPath

        $signArguments = @(
            'sign',
            '/s', 'My',
            '/sha1', $Thumbprint,
            '/fd', 'SHA256',
            '/d', 'JGC IcedTea-Web'
        )

        if ($TimestampUrl) {
            $signArguments += @(
                '/tr', $TimestampUrl,
                '/td', 'SHA256'
            )
        }

        & $SignTool @signArguments $resolvedFile

        if ($LASTEXITCODE -ne 0) {
            throw "Signing failed or reported a warning: $resolvedFile"
        }

        Assert-JgcSignature -SignTool $SignTool -Thumbprint $Thumbprint -File $resolvedFile
    }
}

function Assert-JgcSignature {
    param(
        [string]$SignTool,
        [string]$Thumbprint,
        [string]$File
    )

    $resolvedFile = (
        Resolve-Path -LiteralPath $File -ErrorAction Stop
    ).ProviderPath

    & $SignTool verify /pa /v $resolvedFile

    if ($LASTEXITCODE -ne 0) {
        throw "Signature verification failed: $resolvedFile"
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $resolvedFile

    if ($null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Thumbprint -ne $Thumbprint) {
        throw "File is not signed by the configured JGC certificate: $resolvedFile"
    }
}

function Resolve-JgcSignTool {
    param([string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        Assert-File $Path
        return (Resolve-Path -LiteralPath $Path).ProviderPath
    }

    $command = Get-Command signtool.exe `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($command) {
        return $command.Source
    }

    $sdkTools = @(
        Get-ChildItem -Path (
            "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe"
        ) -ErrorAction SilentlyContinue |
        Sort-Object {
            [version]$_.Directory.Parent.Name
        } -Descending
    )

    if ($sdkTools.Count -eq 0) {
        throw (
            'SignTool was not found. Install Windows SDK Signing Tools ' +
            'or set ITW_SIGNTOOL to its full Windows path.'
        )
    }

    return $sdkTools[0].FullName
}

function Assert-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
}

function Invoke-Cargo {
    param([string[]]$CargoArguments)

    & cargo.exe "+$Toolchain" @CargoArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Cargo failed with exit code $LASTEXITCODE."
    }
}

# Restore any environment variables changed by this script.
$SavedEnvironment = @{}
$BuildExitCode = 0

Push-Location -LiteralPath $RepoDir

try {
        $SigningThumbprint = (
        $SigningThumbprint -replace '\s', ''
    ).ToUpperInvariant()

    if ($SigningThumbprint -notmatch '^[0-9A-F]{40}$') {
        throw 'SigningThumbprint must be a 40-character certificate thumbprint.'
    }

    $SignTool = Resolve-JgcSignTool $SignTool

    if ($TimestampUrl -eq 'none') {
        $TimestampUrl = ''
    }

    # Verification needs public trust; signing also needs the private key.
    if (-not $VerifyOnly) {
        $certificatePath = "Cert:\CurrentUser\My\$SigningThumbprint"

        if (-not (Test-Path -LiteralPath $certificatePath)) {
            throw (
                "Signing certificate missing from $certificatePath. " +
                'Run as the account holding its private key; a .cer alone cannot sign.'
            )
        }

        $certificate = Get-Item -LiteralPath $certificatePath

        if (-not $certificate.HasPrivateKey) {
            throw 'The signing certificate has no private key on this account.'
        }

        $now = Get-Date

        if ($now -lt $certificate.NotBefore -or
            $now -gt $certificate.NotAfter) {
            throw 'The signing certificate is outside its validity period.'
        }

        $ekuOids = @(
            $certificate.Extensions |
            Where-Object {
                $_.Oid.Value -eq '2.5.29.37'
            } |
            ForEach-Object {
                $_.EnhancedKeyUsages |
                ForEach-Object { $_.Value }
            }
        )

        if ('1.3.6.1.5.5.7.3.3' -notin $ekuOids) {
            throw 'The certificate does not have the Code Signing enhanced key usage.'
        }
    }

    # These modes are used by build_itw_msi.sh.
    if ($CheckSigning) {
        Write-Host "Signing prerequisites ready: $SigningThumbprint"
        exit 0
    }

    if ($VerifyOnly) {
        foreach ($file in $Files) {
            Assert-JgcSignature `
                -SignTool $SignTool `
                -Thumbprint $SigningThumbprint `
                -File $file
        }

        exit 0
    }

    if ($SignOnly) {
        Invoke-JgcCodeSigning `
            -SignTool $SignTool `
            -Thumbprint $SigningThumbprint `
            -Files $Files `
            -TimestampUrl $TimestampUrl

        exit 0
    }
    
    foreach ($Command in @('cargo.exe', 'rustup.exe', 'link.exe')) {
        if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
            throw (
                "$Command was not found. Use Developer PowerShell for VS " +
                "or the x64 Native Tools Command Prompt with Rust installed."
            )
        }
    }

    $JdkHome = (Resolve-Path -LiteralPath $JdkHome).Path
    $JavaExe = Join-Path $JdkHome 'bin\java.exe'
    $JreDir = Join-Path $JdkHome 'jre'

    Assert-File $JavaExe
    Assert-File (Join-Path $JdkHome 'bin\javac.exe')
    Assert-File (Join-Path $JreDir 'bin\java.exe')
    Assert-File (Join-Path $JreDir 'lib\rt.jar')
    Assert-File $Manifest

    $PackageFiles = @(
        @{
            Source = Join-Path $RepoDir 'netx.build\lib\classes.jar'
            Destination = Join-Path $ShareDir 'javaws.jar'
        }
        @{
            Source = Join-Path $RepoDir 'netx\javaws_splash.png'
            Destination = Join-Path $ShareDir 'javaws_splash.png'
        }
        @{
            Source = Join-Path $RepoDir 'build-deps\tagsoup.jar'
            Destination = Join-Path $DepsDir 'tagsoup.jar'
        }
        @{
            Source = Join-Path $RepoDir 'build-deps\js.jar'
            Destination = Join-Path $DepsDir 'js.jar'
        }
        @{
            Source = Join-Path $RepoDir 'build-deps\mslinks.jar'
            Destination = Join-Path $DepsDir 'mslinks.jar'
        }
        @{
            Source = Join-Path $RepoDir 'itw-modularjdk.args'
            Destination = Join-Path $BinDir 'itw-modularjdk.args'
        }
    )

    foreach ($File in $PackageFiles) {
        Assert-File $File.Source
    }

    $BuildEnvironment = @{
        # Shared build environment
        ITW_JDK = $JdkHome
        JAVA_HOME = $JdkHome
        ITW_REPO = $RepoDir
        ITW_BUILD = $BuildDir
        ITW_DIST = $DistDir
        PATH = "$(Join-Path $JdkHome 'bin');$env:PATH"

        # Rust launcher's compile-time configuration
        JAVA = $JavaExe
        JRE = $JreDir
        ITW_LIBS = 'BUNDLED'

        NETX_JAR = Join-Path $ShareDir 'javaws.jar'
        SPLASH_PNG = Join-Path $ShareDir 'javaws_splash.png'
        TAGSOUP_JAR = Join-Path $DepsDir 'tagsoup.jar'
        RHINO_JAR = Join-Path $DepsDir 'js.jar'
        MSLINKS_JAR = Join-Path $DepsDir 'mslinks.jar'
        MODULARJDK_ARGS_LOCATION = Join-Path $BinDir 'itw-modularjdk.args'

        PLUGIN_JAR = $null
        JSOBJECT_JAR = $null
        LAUNCHER_BOOTCLASSPATH = $null

        RUSTFLAGS = '-C target-feature=+crt-static'
        CARGO_ENCODED_RUSTFLAGS = $null

        # Assigned separately for each executable
        PROGRAM_NAME = $null
        MAIN_CLASS = $null
        BIN_LOCATION = $null
    }

    foreach ($Name in $BuildEnvironment.Keys) {
        $SavedEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')

        [Environment]::SetEnvironmentVariable(
            $Name,
            $BuildEnvironment[$Name],
            'Process'
        )
    }

    # Clean all three build directories before compiling anything.
    foreach ($Launcher in $Launchers) {
        $LauncherBuildDir = Join-Path $BuildDir $Launcher.Name

        Write-Host "`nCleaning $($Launcher.Name)..."

        Invoke-Cargo -CargoArguments @(
            'clean'
            '--manifest-path'
            $Manifest
            '--target-dir'
            $LauncherBuildDir
        )
    }

    # Each executable has its own compile-time main class.
    foreach ($Launcher in $Launchers) {
        $LauncherBuildDir = Join-Path $BuildDir $Launcher.Name

        $env:PROGRAM_NAME = $Launcher.Name
        $env:MAIN_CLASS = $Launcher.MainClass
        $env:BIN_LOCATION = Join-Path $BinDir "$($Launcher.Name).exe"

        Write-Host "`nBuilding $($Launcher.Name).exe..."

        Invoke-Cargo -CargoArguments @(
            'build'
            '--release'
            '--manifest-path'
            $Manifest
            '--target'
            $Target
            '--target-dir'
            $LauncherBuildDir
        )

        $BuiltExe = Join-Path $LauncherBuildDir "$Target\release\launcher.exe"
        Assert-File $BuiltExe
    }

    # Package only after all three compilations have succeeded.
    Write-Host "`nPreparing distribution..."

    foreach ($Directory in @($BinDir, $ShareDir, $DepsDir)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    foreach ($File in $PackageFiles) {
        Copy-Item -LiteralPath $File.Source -Destination $File.Destination -Force
    }

    foreach ($Launcher in $Launchers) {
        $LauncherBuildDir = Join-Path $BuildDir $Launcher.Name
        $BuiltExe = Join-Path $LauncherBuildDir "$Target\release\launcher.exe"
        $Destination = Join-Path $BinDir "$($Launcher.Name).exe"

        Copy-Item -LiteralPath $BuiltExe -Destination $Destination -Force
    }

    # Sign the distribution copies after all binary/resource changes.
    $launcherFiles = @(
        $Launchers | ForEach-Object {
            Join-Path $BinDir "$($_.Name).exe"
        }
    )

    Write-Host "`nSigning Windows launchers..."

    Invoke-JgcCodeSigning `
        -SignTool $SignTool `
        -Thumbprint $SigningThumbprint `
        -Files $launcherFiles `
        -TimestampUrl $TimestampUrl

    Write-Host "`nBuild completed successfully."
    Write-Host "Distribution: $DistDir"

    Get-Item -LiteralPath @(
        (Join-Path $BinDir 'javaws.exe')
        (Join-Path $BinDir 'itweb-settings.exe')
        (Join-Path $BinDir 'policyeditor.exe')
    ) | Select-Object Name, Length, LastWriteTime
}
catch {
    [Console]::Error.WriteLine("BUILD FAILED: $($_.Exception.Message)")
    $BuildExitCode = 1
}
finally {
    foreach ($Name in $SavedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable(
            $Name,
            $SavedEnvironment[$Name],
            'Process'
        )
    }

    Pop-Location
}

exit $BuildExitCode
