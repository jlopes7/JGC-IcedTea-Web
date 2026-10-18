@echo off
setlocal DisableDelayedExpansion
rem Single-file CMD collector. Windows PowerShell 5.1 runs the embedded payload.
rem No elevation, downloads, execution-policy changes, or machine configuration changes.
set "ITWD_SELF=%~f0"
set "ITWD_JNLP=%~1"
set "ITWD_INSTALL=%~2"
set "ITWD_OUTPUT=%~3"
set "ITWD_EXTRA=%~4"
if not defined ITWD_JNLP set "ITWD_JNLP=%USERPROFILE%\Downloads\frmservlet"

if not defined ITWD_INSTALL if exist "%~dp0bin\javaws.exe" set "ITWD_INSTALL=%~dp0"
if not defined ITWD_INSTALL if exist "%~dp0..\bin\javaws.exe" for %%I in ("%~dp0..") do set "ITWD_INSTALL=%%~fI"
if not defined ITWD_INSTALL if exist "%~dp0..\..\bin\javaws.exe" for %%I in ("%~dp0..\..") do set "ITWD_INSTALL=%%~fI"
if not defined ITWD_INSTALL set "ITWD_INSTALL=C:\Program Files\IcedTeaWeb\WebStart"

if not exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
  echo ERROR: Windows PowerShell 5.1 is required.
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; try { $t=[IO.File]::ReadAllText($env:ITWD_SELF); $p=[regex]::Split($t,'(?m)^#==ITW_POWERSHELL==\r?$'); if($p.Count -ne 2){throw 'Invalid collector payload'}; & ([scriptblock]::Create($p[1])) } catch { Write-Host ('ERROR: '+$_.Exception.Message); exit 1 }"
exit /b %ERRORLEVEL%
#==ITW_POWERSHELL==
# Compatible with Windows PowerShell 5.1 / .NET Framework 4.5+.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw 'Windows PowerShell 5.1 or later is required.' }
if ($env:ITWD_JNLP -in @('/?', '-h', '--help')) {
    Write-Host 'Collect-ITW-EBS.cmd [JNLP-or--] [ITW-install-folder-or--] [output-parent-or--] [extra-evidence-folder]'
    Write-Host 'Example: Collect-ITW-EBS.cmd "%USERPROFILE%\Downloads\launch.jnlp" "C:\Program Files\IcedTeaWeb\WebStart"'
    Write-Host 'Defaults: JNLP=%USERPROFILE%\Downloads\frmservlet; ITW=C:\Program Files\IcedTeaWeb\WebStart.'
    Write-Host 'Use - for JNLP/ITW automatic discovery only; output defaults to %USERPROFILE%\ITW-EBS-Diagnostics.'
    Write-Host 'Run as the affected normal user. Exit codes: 0 ZIP created, 2 incomplete collection/ZIP, 1 fatal error.'
    exit 0
}
$script:Warnings = 0
$script:Copies = New-Object 'System.Collections.Generic.List[object]'
$script:Map = New-Object 'System.Collections.Generic.List[object]'
$script:SeenSources = @{}
$script:ConfigQueue = New-Object 'System.Collections.Generic.List[string]'
$script:SeenConfigs = @{}
$script:JavaRoots = @{}
$script:InstallRoots = @{}
function FullPath([string]$Path) { [IO.Path]::GetFullPath($Path) }
function Under([string]$Path, [string]$Root) {
    $a = (FullPath $Path).TrimEnd('\','/')
    $b = (FullPath $Root).TrimEnd('\','/')
    return ($a.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or $a.StartsWith($b + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))
}
$outParent = Join-Path $env:USERPROFILE 'ITW-EBS-Diagnostics'
if ($env:ITWD_OUTPUT -and $env:ITWD_OUTPUT -ne '-') { $outParent = FullPath $env:ITWD_OUTPUT }
$outParent = FullPath $outParent
[void][IO.Directory]::CreateDirectory($outParent)
$tag = 'ITW-EBS_{0}_{1}_{2}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,6))
$script:Bundle = Join-Path $outParent $tag
[void][IO.Directory]::CreateDirectory($Bundle)
foreach ($d in @('reports','files')) { [void][IO.Directory]::CreateDirectory((Join-Path $Bundle $d)) }
$script:Journal = Join-Path $Bundle 'reports\collection.log'
function Note([string]$Message) { ('{0:o} {1}' -f (Get-Date), $Message) | Add-Content -LiteralPath $Journal -Encoding UTF8 }
function Warn([string]$Message) { $script:Warnings++; Note ('WARNING: ' + $Message) }
function Report([string]$Name, [scriptblock]$Action) {
    $dest = Join-Path $Bundle ('reports\' + $Name)
    try { & $Action 2>&1 | Out-String -Width 4096 | Set-Content -LiteralPath $dest -Encoding UTF8 }
    catch { Warn ($Name + ': ' + $_.Exception.Message); $_ | Out-String | Add-Content -LiteralPath $dest -Encoding UTF8 }
}
function NativeReport([string]$Name, [string]$Exe, [string[]]$NativeArgs) {
    Report $Name {
        $pi=New-Object Diagnostics.ProcessStartInfo
        $pi.FileName=$Exe; $pi.UseShellExecute=$false; $pi.CreateNoWindow=$true
        $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
        $pi.Arguments=($NativeArgs | ForEach-Object {
            '"' + [regex]::Replace([regex]::Replace($_,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
        }) -join ' '
        $process=New-Object Diagnostics.Process; $process.StartInfo=$pi
        try {
            [void]$process.Start()
            $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(30000)) { $process.Kill(); throw ('Command timed out: '+$Exe) }
            $stdout.GetAwaiter().GetResult(); $stderr.GetAwaiter().GetResult()
            'ExitCode=' + $process.ExitCode
            if ($process.ExitCode -ne 0) { Note ($Name+': native exit code '+$process.ExitCode+'; absent registry keys are expected.') }
        } finally { $process.Dispose() }
    }
}
function PrivateKeyFile([string]$Path) {
    return ([IO.Path]::GetFileName($Path) -match '(?i)(clientcert|clientauth|\.p12$|\.pfx$|\.key$|\.jks$|\.keystore$)')
}
function SafeFiles([string]$Root) {
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { $items = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) }
        catch { Warn ('Cannot enumerate ' + $dir + ': ' + $_.Exception.Message); continue }
        foreach ($item in $items) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Note ('Skipped reparse point: ' + $item.FullName); continue }
            if (Under $item.FullName $outParent) { Note ('Skipped diagnostics output: ' + $item.FullName); continue }
            if ($item.PSIsContainer) { $stack.Push($item.FullName) } else { $item }
        }
    }
}
function CopyEvidence([string]$Source, [string]$Destination) {
    if (PrivateKeyFile $Source) { Note ('Skipped potential private-key store: ' + $Source); return }
    $inputStream = $null; $outputStream = $null; $createdDest=$false; $copyFailed=$false
    try {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination))
        $before = Get-Item -LiteralPath $Source -Force
        $inputStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $createdDest=$true
        $inputStream.CopyTo($outputStream)
        $outputStream.Dispose(); $outputStream = $null
        $inputStream.Dispose(); $inputStream = $null
        [IO.File]::SetLastWriteTimeUtc($Destination, $before.LastWriteTimeUtc)
        $after = Get-Item -LiteralPath $Source -Force
        if ($before.Length -ne $after.Length -or $before.LastWriteTimeUtc -ne $after.LastWriteTimeUtc) { Warn ('File changed during collection: ' + $Source) }
        $script:Copies.Add([pscustomobject]@{Source=$Source; BundlePath=$Destination.Substring($Bundle.Length + 1); Bytes=(Get-Item -LiteralPath $Destination).Length; SourceLastWriteUtc=$before.LastWriteTimeUtc.ToString('o'); SHA256=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash})
    } catch { $copyFailed=$true; Warn ('Copy failed: ' + $Source + ': ' + $_.Exception.Message) }
    finally {
        if ($inputStream) {$inputStream.Dispose()}; if ($outputStream) {$outputStream.Dispose()}
        if ($copyFailed -and $createdDest) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue }
    }
}
function Collect([string]$Source, [string]$Reason) {
    if ([string]::IsNullOrWhiteSpace($Source)) { return }
    try {
        $Source = FullPath $Source
        if ($script:SeenSources.ContainsKey($Source)) { return }
        $script:SeenSources[$Source] = $true
        if (-not (Test-Path -LiteralPath $Source)) { Note ('Not present: ' + $Source); return }
        $item = Get-Item -LiteralPath $Source -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Note ('Skipped reparse point root: ' + $Source); return }
        if (Under $Source $outParent) { Warn ('Source is inside output folder, skipped: ' + $Source); return }
        if ($item.PSIsContainer -and (Under $outParent $Source)) { Warn ('Source contains output folder, skipped: ' + $Source); return }
        if ($item.PSIsContainer -and $Source.TrimEnd('\','/') -eq [IO.Path]::GetPathRoot($Source).TrimEnd('\','/')) { Warn ('Refused entire drive/share root: ' + $Source); return }
        $dest = Join-Path $Bundle ('files\source_{0:D3}' -f ($script:Map.Count + 1))
        $script:Map.Add([pscustomobject]@{Source=$Source; BundlePath=$dest.Substring($Bundle.Length + 1); Reason=$Reason})
        Write-Host ('Collecting: ' + $Source)
        if ($item.PSIsContainer) {
            [void][IO.Directory]::CreateDirectory($dest)
            foreach ($f in (SafeFiles $Source)) { CopyEvidence $f.FullName (Join-Path $dest $f.FullName.Substring($Source.TrimEnd('\','/').Length + 1)) }
        } else { CopyEvidence $Source (Join-Path $dest $item.Name) }
    } catch { Warn ('Collection failed: ' + $Source + ': ' + $_.Exception.Message) }
}
function AddConfig([string]$File) {
    if ($File -and (Test-Path -LiteralPath $File -PathType Leaf)) {
        $File = FullPath $File
        if (-not $script:ConfigQueue.Contains($File)) { $script:ConfigQueue.Add($File) }
    }
}
# Decode the Java .properties escapes, including continuations and Unicode.
function UnescapeJava([string]$Value) {
    $sb = New-Object Text.StringBuilder
    for ($i=0; $i -lt $Value.Length; $i++) {
        $c=$Value[$i]
        if ($c -ne '\' -or $i -eq $Value.Length-1) { [void]$sb.Append($c); continue }
        $i++; $c=$Value[$i]
        switch -CaseSensitive ($c) {
            't' {[void]$sb.Append("`t")}
            'r' {[void]$sb.Append("`r")}
            'n' {[void]$sb.Append("`n")}
            'f' {[void]$sb.Append([char]12)}
            'u' {
                if ($i+4 -lt $Value.Length -and $Value.Substring($i+1,4) -match '^[0-9A-Fa-f]{4}$') { [void]$sb.Append([char][Convert]::ToInt32($Value.Substring($i+1,4),16)); $i+=4 }
                else { throw 'Invalid Unicode escape in properties file.' }
            }
            default {[void]$sb.Append($c)}
        }
    }
    $sb.ToString()
}
function ReadProperties([string]$File) {
    $result=@{}; $logical=''
    foreach ($line in [IO.File]::ReadAllLines($File, [Text.Encoding]::GetEncoding(28591))) {
        $logical += $line.TrimStart()
        $trail=[regex]::Match($logical,'\\+$').Length
        if ($trail % 2 -eq 1) { $logical=$logical.Substring(0,$logical.Length-1); continue }
        if ($logical -notmatch '^\s*[#!]' -and $logical -match '^\s*((?:\\.|[^\s=:])+)(?:\s*[=:]\s*|\s+)?(.*)$') {
            $result[(UnescapeJava $Matches[1])] = UnescapeJava $Matches[2]
        }
        $logical=''
    }
    return $result
}
function LocalReference([string]$Value, [string]$From) {
    if (-not $Value) { return $null }
    if ($Value -match '^file:') { $uri=[uri]$Value; return $uri.LocalPath }
    if ($Value -match '^[a-zA-Z][a-zA-Z0-9+.-]*://' ) { Note ('Remote reference not fetched: ' + $Value); return $null }
    if ($Value -match '[%$]') { Warn ('Unexpanded path reference; pass its real folder as argument 4: ' + $Value); return $null }
    if (-not [IO.Path]::IsPathRooted($Value)) { Warn ('Relative configured path, resolved against config folder for discovery only: ' + $Value); return Join-Path ([IO.Path]::GetDirectoryName($From)) $Value }
    return $Value
}
function AddJava([string]$Dir) {
    if ($Dir -and (Test-Path -LiteralPath (Join-Path $Dir 'bin\java.exe'))) { $script:JavaRoots[(FullPath $Dir)]=$true }
}
function AddInstall([string]$Dir) {
    if (-not $Dir) {return}
    if (Test-Path -LiteralPath (Join-Path $Dir 'javaws.exe')) { $Dir=Split-Path -Parent $Dir }
    if (Test-Path -LiteralPath (Join-Path $Dir 'bin\javaws.exe')) { $script:InstallRoots[(FullPath $Dir)]=$true }
}
Note 'Collector version 1.1; source reference jlopes7/JGC-IcedTea-Web branch 1.8, inspected 2026-10-15.'
Write-Host ('Output folder: ' + $Bundle)
Write-Host 'Copying the complete ITW cache can take several minutes. No cache is deleted.'
Report 'session.txt' {
    'CollectedLocal=' + (Get-Date -Format o); 'CollectedUTC=' + [DateTime]::UtcNow.ToString('o')
    'Computer=' + $env:COMPUTERNAME; 'User=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name
    'SID=' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    'Elevated=' + (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    'WorkingDirectory=' + (Get-Location).Path; $PSVersionTable; Get-TimeZone
}
Report 'environment.txt' {
    foreach ($scope in @('Process','User','Machine')) {
        '['+$scope+']'
        [Environment]::GetEnvironmentVariables($scope).GetEnumerator() | Where-Object { $_.Key -match '^(JAVA.*|JRE.*|JDK.*|ITW.*|ICEDTEA.*|XDG_.*|PATH|PATHEXT|USERPROFILE|USERNAME|USERDOMAIN|TEMP|TMP|APPDATA|LOCALAPPDATA|PROCESSOR_ARCHITECTURE|PROCESSOR_ARCHITEW6432|_JAVA_OPTIONS|J2D_.*|RUST_.*|HTTP_PROXY|HTTPS_PROXY|NO_PROXY)$' -and $_.Key -notmatch '^ITWD_' } | Sort-Object Key | Format-Table Key,Value -Wrap
    }
}
NativeReport 'where-java.txt' 'where.exe' @('java.exe')
NativeReport 'where-javaws.txt' 'where.exe' @('javaws.exe')
NativeReport 'ipconfig.txt' 'ipconfig.exe' @('/all')
NativeReport 'winhttp-proxy.txt' 'netsh.exe' @('winhttp','show','proxy')
Report 'os.txt' { Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture,LocalDateTime,LastBootUpTime | Format-List }
Report 'recent-application-events.txt' {
    # Standard-user event-log access varies; this report is best effort.
    $eventErrors=@()
    $events=Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-2); Id=@(1000,1001,1002)} -MaxEvents 500 -ErrorAction SilentlyContinue -ErrorVariable eventErrors
    if ($eventErrors) {Note ('Application events unavailable/empty: ' + ($eventErrors | Out-String))}
    $events | Where-Object {$_.Message -match '(?i)(javaw?s?\.exe|icedtea|jvm\.dll|webstart)'} | Select-Object TimeCreated,Id,ProviderName,Message | Format-List
}
Report 'processes.txt' {
    # Read only processes owned by this user; executable/cmdline can be empty when access is restricted.
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    foreach ($proc in (Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe' OR Name='javaws.exe' OR Name='msedge.exe'")) {
        try {
            $owner=Invoke-CimMethod -InputObject $proc -MethodName GetOwner
            if (($owner.Domain+'\'+$owner.User) -ieq $identity) {
                $proc | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate | Format-List
                if ($proc.ExecutablePath -and $proc.Name -match '^javaw?\.exe$') { AddJava (Split-Path -Parent (Split-Path -Parent $proc.ExecutablePath)) }
                if ($proc.ExecutablePath -and $proc.Name -eq 'javaws.exe') { AddInstall (Split-Path -Parent $proc.ExecutablePath) }
            }
        } catch { Note ('Process details unavailable PID ' + $proc.ProcessId) }
    }
}
Collect (Join-Path $env:WINDIR 'System32\drivers\etc\hosts') 'Hosts file'
# Narrow registry queries, including both registry views; missing/access-denied keys stay in reports.
$regKeys=@(
 'HKCU\Software\Classes\.jnlp','HKLM\Software\Classes\.jnlp',
 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.jnlp',
 'HKCR\.jnlp','HKCR\JNLPFile','HKCR\JNLPFile.File',
 'HKLM\Software\Classes\MIME\Database\Content Type\application/x-java-jnlp-file',
 'HKCU\Software\Classes\MIME\Database\Content Type\application/x-java-jnlp-file',
 'HKLM\Software\Policies\Microsoft\Edge','HKCU\Software\Policies\Microsoft\Edge',
 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
 'HKLM\Software\JavaSoft','HKCU\Software\JavaSoft',
 'HKLM\Software\Azul Systems','HKCU\Software\Azul Systems',
 'HKLM\Software\IcedTeaWeb','HKCU\Software\IcedTeaWeb',
 'HKLM\Software\JGComplianceMonitor\UniversalSoldier')
$progIds=@('JNLPFile','JNLPFile.File','IcedTeaWeb.JNLP','IcedTea-Web.JNLP')
foreach ($rp in @('Registry::HKEY_CLASSES_ROOT\.jnlp','HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.jnlp\UserChoice')) {
    try { $key=Get-Item -LiteralPath $rp; $progIds+=@($key.GetValue(''),$key.GetValue('ProgId')) } catch { Note ('Association key absent/unreadable: ' + $rp) }
}
foreach ($id in ($progIds | Where-Object {$_ -and $_ -match '^[\w.\-]+$'} | Select-Object -Unique)) { $regKeys += 'HKCR\' + $id }
$regIndex=0
foreach ($view in @('64','32')) {
    foreach ($key in ($regKeys | Select-Object -Unique)) {
        $regIndex++
        NativeReport ('registry_{0:D3}_{1}.txt' -f $regIndex,$view) 'reg.exe' @('query',$key,'/s',('/reg:'+$view))
    }
}
Report 'installed-java-itw.txt' {
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
            $base=$null; $uninstall=$null
            try {
                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                $uninstall=$base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall')
                if (-not $uninstall) {continue}
                foreach ($sub in $uninstall.GetSubKeyNames()) {
                    $app=$uninstall.OpenSubKey($sub)
                    try {
                        $name=[string]$app.GetValue('DisplayName')
                        if ($name -match '(?i)(java|jdk|jre|zulu|azul|icedtea|webstart|openwebstart)') {
                            [pscustomobject]@{Hive=$hive; View=$view; Key=$sub; DisplayName=$name; Version=$app.GetValue('DisplayVersion'); Publisher=$app.GetValue('Publisher'); InstallLocation=$app.GetValue('InstallLocation'); DisplayIcon=$app.GetValue('DisplayIcon'); UninstallString=$app.GetValue('UninstallString')} | Format-List
                            if ($app.GetValue('InstallLocation')) { AddInstall ([string]$app.GetValue('InstallLocation')); AddJava ([string]$app.GetValue('InstallLocation')) }
                        }
                    } finally {if ($app) {$app.Dispose()}}
                }
            } catch {Note ('Uninstall registry view unavailable: ' + $_.Exception.Message)}
            finally {if ($uninstall) {$uninstall.Dispose()}; if ($base) {$base.Dispose()}}
        }
    }
}
$configRoots=@((Join-Path $env:USERPROFILE '.config\icedtea-web'),(Join-Path $env:USERPROFILE '.icedtea'))
$cacheRoots=@((Join-Path $env:USERPROFILE '.cache\icedtea-web'))
if ($env:XDG_CONFIG_HOME) { $configRoots += Join-Path $env:XDG_CONFIG_HOME 'icedtea-web' }
if ($env:XDG_CACHE_HOME) { $cacheRoots += Join-Path $env:XDG_CACHE_HOME 'icedtea-web' }
if ($env:APPDATA) { $configRoots += Join-Path $env:APPDATA 'Sun\Java\Deployment' }
if ($env:LOCALAPPDATA) { $configRoots += Join-Path $env:LOCALAPPDATA 'Sun\Java\Deployment' }
foreach ($root in ($configRoots | Select-Object -Unique)) {
    Collect $root 'User deployment configuration/logs/security settings (potential private-key stores excluded)'
    AddConfig (Join-Path $root 'deployment.properties'); AddConfig (Join-Path $root 'deployment.config')
}
foreach ($root in $cacheRoots) { Collect $root 'Full ITW resource cache, metadata, persistence cache and temporary files' }
$systemDeployment=Join-Path $env:WINDIR 'Sun\Java\Deployment'
Collect $systemDeployment 'System deployment configuration and rulesets'
AddConfig (Join-Path $systemDeployment 'deployment.config'); AddConfig (Join-Path $systemDeployment 'deployment.properties')
AddJava $env:JAVA_HOME; AddJava $env:JRE_HOME
AddInstall $env:ITW_HOME
if ($env:ITWD_INSTALL -and $env:ITWD_INSTALL -ne '-') {
    if (-not (Test-Path -LiteralPath $env:ITWD_INSTALL -PathType Container)) { Warn ('Requested/default installation folder is missing: ' + $env:ITWD_INSTALL) }
    AddInstall $env:ITWD_INSTALL
}
AddInstall (Split-Path -Parent $env:ITWD_SELF)
foreach ($cmd in @(Get-Command javaws.exe -All -ErrorAction SilentlyContinue)) { AddInstall (Split-Path -Parent $cmd.Source) }
foreach ($cmd in @(Get-Command java.exe -All -ErrorAction SilentlyContinue)) { AddJava (Split-Path -Parent (Split-Path -Parent $cmd.Source)) }
foreach ($pf in @($env:ProgramFiles,${env:ProgramFiles(x86)})) {
    if ($pf) { AddInstall (Join-Path $pf 'IcedTeaWeb\WebStart'); AddInstall (Join-Path $pf 'IcedTea-Web') }
}
# Discover the executable registered for the effective JNLP ProgID as well as PATH installations.
foreach ($id in ($progIds | Where-Object {$_ -and $_ -match '^[\w.\-]+$'} | Select-Object -Unique)) {
    try {
        $key=Get-Item -LiteralPath ('Registry::HKEY_CLASSES_ROOT\'+$id+'\shell\open\command')
        $command=[string]$key.GetValue('')
        if ($command -match '^\s*"([^\"]+\.exe)"' -or $command -match '^\s*(\S+\.exe)') { AddInstall (Split-Path -Parent $Matches[1]) }
    } catch {Note ('No readable launch command for: ' + $id)}
}
foreach ($root in @($script:InstallRoots.Keys)) {
    Collect (Join-Path $root 'customer') 'Custom package customer resources'
    foreach ($f in (SafeFiles $root)) {
        if ($f.Name -in @('deployment.properties','deployment.config')) { AddConfig $f.FullName }
        if ($f.Extension -in @('.properties','.config','.args','.ini','.vmoptions','.bat','.cmd','.json') -and $f.FullName -ne $env:ITWD_SELF) { Collect $f.FullName 'Installation configuration/launcher settings' }
    }
    AddJava (Join-Path $root 'jre'); AddJava (Join-Path $root 'jdk')
}
# Iteratively discover local system property targets and custom log/cache/runtime paths.
$javaConfigsDone=@{}
for ($round=0; $round -lt 12; $round++) {
    foreach ($j in @($script:JavaRoots.Keys)) {
        if ($javaConfigsDone.ContainsKey($j)) {continue}; $javaConfigsDone[$j]=$true
        foreach ($sub in @('lib','jre\lib')) {
            foreach ($file in @('deployment.config','deployment.properties')) { AddConfig (Join-Path (Join-Path $j $sub) $file) }
        }
    }
    $pending=@($script:ConfigQueue | Where-Object {-not $script:SeenConfigs.ContainsKey($_)})
    if ($pending.Count -eq 0) {break}
    foreach ($file in $pending) {
        $script:SeenConfigs[$file]=$true; Collect $file 'Discovered deployment configuration'
        try {
            $props=ReadProperties $file
            foreach ($k in $props.Keys) {
                if ($k -eq 'deployment.jre.dir') {AddJava (LocalReference $props[$k] $file)}
                elseif ($k -in @('deployment.system.config','deployment.user.logdir','deployment.user.cachedir','deployment.user.pcachedir','deployment.user.tmp','deployment.system.cachedir','deployment.user.locksdir','deployment.user.runningfile','deployment.user.security.policy','deployment.system.security.policy','deployment.security.trusted.policy','deployment.user.security.trusted.cacerts','deployment.user.security.trusted.certs','deployment.user.security.trusted.jssecacerts','deployment.user.security.trusted.jssecerts','deployment.system.security.cacerts','deployment.system.security.jssecacerts','deployment.system.security.trusted.certs','deployment.system.security.trusted.jssecerts')) {
                    $target=LocalReference $props[$k] $file
                    if ($target) {Collect $target ($k+' from '+$file); if ($k -eq 'deployment.system.config') {AddConfig $target}}
                }
            }
        } catch {Warn ('Cannot parse config ' + $file + ': ' + $_.Exception.Message)}
    }
}
foreach ($root in @($script:JavaRoots.Keys)) {
    Collect (Join-Path $root 'release') 'Java build metadata'
    NativeReport ('java-version_{0:D2}.txt' -f (@($script:JavaRoots.Keys).IndexOf($root)+1)) (Join-Path $root 'bin\java.exe') @('-version')
    foreach ($lib in @('lib','jre\lib')) {
        foreach ($sec in @('java.security','java.policy','cacerts','jssecacerts')) {Collect (Join-Path $root ($lib+'\security\'+$sec)) 'Java security configuration / server trust store'}
    }
}
Report 'installations-and-runtimes.txt' {'[ITW roots]'; $script:InstallRoots.Keys; '[Java roots - candidates, confirm selection in launcher log]'; $script:JavaRoots.Keys}
Report 'package-binary-hashes.csv' {
    $records=foreach ($root in @($script:InstallRoots.Keys)) {
        foreach ($f in (SafeFiles $root | Where-Object {$_.Extension -in @('.exe','.dll','.jar')})) {
            try { [pscustomobject]@{Path=$f.FullName; Bytes=$f.Length; LastWriteUTC=$f.LastWriteTimeUtc.ToString('o'); FileVersion=$f.VersionInfo.FileVersion; ProductVersion=$f.VersionInfo.ProductVersion; Company=$f.VersionInfo.CompanyName; SHA256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash} }
            catch {Warn ('Cannot hash installed binary: ' + $f.FullName)}
        }
    }
    $records | ConvertTo-Csv -NoTypeInformation
}
# JNLP downloads / crash text at shallow locations; no browser profile databases.
$downloadDir=Join-Path $env:USERPROFILE 'Downloads'
try {
    $shell=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    if ($shell.'{374DE290-123F-4565-9164-39C4925E467B}') {$downloadDir=[Environment]::ExpandEnvironmentVariables($shell.'{374DE290-123F-4565-9164-39C4925E467B}')}
} catch {Note 'Using default Downloads folder.'}
$shallow=@($downloadDir,[Environment]::GetFolderPath('Desktop'),$env:TEMP,(Get-Location).Path)
foreach ($dir in ($shallow | Where-Object {$_} | Select-Object -Unique)) {
    try {
        foreach ($f in (Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction Stop | Where-Object {$_.Name -match '(?i)(\.jnlp$|^frmservlet(?:\s*\(\d+\))?$|^hs_err_pid.*\.log$|^replay_pid.*\.log$|^javaws.*\.log$|^itw.*\.log$|^j[ai]va.*\.trace$)'})) { Collect $f.FullName 'Downloaded JNLP or JVM/launcher diagnostic text' }
    } catch {Note ('Shallow search unavailable: ' + $dir)}
}
if ($env:TEMP) {Collect (Join-Path $env:TEMP ($env:USERNAME+'\netx')) 'NetX temporary runtime files'}
if ($env:XDG_RUNTIME_DIR) {Collect (Join-Path $env:XDG_RUNTIME_DIR ($env:USERNAME+'\netx')) 'XDG NetX runtime files'}
if ($env:ITWD_JNLP -and $env:ITWD_JNLP -ne '-') {
    if (Test-Path -LiteralPath $env:ITWD_JNLP -PathType Leaf) { Collect $env:ITWD_JNLP 'Requested/default failing JNLP' }
    else {Warn ('Requested/default JNLP file is missing: ' + $env:ITWD_JNLP)}
}
if ($env:ITWD_EXTRA -and $env:ITWD_EXTRA -ne '-') {
    if (Test-Path -LiteralPath $env:ITWD_EXTRA) {Collect $env:ITWD_EXTRA 'Explicit extra evidence (console capture, Forms logs, screenshots, or custom folders)'}
    else {Warn ('Explicit extra evidence folder is missing: ' + $env:ITWD_EXTRA)}
}
if ($script:InstallRoots.Count -eq 0) {Warn 'No ITW installation discovered. Run again with the actual ITW installation folder as argument 2.'}
$script:Copies | Export-Csv -LiteralPath (Join-Path $Bundle 'reports\copied-files.csv') -NoTypeInformation -Encoding UTF8
$script:Map | Export-Csv -LiteralPath (Join-Path $Bundle 'reports\source-map.csv') -NoTypeInformation -Encoding UTF8
@'
ITW / EBS diagnostic collection
Run as the affected user. This is a best-effort file snapshot, not a crash dump.
source-map.csv maps source folders/files to files/source_NNN.
copied-files.csv includes timestamps and SHA256 hashes of copied bytes.
collection.log records unavailable/locked/changing files and warnings.
registry_*.txt contains read-only reg query output, including absent-key errors.
Missing registry keys are normal. No machine settings or original files were changed.
The complete resource cache is copied, including libraries and .info metadata.
Common client-certificate/private-key filenames are excluded. This is not a secret scrubber.
No browser cookies/history databases, memory dumps, or private-key exports are collected.
Logs, downloaded JNLPs, cache entries and command lines can still contain EBS session tokens.
Review this folder/ZIP before sharing through an approved support channel.
No remote deployment.properties URL is fetched. Supply a locally saved copy if required.
No byte/file limits are silently applied. Failed copies are listed in collection.log.
Extra application logs outside ITW directories require the extra-evidence-folder argument.
Effective settings may include system overrides and locked properties; raw files are preserved.
For live hangs, collect while the failure is visible; for stable cache copies collect after closing Java.
Exit 0 means ZIP created with no collector warnings. It does not guarantee application completeness.
Exit 2 means a ZIP/copy/config discovery problem occurred; inspect retained folder and log.
'@ | Set-Content -LiteralPath (Join-Path $Bundle 'READ-ME.txt') -Encoding UTF8
Note ('Collection complete. Files=' + $script:Copies.Count + '; warnings=' + $script:Warnings)
Write-Host 'Creating ZIP (large caches may take several minutes)...'
$zipPath=$Bundle+'.zip'
$archive=$null; $zipFile=$null
try {
    Add-Type -AssemblyName System.IO.Compression
    $zipFile=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $archive=New-Object IO.Compression.ZipArchive($zipFile,[IO.Compression.ZipArchiveMode]::Create,$true)
    foreach ($f in (Get-ChildItem -LiteralPath $Bundle -Recurse -Force -File)) {
        $entry=$archive.CreateEntry($f.FullName.Substring($Bundle.Length+1).Replace('\','/'),[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new((Get-Date '2000-01-01'))
        if ($f.LastWriteTime.Year -ge 1980 -and $f.LastWriteTime.Year -le 2107) {$entry.LastWriteTime=[DateTimeOffset]$f.LastWriteTime}
        $entryStream=$entry.Open(); $sourceStream=$null
        try {$sourceStream=[IO.File]::OpenRead($f.FullName); $sourceStream.CopyTo($entryStream)}
        finally {if ($sourceStream) {$sourceStream.Dispose()}; $entryStream.Dispose()}
    }
    $archive.Dispose(); $archive=$null; $zipFile.Dispose(); $zipFile=$null
    Write-Host ('ZIP: ' + $zipPath)
    Write-Host ('Retained folder: ' + $Bundle)
    Write-Host ('Warnings: ' + $script:Warnings + ' (see reports\collection.log)')
    if ($script:Warnings -gt 0) {exit 2} else {exit 0}
} catch {
    Warn ('ZIP FAILED; retained folder is usable. ' + $_.Exception.Message)
    Write-Host ('ZIP failed/incomplete. Use retained folder: ' + $Bundle)
    Write-Host ('Do not submit the incomplete ZIP: ' + $zipPath)
    exit 2
} finally {if ($archive) {$archive.Dispose()}; if ($zipFile) {$zipFile.Dispose()}}
