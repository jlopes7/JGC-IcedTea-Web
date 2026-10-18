IcedTea-Web 1.8 / JGC EBS diagnostics
==================================
Reference: jlopes7/JGC-IcedTea-Web branch 1.8, inspected 15 October 2026.
Designed for Windows 10/11 and Windows PowerShell 5.1, as the affected normal user.
There is no administrator prompt and no installation or third-party module.
The CMD collector contains an embedded PowerShell payload for property parsing,
hashing, read-only Windows queries and ZIP creation. It does not change execution
policy. Application control or Constrained Language Mode can block it; this is
not bypassed. Run it from a normal CMD window so you can see its final messages.

1. PREPARE LOGGING
------------------
Close existing ITW/Java application sessions before changing settings. Back up
the active deployment.properties. The standard file is:

  %USERPROFILE%\.config\icedtea-web\deployment.properties

With XDG_CONFIG_HOME set, the Java-side location is:

  %XDG_CONFIG_HOME%\icedtea-web\deployment.properties

Important for this fork: the Windows Rust launcher reads its startup properties
from USERPROFILE\.config\icedtea-web even though the Java side supports XDG.
If you deliberately redirect XDG_CONFIG_HOME, put the logging entries in both
existing configurations so early launcher diagnostics are also enabled.
Do not introduce/change XDG variables just to collect logs.

Merge the following keys, replacing any existing values for these same keys:

  deployment.log=true
  deployment.log.headers=true
  deployment.log.file=true
  deployment.log.file.clientapp=true
  deployment.log.stdstreams=true
  deployment.console.startup.mode=SHOW

These enable verbose ITW logs, message headers, file output, separate application
stdout/stderr logging, stream output and the Java console. They do not turn on
every application's own logging system; EBS Forms-specific logs can be separate.
The supplied deployment-diagnostics.properties is a merge snippet, not a complete
replacement configuration. Keep deployment.jre.dir and all existing settings.

The default log directory is:
  %USERPROFILE%\.config\icedtea-web\log
The default resource cache is:
  %USERPROFILE%\.cache\icedtea-web\cache

If deployment.user.logdir is already set, retain its value. An optional custom
value must be an actual writable absolute path in Java .properties syntax:
  deployment.user.logdir=C:/Users/joaol/ITW-EBS-Repro/itw-log
Replace the username as appropriate. Forward slashes avoid backslash escapes.
Do not put %USERPROFILE% into deployment.properties: it is not a CMD file and
does not automatically expand Windows environment variables.

System deployment.config can point to a system deployment.properties, whose
*.locked keys can override/prevent user changes. The collector preserves local
system files and follows local deployment.system.config references. It does not
download remote configuration URLs. If logging does not enable, inspect the
system file/locks and the configuration paths printed in the verbose output.
itweb-settings.exe -info deployment.log deployment.log.file deployment.user.logdir
can also show the effective values and their sources when the runtime starts.

2. ENVIRONMENT AND LAUNCHER OPTIONS
-----------------------------------
The Rust javaws.exe in the inspected fork does NOT consume JAVAWS_OPT,
JAVAWS_OPTS or JAVAWS_OPTIONS. Setting those alone has no effect.

Use -J arguments for javaws.exe, for example:
  "C:\Program Files\IcedTeaWeb\WebStart\bin\javaws.exe" -verbose -J-Ditw.ebs.trace=true "C:\path\launch.jnlp"

The fork's EbsHttpTrace class is gated by the JVM system property itw.ebs.trace.
It emits summarized HTTP headers, response status, redirect/cookie metadata and
applet initialization context through ITW logging. It does not record all HTTP
bodies or every possible network transport. The installed javaws.jar must include
that class and its initialization calls; older packages will ignore the flag.
Look for 'HTTP header tracing enabled; values are summarized' and [EBS-HTTP].

JAVA_TOOL_OPTIONS is read by Java itself. It can carry the custom property into
ITW and child JVMs, including launches that originate in a browser. For a scoped
CMD reproduction:
  set "JAVA_TOOL_OPTIONS=%JAVA_TOOL_OPTIONS% -Ditw.ebs.trace=true"

Preserve existing JVM options. The supplied Launch-ITW-EBS.cmd does this inside
SETLOCAL, so your original environment is restored on return. It also supplies
-J-Ditw.ebs.trace=true explicitly to the initial Rust launcher.

