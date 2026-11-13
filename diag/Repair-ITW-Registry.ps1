#Requires -Version 5.1
#Requires -RunAsAdministrator
<#

.SYNOPSIS
Restores the JGC IcedTea-Web machine-wide Windows registrations.
.DESCRIPTION
Repairs missing AND incorrect association values in the 64-bit HKLM view.
Backs up existing association/policy keys before the first registry write.
Preserves other values and appends Edge list members at unused indexes.
Does not change user defaults, UniversalSoldier state, PATH, or splash settings.
.EXAMPLE
.\Repair-ITW-Registry.ps1 -WhatIf
.EXAMPLE
.\Repair-ITW-Registry.ps1 -InstallDir 'D:\IcedTeaWeb\WebStart'
.EXAMPLE
.\Repair-ITW-Registry.ps1 -SkipEdgePolicies

.AUTHOR
Joao Gonzalez

#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$InstallDir = 'C:\Program Files\IcedTeaWeb\WebStart',

    [ValidateNotNullOrEmpty()]
    [string]$AllowedDomain = 'oracleoutsourcing.com',

    [switch]$SkipEdgePolicies,

    [ValidateNotNullOrEmpty()]
    [string]$BackupRoot = (Join-Path $env:ProgramData 'IcedTeaWeb\RegistryRepair')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$hklm = $null
$backupPath = $null

