//! R1's map as resample.wgsl reads it. The CPU quantises the double matrix
//! once by the spec's q() — x · 2^k rounded half away from zero, as Dart's
//! round() and C's llround() do — and divides a homography through by its
//! corner w farthest from 0 first, so 0 < w <= 1 on the side of the
//! output's centre (gpu-int-spec-canvas 1b (1/4) R1). Only + − × ÷ on
//! doubles, which IEEE fixes on every device.

/// R1's three modes, resample.wgsl's ids (2 is the copy any of them takes).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ResampleMode {
    /// The tent mean.
    Blend = 0,
    /// The area vote: the one source word covering most of the preimage.
    Pick = 1,
    /// The one source word where the pixel's centre lands — the screen's at
    /// 100% and over, as the app's `FilterQuality.none` is today (canvas
    /// base, gpu-int-spec-canvas 11-05 21:39).
    Nearest = 3,
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
    /// How much coarser than Q.36 g and h are held: 0 but for a steep
    /// homography (see [`ResampleMap::new`]).
    shift: u32,
}

/// |q| below 2^31: a, b, d, e (2^11 px, Q.20) and g, h (Q.36, or coarser
/// by a shift).
const NARROW: f64 = 2_147_483_648.0;
/// |q| below 2^61: c, f, i. A c past it lands 2^41 px away, where nothing
/// is inside, and keeps every sum the kernel forms within an i64.
const WIDE: f64 = 2_305_843_009_213_693_952.0;
/// Blend's radius ceiling, 16 px: a floor above it lands on it anyway.
pub(crate) const CEILING: f64 = 16.0;
/// resample.wgsl's mode for a map that copies words, whichever was asked.
const COPY: u32 = 2;
/// Where a map's mode is among its words (resample.wgsl's `resample_map`).
const MODE_WORD: usize = 7;
/// 1 in Q.20 and in Q.36.
const ONE: i32 = 1 << 20;
const ONE_36: i64 = 1 << 36;
/// How far past the box where an affine map's corners land a pixel can
/// read: Blend's tent reaches under 15.5 px past where a centre lands, and
/// every centre lands inside the box; the half pixel more is the doubles'.
/// Pick reads inside each pixel's own preimage, Nearest at its centre.
const SLACK: f64 = 16.0;

impl ResampleMap {
    /// Words one map takes, resample.wgsl's `ResampleMap` field by field.
    pub(crate) const WORDS: usize = 16;

