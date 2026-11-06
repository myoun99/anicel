//! The Rust compressor against the engine's C (native/oracle): every frame
//! held to the bytes `qa_zstd_compress(…, 9)` writes, and decoded back by
//! the Rust decoder.

use oracle::export;

use super::compress;
use crate::tests::{Noise, compressed, kinds};

type Compress = unsafe extern "C" fn(*mut u8, i64, *const u8, i64, i32) -> i64;
type Bound = extern "C" fn(i64) -> i64;

/// The C's answer for `data` into `capacity` bytes: its frame, or None
/// where it answers 0.
fn c_compress(data: &[u8], capacity: usize) -> Option<Vec<u8>> {
    // SAFETY: qa_compress.c — `int64_t qa_zstd_compress(uint8_t*, int64_t, const uint8_t*, int64_t, int32_t)`.
    let compress = unsafe { export::<Compress>("qa_zstd_compress") };
    let mut frame = vec![0u8; capacity.max(1)];
    // SAFETY: both buffers hold the sizes passed.
    let written = unsafe { compress(frame.as_mut_ptr(), capacity as i64, data.as_ptr(), data.len() as i64, 9) };
    (written > 0).then(|| {
        frame.truncate(written as usize);
        frame
    })
}

/// The Rust's answer for `data` into `capacity` bytes.
fn ours(data: &[u8], capacity: usize) -> Option<Vec<u8>> {
    let mut frame = vec![0u8; capacity];
    compress(&mut frame, data).map(|written| {
        frame.truncate(written);
        frame
    })
}

fn bound(size: usize) -> usize {
    // SAFETY: qa_compress.c — `int64_t qa_zstd_compress_bound(int64_t)`.
    let bound = unsafe { export::<Bound>("qa_zstd_compress_bound") };
    bound(size as i64) as usize
}

/// The Rust's frame of `data` is the C's, and decodes to `data`.
fn same_frame(data: &[u8], what: &str) {
    let theirs = compressed(data, 9);
    let mine = ours(data, bound(data.len())).unwrap_or_else(|| panic!("{what}: the Rust compresses it"));
    let first = mine.iter().zip(&theirs).position(|(a, b)| a != b);
    assert!(
        first.is_none() && mine.len() == theirs.len(),
        "{what}: {} bytes where the C writes {}, first apart at {first:?}",
        mine.len(),
        theirs.len(),
    );
    let mut back = vec![0u8; data.len()];
    assert_eq!(crate::frame::decompress(&mut back, &mine), Ok(data.len()), "{what}: decoded whole");
    assert!(back == data, "{what}: the input back");
}

// Sizes at each turn of level 9: the window shrunk to small inputs, the
// tree up to 16 KiB and the rows past it, the parameter rows at 128 KiB
// and 256 KiB, the content size's forms, stored blocks under 7 bytes, and
// blocks of 128 KiB in a row behind a window of 4 MiB.
const SIZES: [usize; 30] = [
    1, 2, 6, 7, 8, 63, 64, 65, 100, 255, 256, 1000, 1024, 1025, 4095, 16383, 16384, 16385, 65535, 65791, 65792,
    131_071, 131_072, 131_073, 131_075, 131_078, 262_144, 262_145, 300_000, 1_000_000,
];

#[test]
fn every_input_compresses_to_the_c_s_frame() {
    for &size in &SIZES {
        for (kind, data) in kinds(size, size as u64) {
            same_frame(&data, &format!("{kind} × {size}"));
        }
    }
}

/// `size` bytes cut from every kind at random lengths.
fn cut(noise: &mut Noise, size: usize) -> Vec<u8> {
    let pieces = kinds(size, noise.next());
    let mut data = Vec::with_capacity(size);
    while data.len() < size {
        let (_, source) = &pieces[noise.below(pieces.len())];
        let take = (noise.below(70_000) + 1).min(size - data.len());
        let start = noise.below(size - take + 1);
        data.extend_from_slice(&source[start..start + take]);
    }
    data
}

// Inputs cut from every kind at random lengths, and runs of one byte after
// coded blocks — the later blocks sent as the byte repeated, the first
// never.
#[test]
fn mixed_inputs_compress_to_the_c_s_frame() {
    let mut noise = Noise(0x9E37_79B9_7F4A_7C15);
    for round in 0..40 {
        let size = noise.below(400_000) + 1;
        same_frame(&cut(&mut noise, size), &format!("round {round}, {size} bytes"));
    }
    for &(head, tail) in &[(131_072, 131_072), (131_072, 5), (131_072, 30), (16_384, 1), (200_000, 300_000)] {
        let mut data = kinds(head, head as u64).swap_remove(2).1;
        data.extend(std::iter::repeat_n(7u8, tail));
        same_frame(&data, &format!("text × {head}, then 7 × {tail}"));
    }
}

