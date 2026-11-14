//! One 10 ms frame through RNNoise — `denoise.c`: high-pass, window and
//! transform, 22 bands' features, the network's gains, the pitch filter,
//! and the overlap-add back out.
//!
//! The arithmetic is the C's, in the C's order — and where a C double
//! literal (`1e-2`, `.001`, `-= 1.3`) lifts a float expression into
//! double, the expression is done in double here and rounded to float
//! where the C stores it.

use std::sync::OnceLock;

use crate::fft::{Complex, Fft, NFFT};
use crate::pitch::{self, max, min};
use crate::rnn::{self, GAINS, INPUT_SIZE, RnnState};

pub(crate) const FRAME_SIZE: usize = 480;
const WINDOW_SIZE: usize = 2 * FRAME_SIZE;
const FREQ_SIZE: usize = FRAME_SIZE + 1;
const NB_BANDS: usize = 22;
const CEPS_MEM: usize = 8;
const NB_DELTA_CEPS: usize = 6;
const NB_FEATURES: usize = NB_BANDS + 3 * NB_DELTA_CEPS + 2;
const _: () = assert!(NB_FEATURES == INPUT_SIZE && NB_BANDS == GAINS && WINDOW_SIZE == NFFT);

/// The bands' edges, in 200 Hz steps of the 20 ms window's bins / 4.
const EBAND5MS: [usize; NB_BANDS] =
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 34, 40, 48, 60, 78, 100];

/// What every frame shares: the transform, the window, the DCT.
struct Common {
    fft: Fft,
    half_window: [f32; FRAME_SIZE],
    dct_table: [f32; NB_BANDS * NB_BANDS],
}

fn common() -> &'static Common {
    static COMMON: OnceLock<Common> = OnceLock::new();
    COMMON.get_or_init(|| {
        use std::f64::consts::PI;
        let mut half_window = [0.0f32; FRAME_SIZE];
        for (i, w) in half_window.iter_mut().enumerate() {
            let a = 0.5 * PI * (i as f64 + 0.5) / FRAME_SIZE as f64;
            *w = libm::sin(0.5 * PI * libm::sin(a) * libm::sin(a)) as f32;
        }
        let mut dct_table = [0.0f32; NB_BANDS * NB_BANDS];
        for i in 0..NB_BANDS {
            for j in 0..NB_BANDS {
                let mut v = libm::cos((i as f64 + 0.5) * j as f64 * PI / NB_BANDS as f64) as f32;
                if j == 0 {
                    v = (f64::from(v) * 0.5f64.sqrt()) as f32;
                }
                dct_table[i * NB_BANDS + j] = v;
            }
        }
        Common { fft: Fft::new(), half_window, dct_table }
    })
}

/// Each band's share of `x` and `y` multiplied bin by bin, its edges'
/// bins split between the two bands they join (`compute_band_energy` with
/// `y` = `x`, `compute_band_corr` otherwise).
fn band_products(x: &[Complex], y: &[Complex]) -> [f32; NB_BANDS] {
    let mut sum = [0.0f32; NB_BANDS];
    for i in 0..NB_BANDS - 1 {
        let band_size = (EBAND5MS[i + 1] - EBAND5MS[i]) << 2;
        for j in 0..band_size {
            let frac = j as f32 / band_size as f32;
            let at = (EBAND5MS[i] << 2) + j;
            let mut tmp = x[at].r * y[at].r;
            tmp += x[at].i * y[at].i;
            sum[i] += (1.0 - frac) * tmp;
            sum[i + 1] += frac * tmp;
        }
    }
    sum[0] *= 2.0;
    sum[NB_BANDS - 1] *= 2.0;
    sum
}

/// `interp_band_gain`: the bands' values spread over the bins.
///
/// ⚠️Bins 400–480 stay 0 — above the last band's start no loop reaches,
/// and every C caller had zeroed them (the C's `memset` clears 481 BYTES,
/// a quarter of the row; its callers' `= {0}` cleared the rest).
fn interp_band_gain(band: &[f32; NB_BANDS]) -> [f32; FREQ_SIZE] {
    let mut g = [0.0f32; FREQ_SIZE];
    for i in 0..NB_BANDS - 1 {
        let band_size = (EBAND5MS[i + 1] - EBAND5MS[i]) << 2;
        for j in 0..band_size {
            let frac = j as f32 / band_size as f32;
            g[(EBAND5MS[i] << 2) + j] = (1.0 - frac) * band[i] + frac * band[i + 1];
        }
    }
    g
}

