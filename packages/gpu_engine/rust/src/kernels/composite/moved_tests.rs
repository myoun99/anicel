//! A surface's texels moved by whole pixels (moved.rs): every texel that
//! stays put where the move takes it, word for word, and those it uncovers
//! left as they were — in bands of rows, down and up alike —; its buffer a
//! spare, taken again from one move to the next and let go at rest; its
//! pass compiled where the executor an app shows through is made.

use super::Composite;
use crate::device::{Engine, storage_texture};
use crate::kernels::fill::Fill;
use crate::kernels::shared::storage_format;
use crate::platform::stores;
use crate::testing::{a_device_of_its_own, first_engine};

/// The formats a surface is made in (`platform::Surface`).
const FORMATS: [wgpu::TextureFormat; 2] = [wgpu::TextureFormat::Rgba8Unorm, wgpu::TextureFormat::Bgra8Unorm];

/// A surface's sides: a row's bytes, 1200, short of a multiple of the
/// copy's alignment, so the copy pads every row.
const SIZE: (u32, u32) = (300, 240);

/// Moves across, down, both, by one texel and by many, and by as many as
/// the surface holds and more — nothing staying.
const BY: [(i32, i32); 12] = [
    (0, 0),
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (13, -6),
    (-64, 65),
    (29, 47),
    (299, 0),
    (0, -239),
    (300, 0),
    (-300, -240),
];

/// A surface of `size` made as the app's are — stored to and copied from,
/// and no more —, every texel a word of its own (the fill's).
fn filled(engine: &Engine, (width, height): (u32, u32), format: wgpu::TextureFormat) -> wgpu::Texture {
    let surface = storage_texture(engine.device(), width, height, format);
    Fill::new(engine).run(engine, &surface, 7).expect("fill");
    surface
}

/// `before`, a surface of `width` × `height` read back row after row, as a
/// move by (`dx`, `dy`) leaves it.
fn moved_by(before: &[u8], (width, height): (u32, u32), (dx, dy): (i32, i32)) -> Vec<u8> {
    let (width, height) = (width as i32, height as i32);
    let at = |x: i32, y: i32| ((y * width + x) * 4) as usize;
    let mut after = before.to_vec();
    for y in 0..height {
        for x in 0..width {
            let (from_x, from_y) = (x - dx, y - dy);
            if (0..width).contains(&from_x) && (0..height).contains(&from_y) {
                after[at(x, y)..at(x, y) + 4].copy_from_slice(&before[at(from_x, from_y)..at(from_x, from_y) + 4]);
            }
        }
    }
    after
}

/// Every move of [`BY`] on a filled surface of [`SIZE`] in each format
/// `engine` stores to leaves it as [`moved_by`] does.
fn every_move_on(engine: &Engine) {
    assert!(stores(engine, wgpu::TextureFormat::Rgba8Unorm), "the premise: a surface to move on");
    for format in FORMATS.into_iter().filter(|&format| stores(engine, format)) {
        let composite = Composite::showing(engine, Some(format)).expect("the executor");
        for by in BY {
            let surface = filled(engine, SIZE, format);
            let before = engine.read_texture(&surface).expect("read before");
            composite.moved(engine, &surface, by).expect("the move");
            let after = engine.read_texture(&surface).expect("read after");
            assert!(after == moved_by(&before, SIZE, by), "{format:?} moved by {by:?}");
        }
    }
}

#[test]
fn a_move_puts_every_texel_that_stays_where_it_goes_word_for_word() {
    every_move_on(first_engine());
}

// A binding of 64 KiB holds 51 rows of [`SIZE`]'s padded 1280 bytes: a
// move down or up of 60 rows copies out 180, in four bands, each stored
// onto rows a band after it would read were they the other way about.
#[test]
fn a_move_in_bands_stores_each_band_where_no_band_after_it_reads() {
    let turn = a_device_of_its_own();
    let engine = turn.engine_binding(1 << 16);
    let row = u64::from(SIZE.0 * 4).next_multiple_of(u64::from(wgpu::COPY_BYTES_PER_ROW_ALIGNMENT));
    assert!(row * u64::from(SIZE.1 - 65) > 1 << 17, "the premise: a move of BY's in more than two bands");
    every_move_on(&engine);
}

// The buffer a move copies through is one of the engine's spares: kept
// for the next move while a hand is at work, none kept once it rests. On
// a device of the test's own, whose spares are no other test's.
#[test]
fn a_move_copies_through_a_spare_taken_again_and_let_go_at_rest() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::showing(&engine, Some(wgpu::TextureFormat::Rgba8Unorm)).expect("the executor");
    let surface = filled(&engine, SIZE, wgpu::TextureFormat::Rgba8Unorm);
    let before = engine.spares.made();
    composite.moved(&engine, &surface, (5, -3)).expect("the move");
    assert_eq!(engine.spares.made(), before + 1, "the premise: the move made its buffer");
    composite.moved(&engine, &surface, (-2, 7)).expect("the next move");
    assert_eq!(engine.spares.made(), before + 1, "taken again");
    assert!(engine.spares.bytes() > 0, "kept while a hand is at work");
    engine.spares.rest();
    assert_eq!(engine.spares.bytes(), 0, "none at rest");
}

// An executor an app shows through has the move of its surface's format
// compiled as it is made (`Composite::showing`); one made to show nothing
// has none.
#[test]
fn an_executor_opened_to_show_has_its_move() {
    let engine = first_engine();
    for format in FORMATS {
        let composite = Composite::showing(engine, Some(format)).expect("the executor");
        let shown = storage_format(format).filter(|_| stores(engine, format));
        if let Some(token) = shown {
            assert!(composite.moves.cell(Some(token)).get().is_some(), "{format:?}'s");
        }
        assert_eq!(composite.moves.outputs(), shown.map_or(vec![], |token| vec![Some(token)]), "no other ({format:?})");
    }
    let none = Composite::new(engine).expect("the executor");
    assert!(none.moves.outputs().is_empty(), "none made to show nothing");
}
