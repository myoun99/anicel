//! The pitch analysis RNNoise filters its harmonics by — opus's
//! `pitch.c` and `celt_lpc.c` (float build), for the one buffer it is
//! asked of: 1728 samples down to 864.
//!
//! The arithmetic is the C's, in the C's order: a sum runs from its first
//! term to its last, and where the C rounds through double (`sqrt` of a
//! float sum) this does too. `max`/`min` are the C's macros — the first
//! when it compares greater — never `f32::max`, which answers NaN and -0
//! another way.

pub(crate) const MAX_PERIOD: usize = 768;
pub(crate) const MIN_PERIOD: usize = 60;
pub(crate) const FRAME: usize = 960;
pub(crate) const BUF: usize = MAX_PERIOD + FRAME;

/// arch.h's MAX16/MAX32 on floats.
pub(crate) fn max(a: f32, b: f32) -> f32 {
    if a > b { a } else { b }
}

/// arch.h's MIN16/MIN32 on floats.
pub(crate) fn min(a: f32, b: f32) -> f32 {
    if a < b { a } else { b }
}

fn inner_prod(x: &[f32], y: &[f32], n: usize) -> f32 {
    let mut xy = 0.0;
    for (a, b) in x[..n].iter().zip(&y[..n]) {
        xy += a * b;
    }
    xy
}

/// `rnn_pitch_xcorr`: `xcorr[i]` = x · y[i..] over `len`, for each lag.
///
/// The C unrolls four lags at a time (`xcorr_kernel`), each lag's sum
/// still running from its first term to its last — what one inner
/// product does, which is why four interleaved here are the same bits.
fn pitch_xcorr(x: &[f32], y: &[f32], xcorr: &mut [f32], len: usize, max_pitch: usize) {
    let mut i = 0;
    while i + 4 <= max_pitch {
        let mut sum = [0.0f32; 4];
        for (j, &t) in x[..len].iter().enumerate() {
            sum[0] += t * y[i + j];
            sum[1] += t * y[i + j + 1];
            sum[2] += t * y[i + j + 2];
            sum[3] += t * y[i + j + 3];
        }
        xcorr[i..i + 4].copy_from_slice(&sum);
        i += 4;
    }
    for at in i..max_pitch {
        xcorr[at] = inner_prod(x, &y[at..], len);
    }
}

/// `rnn_autocorr` with no window: `lag` + 1 values over `x`.
fn autocorr(x: &[f32], lag: usize) -> [f32; 5] {
    let n = x.len();
    let fast_n = n - lag;
    let mut ac = [0.0; 5];
    pitch_xcorr(x, x, &mut ac, fast_n, lag + 1);
    for (k, value) in ac.iter_mut().enumerate().take(lag + 1) {
        let mut d = 0.0;
        for i in k + fast_n..n {
            d += x[i] * x[i - k];
        }
        *value += d;
    }
    ac
}

/// `rnn_lpc`: four LPC coefficients from five autocorrelations.
fn lpc(ac: &[f32; 5]) -> [f32; 4] {
    let mut lpc = [0.0f32; 4];
    let mut error = ac[0];
    if ac[0] == 0.0 {
        return lpc;
    }
    for i in 0..4 {
        let mut rr = 0.0f32;
        for j in 0..i {
            rr += lpc[j] * ac[i - j];
        }
        rr += ac[i + 1];
        let r = -rr / error;
        lpc[i] = r;
        for j in 0..(i + 1) >> 1 {
            let tmp1 = lpc[j];
            let tmp2 = lpc[i - 1 - j];
            lpc[j] = tmp1 + r * tmp2;
            lpc[i - 1 - j] = tmp2 + r * tmp1;
        }
        error -= (r * r) * error;
        // Bail out once the prediction has bought 30 dB.
        if error < 0.001 * ac[0] {
            break;
        }
    }
    lpc
}

/// `celt_fir5`, in place, from a zero memory.
fn fir5(x: &mut [f32], num: &[f32; 5]) {
    let mut mem = [0.0f32; 5];
    for value in x.iter_mut() {
        let xi = *value;
        let mut sum = xi;
        for (n, m) in num.iter().zip(&mem) {
            sum += n * m;
        }
        mem = [xi, mem[0], mem[1], mem[2], mem[3]];
        *value = sum;
    }
}

