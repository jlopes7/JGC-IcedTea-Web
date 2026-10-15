# EBS browser handoff and optional-resource diagnostics

## 1. MSI / WiX associations

The previous JSON already described the core `.jnlp`, `JNLPFile`, and MIME
entries. A WiXGen 1.7 fixture confirmed that they are emitted. Their absence on
the affected workstations therefore does not prove that they were absent from
the installed MSI. Installation/uninstallation ordering still needs checking.

This change removes the duplicate MIME registry declaration, explicitly selects
x64, quotes the icon path, and adds `.jnlp\OpenWithProgids` plus
`Applications\javaws.exe` registrations so Windows can offer ITW as a handler.
It preserves the existing `jnlp:` and `jnlps:` protocol registrations and the
upgrade code. The build label is `4rc` and the fourth MSI version field is `2`.
WiXGen already generates a new ProductCode when updates are enabled.

After WiXGen runs, `Finalize-Wix.ps1` validates the required values and splits the
association entries into one value per component. Each gets an explicit registry
value keypath and a stable ID/GUID derived from its registry location. This makes
the ownership of each registry value explicit across future builds and repairs.
The build stops before Candle if a required association is missing or incorrect.
`RemoveExistingProducts` runs after `InstallInitialize`, before the replacement
associations are written, so an old ITW uninstaller does not remove the new values.

For Oracle-to-ITW remediation, remove Oracle Java first, then install or repair
ITW. If Oracle removal must happen later, repair ITW afterwards. An ITW MSI cannot
prevent a different product's later uninstaller from deleting shared registry
keys. Do not edit Windows' hashed `UserChoice` registry values. An explicit user
choice of another application may still need changing through Windows Settings.

The existing managed Edge policies must also be effective in `edge://policy`:
`AutoOpenFileTypes` includes `jnlp`, and `AutoOpenAllowedForURLs` matches EBS.
Those policies are managed separately; this change does not overwrite them.

## 2. Icon diagnostics

Shortcut icon lookup/cache/conversion failures now log `WARNING_ALL` messages
without passing exceptions to the logger, so no stack trace is printed. Missing
`favicon.ico` downloads and their HTTP cleanup failures are likewise warnings.
The existing default-icon fallback remains in use. Normal download failures for
required JARs and unrelated application resources retain their previous error
and exception reporting.

Example:

```text
Application icon unavailable (NonFileProtocolException); using the default icon.
Optional resource /OA_JAVA/favicon.ico unavailable: HTTP 404 for GET
```

## 3. Oracle Forms British-English bundle

`RunformBundle` belongs to Oracle Forms, not ITW. The supplied signed Oracle JARs
contain `RunformBundle`, `RunformBundle_en`, and `RunformBundle_en_US`. They do not
contain `RunformBundle_en_EN` or `RunformBundle_en_GB`.

A Java 8 probe using the collected Oracle JARs confirmed that `Locale.UK` falls
back to `oracle.forms.engine.RunformBundle_en`. No Oracle JAR is copied, renamed,
modified or re-signed. Renaming a compiled class file would not change the binary
name recorded inside it, and modifying a signed JAR would invalidate signatures.

The exact optional `oracle.forms.engine.RunformBundle_en_GB` lookup now produces
a warning without a classloader stack trace. Its missing-class exception still
propagates to Java's ResourceBundle logic so normal locale fallback works.
Missing required application classes still retain their error behaviour. The
related HTTP `.class`/`.properties` probe warnings are limited to this exact
Oracle bundle. HTTP tracing continues to report the actual 403/404 status.

## Build and deployment

From the repository root, rebuild classes, the Windows distribution, and the MSI
in that order, using the existing scripts and signing configuration:

```text
Cygwin:      bash build_itw_classes.sh C:/cygwin64/zulu8
PowerShell:  .\build_itw_exe.ps1 -JdkHome C:\cygwin64\zulu8
Cygwin:      bash build_itw_msi.sh C:/cygwin64/zulu8
```

Use the existing approved PowerShell invocation if local execution policy
requires it. The EXE build script stages the rebuilt Java JAR; reusing an old
`dist-native` directory would package the old logging code.

Deploy/upgrade the newly built MSI with the normal managed deployment account.
For an already-installed package, a machine-registry repair can be requested
after Oracle removal, using the exact newly built MSI path:

```text
msiexec.exe /fm "C:\Packages\jgc-j8-icedtea-web-1.8.8-4rc-x64.msi" /qn /norestart /L*v "C:\Packages\itw-repair.log"
```

`/fm` repairs machine registry entries; use the matching installed MSI when doing
a repair, and use `/i` for the initial installation/upgrade. The log directory
must exist and be writable by the deployment account. Follow normal reboot-code
handling in the deployment tooling.

After installation, verify `.jnlp`, `JNLPFile\shell\open\command`, and the MIME
mapping in the 64-bit registry, check the effective Edge policies, and launch a
fresh EBS request through the browser. Download followed by automatic opening is
the expected behaviour; no Java browser plugin is introduced by this change.

## Validation

- Compiled the Web Start Java sources with a Java 8 JDK and the project's
  TagSoup, Rhino and MSLinks dependencies (native plugin classes excluded).
- Five regression tests cover warning-only output, absence of stack traces,
  omission of query credentials, narrow optional-resource matching, and retention
  of stack traces for required-resource failures.
- Generated real WiXGen 1.7 descriptors; verified all 17 association values have
  x64 components, explicit value keypaths, and feature references.
- Validated the descriptor against the WiX XML schema, checked repeated
  finalization and stable identities across independent generations, and verified
  that removing a required association fails the build gate.
- Checked the collected Oracle JARs with Java 8's ResourceBundle lookup to confirm
  the British-English-to-English fallback without modifying those JARs.

Windows Candle/Light compilation, MSI signing, installation/upgrade/repair, and
Edge handoff must be validated on the Windows pilot environment. Those cannot be
executed on the Linux validation host.
