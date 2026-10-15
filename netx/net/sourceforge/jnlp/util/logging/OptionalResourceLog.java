package net.sourceforge.jnlp.util.logging;

import java.net.URL;

/**
 * Logging for optional shortcut icons and the known Oracle Forms locale probe.
 */
public final class OptionalResourceLog {

    private static final String FORMS_GB_BUNDLE = "oracle.forms.engine.RunformBundle_en_GB";

    private static final String FORMS_GB_PATH = "/oracle/forms/engine/RunformBundle_en_GB";

    private OptionalResourceLog() {
    }

    public static boolean isFormsBritishEnglishBundle(String name) {
        return FORMS_GB_BUNDLE.equals(name);
    }

    public static boolean isOptionalResource(URL location) {
        if (location == null) {
            return false;
        }

        String path = location.getPath();

        return path.endsWith("/favicon.ico")
                || path.endsWith(FORMS_GB_PATH + ".class")
                || path.endsWith(FORMS_GB_PATH + ".properties");
    }

    /**
     * Returns true when the optional failure was logged without a stack trace.
     */
    public static boolean logIfOptionalResourceFailure(URL location, String detail) {

        if (!isOptionalResource(location)) {
            return false;
        }

        // Exclude query strings that might contain session credentials.
        OutputController.getLogger().log(
                OutputController.Level.WARNING_ALL,
                "Optional resource " + location.getPath()
                        + " unavailable: " + detail);

        return true;
    }

    public static void logIconFailure(Throwable cause) {
        OutputController.getLogger().log(
                OutputController.Level.WARNING_ALL,
                "Application icon unavailable ("
                        + cause.getClass().getSimpleName()
                        + "); using the default icon.");
    }

    public static void logFormsBritishEnglishBundleMissing() {
        OutputController.getLogger().log(
                OutputController.Level.WARNING_ALL,
                "Optional Oracle Forms locale bundle "
                        + FORMS_GB_BUNDLE
                        + " not found; Java ResourceBundle fallback"
                        + " will select an available bundle.");
    }
}