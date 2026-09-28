/* SplashUtils.java
Copyright (C) 2012 Red Hat, Inc.

This file is part of IcedTea.

IcedTea is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

IcedTea is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with IcedTea; see the file COPYING.  If not, write to the
Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA.

Linking this library statically or dynamically with other modules is
making a combined work based on this library.  Thus, the terms and
conditions of the GNU General Public License cover the whole
combination.

As a special exception, the copyright holders of this library give you
permission to link this library with independent modules to produce an
executable, regardless of the license terms of these independent
modules, and to copy and distribute the resulting executable under
terms of your choice, provided that you also meet, for each linked
independent module, the terms and conditions of the license of that
module.  An independent module is a module which is not derived from
or based on this library.  If you modify this library, you may extend
this exception to your version of the library, but you are not
obligated to do so.  If you do not wish to do so, delete this
exception statement from your version. */
package net.sourceforge.jnlp.splashscreen;

import net.sourceforge.jnlp.runtime.AppletEnvironment;
import net.sourceforge.jnlp.runtime.AppletInstance;
import net.sourceforge.jnlp.runtime.Boot;
import net.sourceforge.jnlp.runtime.JNLPRuntime;
import net.sourceforge.jnlp.splashscreen.impls.DefaultSplashScreen2012;
import net.sourceforge.jnlp.splashscreen.impls.DefaultErrorSplashScreen2012;
import net.sourceforge.jnlp.util.logging.OutputController;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.Iterator;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;

import net.sourceforge.jnlp.splashscreen.impls.CustomSplashScreen;

public class SplashUtils {

    static final String ICEDTEA_WEB_PLUGIN_SPLASH = "ICEDTEA_WEB_PLUGIN_SPLASH";
    static final String ICEDTEA_WEB_SPLASH = "ICEDTEA_WEB_SPLASH";
    static final String ICEDTEA_WEB_SPLASH_CUSTOM_IMG = "ICEDTEA_WEB_SPLASH_CUSTOM_IMG";

    static final String NONE = "none";
    static final String DEFAULT = "default";
    static final String CUSTOM = "custom";

    /**
     * Indicator whether to show icedtea-web plugin or just icedtea-web
     * For "just icedtea-web" will be done an attempt to show content of
     * information element 
     */
    public static enum SplashReason {

        APPLET, JAVAWS;

        @Override
        public String toString() {
            switch (this) {
                case APPLET:
                    return "IcedTea-Web Plugin";
                case JAVAWS:
                    return "IcedTea-Web";
            }
            return "unknown";
        }
    }

    public static void showErrorCaught(Throwable ex, AppletInstance appletInstance) {
        try {
            showError(ex, appletInstance);
        } catch (Throwable t) {
                // prinitng this exception is discutable. I have let it in for case that
                //some retyping will fail
                OutputController.getLogger().log(t);
        }
    }

    public static void showError(Throwable ex, AppletInstance appletInstance) {
        if (appletInstance == null) {
            return;
        }
        AppletEnvironment ae = appletInstance.getAppletEnvironment();
        showError(ex, ae);
    }

    public static void showError(Throwable ex, AppletEnvironment ae) {
        if (ae == null) {
            return;
        }
        SplashController p = ae.getSplashController();
        showError(ex, p);
    }

    public static void showError(Throwable ex, SplashController f) {
        if (f == null) {
            return;
        }

        f.replaceSplash(getErrorSplashScreen(f.getSplashWidth(), f.getSplashHeigth(), ex));
    }

    
    private static SplashReason getReason() {
        if (JNLPRuntime.isWebstartApplication()) {
            return SplashReason.JAVAWS;
        } else {
            return SplashReason.APPLET;
        }        
    }
    

    /**
     * Warning - splash should have recieve width and height without borders.
     * plugin's window have NO border, but javaws window HAVE border. This must 
     * be calcualted prior calling this method
     * @param width
     * @param height
     */
    public static SplashPanel getSplashScreen(int width, int height) {
        return getSplashScreen(width, height, getReason());
    }

    /**
     * Warning - splash should have recieve width and height without borders.
     * plugin's window have NO border, but javaws window HAVE border. This must
     * be calcualted prior calling this method
     * @param width
     * @param height
     * @param ex exception to be shown if any
     */
    public static SplashErrorPanel getErrorSplashScreen(int width, int height, Throwable ex) {
        return getErrorSplashScreen(width, height, getReason(), ex);
    }