/// `rnn_pitch_downsample` of one channel: [`BUF`] samples to half as
/// many, whitened by a fourth-order LPC.
pub(crate) fn downsample(x: &[f32; BUF]) -> [f32; BUF / 2] {
    let mut x_lp = [0.0f32; BUF / 2];
    for i in 1..BUF / 2 {
        x_lp[i] = 0.5 * (0.5 * (x[2 * i - 1] + x[2 * i + 1]) + x[2 * i]);
    }
    x_lp[0] = 0.5 * (0.5 * x[1] + x[0]);
    let mut ac = autocorr(&x_lp, 4);
    ac[0] *= 1.0001;
    for (i, value) in ac.iter_mut().enumerate().skip(1) {
        let lag = 0.008 * i as f32;
        *value -= *value * lag * lag;
    }
    let mut lpc = lpc(&ac);
    let mut tmp = 1.0f32;
    for value in &mut lpc {
        tmp *= 0.9;
        *value *= tmp;
    }
    let c1 = 0.8f32;
    let lpc2 = [lpc[0] + 0.8, lpc[1] + c1 * lpc[0], lpc[2] + c1 * lpc[1], lpc[3] + c1 * lpc[2], c1 * lpc[3]];
    fir5(&mut x_lp, &lpc2);
    x_lp
}

/// `find_best_pitch`: the two lags whose normalised correlation is
/// highest, best first.
fn find_best_pitch(xcorr: &[f32], y: &[f32], len: usize, max_pitch: usize) -> [usize; 2] {
    let mut syy = 1.0f32;
    let mut best_num = [-1.0f32; 2];
    let mut best_den = [0.0f32; 2];
    let mut best_pitch = [0, 1];
    for value in &y[..len] {
        syy += value * value;
    }
    for i in 0..max_pitch {
        if xcorr[i] > 0.0 {
            // Scaled so that squaring it neither underflows nor overflows.
            let xcorr16 = xcorr[i] * 1e-12;
            let num = xcorr16 * xcorr16;
            if num * best_den[1] > best_num[1] * syy {
                if num * best_den[0] > best_num[0] * syy {
                    best_num = [num, best_num[0]];
                    best_den = [syy, best_den[0]];
                    best_pitch = [i, best_pitch[0]];
                } else {
                    best_num[1] = num;
                    best_den[1] = syy;
                    best_pitch[1] = i;
                }
            }
        }
        syy += y[i + len] * y[i + len] - y[i] * y[i];
        syy = max(1.0, syy);
    }
    best_pitch
}

/// `rnn_pitch_search`: the period of `x_lp` in `y`, at the full rate,
/// searched coarse (a quarter of the rate) then fine (half).
pub(crate) fn search(x_lp: &[f32], y: &[f32], len: usize, max_pitch: usize) -> i32 {
    let lag = len + max_pitch;
    let x_lp4: Vec<f32> = (0..len >> 2).map(|j| x_lp[2 * j]).collect();
    let y_lp4: Vec<f32> = (0..lag >> 2).map(|j| y[2 * j]).collect();
    let mut xcorr = [0.0f32; MAX_PERIOD >> 1];
    pitch_xcorr(&x_lp4, &y_lp4, &mut xcorr, len >> 2, max_pitch >> 2);
    let best = find_best_pitch(&xcorr, &y_lp4, len >> 2, max_pitch >> 2);
    for (i, value) in xcorr.iter_mut().enumerate().take(max_pitch >> 1) {
        *value = 0.0;
        if i.abs_diff(2 * best[0]) > 2 && i.abs_diff(2 * best[1]) > 2 {
            continue;
        }
        *value = max(-1.0, inner_prod(x_lp, &y[i..], len >> 1));
    }
    let best = find_best_pitch(&xcorr, y, len >> 1, max_pitch >> 1);
    let offset = if best[0] > 0 && best[0] < (max_pitch >> 1) - 1 {
        let (a, b, c) = (xcorr[best[0] - 1], xcorr[best[0]], xcorr[best[0] + 1]);
        if c - a > 0.7 * (b - a) {
            1
        } else if a - c > 0.7 * (b - c) {
            -1
        } else {
            0
        }
    } else {
        0
    };
    2 * best[0] as i32 - offset
}

