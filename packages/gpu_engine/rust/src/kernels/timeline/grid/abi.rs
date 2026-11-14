//! The frame grid's C ABI (grid-on-the-engine ①, 관제 2026-11-08 16:42):
//! the app hands a tile's op stream — the words `TimelineGridTileOpWriter`
//! writes — and the A8 atlas its GLYPH ops read its letters from, and the
//! engine draws them into a picture of its own that stays on the GPU for
//! the view's screen to lay: nothing comes back but whether it drew.

#[cfg(test)]
mod tests;

use crate::device::{Engine, let_go};
use crate::fail;
use crate::kernels::timeline::wave::{WavePeaks, WaveTile, WaveView, Waved};
use crate::platform::surface_format;

use super::lay::{GridLay, Laid};
use super::{ATLAS_SIDE, Drawn, GridPicture, GridTile, Put};

/// The tile pass, compiled here for the pictures it draws
/// (`gpu_engine_grid_pictures_new`) on the calling thread
/// ([`GridTile::for_pictures`]): an app asks off the thread its frames are
/// built on.
///
/// # Safety
/// `engine` is live; the pass is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_new(engine: *const Engine) -> *mut GridTile {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        engine.hands(GridTile::for_pictures(engine))
    })
}

/// The side of the square atlas a batch's letters are put on
/// (`gpu_engine_grid_flush`), in pixels: where its caller places them.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_grid_atlas_side() -> u32 {
    ATLAS_SIDE
}

/// The longest side of a picture `grid`'s device makes
/// (`gpu_engine_grid_pictures_new`): read as the pass was made, so a
/// caller asks its pictures within it where it asks them, and no trip.
///
/// # Safety
/// `grid` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_most_side(grid: *const GridTile) -> u32 {
    // SAFETY: see the function's contract.
    unsafe { &*grid }.most_side()
}

/// # Safety
/// `grid` came from `gpu_engine_grid_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_free(grid: *mut GridTile) {
    // SAFETY: see the function's contract.
    unsafe { let_go(grid) };
}

/// # Safety
/// `picture` came from `gpu_engine_grid_pictures_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_picture_free(picture: *mut GridPicture) {
    // SAFETY: see the function's contract.
    unsafe { let_go(picture) };
}

/// Copies `picture`'s pixels — straight RGBA8, row by row — into `bytes`
/// once the GPU is done, `capacity` of them at most. False on failure; see
/// the last error.
///
/// # Safety
/// `engine` and `picture` are live and `bytes` holds `capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_picture_read(
    engine: *const Engine,
    picture: *const GridPicture,
    bytes: *mut u8,
    capacity: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, picture) = unsafe { (&*engine, &*picture) };
    engine.on_thread(|| {
        let Some(read) = engine.read_texture(&picture.texture) else {
            return false;
        };
        let count = read.len().min(capacity);
        // SAFETY: `bytes` holds `capacity`, and `count` is no more.
        unsafe { std::ptr::copy_nonoverlapping(read.as_ptr(), bytes, count) };
        true
    })
}

/// Makes `count` clear pictures, the i-th `sizes[2i]` × `sizes[2i + 1]`
/// pixels, into `made` — on one trip to the engine's thread for all of
/// them. False, with none made, where a side is none or past what the
/// device makes; see the last error.
///
/// ↩️One picture a trip (`gpu_engine_grid_picture_new`): 🔬0.41 ms of a
/// cold tile's 3.3 on the main PC (measure-cold-tiles, 11-15).
///
/// # Safety
/// `engine` is live, `sizes` holds `2 × count` words and `made` room
/// for `count` pictures; each is freed before the engine.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_pictures_new(
    engine: *const Engine,
    sizes: *const u32,
    count: usize,
    made: *mut *mut GridPicture,
) -> bool {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        if count == 0 {
            return true;
        }
        // SAFETY: see the function's contract.
        let sizes = unsafe { std::slice::from_raw_parts(sizes, 2 * count) };
        let Some(pictures) = sizes
            .chunks_exact(2)
            .map(|side| GridPicture::new(engine, side[0], side[1]))
            .collect::<Option<Vec<_>>>()
        else {
            return false;
        };
        // SAFETY: see the function's contract.
        let made = unsafe { std::slice::from_raw_parts_mut(made, count) };
        for (slot, picture) in made.iter_mut().zip(pictures) {
            *slot = engine.hands(picture);
        }
        true
    })
}

