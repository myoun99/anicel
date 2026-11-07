//! The Rust decoder against the engine's C (native/oracle): frames the C
//! compresses, decoded by both — every answer and every byte written held
//! to the C's, on good frames and on damaged ones — and those of frames
//! that outlive the C held to the ledger too.

use oracle::export;

use crate::{frame_header, sequences, xxhash};

type Compress = unsafe extern "C" fn(*mut u8, i64, *const u8, i64, i32) -> i64;
type Decompress = unsafe extern "C" fn(*mut u8, i64, *const u8, i64) -> i64;
type Size = unsafe extern "C" fn(*const u8, i64) -> i64;
type Bound = extern "C" fn(i64) -> i64;

/// The C's frame of `data` at `level`.
pub(crate) fn compressed(data: &[u8], level: i32) -> Vec<u8> {
    // SAFETY: qa_compress.c's declarations.
    let (bound, compress) = unsafe { (export::<Bound>("qa_zstd_compress_bound"), export::<Compress>("qa_zstd_compress")) };
    let mut frame = vec![0u8; bound(data.len().max(1) as i64) as usize];
    // SAFETY: both buffers hold the sizes passed.
    let written = unsafe { compress(frame.as_mut_ptr(), frame.len() as i64, data.as_ptr(), data.len() as i64, level) };
    assert!(written > 0, "the C compresses {} bytes at level {level}", data.len());
    frame.truncate(written as usize);
    frame
}

/// What a decoder answers for `frame` into `capacity` bytes, and the bytes
/// it says it wrote.
fn decoded(decompress: Decompress, frame: &[u8], capacity: usize) -> (i64, Vec<u8>) {
    let mut out = vec![0u8; capacity.max(1)];
    // SAFETY: both buffers hold the sizes passed.
    let answer = unsafe { decompress(out.as_mut_ptr(), capacity as i64, frame.as_ptr(), frame.len() as i64) };
    out.truncate(answer.max(0) as usize);
    (answer, out)
}

fn c_decompress() -> Decompress {
    // SAFETY: qa_compress.c — `int64_t qa_zstd_decompress(uint8_t*, int64_t, const uint8_t*, int64_t)`.
    unsafe { export::<Decompress>("qa_zstd_decompress") }
}

/// A test's answers in a row, fingerprinted for the ledger: each the
/// number answered, little-endian, then the bytes written — so the C's
/// answers stay held once the C is deleted (connection-round-checklist A,
/// 관제 2026-11-07).
#[derive(Default)]
pub(crate) struct Answers(ledger::Running);

impl Answers {
    pub(crate) fn add(&mut self, answer: i64, written: &[u8]) {
        self.0.add(&answer.to_le_bytes());
        self.0.add(written);
    }

    pub(crate) fn pinned(self, id: &str) {
        self.0.assert_pinned(id);
    }
}

// The C's frames below level 9 that outlive it: each of at most
// `KEPT_MAX` bytes that a test here decodes — the C's compressor frozen
// for small inputs while it lives (connection-round-checklist A ②,
// 관제 2026-11-07). Level 9 needs none: it is the Rust compressor's own.
// Records, little-endian: the level (i32), the input's length (u64) and
// its fingerprint (8 hex digits), the frame's length (u32), the frame.
const C_FRAMES: &[u8] = include_bytes!("../fixtures/c_frames.bin");
const KEPT_MAX: usize = 10 << 10;

/// The frame of `data` at `level` that outlives the C, if there is one.
fn kept_frame(data: &[u8], level: i32) -> Option<Vec<u8>> {
    if level == 9 {
        let mut frame = vec![0u8; crate::qa_zstd_compress_bound(data.len() as i64) as usize];
        let written = crate::encode::compress(&mut frame, data).expect("the Rust compresses it");
        frame.truncate(written);
        return Some(frame);
    }
    let (size, fingerprint) = (data.len() as u64, ledger::fingerprint(data));
    let mut at = 0;
    while at < C_FRAMES.len() {
        let field = |from: usize, to: usize| &C_FRAMES[at + from..at + to];
        let length = u32::from_le_bytes(field(20, 24).try_into().unwrap()) as usize;
        let frame = field(24, 24 + length);
        if field(0, 4) == level.to_le_bytes() && field(4, 12) == size.to_le_bytes() && field(12, 20) == fingerprint.as_bytes()
        {
            return Some(frame.to_vec());
        }
        at += 24 + length;
    }
    None
}

