//! The Rust decoder held to what the C engine's decoder answered: the
//! frames the C wrote that outlive it decoded — every answer and every
//! byte written held to the ledger, on good frames and on damaged ones.
//! ↩️Until the connection round deleted the C (connection-round-checklist
//! H, 2026-11-08) both decoders were asked side by side (native/oracle),
//! on the C's every frame; what outlives it was kept before it went
//! (connection-round-checklist A, 관제 2026-11-07).

use crate::{frame_header, sequences, xxhash};

type Decompress = unsafe extern "C" fn(*mut u8, i64, *const u8, i64) -> i64;

/// What a decoder answers for `frame` into `capacity` bytes, and the bytes
/// it says it wrote.
fn decoded(decompress: Decompress, frame: &[u8], capacity: usize) -> (i64, Vec<u8>) {
    let mut out = vec![0u8; capacity.max(1)];
    // SAFETY: both buffers hold the sizes passed.
    let answer = unsafe { decompress(out.as_mut_ptr(), capacity as i64, frame.as_ptr(), frame.len() as i64) };
    out.truncate(answer.max(0) as usize);
    (answer, out)
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
// 10 KiB that a test here decodes — the C's compressor frozen
// for small inputs before it went (connection-round-checklist A ②,
// 관제 2026-11-07). Level 9 needs none: it is the Rust compressor's own.
// A frame of the C's past 10 KiB went with it, and its case with it.
// Records, little-endian: the level (i32), the input's length (u64) and
// its fingerprint (8 hex digits), the frame's length (u32), the frame.
const C_FRAMES: &[u8] = include_bytes!("../fixtures/c_frames.bin");

/// The frame of `data` at `level` that outlives the C, if there is one.
pub(crate) fn kept_frame(data: &[u8], level: i32) -> Option<Vec<u8>> {
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

/// The frame of `data` at `level` that outlives the C, which a case says
/// it decodes.
fn kept(data: &[u8], level: i32, what: &str) -> Vec<u8> {
    kept_frame(data, level).unwrap_or_else(|| panic!("{what}: c_frames.bin keeps the C's frame at level {level}"))
}

/// The decoder on `frame` into `capacity`: its answer — which goes into
/// `answers`, where there are any, with the bytes it wrote.
fn answer(answers: Option<&mut Answers>, frame: &[u8], capacity: usize) -> i64 {
    let ours = decoded(crate::qa_zstd_decompress, frame, capacity);
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
// at the app's level and around it — each frame that outlives the C — into
// an exact buffer, one with room to spare, one with room for its literals
// behind the block, and one a byte short: the input back, or nothing.
#[test]
fn every_frame_the_c_makes_decodes_to_the_c_s_bytes() {
    for &size in &SIZES {
        for (kind, data) in kinds(size, size as u64) {
            let levels: &[i32] = if size <= 131_073 { &[-5, 1, 3, 9, 19] } else { &[1, 9] };
            for &level in levels {
                let Some(frame) = kept_frame(&data, level) else { continue };
                let what = format!("{kind} × {size} at level {level}");
                for (capacity, room) in [(size, ""), (size + 100, ", room to spare"), (size + 300_000, ", literals behind the block")] {
                    let what = format!("{what}{room}");
                    let (written, back) = decoded(crate::qa_zstd_decompress, &frame, capacity);
                    assert_eq!(written, size as i64, "{what}: decoded whole");
                    assert_eq!(back, data, "{what}: the input back");
                }
                assert_eq!(answer(None, &frame, size - 1), 0, "{what}, a byte short: nothing");
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
// refused and writes what the C wrote from what it accepts: no checksum
// guards a frame the app writes, so a damaged one can decode to other
// bytes, and those must be the C's (the ledger's). Each frame is damaged by
// noise of its own: one frame gone with the C leaves the others' damage as
// it was.
#[test]
fn a_damaged_frame_is_refused_or_decoded_as_the_c_does() {
    let mut answers = Answers::default();
    let mut refused = 0;
    let mut runs = 0;
    for &size in &[33, 1000, 4095, 65537, 131073, 300_000] {
        for (k, (_, data)) in kinds(size, size as u64 ^ 0xC0FFEE).into_iter().enumerate() {
            for level in [1, 9, 19] {
                if level == 19 && size > 131_073 {
                    continue;
                }
                let Some(frame) = kept_frame(&data, level) else { continue };
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
                    for capacity in [size, size + 300_000] {
                        refused += usize::from(answer(Some(&mut answers), &damaged, capacity) == 0);
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
    let frames: Vec<Vec<u8>> =
        parts.iter().enumerate().map(|(k, data)| kept(data, [1, 9, 3, 19, -5][k], "a frame of the row")).collect();
    let total: usize = parts.iter().map(Vec::len).sum();
    let mut row = Vec::new();
    for (k, frame) in frames.iter().enumerate() {
        row.extend(skippable(k as u8, &vec![k as u8; k * 3]));
        row.extend_from_slice(frame);
    }
    assert_eq!(answer(Some(&mut answers), &row, total), total as i64);
    let all: Vec<u8> = parts.concat();
    assert_eq!(decoded(crate::qa_zstd_decompress, &row, total).1, all);
    answer(Some(&mut answers), &row, total - 1);
    for tail in [&[0u8][..], &[1, 2, 3, 4], &[0x28, 0xB5, 0x2F, 0xFD], &[0x28, 0xB5, 0x2F, 0xFD, 0x20], &[0x50, 0x2A, 0x4D, 0x18, 9, 0, 0, 0]] {
        let mut trailed = row.clone();
        trailed.extend_from_slice(tail);
        answer(Some(&mut answers), &trailed, total);
    }
    answer(Some(&mut answers), &skippable(15, b"alone"), 16);
    answer(Some(&mut answers), &[skippable(0, &[]), frames[0].clone()].concat(), parts[0].len());
    let mut overlong = skippable(1, b"xx");
    overlong[4] = 0xFF;
    let overlong = [overlong, frames[0].clone()].concat();
    answer(Some(&mut answers), &overlong, parts[0].len());
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
    let frame = kept(&data, 9, "text × 20000");
    let (body, kind, _) = blocks(&frame)[0];
    assert_eq!((kind, frame[body] & 3), (2, 2), "the first block's literals are Huffman-coded");
    let repeated = with(&frame, body, frame[body] | 3);
    assert_eq!(answer(None, &repeated, data.len()), 0);
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
        let Some(frame) = kept_frame(&echo, level) else { continue };
        assert_eq!(answer(Some(&mut answers), &frame, echo.len()), echo.len() as i64, "level {level}");
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
        let frame = kept(&data, 9, kind);
        let windows = [0x00, 0x08, 0x0F, 0x10, 0x17, 0x18, 0x1D, 0x20, 0x2B, 0x38, 0x3F, 0x40, 0x48, 0x58, 0x70, 0xA8, 0xF8, 0xFF];
        for window in windows {
            for state_size in [true, false] {
                answer(Some(&mut answers), &reheaded(&frame, window, state_size, None), data.len());
                let checked = reheaded(&frame, window, state_size, Some(&data));
                answer(Some(&mut answers), &checked, data.len());
                let wrong = checked.len() - 1;
                let damaged = with(&checked, wrong, checked[wrong] ^ 1);
                answer(Some(&mut answers), &damaged, data.len());
                answer(Some(&mut answers), &checked[..checked.len() - 2], data.len());
            }
        }
        // The dictionary's id goes after the window byte, before the size.
        let mut dictionary = frame.clone();
        dictionary[4] |= 1;
        dictionary.insert(frame_header::PREFIX + usize::from(frame[4] >> 5 & 1 == 0), 7);
        answer(Some(&mut answers), &dictionary, data.len());
        answer(Some(&mut answers), &with(&frame, 4, frame[4] | 0x08), data.len());
    }
    // Every length of checksummed frame up to two stripes and a tail (the
    // C compresses nothing to no frame).
    for size in 1..80 {
        let data: Vec<u8> = (0..size).map(|k| (k * 7 + 1) as u8).collect();
        let frame = kept(&data, 3, &format!("checksummed {size}"));
        let checked = reheaded(&frame, 0x50, true, Some(&data));
        assert_eq!(answer(Some(&mut answers), &checked, size), size as i64);
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
                let frame = reheaded(&kept(&data, 9, kind), window, true, None);
                for capacity in (size..size + 96).step_by(2).chain([size + 5000]) {
                    match answer(Some(&mut answers), &frame, capacity) {
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

// The size Dart allocates by: the C's answer (the ledger's) for every frame
// header, for every prefix of one, and for what is not one.
#[test]
fn the_stated_size_is_the_c_s() {
    let mut answers = Answers::default();
    let mut frames: Vec<Vec<u8>> = SIZES.iter().map(|&size| kept(&vec![9u8; size], 9, "nines")).collect();
    let data = vec![1u8; 70_000];
    let frame = kept(&data, 1, "ones × 70000");
    frames.extend([0x00, 0x48, 0xF0, 0xF8].map(|window| reheaded(&frame, window, true, None)));
    frames.push(reheaded(&frame, 0x48, false, None));
    frames.push(skippable(3, b"skip"));
    frames.push(with(&frame, 4, frame[4] | 0x08));
    frames.push(with(&frame, 0, 0x29));
    for frame in &frames {
        for end in 0..=frame.len().min(24) {
            let prefix = &frame[..end];
            // SAFETY: the slice holds the length passed.
            let ours = unsafe { crate::qa_zstd_decompressed_size(prefix.as_ptr(), prefix.len() as i64) };
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
        assert_eq!(crate::qa_zstd_compress_bound(size), bound, "{size}");
    }
}

// Pointers that are null and sizes that are not sizes come back 0, as the
// C's did.
#[test]
fn nothing_to_decode_is_refused() {
    let frame = kept(b"cel", 9, "cel");
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
        assert_eq!(unsafe { crate::qa_zstd_decompress(dst, capacity, src, size) }, 0);
    }
}

// The predefined tables the Rust builds from the default distributions are
// the ones zstd ships precomputed — `LL_defaultDTable`, `OF_defaultDTable`
// and `ML_defaultDTable` of zstd 1.5.6, held to the ledger: each table's
// cells, then each cell's fields. ↩️Read from the vendored zstd.c's text
// until the connection round deleted it (connection-round-checklist H,
// 2026-11-08), and pinned from that text before it went (관제 20:18).
#[test]
fn the_predefined_tables_are_zstd_s() {
    let mut tables = ledger::Running::new();
    for table in sequences::defaults() {
        let cells = &table.cells[..1 << table.log];
        tables.add(&(cells.len() as u32).to_le_bytes());
        for cell in cells {
            tables.add(&cell.next_state.to_le_bytes());
            tables.add(&[cell.extra_bits, cell.nb_bits]);
            tables.add(&cell.base.to_le_bytes());
        }
    }
    tables.assert_pinned("compress/default-tables");
}