/// A sound's view as `gpu_engine_grid_flush` hands it — eleven words, in
/// [`WaveView`]'s order, a bool and the unsigned ones as their bits.
fn view_of(words: &[i32]) -> WaveView {
    WaveView {
        along0: words[0],
        length: words[1],
        vertical: words[2] != 0,
        frame_q8: words[3],
        fps: (words[4] as u32, words[5] as u32),
        buckets_per_second: words[6] as u32,
        leading_frames: words[7],
        across_q8: words[8],
        gain_q16: words[9],
        rgba: words[10] as u32,
    }
}

/// THE GRID'S BATCH: puts `put_count` letters on `grid`'s atlas — the i-th
/// over `puts[4i .. 4i + 4]` (x, y, width, height), its bytes the next
/// width × height of `put_bytes` —, then draws `tile_count` streams into
/// their pictures over clear, the i-th `ops[ends[i - 1] .. ends[i]]`
/// (from 0) into `tiles[i]`, then lays `wave_count` sounds, the i-th
/// `peaks[i]` over what `waved[i]` holds as `views[11i .. 11i + 11]` shows
/// it ([`view_of`]): one trip to the engine's thread and one submit, not
/// waited for — what reads a picture after comes after it on the same
/// queue ([`GridTile::encode`], [`WaveTile::encode`]). False, with nothing
/// drawn, for letters, a stream or a view the passes refuse, and on
/// failure; see the last error. The letters are put then all the same.
///
/// ⚠️Over clear, always: a tile lays over its view's sheet (the store's
/// contract, timeline_grid_tile_store.dart), so the pass's background word
/// is nobody's to hand. A sound lays over what its picture holds: it is
/// baked into its row's cell tile (the-waveform-is-drawn-on-the-cpu-beside-
/// its-kernel-Q2, 유저 2026-11-14 「(가)」), and a screen copies what it
/// lays (lay.wgsl) — a picture of the wave's own laid over the cells'
/// would clear them.
///
/// ↩️A tile and a sound each were drawn on a trip and a submit of their own
/// (`gpu_engine_grid_draw`, `gpu_engine_wave_draw`; a-grid-row-paints-its-
/// cells-on-a-canvas-beside-its-tiles-Q2, 유저 2026-11-15 「(라)」).
///
/// # Safety
/// Every pointer is live, made on `engine`; `puts` holds `4 × put_count`
/// words and `put_bytes` their bytes, `tiles` and `ends` `tile_count`
/// each and `ops` the last end's words, `waved` and `peaks` `wave_count`
/// each and `views` `11 × wave_count` words.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_grid_flush(
    grid: *mut GridTile,
    wave: *mut WaveTile,
    engine: *const Engine,
    puts: *const u32,
    put_count: usize,
    put_bytes: *const u8,
    tiles: *const *const GridPicture,
    ends: *const u32,
    tile_count: usize,
    ops: *const i32,
    waved: *const *const GridPicture,
    peaks: *const *const WavePeaks,
    views: *const i32,
    wave_count: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (grid, wave, engine) = unsafe { (&mut *grid, &mut *wave, &*engine) };
    engine.on_thread(|| {
        // A slice of none: its pointer may be null, which no slice may be.
        fn held<'a, T>(from: *const T, count: usize) -> &'a [T] {
            match count {
                0 => &[],
                // SAFETY: the caller's contract holds `count` there.
                count => unsafe { std::slice::from_raw_parts(from, count) },
            }
        }
        let boxes = held(puts, 4 * put_count);
        let lengths: Vec<usize> = boxes.chunks_exact(4).map(|at| at[2] as usize * at[3] as usize).collect();
        let bytes = held(put_bytes, lengths.iter().sum());
        let mut from = 0;
        let letters: Vec<Put> = boxes
            .chunks_exact(4)
            .zip(&lengths)
            .map(|(at, &length)| {
                from += length;
                Put {
                    at: [at[0], at[1], at[2], at[3]],
                    bytes: &bytes[from - length..from],
                }
            })
            .collect();
        let ends = held(ends, tile_count);
        if ends.windows(2).any(|pair| pair[0] > pair[1]) {
            return fail("a batch's streams end before they begin");
        }
        let ops = held(ops, ends.last().map_or(0, |&end| end as usize));
        let tiles = held(tiles, tile_count);
        let drawn: Vec<Drawn> = tiles
            .iter()
            .zip(ends)
            .scan(0, |from, (&tile, &end)| {
                let stream = &ops[*from..end as usize];
                *from = end as usize;
                // SAFETY: each picture is live (the function's contract).
                let tile = unsafe { &(*tile).texture };
                Some(Drawn { tile, background: 0, ops: stream })
            })
            .collect();
        let sounds = held(peaks, wave_count);
        let waves: Vec<Waved> = held(waved, wave_count)
            .iter()
            .zip(sounds)
            .zip(held(views, 11 * wave_count).chunks_exact(11))
            .map(|((&tile, &peaks), view)| Waved {
                // SAFETY: each picture and sound is live (the contract).
                tile: unsafe { &(*tile).texture },
                peaks: unsafe { &*peaks },
                view: view_of(view),
            })
            .collect();
        grid.put_letters(engine, &letters)?;
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        grid.encode(engine, &mut encoder, &drawn)?;
        wave.encode(engine, &mut encoder, &waves)?;
        engine.queue.submit([encoder.finish()]);
        Some(())
    })
    .is_some()
}

