//! The decoder held to what a JPEG says: its pixels near what was encoded
//! (the repo's own encoder, `image_encode`), each EXIF orientation laid as
//! worked out by hand, any side a JPEG can say, a refusal that says why —
//! and its bytes pinned, so a device whose SIMD reads otherwise goes red.

use super::jpeg::orientation_of;
use super::{
    Decoded, qa_image_decode_jpg_close, qa_image_decode_jpg_error, qa_image_decode_jpg_open,
    qa_image_decode_jpg_row, qa_image_decode_jpg_size,
};

/// 🚨The most one request of these tests asks the heap for: past it the
/// request is refused — so a decoder that takes a buffer the size a file's
/// header says, with no answer for 「no room」, ends the tests where it
/// would end the app (`handle_alloc_error`), on any machine, however much
/// memory it has. No test here asks for a gigabyte. The audio decoder's
/// tests hold theirs the same way (`native/audio/src/tests.rs`): two, and
/// a third crate that refuses is where they move into one.
const ROOM: usize = 1 << 30;

/// The system's allocator, refusing a request past [ROOM].
struct Room;

// SAFETY: the system's allocator, or null — which a caller must meet for
// any request.
unsafe impl std::alloc::GlobalAlloc for Room {
    unsafe fn alloc(&self, layout: std::alloc::Layout) -> *mut u8 {
        if layout.size() > ROOM {
            return std::ptr::null_mut();
        }
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: std::alloc::Layout) -> *mut u8 {
        if layout.size() > ROOM {
            return std::ptr::null_mut();
        }
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.alloc_zeroed(layout) }
    }

    unsafe fn realloc(&self, at: *mut u8, layout: std::alloc::Layout, size: usize) -> *mut u8 {
        if size > ROOM {
            return std::ptr::null_mut();
        }
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.realloc(at, layout, size) }
    }

    unsafe fn dealloc(&self, at: *mut u8, layout: std::alloc::Layout) {
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.dealloc(at, layout) }
    }
}

#[global_allocator]
static ROOM_ONLY: Room = Room;

/// `jpeg` with its frame header saying `width` × `height` — the two words
/// written over, every other byte as it was: a file that says a size its
/// data is not.
fn saying(jpeg: &[u8], width: u16, height: u16) -> Vec<u8> {
    let mut said = jpeg.to_vec();
    let mut at = 2;
    loop {
        assert_eq!(said[at], 0xFF, "a marker at {at}");
        let marker = said[at + 1];
        if (0xC0..=0xC2).contains(&marker) {
            // Marker, length, precision — then the height and the width.
            said[at + 5..at + 7].copy_from_slice(&height.to_be_bytes());
            said[at + 7..at + 9].copy_from_slice(&width.to_be_bytes());
            return said;
        }
        at += 2 + usize::from(u16::from_be_bytes([said[at + 2], said[at + 3]]));
    }
}

/// Every row of `decoded` as it shows, RGBA, one after the other.
fn rows_of(decoded: &Decoded) -> Vec<u8> {
    let (width, height) = decoded.shown();
    let mut rgba = vec![0u8; width * height * 4];
    for (y, row) in rgba.chunks_exact_mut(width * 4).enumerate() {
        assert!(decoded.row(y, row), "row {y}");
    }
    rgba
}

/// `width` × `height` RGB: red rising to the right, blue rising down,
/// green a ripple of both — no two channels alike, so a swap shows.
fn gradient(width: usize, height: usize) -> Vec<u8> {
    let mut rgb = Vec::with_capacity(width * height * 3);
    for y in 0..height {
        for x in 0..width {
            rgb.extend([(x * 255 / width) as u8, ((x + 2 * y) % 64 * 4) as u8, (y * 255 / height) as u8]);
        }
    }
    rgb
}

/// `jpeg` with an EXIF segment naming `orientation` just after its SOI —
/// TIFF little-endian, one IFD of one entry.
fn oriented(jpeg: &[u8], orientation: u16) -> Vec<u8> {
    let mut tiff = b"II*\0".to_vec();
    tiff.extend(8u32.to_le_bytes());
    tiff.extend(1u16.to_le_bytes());
    tiff.extend(0x0112u16.to_le_bytes());
    tiff.extend(3u16.to_le_bytes());
    tiff.extend(1u32.to_le_bytes());
    tiff.extend(orientation.to_le_bytes());
    tiff.extend([0, 0, 0, 0, 0, 0]);
    let mut segment = vec![0xFF, 0xE1];
    segment.extend(((2 + 6 + tiff.len()) as u16).to_be_bytes());
    segment.extend(b"Exif\0\0");
    segment.extend(tiff);
    [&jpeg[..2], &segment, &jpeg[2..]].concat()
}

