//! The letters' C ABI (cel-number-on-the-engine-letters): the app hands
//! the engine its faces once — each family's files, families in the order
//! a letter goes down them — and a picture of letters a pass at a time,
//! each run as the app's layout set it, and lands what they make — the
//! straight RGBA8 tiles of one rectangle of the grid — in a pool's slots,
//! which the app holds as it holds a row's picture. Where a letter stands is the app's to say
//! ([`Run`]); which glyphs it takes and how they raster, the engine's.

#[cfg(test)]
mod tests;

use std::path::Path;
use std::sync::Arc;

use read_fonts::model::Blob;

use crate::device::{Engine, hands_bytes, let_go_bytes, taken_bytes};
use crate::fail;
use crate::kernels::composite::Composite;
use crate::kernels::dab::abi::reported;
use crate::kernels::pool::{Cel, Pool, Writing};
use crate::kernels::write::Change;

use super::glyphs::{Affine, Cluster, Faces, Family, Paint, Placed, Run, Shape, WEIGHTS};
use super::mapped::mapped;
use super::{Covered, Pass, lettered, set, words};

/// A picture of letters as the app builds it: its passes, bottom to top,
/// and their covers as they stood when last covered
/// ([`gpu_engine_letters_cover`]) — none where they cover no pixel.
#[derive(Default)]
pub(crate) struct Lettering {
    passes: Vec<Pass>,
    covered: Option<Arc<Covered>>,
}

impl Lettering {
    /// The pass the shapes being added go to.
    fn last(&mut self) -> Option<&mut Pass> {
        match self.passes.last_mut() {
            Some(pass) => Some(pass),
            None => fail("a shape is added to a pass — none was begun"),
        }
    }
}

/// False, `message` the last error.
fn refused(message: impl Into<String>) -> bool {
    fail::<()>(message);
    false
}

/// Null, `message` the last error.
fn none<T>(message: impl Into<String>) -> *mut T {
    fail::<()>(message);
    std::ptr::null_mut()
}

/// # Safety
/// `at` is null or holds six floats: a, b, c, d, e, f.
unsafe fn affine(at: *const f32) -> Option<Affine> {
    if at.is_null() {
        return fail("a shape stands somewhere — no placement was given");
    }
    // SAFETY: see the function's contract.
    let [a, b, c, d, e, f] = unsafe { *at.cast::<[f32; 6]>() };
    Some(Affine { a, b, c, d, e, f })
}

/// The faces being handed to the engine a file at a time
/// ([`gpu_engine_faces_file`], [`gpu_engine_faces_file_at`]), each
/// family's files together, till [`gpu_engine_faces_of`] sets them up —
/// and the first thing it refused.
#[derive(Default)]
pub struct FacesHanded {
    families: Vec<Vec<Blob>>,
    refused: Option<String>,
}

impl FacesHanded {
    /// `file` as one of family `family`'s: 0 first and each one the last's
    /// or the next — else refused.
    fn hand(&mut self, family: u32, file: Blob) {
        if self.refused.is_some() {
            return;
        }
        let families = &mut self.families;
        if family as usize == families.len() {
            families.push(Vec::new());
        } else if family as usize + 1 != families.len() {
            self.refused = Some(format!("family {family} is not the last one's nor the next"));
            return;
        }
        families.last_mut().expect("pushed above").push(file);
    }
}

/// Nothing handed yet: what [`gpu_engine_faces_file`] is handed each file
/// into, and [`gpu_engine_faces_of`] takes.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_faces_handed() -> *mut FacesHanded {
    hands_bytes(FacesHanded::default())
}

/// Copies a file — `length` bytes at `bytes`, alive for the call — into
/// `handed` as one of family `family`'s: 0 first and each one the last's
/// or the next, so a family's files lie together in the order its family
/// is handed over. What it refuses, [`gpu_engine_faces_of`] says.
///
/// ⛔ONE COPY: the app calls this as a leaf, handing the bytes its bundle
/// read where they lie, and this copy is the only one made — the app held
/// them in a block it zeroed and filled first, and the engine copied that
/// (🔬저장 11-14, the surface's AOT profiler: 35 MB three times over, a
/// 50–120 ms stop of the UI the first time letters were set). ⚠️Nothing
/// here may call back into the app's runtime, as no leaf may. A file that
/// is a file on the device is mapped instead, and copied by no one
/// ([`gpu_engine_faces_file_at`]).
///
/// # Safety
/// `handed` came from [`gpu_engine_faces_handed`] and is not yet set up;
/// `bytes` holds `length`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_faces_file(
    handed: *mut FacesHanded,
    family: u32,
    bytes: *const u8,
    length: usize,
) {
    // SAFETY: see the function's contract.
    let handed = unsafe { &mut *handed };
    // SAFETY: see the function's contract.
    let bytes = unsafe { std::slice::from_raw_parts(bytes, length) };
    handed.hand(family, Blob::from(bytes.to_vec()));
}

