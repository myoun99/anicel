//! The frame grid's C ABI on a real GPU, checked by hand: a tile drawn
//! through it holds what its stream says, its letters read from the words
//! where their places put them, a batch draws each of its tiles and sounds
//! as it would alone, and what it cannot make or draw is refused with why.

use super::*;
use crate::kernels::timeline::grid::ATLAS_SIDE;
use crate::kernels::timeline::wave::abi::{
    gpu_engine_wave_free, gpu_engine_wave_new, gpu_engine_wave_peaks_free, gpu_engine_wave_peaks_new,
};
use crate::testing::{first_engine, last_error};

const FILL_RECT: i32 = 1;
const GLYPH: i32 = 4;

/// An RGBA word, as the grids pack one.
fn rgba(r: u32, g: u32, b: u32, a: u32) -> i32 {
    (r | g << 8 | b << 16 | a << 24) as i32
}

/// Pictures of `sizes` made through the ABI, all on one trip — none where
/// it refused them.
fn pictures(sizes: &[(u32, u32)]) -> Option<Vec<*mut GridPicture>> {
    let words: Vec<u32> = sizes.iter().flat_map(|&(width, height)| [width, height]).collect();
    let mut made = vec![std::ptr::null_mut(); sizes.len()];
    // SAFETY: the engine is live, and each holds its count.
    let ok = unsafe { gpu_engine_grid_pictures_new(first_engine(), words.as_ptr(), sizes.len(), made.as_mut_ptr()) };
    ok.then_some(made)
}

/// A `width` × `height` tile made through the ABI.
fn picture(width: u32, height: u32) -> *mut GridPicture {
    pictures(&[(width, height)]).map_or(std::ptr::null_mut(), |made| made[0])
}

/// A grid's pass and a sound's, through the ABI.
fn passes() -> (*mut GridTile, *mut WaveTile) {
    let engine = first_engine();
    // SAFETY: the engine is live.
    unsafe { (gpu_engine_grid_new(engine), gpu_engine_wave_new(engine)) }
}

/// Lets go of `passes` ([`passes`]).
fn let_go_of((grid, wave): (*mut GridTile, *mut WaveTile)) {
    // SAFETY: each came from its new, let go of once.
    unsafe {
        gpu_engine_grid_free(grid);
        gpu_engine_wave_free(wave);
    }
}