    /**
     * Warning - splash should have recieve width and height without borders.
     * plugin's window have NO border, but javaws window HAVE border. This must
     * be calcualted prior calling this method
     * @param width
     * @param height
     * @param splashReason
     */
    static SplashPanel getSplashScreen(int width, int height, SplashUtils.SplashReason splashReason) {
        return getSplashScreen(width, height, splashReason, null, false);
    }

    /**
     * Warning - splash should have recieve width and height without borders.
     * plugin's window have NO border, but javaws window HAVE border. This must
     * be calcualted prior calling this method
     * @param width
     * @param height
     * @param splashReason
     * @param ex exception to be shown if any
     */
    static SplashErrorPanel getErrorSplashScreen(int width, int height, SplashUtils.SplashReason splashReason, Throwable ex) {
        return (SplashErrorPanel) getSplashScreen(width, height, splashReason, ex, true);
    }

    /**
     * @param width
     * @param height
     * @param splashReason
     * @param loadingException
     * @param isError
     */
    public static SplashPanel getSplashScreen(int width, int height, SplashUtils.SplashReason splashReason, Throwable loadingException, boolean isError) {
        String mode = getSplashMode(splashReason);

        String imagePath = CUSTOM.equals(mode) && !isError
                ? getEnvironmentVariable(ICEDTEA_WEB_SPLASH_CUSTOM_IMG)
                : null;

        return getSplashScreen(
                width,
                height,
                splashReason,
                loadingException,
                isError,
                mode,
                imagePath);
    }

    /**
     * Whether the environment requests a custom splash instead of
     * the splash image specified by the JNLP file.
     */
    public static boolean isCustomSplashRequested() {
        return CUSTOM.equals(getSplashMode(getReason()));
    }

    private static String getSplashMode(SplashReason reason) {
        return getEnvironmentVariable(
                SplashReason.JAVAWS.equals(reason)
                        ? ICEDTEA_WEB_SPLASH
                        : ICEDTEA_WEB_PLUGIN_SPLASH);
    }

    private static String getEnvironmentVariable(String name) {
        try {
            return System.getenv(name);
        } 
        catch (SecurityException ex) {
            OutputController.getLogger().log(OutputController.Level.ERROR_ALL, ex);

            return null;
        }
    }

    /**
     * Selects the splash using explicit configuration values.
     * This also allows testing without modifying process environment variables.
     */
    static SplashPanel getSplashScreen(int width, int height, SplashReason reason, Throwable loadingException, boolean isError, String mode, String imagePath) {
        SplashPanel splash = null;

        if (NONE.equals(mode)) {
            return null;
        }

        if (CUSTOM.equals(mode) && !isError) {
            BufferedImage image = loadCustomImage(imagePath);

            if (image != null) {
                splash = new CustomSplashScreen(width, height, reason, image);
            }
        }

        // Relays on the default splash screen!
        if (splash == null) {
            if (isError) {
                // Preserve the existing error details and diagnostic controls.
                splash = new DefaultErrorSplashScreen2012(width, height, reason, loadingException);
            } 
            else {
                splash = new DefaultSplashScreen2012(width, height, reason);
            }
        }

        splash.setVersion(Boot.version);
        return splash;
    }

    /**
     * Loads a local PNG, returning null when it cannot be used.
     */
    private static BufferedImage loadCustomImage(String path) {
        if (path == null || path.trim().isEmpty()) {
            return null;
        }

        try {
            File file = new File(path);

            if (!file.isFile() || !file.canRead()) {
                throw new IOException(String.format("Custom splash image is not a readable file: %s", path));
            }

            try (ImageInputStream input = ImageIO.createImageInputStream(file)) {
                if (input == null) {
                    throw new IOException(String.format("Cannot open custom splash image: %s", path));
                }

                Iterator<ImageReader> readers = ImageIO.getImageReaders(input);

                if (!readers.hasNext()) {
                    throw new IOException(String.format("Invalid custom splash image: %s", path));
                }

                ImageReader reader = readers.next();
                try {
                    // Validate the actual format, not just the filename extension.
                    if (!"png".equalsIgnoreCase(reader.getFormatName())) {
                        throw new IOException(String.format("Custom splash image must be a PNG: %s", path));
                    }

                    reader.setInput(input);
                    return reader.read(0);
                } 
                finally {
                    reader.dispose();
                }
            }
        } 
        catch (IOException | RuntimeException ex) {
            OutputController.getLogger().log(OutputController.Level.ERROR_ALL, ex);

            return null;
        }
    }
}
