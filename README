# JGC-IcedTea-Web

Windows Java Web Start packaging, customization, and diagnostics based on the IcedTea-Web 1.8 branch.

This repository contains a modified distribution of **IcedTea-Web**, the Free Software implementation of Java Web Start originally based on **NetX**. It retains the upstream Java Web Start implementation and adds Windows build scripts, native launcher packaging, configurable splash screens, and tools for investigating Oracle E-Business Suite (EBS) / Oracle Forms launches.

Fork maintainer: **Joao Gonzalez**. Upstream authors and contributors remain credited in [AUTHORS](AUTHORS) and the source-file notices. This fork's name and packaging identify its modifications; they do not imply endorsement by the upstream project, Oracle, Azul, or customers whose resources may appear in a deployment.

**Documentation revision:** 18 October 2026. This README replaces the upstream-oriented package introduction with documentation of this fork. Technical details were checked against source commit [`df15e4187ed67bb3e41b3a4f1fbeea9fc56f4886`](https://github.com/jlopes7/JGC-IcedTea-Web/commit/df15e4187ed67bb3e41b3a4f1fbeea9fc56f4886).

## Project and source

- Fork: <https://github.com/jlopes7/JGC-IcedTea-Web>
- Development branch: [`1.8`](https://github.com/jlopes7/JGC-IcedTea-Web/tree/1.8)
- Upstream repository: <https://github.com/AdoptOpenJDK/IcedTea-Web>
- Historical project documentation: <https://icedtea.classpath.org/wiki/IcedTea-Web>

Use the exact source revision associated with a binary release when rebuilding or investigating that release. The development branch can change after a package is built.

## Changes in this distribution

| Area | Fork-specific behavior |
| --- | --- |
| Windows build workflow | Separate scripts build Java classes, build and sign Rust launchers, create a signed MSI, and create a ZIP from existing build outputs. |
| Native launchers | Packages `javaws.exe`, `itweb-settings.exe`, and `policyeditor.exe` for Windows x64. |
| MSI integration | Registers JNLP file associations, MIME information, `jnlp` / `jnlps` URL protocols, Open With entries, and launcher commands. The WiX finalization step gives association values stable component identities and explicit key paths. |
| Edge configuration | The MSI template includes automatic opening of `jnlp` downloads and a URL restriction for `oracleoutsourcing.com`, including its subdomains. These are deployment settings and can be adapted for other environments. |
| Custom splash | Supports a custom image and configurable dimensions through environment variables, with fallback to the standard splash when the custom image cannot be loaded. |
| EBS instrumentation | Includes optional HTTP and application lifecycle tracing for investigating EBS / Forms behavior. See the tracing limitation below. |
| Optional-resource logging | Uses warnings without exception stack traces for handled icon failures and the known `RunformBundle_en_GB` locale lookup. Required-resource failures retain their normal error handling. |
| Installed diagnostics | Includes registry verification, missing-value repair, console capture, evidence collection, logging examples, and user instructions under `diag`. |

The locale handling preserves Java resource-bundle fallback. It does not rename Oracle classes, modify signed Oracle JARs, or manufacture an Oracle `RunformBundle_en_GB` resource.

## Runtime and browser behavior

This Windows package targets **Java 8** and **Windows x64**. Install and configure a compatible Java 8 runtime separately. The build scripts require a full JDK 8, including `javac`, `jar`, and `jre/lib/rt.jar`.

The Windows packaging workflow disables the legacy native browser plugin. Applications run through the Java Web Start launcher; this distribution does not embed a Java plugin in Edge.

With accepted Edge policies and a matching download, the expected sequence is:

1. The user launches the EBS function in the browser.
2. Edge downloads the JNLP.
3. Edge opens it through the registered `javaws.exe` handler.

Automatic opening does **not** eliminate the download. The downloaded file must match the configured file type; a file saved only as `frmservlet`, without `.jnlp`, does not match the `jnlp` extension rule. The servlet URL itself need not end in `.jnlp`.

Verify effective policy status in `edge://policy`. Registry values alone do not establish that Edge accepts the policies. Microsoft documents management/join requirements for `AutoOpenFileTypes`; browser security checks and save-location settings can also affect the user experience. This package does not guarantee prompt-free launches on every machine.

See Microsoft's documentation for [AutoOpenFileTypes](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/autoopenfiletypes) and [AutoOpenAllowedForURLs](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/autoopenallowedforurls).

## Installed layout

The default MSI installation root is:

```text
C:\Program Files\IcedTeaWeb\WebStart
```

| Relative location | Contents |
| --- | --- |
| `bin` | Native launchers and launcher arguments. |
| `share\icedtea-web` | Java Web Start JAR and splash resources. |
| `share\pixmaps` | Launcher icon. |
| `win-deps-runtime` | Runtime dependency JARs. |
| `customer\NR` | Deployment-specific customer resources, including the configured splash image. |
| `diag` | Registry checker, repair tool, and user instructions. |
| `diag\ITW-EBS-Diagnostics-Toolkit` | Collector, launch wrapper, toolkit README, and logging-property example. |

The ZIP contains the packaged file layout. Extracting it does not perform the MSI's registry or environment integration, or create a Windows Installer product registration.

## Custom splash configuration

| Environment variable | Purpose |
| --- | --- |
| `ICEDTEA_WEB_SPLASH` | Set to `custom` to request the custom Java Web Start loading splash. |
| `ICEDTEA_WEB_PLUGIN_SPLASH` | Corresponding setting for the legacy plugin splash code. Setting it does not install or enable a browser plugin. |
| `ICEDTEA_WEB_SPLASH_CUSTOM_IMG` | Path to the custom image. |
| `ICEDTEA_WEB_SPLASH_MAXHEIGHT` | Positive height limit; the current MSI sets `650`. |
| `ICEDTEA_WEB_SPLASH_MAXWIDTH` | Optional positive width limit supported by the splash implementation. |

The current MSI points the image variable to `customer\NR\nr_logo_1.png` under the selected installation root. Update the customer resources and installer template when producing another deployment's package. Existing Windows sessions may need sign-out/sign-in to receive changed environment values.

## Diagnostics

| Tool or file | Purpose | Run as |
| --- | --- | --- |
| `diag\Check-ITW-Registry.cmd` | Read-only verification of associations, installation files, splash variables, PATH, and related registry evidence. | Affected normal user |
| `diag\Repair-ITW-Registry.cmd` | Restores missing machine values, appends missing PATH/policy entries, verifies writes, and reports conflicts without overwriting them. | Administrator |
| `diag\EBS-IcedTea-Web-User-Instructions.txt` | Browser reproduction and evidence-collection instructions. | Affected normal user |
| `diag\ITW-EBS-Diagnostics-Toolkit\Collect-ITW-EBS.cmd` | Collects available configuration, logs, cached libraries, JNLPs, selected registry/process/environment information, and a SHA256 inventory into a ZIP. | Affected normal user |
| `diag\ITW-EBS-Diagnostics-Toolkit\Launch-ITW-EBS.cmd` | Launches an unused JNLP once with verbose output and console capture. | Affected normal user |
| `diag\ITW-EBS-Diagnostics-Toolkit\deployment-diagnostics.properties` | Logging settings to merge into the active configuration. | Reference file |

The collector does not launch the application, clear its cache, or repair settings. Its automatic filename search includes `.jnlp` files and extensionless `frmservlet` / numbered variants.

The registry checker prints URL-policy entries for manual inspection; it does not currently validate the expected Oracle domain. Warnings do not produce a nonzero exit code in the checker. A clean registry report does not prove successful browser launch.

### Check and collect

Run in a normal Command Prompt, adjusting the installation path if necessary:

```cmd
cd /d "C:\Program Files\IcedTeaWeb\WebStart\diag"
Check-ITW-Registry.cmd
```

After following the logging and browser reproduction instructions, collect once:

```cmd
cd /d "C:\Program Files\IcedTeaWeb\WebStart\diag\ITW-EBS-Diagnostics-Toolkit"
if not exist "%USERPROFILE%\ITW-EBS-Repro" mkdir "%USERPROFILE%\ITW-EBS-Repro"
Collect-ITW-EBS.cmd - "..\.." - "%USERPROFILE%\ITW-EBS-Repro"
```

The first `-` allows collection without an explicitly supplied JNLP. The second `-` selects the default output parent. Existing files can be collected; files deleted by the application cannot be recovered by this tool.

EBS launch files may contain session-specific values and may be deleted after use. Use the actual downloaded filename, including its extension, and do not replay a previously used launch file simply to gather more logs.

### Repair missing registry values

From an elevated Command Prompt:

```cmd
"C:\Program Files\IcedTeaWeb\WebStart\diag\Repair-ITW-Registry.cmd"
```

Optional arguments select the installation root and allowed URL pattern:

```cmd
Repair-ITW-Registry.cmd "D:\IcedTeaWeb\WebStart" "oracleoutsourcing.com"
```

Run repair after all planned Oracle Java uninstallations, because another uninstaller may remove shared associations afterward. The tool requires the launcher, icon, and configured customer splash file to exist before starting repairs. It does not change per-user default-app selections or install missing binaries. Existing conflicting values are reported for review.

### Output and handling

- Collection ZIPs, retained collection folders, and registry reports: `%USERPROFILE%\ITW-EBS-Diagnostics`.
- Launch-wrapper console captures: `%USERPROFILE%\ITW-EBS-Repro`.
- An elevated repair writes its report under the profile of the account executing it.

Logs, configuration, JNLPs, and command lines can contain credentials or EBS session information. Common private-key filenames are excluded by the collector, but the result is not comprehensively redacted. Review evidence before sharing it through the appropriate support channel. The tools do not upload evidence automatically.

## Logging and EBS tracing

The usual per-user configuration file is:

```text
%USERPROFILE%\.config\icedtea-web\deployment.properties
```

Back it up and merge logging settings rather than replacing unrelated runtime, proxy, or security configuration:

```properties
deployment.log=true
deployment.log.headers=true
deployment.log.file=true
deployment.log.file.clientapp=true
deployment.log.stdstreams=true
deployment.console.startup.mode=SHOW
```

System configuration and locked properties can affect the effective settings. Consult the toolkit README for redirected configuration/cache paths and the distinction between launcher startup configuration and Java-side configuration.

The Rust launcher accepts JVM options using `-J`, including `-J-Ditw.ebs.trace=true`. It does not read `JAVAWS_OPT`, `JAVAWS_OPTS`, or `JAVAWS_OPTIONS`. Java itself reads `JAVA_TOOL_OPTIONS`; changes to that variable can affect other Java applications in the same environment. The launch wrapper scopes its additions to itself and its child processes.

**Current tracing limitation:** `EbsHttpTrace.install()` checks both the JVM property `itw.ebs.trace` and deployment property `deployment.ebs.trace`. In the source revision documented here, the latter is evaluated with `Boolean.getBoolean(keyEnabled)`, which treats the configured value as a system-property name instead of parsing a boolean value. Consequently, setting the ordinary trace flags alone may not install the HTTP handler. This gate needs correction to parse the deployment value, followed by rebuilding, before those settings can be relied on for HTTP tracing. Other verbose logging and console capture remain separate facilities.

Restore temporary logging and environment changes after troubleshooting when appropriate. Do not disable certificate or application security checks merely to obtain logs.

## Building the Windows package

### Prerequisites

- Windows x64 and a full JDK 8; the script default is `C:\cygwin64\zulu8`.
- Cygwin with Bash, Make, Autoconf, Automake, and the standard tools required by `autogen.sh` / `configure`.
- Windows PowerShell 5.1 or later for the Windows scripts.
- Rust/Cargo with the Windows MSVC target and Visual Studio C++ Build Tools. Run launcher builds in a shell where the MSVC linker is available.
- Runtime build dependencies under `build-deps`: `tagsoup.jar`, `js.jar`, and `mslinks.jar`.
- For MSI packaging: WiX 3.14.1 under `build-deps/wix-3.14.1` and WiXGen under `build-deps/wixgen.jar`.
- For the current signed EXE/MSI workflow: Windows SDK SignTool and a usable code-signing certificate/private key in the executing account's `CurrentUser\My` certificate store.

Use repository and JDK paths without spaces for the legacy Autotools Java build. Configure `ITW_SIGNING_THUMBPRINT` for your own certificate; `ITW_SIGNTOOL` and `ITW_TIMESTAMP_URL` provide signing-tool/timestamp overrides. The scripts' maintainer-specific certificate default is not a certificate or private key supplied to other builders. Certificate trust must be configured separately where required.

### Build sequence

In Cygwin, build the Java classes and JAR:

```bash
bash build_itw_classes.sh C:/cygwin64/zulu8
```

In a PowerShell environment with the MSVC tools and signing configuration available, build the native launchers and stage the Windows distribution:

```powershell
.\build_itw_exe.ps1 -JdkHome C:\cygwin64\zulu8
```

Apply your environment's execution-policy rules when invoking PowerShell scripts. The build script also has a companion `build_itw_exe.bat` entry point.

Then, in Cygwin with the signing environment available:

```bash
bash build_itw_msi.sh C:/cygwin64/zulu8
```

For a ZIP using existing build outputs:

```bash
bash build_itw_zip.sh
```

The ZIP script does not compile or sign code. Place custom ZIP output paths outside the source trees being copied, including `diag`.

| Output | Location |
| --- | --- |
| Compiled Java JAR | `netx.build/lib/classes.jar` |
| Windows distribution | `dist-native` |
| MSI staging image | `build-msi/image` |
| Signed MSI | `win-installer.build/jgc-j8-icedtea-web-<package-version>-<build-version>-x64.msi` |
| Default distribution ZIP | `dist-zip/JGC-IcedTea-Web-windows-x64.zip` |

Keep the deployable diagnostics under the repository's `diag` folder. Both package scripts copy this folder into the packaged image. The MSI also stages customer resources and the icon referenced by its registry template.

The original Autotools project and test infrastructure remain available. See `configure --help`, `Makefile.am`, `NEWS`, `ChangeLog`, and `tests` for the upstream build/test facilities. Plugin and test capabilities depend on build options and dependencies; a successful package build does not establish application compatibility.

## Licensing, attribution, and redistribution

IcedTea-Web is Free Software. [COPYING](COPYING) contains the GNU GPL version 2 text. The repository's [LICENSE](LICENSE) summary identifies GPL-covered code with exceptions and LGPL-covered code; individual files specify the applicable terms, including any later-version permissions. Existing source-file notices and exceptions remain authoritative.

This fork does not claim ownership of upstream contributions or relicense third-party components. The existing linking exceptions apply only where granted by the relevant notices. They do not remove the obligations that apply to distributing IcedTea-Web itself. New package branding, signatures, and installer metadata add no restrictions on recipients' rights under the applicable licences.

When redistributing a modified package, preserve applicable copyright, licence, exception, and warranty notices; include the required licence texts; and retain prominent modification notices and dates in changed files. Provide complete corresponding source, including required build and installation scripts, through an applicable GPLv2 section 3 distribution method. Publish the matching source revision alongside downloadable binary releases when using the equivalent source-access provision. A mutable development-branch link is not a substitute for the corresponding source of a particular binary.

Bundled dependencies and customer artwork retain their own applicable terms. Verify redistribution permission for deployment-specific logos and other assets. Do not infer that an asset has been relicensed merely because it is packaged here.

The software is provided without warranty to the extent stated in the applicable licences and permitted by law. This README summarizes the package; it does not replace licence texts, grant additional exceptions, or certify a complete distribution's licence compliance.

References: [GNU GPLv2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html), [GNU GPLv2 FAQ](https://www.gnu.org/licenses/old-licenses/gpl-2.0-faq.html), and [GNU Classpath licensing](https://www.gnu.org/software/classpath/license.html).

## Reporting issues

Report fork-specific packaging and customization issues through this repository's [issue tracker](https://github.com/jlopes7/JGC-IcedTea-Web/issues). Include the package version, source revision when known, Windows/Java versions, launch method, and reproduction time. Share diagnostic archives through an appropriate private support channel rather than attaching unreviewed session information to a public issue.

Credit for the underlying implementation belongs to the IcedTea-Web, NetX, GNU Classpath, OpenJDK, and other contributors identified by the project's notices and [AUTHORS](AUTHORS).