/// Letters to put: where, and their bytes.
type Letters<'a> = &'a [([u32; 4], &'a [u8])];

/// Sounds to lay: over which tile, what, and its view's eleven words.
type Sounds<'a> = &'a [(*mut GridPicture, *mut WavePeaks, [i32; 11])];

/// `letters` put, each of `streams` drawn into its tile and each of
/// `sounds` laid over its own by `passes` in one batch through the ABI:
/// whether it drew.
fn batch(
    passes: (*mut GridTile, *mut WaveTile),
    letters: Letters,
    streams: &[(*mut GridPicture, &[i32])],
    sounds: Sounds,
) -> bool {
    let puts: Vec<u32> = letters.iter().flat_map(|(at, _)| *at).collect();
    let bytes: Vec<u8> = letters.iter().flat_map(|(_, bytes)| bytes.iter().copied()).collect();
    let tiles: Vec<*const GridPicture> = streams.iter().map(|(tile, _)| tile.cast_const()).collect();
    let ops: Vec<i32> = streams.iter().flat_map(|(_, ops)| ops.iter().copied()).collect();
    let ends: Vec<u32> = streams
        .iter()
        .scan(0, |end, (_, ops)| {
            *end += ops.len() as u32;
            Some(*end)
        })
        .collect();
    let waved: Vec<*const GridPicture> = sounds.iter().map(|(tile, ..)| tile.cast_const()).collect();
    let peaks: Vec<*const WavePeaks> = sounds.iter().map(|(_, peaks, _)| peaks.cast_const()).collect();
    let views: Vec<i32> = sounds.iter().flat_map(|(.., view)| *view).collect();
    // SAFETY: every pointer is live and holds what it is said to.
    unsafe {
        gpu_engine_grid_flush(
            passes.0,
            passes.1,
            first_engine(),
            puts.as_ptr(),
            letters.len(),
            bytes.as_ptr(),
            tiles.as_ptr(),
            ends.as_ptr(),
            tiles.len(),
            ops.as_ptr(),
            waved.as_ptr(),
            peaks.as_ptr(),
            views.as_ptr(),
            sounds.len(),
        )
    }
}

/// [`batch`], of no sound.
fn flushed(passes: (*mut GridTile, *mut WaveTile), letters: Letters, streams: &[(*mut GridPicture, &[i32])]) -> bool {
    batch(passes, letters, streams, &[])
}

/// `picture`'s bytes read through the ABI, `size` of them.
fn read(picture: *mut GridPicture, (width, height): (u32, u32)) -> Vec<u8> {
    let mut bytes = vec![0; (width * height * 4) as usize];
    // SAFETY: it came from its new, and `bytes` holds its length.
    let read = unsafe { gpu_engine_grid_picture_read(first_engine(), picture, bytes.as_mut_ptr(), bytes.len()) };
    assert!(read, "{}", last_error());
    bytes
}

/// `ops` drawn into a fresh `size` tile through the ABI by a pass whose
/// atlas holds `letters`: whether it drew, and the tile's bytes.
fn drawn(size: (u32, u32), ops: &[i32], letters: Letters) -> (bool, Vec<u8>) {
    let passes = passes();
    let tile = picture(size.0, size.1);
    assert!(!tile.is_null(), "{}", last_error());
    let ok = flushed(passes, letters, &[(tile, ops)]);
    let bytes = read(tile, size);
    // SAFETY: it came from its new, let go of once.
    unsafe { gpu_engine_grid_picture_free(tile) };
    let_go_of(passes);
    (ok, bytes)
}

/// The pixel at (x, y) of a tile `width` across.
fn at(bytes: &[u8], width: u32, x: u32, y: u32) -> [u8; 4] {
    let i = ((y * width + x) * 4) as usize;
    [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]]
}

#[test]
fn a_tile_of_no_side_or_past_the_device_is_refused_with_why() {
    let most = first_engine().device().limits().max_texture_dimension_2d;
    for (width, height) in [(0, 4), (4, 0), (most + 1, 4), (4, most + 1)] {
        assert!(picture(width, height).is_null(), "{width} × {height}");
        assert!(last_error().contains(&format!("a grid tile {width} × {height}")), "{}", last_error());
        assert!(pictures(&[(4, 4), (width, height)]).is_none(), "none made of a trip with {width} × {height}");
    }
    let largest = pictures(&[(most, 1), (1, most)]).expect("as large as the device makes");
    // SAFETY: each came from its new.
    unsafe { largest.into_iter().for_each(|picture| gpu_engine_grid_picture_free(picture)) };
    assert!(pictures(&[]).is_some_and(|made| made.is_empty()), "a trip for none");
}

#[test]
fn a_stream_drawn_through_the_abi_is_over_clear() {
    let red = rgba(255, 0, 0, 255);
    let (ok, bytes) = drawn((4, 3), &[FILL_RECT, 1, 1, 2, 1, red], &[]);
    assert!(ok, "{}", last_error());
    assert_eq!(at(&bytes, 4, 1, 1), [255, 0, 0, 255]);
    assert_eq!(at(&bytes, 4, 2, 1), [255, 0, 0, 255]);
    for (x, y) in [(0, 0), (0, 1), (3, 1), (1, 2), (3, 2)] {
        assert_eq!(at(&bytes, 4, x, y), [0; 4], "({x}, {y})");
    }
}

// A read copies as many bytes as it is handed room for, and no more.
#[test]
fn a_tile_read_through_the_abi_fills_the_room_it_is_handed() {
    let engine = first_engine();
    let passes = passes();
    let tile = picture(2, 1);
    assert!(flushed(passes, &[], &[(tile, &[FILL_RECT, 0, 0, 2, 1, rgba(255, 0, 0, 255)])]));
    let mut bytes = [7; 8];
    // SAFETY: as above; `bytes` holds 8, and the read is handed 4.
    assert!(unsafe { gpu_engine_grid_picture_read(engine, tile, bytes.as_mut_ptr(), 4) }, "{}", last_error());
    assert_eq!(bytes, [255, 0, 0, 255, 7, 7, 7, 7]);
    // SAFETY: it came from its new, let go of once.
    unsafe { gpu_engine_grid_picture_free(tile) };
    let_go_of(passes);
}

// Two words put apart, the second below and right of the first: each
// letter reads the atlas where its op says. Opaque white scaled by a
// coverage c over clear is white at c, stored straight.
#[test]
fn a_letter_reads_the_atlas_where_its_op_says() {
    // [255, 128] at (0, 0), [64] over [32] at (2, 1).
    let letters: Letters = &[([0, 0, 2, 1], &[255, 128]), ([2, 1, 1, 2], &[64, 32])];
    let white = rgba(255, 255, 255, 255);
    let ops = [[GLYPH, 0, 0, 0, 0, 2, 1, white], [GLYPH, 3, 0, 2, 1, 1, 2, white]].concat();
    let (ok, bytes) = drawn((4, 2), &ops, letters);
    assert!(ok, "{}", last_error());
    assert_eq!(at(&bytes, 4, 0, 0), [255; 4]);
    assert_eq!(at(&bytes, 4, 1, 0), [255, 255, 255, 128]);
    assert_eq!(at(&bytes, 4, 3, 0), [255, 255, 255, 64]);
    assert_eq!(at(&bytes, 4, 3, 1), [255, 255, 255, 32]);
    // What lies between the words in the atlas is nothing.
    let (_, between) = drawn((2, 2), &[GLYPH, 0, 0, 0, 1, 2, 1, white], letters);
    assert_eq!(at(&between, 2, 0, 0), [0; 4]);
    assert_eq!(at(&between, 2, 1, 0), [0; 4]);
}

#[test]
fn a_stream_the_pass_refuses_draws_nothing_and_says_why() {
    let white = rgba(255, 255, 255, 255);
    let (ok, bytes) = drawn((2, 2), &[GLYPH, 0, 0, 0, 0, 1, 1, white], &[]);
    assert!(!ok);
    assert!(last_error().contains("tile 0: ") && last_error().contains("has no atlas"), "{}", last_error());
    assert!(bytes.iter().all(|&byte| byte == 0));
}

#[test]
fn letters_past_the_atlas_are_refused_with_why() {
    let side = ATLAS_SIDE;
    let (ok, bytes) = drawn((1, 1), &[FILL_RECT, 0, 0, 1, 1, rgba(9, 9, 9, 255)], &[([side, 0, 1, 1], &[255])]);
    assert!(!ok);
    assert!(last_error().contains("past the atlas"), "{}", last_error());
    assert_eq!(bytes, [0; 4], "nothing is drawn of the batch");
    let (ok, _) = drawn((1, 1), &[], &[([side - 1, side - 1, 1, 1], &[255])]);
    assert!(ok, "letters at the atlas's last pixel: {}", last_error());
}

// One batch: two tiles, their letters, and a sound over the second — each
// as it is drawn alone, on one trip and one submit.
#[test]
fn a_batch_through_the_abi_draws_each_tile_and_sound_as_alone() {
    let engine = first_engine();
    let white = rgba(255, 255, 255, 255);
    let letters: Letters = &[([0, 0, 2, 1], &[255, 128])];
    let first: &[i32] = &[GLYPH, 1, 1, 0, 0, 2, 1, white];
    let second: &[i32] = &[FILL_RECT, 0, 0, 6, 2, rgba(40, 80, 120, 255)];
    let peaks: Vec<u16> = (0..16u32).map(|i| (i * 4099 % 65536) as u16 | 0x2000).collect();
    let view = [1, 6, 0, 256, 24, 1, 4, 0, 4 * 256, 65536, 0xff30_a0c8_u32 as i32];
    let draw = |together: bool| -> Vec<Vec<u8>> {
        let passes = passes();
        let made = pictures(&[(4, 3), (6, 4)]).expect("two pictures");
        // SAFETY: the engine is live, and `peaks` holds its one lane.
        let kept = unsafe { gpu_engine_wave_peaks_new(engine, peaks.as_ptr(), 1, peaks.len()) };
        let streams = [(made[0], first), (made[1], second)];
        let sounds = [(made[1], kept, view)];
        if together {
            assert!(batch(passes, letters, &streams, &sounds), "{}", last_error());
        } else {
            for stream in streams {
                assert!(flushed(passes, letters, &[stream]), "{}", last_error());
            }
            assert!(batch(passes, &[], &[], &sounds), "{}", last_error());
        }
        let read = vec![read(made[0], (4, 3)), read(made[1], (6, 4))];
        // SAFETY: each came from its new, let go of once.
        unsafe {
            made.into_iter().for_each(|picture| gpu_engine_grid_picture_free(picture));
            gpu_engine_wave_peaks_free(kept);
        }
        let_go_of(passes);
        read
    };
    let alone = draw(false);
    assert_eq!(draw(true), alone);
    assert!(alone[0].chunks(4).any(|pixel| pixel[3] > 0), "premise: the letters drew");
    assert!(
        alone[1].chunks(4).any(|pixel| pixel != [40, 80, 120, 255]),
        "premise: the sound drew over the fill"
    );
}

// What the passes keep between batches is counted, and goes when they are
// told to let it go.
#[test]
fn what_a_batch_keeps_is_counted_and_let_go_of() {
    let passes = passes();
    // SAFETY: the passes are live, and no batch is under way.
    let kept = || unsafe { gpu_engine_grid_kept_bytes(passes.0, passes.1) };
    assert_eq!(kept(), 0, "nothing before a batch");
    let tile = picture(2, 2);
    assert!(flushed(passes, &[([0, 0, 1, 1], &[255])], &[(tile, &[FILL_RECT, 0, 0, 1, 1, rgba(1, 2, 3, 255)])]));
    let atlas = u64::from(ATLAS_SIDE) * u64::from(ATLAS_SIDE);
    assert!(kept() > atlas, "the atlas and the plane: {}", kept());
    // SAFETY: every pointer is live.
    unsafe { gpu_engine_grid_let_go_kept(passes.0, passes.1, first_engine()) };
    assert_eq!(kept(), 0);
    // SAFETY: it came from its new, let go of once.
    unsafe { gpu_engine_grid_picture_free(tile) };
    let_go_of(passes);
}

// Through the ABI a box is eight doubles, the tile's part then the
// screen's: the right half of a red-and-green tile laid on the screen's
// top-left pixel is green there, and the rest of the rect — the pixel
// below it among it — is made clear.
#[test]
fn a_tile_laid_through_the_abi_takes_its_part_onto_the_screens() {
    let engine = first_engine();
    let passes = passes();
    let tile = picture(2, 1);
    let ops = [[FILL_RECT, 0, 0, 1, 1, rgba(255, 0, 0, 255)], [FILL_RECT, 1, 0, 1, 1, rgba(0, 255, 0, 255)]].concat();
    assert!(flushed(passes, &[], &[(tile, &ops)]), "{}", last_error());
    let screen = crate::device::storage_texture(engine.device(), 3, 2, wgpu::TextureFormat::Rgba8Unorm);
    // SAFETY: the engine is live.
    let lay = unsafe { gpu_engine_grid_lay_new(engine) };
    let tiles = [tile.cast_const()];
    let laid = |rect: [u32; 4], boxes: [f64; 8]| {
        // SAFETY: as above.
        unsafe { gpu_engine_grid_lay(lay, engine, &screen, rect.as_ptr(), tiles.as_ptr(), boxes.as_ptr(), 1) }
    };
    assert!(laid([0, 0, 3, 2], [1.0, 0.0, 2.0, 1.0, 0.0, 0.0, 1.0, 1.0]), "{}", last_error());
    let bytes = engine.read_texture(&screen).expect("read back");
    let mut want = vec![0; 4 * 6];
    want[..4].copy_from_slice(&[0, 255, 0, 255]);
    assert_eq!(bytes, want);
    assert!(!laid([0, 0, 4, 2], [0.0, 0.0, 2.0, 1.0, 0.0, 0.0, 2.0, 1.0]));
    assert!(last_error().contains("is no rectangle of a 3 × 2 screen"), "{}", last_error());
    // SAFETY: each came from its new, let go of once.
    unsafe {
        gpu_engine_grid_lay_free(lay);
        gpu_engine_grid_picture_free(tile);
    }
    let_go_of(passes);
}
