//! The fx plugin the host's tests open — built against the spec crate as a
//! maker builds one — and what its WebAssembly twin (src/tests/wasm.rs)
//! answers too.
//!
//! It inverts where its Amount is at least 50 and its Map's alpha (read at
//! the same canvas place, nothing outside the map) is over 127; with no Map
//! it inverts everywhere Amount allows. Amount below 0 answers a failure.
//! Its reach is Amount / 10 at the frame's scale, plus the frame's index,
//! plus its time in frames — a reach that comes back right has read the
//! values and every number of the frame.

use anicel_fx::{Ask, Effect, Failed, Job};

pub struct Invert;

impl Effect for Invert {
    const DESCRIPTION: &'static str = concat!(
        r#"{"spec":1,"id":"app.anicel.test.invert","name":"Invert","#,
        r#""vendor":"Anicel test","version":"1.0.0","can":["cpu"],"#,
        r#""params":[{"id":"amount","kind":"number","label":"Amount","#,
        r#""default":100,"min":0,"max":100},"#,
        r#"{"id":"map","kind":"layer","label":"Map"}]}"#,
    );

    fn reach(ask: &Ask<'_>) -> u32 {
        let moment = ask.moment;
        // A sum of unsigned words, wrapping as they do.
        ((ask.values[0].number() / 10.0 * moment.scale) as u32)
            .wrapping_add(moment.frame_index as u32)
            .wrapping_add((moment.time * moment.frame_rate + 0.5) as u32)
    }

    fn render(job: &mut Job<'_>) -> Result<(), Failed> {
        let amount = job.values[0].number();
        if amount < 0.0 {
            return Err(Failed);
        }
        let map = job.values[1].layer().and_then(|place| job.layers.get(place));
        let input = job.input;
        for y in 0..input.height {
            let (from, to) = (input.row(y), job.output.row_mut(y));
            for (x, (p, q)) in from.chunks(4).zip(to.chunks_mut(4)).enumerate() {
                let (at_x, at_y) = (input.left + x as i32, input.top + y as i32);
                let allows = map.is_none_or(|map| map.at(at_x, at_y).is_some_and(|m| m[3] > 127));
                let inverts = amount >= 50.0 && allows;
                for c in 0..3 {
                    q[c] = if inverts { p[3].wrapping_sub(p[c]) } else { p[c] };
                }
                q[3] = p[3];
            }
        }
        Ok(())
    }
}