#[test]
fn a_jpeg_comes_back_its_size_and_near_what_was_encoded() {
    let (width, height) = (197, 131);
    let rgb = gradient(width, height);
    let decoded = Decoded::of(&image_encode::encode(&rgb, width, height, 95)).expect("it decodes");
    assert_eq!(decoded.shown(), (width, height));
    let rgba = rows_of(&decoded);
    let mut off = Vec::new();
    for (shown, coded) in rgba.chunks_exact(4).zip(rgb.chunks_exact(3)) {
        assert_eq!(shown[3], 255, "opaque");
        off.extend(shown[..3].iter().zip(coded).map(|(a, b)| a.abs_diff(*b)));
    }
    let mean = off.iter().map(|&d| f64::from(d)).sum::<f64>() / off.len() as f64;
    assert!(mean < 2.0 && off.iter().all(|&d| d <= 24), "mean {mean}, most {:?}", off.iter().max());
}

/// Six blocks of 16 × 16, each one flat colour, three across and two down:
/// `A B C` over `D E F`, coded so (quality 100, no subsampling) each block's
/// middle comes back as its colour.
const BLOCKS: [[u8; 3]; 6] =
    [[230, 20, 20], [20, 230, 20], [20, 20, 230], [230, 230, 20], [20, 230, 230], [230, 20, 230]];

fn blocks() -> Vec<u8> {
    let mut rgb = Vec::new();
    for y in 0..32 {
        for x in 0..48 {
            rgb.extend(BLOCKS[(y / 16) * 3 + x / 16]);
        }
    }
    rgb
}

/// Which block shows where, in each orientation — worked out by hand from
/// EXIF's own words (2 mirrored · 3 turned half · 4 flipped · 5 transposed ·
/// 6 turned a quarter clockwise · 7 transposed the other way · 8 turned a
/// quarter back), row by row as it shows: 0 = A … 5 = F.
const SHOWN: [(u16, &[&[usize]]); 8] = [
    (1, &[&[0, 1, 2], &[3, 4, 5]]),
    (2, &[&[2, 1, 0], &[5, 4, 3]]),
    (3, &[&[5, 4, 3], &[2, 1, 0]]),
    (4, &[&[3, 4, 5], &[0, 1, 2]]),
    (5, &[&[0, 3], &[1, 4], &[2, 5]]),
    (6, &[&[3, 0], &[4, 1], &[5, 2]]),
    (7, &[&[5, 2], &[4, 1], &[3, 0]]),
    (8, &[&[2, 5], &[1, 4], &[0, 3]]),
];

#[test]
fn each_orientation_shows_its_blocks_where_exif_says() {
    let jpeg = image_encode::encode(&blocks(), 48, 32, 100);
    for (orientation, rows) in SHOWN {
        let decoded = Decoded::of(&oriented(&jpeg, orientation)).expect("it decodes");
        let (width, height) = (rows[0].len() * 16, rows.len() * 16);
        assert_eq!(decoded.shown(), (width, height), "orientation {orientation}: its size");
        let rgba = rows_of(&decoded);
        assert!(rgba.chunks_exact(4).all(|pixel| pixel[3] == 255), "orientation {orientation}: opaque");
        for (row, blocks) in rows.iter().enumerate() {
            for (column, &block) in blocks.iter().enumerate() {
                let at = ((row * 16 + 8) * width + column * 16 + 8) * 4;
                let near = rgba[at..at + 3].iter().zip(BLOCKS[block]).all(|(a, b)| a.abs_diff(b) <= 4);
                assert!(near, "orientation {orientation} ({column}, {row}): {:?}, not block {block}", &rgba[at..at + 3]);
            }
        }
    }
}

#[test]
fn an_orientation_is_read_either_byte_order_and_none_is_as_coded() {
    let little = [b"II*\0".as_slice(), &[8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0]].concat();
    let big = [b"MM\0*".as_slice(), &[0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 8, 0, 0]].concat();
    assert_eq!(orientation_of(&little), 6);
    assert_eq!(orientation_of(&big), 8);
    let other_tag = [b"II*\0".as_slice(), &[8, 0, 0, 0, 1, 0, 0x10, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0]].concat();
    assert_eq!(orientation_of(&other_tag), 1, "no orientation tag");
    assert_eq!(orientation_of(&little[..14]), 1, "an IFD cut short");
    assert_eq!(orientation_of(b"not a tiff"), 1);
}

#[test]
fn a_side_past_zune_s_own_ceiling_decodes() {
    let (width, height) = (16_400, 8);
    let decoded = Decoded::of(&image_encode::encode(&gradient(width, height), width, height, 75)).expect("it decodes");
    assert_eq!(decoded.shown(), (width, height));
}