/// The C's frame of `data` at `level`, and whether it outlives the C —
/// the frame that does is the C's, and every one small enough is kept.
/// The one that outlives it is the one decoded, so the ledger's rows hold
/// what the tests decode once the C is gone.
fn frame(data: &[u8], level: i32) -> (Vec<u8>, bool) {
    let theirs = compressed(data, level);
    let what = format!("{} bytes ({}) at level {level}", data.len(), ledger::fingerprint(data));
    match kept_frame(data, level) {
        Some(kept) => {
            assert!(kept == theirs, "{what}: the frame kept is the C's");
            (kept, true)
        }
        None => {
            assert!(theirs.len() > KEPT_MAX, "{what}: c_frames.bin keeps the C's frame");
            (theirs, false)
        }
    }
}

/// Both decoders on `frame` into `capacity`: the Rust's answer is the C's
/// — and goes into `answers`, where there are any.
fn same_answer(answers: Option<&mut Answers>, frame: &[u8], capacity: usize, what: &str) -> i64 {
    let theirs = decoded(c_decompress(), frame, capacity);
    let ours = decoded(crate::qa_zstd_decompress, frame, capacity);
    assert!(ours.0 == theirs.0, "{what}: the Rust answers {} where the C answers {}", ours.0, theirs.0);
    let first = ours.1.iter().zip(&theirs.1).position(|(a, b)| a != b);
    assert!(first.is_none(), "{what}: {} bytes written, first apart at {first:?}", ours.0);
    if let Some(answers) = answers {
        answers.add(ours.0, &ours.1);
    }
    ours.0
}

/// xorshift64: the same "random" bytes on every machine.
pub(crate) struct Noise(pub(crate) u64);

impl Noise {
    pub(crate) fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }

    pub(crate) fn below(&mut self, bound: usize) -> usize {
        (self.next() % bound as u64) as usize
    }
}

/// Inputs that take each path of a frame: raw and RLE blocks, literals
/// raw, RLE, and Huffman-coded in one stream and four, single- and
/// double-symbol, offsets near and far, long runs and repeats.
pub(crate) fn kinds(size: usize, seed: u64) -> Vec<(&'static str, Vec<u8>)> {
    let mut noise = Noise(seed | 1);
    let random: Vec<u8> = (0..size).map(|_| noise.next() as u8).collect();
    let words = [&b"stroke "[..], b"cel ", b"timeline ", b"onion skin ", b"brush ", b"layer ", b"\n", b"frame 0012 "];
    let mut text = Vec::with_capacity(size + 16);
    while text.len() < size {
        text.extend_from_slice(words[noise.below(words.len())]);
    }
    text.truncate(size);
    // A cel: transparent, then a drawn band with soft edges and a little
    // grain, as the app compresses them.
    let width = 256;
    let cel: Vec<u8> = (0..size)
        .map(|at| {
            let (pixel, channel) = (at / 4, at % 4);
            let (x, y) = (pixel % width, pixel / width);
            let inside = (x + y / 2) % 97 < 40;
            match (inside, channel) {
                (false, _) => 0,
                (true, 3) => 255,
                (true, _) => ((x * 3 + y + channel * 40) % 256) as u8 ^ (noise.next() as u8 & 1),
            }
        })
        .collect();
    let periodic = |period: usize| -> Vec<u8> { (0..size).map(|at| (at % period * 37 % 251) as u8).collect() };
    let sparse: Vec<u8> = (0..size).map(|_| if noise.below(64) == 0 { noise.next() as u8 } else { 0 }).collect();
    let skewed: Vec<u8> = (0..size).map(|_| (noise.next().trailing_zeros().min(20) as u8) + b'a').collect();
    let mut mixed = Vec::with_capacity(size);
    while mixed.len() < size {
        let take = (noise.below(5000) + 1).min(size - mixed.len());
        let from = noise.below(4);
        let source = [&random, &text, &cel, &sparse][from];
        let start = noise.below(size.max(1));
        mixed.extend((0..take).map(|k| source[(start + k) % size.max(1)]));
    }
    vec![
        ("zeros", vec![0; size]),
        ("random", random),
        ("text", text),
        ("cel", cel),
        ("period-1", periodic(1)),
        ("period-3", periodic(3)),
        ("period-7", periodic(7)),
        ("period-23", periodic(23)),
        ("sparse", sparse),
        ("skewed", skewed),
        ("mixed", mixed),
    ]
}