/// The bytes `grid` and `wave` keep between their batches — the atlas,
/// the planes, the unders — for the memory census: their own counts, no
/// device asked.
///
/// # Safety
/// `grid` and `wave` are live, and no batch of theirs is under way.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_kept_bytes(grid: *const GridTile, wave: *const WaveTile) -> u64 {
    // SAFETY: see the function's contract.
    let (grid, wave) = unsafe { (&*grid, &*wave) };
    grid.kept_bytes() + wave.kept_bytes()
}

/// Lets go of what `grid` and `wave` keep between their batches — the OS
/// says memory is tight: the next batch makes its own, and the atlas holds
/// no letters till they are put again.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_let_go_kept(grid: *mut GridTile, wave: *mut WaveTile, engine: *const Engine) {
    // SAFETY: see the function's contract.
    let (grid, wave, engine) = unsafe { (&mut *grid, &mut *wave, &*engine) };
    engine.on_thread(|| {
        grid.let_go_kept();
        wave.let_go_kept();
    });
}

/// The screen pass that lays tiles on a view's screen ([`GridLay`]),
/// compiled for a format the first time it lays onto one, or ahead of it
/// (`gpu_engine_grid_lay_ready`).
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_lay_new(engine: *const Engine) -> *mut GridLay {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.hands(GridLay::new())
}

/// Compiles the pass for a screen of BGRA or RGBA 8-bit unorm texels — as
/// `gpu_engine_surface_new` makes for the same `bgra`, and a window is
/// RGBA — on the calling thread ([`GridLay::ready`]): an app asks off the
/// thread its frames are built on, and its first screen compiles nothing
/// there.
///
/// # Safety
/// `lay` and `engine` are live, and no other thread holds the pass.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_lay_ready(lay: *mut GridLay, engine: *const Engine, bgra: bool) {
    // SAFETY: see the function's contract.
    let (lay, engine) = unsafe { (&mut *lay, &*engine) };
    engine.on_thread(|| {
        lay.ready(engine, surface_format(bgra));
    })
}

/// # Safety
/// `lay` came from `gpu_engine_grid_lay_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_lay_free(lay: *mut GridLay) {
    // SAFETY: see the function's contract.
    unsafe { let_go(lay) };
}

/// The pixels `rect` of `target` — [left, top, right, bottom) — clear, and
/// the `count` tiles `pictures` laid over them, the i-th from `boxes[8i ..
/// 8i + 4]` of its own pixels onto `boxes[8i + 4 .. 8i + 8]` of the
/// screen's, each [left, top, right, bottom) ([`GridLay::lay`]); waits for
/// the GPU. `target` is what the view shows: a surface's texture
/// (`gpu_engine_surface_texture`) or a window's next image
/// (`gpu_engine_window_target`). False on failure; see the last error.
///
/// # Safety
/// Every pointer is live, made on `engine`; `rect` holds four words,
/// `pictures` `count` tiles and `boxes` `8 × count` doubles.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_lay(
    lay: *mut GridLay,
    engine: *const Engine,
    target: *const wgpu::Texture,
    rect: *const u32,
    pictures: *const *const GridPicture,
    boxes: *const f64,
    count: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (lay, engine, target) = unsafe { (&mut *lay, &*engine, &*target) };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let (rect, pictures, boxes) = unsafe {
            (
                *rect.cast::<[u32; 4]>(),
                std::slice::from_raw_parts(pictures, count),
                std::slice::from_raw_parts(boxes, 8 * count),
            )
        };
        let laid: Vec<Laid> = pictures
            .iter()
            .zip(boxes.chunks_exact(8))
            .map(|(&picture, edges)| Laid {
                // SAFETY: each tile is live (the function's contract).
                picture: unsafe { &*picture },
                from: [edges[0], edges[1], edges[2], edges[3]],
                onto: [edges[4], edges[5], edges[6], edges[7]],
            })
            .collect();
        lay.lay(engine, target, rect, &laid).is_some()
    })
}