    /// The map of `inverse` — destination point to source point, row-major
    /// with the homogeneous row last, pixel (x, y) spanning x..x+1 — over a
    /// whole output of `columns` × `rows` pixels; a window of it keeps the
    /// whole's map. `radius_floor` is Blend's, at least 1.
    ///
    /// `None` when nothing lands anywhere: a matrix past the spec's ranges
    /// (a reduction past 2048 times), or a homography whose w is 0 at every
    /// corner of the output.
    ///
    /// A homography is divided through by its corner w farthest from 0,
    /// sign and all — the positive one on a tie —, so a matrix and its
    /// negative are one map, as a homogeneous matrix is at any scale. A
    /// linear w is largest and least at opposite corners, so the farther
    /// one is on the side of the output's centre, where a caller sized the
    /// output to what lands: w is positive there and at most 1, and w <= 0
    /// is outside. ↩️It took the largest w, so a matrix whose w was
    /// negative over the whole output landed nothing — the quad tool's,
    /// made 1 at the canvas origin, wherever the vanishing line runs
    /// between the origin and the float (a-small-float-in-steep-
    /// perspective-vanishes, 2026-11-11).
    ///
    /// Divided through, |w| <= 1 at every corner, so |g| <= 2 / columns and
    /// |h| <= 2 / rows. A g or h past an i32 at Q.36 — |g| >= 2^-5 a pixel,
    /// over an output 64 px or fewer a side — is held at Q.(36 − shift),
    /// by the least shift that holds both (7 holds any), and
    /// resample.wgsl shifts their part of w back: w is the same Q.37 either
    /// way — it and each of its terms within 2^40 —, and a map that needs
    /// no shift is the words, so the bytes, it always was. ↩️It landed
    /// nothing (canvas base agreed, gpu-int-spec-canvas 2026-11-05 16:48),
    /// counted as "a vanishing line within 32 px of the output's edge, as
    /// rare as a reduction past 2048 times" — but that is every small float
    /// pinched hard in perspective (a-small-float-in-steep-perspective-
    /// vanishes, 관제 2026-11-11).
    pub(crate) fn new(
        inverse: [f64; 9],
        radius_floor: f64,
        mode: ResampleMode,
        columns: u32,
        rows: u32,
    ) -> Option<Self> {
        let mut m = inverse;
        let projective = !(m[6] == 0.0 && m[7] == 0.0 && m[8] == 1.0);
        if projective {
            let (right, bottom) = (f64::from(columns), f64::from(rows));
            let w = |x: f64, y: f64| m[6] * x + m[7] * y + m[8];
            let farther = |most: f64, corner: f64| {
                let past = corner.abs() > most.abs() || (corner.abs() == most.abs() && corner > most);
                if past { corner } else { most }
            };
            let most = [w(right, 0.0), w(0.0, bottom), w(right, bottom)].into_iter().fold(w(0.0, 0.0), farther);
            if !(most.abs() > 0.0) {
                return None;
            }
            for entry in &mut m {
                *entry /= most;
            }
        }
        let [a, b, c, d, e, f, g, h, i] = m;
        let shift = if projective { shift_of(g, h)? } else { 0 };
        Some(Self {
            a: q(a, 20, NARROW)? as i32,
            b: q(b, 20, NARROW)? as i32,
            d: q(d, 20, NARROW)? as i32,
            e: q(e, 20, NARROW)? as i32,
            g: q(g, 36 - shift, NARROW)? as i32,
            h: q(h, 36 - shift, NARROW)? as i32,
            floor: floor(radius_floor)?,
            mode,
            c: q(c, 20, WIDE)?,
            f: q(f, 20, WIDE)?,
            i: q(i, 36, WIDE)?,
            shift,
        })
    }

    /// The affine map whose entries `[a, b, c, d, e, f]` are already Q.20 —
    /// source x = a·x + b·y + c, source y = d·x + e·y + f — as R3 works each
    /// triangle's out exactly (gpu-int-spec-canvas 1b R3), so they are not
    /// rounded a second time through [`Self::new`]'s doubles. `None` past
    /// the ranges `new` holds them to: that triangle lands nothing.
    pub(crate) fn affine(
        [a, b, c, d, e, f]: [i128; 6],
        radius_floor: f64,
        mode: ResampleMode,
    ) -> Option<Self> {
        Some(Self {
            a: held(a, NARROW)? as i32,
            b: held(b, NARROW)? as i32,
            d: held(d, NARROW)? as i32,
            e: held(e, NARROW)? as i32,
            g: 0,
            h: 0,
            floor: floor(radius_floor)?,
            mode,
            c: held(c, WIDE)?,
            f: held(f, WIDE)?,
            i: ONE_36,
            shift: 0,
        })
    }

    /// The whole-pixel move by (`dx`, `dy`): destination (x, y) is the
    /// source's (x − dx, y − dy), copied word for word in either mode.
    pub(crate) fn moved(dx: i32, dy: i32) -> Self {
        Self {
            a: ONE,
            b: 0,
            d: 0,
            e: ONE,
            g: 0,
            h: 0,
            floor: 1 << 16,
            mode: ResampleMode::Blend,
            c: -i64::from(dx) << 20,
            f: -i64::from(dy) << 20,
            i: ONE_36,
            shift: 0,
        }
    }

    /// The same map with g and h held `by` bits coarser and the shift
    /// taking them back, when both are whole there: the same w and the same
    /// Jacobian.
    #[cfg(test)]
    pub(crate) fn coarser(self, by: u32) -> Option<Self> {
        let whole = |x: i32| x % (1 << by) == 0;
        (whole(self.g) && whole(self.h)).then_some(Self {
            g: self.g >> by,
            h: self.h >> by,
            shift: self.shift + by,
            ..self
        })
    }