function Read-Value([string]$Path, [string]$Name) {
    $key = $hklm.OpenSubKey($Path)
    try {
        if ($null -eq $key -or $key.GetValueNames() -notcontains $Name) {
            return [pscustomobject]@{ Exists = $false; Kind = $null; Value = $null }
        }
        return [pscustomobject]@{
            Exists = $true
            Kind = [string]$key.GetValueKind($Name)
            Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    } finally { if ($key) { $key.Dispose() } }
}

function Matches-Value($Actual, $Expected) {
    return ($Actual.Exists -and $Actual.Kind -eq $Expected.Kind -and
        [string]::Equals([string]$Actual.Value, [string]$Expected.Value, [StringComparison]::OrdinalIgnoreCase))
}

function Add-PolicyMember($Entries, [string]$Policy, [string]$Value) {
    $path = 'SOFTWARE\Policies\Microsoft\Edge\' + $Policy
    $key = $hklm.OpenSubKey($path)
    try {
        $names = @()
        if ($key) {
            $names = @($key.GetValueNames())
            foreach ($name in $names) {
                if ($name -match '^[1-9][0-9]*$' -and
                    $key.GetValueKind($name) -eq 'String' -and
                    [string]::Equals([string]$key.GetValue($name), $Value,
                        [StringComparison]::OrdinalIgnoreCase)) { return }
            }
        }
        $index = 1
        while ($names -contains [string]$index) { $index++ }
        $Entries.Add([pscustomobject]@{
            Path = $path; Name = [string]$index; Value = $Value; Kind = 'String'
        })
    } 
    finally { 
        if ($key) { $key.Dispose() } 
    }
}

try {
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'This script targets the x64 ITW package.' }
    $InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
    $AllowedDomain = $AllowedDomain.Trim()
    if (-not $SkipEdgePolicies -and -not $AllowedDomain) { throw 'AllowedDomain cannot be blank.' }

    # Never register commands pointing at an incomplete/nonexistent installation.
    foreach ($relative in @('bin\javaws.exe', 'share\icedtea-web\javaws.jar', 'share\pixmaps\javaws.ico')) {
        $file = Join-Path $InstallDir $relative
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Required installed file missing: $file. Repair the MSI files first."
        }
    }

    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $command = '"' + $InstallDir + '\bin\javaws.exe" "%1"'
    $icon = '"' + $InstallDir + '\share\pixmaps\javaws.ico",0'
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $definitions = @(
        @('SOFTWARE\Classes\.jnlp', '', 'JNLPFile', 'String'),
        @('SOFTWARE\Classes\.jnlp', 'Content Type', 'application/x-java-jnlp-file', 'String'),
        @('SOFTWARE\Classes\.jnlp\OpenWithProgids', 'JNLPFile', '', 'String'),
        @('SOFTWARE\Classes\JNLPFile', '', 'JNLP File', 'String'),
        @('SOFTWARE\Classes\JNLPFile', 'EditFlags', 65536, 'DWord'),
        @('SOFTWARE\Classes\JNLPFile\DefaultIcon', '', $icon, 'String'),
        @('SOFTWARE\Classes\JNLPFile\shell\open\command', '', $command, 'String'),
        @('SOFTWARE\Classes\Applications\javaws.exe', 'FriendlyAppName', 'IcedTea-Web', 'String'),
        @('SOFTWARE\Classes\Applications\javaws.exe\SupportedTypes', '.jnlp', '', 'String'),
        @('SOFTWARE\Classes\Applications\javaws.exe\shell\open\command', '', $command, 'String'),
        @('SOFTWARE\Classes\MIME\Database\Content Type\application/x-java-jnlp-file', 'Extension', '.jnlp', 'String'),
        @('SOFTWARE\Classes\jnlp', '', 'URL:jnlp Protocol', 'String'),
        @('SOFTWARE\Classes\jnlp', 'URL Protocol', '', 'String'),
        @('SOFTWARE\Classes\jnlp\shell\open\command', '', $command, 'String'),
        @('SOFTWARE\Classes\jnlps', '', 'URL:jnlp Protocol', 'String'),
        @('SOFTWARE\Classes\jnlps', 'URL Protocol', '', 'String'),
        @('SOFTWARE\Classes\jnlps\shell\open\command', '', $command, 'String')
    )
    foreach ($d in $definitions) {
        $entries.Add([pscustomobject]@{ Path = $d[0]; Name = $d[1]; Value = $d[2]; Kind = $d[3] })
    }
    if (-not $SkipEdgePolicies) {
        Add-PolicyMember $entries 'AutoOpenFileTypes' 'jnlp'
        Add-PolicyMember $entries 'AutoOpenAllowedForURLs' $AllowedDomain
    }

    $changes = @($entries | Where-Object { -not (Matches-Value (Read-Value $_.Path $_.Name) $_) })
    if ($changes.Count -eq 0) {
        Write-Host 'All requested ITW registrations are already correct. No changes required.'
        exit 0
    }
    foreach ($entry in $changes) {
        $label = $entry.Name
        if ($label -eq '') { $label = '(Default)' }
        Write-Host "[CHANGE] HKLM\$($entry.Path) [$label] => <$($entry.Value)> ($($entry.Kind))"
    }
    if (-not $PSCmdlet.ShouldProcess('64-bit HKLM IcedTea-Web registrations',
            "Back up affected keys and apply $($changes.Count) registry repairs")) { return }

    # All backups must succeed before any registry value is written.
    $backupPath = Join-Path ([IO.Path]::GetFullPath($BackupRoot)) (
        (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($backupPath)
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    if (-not [Environment]::Is64BitProcess) { $regExe = Join-Path $env:SystemRoot 'Sysnative\reg.exe' }

    $roots = @(
        'SOFTWARE\Classes\.jnlp', 'SOFTWARE\Classes\JNLPFile',
        'SOFTWARE\Classes\Applications\javaws.exe',
        'SOFTWARE\Classes\MIME\Database\Content Type\application/x-java-jnlp-file',
        'SOFTWARE\Classes\jnlp', 'SOFTWARE\Classes\jnlps'
    )
    if (-not $SkipEdgePolicies) {
        $roots += 'SOFTWARE\Policies\Microsoft\Edge\AutoOpenFileTypes'
        $roots += 'SOFTWARE\Policies\Microsoft\Edge\AutoOpenAllowedForURLs'
    }
    $before = foreach ($entry in $changes) {
        $old = Read-Value $entry.Path $entry.Name
        [pscustomobject]@{
            Path = $entry.Path; Name = $entry.Name; Existed = $old.Exists
            OldKind = $old.Kind; OldValue = $old.Value
            NewKind = $entry.Kind; NewValue = $entry.Value
        }
    }
    @($before) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backupPath 'values-before.json') -Encoding UTF8
    $index = 0
    foreach ($path in $roots) {
        $index++
        $key = $hklm.OpenSubKey($path)
        if ($key) {
            $key.Dispose()
            $destination = Join-Path $backupPath ('key-{0:D2}.reg' -f $index)
            $output = & $regExe export "HKLM\$path" $destination /y 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Registry export failed for HKLM\${path}: $output" }
        }
    }

    foreach ($entry in $changes) {
        $key = $hklm.CreateSubKey($entry.Path)
        try { $key.SetValue($entry.Name, $entry.Value, [Microsoft.Win32.RegistryValueKind]$entry.Kind) }
        finally { $key.Dispose() }
        if (-not (Matches-Value (Read-Value $entry.Path $entry.Name) $entry)) {
            throw "Write verification failed: HKLM\$($entry.Path) [$($entry.Name)]"
        }
        Write-Host "[FIXED] HKLM\$($entry.Path) [$($entry.Name)]"
    }
    # Verify the complete requested footprint, not just changed values.
    foreach ($entry in $entries) {
        if (-not (Matches-Value (Read-Value $entry.Path $entry.Name) $entry)) {
            throw "Final verification failed: HKLM\$($entry.Path) [$($entry.Name)]"
        }
    }

    # Tells Windows that the file associations have changed, so Explorer can refresh its cached association 
    # and icon information after the registry repair. Microsoft recommends sending this notification when
    # associations or registered protocols change.
    try {
        if (-not ('ItwRegistryRepair.NativeMethods' -as [type])) {
            Add-Type -Namespace ItwRegistryRepair -Name NativeMethods -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(uint eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@
        }
        [ItwRegistryRepair.NativeMethods]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    } catch { Write-Warning 'Registry repaired; sign out/in to refresh file associations if needed.' }

    Write-Host "Repair complete. Verified $($entries.Count) requested values; changed $($changes.Count)."
    Write-Host "Backups: $backupPath"
    Write-Host 'Refresh edge://policy and test a fresh EBS launch as the affected normal user.'
    exit 0
} 
catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    if ($backupPath) { Write-Host "Backups: $backupPath. Repairs already applied are not automatically rolled back." }
    exit 1
} 
finally {
    if ($hklm) { 
        $hklm.Dispose() 
    }
}