fn dct(input: &[f32; NB_BANDS]) -> [f32; NB_BANDS] {
    let table = &common().dct_table;
    let mut out = [0.0f32; NB_BANDS];
    for (i, value) in out.iter_mut().enumerate() {
        let mut sum = 0.0f32;
        for (j, &x) in input.iter().enumerate() {
            sum += x * table[j * NB_BANDS + i];
        }
        *value = (f64::from(sum) * (2.0f64 / 22.0).sqrt()) as f32;
    }
    out
}

fn forward_transform(input: &[f32; WINDOW_SIZE]) -> [Complex; FREQ_SIZE] {
    let x = input.map(|r| Complex { r, i: 0.0 });
    let y = common().fft.forward(&x);
    let mut out = [Complex::default(); FREQ_SIZE];
    out.copy_from_slice(&y[..FREQ_SIZE]);
    out
}

fn inverse_transform(input: &[Complex; FREQ_SIZE]) -> [f32; WINDOW_SIZE] {
    let mut x = [Complex::default(); WINDOW_SIZE];
    x[..FREQ_SIZE].copy_from_slice(input);
    for i in FREQ_SIZE..WINDOW_SIZE {
        x[i] = Complex { r: x[WINDOW_SIZE - i].r, i: -x[WINDOW_SIZE - i].i };
    }
    let y = common().fft.forward(&x);
    // The inverse is the forward transform read backwards.
    let mut out = [0.0f32; WINDOW_SIZE];
    out[0] = WINDOW_SIZE as f32 * y[0].r;
    for i in 1..WINDOW_SIZE {
        out[i] = WINDOW_SIZE as f32 * y[WINDOW_SIZE - i].r;
    }
    out
}

fn apply_window(x: &mut [f32; WINDOW_SIZE]) {
    for (i, &w) in common().half_window.iter().enumerate() {
        x[i] *= w;
        x[WINDOW_SIZE - 1 - i] *= w;
    }
}

/// What one channel carries from frame to frame (`struct DenoiseState`).
/// ⛔The C's `pitch_enh_buf` is not: nothing ever read it.
pub(crate) struct DenoiseState {
    analysis_mem: [f32; FRAME_SIZE],
    cepstral_mem: [[f32; NB_BANDS]; CEPS_MEM],
    memid: usize,
    synthesis_mem: [f32; FRAME_SIZE],
    pitch_buf: [f32; pitch::BUF],
    last_gain: f32,
    last_period: i32,
    mem_hp_x: [f32; 2],
    lastg: [f32; NB_BANDS],
    rnn: RnnState,
}

/// What the analysis of one frame hands the rest of it.
struct Analysis {
    x: [Complex; FREQ_SIZE],
    p: [Complex; FREQ_SIZE],
    ex: [f32; NB_BANDS],
    ep: [f32; NB_BANDS],
    exp: [f32; NB_BANDS],
    /// None for a frame with no audio in it (`compute_frame_features`
    /// answering 1): its features are not asked for.
    features: Option<[f32; NB_FEATURES]>,
}

impl DenoiseState {
    pub(crate) fn new() -> Self {
        DenoiseState {
            analysis_mem: [0.0; FRAME_SIZE],
            cepstral_mem: [[0.0; NB_BANDS]; CEPS_MEM],
            memid: 0,
            synthesis_mem: [0.0; FRAME_SIZE],
            pitch_buf: [0.0; pitch::BUF],
            last_gain: 0.0,
            last_period: 0,
            mem_hp_x: [0.0; 2],
            lastg: [0.0; NB_BANDS],
            rnn: RnnState::new(),
        }
    }

    /// `rnnoise_process_frame` without its voice probability: `input`, in
    /// 16-bit range, denoised into the frame it returns — the one before
    /// it, by the overlap.
    pub(crate) fn process_frame(&mut self, input: &[f32; FRAME_SIZE]) -> [f32; FRAME_SIZE] {
        let x = self.high_pass(input);
        let mut analysis = self.analyse(&x);
        if let Some(features) = analysis.features {
            let mut g = rnn::band_gains(&mut self.rnn, &features);
            pitch_filter(&mut analysis, &g);
            for (gain, last) in g.iter_mut().zip(&mut self.lastg) {
                let alpha = 0.6f32;
                *gain = max(*gain, alpha * *last);
                *last = *gain;
            }
            let gf = interp_band_gain(&g);
            for (bin, &gain) in analysis.x.iter_mut().zip(&gf) {
                bin.r *= gain;
                bin.i *= gain;
            }
        }
        self.synthesis(&analysis.x)
    }