    /// The source pixels that destination pixels `x0..x1` × `y0..y1` can
    /// read, as `[left, top, right, bottom)`: exactly for a copy, the box
    /// where the rectangle's corners land widened by [`SLACK`] for any other
    /// affine map, and `None` — unbounded here — for a homography.
    ///
    /// ⚠️A homography's subsamples land by its Jacobian at the pixel's
    /// centre, so past its own preimage — by more than a slack only near its
    /// horizon under reductions of thousands of times. Its row binds all its
    /// tiles instead of carrying a bound that no test could reach and so no
    /// mutant could check (11-05); a cel's tiles share one page (설계 ④).
    pub(crate) fn reads(&self, x0: i64, y0: i64, x1: i64, y1: i64) -> Option<[i64; 4]> {
        if self.is_copy() {
            let (dx, dy) = (self.c >> 20, self.f >> 20);
            return Some([x0 + dx, y0 + dy, x1 + dx, y1 + dy]);
        }
        if !self.is_affine() {
            return None;
        }
        let one = f64::from(ONE);
        let at = |x: i64, y: i64| {
            let (x, y) = (x as f64, y as f64);
            (
                (f64::from(self.a) * x + f64::from(self.b) * y + self.c as f64) / one,
                (f64::from(self.d) * x + f64::from(self.e) * y + self.f as f64) / one,
            )
        };
        let (mut left, mut top, mut right, mut bottom) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for (u, v) in [at(x0, y0), at(x1, y0), at(x0, y1), at(x1, y1)] {
            (left, top, right, bottom) = (left.min(u), top.min(v), right.max(u), bottom.max(v));
        }
        Some([
            (left - SLACK).floor() as i64,
            (top - SLACK).floor() as i64,
            (right + SLACK).ceil() as i64,
            (bottom + SLACK).ceil() as i64,
        ])
    }

    /// Whether the map is affine — no homogeneous row but (0, 0, 1). The one
    /// place it is decided: the kernel reads it as its last word, and a plan
    /// bounding a row's reads asks it here.
    pub(crate) fn is_affine(&self) -> bool {
        self.g == 0 && self.h == 0 && self.i == ONE_36
    }

    /// Whether the map moves by whole pixels and nothing else, so each pixel
    /// is one source word as it is — R1's integer copy, in either mode. The
    /// one place it is decided: the kernel reads it as its mode, and a plan
    /// that splits a row's reads by page asks it here. A correctness contract,
    /// not a speed trick: moving a drawing by an exact pixel count and getting
    /// different bytes back would be a defect no filter quality could excuse.
    pub(crate) fn is_copy(&self) -> bool {
        let whole = |offset: i64| offset % i64::from(ONE) == 0;
        self.is_affine() && self.a == ONE && self.e == ONE && self.b == 0 && self.d == 0
            && whole(self.c) && whole(self.f)
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
            if self.is_copy() { COPY } else { self.mode as u32 },
            c as u32,
            (c >> 32) as u32,
            f as u32,
            (f >> 32) as u32,
            i as u32,
            (i >> 32) as u32,
            u32::from(!self.is_affine()),
            self.shift,
        ]
    }
}

/// The R1 modes a pass's maps hold, as their own mode words say — what
/// resample.wgsl's overrides compile in. The copy is in every pass, as
/// [`ResampleMap::words`] makes a whole-pixel move one whatever was asked.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct ResampleModes(u32);

impl ResampleModes {
    /// Every mode.
    pub(crate) const ALL: Self = Self(
        1 << ResampleMode::Blend as u32
            | 1 << ResampleMode::Pick as u32
            | 1 << ResampleMode::Nearest as u32,
    );

