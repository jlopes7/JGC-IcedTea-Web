package net.sourceforge.jnlp.runtime;

import java.net.CookieHandler;
import java.net.CookieManager;
import java.net.HttpCookie;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.logging.Handler;
import java.util.logging.Level;
import java.util.logging.LogRecord;
import java.util.logging.Logger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import net.sourceforge.jnlp.util.logging.OutputController;

public final class EbsHttpTrace extends Handler {

    private static final boolean ENABLED =
            Boolean.getBoolean("itw.ebs.trace");

    private static final Pattern PAIR =
            Pattern.compile("\\{([^{}]*)\\}");

    private static final Pattern REQUEST = Pattern.compile(
            "^(GET|POST|HEAD|PUT|DELETE|OPTIONS|CONNECT) (.+) HTTP/\\d\\.\\d$");

    // Keep the JUL logger strongly reachable.
    private static Logger httpLogger;

    public static synchronized void install() {
        if (!ENABLED || httpLogger != null) {
            return;
        }

        try {
            Logger logger = Logger.getLogger(
                    "sun.net.www.protocol.http.HttpURLConnection");

            // Do not enable raw records on an existing handler.
            if (logger.getHandlers().length != 0) {
                write("HTTP tracing skipped: this logger already has a handler");
                return;
            }

            logger.setUseParentHandlers(false);
            logger.addHandler(new EbsHttpTrace());
            logger.setLevel(Level.FINE);
            httpLogger = logger;

            write("HTTP header tracing enabled; values are summarized");
        } catch (RuntimeException e) {
            write("HTTP tracing unavailable: "
                    + e.getClass().getSimpleName());
        }
    }

    public static void state(String phase, String codeBase,
                             String documentBase, String serverURL) {

        if (!ENABLED) {
            return;
        }

        try {
            write(phase
                    + " codeBase=" + url(codeBase)
                    + " documentBase=" + url(documentBase)
                    + " serverURL=" + url(serverURL)
                    + " controls=" + controls(serverURL));

            CookieHandler handler = CookieHandler.getDefault();

            write(phase + " cookieHandler="
                    + (handler == null
                    ? "null" : handler.getClass().getName()));

            if (handler instanceof CookieManager) {
                CookieManager manager = (CookieManager) handler;

                write(phase + " storedCookies="
                        + manager.getCookieStore().getCookies().size());

                for (HttpCookie c : manager.getCookieStore().getCookies()) {
                    write(phase + " stored " + cookie(c));
                }
            }
        } catch (RuntimeException e) {
            write(phase + " snapshot unavailable: "
                    + e.getClass().getSimpleName());
        }
    }

    @Override
    public void publish(LogRecord record) {
        if (!isLoggable(record)
                || record.getMessage() == null
                || !record.getMessage().startsWith(
                "sun.net.www.MessageHeader")) {
            return;
        }

        // Whitelist fields; never emit the raw record or exception.
        try {
            StringBuilder result = new StringBuilder();
            boolean requestSeen = false;
            boolean cookieSeen = false;
            Matcher pairs = PAIR.matcher(record.getMessage());

            while (pairs.find()) {
                String pair = pairs.group(1);
                int colon = pair.indexOf(": ");

                if (colon < 0) {
                    continue;
                }

                String name = pair.substring(0, colon);
                String value = pair.substring(colon + 2);
                Matcher request = REQUEST.matcher(name);

                if (request.matches()) {
                    requestSeen = true;
                    result.append("request ")
                            .append(request.group(1))
                            .append(' ')
                            .append(url(request.group(2)));

                } else if ("null".equals(name)
                        && value.startsWith("HTTP/")) {

                    String[] status = value.split(" ", 3);
                    result.append("response status=")
                            .append(status.length > 1
                                    ? text(status[1]) : "unknown");

                } else if ("Content-Type".equalsIgnoreCase(name)
                        || "Content-Length".equalsIgnoreCase(name)
                        || "Host".equalsIgnoreCase(name)) {

                    result.append(' ').append(text(name))
                            .append('=').append(text(value));

                } else if ("Location".equalsIgnoreCase(name)) {
                    result.append(" Location=").append(url(value));

                } else if ("Set-Cookie".equalsIgnoreCase(name)
                        || "Set-Cookie2".equalsIgnoreCase(name)) {

                    try {
                        for (HttpCookie c : HttpCookie.parse(value)) {
                            result.append(" receivedCookie=[")
                                    .append(cookie(c)).append(']');
                        }
                    } catch (IllegalArgumentException e) {
                        result.append(" receivedCookie=[unparseable]");
                    }

                } else if ("Cookie".equalsIgnoreCase(name)
                        || "Cookie2".equalsIgnoreCase(name)) {

                    cookieSeen = true;

                    for (String part : value.split(";")) {
                        int equals = part.indexOf('=');

                        if (equals > 0
                                && !part.trim().startsWith("$")) {
                            result.append(" sentCookie=[")
                                    .append(text(part.substring(
                                            0, equals).trim()))
                                    .append('=')
                                    .append(summary(part.substring(
                                            equals + 1).trim()))
                                    .append(']');
                        }
                    }
                }
            }

            if (requestSeen && !cookieSeen) {
                result.append(" sentCookie=[none]");
            }

            if (result.length() != 0) {
                write(result.toString());
            }
        } catch (RuntimeException e) {
            write("header summary unavailable: "
                    + e.getClass().getSimpleName());
        }
    }

