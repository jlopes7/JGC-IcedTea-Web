package net.sourceforge.jnlp.splashscreen.impls;

import java.awt.Color;
import java.awt.Dimension;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.event.ComponentAdapter;
import java.awt.event.ComponentEvent;
import java.awt.image.BufferedImage;

import net.sourceforge.jnlp.splashscreen.SplashUtils.SplashReason;
import net.sourceforge.jnlp.splashscreen.parts.BasicComponentSplashScreen;

/**
 * A static PNG splash without branding, text or progress overlays.
 */
public final class CustomSplashScreen extends BasicComponentSplashScreen {

    static public final int MAX_WIDTH = 720;
    static public final int MAX_HEIGHT = (int) (MAX_WIDTH * net.sourceforge.jnlp.splashscreen.SplashUtils.ASPECT_RATIO);

    private final BufferedImage image;
    private int percentage;

    public CustomSplashScreen(
            int width,
            int height,
            SplashReason reason,
            BufferedImage image) {

        this.image = image;

        // Ensure background is transparent or matches the image top background
        setOpaque(false);
        setBackground(new Color(0, 0, 0, 0));

        // These limits have already been calculated by SplashUtils.
        int maxWidth = Math.max(1, width);
        int maxHeight = Math.max(1, height);

        int targetWidth = image != null ? image.getWidth() : maxWidth;
        int targetHeight = image != null ? image.getHeight() : maxHeight;

        // Scale down to fit both limits, preserving the image's aspect ratio.
        // A smaller image stays at its original size.
        double scale = Math.min(1.0, Math.min((double) maxWidth / targetWidth, (double) maxHeight / targetHeight));

        targetWidth = Math.max(1, (int) Math.round(targetWidth * scale));
        targetHeight = Math.max(1, (int) Math.round(targetHeight * scale));

        setSplashWidth(targetWidth);
        setSplashHeight(targetHeight);
        setSplashReason(reason);

        Dimension size = new Dimension(targetWidth, targetHeight);
        setPreferredSize(size);
        setMinimumSize(size);

        addComponentListener(new ComponentAdapter() {
            @Override
            public void componentResized(ComponentEvent event) {
                setSplashWidth(getWidth());
                setSplashHeight(getHeight());
                adjustForSize();
            }
        });
    }

    @Override
    public Dimension getPreferredSize() {
        return new Dimension(getSplashWidth(), getSplashHeight());
    }

    @Override
    public Dimension getMinimumSize() {
        return getPreferredSize();
    }

    @Override
    protected void paintComponent(Graphics g) {
        super.paintComponent(g);
        paintTo(g);
    }

    @Override
    public void paintTo(Graphics g) {
        if (image == null) {
            return;
        }

        int width = getWidth() > 0 ? getWidth() : getSplashWidth();
        int height = getHeight() > 0 ? getHeight() : getSplashHeight();

        if (width <= 0 || height <= 0) {
            return;
        }

        Graphics2D graphics = (Graphics2D) g.create();

        try {
            graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            // OPTION 1: Exact flush stretch to panel bounds (eliminates any borders entirely)
            graphics.drawImage(image, 0, 0, width, height, null);

            /* OPTION 2: If strict aspect-ratio preservation is required, uncomment this:
            double scale = Math.min((double) width / image.getWidth(), (double) height / image.getHeight());
            int imageWidth = Math.max(1, (int) Math.round(image.getWidth() * scale));
            int imageHeight = Math.max(1, (int) Math.round(image.getHeight() * scale));
            int x = (width - imageWidth) / 2;
            int y = (height - imageHeight) / 2;
            graphics.drawImage(image, x, y, imageWidth, imageHeight, null);
            */
        } 
        finally {
            graphics.dispose();
        }
    }

    @Override
    public void adjustForSize() {
        repaint();
    }

    @Override
    public void startAnimation() {
        // A static image does not need an animation thread.
        // TODO: Maybe work something here in the future
    }

    @Override
    public void stopAnimation() {
        // No animation thread is running.
        // TODO: Maybe work something here in the future
    }

    @Override
    public void setPercentage(int done) {
        percentage = done;
    }

    @Override
    public int getPercentage() {
        return percentage;
    }
}
