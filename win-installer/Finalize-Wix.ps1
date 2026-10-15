[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WxsPath
)

# WiXGen 1.7 gives registry components random identities and no explicit value
# keypaths. Give each association value its own stable, repairable component.
$ErrorActionPreference = 'Stop'
$nsUri = 'http://schemas.microsoft.com/wix/2006/wi'
$doc = New-Object System.Xml.XmlDocument
$doc.PreserveWhitespace = $true
$doc.Load((Resolve-Path -LiteralPath $WxsPath).Path)
$ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
$ns.AddNamespace('w', $nsUri)

$required = @(
    @('SOFTWARE\Classes\.jnlp', '', 'JNLPFile'),
    @('SOFTWARE\Classes\.jnlp', 'Content Type', 'application/x-java-jnlp-file'),
    @('SOFTWARE\Classes\.jnlp\OpenWithProgids', 'JNLPFile', ''),
    @('SOFTWARE\Classes\JNLPFile', '', 'JNLP File'),
    @('SOFTWARE\Classes\JNLPFile\DefaultIcon', '', '"[INSTALLDIR]share\pixmaps\javaws.ico",0'),
    @('SOFTWARE\Classes\JNLPFile\shell\open\command', '', '"[INSTALLDIR]bin\javaws.exe" "%1"'),
    @('SOFTWARE\Classes\Applications\javaws.exe\shell\open\command', '', '"[INSTALLDIR]bin\javaws.exe" "%1"'),
    @('SOFTWARE\Classes\Applications\javaws.exe\SupportedTypes', '.jnlp', ''),
    @('SOFTWARE\Classes\MIME\Database\Content Type\application/x-java-jnlp-file', 'Extension', '.jnlp')
)
foreach ($entry in $required) {
    $keyPath, $valueName, $expected = $entry
    $keys = @($doc.SelectNodes('//w:RegistryKey', $ns) | Where-Object {
        $_.GetAttribute('Root') -eq 'HKLM' -and $_.GetAttribute('Key') -eq $keyPath
    })
    if ($keys.Count -eq 0) { throw "Missing registry key: HKLM\$keyPath." }
    $values = @($keys | ForEach-Object { $_.SelectNodes('w:RegistryValue', $ns) } | Where-Object { $_.GetAttribute('Name') -eq $valueName })
    if ($values.Count -ne 1 -or $values[0].GetAttribute('Type') -ne 'string' -or $values[0].GetAttribute('Value') -cne $expected) {
        throw "Missing or incorrect association value: HKLM\$keyPath [$valueName]."
    }
}

$seen = @{}
$count = 0
$sha = [Security.Cryptography.SHA256]::Create()
try {
    foreach ($component in @($doc.SelectNodes('//w:Component[w:RegistryKey]', $ns))) {
        $key = $component.SelectSingleNode('w:RegistryKey', $ns)
        $path = $key.GetAttribute('Key')
        # Limit the transformation to ITW's Classes registrations, preserving
        # unrelated installer registry components/environment variables.
        if ($key.GetAttribute('Root') -ne 'HKLM' -or $path -notmatch '^SOFTWARE\\Classes\\(?:\.jnlp(?:\\|$)|JNLPFile(?:\\|$)|jnlps?(?:\\|$)|Applications\\javaws\.exe(?:\\|$)|MIME\\Database\\Content Type\\application/x-java-jnlp-file$)') {
            continue
        }
        if ($component.GetAttribute('Win64') -ne 'yes') { throw "Association must be in the 64-bit registry view: $path" }
        $oldId = $component.GetAttribute('Id')
        $refs = @($doc.SelectNodes('//w:ComponentRef', $ns) | Where-Object { $_.GetAttribute('Id') -eq $oldId })
        if ($refs.Count -eq 0) { throw "Association component is not referenced by a feature: $path" }
        $values = @($key.SelectNodes('w:RegistryValue', $ns))
        if ($values.Count -eq 0) { throw "Association has no registry values: $path" }
        foreach ($value in $values) {
            $identity = ('JGC.ITW.Registry.v1|64|HKLM|' + $path + '|' + $value.GetAttribute('Name')).ToLowerInvariant()
            if ($seen.ContainsKey($identity)) { throw "Duplicate association value: $path [$($value.GetAttribute('Name'))]" }
            $seen[$identity] = $true
            $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '').ToLowerInvariant()
            $id = 'JgcReg_' + $hash.Substring(0, 24)
            $newComponent = $doc.CreateElement('Component', $nsUri)
            $newComponent.SetAttribute('Id', $id)
            $newComponent.SetAttribute('Guid', ([guid]::ParseExact($hash.Substring(0, 32), 'N')).ToString('B'))
            $newComponent.SetAttribute('Win64', 'yes')
            $newKey = $doc.CreateElement('RegistryKey', $nsUri)
            $newKey.SetAttribute('Root', 'HKLM')
            $newKey.SetAttribute('Key', $path)
            $newValue = $value.CloneNode($true)
            $newValue.SetAttribute('Id', $id + 'Value')
            $newValue.SetAttribute('KeyPath', 'yes')
            [void]$newKey.AppendChild($newValue)
            [void]$newComponent.AppendChild($newKey)
            [void]$component.ParentNode.InsertBefore($newComponent, $component)
            foreach ($ref in $refs) {
                $newRef = $ref.CloneNode($true)
                $newRef.SetAttribute('Id', $id)
                [void]$ref.ParentNode.InsertBefore($newRef, $ref)
            }
            $count++
        }
        foreach ($ref in $refs) { [void]$ref.ParentNode.RemoveChild($ref) }
        [void]$component.ParentNode.RemoveChild($component)
    }
} finally { $sha.Dispose() }
if ($count -eq 0) { throw 'No JNLP associations were finalized.' }
# Remove the previous ITW version before installing the replacement values.
$upgrade = $doc.SelectSingleNode('//w:MajorUpgrade', $ns)
if ($null -eq $upgrade) { throw 'MajorUpgrade is required for the ITW installer.' }
$upgrade.SetAttribute('Schedule', 'afterInstallInitialize')
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$writer = [System.Xml.XmlWriter]::Create((Resolve-Path -LiteralPath $WxsPath).Path, $settings)
try { $doc.Save($writer) } finally { $writer.Dispose() }
Write-Host "Validated and finalized $count JNLP registry values with stable component identities and explicit keypaths."
