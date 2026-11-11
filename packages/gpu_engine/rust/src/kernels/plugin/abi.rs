//! The C ABI of a GPU fx plugin (fx spec 2 ㉯ ②, an-endless-plugin-
//! stalls-the-app): opened from its WGSL source on the engine's device,
//! asked its reach on the CPU and run over a picture — what the app's
//! `FxPluginRunner` asks of it. A picture is straight RGBA8, a word a
//! pixel as the engine's pool holds it, row by row; a place is canvas
//! pixels. The doubles the app works out become the plugin's integers
//! here, once (design ③): past this file the plugin sees integers alone.

use fx_wgsl::{Cut, Frame};

use super::Plugin;
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{q, sixteen_bit};

/// A value's kind, which says how its four doubles become the four words
/// the plugin reads (prelude.wgsl's `AnicelFrame`): a whole number — a
/// menu's choice, a checkbox's 0 or 1, a layer's slot or -1.
pub(crate) const WHOLE: u32 = 0;
/// Q.16 — a number, an angle, a length in pixels, a point's canvas pixels.
pub(crate) const FIXED: u32 = 1;
/// 16 bits a channel — a colour's four, each on 0..=1.
pub(crate) const CHANNELS: u32 = 2;

/// Past what an i32 holds: the plugin reads each word as one.
const WORD: f64 = 2_147_483_648.0;

/// What a plugin is asked with: its values' words, four a parameter, and
/// the moment's four — the frame's number, then its time in seconds, the
/// frames a second and the output pixels a canvas pixel, each in Q.16.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct Asked {
    pub(crate) values: Vec<[i32; 4]>,
    pub(crate) moment: [i32; 4],
}

impl Asked {
    /// The words of `values` — four doubles a parameter, its kind in
    /// `kinds` — and of `moment`; none where one is past an i32 or a kind
    /// is none of the three (the last error says which).
    pub(crate) fn new(values: &[f64], kinds: &[u32], moment: [f64; 4]) -> Option<Self> {
        let mut words = Vec::with_capacity(kinds.len());
        for (index, (four, &kind)) in values.chunks_exact(4).zip(kinds).enumerate() {
            let fraction = match kind {
                WHOLE => Some(0),
                FIXED => Some(16),
                CHANNELS => None,
                _ => return fail(format!("value {index} is of kind {kind}, none the host knows")),
            };
            let mut word = [0; 4];
            for (word, &x) in word.iter_mut().zip(four) {
                *word = match fraction {
                    Some(k) => fixed(x, k, || format!("value {index}"))?,
                    None => sixteen_bit(x) as i32,
                };
            }
            words.push(word);
        }
        let [frame, time, rate, scale] = moment;
        let moment = [
            fixed(frame, 0, || "the frame's number".into())?,
            fixed(time, 16, || "the time".into())?,
            fixed(rate, 16, || "the frame rate".into())?,
            fixed(scale, 16, || "the scale".into())?,
        ];
        Some(Asked { values: words, moment })
    }

    /// The frame a run over `rect` — (left, top, width, height), the input
    /// and the output alike — is handed, each invocation's `fuel` its own.
    fn frame<'a>(&'a self, rect: [i32; 4], fuel: u32, input: &'a [u32], rows: &'a [u32]) -> Frame<'a> {
        let [left, top, width, height] = rect;
        let [frame, time_q16, rate_q16, scale_q16] = self.moment;
        Frame {
            out_origin: [left, top],
            out_size: [width, height],
            in_origin: [left, top],
            in_size: [width, height],
            frame,
            time_q16,
            rate_q16,
            scale_q16,
            fuel,
            input,
            rows,
            values: &self.values,
        }
    }
}

/// `x` with `k` bits of fraction as an i32, or none where it is past one
/// — `what` it is named in the last error.
fn fixed(x: f64, k: u32, what: impl FnOnce() -> String) -> Option<i32> {
    match q(x, k, WORD) {
        Some(word) => Some(word as i32),
        None => fail(format!("{} is {x}, past an i32 in Q.{k}", what())),
    }
}

/// The pictures — each `rects`' (left, top, width, height), their pixels
/// one after another in `pixels` — laid on `on`'s grid, a plane each, as
/// `anicel_row` reads them: transparent where a picture has no pixel.
pub(crate) fn planes(pixels: &[u32], rects: &[[i32; 4]], on: [i32; 4]) -> Vec<u32> {
    let [left, top, width, height] = on;
    let plane = width as usize * height as usize;
    let mut planes = vec![0; plane * rects.len()];
    let mut from = 0;
    for (slot, &[x0, y0, columns, rows]) in rects.iter().enumerate() {
        for y in 0..rows {
            for x in 0..columns {
                let (column, row) = (x0 + x - left, y0 + y - top);
                if (0..width).contains(&column) && (0..height).contains(&row) {
                    let at = (row * width + column) as usize;
                    planes[slot * plane + at] = pixels[from + (y * columns + x) as usize];
                }
            }
        }
        from += columns as usize * rows as usize;
    }
    planes
}

/// The words a picture of `rect` holds, or none where a side is negative.
fn area(rect: [i32; 4]) -> Option<usize> {
    let [_, _, width, height] = rect;
    if width < 0 || height < 0 {
        return fail(format!("a picture {width} by {height}"));
    }
    Some(width as usize * height as usize)
}

