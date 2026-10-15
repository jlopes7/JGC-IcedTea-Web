@echo off
setlocal DisableDelayedExpansion
rem Read-only. Usage: Check-ITW-Registry.cmd [ITW installation folder]
set "ITW_CHECK_SELF=%~f0"
set "ITW_CHECK_HOME=%~1"
if not defined ITW_CHECK_HOME set "ITW_CHECK_HOME=C:\Program Files\IcedTeaWeb\WebStart"
set "ITW_CHECK_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "ITW_CHECK_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%ITW_CHECK_PS%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:ITW_CHECK_SELF); & ([scriptblock]::Create(($s -split '(?m)^:POWERSHELL\r?$',2)[1]))"
set "ITW_CHECK_RC=%ERRORLEVEL%"
echo.
echo Exit code: %ITW_CHECK_RC% ^(0=passed, 1=failed checks, 2=script error^)
if not defined ITW_CHECK_NO_PAUSE pause
exit /b %ITW_CHECK_RC%
:POWERSHELL
$ErrorActionPreference = 'Stop'
$script:Passed = 0; $script:Failed = 0; $script:Warnings = 0
$script:Lines = New-Object 'System.Collections.Generic.List[string]'
function Say([string]$s) { Write-Host $s; $script:Lines.Add($s) }
function Result([string]$status, [string]$text) {
    switch ($status) {
        'PASS' { $script:Passed++ }
        'FAIL' { $script:Failed++ }
        'WARN' { $script:Warnings++ }
    }
    Say ('[{0}] {1}' -f $status, $text)
}
function Read-Reg($hive, $view, [string]$path, [string]$name) {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
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
function Check($hive, [string]$path, [string]$name, [string]$expected, [string]$kind = 'String') {
    $label = '{0}\{1} [{2}]' -f $hive, $path, $(if ($name) { $name } else { '(Default)' })
    $r = Read-Reg $hive 'Registry64' $path $name
    if ($null -eq $r) { Result FAIL "$label MISSING"; return }
    if (($kind -split '\|') -contains $r.Kind -and [string]$r.Value -ieq $expected) {
        Result PASS "$label = <$($r.Value)> ($($r.Kind))"
    } else {
        Result FAIL "$label = <$($r.Value)> ($($r.Kind)); expected <$expected> ($kind)"
    }
}
function Show-PolicyList([string]$name) {
    $found = $false; $hasJnlp = $false
    foreach ($hive in @('LocalMachine', 'CurrentUser')) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, 'Registry64')
        $key = $null
        try {
            $key = $base.OpenSubKey("SOFTWARE\Policies\Microsoft\Edge\$name")
            if ($key) {
                foreach ($n in $key.GetValueNames()) {
                    $found = $true; $v = $key.GetValue($n)
                    Say "[INFO] $hive Edge $name [$n] = <$v>"
                    if ([string]$v -ieq 'jnlp' -and $key.GetValueKind($n) -eq 'String') { $hasJnlp = $true }
                }
            }
        } finally { if ($key) { $key.Dispose() }; $base.Dispose() }
    }
    if (-not $found) { Result WARN "Edge $name has no entries." }
    elseif ($name -eq 'AutoOpenFileTypes' -and -not $hasJnlp) { Result WARN 'Edge AutoOpenFileTypes does not contain the string jnlp.' }
}
$exitCode = 2
try {
    $homePath = [IO.Path]::GetFullPath($env:ITW_CHECK_HOME).TrimEnd('\')
    $command = '"' + $homePath + '\bin\javaws.exe" "%1"'
    $icon = '"' + $homePath + '\share\pixmaps\javaws.ico",0'
    Say 'IcedTea-Web MSI registry verification (read-only; 64-bit installation)'
    Say "Computer: $env:COMPUTERNAME   User: $env:USERDOMAIN\$env:USERNAME"
    Say "Time: $(Get-Date -Format o)   Expected installation: $homePath"
    Say 'Empty <> is an expected empty string, not a missing value.'
    Say ''
    Say '--- All 17 installer association values: HKLM, 64-bit view ---'
    Check LocalMachine 'SOFTWARE\Classes\.jnlp' '' 'JNLPFile'
    Check LocalMachine 'SOFTWARE\Classes\.jnlp' 'Content Type' 'application/x-java-jnlp-file'
    Check LocalMachine 'SOFTWARE\Classes\.jnlp\OpenWithProgids' 'JNLPFile' ''
    Check LocalMachine 'SOFTWARE\Classes\JNLPFile' '' 'JNLP File'
    Check LocalMachine 'SOFTWARE\Classes\JNLPFile' 'EditFlags' '65536' 'DWord'
    Check LocalMachine 'SOFTWARE\Classes\JNLPFile\DefaultIcon' '' $icon
    Check LocalMachine 'SOFTWARE\Classes\JNLPFile\shell\open\command' '' $command
    Check LocalMachine 'SOFTWARE\Classes\jnlp' '' 'URL:jnlp Protocol'
    Check LocalMachine 'SOFTWARE\Classes\jnlp' 'URL Protocol' ''
    Check LocalMachine 'SOFTWARE\Classes\jnlp\shell\open\command' '' $command
    Check LocalMachine 'SOFTWARE\Classes\jnlps' '' 'URL:jnlp Protocol'
    Check LocalMachine 'SOFTWARE\Classes\jnlps' 'URL Protocol' ''
    Check LocalMachine 'SOFTWARE\Classes\jnlps\shell\open\command' '' $command
    Check LocalMachine 'SOFTWARE\Classes\Applications\javaws.exe' 'FriendlyAppName' 'IcedTea-Web'
    Check LocalMachine 'SOFTWARE\Classes\Applications\javaws.exe\shell\open\command' '' $command
    Check LocalMachine 'SOFTWARE\Classes\Applications\javaws.exe\SupportedTypes' '.jnlp' ''
    Check LocalMachine 'SOFTWARE\Classes\MIME\Database\Content Type\application/x-java-jnlp-file' 'Extension' '.jnlp'
    Say ''
    Say '--- Installed files and persisted environment ---'
    foreach ($file in @('bin\javaws.exe', 'share\pixmaps\javaws.ico', 'customer\NR\nr_logo_1.png')) {
        $p = Join-Path $homePath $file
        if (Test-Path -LiteralPath $p -PathType Leaf) { Result PASS "File exists: $p" }
        else { Result FAIL "File missing: $p" }
    }
    $environmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    Check LocalMachine $environmentKey 'ICEDTEA_WEB_SPLASH' 'custom' 'String|ExpandString'
    Check LocalMachine $environmentKey 'ICEDTEA_WEB_PLUGIN_SPLASH' 'custom' 'String|ExpandString'
    Check LocalMachine $environmentKey 'ICEDTEA_WEB_SPLASH_MAXHEIGHT' '650' 'String|ExpandString'
    Check LocalMachine $environmentKey 'ICEDTEA_WEB_SPLASH_CUSTOM_IMG' "$homePath\customer\NR\nr_logo_1.png" 'String|ExpandString'
    $pathFound = $false
    foreach ($source in @(@('LocalMachine', $environmentKey), @('CurrentUser', 'Environment'))) {
        $r = Read-Reg $source[0] 'Registry64' $source[1] 'Path'
        if ($r) {
            foreach ($part in ([string]$r.Value -split ';')) {
                $expanded = [Environment]::ExpandEnvironmentVariables($part.Trim().Trim('"')).TrimEnd('\')
                if ($expanded -ieq "$homePath\bin") { $pathFound = $true; Say "[INFO] ITW bin is in persisted $($source[0]) PATH." }
            }
        }
    }
    if ($pathFound) { Result PASS 'Persisted PATH includes the ITW bin folder.' }
    else { Result FAIL 'Persisted machine/user PATH does not include the ITW bin folder.' }
    Say ''
    Say '--- Current user: merged Classes and explicit default application ---'
    Check ClassesRoot '.jnlp' '' 'JNLPFile'
    Check ClassesRoot 'JNLPFile\shell\open\command' '' $command
    $choice = Read-Reg CurrentUser 'Registry64' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.jnlp\UserChoice' 'ProgId'
    if ($choice) {
        Say "[INFO] Current-user JNLP UserChoice ProgId: $($choice.Value)"
        $handler = Read-Reg ClassesRoot 'Registry64' ($choice.Value + '\shell\open\command') ''
        if ($handler -and [string]$handler.Value -ieq $command) { Result PASS 'Explicit user default points to this ITW launcher.' }
        else { Result WARN "Explicit user default may override the MSI association. Handler: <$($handler.Value)>" }
    } else { Say '[INFO] No explicit JNLP UserChoice; merged Classes association applies.' }
    Say ''
    Say '--- Edge policies (registry evidence; verify effective status in edge://policy) ---'
    Show-PolicyList 'AutoOpenFileTypes'
    Show-PolicyList 'AutoOpenAllowedForURLs'
    foreach ($name in @('DirectInvokeEnabled', 'DownloadRestrictions')) {
        foreach ($hive in @('LocalMachine', 'CurrentUser')) {
            $r = Read-Reg $hive 'Registry64' 'SOFTWARE\Policies\Microsoft\Edge' $name
            if ($r) { Say "[INFO] $hive Edge $name = <$($r.Value)> ($($r.Kind))" }
        }
    }
    Say ''
    Say '--- Other registry view (informational; does not replace required 64-bit entries) ---'
    $other = Read-Reg LocalMachine 'Registry32' 'SOFTWARE\Classes\JNLPFile\shell\open\command' ''
    if ($other) { Say "[INFO] 32-bit JNLPFile command: <$($other.Value)>" }
    else { Say '[INFO] No JNLPFile command in the 32-bit registry view.' }
    Say ''
    Say '--- Registered IcedTea-Web installations ---'
    $installed = $false
    foreach ($view in @('Registry64', 'Registry32')) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
        $uninstall = $null
        try {
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($uninstall) {
                foreach ($sub in $uninstall.GetSubKeyNames()) {
                    $entry = $uninstall.OpenSubKey($sub)
                    if ($null -eq $entry) { continue }
                    try {
                        $display = [string]$entry.GetValue('DisplayName')
                        if ($display -match 'IcedTea.?Web') {
                            $installed = $true
                            Say "[INFO] $view : $display; version=$($entry.GetValue('DisplayVersion')); key=$sub; location=$($entry.GetValue('InstallLocation'))"
                        }
                    } finally { $entry.Dispose() }
                }
            }
        } finally { if ($uninstall) { $uninstall.Dispose() }; $base.Dispose() }
    }
    if (-not $installed) { Result WARN 'No IcedTea-Web machine installation found in Uninstall registry entries.' }
    Say ''
    Say "Summary: $script:Passed PASS, $script:Failed FAIL, $script:Warnings WARN."
    Say 'Warnings need review. A PASS does not confirm effective Edge policies or a successful browser launch.'
    $exitCode = 0
    if ($script:Failed -gt 0) { $exitCode = 1 }
} catch {
    Say "[ERROR] Registry verification could not finish: $($_.Exception.Message)"
    $exitCode = 2
}
try {
    $reportFolder = Join-Path $env:USERPROFILE 'ITW-EBS-Diagnostics'
    [void][IO.Directory]::CreateDirectory($reportFolder)
    $report = Join-Path $reportFolder ('ITW-Registry-Check_{0}_{1}_{2}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'), $PID)
    $script:Lines | Set-Content -LiteralPath $report -Encoding UTF8
    Write-Host "Report: $report"
} catch { Write-Host "[ERROR] Could not save report: $($_.Exception.Message)"; $exitCode = 2 }
exit $exitCode
