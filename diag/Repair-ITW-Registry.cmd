@echo off
setlocal DisableDelayedExpansion
rem Usage: Repair-ITW-Registry.cmd [InstallDir] [AllowedDomainOrURLPattern]
rem Run as administrator. Restores missing values; leaves conflicting values unchanged.
rem Set ITW_REPAIR_NO_PAUSE=1 for unattended execution.
if /I "%~1"=="/?" goto :usage
if not "%~3"=="" goto :usage
set "ITW_REPAIR_SELF=%~f0"

set "ITW_REPAIR_HOME=%~1"
if not defined ITW_REPAIR_HOME if exist "%~dp0bin\javaws.exe" set "ITW_REPAIR_HOME=%~dp0"
if not defined ITW_REPAIR_HOME if exist "%~dp0..\bin\javaws.exe" for %%I in ("%~dp0..") do set "ITW_REPAIR_HOME=%%~fI"
if not defined ITW_REPAIR_HOME set "ITW_REPAIR_HOME=C:\Program Files\IcedTeaWeb\WebStart"

set "ITW_REPAIR_DOMAIN=%~2"
if not defined ITW_REPAIR_DOMAIN set "ITW_REPAIR_DOMAIN=oracleoutsourcing.com"
set "ITW_REPAIR_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "ITW_REPAIR_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%ITW_REPAIR_PS%" exit /b 2
"%ITW_REPAIR_PS%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:ITW_REPAIR_SELF); & ([scriptblock]::Create(($s -split '(?m)^:POWERSHELL\r?$',2)[1]))"
set "ITW_REPAIR_RC=%ERRORLEVEL%"
echo.
echo Exit code: %ITW_REPAIR_RC% ^(0=all requested values present, 1=unresolved checks, 2=execution error^)
if not defined ITW_REPAIR_NO_PAUSE pause
exit /b %ITW_REPAIR_RC%
:usage
echo Usage: Repair-ITW-Registry.cmd [InstallDir] [AllowedDomainOrURLPattern]
echo Example: Repair-ITW-Registry.cmd "C:\Program Files\IcedTeaWeb\WebStart" "oracleoutsourcing.com"
exit /b 2
:POWERSHELL
$ErrorActionPreference = 'Stop'
$script:Counts = @{ PASS = 0; FIXED = 0; FAIL = 0 }
$script:Report = $null
function Say([string]$text) {
    Write-Host $text
    if ($script:Report) { Add-Content -LiteralPath $script:Report -Value $text -Encoding UTF8 }
}
function Result([string]$status, [string]$text) {
    $script:Counts[$status]++
    Say ('[{0}] {1}' -f $status, $text)
}
function Read-Reg([string]$path, [string]$name) {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $key = $null
    try {
        $key = $base.OpenSubKey($path)
        if ($null -eq $key -or $key.GetValueNames() -notcontains $name) { return $null }
        [pscustomobject]@{
            Value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            Kind = [string]$key.GetValueKind($name)
        }
    } finally { if ($key) { $key.Dispose() }; $base.Dispose() }
}
function Write-Reg([string]$path, [string]$name, $value, [string]$kind) {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $key = $null
    try {
        $key = $base.CreateSubKey($path)
        $key.SetValue($name, $value, [Microsoft.Win32.RegistryValueKind]$kind)
    } finally { if ($key) { $key.Dispose() }; $base.Dispose() }
    $r = Read-Reg $path $name
    if ($null -eq $r -or $r.Kind -ne $kind -or [string]$r.Value -cne [string]$value) {
        throw "Write verification failed: HKLM\$path [$name]"
    }
}
function Ensure([string]$path, [string]$name, $expected, [string]$kind = 'String', [switch]$EnvironmentValue) {
    $label = 'HKLM\{0} [{1}]' -f $path, $(if ($name) { $name } else { '(Default)' })
    try {
        $r = Read-Reg $path $name
        if ($null -eq $r) {
            Write-Reg $path $name $expected $kind
            Result FIXED "$label created = <$expected> ($kind)"
        } elseif (($r.Kind -eq $kind -or ($EnvironmentValue -and $r.Kind -eq 'ExpandString')) -and [string]$r.Value -ieq [string]$expected) {
            Result PASS "$label = <$($r.Value)> ($($r.Kind))"
        } else {
            Result FAIL "$label exists = <$($r.Value)> ($($r.Kind)); expected <$expected> ($kind). Left unchanged."
        }
    } catch { Result FAIL "$label : $($_.Exception.Message)" }
}
function Ensure-PolicyMember([string]$policy, [string]$expected) {
    $path = "SOFTWARE\Policies\Microsoft\Edge\$policy"
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $key = $null
    try {
        $key = $base.OpenSubKey($path)
        $names = @()
        if ($key) {
            $names = @($key.GetValueNames())
            foreach ($n in $names) {
                $v = $key.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                Say "[INFO] Existing $policy [$n] = <$v>"
                if ($n -match '^[1-9][0-9]*$' -and $key.GetValueKind($n) -eq 'String' -and [string]$v -ieq $expected) {
                    Result PASS "$policy contains <$expected> at [$n]."
                    return
                }
            }
        }
        $index = 1
        while ($names -contains [string]$index) { $index++ }
        # Add an unused numbered value; preserve the rest of the policy list.
        Ensure $path ([string]$index) $expected
    } finally { if ($key) { $key.Dispose() }; $base.Dispose() }
}
function Ensure-MachinePath([string]$bin) {
    $path = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $r = Read-Reg $path 'Path'
    if ($r -and $r.Kind -notin @('String', 'ExpandString')) {
        Result FAIL 'Machine PATH has an unexpected registry type; left unchanged.'
        return
    }
    $old = ''; $kind = 'ExpandString'
    if ($r) { $old = [string]$r.Value; $kind = $r.Kind }
    foreach ($part in ($old -split ';')) {
        if ([Environment]::ExpandEnvironmentVariables($part.Trim().Trim('"')).TrimEnd('\') -ieq $bin) {
            Result PASS "Machine PATH includes <$bin>."
            return
        }
    }
    $new = $old
    if ($new -and -not $new.EndsWith(';')) { $new += ';' }
    $new += $bin
    Say "[INFO] Machine PATH before: <$old>"
    Write-Reg $path 'Path' $new $kind
    Result FIXED "Appended <$bin> to machine PATH; preserved existing entries and type."
}
$exitCode = 2
try {
    $reportFolder = Join-Path $env:USERPROFILE 'ITW-EBS-Diagnostics'
    [void][IO.Directory]::CreateDirectory($reportFolder)
    $script:Report = Join-Path $reportFolder ('ITW-Registry-Repair_{0}_{1}_{2}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'), $PID)
    Set-Content -LiteralPath $script:Report -Value 'IcedTea-Web registry repair report' -Encoding UTF8
    Say "Computer: $env:COMPUTERNAME; execution account: $env:USERDOMAIN\$env:USERNAME"
    Say "Time: $(Get-Date -Format o)"
    Say 'Mode: restore missing values only; report conflicts without overwriting them.'
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'This script requires 64-bit Windows.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $admin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    finally { $identity.Dispose() }
    if (-not $admin) { throw 'Administrator rights are required. Right-click this CMD and select Run as administrator, or use an elevated Command Prompt.' }
    $homePath = [IO.Path]::GetFullPath($env:ITW_REPAIR_HOME).TrimEnd('\')
    $domain = $env:ITW_REPAIR_DOMAIN.Trim()
    if ([string]::IsNullOrWhiteSpace($domain)) { throw 'An allowed domain or URL pattern is required.' }
    Say "Installation: $homePath; Edge allowed pattern: $domain"
    # Validate the installation before making any registry changes.
    foreach ($file in @('bin\javaws.exe', 'share\pixmaps\javaws.ico', 'customer\NR\nr_logo_1.png')) {
        $p = Join-Path $homePath $file
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Required installed file missing: $p. No registry repair has started; repair the MSI installation first." }
    }
    $command = '"' + $homePath + '\bin\javaws.exe" "%1"'
    $icon = '"' + $homePath + '\share\pixmaps\javaws.ico",0'
    Say ''
    Say '--- All 17 MSI association values: HKLM, 64-bit view ---'
    Ensure 'SOFTWARE\Classes\.jnlp' '' 'JNLPFile'
    Ensure 'SOFTWARE\Classes\.jnlp' 'Content Type' 'application/x-java-jnlp-file'
    Ensure 'SOFTWARE\Classes\.jnlp\OpenWithProgids' 'JNLPFile' ''
    Ensure 'SOFTWARE\Classes\JNLPFile' '' 'JNLP File'
    Ensure 'SOFTWARE\Classes\JNLPFile' 'EditFlags' 65536 'DWord'
    Ensure 'SOFTWARE\Classes\JNLPFile\DefaultIcon' '' $icon
    Ensure 'SOFTWARE\Classes\JNLPFile\shell\open\command' '' $command
    Ensure 'SOFTWARE\Classes\jnlp' '' 'URL:jnlp Protocol'
    Ensure 'SOFTWARE\Classes\jnlp' 'URL Protocol' ''
    Ensure 'SOFTWARE\Classes\jnlp\shell\open\command' '' $command
    Ensure 'SOFTWARE\Classes\jnlps' '' 'URL:jnlp Protocol'
    Ensure 'SOFTWARE\Classes\jnlps' 'URL Protocol' ''
    Ensure 'SOFTWARE\Classes\jnlps\shell\open\command' '' $command
    Ensure 'SOFTWARE\Classes\Applications\javaws.exe' 'FriendlyAppName' 'IcedTea-Web'
    Ensure 'SOFTWARE\Classes\Applications\javaws.exe\shell\open\command' '' $command
    Ensure 'SOFTWARE\Classes\Applications\javaws.exe\SupportedTypes' '.jnlp' ''
    Ensure 'SOFTWARE\Classes\MIME\Database\Content Type\application/x-java-jnlp-file' 'Extension' '.jnlp'
    Say ''
    Say '--- Splash environment and machine PATH ---'
    $environmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    Ensure $environmentKey 'ICEDTEA_WEB_SPLASH' 'custom' -EnvironmentValue
    Ensure $environmentKey 'ICEDTEA_WEB_PLUGIN_SPLASH' 'custom' -EnvironmentValue
    Ensure $environmentKey 'ICEDTEA_WEB_SPLASH_MAXHEIGHT' '650' -EnvironmentValue
    Ensure $environmentKey 'ICEDTEA_WEB_SPLASH_CUSTOM_IMG' "$homePath\customer\NR\nr_logo_1.png" -EnvironmentValue
    Ensure-MachinePath "$homePath\bin"
    Say ''
    Say '--- Edge auto-open policy list members ---'
    Ensure-PolicyMember 'AutoOpenFileTypes' 'jnlp'
    Ensure-PolicyMember 'AutoOpenAllowedForURLs' $domain
    Say ''
    Say "Summary: $($script:Counts.PASS) PASS, $($script:Counts.FIXED) FIXED, $($script:Counts.FAIL) FAIL."
    Say 'No current-user defaults, MSI registration, security settings, or download-location prompts were changed.'
    Say 'Run Check-ITW-Registry.cmd as the affected normal user to inspect their effective file association.'
    Say 'Reload policies in edge://policy and verify their status; registry presence does not prove policy acceptance.'
    Say 'Sign out and sign in before testing if environment values or PATH were restored.'
    $exitCode = 0
    if ($script:Counts.FAIL -gt 0) { $exitCode = 1 }
} catch {
    Say "[ERROR] $($_.Exception.Message)"
    Say 'Any repairs already logged as FIXED remain applied; the script does not roll them back.'
    $exitCode = 2
}
if ($script:Report) { Write-Host "Report: $script:Report" }
exit $exitCode