/// Maps the file at `path` — UTF-8, `length` bytes, alive for the call —
/// into `handed` as one of family `family`'s, as [`gpu_engine_faces_file`]
/// copies one: its bytes the file's own pages, read-only, shared with
/// whoever else maps it — the app's bundled faces are mapped by Flutter
/// too — and so in none of the process' own memory (`mapped`). False,
/// and nothing handed, where the file cannot be mapped: the app hands its
/// bytes instead.
///
/// 🗣️유저 (engine-fonts-held-twice): 「사본이나 ram에있는걸 최대한
/// 없애고싶어서」 — the copy [`gpu_engine_faces_file`] makes was the
/// faces' only one in the process (🔬공통 11-21, a Windows release run).
///
/// # Safety
/// `handed` came from [`gpu_engine_faces_handed`] and is not yet set up;
/// `path` holds `length`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_faces_file_at(
    handed: *mut FacesHanded,
    family: u32,
    path: *const u8,
    length: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let handed = unsafe { &mut *handed };
    // SAFETY: see the function's contract.
    let path = unsafe { std::slice::from_raw_parts(path, length) };
    let Some(file) = std::str::from_utf8(path).ok().and_then(|path| mapped(Path::new(path))) else {
        return false;
    };
    handed.hand(family, file);
    true
}

/// The faces letters are set in, of the files `handed` was handed — which
/// it takes and lets go of. Null on failure; see the last error.
///
/// # Safety
/// `handed` came from [`gpu_engine_faces_handed`] and is set up once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_faces_of(handed: *mut FacesHanded) -> *mut Faces {
    // SAFETY: see the function's contract.
    let FacesHanded { families, refused } = unsafe { taken_bytes(handed) };
    if let Some(why) = refused {
        return none(why);
    }
    let mut set_in = Vec::with_capacity(families.len());
    for (family, files) in families.into_iter().enumerate() {
        let Some(faces) = Family::of_files(files) else {
            return none(format!("family {family} holds no face"));
        };
        set_in.push(faces);
    }
    Faces::new(set_in).map_or(std::ptr::null_mut(), hands_bytes)
}

/// The families of `faces` in the order `order` names them — `count`
/// places, each where a family stands in `faces` —, sharing their files:
/// let go of on its own, before `faces` or after. Null on failure; see the
/// last error.
///
/// # Safety
/// `faces` came from [`gpu_engine_faces_of`] or this, and `order` holds
/// `count`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_faces_ordered(faces: *const Faces, order: *const u32, count: usize) -> *mut Faces {
    // SAFETY: see the function's contract.
    let (faces, order) = unsafe { (&*faces, std::slice::from_raw_parts(order, count)) };
    faces.ordered(order).map_or(std::ptr::null_mut(), hands_bytes)
}

/// # Safety
/// `faces` came from `gpu_engine_faces_of` or `gpu_engine_faces_ordered`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_faces_free(faces: *mut Faces) {
    // SAFETY: see the function's contract.
    unsafe { let_go_bytes(faces) };
}

/// A picture of letters of no pass.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_letters_new() -> *mut Lettering {
    hands_bytes(Lettering::default())
}

/// # Safety
/// `letters` came from `gpu_engine_letters_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_letters_free(letters: *mut Lettering) {
    // SAFETY: see the function's contract.
    unsafe { let_go_bytes(letters) };
}

/// Begins a pass over the ones before it: its shapes in `colour` —
/// straight RGBA8, A<<24|B<<16|G<<8|R, its alpha the pass's strength —,
/// `hard` or not (`TextLetterStyle.antialias` off), filled where
/// `outline` is 0 and else outlined that wide, 1/64 px of the layout.
/// False on failure; see the last error.
///
/// # Safety
/// `letters` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_letters_pass(
    letters: *mut Lettering,
    colour: u32,
    hard: bool,
    outline: i32,
) -> bool {
    // SAFETY: see the function's contract.
    let letters = unsafe { &mut *letters };
    let paint = match outline {
        0 => Paint::Fill,
        width if width > 0 => Paint::Stroke { width },
        width => return refused(format!("an outline {width} wide")),
    };
    letters.passes.push(Pass {
        colour,
        hard,
        paint,
        shapes: Vec::new(),
    });
    true
}