    /// `biquad` with the high-pass's own coefficients, its feedback in
    /// double as the C's casts put it.
    fn high_pass(&mut self, input: &[f32; FRAME_SIZE]) -> [f32; FRAME_SIZE] {
        let a = [-1.99599f64 as f32, 0.99600f64 as f32];
        let b = [-2.0f32, 1.0];
        let mem = &mut self.mem_hp_x;
        input.map(|xi| {
            let yi = xi + mem[0];
            let (xd, yd) = (f64::from(xi), f64::from(yi));
            mem[0] = (f64::from(mem[1]) + (f64::from(b[0]) * xd - f64::from(a[0]) * yd)) as f32;
            mem[1] = (f64::from(b[1]) * xd - f64::from(a[1]) * yd) as f32;
            yi
        })
    }

    /// `frame_analysis`: the window over the last frame and this one,
    /// transformed, and its bands' energies.
    fn transform(&mut self, input: &[f32; FRAME_SIZE]) -> ([Complex; FREQ_SIZE], [f32; NB_BANDS]) {
        let mut x = [0.0f32; WINDOW_SIZE];
        x[..FRAME_SIZE].copy_from_slice(&self.analysis_mem);
        x[FRAME_SIZE..].copy_from_slice(input);
        self.analysis_mem = *input;
        apply_window(&mut x);
        let spectrum = forward_transform(&x);
        let energy = band_products(&spectrum, &spectrum);
        (spectrum, energy)
    }

    /// `compute_frame_features`.
    fn analyse(&mut self, input: &[f32; FRAME_SIZE]) -> Analysis {
        let (x, ex) = self.transform(input);
        self.pitch_buf.copy_within(FRAME_SIZE.., 0);
        self.pitch_buf[pitch::BUF - FRAME_SIZE..].copy_from_slice(input);
        let pitch_buf = pitch::downsample(&self.pitch_buf);
        let found = pitch::search(
            &pitch_buf[pitch::MAX_PERIOD >> 1..],
            &pitch_buf,
            pitch::FRAME,
            pitch::MAX_PERIOD - 3 * pitch::MIN_PERIOD,
        );
        let (period, gain) =
            pitch::remove_doubling(&pitch_buf, pitch::MAX_PERIOD as i32 - found, self.last_period, self.last_gain);
        self.last_period = period;
        self.last_gain = gain;
        let start = pitch::BUF - WINDOW_SIZE - period as usize;
        let mut p: [f32; WINDOW_SIZE] = self.pitch_buf[start..start + WINDOW_SIZE].try_into().expect("a window");
        apply_window(&mut p);
        let p = forward_transform(&p);
        let ep = band_products(&p, &p);
        let mut exp = band_products(&x, &p);
        for ((value, &e), &q) in exp.iter_mut().zip(&ex).zip(&ep) {
            *value = (f64::from(*value) / (0.001 + f64::from(e * q)).sqrt()) as f32;
        }
        let features = self.features(&ex, &exp, period);
        Analysis { x, p, ex, ep, exp, features }
    }

