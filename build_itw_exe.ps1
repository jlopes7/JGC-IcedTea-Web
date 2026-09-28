#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [Alias('JavaHome')]
    [ValidateNotNullOrEmpty()]
    [string]$JdkHome = 'C:\cygwin64\zulu8',

    [ValidateNotNullOrEmpty()]
    [string]$Toolchain = 'stable-x86_64-pc-windows-msvc'
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