For actual Edge/double-click reproduction, the deployment logging settings
already apply without any new environment variable. If you also need the custom
EBS trace, append -Ditw.ebs.trace=true to JAVA_TOOL_OPTIONS under Windows 'Edit
environment variables for your account' (User variables, not System variables).
Preserve/record the old value. Sign out and sign back in to ensure Explorer and
all Edge background processes inherit it. A SET command in CMD does not change
the environment of an already-running Edge or Explorer process. Remove only
your added diagnostic option afterwards, restoring the previous value.
JAVA_TOOL_OPTIONS affects other Java applications launched from that environment.

ICEDTEAPLUGIN_DEBUG=true is an optional Java-side debug switch; deployment.log=true
and -verbose already cover ordinary verbose output. It is not required here.
JAVAWS_J_OPTIONS belongs to this project's javaws.bat launcher; it is not read
by the Rust javaws.exe. Do not use it to configure the EXE.
Existing JAVA_HOME, ITW_HOME and ICEDTEA_WEB_SPLASH* values need no diagnostic change.

If the failure specifically involves TLS, temporarily use:
  set "ITW_DIAG_SSL=1"
before invoking Launch-ITW-EBS.cmd. This adds -Djavax.net.debug=ssl,handshake to
JAVA_TOOL_OPTIONS in that launcher only. It creates much more output.
  set "ITW_DIAG_SSL="
clears the toggle. Do not disable certificate checks or security checks to log.

3. REPRODUCE AND COLLECT
------------------------
A. Preserve the current cache. Do not clear it or reinstall the package first.
B. Enable logging as above. Save a fresh JNLP from the affected EBS environment.
   Keep the original failing JNLP too. EBS launch files can contain time-limited
   session values; an expired saved JNLP may give a different failure.
C. Reproduce the original launch method (Edge Open File, double-click, etc.).
   For an additional controlled command-line reproduction, run:

  Launch-ITW-EBS.cmd "%USERPROFILE%\Downloads\launch.jnlp" "C:\Program Files\IcedTeaWeb\WebStart"

The console capture goes to %USERPROFILE%\ITW-EBS-Repro. Console redirection alone
is not a replacement for file logging: early launcher failures, app output and
forked Java processes may use different outputs. The wrapper waits for the EXE;
an external child JVM can outlive its initial launcher. Close the Java application
after reproducing, then collect. If it is hung, collect once while it is still
visible and again after closing it to get both live process details and flushed
logs. The collector does not terminate Java or attach a debugger.

D. Run the collector, from the same affected normal Windows account:

  Collect-ITW-EBS.cmd "%USERPROFILE%\Downloads\launch.jnlp" "C:\Program Files\IcedTeaWeb\WebStart" - "%USERPROFILE%\ITW-EBS-Repro"

Use your actual ITW installation folder. The third '-' uses the default output.
Argument order:
  1 = failing local JNLP file (default Downloads\frmservlet), or '-' for automatic discovery only
  2 = ITW installation folder (default C:\Program Files\IcedTeaWeb\WebStart), or '-' for automatic discovery only
  3 = output parent folder, or '-' for the default
  4 = optional extra evidence folder (recursively copied)

When omitted, the first two paths default to:
  JNLP: %USERPROFILE%\Downloads\frmservlet
  ITW:  C:\Program Files\IcedTeaWeb\WebStart
The frmservlet filename has no extension; no .jnlp suffix is added.
Explicit path arguments override these defaults independently. In the collector,
'-' for arguments 1/2 still requests automatic discovery only. In the launcher,
'-' retains the corresponding default.

With those files installed, both scripts can be run without path arguments:
  Launch-ITW-EBS.cmd
  Collect-ITW-EBS.cmd

To include the launch wrapper's console captures using the default JNLP/ITW:
  Collect-ITW-EBS.cmd "%USERPROFILE%\Downloads\frmservlet" "C:\Program Files\IcedTeaWeb\WebStart" - "%USERPROFILE%\ITW-EBS-Repro"

If the default JNLP is missing, the launcher fails with an error. The collector
reports a warning and continues collecting the remaining available evidence.

Default output:
  %USERPROFILE%\ITW-EBS-Diagnostics\ITW-EBS_<computer>_<time>_<id>.zip