const SIZES: [usize; 21] = [
    1, 2, 3, 7, 8, 31, 32, 33, 100, 255, 256, 1000, 4095, 65535, 65536, 65537, 131071, 131072, 131073, 300_000,
    1_000_000,
];

// Every kind of input at every size the block and literal limits turn on,
// at the app's level and around it: the Rust writes what the C writes,
// into an exact buffer, one with room to spare, one with room for its
// literals behind the block, and one a byte short.
#[test]
fn every_frame_the_c_makes_decodes_to_the_c_s_bytes() {
    for &size in &SIZES {
        for (kind, data) in kinds(size, size as u64) {
            let levels: &[i32] = if size <= 131_073 { &[-5, 1, 3, 9, 19] } else { &[1, 9] };
            for &level in levels {
                let (frame, _) = frame(&data, level);
                let what = format!("{kind} × {size} at level {level}");
                for (capacity, room) in [(size, ""), (size + 100, ", room to spare"), (size + 300_000, ", literals behind the block")] {
                    let what = format!("{what}{room}");
                    assert_eq!(same_answer(None, &frame, capacity, &what), size as i64, "{what}: decoded whole");
                    assert_eq!(decoded(crate::qa_zstd_decompress, &frame, capacity).1, data, "{what}: the input back");
                }
                let what = format!("{what}, a byte short");
                assert_eq!(same_answer(None, &frame, size - 1, &what), 0, "{what}: nothing");
            }
        }
    }
}

/// `frame` with byte `at` set to `value`.
fn with(frame: &[u8], at: usize, value: u8) -> Vec<u8> {
    let mut damaged = frame.to_vec();
    damaged[at] = value;
    damaged
}

// Damage a frame as a disk or a cut-off save does — a bit flipped, a byte
// replaced, the end cut, a byte inserted — and the Rust refuses what the C
// refuses and writes what the C writes from what it accepts: no checksum
// guards a frame the app writes, so a damaged one can decode to other
// bytes, and those must be the C's. Each frame is damaged by noise of its
// own: one frame gone with the C leaves the others' damage as it was.
#[test]
fn a_damaged_frame_is_refused_or_decoded_as_the_c_does() {
    let mut answers = Answers::default();
    let mut refused = 0;
    let mut runs = 0;
    for &size in &[33, 1000, 4095, 65537, 131073, 300_000] {
        for (k, (kind, data)) in kinds(size, size as u64 ^ 0xC0FFEE).into_iter().enumerate() {
            for level in [1, 9, 19] {
                if level == 19 && size > 131_073 {
                    continue;
                }
                let (frame, kept) = frame(&data, level);
                let mut noise = Noise(0x5EED ^ (size as u64) << 16 ^ (level as u64) << 8 ^ k as u64);
                for damage in 0..60 {
                    let at = noise.below(frame.len());
                    let damaged = match damage % 4 {
                        0 => with(&frame, at, frame[at] ^ (1 << noise.below(8))),
                        1 => with(&frame, at, noise.next() as u8),
                        2 => frame[..at.max(1)].to_vec(),
                        _ => {
                            let mut longer = frame.clone();
                            longer.insert(at, noise.next() as u8);
                            longer
                        }
                    };
                    let what = format!("{kind} × {size} at level {level}, damage {damage} at {at}");
                    for capacity in [size, size + 300_000] {
                        refused += usize::from(same_answer(kept.then_some(&mut answers), &damaged, capacity, &what) == 0);
                        runs += 1;
                    }
                }
            }
        }
    }
    // LIVENESS — the damage reached both outcomes.
    assert!(refused > runs / 4 && refused < runs, "{refused} of {runs} refused");
    answers.pinned("compress/decode-damaged");
}

