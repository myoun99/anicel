//! The C ABI of a GPU fx plugin (fx spec 2 ㉯ ②, an-endless-plugin-
//! stalls-the-app): opened from its WGSL source on the engine's device,
//! asked its reach on the CPU and run over a chain's tiles where they lie
//! on the device — what the app's `FxPluginRunner` asks of it —, what it
//! made landed in the pool as a stroke's is. A pixel is straight RGBA8, a
//! word as the engine's pool holds it. The doubles the app works out become
//! the plugin's integers here, once (design ③): past this file the plugin
//! sees integers alone.

use fx_wgsl::{Cut, Frame};

use super::{Plugin, PluginMade, Tiled};
use crate::device::{Engine, let_go};
use crate::fail;
use crate::kernels::chain::{ChainRead, Kept};
use crate::kernels::dab::abi::reported;
use crate::kernels::dab::landing::placed;
use crate::kernels::effects::blur::TileRect;
use crate::kernels::pool::{Cel, Pool};
use crate::kernels::shared::{q, sixteen_bit};
use crate::kernels::write::Change;

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
/// null where any refuses it, the last error saying why. Where `cut` is
/// false the device compiles it with no charge, so no run of it is cut
/// there (fx_wgsl's `open_uncut`, 🗣️-Q18).
///
/// # Safety
/// `engine` is live; `source` holds `length` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plugin_open(
    engine: *const Engine,
    source: *const u8,
    length: usize,
    cut: bool,
) -> *mut Plugin {
    // SAFETY: see the function's contract.
    let (engine, source) = unsafe { (&*engine, std::slice::from_raw_parts(source, length)) };
    engine.on_thread(|| {
        opened(engine, source, cut).map_or(std::ptr::null_mut(), |plugin| engine.hands(plugin))
    })
}

fn opened(engine: &Engine, source: &[u8], cut: bool) -> Option<Plugin> {
    let Ok(source) = std::str::from_utf8(source) else {
        return fail("the plugin's source is no UTF-8");
    };
    let read = if cut { fx_wgsl::open(source) } else { fx_wgsl::open_uncut(source) };
    match read.map_err(|refusal| refusal.to_string()).and_then(|kernel| Plugin::open(engine, kernel)) {
        Ok(plugin) => Some(plugin),
        Err(why) => fail(why),
    }
}

/// # Safety
/// `plugin` came from `gpu_engine_plugin_open`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plugin_free(plugin: *mut Plugin) {
    // SAFETY: see the function's contract.
    unsafe { let_go(plugin) };
}

/// Whether the plugin reads the moment — the frame's number or its time
/// (fx_wgsl's `Kernel::reads_the_moment`): what the app signs a run of
/// it with (`FxPluginRun`).
///
/// # Safety
/// `plugin` came from `gpu_engine_plugin_open`, and is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plugin_reads_the_moment(plugin: *const Plugin) -> bool {
    // SAFETY: see the function's contract.
    unsafe { &*plugin }.kernel.reads_the_moment()
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

