//! The complex FFT RNNoise transforms its windows with — opus's kiss_fft
//! (`kiss_fft.c`, float build), at the one size it is asked: 960 points.
//!
//! Every butterfly does the C's arithmetic in the C's order, so the bins
//! come out bit for bit. ⛔Not ported, for no call reaches them at 960:
//! the radix-2 butterfly, the inverse transform, a size taken from
//! another's twiddles, and the factoring that fails past radix 5.

#[derive(Clone, Copy, Default)]
pub(crate) struct Complex {
    pub(crate) r: f32,
    pub(crate) i: f32,
}

fn mul(a: Complex, b: Complex) -> Complex {
    Complex { r: a.r * b.r - a.i * b.i, i: a.r * b.i + a.i * b.r }
}

fn add(a: Complex, b: Complex) -> Complex {
    Complex { r: a.r + b.r, i: a.i + b.i }
}

fn sub(a: Complex, b: Complex) -> Complex {
    Complex { r: a.r - b.r, i: a.i - b.i }
}

pub(crate) const NFFT: usize = 960;

/// Each stage's radix and the length left after it, as `kf_factor` lays
/// 960 out: the fours first, then the primes that remain, the whole order
/// reversed so the degenerate radix 4 (all twiddles 1) runs last.
const STAGES: [(usize, usize); 5] = [(5, 192), (3, 64), (4, 16), (4, 4), (4, 1)];

pub(crate) struct Fft {
    twiddles: [Complex; NFFT],
    bitrev: [usize; NFFT],
    scale: f32,
}

impl Fft {
    pub(crate) fn new() -> Self {
        let mut twiddles = [Complex::default(); NFFT];
        for (i, twiddle) in twiddles.iter_mut().enumerate() {
            // compute_twiddles: the phase in double, each part rounded once.
            let phase = (-2.0 * std::f64::consts::PI / NFFT as f64) * i as f64;
            *twiddle = Complex { r: phase.cos() as f32, i: phase.sin() as f32 };
        }
        let mut bitrev = [0; NFFT];
        bitrev_table(0, &mut bitrev, 0, 1, &STAGES);
        Fft { twiddles, bitrev, scale: 1.0 / NFFT as f32 }
    }

    /// The forward transform of `input`, scaled by 1/960 (`rnn_fft_c`).
    pub(crate) fn forward(&self, input: &[Complex; NFFT]) -> [Complex; NFFT] {
        let mut out = [Complex::default(); NFFT];
        for (x, &at) in input.iter().zip(&self.bitrev) {
            out[at] = Complex { r: self.scale * x.r, i: self.scale * x.i };
        }
        self.stages(&mut out);
        out
    }

    /// `rnn_fft_impl`: the stages from the last factor back to the first.
    fn stages(&self, fout: &mut [Complex; NFFT]) {
        let mut fstride = [1; STAGES.len()];
        for at in 1..STAGES.len() {
            fstride[at] = fstride[at - 1] * STAGES[at - 1].0;
        }
        for at in (0..STAGES.len()).rev() {
            let (radix, m) = STAGES[at];
            let mm = if at == 0 { 1 } else { STAGES[at - 1].1 };
            let (stride, n) = (fstride[at], fstride[at]);
            match radix {
                3 => self.bfly3(fout, stride, m, n, mm),
                4 => self.bfly4(fout, stride, m, n, mm),
                _ => self.bfly5(fout, stride, m, n, mm),
            }
        }
    }

    fn bfly4(&self, fout: &mut [Complex], fstride: usize, m: usize, n: usize, mm: usize) {
        if m == 1 {
            // The degenerate case: every twiddle is 1.
            for block in fout.chunks_exact_mut(4).take(n) {
                let scratch0 = sub(block[0], block[2]);
                block[0] = add(block[0], block[2]);
                let mut scratch1 = add(block[1], block[3]);
                block[2] = sub(block[0], scratch1);
                block[0] = add(block[0], scratch1);
                scratch1 = sub(block[1], block[3]);
                block[1] = Complex { r: scratch0.r + scratch1.i, i: scratch0.i - scratch1.r };
                block[3] = Complex { r: scratch0.r - scratch1.i, i: scratch0.i + scratch1.r };
            }
            return;
        }
        let tw = &self.twiddles;
        for i in 0..n {
            for j in 0..m {
                let at = i * mm + j;
                let s0 = mul(fout[at + m], tw[j * fstride]);
                let s1 = mul(fout[at + 2 * m], tw[j * fstride * 2]);
                let s2 = mul(fout[at + 3 * m], tw[j * fstride * 3]);
                let s5 = sub(fout[at], s1);
                fout[at] = add(fout[at], s1);
                let s3 = add(s0, s2);
                let s4 = sub(s0, s2);
                fout[at + 2 * m] = sub(fout[at], s3);
                fout[at] = add(fout[at], s3);
                fout[at + m] = Complex { r: s5.r + s4.i, i: s5.i - s4.r };
                fout[at + 3 * m] = Complex { r: s5.r - s4.i, i: s5.i + s4.r };
            }
        }
    }