/// A skippable frame of `payload`, with magic variant `variant`.
fn skippable(variant: u8, payload: &[u8]) -> Vec<u8> {
    let mut frame = (frame_header::SKIPPABLE_START + u32::from(variant)).to_le_bytes().to_vec();
    frame.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    frame.extend_from_slice(payload);
    frame
}

// Frames one after another, skippable frames between, and what is left
// over after them.
#[test]
fn frames_in_a_row_decode_as_the_c_decodes_them() {
    let mut answers = Answers::default();
    let parts: Vec<Vec<u8>> = kinds(70_000, 7).into_iter().take(5).map(|(_, data)| data).collect();
    let (frames, kept): (Vec<Vec<u8>>, Vec<bool>) =
        parts.iter().enumerate().map(|(k, data)| frame(data, [1, 9, 3, 19, -5][k])).unzip();
    assert!(kept.iter().all(|&kept| kept), "every frame of the row outlives the C");
    let total: usize = parts.iter().map(Vec::len).sum();
    let mut row = Vec::new();
    for (k, frame) in frames.iter().enumerate() {
        row.extend(skippable(k as u8, &vec![k as u8; k * 3]));
        row.extend_from_slice(frame);
    }
    assert_eq!(same_answer(Some(&mut answers), &row, total, "frames in a row"), total as i64);
    let all: Vec<u8> = parts.concat();
    assert_eq!(decoded(crate::qa_zstd_decompress, &row, total).1, all);
    same_answer(Some(&mut answers), &row, total - 1, "a byte short of the last");
    for tail in [&[0u8][..], &[1, 2, 3, 4], &[0x28, 0xB5, 0x2F, 0xFD], &[0x28, 0xB5, 0x2F, 0xFD, 0x20], &[0x50, 0x2A, 0x4D, 0x18, 9, 0, 0, 0]] {
        let mut trailed = row.clone();
        trailed.extend_from_slice(tail);
        same_answer(Some(&mut answers), &trailed, total, &format!("trailed by {tail:?}"));
    }
    same_answer(Some(&mut answers), &skippable(15, b"alone"), 16, "a skippable frame alone");
    same_answer(Some(&mut answers), &[skippable(0, &[]), frames[0].clone()].concat(), parts[0].len(), "an empty skippable first");
    let mut overlong = skippable(1, b"xx");
    overlong[4] = 0xFF;
    let overlong = [overlong, frames[0].clone()].concat();
    same_answer(Some(&mut answers), &overlong, parts[0].len(), "a skippable frame longer than what is left");
    answers.pinned("compress/decode-frames-in-a-row");
}

/// The blocks of a frame: where each one's body starts, its kind, and the
/// body's length.
fn blocks(frame: &[u8]) -> Vec<(usize, usize, usize)> {
    let mut at = frame_header::size(frame[4]);
    let mut found = Vec::new();
    loop {
        let word = frame_header::le(&frame[at..at + 3]) as usize;
        let (kind, size) = ((word >> 1) & 3, word >> 3);
        let length = if kind == 1 { 1 } else { size };
        found.push((at + 3, kind, length));
        at += 3 + length;
        if word & 1 == 1 {
            return found;
        }
    }
}

// A block's literals may repeat the tree of a block before them — and the
// first block's, with none before it, are refused.
#[test]
fn literals_repeat_only_a_tree_already_read() {
    let data = kinds(20_000, 5).swap_remove(2).1;
    let (frame, _) = frame(&data, 9);
    let (body, kind, _) = blocks(&frame)[0];
    assert_eq!((kind, frame[body] & 3), (2, 2), "the first block's literals are Huffman-coded");
    let repeated = with(&frame, body, frame[body] | 3);
    assert_eq!(same_answer(None, &repeated, data.len(), "the first literals repeating a tree"), 0);
}

// A match far behind and long, a few literals into a block, whose offset
// and length take 32 bits together — more than are left after them, fewer
// than a sequence with long literals too: the stream reloads in the middle
// of the sequence.
#[test]
fn a_far_long_match_decodes_as_the_c_s() {
    let mut answers = Answers::default();
    let mut noise = Noise(77);
    let mut echo: Vec<u8> = (0..(256 << 10) + 5).map(|_| noise.next() as u8).collect();
    echo.extend_from_within(50_000..50_000 + 65_536);
    for level in [1, 9, 19] {
        let (frame, kept) = frame(&echo, level);
        let answer = same_answer(kept.then_some(&mut answers), &frame, echo.len(), &format!("level {level}"));
        assert_eq!(answer, echo.len() as i64);
    }
    answers.pinned("compress/decode-far-long-match");
}