// Too small a destination: the Rust refuses where the C answers 0, and
// writes what the C writes where it does not — a block stored, say, that
// the room did not take coded.
#[test]
fn a_short_destination_is_answered_as_the_c_answers_it() {
    for &size in &[1, 7, 100, 5000, 16_385, 140_000] {
        for (kind, data) in kinds(size, size as u64 + 1) {
            let whole = compressed(&data, 9).len();
            let mut capacities: Vec<usize> = (0..24).collect();
            capacities.extend([whole / 2, whole - 4, whole - 3, whole - 1, whole, whole + 1]);
            capacities.extend((0..8).map(|k| whole * (k + 1) / 9));
            for capacity in capacities {
                let what = format!("{kind} × {size} into {capacity}");
                assert!(ours(&data, capacity) == c_compress(&data, capacity), "{what}: the Rust's answer is the C's");
            }
        }
    }
}

#[test]
fn nothing_to_compress_is_refused() {
    assert_eq!(compress(&mut [0u8; 64], &[]), None);
    assert_eq!(compress(&mut [], b"cel"), None);
}

/// `count` letters of `alphabet` from `first` on — `first` one in eight,
/// the rest even: worth a Huffman tree, and four in a row repeated only by
/// chance.
fn letters(noise: &mut Noise, count: usize, alphabet: usize, first: u8) -> Vec<u8> {
    (0..count).map(|_| if noise.below(8) == 0 { first } else { first + noise.below(alphabet) as u8 }).collect()
}

/// `length` bytes onto `data`, each the one `offset` back: a match there.
fn copy(data: &mut Vec<u8>, offset: usize, length: usize) {
    for _ in 0..length {
        data.push(data[data.len() - offset]);
    }
}

/// `passes` rounds of the 128 letters from 128 on, each round shuffled:
/// every letter exactly as common as the next, four in a row repeated
/// only by chance.
fn rounds(noise: &mut Noise, passes: usize) -> Vec<u8> {
    let mut data = Vec::with_capacity(passes * 128);
    for _ in 0..passes {
        let mut round: Vec<u8> = (128..=255).collect();
        for at in (1..round.len()).rev() {
            round.swap(at, noise.below(at + 1));
        }
        data.extend(round);
    }
    data
}

/// `count` of the bytes in `range` turned into `letter`, spread across it.
fn boost(data: &mut [u8], range: std::ops::Range<usize>, letter: u8, count: usize) {
    let step = range.len() / (count + 1);
    for k in 1..=count {
        let mut at = range.start + step * k;
        while data[at] == letter {
            at += 1;
        }
        data[at] = letter;
    }
}

/// `count` bytes over the letters 0..=`max`, each as common as a power of
/// two from 1 down to 2^-`spread` of the most common, picked at random:
/// trees of many depths, their weights now easy to code and now not.
fn weighted(noise: &mut Noise, count: usize, max: usize, spread: usize) -> Vec<u8> {
    let weights: Vec<u64> = (0..=max).map(|_| 1u64 << noise.below(spread + 1)).collect();
    let total: u64 = weights.iter().sum();
    let mut data: Vec<u8> = (0..count)
        .map(|_| {
            let mut pick = noise.next() % total;
            let letter = weights.iter().position(|&weight| {
                if pick < weight {
                    return true;
                }
                pick -= weight;
                false
            });
            letter.expect("a letter") as u8
        })
        .collect();
    data[noise.below(count)] = max as u8;
    data
}

// Past 4 MiB the window no longer covers the input — a cel of the app's at
// full HD is 8 MiB: the frame states the window, and the oldest bytes fall
// out of a match's reach.
#[test]
fn a_frame_past_its_window_states_the_window() {
    for &size in &[4 << 20, (4 << 20) + 1, 8 << 20] {
        for (kind, data) in kinds(size, size as u64) {
            if matches!(kind, "text" | "cel" | "mixed") {
                same_frame(&data, &format!("{kind} × {size}"));
            }
        }
    }
    let mut noise = Noise(0x2F2C_9B6E_0A3D_57E1);
    for round in 0..3 {
        let size = (4 << 20) + noise.below(5 << 20);
        same_frame(&cut(&mut noise, size), &format!("past the window, round {round}, {size} bytes"));
    }
}