/// Runs the plugin over what `read` kept of a chain ([`Op::Read`]) — its
/// tiles, and its rows' as the layers its layer values name, by slot — at
/// `picture`'s (left, top, width, height), the input and the output alike,
/// in the plug-in's pixels: the paper's, which lie `at` (two words) from
/// the tiles' grid. Returns what it made on the device, the chain's
/// rectangle of tiles — written to `rect` (column, row, columns, rows) —
/// clear past the picture and wherever its alpha is 0, for the app to land
/// ([`gpu_engine_plugin_made_land`]); null where a value does not fit, the
/// picture has a negative side, no plan ran through `read`, the run was cut
/// or the device failed (the last error says). The values and moment are
/// as `gpu_engine_plugin_reach` takes them; each pixel's share is `share`,
/// however many there are — for a plugin opened not to be cut, what its
/// chunks are sized for alone. ⚠️Waits for the GPU a batch of chunks at a
/// time, the cut read after each: the app asks it on a worker.
///
/// 🗣️an-endless-plugin-stalls-the-app-Q19 (유저 2026-11-10 16:36): 「화소
/// 하나의 몫으로 고정하고, 그리기를 덩어리로 나눠 넘긴다」 — ↩️the share was
/// the limit over the pixels (Q5) till then, so the same plugin was cut
/// first on the biggest picture: a 3×3 blur was all a 4K frame allowed.
///
/// ↩️Till 2026-11-15 the app read the chain back to the CPU, read each
/// row's tiles there, handed both here and read what it made back again,
/// to put it as bytes (a-plugin-step-goes-through-the-cpu-and-back).
///
/// [`Op::Read`]: crate::kernels::chain::Op::Read
///
/// # Safety
/// `plugin`, `engine` and `read` are live, `plugin` opened on `engine`;
/// `picture` holds four words, `at` two, `values` `4 * count` doubles,
/// `kinds` `count`, `moment` four and `rect` four writable words.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_plugin_render_read(
    plugin: *const Plugin,
    engine: *const Engine,
    read: *const ChainRead,
    picture: *const i32,
    at: *const i32,
    values: *const f64,
    kinds: *const u32,
    count: usize,
    moment: *const f64,
    share: u32,
    rect: *mut i32,
) -> *mut PluginMade {
    // SAFETY: see the function's contract.
    let (plugin, engine, read, picture, at, values, kinds, moment) = unsafe {
        (
            &*plugin,
            &*engine,
            &*read,
            *picture.cast::<[i32; 4]>(),
            *at.cast::<[i32; 2]>(),
            std::slice::from_raw_parts(values, 4 * count),
            std::slice::from_raw_parts(kinds, count),
            *moment.cast::<[f64; 4]>(),
        )
    };
    engine.on_thread(|| {
        let made = area(picture)
            .and_then(|_| Asked::new(values, kinds, moment))
            .and_then(|asked| {
                let Kept { tiles, rect, rows } = read.kept()?;
                let frame = asked.frame(picture, share, &[], &[]);
                let rows: Vec<Tiled> =
                    rows.iter().map(|tiles| Tiled { tiles: tiles.buffer(), rect }).collect();
                match plugin.render_tiled(engine, &frame, at, Tiled { tiles: tiles.buffer(), rect }, &rows)? {
                    Ok(tiles) => Some(PluginMade { rect, tiles }),
                    Err(Cut) => fail(format!("the plugin spent each pixel's share of {share} and was cut")),
                }
            });
        let Some(made) = made else {
            return std::ptr::null_mut();
        };
        let TileRect { x0, y0, columns, rows } = made.rect;
        // SAFETY: `rect` holds four writable words.
        unsafe { *rect.cast::<[i32; 4]>() = [x0, y0, columns as i32, rows as i32] };
        engine.hands(made)
    })
}

/// Puts each of `made`'s tiles that `asks` names — its column and row on
/// the grid, `count` of them — in a fresh slot of `cel`, as a landing puts
/// what it made ([`placed`]): the engine's alone, with no wait for the
/// GPU. Returns as [`gpu_engine_stroke_land`] does, each landed inked.
///
/// ↩️The letters' plate landed so too, its own entry over the one door,
/// till its laying went to the engine's thread unwaited
/// (`gpu_engine_letters_land`, 2026-11-18).
///
/// [`gpu_engine_stroke_land`]: crate::kernels::dab::abi::gpu_engine_stroke_land
///
/// # Safety
/// `engine`, `made` and `pool` are live, the pool made on `engine`; `asks`
/// holds `2 × count`, and `places` and `changes` hold `count`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_plugin_made_land(
    engine: *const Engine,
    made: *const PluginMade,
    pool: *mut Pool,
    cel: u32,
    asks: *const i32,
    count: usize,
    places: *mut u32,
    changes: *mut u8,
    inks: *mut i32,
) -> isize {
    // SAFETY: see the function's contract.
    let (engine, made, pool) = unsafe { (&*engine, &*made, &mut *pool) };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let asks = unsafe { std::slice::from_raw_parts(asks, 2 * count) };
        let landed = asks
            .chunks_exact(2)
            .map(|tile| made.rect.index_of(tile[0], tile[1]))
            .collect::<Option<Vec<usize>>>()
            .and_then(|indices| {
                let inked = indices.into_iter().map(|index| (index, Change::Inked));
                placed(engine, (pool, Cel(cel)), &made.tiles, inked)
            });
        // SAFETY: see the function's contract.
        unsafe { reported(landed, places, changes, inks) }
    })
}

/// # Safety
/// `made` came from `gpu_engine_plugin_render_read`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plugin_made_free(made: *mut PluginMade) {
    // SAFETY: see the function's contract.
    unsafe { let_go(made) };
}