    fn bfly3(&self, fout: &mut [Complex], fstride: usize, m: usize, n: usize, mm: usize) {
        let tw = &self.twiddles;
        let epi3 = tw[fstride * m];
        for i in 0..n {
            for k in 0..m {
                let at = i * mm + k;
                let s1 = mul(fout[at + m], tw[k * fstride]);
                let s2 = mul(fout[at + 2 * m], tw[k * fstride * 2]);
                let s3 = add(s1, s2);
                let mut s0 = sub(s1, s2);
                let mut fm = Complex {
                    r: fout[at].r - s3.r * 0.5,
                    i: fout[at].i - s3.i * 0.5,
                };
                s0.r *= epi3.i;
                s0.i *= epi3.i;
                fout[at] = add(fout[at], s3);
                fout[at + 2 * m] = Complex { r: fm.r + s0.i, i: fm.i - s0.r };
                fm = Complex { r: fm.r - s0.i, i: fm.i + s0.r };
                fout[at + m] = fm;
            }
        }
    }

    fn bfly5(&self, fout: &mut [Complex], fstride: usize, m: usize, n: usize, mm: usize) {
        let tw = &self.twiddles;
        let ya = tw[fstride * m];
        let yb = tw[fstride * 2 * m];
        for i in 0..n {
            for u in 0..m {
                let at = [0, 1, 2, 3, 4].map(|k| i * mm + k * m + u);
                let s0 = fout[at[0]];
                let s1 = mul(fout[at[1]], tw[u * fstride]);
                let s2 = mul(fout[at[2]], tw[2 * u * fstride]);
                let s3 = mul(fout[at[3]], tw[3 * u * fstride]);
                let s4 = mul(fout[at[4]], tw[4 * u * fstride]);
                let s7 = add(s1, s4);
                let s10 = sub(s1, s4);
                let s8 = add(s2, s3);
                let s9 = sub(s2, s3);
                fout[at[0]] = Complex {
                    r: fout[at[0]].r + (s7.r + s8.r),
                    i: fout[at[0]].i + (s7.i + s8.i),
                };
                let s5 = Complex {
                    r: s0.r + (s7.r * ya.r + s8.r * yb.r),
                    i: s0.i + (s7.i * ya.r + s8.i * yb.r),
                };
                let s6 = Complex {
                    r: s10.i * ya.i + s9.i * yb.i,
                    i: -(s10.r * ya.i + s9.r * yb.i),
                };
                fout[at[1]] = sub(s5, s6);
                fout[at[4]] = add(s5, s6);
                let s11 = Complex {
                    r: s0.r + (s7.r * yb.r + s8.r * ya.r),
                    i: s0.i + (s7.i * yb.r + s8.i * ya.r),
                };
                let s12 = Complex {
                    r: s9.i * ya.i - s10.i * yb.i,
                    i: s10.r * yb.i - s9.r * ya.i,
                };
                fout[at[2]] = add(s11, s12);
                fout[at[3]] = sub(s11, s12);
            }
        }
    }
}

/// `compute_bitrev_table`: where each input lands, stage by stage.
fn bitrev_table(fout: usize, f: &mut [usize], at: usize, fstride: usize, stages: &[(usize, usize)]) {
    let (p, m) = stages[0];
    for j in 0..p {
        if m == 1 {
            f[at + j * fstride] = fout + j;
        } else {
            bitrev_table(fout + j * m, f, at + j * fstride, fstride * p, &stages[1..]);
        }
    }
}