#[test]
fn a_file_that_is_no_jpeg_says_why_through_its_handle() {
    let junk = b"this is not a jpeg at all";
    // SAFETY (each): the decoder's declarations — the bytes held, room for
    // two and for the text given.
    unsafe {
        let opened = qa_image_decode_jpg_open(junk.as_ptr(), junk.len());
        assert!(!opened.is_null(), "a handle, to say why");
        let mut size = [0i32; 2];
        assert_eq!(qa_image_decode_jpg_size(opened, size.as_mut_ptr()), 0);
        let mut row = [0u8; 16];
        assert_eq!(qa_image_decode_jpg_row(opened, 0, row.as_mut_ptr()), 0);
        let mut text = [0u8; 256];
        let length = qa_image_decode_jpg_error(opened, text.as_mut_ptr(), 256);
        assert!(length > 5 && text[length as usize] == 0, "{length}");
        let mut short = [0xAAu8; 6];
        assert_eq!(qa_image_decode_jpg_error(opened, short.as_mut_ptr(), 6), 5, "cut to the room");
        assert_eq!(short[5], 0);
        qa_image_decode_jpg_close(opened);
        assert!(qa_image_decode_jpg_open(std::ptr::null(), 4).is_null());
        assert!(qa_image_decode_jpg_open(junk.as_ptr(), 0).is_null());
    }
}

#[test]
fn a_decoded_file_hands_its_size_and_rows_and_no_error() {
    let jpeg = oriented(&image_encode::encode(&blocks(), 48, 32, 100), 6);
    // SAFETY (each): as above.
    unsafe {
        let opened = qa_image_decode_jpg_open(jpeg.as_ptr(), jpeg.len());
        let mut size = [0i32; 2];
        assert_eq!(qa_image_decode_jpg_size(opened, size.as_mut_ptr()), 1);
        assert_eq!(size, [32, 48], "as it shows");
        let mut row = vec![0u8; 32 * 4];
        assert_eq!(qa_image_decode_jpg_row(opened, 47, row.as_mut_ptr()), 1, "the last row");
        assert_eq!(qa_image_decode_jpg_row(opened, 48, row.as_mut_ptr()), 0, "past it");
        assert_eq!(qa_image_decode_jpg_row(opened, -1, row.as_mut_ptr()), 0);
        let mut text = [0u8; 16];
        assert_eq!(qa_image_decode_jpg_error(opened, text.as_mut_ptr(), 16), -1);
        qa_image_decode_jpg_close(opened);
    }
}

// Pinned: a picture at both of the encoder's samplings (75: 4:2:0, so the
// chroma is upsampled; 95: 4:4:4), odd sides — every row as it shows.
// The same bytes on every device, or the decoder is not the one law:
// zune's SIMD (AVX2 here, NEON on ARM) and its plain code alike.
#[test]
fn every_device_decodes_the_pinned_jpegs() {
    let (width, height) = (197, 131);
    let mut running = ledger::Running::new();
    for quality in [75, 95] {
        let jpeg = image_encode::encode(&gradient(width, height), width, height, quality);
        running.add(&rows_of(&Decoded::of(&jpeg).expect("it decodes")));
    }
    running.assert_pinned("image_decode/jpg-rows");
}

// 🚨The file that ended the app: a few hundred bytes saying 65,535 ×
// 65,535 — 12.9 GB of pixels. Its room is refused here (ROOM), as it is
// on a machine that has none, and the decoder answers; before it asked
// with `try_reserve` these tests ended at this one.
#[test]
fn a_jpeg_saying_a_size_there_is_no_room_for_says_so() {
    let honest = image_encode::encode(&gradient(64, 48), 64, 48, 90);
    assert_eq!(Decoded::of(&saying(&honest, 64, 48)).expect("the premise: as it was, it decodes").shown(), (64, 48));
    let why = Decoded::of(&saying(&honest, u16::MAX, u16::MAX)).err().expect("no room for it");
    assert!(why.contains("out of memory for 65535x65535"), "{why}");
}

#[test]
fn a_jpeg_there_is_no_room_for_says_why_through_its_handle() {
    let lying = saying(&image_encode::encode(&gradient(64, 48), 64, 48, 90), u16::MAX, u16::MAX);
    // SAFETY (each): the decoder's declarations — the bytes held, room for
    // two and for the text given.
    unsafe {
        let opened = qa_image_decode_jpg_open(lying.as_ptr(), lying.len());
        assert!(!opened.is_null(), "a handle, to say why");
        let mut size = [0i32; 2];
        assert_eq!(qa_image_decode_jpg_size(opened, size.as_mut_ptr()), 0);
        let mut text = [0u8; 256];
        let length = qa_image_decode_jpg_error(opened, text.as_mut_ptr(), 256);
        let why = std::str::from_utf8(&text[..length.max(0) as usize]).expect("text");
        assert!(why.contains("out of memory"), "{why}");
        qa_image_decode_jpg_close(opened);
    }
}