/// Opens the plugin whose WGSL is `source`'s `length` bytes of UTF-8 on
/// `engine`: checked and counted (fx_wgsl), then compiled by the device —
/// null where any refuses it, the last error saying why.
///
/// # Safety
/// `engine` is live; `source` holds `length` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plugin_open(engine: *const Engine, source: *const u8, length: usize) -> *mut Plugin {
    // SAFETY: see the function's contract.
    let (engine, source) = unsafe { (&*engine, std::slice::from_raw_parts(source, length)) };
    opened(engine, source).map_or(std::ptr::null_mut(), |plugin| Box::into_raw(Box::new(plugin)))
}

fn opened(engine: &Engine, source: &[u8]) -> Option<Plugin> {
    let Ok(source) = std::str::from_utf8(source) else {
        return fail("the plugin's source is no UTF-8");
    };
    let opened = fx_wgsl::open(source).map_err(|refusal| refusal.to_string());
    match opened.and_then(|kernel| Plugin::open(engine, kernel)) {
        Ok(plugin) => Some(plugin),
        Err(why) => fail(why),
    }
}

/// # Safety
/// `plugin` came from `gpu_engine_plugin_open`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plugin_free(plugin: *mut Plugin) {
    if !plugin.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(plugin) });
    }
}

/// How far past its input the plugin reaches, in output pixels, for its
/// `count` values — four doubles each in `values`, its kind in `kinds`
/// ([`WHOLE`], [`FIXED`] or [`CHANNELS`]) — at `moment`'s four (the
/// frame's number, its time in seconds, the frames a second, the output
/// pixels a canvas pixel), on `share` — an invocation's, as a pixel's is
/// (the reach is a call too); -1 where a value does not fit or the reach
/// spent its share (the last error says).
///
/// # Safety
/// `plugin` is live; `values` holds `4 * count` doubles, `kinds` `count`
/// and `moment` four.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plugin_reach(
    plugin: *const Plugin,
    values: *const f64,
    kinds: *const u32,
    count: usize,
    moment: *const f64,
    share: u32,
) -> i64 {
    // SAFETY: see the function's contract.
    let (plugin, values, kinds, moment) = unsafe {
        (
            &*plugin,
            std::slice::from_raw_parts(values, 4 * count),
            std::slice::from_raw_parts(kinds, count),
            *moment.cast::<[f64; 4]>(),
        )
    };
    let Some(asked) = Asked::new(values, kinds, moment) else {
        return -1;
    };
    match plugin.reach(&asked.frame([0; 4], share, &[], &[])) {
        Ok(reach) => i64::from(reach),
        Err(Cut) => {
            fail::<()>(format!("the plugin's reach spent its share of {share} and was cut"));
            -1
        }
    }
}

/// Runs the plugin over the first of `pictures` + 1 pictures — each
/// `rects`' (left, top, width, height), four words a picture, their pixels
/// one after another in `pixels` — into `output`, a word a pixel of the
/// first's size and place, transparent where the render writes none. The
/// pictures after the first are the layers its layer values name, by
/// slot. The values and moment are as `gpu_engine_plugin_reach` takes
/// them; each pixel's share is `share`, however many there are. 0 where it
/// drew, -1 where a value does not fit, the run was cut or the device
/// failed (the last error says).
///
/// 🗣️an-endless-plugin-stalls-the-app-Q19 (유저 2026-11-10 16:36): 「화소
/// 하나의 몫으로 고정하고, 그리기를 덩어리로 나눠 넘긴다」 — ↩️the share was
/// the limit over the pixels (Q5) till then, so the same plugin was cut
/// first on the biggest picture: a 3×3 blur was all a 4K frame allowed.
///
/// # Safety
/// `plugin` and `engine` are live, `plugin` opened on `engine`; `rects`
/// holds `4 * (layers + 1)` words, `pixels` each rect's width × height one
/// after another, `values` `4 * count` doubles, `kinds` `count`, `moment`
/// four and `output` the first rect's width × height.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plugin_render(
    plugin: *const Plugin,
    engine: *const Engine,
    pixels: *const u32,
    rects: *const i32,
    layers: usize,
    values: *const f64,
    kinds: *const u32,
    count: usize,
    moment: *const f64,
    share: u32,
    output: *mut u32,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plugin, engine, rects, values, kinds, moment) = unsafe {
        (
            &*plugin,
            &*engine,
            std::slice::from_raw_parts(rects.cast::<[i32; 4]>(), layers + 1),
            std::slice::from_raw_parts(values, 4 * count),
            std::slice::from_raw_parts(kinds, count),
            *moment.cast::<[f64; 4]>(),
        )
    };
    let Some(areas) = rects.iter().map(|&rect| area(rect)).collect::<Option<Vec<_>>>() else {
        return -1;
    };
    // SAFETY: see the function's contract — `pixels` and `output` hold
    // what the rects say, each now known to be no negative area.
    let (pixels, output) = unsafe {
        (std::slice::from_raw_parts(pixels, areas.iter().sum()), std::slice::from_raw_parts_mut(output, areas[0]))
    };
    let Some(asked) = Asked::new(values, kinds, moment) else {
        return -1;
    };
    let (input, layered) = pixels.split_at(areas[0]);
    let rows = planes(layered, &rects[1..], rects[0]);
    let frame = asked.frame(rects[0], share, input, &rows);
    output.fill(0);
    match plugin.render(engine, &frame, output) {
        Some(Ok(())) => 0,
        Some(Err(Cut)) => {
            fail::<()>(format!("the plugin spent each pixel's share of {share} and was cut"));
            -1
        }
        None => -1,
    }
}
