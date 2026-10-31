package com.baz.djmusi.engine;

/** Stereo biquad filter (RBJ cookbook), used for the EQ and the DJ filter. */
final class Biquad {
    private double b0 = 1, b1, b2, a1, a2;
    private final double[] z1 = new double[2], z2 = new double[2];

    void lowShelf(double fs, double f, double db) { shelf(fs, f, db, true); }
    void highShelf(double fs, double f, double db) { shelf(fs, f, db, false); }

    void peak(double fs, double f, double q, double db) {
        double A = Math.pow(10, db / 40), w = 2 * Math.PI * f / fs, alpha = Math.sin(w) / (2 * q);
        double cos = Math.cos(w), a0 = 1 + alpha / A;
        set((1 + alpha * A) / a0, -2 * cos / a0, (1 - alpha * A) / a0, -2 * cos / a0, (1 - alpha / A) / a0);
    }

    void lowPass(double fs, double f, double q) {
        double w = 2 * Math.PI * f / fs, alpha = Math.sin(w) / (2 * q), cos = Math.cos(w), a0 = 1 + alpha;
        set((1 - cos) / 2 / a0, (1 - cos) / a0, (1 - cos) / 2 / a0, -2 * cos / a0, (1 - alpha) / a0);
    }

    void highPass(double fs, double f, double q) {
        double w = 2 * Math.PI * f / fs, alpha = Math.sin(w) / (2 * q), cos = Math.cos(w), a0 = 1 + alpha;
        set((1 + cos) / 2 / a0, -(1 + cos) / a0, (1 + cos) / 2 / a0, -2 * cos / a0, (1 - alpha) / a0);
    }

    private void shelf(double fs, double f, double db, boolean low) {
        double A = Math.pow(10, db / 40), w = 2 * Math.PI * f / fs, cos = Math.cos(w);
        double alpha = Math.sin(w) / 2 * Math.sqrt(2), sq = 2 * Math.sqrt(A) * alpha;
        double s = low ? 1 : -1;
        double a0 = (A + 1) + s * (A - 1) * cos + sq;
        set(A * ((A + 1) - s * (A - 1) * cos + sq) / a0,
            s * 2 * A * ((A - 1) - s * (A + 1) * cos) / a0,
            A * ((A + 1) - s * (A - 1) * cos - sq) / a0,
            -s * 2 * ((A - 1) + s * (A + 1) * cos) / a0,
            ((A + 1) + s * (A - 1) * cos - sq) / a0);
    }

    private void set(double nb0, double nb1, double nb2, double na1, double na2) {
        b0 = nb0; b1 = nb1; b2 = nb2; a1 = na1; a2 = na2;
    }

    /** Transposed direct form II; ch = 0 (left) or 1 (right). */
    float process(float x, int ch) {
        double y = b0 * x + z1[ch];
        z1[ch] = b1 * x - a1 * y + z2[ch];
        z2[ch] = b2 * x - a2 * y;
        return (float) y;
    }
}