// The same cel again after other bytes: up to 4 MiB back the C matches it,
// past that it cannot reach it, and neither may the Rust.
#[test]
fn a_cel_seen_again_is_reached_back_as_far_as_the_window() {
    let cel = kinds(1 << 20, 11).into_iter().find(|(kind, _)| *kind == "cel").expect("a cel").1;
    let mut noise = Noise(0x7137_4491_B5C0_FBCF);
    for &between in &[(3 << 20) - 64, (3 << 20) - 1, 3 << 20, (3 << 20) + 1, (3 << 20) + 64, 9 << 19] {
        let mut data = cel.clone();
        data.extend(letters(&mut noise, between, 64, b'!'));
        data.extend_from_slice(&cel);
        same_frame(&data, &format!("a cel, {between} letters, the cel again"));
    }
}

// A block sent as its byte repeated hands the next block the repeat
// offsets and tables it was handed, as a stored block does: the block
// after it is coded against the block before.
#[test]
fn a_run_s_block_hands_on_what_it_was_handed() {
    for kind in ["text", "cel", "mixed"] {
        let piece = |seed: u64| kinds(131_072, seed).into_iter().find(|(name, _)| *name == kind).expect("a kind").1;
        let mut data = piece(1);
        data.extend(std::iter::repeat_n(7u8, 131_072));
        data.extend(piece(2));
        data.extend(piece(3));
        same_frame(&data, &format!("{kind}, a block of 7s, {kind} twice"));
    }
}

// A literal section at each turn of its form — one stream below 256
// literals and four from it, a 3-byte header below 1 KiB and 4 from it:
// the letters, then a run whose first byte is a literal too.
#[test]
fn a_literal_section_at_each_turn_of_its_form() {
    let mut noise = Noise(0x2545_F491_4F6C_DD1D);
    let all = letters(&mut noise, 1100, 64, b'!');
    for count in (236..=276).chain(1004..=1044) {
        let mut data = all[..count].to_vec();
        data.extend(std::iter::repeat_n(0u8, 300));
        same_frame(&data, &format!("{count} letters, then a run"));
    }
}

// A block at each count of sequences around 128, where the count's field
// grows a byte: letters, then copies of twelve of them from far back, two
// new letters before each.
#[test]
fn a_block_at_each_count_of_sequences() {
    let mut noise = Noise(0x6A09_E667_F3BC_C909);
    let mut data = letters(&mut noise, 4096, 64, b'!');
    for copies in 1..=144 {
        let from = noise.below(4096 - 12);
        data.extend(letters(&mut noise, 2, 64, b'!'));
        data.extend_from_within(from..from + 12);
        if copies >= 112 {
            same_frame(&data, &format!("{copies} copies"));
        }
    }
}

// Literals at the C's bars for "not worth a tree" — the first and last
// 4 KiB sampled when few sequences make it suspect them, then the whole
// count: each letter as common as the next, but one made a little more
// common a step at a time, across the sample's bar and then the count's.
#[test]
fn literals_at_the_bars_for_not_worth_a_tree() {
    let mut noise = Noise(0xBB67_AE85_84CA_A73B);
    let even = rounds(&mut noise, 512);
    let end = even.len();
    for extra in 0..=12 {
        let mut data = even.clone();
        boost(&mut data, 0..4096, 200, extra / 2);
        boost(&mut data, end - 4096..end, 200, extra - extra / 2);
        same_frame(&data, &format!("{extra} more of one letter at the ends"));
        // Each end past the sample's bar with a letter of its own; the one
        // letter between them across the count's.
        let mut data = even.clone();
        boost(&mut data, 0..4096, 140, 3);
        boost(&mut data, end - 4096..end, 150, 3);
        boost(&mut data, 4096..end - 4096, 200, extra);
        same_frame(&data, &format!("past the sample's bar, {extra} more in between"));
    }
}

// Twenty literals to a sequence is where the C starts to suspect them of
// not being worth a tree: the even letters, each run of them followed by
// four bytes from a fixed distance back — one letter more common only
// between the sampled ends, so that the whole count finds a tree worth it
// where the sample does not.
#[test]
fn literals_suspected_from_twenty_to_a_sequence() {
    let mut noise = Noise(0x3C6E_F372_FE94_F82B);
    let mut literals = rounds(&mut noise, 512);
    let end = literals.len();
    boost(&mut literals, 4096..end - 4096, 200, 20);
    for run in 19..=22 {
        let mut data = Vec::new();
        for piece in literals.chunks(run) {
            data.extend_from_slice(piece);
            if data.len() > 1000 {
                copy(&mut data, 1000, 4);
            }
        }
        same_frame(&data, &format!("{run} literals to a sequence"));
    }
}