/// Adds to the pass begun last a run of letters in one style — `size`
/// 64ths of a px, `weight` — `FontWeight`'s, 1 to 1000 — and `italic` —
/// standing in the layout where `at` puts its own space: `text`, `length`
/// bytes of UTF-8, cut into `count` clusters, the i-th ending at byte
/// `ends[i]` and set with its box's left and its line's baseline at
/// `origins[2i]`, `origins[2i + 1]`, 64ths of a px. False on failure; see
/// the last error.
///
/// # Safety
/// `letters` is live, `at` holds six floats, `text` holds `length` bytes
/// and `ends` `count` words, `origins` `2 × count`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_letters_run(
    letters: *mut Lettering,
    at: *const f32,
    size: i32,
    weight: u32,
    italic: bool,
    text: *const u8,
    length: usize,
    ends: *const u32,
    origins: *const i32,
    count: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (letters, at) = unsafe { (&mut *letters, affine(at)) };
    let Some(at) = at else {
        return false;
    };
    // SAFETY: see the function's contract.
    let Some(run) = (unsafe { run_of(size, weight, italic, text, length, ends, origins, count) }) else {
        return false;
    };
    let Some(pass) = letters.last() else {
        return false;
    };
    pass.shapes.push(Placed {
        at,
        shape: Shape::Letters(run),
    });
    true
}

/// `weight` as a run takes it — None, with the last error, for one that is
/// no `FontWeight`'s.
fn weight_of(weight: u32) -> Option<u16> {
    match u16::try_from(weight) {
        Ok(weight) if WEIGHTS.contains(&weight) => Some(weight),
        _ => fail(format!("a weight of {weight}: a run's is 1 to 1000")),
    }
}

/// `text`, `length` bytes of UTF-8, cut into `count` clusters, the i-th
/// ending at byte `ends[i]` and set at `origins[2i]`, `origins[2i + 1]`.
/// None on failure; see the last error.
///
/// # Safety
/// `text` holds `length` bytes, `ends` `count` words and `origins`
/// `2 × count`.
unsafe fn clusters_of(
    text: *const u8,
    length: usize,
    ends: *const u32,
    origins: *const i32,
    count: usize,
) -> Option<Vec<Cluster>> {
    // SAFETY: see the function's contract.
    let (bytes, ends, origins) = unsafe {
        (
            std::slice::from_raw_parts(text, length),
            std::slice::from_raw_parts(ends, count),
            std::slice::from_raw_parts(origins, 2 * count),
        )
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return fail("letters are UTF-8");
    };
    let mut clusters = Vec::with_capacity(count);
    let mut start = 0;
    for (cluster, &end) in ends.iter().enumerate() {
        let end = end as usize;
        let Some(letter) = text.get(start..end).filter(|letter| !letter.is_empty()) else {
            return fail(format!("cluster {cluster} ends at {end}: past {start}, within {length}"));
        };
        clusters.push(Cluster {
            text: letter.to_owned(),
            origin: [origins[2 * cluster], origins[2 * cluster + 1]],
        });
        start = end;
    }
    if start != length {
        return fail(format!("the clusters end at {start}, the letters at {length}"));
    }
    Some(clusters)
}

/// A run of letters in one style as a verb is handed it: `size` 64ths of a
/// px, `weight` — `FontWeight`'s, 1 to 1000 — and `italic`, its clusters
/// read as [`clusters_of`] reads them. None on failure; see the last
/// error.
///
/// # Safety
/// `text` holds `length` bytes, `ends` `count` words and `origins`
/// `2 × count`.
#[allow(clippy::too_many_arguments)]
unsafe fn run_of(
    size: i32,
    weight: u32,
    italic: bool,
    text: *const u8,
    length: usize,
    ends: *const u32,
    origins: *const i32,
    count: usize,
) -> Option<Run> {
    let weight = weight_of(weight)?;
    // SAFETY: see the function's contract.
    let clusters = unsafe { clusters_of(text, length, ends, origins, count) }?;
    Some(Run {
        size,
        weight,
        italic,
        clusters,
    })
}

