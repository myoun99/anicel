//! Shadow — an example Anicel fx plugin.
//!
//! SPDX-License-Identifier: MIT
//! Copyright (c) 2026 PARK GUNWOO — the Anicel fx plugin SDK's LICENSE.
//!
//! Draws the row's picture over a shadow of itself: the picture's alpha,
//! moved by an offset and painted in a color. It shows the parts most
//! plugins need — parameters of a few kinds, a reach (the shadow lands
//! outside the picture), the frame's scale, and premultiplied pixels.

use anicel_fx::{Ask, Effect, Failed, Job, Value};

struct Shadow;

// The values, in the order of "params".
const X: usize = 0;
const Y: usize = 1;
const COLOR: usize = 2;

impl Effect for Shadow {
    const DESCRIPTION: &'static str = concat!(
        r#"{"spec":1,"id":"com.example.shadow","name":"Shadow","#,
        r#""vendor":"Anicel SDK example","version":"1.0.0","#,
        r#""can":["cpu"],"params":["#,
        r#"{"id":"x","kind":"number","label":"Offset X","#,
        r#""default":8,"min":-200,"max":200},"#,
        r#"{"id":"y","kind":"number","label":"Offset Y","#,
        r#""default":8,"min":-200,"max":200},"#,
        r#"{"id":"color","kind":"color","label":"Color","#,
        r#""default":[0,0,0,0.6]}]}"#,
    );

    /// The shadow lands as far outside the picture as it is moved.
    fn reach(ask: &Ask<'_>) -> u32 {
        let (dx, dy) = offset(ask.values, ask.moment.scale);
        dx.unsigned_abs().max(dy.unsigned_abs())
    }

    fn render(job: &mut Job<'_>) -> Result<(), Failed> {
        let [red, green, blue, alpha] = job.values[COLOR].color().map(byte_of);
        let (dx, dy) = offset(job.values, job.moment.scale);
        let input = job.input;
        for y in 0..input.height {
            let (from, to) = (input.row(y), job.output.row_mut(y));
            for (x, (p, q)) in from.chunks(4).zip(to.chunks_mut(4)).enumerate() {
                // The shadow here is the picture's alpha where the offset
                // came from.
                let (sx, sy) = (x as i64 - i64::from(dx), i64::from(y) - i64::from(dy));
                let cast = input.get(sx, sy).map_or(0, |pixel| pixel[3]);
                let a = times(u32::from(cast), alpha);
                // The picture over its shadow, both premultiplied.
                let behind = 255 - u32::from(p[3]);
                for (c, shade) in [red, green, blue].into_iter().enumerate() {
                    q[c] = (u32::from(p[c]) + times(times(shade, a), behind)) as u8;
                }
                q[3] = (u32::from(p[3]) + times(a, behind)) as u8;
            }
        }
        Ok(())
    }
}

anicel_fx::export!(Shadow);

/// The offset in output pixels: the values are canvas pixels, and a draft
/// renders at a scale below 1.
fn offset(values: &[Value], scale: f64) -> (i32, i32) {
    (rounded(values[X].number() * scale), rounded(values[Y].number() * scale))
}

/// To the nearest whole pixel, halves away from zero.
fn rounded(value: f64) -> i32 {
    (if value < 0.0 { value - 0.5 } else { value + 0.5 }) as i32
}

/// A color's part from 0 to 1, as a byte.
fn byte_of(unit: f64) -> u32 {
    if unit <= 0.0 {
        0
    } else if unit >= 1.0 {
        255
    } else {
        (unit * 255.0 + 0.5) as u32
    }
}

/// a × b / 255, rounded — the product of two 8-bit fractions.
fn times(a: u32, b: u32) -> u32 {
    let t = a * b + 128;
    (t + (t >> 8)) >> 8
}
