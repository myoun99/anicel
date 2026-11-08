//! The letters' C ABI (cel-number-on-the-engine-letters): the app hands
//! the engine its faces once — each family's files, families in the order
//! a letter goes down them — and a picture of letters a pass at a time,
//! each run as the app's layout set it, and reads back what they make: the
//! straight RGBA8 tiles of one rectangle of the grid, which the app holds
//! as it holds a row's picture. Where a letter stands is the app's to say
//! ([`Run`]); which glyphs it takes and how they raster, the engine's.

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::Composite;

use super::glyphs::{Affine, Cluster, Faces, Family, Paint, Placed, Run, Shape, WEIGHTS};
use super::words::{self, WordCover};
use super::{Lettered, Pass, set};

/// A picture of letters as the app builds it: its passes, bottom to top.
#[derive(Default)]
pub(crate) struct Lettering {
    passes: Vec<Pass>,
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

/// The faces letters are set in: `count` files — each `lengths[i]` bytes
/// at `files[i]`, alive for the call — of the families `families[i]`
/// names, 0 first and each one the last's or the next, so a family's files
/// lie together in the order its family is handed over. Null on failure;
/// see the last error.
///
/// # Safety
/// `files`, `lengths` and `families` each hold `count`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_faces_new(
    files: *const *const u8,
    lengths: *const usize,
    families: *const u32,
    count: usize,
) -> *mut Faces {
    // SAFETY: see the function's contract.
    let (files, lengths, named) = unsafe {
        (
            std::slice::from_raw_parts(files, count),
            std::slice::from_raw_parts(lengths, count),
            std::slice::from_raw_parts(families, count),
        )
    };
    let mut grouped: Vec<Vec<Vec<u8>>> = Vec::new();
    for ((&file, &length), &family) in files.iter().zip(lengths).zip(named) {
        if family as usize == grouped.len() {
            grouped.push(Vec::new());
        } else if family as usize + 1 != grouped.len() {
            return none(format!("family {family} is not the last one's nor the next"));
        }
        // SAFETY: each file holds its length, alive for the call.
        let bytes = unsafe { std::slice::from_raw_parts(file, length) };
        grouped.last_mut().expect("pushed above").push(bytes.to_vec());
    }
    let mut set_in = Vec::with_capacity(grouped.len());
    for (family, files) in grouped.into_iter().enumerate() {
        let Some(faces) = Family::of_files(files) else {
            return none(format!("family {family} holds no face"));
        };
        set_in.push(faces);
    }
    Faces::new(set_in).map_or(std::ptr::null_mut(), |faces| Box::into_raw(Box::new(faces)))
}

/// The families of `faces` in the order `order` names them — `count`
/// places in the order `faces` holds them —, sharing their files: freed on
/// its own, before or after `faces`. Null on failure; see the last error.
///
/// # Safety
/// `faces` came from `gpu_engine_faces_new` or this, and `order` holds
/// `count`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_faces_ordered(faces: *const Faces, order: *const u32, count: usize) -> *mut Faces {
    // SAFETY: see the function's contract.
    let (faces, order) = unsafe { (&*faces, std::slice::from_raw_parts(order, count)) };
    faces
        .ordered(order)
        .map_or(std::ptr::null_mut(), |faces| Box::into_raw(Box::new(faces)))
}

/// # Safety
/// `faces` came from `gpu_engine_faces_new` or `gpu_engine_faces_ordered`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_faces_free(faces: *mut Faces) {
    if !faces.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(faces) });
    }
}

/// A picture of letters of no pass.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_letters_new() -> *mut Lettering {
    Box::into_raw(Box::default())
}

/// # Safety
/// `letters` came from `gpu_engine_letters_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_letters_free(letters: *mut Lettering) {
    if !letters.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(letters) });
    }
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
    let Some(weight) = weight_of(weight) else {
        return false;
    };
    // SAFETY: see the function's contract.
    let Some(clusters) = (unsafe { clusters_of(text, length, ends, origins, count) }) else {
        return false;
    };
    let Some(pass) = letters.last() else {
        return false;
    };
    pass.shapes.push(Placed {
        at,
        shape: Shape::Letters(Run {
            size,
            weight,
            italic,
            clusters,
        }),
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

/// A word as the app builds it: its runs, each in one style.
#[derive(Default)]
pub(crate) struct Wording {
    shapes: Vec<Placed>,
}

/// A word of no run.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_word_new() -> *mut Wording {
    Box::into_raw(Box::default())
}

/// # Safety
/// `word` came from `gpu_engine_word_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_word_free(word: *mut Wording) {
    if !word.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(word) });
    }
}

/// Adds to `word` a run of letters in one style — `size` 64ths of a px,
/// `weight` — `FontWeight`'s, 1 to 1000 — and `italic` — standing where
/// the word's layout set it: `text`, `length` bytes of UTF-8, cut into
/// `count` clusters, the i-th ending at byte `ends[i]` and set with its
/// box's left and its line's baseline at `origins[2i]`, `origins[2i + 1]`,
/// 64ths of a px. False on failure; see the last error.
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
    let Some(weight) = weight_of(weight) else {
        return false;
    };
    // SAFETY: see the function's contract.
    let Some(clusters) = (unsafe { clusters_of(text, length, ends, origins, count) }) else {
        return false;
    };
    word.shapes.push(Placed {
        at: Affine { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0 },
        shape: Shape::Letters(Run {
            size,
            weight,
            italic,
            clusters,
        }),
    });
    true
}