    private static String cookie(HttpCookie c) {
        return text(c.getName()) + "=" + summary(c.getValue())
                + " domain=" + text(c.getDomain())
                + " path=" + text(c.getPath())
                + " secure=" + c.getSecure()
                + " maxAge=" + c.getMaxAge()
                + " expired=" + c.hasExpired();
    }

    private static String url(String value) {
        if (value == null) {
            return "null";
        }

        try {
            URI uri = new URI(value);
            String path = uri.getRawPath();

            // Suppress path parameters such as ;jsessionid=...
            path = path == null ? ""
                    : path.replaceAll(";[^/]*", ";<redacted>");

            StringBuilder out = new StringBuilder();

            if (uri.getHost() != null) {
                out.append(uri.getScheme())
                        .append("://").append(uri.getHost());

                if (uri.getPort() != -1) {
                    out.append(':').append(uri.getPort());
                }
            }

            out.append(text(path));

            if (uri.getRawQuery() != null) {
                out.append('?');
                String delimiter = "";

                for (String parameter
                        : uri.getRawQuery().split("&", -1)) {

                    int equals = parameter.indexOf('=');
                    String name = equals < 0 ? "<unnamed>"
                            : parameter.substring(0, equals);
                    String val = equals < 0 ? parameter
                            : parameter.substring(equals + 1);

                    out.append(delimiter)
                            .append(text(name)).append('=');

                    if ("ifcmd".equals(name)
                            && ("startsession".equals(val)
                            || "getinfo".equals(val))) {
                        out.append(val);
                    } else {
                        out.append(summary(val));
                    }

                    delimiter = "&";
                }
            }

            return out.toString();
        } catch (Exception e) {
            return "<invalid URI " + summary(value) + ">";
        }
    }

    private static String summary(String value) {
        if (value == null) {
            return "null";
        }

        if (value.length() >= 2
                && value.startsWith("\"")
                && value.endsWith("\"")) {
            value = value.substring(1, value.length() - 1);
        }

        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));

            StringBuilder id = new StringBuilder();

            for (int i = 0; i < 6; i++) {
                id.append(String.format("%02x", digest[i] & 0xff));
            }

            return "<len=" + value.length()
                    + ",sha256=" + id + ">";
        } catch (Exception e) {
            return "<len=" + value.length() + ">";
        }
    }

    private static int controls(String value) {
        int count = 0;

        if (value != null) {
            for (int i = 0; i < value.length(); i++) {
                if (Character.isISOControl(value.charAt(i))) {
                    count++;
                }
            }
        }

        return count;
    }

    private static String text(String value) {
        return value == null ? "null"
                : value.replaceAll("[\\p{Cntrl}]", "?");
    }

    private static void write(String message) {
        OutputController.getLogger().log(
                OutputController.Level.MESSAGE_ALL,
                "[EBS-HTTP] time=" + System.currentTimeMillis()
                        + " thread=" + Thread.currentThread().getId()
                        + " " + message);
    }

    @Override
    public void flush() {
    }

    @Override
    public void close() {
    }
}