/// float `compute_pitch_gain`: `xy / sqrt(1 + xx·yy)`, the root and the
/// quotient in double, as the C's `sqrt` makes them.
fn pitch_gain(xy: f32, xx: f32, yy: f32) -> f32 {
    (f64::from(xy) / f64::from(1.0 + xx * yy).sqrt()) as f32
}

const SECOND_CHECK: [usize; 16] = [0, 0, 3, 2, 3, 2, 5, 2, 3, 2, 3, 2, 5, 2, 3, 2];

/// `rnn_remove_doubling`: the period `t0` corrected for octave errors
/// against its submultiples, and the gain the corrected period has.
///
/// `x` is the half-rate buffer; the C's pointer moved to `x + maxperiod`
/// is `base` here, so its `x[-i]` is `x[base - i]`.
pub(crate) fn remove_doubling(x: &[f32], t0: i32, prev_period: i32, prev_gain: f32) -> (i32, f32) {
    let max_period = MAX_PERIOD / 2;
    let min_period = MIN_PERIOD / 2;
    let n = FRAME / 2;
    let base = max_period;
    let prev_period = prev_period / 2;
    let t0 = ((t0 / 2) as usize).min(max_period - 1);
    let at = |lag: usize| &x[base - lag..];
    let sq = |v: f32| v * v;

    let xx = inner_prod(&x[base..], &x[base..], n);
    let xy = inner_prod(&x[base..], at(t0), n);
    let mut yy_lookup = [0.0f32; MAX_PERIOD / 2 + 1];
    yy_lookup[0] = xx;
    let mut yy = xx;
    for i in 1..=max_period {
        yy = yy + sq(x[base - i]) - sq(x[base + n - i]);
        yy_lookup[i] = max(0.0, yy);
    }
    let mut best_xy = xy;
    let mut best_yy = yy_lookup[t0];
    let g0 = pitch_gain(xy, xx, best_yy);
    let mut g = g0;
    let mut t = t0;
    for k in 2..=15 {
        let t1 = (2 * t0 + k) / (2 * k);
        if t1 < min_period {
            break;
        }
        let t1b = match k {
            2 if t1 + t0 > max_period => t0,
            2 => t0 + t1,
            _ => (2 * SECOND_CHECK[k] * t0 + k) / (2 * k),
        };
        let xy = 0.5 * (inner_prod(&x[base..], at(t1), n) + inner_prod(&x[base..], at(t1b), n));
        let yy = 0.5 * (yy_lookup[t1] + yy_lookup[t1b]);
        let g1 = pitch_gain(xy, xx, yy);
        let drift = (t1 as i32 - prev_period).abs();
        let cont = if drift <= 1 {
            prev_gain
        } else if drift <= 2 && 5 * k * k < t0 {
            0.5 * prev_gain
        } else {
            0.0
        };
        // Biased against very short periods, which short-term correlation
        // fakes. ⛔The C's further step under twice the minimum sat behind
        // this one's test (under three times) and never ran.
        let thresh = if t1 < 3 * min_period {
            max(0.4, 0.85 * g0 - cont)
        } else {
            max(0.3, 0.7 * g0 - cont)
        };
        if g1 > thresh {
            best_xy = xy;
            best_yy = yy;
            t = t1;
            g = g1;
        }
    }
    best_xy = max(0.0, best_xy);
    let mut pg = if best_yy <= best_xy { 1.0 } else { best_xy / (best_yy + 1.0) };
    let xcorr = [0, 1, 2].map(|k| inner_prod(&x[base..], &x[base + 1 - t - k..], n));
    let offset = if xcorr[2] - xcorr[0] > 0.7 * (xcorr[1] - xcorr[0]) {
        1
    } else if xcorr[0] - xcorr[2] > 0.7 * (xcorr[1] - xcorr[2]) {
        -1
    } else {
        0
    };
    if pg > g {
        pg = g;
    }
    let period = (2 * t as i32 + offset).max(MIN_PERIOD as i32);
    (period, pg)
}