// The sequence count in each of its forms, the three-byte one included —
// pinned by hand, by the format's own words (RFC 8878 3.1.1.3.2.1): it
// takes more than 0x7F00 sequences in a block, and no input tried made the
// C's compressor write more than 19,868 (2026-11-06).
#[test]
fn a_count_is_read_in_each_of_its_forms() {
    let forms: [(&[u8], usize); 6] = [
        (&[0x7F, 0], 0x7F),
        (&[0x80, 0x80, 0], 0x80),
        (&[0xFE, 0xFF, 0], 0x7EFF),
        (&[0xFF, 0, 0, 0], 0x7F00),
        (&[0xFF, 0x34, 0x12, 0], 0x7F00 + 0x1234),
        (&[0xFF, 0xFF, 0xFF, 0], 0x7F00 + 0xFFFF),
    ];
    for (header, count) in forms {
        let mut entropy = sequences::Entropy::new();
        assert_eq!(sequences::read_header(&mut entropy, header), Ok((count, header.len())), "{header:02x?}");
    }
}

/// `frame` (the C's: single segment, its size stated) with its header
/// rewritten — a window descriptor instead of the single segment, the size
/// stated or not, a checksum appended or not.
fn reheaded(frame: &[u8], window: u8, state_size: bool, checksum: Option<&[u8]>) -> Vec<u8> {
    let old = frame_header::size(frame[4]);
    let content = frame_header::read(frame).expect("the C's frame").content_size;
    let mut out = frame[..4].to_vec();
    let (size_code, size_bytes): (u8, Vec<u8>) = if !state_size {
        (0, vec![])
    } else if content < 256 + 65536 && content >= 256 {
        (1, ((content - 256) as u16).to_le_bytes().to_vec())
    } else {
        (2, (content as u32).to_le_bytes().to_vec())
    };
    out.push(size_code << 6 | u8::from(checksum.is_some()) << 2);
    out.push(window);
    out.extend(size_bytes);
    out.extend_from_slice(&frame[old..]);
    if let Some(data) = checksum {
        out.extend_from_slice(&(xxhash::xxh64(data, 0) as u32).to_le_bytes());
    }
    out
}

// Headers the app's frames never have, made by hand from the C's frames:
// a window instead of a single segment — small and large, between a
// block's literals and its whole, a power of two and between two — no size
// stated; a checksum — the C checks it with its own XXH64, so its answer
// is also the Rust hash's — right and wrong; a dictionary asked for;
// reserved bits.
#[test]
fn every_header_decodes_as_the_c_reads_it() {
    let mut answers = Answers::default();
    for (kind, data) in kinds(150_000, 99).into_iter().step_by(2) {
        let (frame, _) = frame(&data, 9);
        let windows = [0x00, 0x08, 0x0F, 0x10, 0x17, 0x18, 0x1D, 0x20, 0x2B, 0x38, 0x3F, 0x40, 0x48, 0x58, 0x70, 0xA8, 0xF8, 0xFF];
        for window in windows {
            for state_size in [true, false] {
                let what = format!("{kind}, window {window:#x}, size stated {state_size}");
                same_answer(Some(&mut answers), &reheaded(&frame, window, state_size, None), data.len(), &what);
                let checked = reheaded(&frame, window, state_size, Some(&data));
                same_answer(Some(&mut answers), &checked, data.len(), &format!("{what}, checksum"));
                let wrong = checked.len() - 1;
                let damaged = with(&checked, wrong, checked[wrong] ^ 1);
                same_answer(Some(&mut answers), &damaged, data.len(), &format!("{what}, checksum wrong"));
                same_answer(Some(&mut answers), &checked[..checked.len() - 2], data.len(), &format!("{what}, checksum cut"));
            }
        }
        // The dictionary's id goes after the window byte, before the size.
        let mut dictionary = frame.clone();
        dictionary[4] |= 1;
        dictionary.insert(frame_header::PREFIX + usize::from(frame[4] >> 5 & 1 == 0), 7);
        same_answer(Some(&mut answers), &dictionary, data.len(), &format!("{kind}, a dictionary asked for"));
        same_answer(Some(&mut answers), &with(&frame, 4, frame[4] | 0x08), data.len(), &format!("{kind}, a reserved bit"));
    }
    // Every length of checksummed frame up to two stripes and a tail (the
    // C compresses nothing to no frame).
    for size in 1..80 {
        let data: Vec<u8> = (0..size).map(|k| (k * 7 + 1) as u8).collect();
        let (frame, kept) = frame(&data, 3);
        assert!(kept, "checksummed {size}: the frame outlives the C");
        let checked = reheaded(&frame, 0x50, true, Some(&data));
        assert_eq!(same_answer(Some(&mut answers), &checked, size, &format!("checksummed {size}")), size as i64);
    }
    answers.pinned("compress/decode-every-header");
}