The uncompressed folder is retained alongside the ZIP. Allow disk space for
both copies of the collected cache and for ZIP overhead. Large caches can take
several minutes. Nothing is uploaded or sent by either CMD script.

Exit codes: 0 = ZIP created without collector warnings; 2 = partial collection
or ZIP problem; 1 = fatal error. Missing registry keys are recorded and normal.
Review reports\collection.log for skipped paths and copy/configuration errors.

4. INCLUDED EVIDENCE
---------------------
- Current user .config/.cache/legacy ITW data, generated JNLPs, log files,
  resource JARs, native libraries in the cache, .info files, recently_used,
  temporary cache data, and persistence cache.
- Default/XDG and locally referenced custom log, cache, temp and policy paths.
- Local system deployment config/properties, rulesets and trust settings.
- Java security files and server trust stores from discovered runtimes.
- Downloaded JNLPs on Desktop/Downloads/Temp (top-level files only), explicit
  JNLP argument, and shallow JVM hs_err_pid/replay_pid text crash logs.
- Specified extra evidence folder, e.g. manually saved console text, EBS Forms
  logs, screenshots, browser console text or edge://policy export.
- Relevant JNLP extension/ProgID/UserChoice/MIME registrations, Edge policies,
  Internet Settings proxy registry data, Java/ITW registry keys in both views,
  and UniversalSoldier state when readable.
- Java/ITW uninstall metadata, installation configuration, custom customer
  resources, package EXE/JAR/DLL versions and SHA256 hashes; Java -version for
  discovered runtime candidates. Full installed JDK/runtime binaries are not copied.
- Selected process/user/machine Java/ITW environment variables, PATH, OS/time,
  affected user's Java/Edge process paths/command lines, recent Java-related
  Application Error/Windows Error Reporting events, IP/DNS configuration,
  hosts file and WinHTTP proxy settings.
- Source-to-bundle map and SHA256/timestamp/size inventory of copied files.

5. LIMITS / HANDLING
--------------------
This cannot recover console output from before logging was enabled. Arbitrary
EBS Forms/client logs outside the known ITW locations need the extra folder.
It collects workstation data, not EBS server Forms/OHS/WebLogic logs, HTTP HAR,
packet captures, screenshots or live thread dumps automatically. Ask the EBS
team for server logs using the same reproduction timestamp if needed.
If the issue is a hang, a separate thread dump from the matching JDK jstack/jcmd
may be needed; it is intentionally not attempted by this baseline collector.

Source paths may be unavailable/locked under a normal user's permissions; the
collector records the problem and continues. Files can change during collection,
so the result is not an atomic snapshot. Reparse-point directories/files are
skipped to avoid following junctions/symlinks outside the selected tree.
Remote system-properties URLs are only recorded. Multiple raw configuration
files are preserved; custom-path discovery does not attempt to reproduce ITW's
full precedence/locked-property rules. Nonstandard user.home/java.io.tmpdir
overrides may require explicitly collecting the real folder as argument 4.

Known potential private-key/client certificate filenames (.pfx/.p12/.jks/
.keystore/.key and clientcert/clientauth names) are skipped. This is NOT a
complete redaction process: JNLPs, config files, cache metadata, application logs,
process arguments and proxy URLs can contain credentials or EBS session tokens.
Review the ZIP before sharing; treat it as confidential support material.
Browser history/cookie databases, private-key exports and memory dumps are not
collected. No cache/configuration/registry cleanup is performed.

After testing, restore the saved deployment.properties and any user environment
values changed for the reproduction. Keep the diagnostic archive until the
issue is resolved. The collector/launcher do not require recompiling ITW.

Validation: PowerShell payload syntax and helper behavior were checked on Linux
PowerShell. The CMD entry points, Windows registry/CIM access and actual Windows
Rust launcher have not been executed in this environment; validate on one pilot
Windows user account before distributing more widely.

Reference sources:
https://github.com/jlopes7/JGC-IcedTea-Web/tree/1.8
https://github.com/jlopes7/JGC-IcedTea-Web/blob/1.8/rust-launcher/src/main.rs
https://github.com/jlopes7/JGC-IcedTea-Web/blob/1.8/netx/net/sourceforge/jnlp/runtime/EbsHttpTrace.java
https://icedtea.classpath.org/download/icedtea-web-docs/1.8/html/en/itweb-settings.html
https://docs.azul.com/core/icedteaweb/configuration