/// A word as the app builds it: its runs, each in one style, where the
/// word's layout set them.
#[derive(Default)]
pub struct Wording {
    shapes: Vec<Placed>,
}

/// A word of no run.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_word_new() -> *mut Wording {
    hands_bytes(Wording::default())
}

/// # Safety
/// `word` came from `gpu_engine_word_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_word_free(word: *mut Wording) {
    // SAFETY: see the function's contract.
    unsafe { let_go_bytes(word) };
}

/// Adds to `word` a run of letters in one style, handed as
/// [`gpu_engine_letters_run`] is handed a pass's, standing where the
/// word's layout set it. False on failure; see the last error.
///
/// # Safety
/// `word` is live, `text` holds `length` bytes and `ends` `count` words,
/// `origins` `2 × count`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_word_run(
    word: *mut Wording,
    size: i32,
    weight: u32,
    italic: bool,
    text: *const u8,
    length: usize,
    ends: *const u32,
    origins: *const i32,
    count: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let word = unsafe { &mut *word };
    // SAFETY: see the function's contract.
    let Some(run) = (unsafe { run_of(size, weight, italic, text, length, ends, origins, count) }) else {
        return false;
    };
    word.shapes.push(Placed {
        at: Affine { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0 },
        shape: Shape::Letters(run),
    });
    true
}

/// Whether every letter of `word` is one some family of `faces` has
/// ([`words::whole`]): false for a word a letter of which the engine
/// would set as an empty box.
///
/// # Safety
/// `word` and `faces` are live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_word_whole(word: *const Wording, faces: *const Faces) -> bool {
    // SAFETY: see the function's contract.
    let (word, faces) = unsafe { (&*word, &*faces) };
    words::whole(faces, &word.shapes)
}

/// Rasters `word`, set in `faces` and laid by `to_raster` — the layout's
/// space to the raster's, six floats —, over `bytes`: the raster's
/// `width` × `height` pixels row by row, a byte of coverage each
/// ([`words::rastered`]). On the CPU, where it is called: no device is
/// taken in hand. False on failure, `bytes` as they were; see the last
/// error.
///
/// # Safety
/// `word` and `faces` are live, `to_raster` holds six floats and `bytes`
/// `width × height`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_word_raster(
    word: *const Wording,
    faces: *const Faces,
    to_raster: *const f32,
    width: u32,
    height: u32,
    bytes: *mut u8,
) -> bool {
    // SAFETY: see the function's contract.
    let (word, faces, to_raster) = unsafe { (&*word, &*faces, affine(to_raster)) };
    let (Some(to_raster), Some(count)) = (to_raster, words::pixels([width, height])) else {
        return false;
    };
    // SAFETY: see the function's contract.
    let bytes = unsafe { std::slice::from_raw_parts_mut(bytes, count) };
    words::rastered(faces, &word.shapes, to_raster, width, bytes);
    true
}

/// Adds to the pass begun last a box or a line — `rect`, [left, top,
/// right, bottom), 64ths of a px — standing in the layout where `at` puts
/// its own space. False on failure; see the last error.
///
/// # Safety
/// `letters` is live, `at` holds six floats and `rect` four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_letters_rect(letters: *mut Lettering, at: *const f32, rect: *const i32) -> bool {
    // SAFETY: see the function's contract.
    let (letters, at, rect) = unsafe { (&mut *letters, affine(at), *rect.cast::<[i32; 4]>()) };
    let (Some(at), Some(pass)) = (at, letters.last()) else {
        return false;
    };
    pass.shapes.push(Placed {
        at,
        shape: Shape::Rect(rect),
    });
    true
}