// A block that writes a little past a window smaller than itself — of a
// power of two and of sizes between two — into buffers from exactly its
// size up past the room its literals take behind it: how far a block may
// write is its window or the buffer, by where the C keeps its literals.
#[test]
fn a_block_past_a_small_window_stops_where_the_c_s_does() {
    let mut answers = Answers::default();
    let (mut accepted, mut refused) = (0, 0);
    for window in [0x00u8, 0x07, 0x08, 0x0F, 0x10, 0x13, 0x17, 0x18] {
        let log = u32::from(window >> 3) + 10;
        let window_size = (1usize << log) + ((1usize << log) >> 3) * usize::from(window & 7);
        for size in (window_size + 16..window_size + 100).step_by(3) {
            let chosen = ["period-7", "text", "sparse", "mixed"];
            for (kind, data) in kinds(size, size as u64).into_iter().filter(|(kind, _)| chosen.contains(kind)) {
                let frame = reheaded(&frame(&data, 9).0, window, true, None);
                for capacity in (size..size + 96).step_by(2).chain([size + 5000]) {
                    let what = format!("{kind} × {size}, window {window:#x}, room {capacity}");
                    match same_answer(Some(&mut answers), &frame, capacity, &what) {
                        0 => refused += 1,
                        _ => accepted += 1,
                    }
                }
            }
        }
    }
    // LIVENESS — the window let some blocks through and stopped others.
    assert!(accepted > 0 && refused > 0, "{accepted} accepted, {refused} refused");
    answers.pinned("compress/decode-small-window");
}

// The size Dart allocates by: the C's answer for every frame header, for
// every prefix of one, and for what is not one.
#[test]
fn the_stated_size_is_the_c_s() {
    // SAFETY: qa_compress.c — `int64_t qa_zstd_decompressed_size(const uint8_t*, int64_t)`.
    let c = unsafe { export::<Size>("qa_zstd_decompressed_size") };
    let mut answers = Answers::default();
    let mut frames: Vec<Vec<u8>> = SIZES.iter().map(|&size| frame(&vec![9u8; size], 9).0).collect();
    let data = vec![1u8; 70_000];
    let (frame, kept) = frame(&data, 1);
    assert!(kept, "the frame at level 1 outlives the C");
    frames.extend([0x00, 0x48, 0xF0, 0xF8].map(|window| reheaded(&frame, window, true, None)));
    frames.push(reheaded(&frame, 0x48, false, None));
    frames.push(skippable(3, b"skip"));
    frames.push(with(&frame, 4, frame[4] | 0x08));
    frames.push(with(&frame, 0, 0x29));
    for frame in &frames {
        for end in 0..=frame.len().min(24) {
            let prefix = &frame[..end];
            // SAFETY: the slice holds the length passed.
            let theirs = unsafe { c(prefix.as_ptr(), prefix.len() as i64) };
            // SAFETY: as above.
            let ours = unsafe { crate::qa_zstd_decompressed_size(prefix.as_ptr(), prefix.len() as i64) };
            assert_eq!(ours, theirs, "{:02x?}", prefix);
            answers.add(ours, &[]);
        }
    }
    answers.pinned("compress/stated-size");
    // SAFETY: null is nothing.
    assert_eq!(unsafe { crate::qa_zstd_decompressed_size(std::ptr::null(), 8) }, -1);
}