    /// These and the mode of `words`, a map's as [`ResampleMap::words`]
    /// wrote them — none for the copy, in every pass. A pass's modes are
    /// taken from the very words it is handed, so no map of a mode left
    /// out can reach it (캔버스 베이스 11-06).
    pub(crate) fn with(self, words: &[u32; ResampleMap::WORDS]) -> Self {
        match words[MODE_WORD] {
            COPY => self,
            mode => Self(self.0 | 1 << mode),
        }
    }

    /// resample.wgsl's overrides for these modes.
    pub(crate) fn constants(self) -> [(&'static str, f64); 3] {
        let has = |mode: ResampleMode| f64::from(self.0 >> mode as u32 & 1);
        [
            ("resample_with_blend", has(ResampleMode::Blend)),
            ("resample_with_pick", has(ResampleMode::Pick)),
            ("resample_with_nearest", has(ResampleMode::Nearest)),
        ]
    }
}

/// q(x, k), when its magnitude is below `limit`: the integer specs' one
/// way a double the CPU worked out becomes fixed point (gpu-int-spec-canvas
/// 1b 공통) — R1's maps, a blur along a way's taps. Scaling by a power of
/// two is exact, so the one rounding is round()'s.
pub(crate) fn q(x: f64, k: u32, limit: f64) -> Option<i64> {
    let scaled = (x * (1u64 << k) as f64).round();
    (scaled.abs() < limit).then_some(scaled as i64)
}

/// The least shift that holds a homography's `g` and `h`, divided through,
/// in an i32 at Q.(36 − shift): 7 holds any, |g| and |h| at most 2.
fn shift_of(g: f64, h: f64) -> Option<u32> {
    (0..=7).find(|&shift| q(g, 36 - shift, NARROW).is_some() && q(h, 36 - shift, NARROW).is_some())
}

/// `value`, already fixed point, when its magnitude is below `limit` — q's
/// range, compared exactly.
fn held(value: i128, limit: f64) -> Option<i64> {
    (value.unsigned_abs() < limit as u128).then_some(value as i64)
}

/// Blend's radius floor in Q.16, at most [`CEILING`].
fn floor(radius_floor: f64) -> Option<u32> {
    Some(q(radius_floor.min(CEILING), 16, NARROW)? as u32)
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

    /// An affine map Q.20 holds exactly is the same map from its integers as
    /// from its doubles.
    #[test]
    fn an_affine_map_from_integers_is_new_s_map() {
        let inverse = [0.25, -0.375, 7.0, -3.0, 0.375, -12.5, 0.0, 0.0, 1.0];
        let made = ResampleMap::new(inverse, 2.5, ResampleMode::Pick, 10, 10);
        let entries = [1 << 18, -3 << 17, 7 << 20, -3 << 20, 3 << 17, -25 << 19];
        assert!(made.is_some());
        assert_eq!(ResampleMap::affine(entries, 2.5, ResampleMode::Pick), made);
        let moved = [1 << 20, 0, -5 << 20, 0, 1 << 20, 3 << 20];
        let shifted = [1.0, 0.0, -5.0, 0.0, 1.0, 3.0, 0.0, 0.0, 1.0];
        let nearest = ResampleMode::Nearest;
        let ceiled = ResampleMap::affine(moved, 40.0, nearest);
        assert_eq!(ceiled, ResampleMap::new(shifted, 40.0, nearest, 1, 1));
        assert_eq!(ceiled.map(|m| m.floor), Some(16 << 16));
    }

    /// Each entry from integers is held to `new`'s range: a, b, d, e under
    /// 2^31 either way — i32::MIN is past it —, c and f under 2^61.
    #[test]
    fn an_affine_map_from_integers_keeps_new_s_ranges() {
        let map = |entries| ResampleMap::affine(entries, 1.0, ResampleMode::Blend);
        let (narrow, wide) = ((1i128 << 31) - 1, (1i128 << 61) - 1);
        assert!(map([narrow, -narrow, wide, -narrow, narrow, -wide]).is_some());
        for at in 0..6 {
            let past = if at == 2 || at == 5 { wide + 1 } else { narrow + 1 };
            let mut entries = [1 << 20, 0, 0, 0, 1 << 20, 0];
            entries[at] = past;
            assert!(map(entries).is_none(), "{at} at {past}");
            entries[at] = -past;
            assert!(map(entries).is_none(), "{at} at -{past}");
        }
    }

    #[test]
    fn a_homography_is_divided_by_its_largest_corner_w() {
        // w = 1 + x/100 is 2 at the right-hand corners of 100 × 100.
        let inverse = [2.0, 0.0, 4.0, 0.0, 2.0, 0.0, 0.01, 0.0, 1.0];
        let m = ResampleMap::new(inverse, 1.0, ResampleMode::Blend, 100, 100).unwrap();
        assert_eq!((m.a, m.c, m.e), (1 << 20, 2 << 20, 1 << 20));
        // 0.005 · 2^36 = 343597383.68.
        assert_eq!((m.g, m.h, m.i, m.shift), (343_597_384, 0, 1 << 35, 0));
    }

    #[test]
    fn a_steep_homography_holds_g_and_h_by_the_least_shift() {
        // g = −1/16 is −2^32 at Q.36, past an i32, and −2^31 at Q.35 still
        // — q() counts the i32's least past it too: at Q.34, −2^30.
        let inverse = [1.0, 0.0, 0.0, -1.0 / 32.0, 0.0, 0.5, -1.0 / 16.0, 0.0, 1.0];
        let m = ResampleMap::new(inverse, 1.0, ResampleMode::Blend, 8, 1).unwrap();
        assert_eq!((m.g, m.h, m.i, m.shift), (-(1 << 30), 0, 1 << 36, 2));
        assert_eq!(m.words()[15], 2);
        // The same down the rows: h takes the shift where g takes none.
        let down = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, -1.0 / 16.0, 1.0];
        let m = ResampleMap::new(down, 1.0, ResampleMode::Blend, 1, 8).unwrap();
        assert_eq!((m.g, m.h, m.shift), (0, -(1 << 30), 2));
        // The steepest a map divided through can be: w = 1 − 2x falls to −1
        // across one column, and g = −2 is −2^30 at Q.29.
        let steepest = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -2.0, 0.0, 1.0];
        let m = ResampleMap::new(steepest, 1.0, ResampleMode::Blend, 1, 1).unwrap();
        assert_eq!((m.g, m.shift), (-(1 << 30), 7));
    }

    #[test]
    fn a_homography_and_its_negative_are_one_map() {
        // w = −1 − x/100 is −2 at the right-hand corners of 100 × 100 —
        // the quad tool's when the canvas origin is past the vanishing line.
        let inverse = [-2.0, 0.0, -4.0, 0.0, -2.0, 0.0, -0.01, 0.0, -1.0];
        let m = ResampleMap::new(inverse, 1.0, ResampleMode::Blend, 100, 100).unwrap();
        assert_eq!((m.a, m.c, m.g, m.i), (1 << 20, 2 << 20, 343_597_384, 1 << 35));
        let negated = inverse.map(|entry| -entry);
        assert_eq!(ResampleMap::new(negated, 1.0, ResampleMode::Blend, 100, 100), Some(m));
        // w = 0 at every corner lands nowhere.
        assert!(map([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]).is_none());
    }

    #[test]
    fn a_homography_is_positive_on_the_side_of_the_output_s_centre() {
        let over = |inverse| ResampleMap::new(inverse, 1.0, ResampleMode::Blend, 128, 1).unwrap();
        // w = 1 − x/32 is 1 at the left corners and −3 at the right:
        // divided by −3, w > 0 right of x = 32, the centre's side. 2^36/96
        // is 715827882.67, and −2^36/3 is −22906492245.33.
        let m = over([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0 / 32.0, 0.0, 1.0]);
        assert_eq!((m.a, m.g, m.i), (-349_525, 715_827_883, -22_906_492_245));
        // w = x/64 − 1 is −1 and 1, the centre on its horizon: the positive.
        let m = over([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0 / 64.0, 0.0, -1.0]);
        assert_eq!((m.a, m.g, m.i), (1 << 20, 1 << 30, -(1 << 36)));
    }

    #[test]
    fn an_affine_map_is_not_rescaled() {
        // Mode 2: the identity copies. The last word 0: affine.
        let m = map(IDENTITY).unwrap();
        assert_eq!(m.words(), [1 << 20, 0, 0, 1 << 20, 0, 0, 65_536, 2, 0, 0, 0, 0, 0, 16, 0, 0]);
    }

    #[test]
    fn a_whole_pixel_move_copies_in_either_mode() {
        let mode = |inverse: [f64; 9], asked| {
            ResampleMap::new(inverse, 1.0, asked, 100, 100).unwrap().words()[7]
        };
        let moved = [1.0, 0.0, -5.0, 0.0, 1.0, 3.0, 0.0, 0.0, 1.0];
        assert_eq!(mode(moved, ResampleMode::Blend), COPY);
        assert_eq!(mode(moved, ResampleMode::Pick), COPY);
        assert_eq!(mode(moved, ResampleMode::Nearest), COPY);
        // One part off a whole-pixel move each — a step of 2^-20 is one unit.
        let unit = 1.0 / 1_048_576.0;
        let under_q36 = 1.0 / (1u64 << 38) as f64;
        let off = [
            [1.0 + unit, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
            [1.0, unit, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
            [1.0, 0.0, -5.5, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
            [1.0, 0.0, 0.0, unit, 1.0, 0.0, 0.0, 0.0, 1.0],
            [1.0, 0.0, 0.0, 0.0, 1.0 - unit, 0.0, 0.0, 0.0, 1.0],
            [1.0, 0.0, 0.0, 0.0, 1.0, 3.0 + unit, 0.0, 0.0, 1.0],
            // w falling from 1 at the left: i stays 1, g is not 0.
            [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -unit, 0.0, 1.0],
            [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, -unit, 1.0],
            // g = 2^-38 rounds to 0, but dividing by the right-hand w,
            // 1 + 100 · 2^-38, leaves i 25 units under 1.
            [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, under_q36, 0.0, 1.0],
        ];
        for (n, inverse) in off.into_iter().enumerate() {
            assert_eq!(mode(inverse, ResampleMode::Pick), ResampleMode::Pick as u32, "{n}");
        }
    }

    // A pass's modes are its maps' mode words: a whole-pixel move asked of
    // any mode is the copy every pass holds, and adds none; the three
    // others together are every mode, each its own override.
    #[test]
    fn a_map_adds_its_mode_word_to_a_pass_s_modes() {
        let moved = |mode| ResampleMap::new(IDENTITY, 1.0, mode, 10, 10).unwrap();
        let turned = |mode| {
            let inverse = [0.8, -0.6, 3.0, 0.6, 0.8, 1.0, 0.0, 0.0, 1.0];
            ResampleMap::new(inverse, 1.0, mode, 10, 10).unwrap()
        };
        let none = ResampleModes::default();
        for mode in [ResampleMode::Blend, ResampleMode::Pick, ResampleMode::Nearest] {
            assert_eq!(none.with(&moved(mode).words()), none, "{mode:?}");
        }
        let of = |mode| none.with(&turned(mode).words()).constants().map(|(_, on)| on);
        assert_eq!(of(ResampleMode::Blend), [1.0, 0.0, 0.0]);
        assert_eq!(of(ResampleMode::Pick), [0.0, 1.0, 0.0]);
        assert_eq!(of(ResampleMode::Nearest), [0.0, 0.0, 1.0]);
        let every = [ResampleMode::Blend, ResampleMode::Pick, ResampleMode::Nearest]
            .into_iter()
            .fold(none, |modes, mode| modes.with(&turned(mode).words()));
        assert_eq!(every, ResampleModes::ALL);
        assert_eq!(ResampleModes::ALL.constants().map(|(_, on)| on), [1.0; 3]);
    }
}