/// Sets `letters` in `faces` and lays them on the grid by `to_grid` — the
/// layout's space to the grid's, six floats —: their covers, kept for
/// [`gpu_engine_letters_land`], and their rectangle written to `rect`, its
/// first tile's column and row and how many columns and rows of tiles it
/// spans — none, zero columns of zero rows, for letters that cover no
/// pixel. On the CPU, where it is called: no device is taken in hand.
/// False on failure, `rect` as it was; see the last error.
///
/// 🚨WHY ON ITS CALLER'S THREAD (the-ui-thread-never-enters-the-driver,
/// 2026-11-18): what the app waits for is the rectangle, which its plate's
/// tiles are asked by; the picture is the engine's thread's to lay
/// ([`gpu_engine_letters_land`]). ↩️The covers were set and laid in one
/// body on the engine's thread, the caller waiting (`gpu_engine_letters_
/// set`): 🔬the test VM, S5_BA cut 352 filling its band again after a
/// stroke (k921), 17 sets, 58 to 97 ms of the UI thread each, nearly all
/// of it the wait for what was handed to that thread before.
///
/// # Safety
/// `letters` and `faces` are live; `to_grid` holds six floats and `rect`
/// four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_letters_cover(
    letters: *mut Lettering,
    faces: *const Faces,
    to_grid: *const f32,
    rect: *mut i32,
) -> bool {
    // SAFETY: see the function's contract.
    let (letters, faces, to_grid) = unsafe { (&mut *letters, &*faces, affine(to_grid)) };
    let Some(to_grid) = to_grid else {
        return false;
    };
    let covered = set(faces, to_grid, &letters.passes);
    let at = covered.as_ref().map_or([0; 4], |covered| {
        let at = covered.rect;
        [at.x0, at.y0, at.columns as i32, at.rows as i32]
    });
    // SAFETY: `rect` holds four words.
    unsafe { *rect.cast::<[i32; 4]>() = at };
    letters.covered = covered.map(Arc::new);
    true
}

/// Gives each tile of `letters`' covers ([`gpu_engine_letters_cover`])
/// that `asks` names — its column and row on the grid, `count` of them —
/// a fresh slot of `cel`, writes each one's place to `places` and its
/// change, inked, to `changes`, and hands the laying of their picture by
/// `composite` ([`lettered`]) and its putting there to the engine's
/// thread, waiting for none of it ([`Pool::lands_unwaited`], which says
/// how `told` is called with `number`): the engine's alone, as a landing
/// puts what it made. Returns as [`gpu_engine_stroke_land`] does — how
/// many it gave a slot, the first of them: all, or fewer where the pool is
/// full at the next; -1 on failure, see the last error.
///
/// 🚨A PICTURE NOT PUT IS TOLD, NOT SAID UNWRITTEN (the-ui-thread-never-
/// enters-the-driver, 2026-11-18): a store's places that were not written
/// are let go and their tiles stored again from the bytes they hold
/// (`gpu_engine_pool_store`); the plate's tiles are the engine's alone,
/// with no bytes to be stored from, so it is the plate the app lets go
/// of — made again of its letters where it is next asked for.
///
/// [`gpu_engine_stroke_land`]: crate::kernels::dab::abi::gpu_engine_stroke_land
///
/// # Safety
/// Every pointer is live, the pool and the executor made on `engine` and
/// the pool its caller's alone (`gpu_engine_pool_new`); the executor is let
/// go of on the engine's thread, behind this in turn. `asks` holds
/// `2 × count`, `places` and `changes` hold `count`, and `told` is one any
/// thread may call.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_letters_land(
    letters: *const Lettering,
    engine: *const Engine,
    composite: *const Composite,
    pool: *mut Pool,
    cel: u32,
    asks: *const i32,
    count: usize,
    places: *mut u32,
    changes: *mut u8,
    told: extern "C" fn(u64, bool),
    number: u64,
) -> isize {
    // SAFETY: see the function's contract.
    let (letters, engine, pool) = unsafe { (&*letters, &*engine, &mut *pool) };
    let Some(covered) = letters.covered.clone() else {
        fail::<()>("letters are landed that were not covered, or cover no pixel");
        return -1;
    };
    // SAFETY: see the function's contract.
    let asks = unsafe { std::slice::from_raw_parts(asks, 2 * count) };
    let tiles = asks.chunks_exact(2).map(|tile| covered.rect.index_of(tile[0], tile[1]));
    let Some(tiles) = tiles.collect::<Option<Vec<usize>>>() else {
        return -1;
    };
    let put = move |engine: &Engine, writing: &Writing| {
        // SAFETY: live till let go of, behind this (the function's
        // contract).
        let composite = unsafe { &*composite };
        lettered(engine, composite, &covered)
            .and_then(|picture| writing.put_from(engine, &picture, tiles))
    };
    // SAFETY: what `put` holds is let go of on the engine's thread, behind
    // it; `told` is one any thread may call (the function's contract).
    let given = unsafe { pool.lands_unwaited(engine, (Cel(cel), count), (told, number), put) };
    let landed = given.into_iter().map(|at| (Change::Inked, Some(at))).collect();
    // SAFETY: see the function's contract.
    unsafe { reported(Some(landed), places, changes) }
}