// The bound every buffer is sized by, at the sizes its margin turns on —
// the C's answers, measured 2026-11-07 (connection-round-checklist A):
// nothing for no size, and past i64's end the sum wraps, as the C's does.
#[test]
fn the_bound_is_the_c_s() {
    // SAFETY: qa_compress.c — `int64_t qa_zstd_compress_bound(int64_t)`.
    let c = unsafe { export::<Bound>("qa_zstd_compress_bound") };
    for (size, bound) in [
        (i64::MIN, 0),
        (-1, 0),
        (0, 0),
        (1, 64),
        (2, 65),
        (255, 318),
        (256, 320),
        (2047, 2117),
        (2048, 2119),
        (131_071, 131_582),
        (131_072, 131_584),
        (131_073, 131_585),
        (1 << 30, 1_077_936_128),
        ((1 << 40) + 5, 1_103_806_595_077),
        (0xFF00_FF00_FF00_FEFFu64 as i64, 0),
        (0xFF00_FF00_FF00_FF00u64 as i64, 0),
        (i64::MAX, -9_187_343_239_835_811_842),
    ] {
        assert_eq!(crate::qa_zstd_compress_bound(size), c(size), "{size}");
        assert_eq!(crate::qa_zstd_compress_bound(size), bound, "{size}");
    }
}

// Pointers that are null and sizes that are not sizes come back 0, as the
// C's do.
#[test]
fn nothing_to_decode_is_refused() {
    let (frame, _) = frame(b"cel", 9);
    let mut out = [0u8; 8];
    for (dst, capacity, src, size) in [
        (std::ptr::null_mut(), 8, frame.as_ptr(), frame.len() as i64),
        (out.as_mut_ptr(), 8, std::ptr::null(), frame.len() as i64),
        (out.as_mut_ptr(), 0, frame.as_ptr(), frame.len() as i64),
        (out.as_mut_ptr(), -8, frame.as_ptr(), frame.len() as i64),
        (out.as_mut_ptr(), 8, frame.as_ptr(), 0),
        (out.as_mut_ptr(), 8, frame.as_ptr(), -1),
    ] {
        // SAFETY: every pointer passed is null or holds what is passed.
        let answers = unsafe { (crate::qa_zstd_decompress(dst, capacity, src, size), c_decompress()(dst, capacity, src, size)) };
        assert_eq!(answers, (0, 0));
    }
}

/// The C's predefined sequence table `name`, as zstd.c prints it.
fn c_default_table(name: &str) -> Vec<sequences::Cell> {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let path = format!("{crate_dir}/../../../../qa_native/src/third_party/zstd/zstd.c");
    let c = std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("{path}: {error}"));
    let start = c.find(&format!("static const ZSTD_seqSymbol {name}[")).unwrap_or_else(|| panic!("zstd.c declares {name}"));
    let body = &c[start..start + c[start..].find("};").expect("the table ends")];
    // Past the declaration, the array's own brace and the header cell.
    let numbers: Vec<u32> = body
        .split('{')
        .skip(3)
        .flat_map(|cell| cell.split('}').next().unwrap().split(',').map(|n| n.trim().parse().unwrap()).collect::<Vec<u32>>())
        .collect();
    numbers
        .chunks(4)
        .map(|cell| sequences::Cell { next_state: cell[0] as u16, extra_bits: cell[1] as u8, nb_bits: cell[2] as u8, base: cell[3] })
        .collect()
}

// The predefined tables the Rust builds from the default distributions are
// the ones zstd ships precomputed.
#[test]
fn the_predefined_tables_are_zstd_s() {
    let ours = sequences::defaults();
    for (k, name) in ["LL_defaultDTable", "OF_defaultDTable", "ML_defaultDTable"].into_iter().enumerate() {
        let theirs = c_default_table(name);
        assert_eq!(theirs.len(), 1 << ours[k].log, "{name}: every cell parsed");
        assert_eq!(ours[k].cells[..theirs.len()], theirs, "{name}");
    }
}