// Trees over alphabets up to every last byte: their weights coded, or
// written four bits each (for 128 letters at most), and trees whose
// description leaves too little room for what they code.
#[test]
fn trees_of_every_width_are_described_as_the_c_describes_them() {
    let mut noise = Noise(0xA54F_F53A_5F1D_36F1);
    for &max in &[20, 40, 64, 100, 126, 127, 128, 129, 160, 200, 255] {
        for &spread in &[3, 6, 10] {
            for &count in &[72, 96, 128, 200, 3000, 20_000] {
                let data = weighted(&mut noise, count, max, spread);
                same_frame(&data, &format!("{count} over 0..={max}, spread {spread}"));
            }
        }
    }
}

// Letters exactly as common as each other, in a bucket past the counts
// sorted one apiece: the C sorts such a bucket unstably and builds the
// tree in the order it leaves — nine letters is where its insertion sort
// stops.
#[test]
fn letters_as_common_as_each_other_are_ordered_as_the_c_orders_them() {
    let mut noise = Noise(0x510E_527F_ADE6_82D1);
    for tied in [8u8, 9, 10, 16, 17] {
        for &each in &[200, 300, 600] {
            let mut ties: Vec<u8> = (0..tied).flat_map(|letter| std::iter::repeat_n(letter, each)).collect();
            for at in (1..ties.len()).rev() {
                ties.swap(at, noise.below(at + 1));
            }
            let data: Vec<u8> = ties.iter().flat_map(|&letter| [letter, 32 + noise.below(224) as u8]).collect();
            same_frame(&data, &format!("{tied} letters {each} times each"));
        }
    }
}

// Past a match 384 long the C enters only its first 96 and last 32
// positions: a match each length about that, then a look back into its
// middle — near, where the match went in whole, else as far back as the
// bytes it copied.
#[test]
fn a_long_match_is_entered_as_the_c_enters_it() {
    let mut noise = Noise(0x9B05_688C_2B3E_6C1F);
    let start = letters(&mut noise, 20_000, 64, b'!');
    let tail = letters(&mut noise, 2000, 64, b'!');
    for length in 372..=400 {
        let mut data = start.clone();
        data.extend_from_within(1000..1000 + length);
        data.extend(letters(&mut noise, 40, 64, b'!'));
        copy(&mut data, length + 40 - 200, 24);
        data.extend_from_slice(&tail);
        same_frame(&data, &format!("a match {length} long, then a look into it"));
    }
}

// A block that ends inside a long match has the next one start with only
// the last 192 positions before it entered: a look back from the new
// block to each position about the 192nd.
#[test]
fn a_block_after_a_long_match_sees_back_as_far_as_the_c_does() {
    let mut noise = Noise(0x1F83_D9AB_FB41_BD6B);
    let mut start = letters(&mut noise, 131_072 - 1000, 64, b'!');
    start.extend_from_within(5000..6000);
    let tail = letters(&mut noise, 3000, 64, b'!');
    for back in 184..=200 {
        let mut data = start.clone();
        copy(&mut data, back, 24);
        data.extend_from_slice(&tail);
        same_frame(&data, &format!("a look {back} back from the block after a long match"));
    }
}

// The second repeat offset is taken straight after a match up to the last
// position a block searches: a match at one distance, one at another,
// then the first distance again, its length stepping the block's end
// across that position — for the tree's limit and the rows'.
#[test]
fn the_second_repeat_is_taken_up_to_the_last_position_searched() {
    let mut noise = Noise(0xCBBB_9D5D_C105_9ED8);
    for &lead in &[600, 20_000] {
        for round in 0..3 {
            let start = letters(&mut noise, lead, 64, b'!');
            for length in 4..=24 {
                let mut data = start.clone();
                copy(&mut data, 300, 12);
                copy(&mut data, 211, 12);
                copy(&mut data, 300, length);
                same_frame(&data, &format!("{lead} letters ({round}), the second repeat {length} long"));
            }
        }
    }
}

// A block that only just pays coded: bytes too random for a tree, and one
// copy among them that saves a byte more for each byte it is longer — at
// one length the coded block is the size from which the C stores it.
#[test]
fn a_block_that_only_just_pays_is_coded_as_the_c_codes_it() {
    let mut noise = Noise(0x5BE0_CD19_137E_2179);
    let random: Vec<u8> = (0..4000).map(|_| noise.next() as u8).collect();
    let tail: Vec<u8> = (0..16).map(|_| noise.next() as u8).collect();
    for length in 40..=120 {
        let mut data = random.clone();
        data.extend_from_within(1000..1000 + length);
        data.extend_from_slice(&tail);
        same_frame(&data, &format!("a copy {length} long among random bytes"));
    }
}
