package net.sourceforge.jnlp.util.logging;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.net.HttpURLConnection;
import java.net.URL;
import net.sourceforge.jnlp.runtime.JNLPRuntime;
import net.sourceforge.jnlp.util.HttpUtils;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;

public class OptionalResourceLogTest {
    private PrintStream oldOut;
    private PrintStream oldErr;
    private boolean oldDebug, oldHeaders, oldStreams, oldFile, oldSystem;
    private ByteArrayOutputStream bytes;

    @Before
    public void captureLogging() throws Exception {
        OutputController logger = OutputController.getLogger();
        logger.flush();
        oldOut = logger.getOut();
        oldErr = logger.getErr();
        oldDebug = JNLPRuntime.isDebug();
        JNLPRuntime.setDebug(true);
        LogConfig config = LogConfig.getLogConfig();
        oldHeaders = config.isEnableHeaders();
        oldStreams = config.isLogToStreams();
        oldFile = config.isLogToFile();
        oldSystem = config.isLogToSysLog();
        config.setEnableHeaders(true);
        config.setLogToStreams(true);
        config.setLogToFile(false);
        config.setLogToSysLog(false);
        bytes = new ByteArrayOutputStream();
        logger.setOut(new PrintStream(bytes, true, "UTF-8"));
        logger.setErr(new PrintStream(bytes, true, "UTF-8"));
    }

    @After
    public void restoreLogging() {
        OutputController logger = OutputController.getLogger();
        logger.flush();
        logger.setOut(oldOut);
        logger.setErr(oldErr);
        LogConfig config = LogConfig.getLogConfig();
        config.setEnableHeaders(oldHeaders);
        config.setLogToStreams(oldStreams);
        config.setLogToFile(oldFile);
        config.setLogToSysLog(oldSystem);
        JNLPRuntime.setDebug(oldDebug);
    }

    private String output() throws Exception {
        OutputController.getLogger().flush();
        return bytes.toString("UTF-8");
    }

    @Test
    public void requiredResourcesAreNotClassifiedAsOptional() throws Exception {
        assertFalse(OptionalResourceLog.isOptionalResource(null));
        assertFalse(OptionalResourceLog.isOptionalResource(new URL("https://example.test/app.jar")));
        assertFalse(OptionalResourceLog.isOptionalResource(new URL("https://example.test/app.png")));
        assertFalse(OptionalResourceLog.isOptionalResource(new URL("https://example.test/favicon.ico.jar")));
        assertFalse(OptionalResourceLog.isFormsBritishEnglishBundle("oracle.forms.engine.Main"));
        assertFalse(OptionalResourceLog.logIfOptionalResourceFailure(new URL("https://example.test/app.jar"), "HTTP 404"));
        assertEquals("", output());
    }

    @Test
    public void iconWarningsOmitStackTracesAndQueryCredentials() throws Exception {
        OptionalResourceLog.logIconFailure(new IOException("private detail"));
        assertTrue(OptionalResourceLog.logIfOptionalResourceFailure(
                new URL("https://example.test/favicon.ico?session=secret"), "HTTP 404"));
        String text = output();
        assertTrue(text.contains("[WARNING_ALL]"));
        assertTrue(text.contains("using the default icon"));
        assertFalse(text.contains("[ERROR"));
        assertFalse(text.contains("private detail"));
        assertFalse(text.contains("session=secret"));
        assertFalse(text.contains("\tat "));
    }

    @Test
    public void formsLocaleWarningIsNarrowAndHasNoStackTrace() throws Exception {
        assertTrue(OptionalResourceLog.isFormsBritishEnglishBundle("oracle.forms.engine.RunformBundle_en_GB"));
        assertTrue(OptionalResourceLog.isOptionalResource(new URL("https://example.test/OA_JAVA/oracle/forms/engine/RunformBundle_en_GB.properties")));
        assertFalse(OptionalResourceLog.isOptionalResource(new URL("https://example.test/OA_JAVA/oracle/forms/engine/Main.class")));
        OptionalResourceLog.logFormsBritishEnglishBundleMissing();
        String text = output();
        assertTrue(text.contains("[WARNING_ALL]"));
        assertTrue(text.contains("ResourceBundle fallback"));
        assertFalse(text.contains("[ERROR"));
        assertFalse(text.contains("\tat "));
    }

    private HttpURLConnection failedConnection(String path) throws Exception {
        return new HttpURLConnection(new URL("https://example.test/" + path)) {
            @Override public void disconnect() { }
            @Override public boolean usingProxy() { return false; }
            @Override public void connect() { }
            @Override public InputStream getInputStream() throws IOException {
                throw new IOException("Expected test failure");
            }
        };
    }

    @Test
    public void faviconCleanupFailureIsAWarningWithoutStackTrace() throws Exception {
        HttpUtils.consumeAndCloseConnectionSilently(failedConnection("favicon.ico"));
        String text = output();
        assertTrue(text.contains("[WARNING_ALL]"));
        assertFalse(text.contains("[ERROR"));
        assertFalse(text.contains("\tat "));
    }

    @Test
    public void requiredResourceCleanupKeepsOriginalExceptionLogging() throws Exception {
        HttpUtils.consumeAndCloseConnectionSilently(failedConnection("required.jar"));
        String text = output();
        assertTrue(text.contains("[ERROR_DEBUG]"));
        assertTrue(text.contains("java.io.IOException: Expected test failure"));
        assertTrue(text.contains("\tat "));
    }
}