    /// The network's 42 inputs — the cepstrum and its deltas, the pitch
    /// correlation's, the period and the spectrum's variability — or None
    /// when the frame holds no audio, which leaves the cepstra as they
    /// were.
    fn features(&mut self, ex: &[f32; NB_BANDS], exp: &[f32; NB_BANDS], period: i32) -> Option<[f32; NB_FEATURES]> {
        let mut features = [0.0f32; NB_FEATURES];
        let tmp = dct(exp);
        let corr = NB_BANDS + 2 * NB_DELTA_CEPS;
        features[corr..corr + NB_DELTA_CEPS].copy_from_slice(&tmp[..NB_DELTA_CEPS]);
        features[corr] = (f64::from(features[corr]) - 1.3) as f32;
        features[corr + 1] = (f64::from(features[corr + 1]) - 0.9) as f32;
        features[NB_BANDS + 3 * NB_DELTA_CEPS] = (0.01 * f64::from(period - 300)) as f32;
        let mut ly = [0.0f32; NB_BANDS];
        let mut log_max = -2.0f32;
        let mut follow = -2.0f32;
        let mut e = 0.0f32;
        for (l, &x) in ly.iter_mut().zip(ex) {
            // MAX16 over a float and a double is a double.
            let max_d = |a: f64, b: f64| if a > b { a } else { b };
            let y = libm::log10(1e-2 + f64::from(x)) as f32;
            *l = max_d(f64::from(log_max - 7.0), max_d(f64::from(follow) - 1.5, f64::from(y))) as f32;
            log_max = max(log_max, *l);
            follow = max_d(f64::from(follow) - 1.5, f64::from(*l)) as f32;
            e += x;
        }
        if f64::from(e) < 0.04 {
            // No audio: the state is left alone.
            return None;
        }
        features[..NB_BANDS].copy_from_slice(&dct(&ly));
        features[0] -= 12.0;
        features[1] -= 4.0;
        let m0 = self.memid;
        let m1 = (m0 + CEPS_MEM - 1) % CEPS_MEM;
        let m2 = (m0 + CEPS_MEM - 2) % CEPS_MEM;
        self.cepstral_mem[m0].copy_from_slice(&features[..NB_BANDS]);
        let (c0, c1, c2) = (self.cepstral_mem[m0], self.cepstral_mem[m1], self.cepstral_mem[m2]);
        self.memid = (m0 + 1) % CEPS_MEM;
        for i in 0..NB_DELTA_CEPS {
            features[i] = c0[i] + c1[i] + c2[i];
            features[NB_BANDS + i] = c0[i] - c2[i];
            features[NB_BANDS + NB_DELTA_CEPS + i] = c0[i] - 2.0 * c1[i] + c2[i];
        }
        let mut spec_variability = 0.0f32;
        for (i, a) in self.cepstral_mem.iter().enumerate() {
            let mut mindist = 1e15f32;
            for (j, b) in self.cepstral_mem.iter().enumerate() {
                let mut dist = 0.0f32;
                for (x, y) in a.iter().zip(b) {
                    let tmp = x - y;
                    dist += tmp * tmp;
                }
                if j != i {
                    mindist = min(mindist, dist);
                }
            }
            spec_variability += mindist;
        }
        features[NB_BANDS + 3 * NB_DELTA_CEPS + 1] = (f64::from(spec_variability / CEPS_MEM as f32) - 2.1) as f32;
        Some(features)
    }

    /// `frame_synthesis`: back out, windowed, overlapped with the frame
    /// before.
    fn synthesis(&mut self, y: &[Complex; FREQ_SIZE]) -> [f32; FRAME_SIZE] {
        let mut x = inverse_transform(y);
        apply_window(&mut x);
        let mut out = [0.0f32; FRAME_SIZE];
        for ((o, &a), &b) in out.iter_mut().zip(&x).zip(&self.synthesis_mem) {
            *o = a + b;
        }
        self.synthesis_mem.copy_from_slice(&x[FRAME_SIZE..]);
        out
    }
}

/// `pitch_filter`: the pitch's harmonics added back where the band is
/// voiced, then each band brought back to its energy.
fn pitch_filter(a: &mut Analysis, g: &[f32; NB_BANDS]) {
    let sq = |v: f32| v * v;
    let mut r = [0.0f32; NB_BANDS];
    for i in 0..NB_BANDS {
        let (exp, gi) = (a.exp[i], g[i]);
        let mut ri = if exp > gi {
            1.0
        } else {
            (f64::from(sq(exp) * (1.0 - sq(gi))) / (0.001 + f64::from(sq(gi) * (1.0 - sq(exp))))) as f32
        };
        ri = f64::from(min(1.0, max(0.0, ri))).sqrt() as f32;
        ri = (f64::from(ri) * (f64::from(a.ex[i]) / (1e-8 + f64::from(a.ep[i]))).sqrt()) as f32;
        r[i] = ri;
    }
    let rf = interp_band_gain(&r);
    for ((x, p), &gain) in a.x.iter_mut().zip(&a.p).zip(&rf) {
        x.r += gain * p.r;
        x.i += gain * p.i;
    }
    let new_e = band_products(&a.x, &a.x);
    let mut norm = [0.0f32; NB_BANDS];
    for ((n, &e), &ne) in norm.iter_mut().zip(&a.ex).zip(&new_e) {
        *n = (f64::from(e) / (1e-8 + f64::from(ne))).sqrt() as f32;
    }
    let normf = interp_band_gain(&norm);
    for (x, &gain) in a.x.iter_mut().zip(&normf) {
        x.r *= gain;
        x.i *= gain;
    }
}
