//! R1's map as resample.wgsl reads it. The CPU quantises the double matrix
//! once by the spec's q() — x · 2^k rounded half away from zero, as Dart's
//! round() and C's llround() do — and divides a homography through by its
//! largest w at the output's corners first, so w <= 1 everywhere inside
//! (gpu-int-spec-canvas 1b (1/4) R1). Only + − × ÷ on doubles, which IEEE
//! fixes on every device.

/// R1's two modes, resample.wgsl's ids.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ResampleMode {
    /// The tent mean.
    Blend = 0,
    /// The area vote: the one source word covering most of the preimage.
    Pick = 1,
}

/// The destination-to-source map in the kernel's integers.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ResampleMap {
    a: i32,
    b: i32,
    d: i32,
    e: i32,
    g: i32,
    h: i32,
    floor: u32,
    mode: ResampleMode,
    c: i64,
    f: i64,
    i: i64,
}

/// |q| below 2^31: a, b, d, e (2^11 px, Q.20) and g, h (Q.36).
const NARROW: f64 = 2_147_483_648.0;
/// |q| below 2^61: c, f, i. A c past it lands 2^41 px away, where nothing
/// is inside, and keeps every sum the kernel forms within an i64.
const WIDE: f64 = 2_305_843_009_213_693_952.0;
/// Blend's radius ceiling, 16 px: a floor above it lands on it anyway.
const CEILING: f64 = 16.0;

impl ResampleMap {
    /// Words one map takes, resample.wgsl's `ResampleMap` field by field.
    pub(crate) const WORDS: usize = 14;

    /// The map of `inverse` — destination point to source point, row-major
    /// with the homogeneous row last, pixel (x, y) spanning x..x+1 — over a
    /// whole output of `columns` × `rows` pixels; a window of it keeps the
    /// whole's map. `radius_floor` is Blend's, at least 1.
    ///
    /// `None` when nothing lands anywhere: a matrix past the spec's ranges
    /// (a reduction past 2048 times), or a homography with no positive w
    /// at the output's corners, where w <= 0 is outside.
    pub(crate) fn new(
        inverse: [f64; 9],
        radius_floor: f64,
        mode: ResampleMode,
        columns: u32,
        rows: u32,
    ) -> Option<Self> {
        let mut m = inverse;
        if !(m[6] == 0.0 && m[7] == 0.0 && m[8] == 1.0) {
            let (right, bottom) = (f64::from(columns), f64::from(rows));
            let w = |x: f64, y: f64| m[6] * x + m[7] * y + m[8];
            let most = w(0.0, 0.0).max(w(right, 0.0)).max(w(0.0, bottom)).max(w(right, bottom));
            if !(most > 0.0) {
                return None;
            }
            for entry in &mut m {
                *entry /= most;
            }
        }
        let [a, b, c, d, e, f, g, h, i] = m;
        Some(Self {
            a: q(a, 20, NARROW)? as i32,
            b: q(b, 20, NARROW)? as i32,
            d: q(d, 20, NARROW)? as i32,
            e: q(e, 20, NARROW)? as i32,
            g: q(g, 36, NARROW)? as i32,
            h: q(h, 36, NARROW)? as i32,
            floor: q(radius_floor.min(CEILING), 16, NARROW)? as u32,
            mode,
            c: q(c, 20, WIDE)?,
            f: q(f, 20, WIDE)?,
            i: q(i, 36, WIDE)?,
        })
    }

    /// The words the kernel reads, i64s low word first.
    pub(crate) fn words(&self) -> [u32; Self::WORDS] {
        let (c, f, i) = (self.c as u64, self.f as u64, self.i as u64);
        [
            self.a as u32,
            self.b as u32,
            self.d as u32,
            self.e as u32,
            self.g as u32,
            self.h as u32,
            self.floor,
            self.mode as u32,
            c as u32,
            (c >> 32) as u32,
            f as u32,
            (f >> 32) as u32,
            i as u32,
            (i >> 32) as u32,
        ]
    }
}

/// q(x, k), when its magnitude is below `limit`. Scaling by a power of two
/// is exact, so the one rounding is round()'s.
fn q(x: f64, k: u32, limit: f64) -> Option<i64> {
    let scaled = (x * (1u64 << k) as f64).round();
    (scaled.abs() < limit).then_some(scaled as i64)
}

#[cfg(test)]
mod tests {
    use super::*;

    const IDENTITY: [f64; 9] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];

    fn map(inverse: [f64; 9]) -> Option<ResampleMap> {
        ResampleMap::new(inverse, 1.0, ResampleMode::Blend, 10, 10)
    }

    #[test]
    fn an_entry_rounds_half_away_from_zero() {
        // 0.5 + 2^-21 is 2^19 + 0.5 in Q.20 — up; its negative, down.
        let half = 0.5 + 1.0 / 2_097_152.0;
        let m = map([half, -half, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]).unwrap();
        assert_eq!((m.a, m.b), (524_289, -524_289));
        assert_eq!(m.floor, 65_536);
    }

    #[test]
    fn a_reduction_past_2048_times_lands_nowhere() {
        let last = 2048.0 - 1.0 / 1_048_576.0;
        assert!(map([last, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]).is_some());
        assert!(map([2048.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]).is_none());
        assert!(map([1.0, 0.0, f64::NAN, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]).is_none());
    }

    #[test]
    fn a_homography_is_divided_by_its_largest_corner_w() {
        // w = 1 + x/100 is 2 at the right-hand corners of 100 × 100.
        let inverse = [2.0, 0.0, 4.0, 0.0, 2.0, 0.0, 0.01, 0.0, 1.0];
        let m = ResampleMap::new(inverse, 1.0, ResampleMode::Blend, 100, 100).unwrap();
        assert_eq!((m.a, m.c, m.e), (1 << 20, 2 << 20, 1 << 20));
        // 0.005 · 2^36 = 343597383.68.
        assert_eq!((m.g, m.h, m.i), (343_597_384, 0, 1 << 35));
    }

    #[test]
    fn a_homography_behind_every_corner_lands_nowhere() {
        assert!(map([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0]).is_none());
        assert!(map([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]).is_none());
    }

    #[test]
    fn an_affine_map_is_not_rescaled() {
        let m = map(IDENTITY).unwrap();
        assert_eq!(m.words(), [1 << 20, 0, 0, 1 << 20, 0, 0, 65_536, 0, 0, 0, 0, 0, 0, 16]);
    }
}
