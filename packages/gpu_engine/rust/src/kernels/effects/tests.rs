//! The colour key walk on a real GPU, checked against what C's walk
//! (`qa_key_rgba`) gives by hand over tables made for each case — never
//! against a CPU copy of the walk (`kernels/mod.rs` has why). The tables
//! are the app's to make; these are made to put one question each.

use std::sync::OnceLock;

use super::{KEY_WGSL, KEYS_PER_RUN, KeyRun};
use crate::device::Engine;
use crate::kernels::shared::{Encoded, encode, pipeline, plane, whole, words_buffer};
use crate::testing::{first_engine, read_buffer};

/// The device and the compiled cases every test here runs on.
struct Rig {
    engine: &'static Engine,
    pipeline: wgpu::ComputePipeline,
}

/// One compile for the whole test process, on the tests' one device
/// (blend's rig has the crash that taught both).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let sources = [KEY_WGSL, include_str!("cases.wgsl")];
        let pipeline = pipeline(engine, &sources, "run_cases");
        Rig { engine, pipeline }
    })
}

/// Walks each `(run, texel, original)` over `runs` on the GPU and returns
/// the words that came out.
fn walk(runs: &[u32], cases: &[(u32, u32, u32)]) -> Vec<u32> {
    let Rig { engine, pipeline } = rig();
    let storage = |words: &[u32]| {
        words_buffer(engine, "key cases", words, wgpu::BufferUsages::STORAGE)
    };
    let runs = storage(runs);
    let words: Vec<u32> = cases
        .iter()
        .flat_map(|&(run, texel, original)| [run, texel, original])
        .collect();
    let input = storage(&words);
    let results = plane(engine, "key results", (cases.len() * 4) as u64);
    let bound = whole(&[(0, &runs), (1, &input), (2, &results)]);
    let groups = ((cases.len() as u32).div_ceil(64), 1, 1);
    encode(engine, &[Encoded { pipeline, bound, groups }]);
    read_buffer(engine, &results)
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

/// A straight RGBA8 word.
pub(crate) const fn rgba(r: u32, g: u32, b: u32, a: u32) -> u32 {
    r | (g << 8) | (b << 16) | (a << 24)
}

/// A run's tables, a key at a time.
struct Keys {
    red: [u32; 256],
    green: [u32; 256],
    blue: [u32; 256],
    restores: u32,
    maps: Vec<u8>,
}

impl Keys {
    fn new() -> Self {
        Self {
            red: [0; 256],
            green: [0; 256],
            blue: [0; 256],
            restores: 0,
            maps: Vec::new(),
        }
    }

    /// The next key: it names a pixel within `tolerance` of `colour` in
    /// every channel, erases (or gives back, `restore`) by `map`.
    fn key(mut self, colour: [u32; 3], tolerance: u32, restore: bool, map: fn(u32) -> u32) -> Self {
        let bit = (self.maps.len() / 256) as u32;
        for (table, centre) in [&mut self.red, &mut self.green, &mut self.blue]
            .into_iter()
            .zip(colour)
        {
            for (byte, word) in table.iter_mut().enumerate() {
                if (byte as u32).abs_diff(centre) <= tolerance {
                    *word |= 1 << bit;
                }
            }
        }
        if restore {
            self.restores |= 1 << bit;
        }
        self.maps.extend((0..256).map(|alpha| map(alpha) as u8));
        self
    }

    fn words(&self) -> Vec<u32> {
        KeyRun {
            red: &self.red,
            green: &self.green,
            blue: &self.blue,
            restores: self.restores,
            maps: &self.maps,
        }
        .words()
    }
}

/// Maps a key could be handed. An erase reads its map at the alpha and a
/// restore at what the run took, so a map that leaves nothing erases all
/// of it, or gives all of it back.
fn nothing(_: u32) -> u32 {
    0
}
fn half(alpha: u32) -> u32 {
    alpha.div_ceil(2)
}

const RED: [u32; 3] = [200, 30, 40];
const GREEN: [u32; 3] = [20, 220, 60];

#[test]
fn a_pixel_no_key_names_keeps_its_alpha() {
    let run = Keys::new().key(RED, 10, false, nothing).words();
    let pixel = rgba(20, 220, 60, 200);
    assert_eq!(walk(&run, &[(0, pixel, 200)]), [pixel]);
}

#[test]
fn an_erasing_key_leaves_what_its_map_says_and_the_colour_as_it_was() {
    let all = Keys::new().key(RED, 10, false, nothing).words();
    let halves = Keys::new().key(RED, 10, false, half).words();
    assert_eq!(walk(&all, &[(0, rgba(200, 30, 40, 200), 200)]), [rgba(200, 30, 40, 0)]);
    assert_eq!(walk(&halves, &[(0, rgba(205, 25, 47, 201), 201)]), [rgba(205, 25, 47, 101)]);
}

#[test]
fn a_key_names_a_pixel_only_within_its_tolerance_in_every_channel() {
    let run = Keys::new().key(RED, 10, false, nothing).words();
    let cases = [
        // Every channel 10 off: named.
        (0, rgba(210, 20, 50, 255), 255),
        // Blue 11 off.
        (0, rgba(200, 30, 51, 255), 255),
        // Green 11 off.
        (0, rgba(200, 19, 40, 255), 255),
        // Red 11 off.
        (0, rgba(189, 30, 40, 255), 255),
    ];
    assert_eq!(
        walk(&run, &cases),
        [
            rgba(210, 20, 50, 0),
            rgba(200, 30, 51, 255),
            rgba(200, 19, 40, 255),
            rgba(189, 30, 40, 255),
        ]
    );
}

#[test]
fn the_keys_of_a_run_go_in_their_order() {
    // Erase it all, then give it all back — and the other way round.
    let erase_then_restore = Keys::new()
        .key(RED, 10, false, nothing)
        .key(RED, 10, true, nothing)
        .words();
    let restore_then_erase = Keys::new()
        .key(RED, 10, true, nothing)
        .key(RED, 10, false, nothing)
        .words();
    let pixel = rgba(200, 30, 40, 200);
    assert_eq!(walk(&erase_then_restore, &[(0, pixel, 200)]), [pixel]);
    assert_eq!(walk(&restore_then_erase, &[(0, pixel, 200)]), [rgba(200, 30, 40, 0)]);
}

#[test]
fn a_second_erase_takes_from_what_the_first_left() {
    let run = Keys::new()
        .key(RED, 10, false, half)
        .key(RED, 10, false, half)
        .words();
    assert_eq!(walk(&run, &[(0, rgba(200, 30, 40, 200), 200)]), [rgba(200, 30, 40, 50)]);
}

#[test]
fn a_restore_gives_back_by_its_map_what_the_run_took() {
    // All of it erased, half of what was taken given back.
    let run = Keys::new()
        .key(RED, 10, false, nothing)
        .key(RED, 10, true, half)
        .words();
    assert_eq!(walk(&run, &[(0, rgba(200, 30, 40, 200), 200)]), [rgba(200, 30, 40, 100)]);
}

#[test]
fn a_restore_gives_back_to_the_alpha_before_the_run() {
    // A later part of a long run: 150 already taken from 200.
    let run = Keys::new().key(RED, 10, true, nothing).words();
    assert_eq!(walk(&run, &[(0, rgba(200, 30, 40, 50), 200)]), [rgba(200, 30, 40, 200)]);
}

#[test]
fn a_pixel_empty_before_the_run_is_left_as_it_is() {
    let run = Keys::new().key(RED, 10, false, nothing).words();
    let pixel = rgba(200, 30, 40, 90);
    assert_eq!(walk(&run, &[(0, pixel, 0)]), [pixel]);
}

#[test]
fn every_alpha_reads_its_own_byte_of_the_map() {
    let run = Keys::new()
        .key([128, 128, 128], 255, false, |alpha| 255 - alpha)
        .words();
    let cases: Vec<_> = (1..=255).map(|alpha| (0, rgba(1, 2, 3, alpha), alpha)).collect();
    let expected: Vec<_> = (1..=255).map(|alpha| rgba(1, 2, 3, 255 - alpha)).collect();
    assert_eq!(walk(&run, &cases), expected);
}

#[test]
fn the_last_key_of_a_full_run_reads_its_own_bit_and_map() {
    // Thirty-one keys naming green, then one naming red that leaves 7 —
    // or, as a restore after the first erases, gives back all but 7.
    let mut erases = Keys::new();
    let mut restores = Keys::new().key(RED, 10, false, nothing);
    for _ in 0..KEYS_PER_RUN - 1 {
        erases = erases.key(GREEN, 10, false, nothing);
    }
    for _ in 0..KEYS_PER_RUN - 2 {
        restores = restores.key(GREEN, 10, false, nothing);
    }
    let erases = erases.key(RED, 10, false, |_| 7).words();
    let restores = restores.key(RED, 10, true, |_| 7).words();
    let pixel = rgba(200, 30, 40, 200);
    assert_eq!(walk(&erases, &[(0, pixel, 200)]), [rgba(200, 30, 40, 7)]);
    assert_eq!(walk(&restores, &[(0, pixel, 200)]), [rgba(200, 30, 40, 193)]);
}

#[test]
fn each_run_reads_its_own_tables() {
    let first = Keys::new().key(RED, 10, false, nothing).words();
    let second = Keys::new().key(GREEN, 10, false, half).words();
    let at = first.len() as u32;
    let runs = [first, second].concat();
    let red = rgba(200, 30, 40, 200);
    let green = rgba(20, 220, 60, 200);
    assert_eq!(
        walk(&runs, &[(0, red, 200), (0, green, 200), (at, red, 200), (at, green, 200)]),
        [rgba(200, 30, 40, 0), green, red, rgba(20, 220, 60, 100)]
    );
}

#[test]
#[should_panic(expected = "keys at most")]
fn a_run_names_thirty_two_keys_at_most() {
    let mut keys = Keys::new();
    for _ in 0..=KEYS_PER_RUN {
        keys.maps.extend([0u8; 256]);
    }
    keys.words();
}