/// Bakes `word` — its box `width` × `height` px of its layout — set in
/// `faces` at `dpr` device pixels a px, rastered `times` times over and
/// narrowed to `along` and `down` of itself — the narrowings the app drew
/// it at, counted in [`words::WHOLE`]ths ([`words::bake`]): its coverage,
/// a byte a pixel with a pixel of margin round it. Null on failure, and
/// for a word the bake refuses — the app paints that one as it always did;
/// see the last error.
///
/// # Safety
/// `word` and `faces` are live.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_word_bake(
    word: *const Wording,
    faces: *const Faces,
    dpr: f64,
    times: u32,
    width: f64,
    height: f64,
    along: f64,
    down: f64,
) -> *mut WordCover {
    // SAFETY: see the function's contract.
    let (word, faces) = unsafe { (&*word, &*faces) };
    // A narrowing that is no number, none or past whole comes out of its
    // parts' range, and the bake refuses it.
    let narrowed = [along, down].map(|fit| (fit * f64::from(words::WHOLE)).round() as u32);
    let baked = words::bake(faces, &word.shapes, dpr, times, [width, height], narrowed);
    baked.map_or(std::ptr::null_mut(), |cover| Box::into_raw(Box::new(cover)))
}

/// `cover`'s width and height, written to `size`.
///
/// # Safety
/// `cover` is live and `size` holds two words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_word_cover_size(cover: *const WordCover, size: *mut u32) {
    // SAFETY: see the function's contract.
    let cover = unsafe { &*cover };
    // SAFETY: as above.
    unsafe { *size.cast::<[u32; 2]>() = [cover.width, cover.height] };
}

/// Copies `cover`'s bytes — a byte a pixel, row by row — into `bytes`,
/// `capacity` of them at most.
///
/// # Safety
/// `cover` is live and `bytes` holds `capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_word_cover_read(cover: *const WordCover, bytes: *mut u8, capacity: usize) {
    // SAFETY: see the function's contract.
    let cover = unsafe { &*cover };
    let count = cover.bytes.len().min(capacity);
    // SAFETY: `bytes` holds `capacity`, and `count` is no more.
    unsafe { std::ptr::copy_nonoverlapping(cover.bytes.as_ptr(), bytes, count) };
}

/// # Safety
/// `cover` came from `gpu_engine_word_bake`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_word_cover_free(cover: *mut WordCover) {
    if !cover.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(cover) });
    }
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
/// layout's space to the grid's, six floats —, and submits the work: the
/// picture, its rectangle written to `rect` as its first tile's column and
/// row and how many columns and rows of tiles it spans. Null for letters
/// that cover no pixel, `rect` none — zero columns of zero rows —, and on
/// failure, `rect` as it was; see the last error.
///
/// # Safety
/// Every pointer is live, the executor made on `engine`; `to_grid` holds
/// six floats and `rect` four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_letters_set(
    letters: *const Lettering,
    engine: *const Engine,
    composite: *const Composite,
    faces: *const Faces,
    to_grid: *const f32,
    rect: *mut i32,
) -> *mut Lettered {
    // SAFETY: see the function's contract.
    let (letters, engine, composite, faces, to_grid) =
        unsafe { (&*letters, &*engine, &*composite, &*faces, affine(to_grid)) };
    let Some(to_grid) = to_grid else {
        return std::ptr::null_mut();
    };
    let Some(lettered) = set(engine, composite, faces, to_grid, &letters.passes) else {
        return std::ptr::null_mut();
    };
    let at = lettered.as_ref().map_or([0; 4], |lettered| {
        let at = lettered.rect;
        [at.x0, at.y0, at.columns as i32, at.rows as i32]
    });
    // SAFETY: `rect` holds four words.
    unsafe { *rect.cast::<[i32; 4]>() = at };
    lettered.map_or(std::ptr::null_mut(), |lettered| Box::into_raw(Box::new(lettered)))
}

/// Copies `lettered`'s pixels — straight RGBA8, tile after tile, row by
/// row of its rectangle — into `bytes` once the GPU is done, `capacity` of
/// them at most. False on failure; see the last error.
///
/// # Safety
/// `engine` and `lettered` are live and `bytes` holds `capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_lettered_read(
    engine: *const Engine,
    lettered: *const Lettered,
    bytes: *mut u8,
    capacity: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, lettered) = unsafe { (&*engine, &*lettered) };
    let Some(read) = engine.read_buffer(&lettered.tiles) else {
        return false;
    };
    let count = read.len().min(capacity);
    // SAFETY: `bytes` holds `capacity`, and `count` is no more.
    unsafe { std::ptr::copy_nonoverlapping(read.as_ptr(), bytes, count) };
    true
}

/// # Safety
/// `lettered` came from `gpu_engine_letters_set`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_lettered_free(lettered: *mut Lettered) {
    if !lettered.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(lettered) });
    }
}
