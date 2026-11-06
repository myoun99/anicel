//! The Rust span reader against the engine's C (native/oracle): the same
//! file opened by both, every answer, every window's bytes and what each
//! read cost held to the C's — the cost is what tells a reader that reads
//! only the blocks a window lands in from one that quietly reads them all.

use std::ffi::{CString, c_char};
use std::path::PathBuf;

use oracle::export;

use super::Span;

type Open = unsafe extern "C" fn(*const c_char, i64, i64, i32) -> *mut u8;
type Size = unsafe extern "C" fn(*const u8) -> i64;
type Read = unsafe extern "C" fn(*mut u8, i64, *mut u8, i64) -> i64;
type Close = unsafe extern "C" fn(*mut u8);
type Stats = unsafe extern "C" fn(*const u8, *mut i64, *mut i64);
type Compress = unsafe extern "C" fn(*mut u8, i64, *const u8, i64, i32) -> i64;
type Bound = extern "C" fn(i64) -> i64;

/// The C's span reader, through the engine's exports.
struct CSpan(*mut u8);

impl CSpan {
    fn open(path: &str, offset: i64, length: i64, framed: bool) -> CSpan {
        let path = CString::new(path).expect("no NUL");
        // SAFETY: qa_media_span.h's declarations; the path is NUL-terminated.
        CSpan(unsafe { export::<Open>("qa_media_span_open")(path.as_ptr(), offset, length, i32::from(framed)) })
    }

    fn size(&self) -> i64 {
        // SAFETY: as above.
        unsafe { export::<Size>("qa_media_span_size")(self.0) }
    }

    fn read(&mut self, position: i64, out: &mut [u8]) -> i64 {
        // SAFETY: as above; `out` holds what is passed.
        unsafe { export::<Read>("qa_media_span_read")(self.0, position, out.as_mut_ptr(), out.len() as i64) }
    }

    fn stats(&self) -> (i64, i64) {
        let (mut blocks, mut bytes) = (0, 0);
        // SAFETY: as above.
        unsafe { export::<Stats>("qa_media_span_stats")(self.0, &mut blocks, &mut bytes) };
        (blocks, bytes)
    }
}

impl Drop for CSpan {
    fn drop(&mut self) {
        // SAFETY: as above; closed once.
        unsafe { export::<Close>("qa_media_span_close")(self.0) }
    }
}

/// A file of this test's own, under a Korean name: what the C's one
/// widening of a path is for.
fn file(name: &str, bytes: &[u8]) -> PathBuf {
    let path = std::env::temp_dir().join(format!("미디어-스팬-{}-{name}.bin", std::process::id()));
    std::fs::write(&path, bytes).expect("write the fixture");
    path
}

/// Byte `at` of a medium: derived from where it is, so a window that is
/// not the medium's own shows, and it compresses.
fn medium(size: usize) -> Vec<u8> {
    (0..size).map(|at| ((at * 7) ^ (at >> 9) ^ (at >> 17)) as u8).collect()
}

/// `medium` framed in blocks of `block_bytes`, each the C's level-9 frame,
/// as `writeMediaBlob` lays them out.
fn framed(medium: &[u8], block_bytes: usize) -> Vec<u8> {
    // SAFETY: qa_compress.c's declarations.
    let (bound, compress) = unsafe { (export::<Bound>("qa_zstd_compress_bound"), export::<Compress>("qa_zstd_compress")) };
    let blocks: Vec<Vec<u8>> = medium
        .chunks(block_bytes)
        .map(|block| {
            let mut frame = vec![0u8; bound(block.len() as i64) as usize];
            // SAFETY: both buffers hold the sizes passed.
            let wrote = unsafe { compress(frame.as_mut_ptr(), frame.len() as i64, block.as_ptr(), block.len() as i64, 9) };
            frame.truncate(wrote as usize);
            frame
        })
        .collect();
    let mut blob = (block_bytes as u32).to_le_bytes().to_vec();
    blob.extend_from_slice(&(medium.len() as u64).to_le_bytes());
    blob.extend_from_slice(&(blocks.len() as u32).to_le_bytes());
    for block in &blocks {
        blob.extend_from_slice(&(block.len() as u32).to_le_bytes());
    }
    blob.extend(blocks.concat());
    blob
}

/// Junk, then `blob`, then junk: the archive a span sits in. The blob's
/// offset in it.
fn archive(blob: &[u8]) -> (Vec<u8>, i64) {
    let mut bytes: Vec<u8> = (0..333u32).map(|k| (k * 31 + 5) as u8).collect();
    let offset = bytes.len() as i64;
    bytes.extend_from_slice(blob);
    bytes.extend((0..77u32).map(|k| (k * 13 + 1) as u8));
    (bytes, offset)
}

/// Both readers opened on the same span: whether each opened, and the size
/// each says, held to the C's.
fn both(path: &str, offset: i64, length: i64, framed: bool) -> Option<(CSpan, Span)> {
    let theirs = CSpan::open(path, offset, length, framed);
    let ours = Span::open(&CString::new(path).expect("no NUL"), offset, length, framed);
    let what = format!("{path} [{offset}, +{length}) framed {framed}");
    assert_eq!(ours.is_some(), !theirs.0.is_null(), "{what}: opened");
    let ours = ours?;
    assert_eq!(ours.size(), theirs.size(), "{what}: size");
    assert_eq!(ours.stats(), theirs.stats(), "{what}: the header's cost");
    Some((theirs, ours))
}

/// One window through both: the answer, the bytes, and the cost so far.
fn window(spans: &mut (CSpan, Span), position: i64, want: usize, what: &str) -> i64 {
    let (mut theirs_out, mut ours_out) = (vec![0xAAu8; want.max(1)], vec![0xAAu8; want.max(1)]);
    let theirs = spans.0.read(position, &mut theirs_out[..want]);
    let ours = spans.1.read(position, &mut ours_out[..want]).map_or(-1, |wrote| wrote as i64);
    assert_eq!(ours, theirs, "{what}: window {position} +{want}");
    assert!(ours_out == theirs_out, "{what}: window {position} +{want}, the bytes");
    assert_eq!(spans.1.stats(), spans.0.stats(), "{what}: window {position} +{want}, the cost");
    ours
}

/// The windows a document reads: inside a block, many small ones in one,
/// across a boundary, the short tail, past the end, and back.
fn windows(size: i64, block: i64) -> Vec<(i64, usize)> {
    let mut found = vec![(0, 1), (0, 100), (block + 10, 50), (block + 70, 50), (block + 900, 3)];
    for k in 0..20 {
        found.push((block + 11 * k, 7));
    }
    found.extend([(block - 5, 10), (2 * block - 1, 2), (size - 3, 10), (size - 1, 1), (size, 4), (size + 9, 4)]);
    found.extend([(0, size as usize), (1, size as usize + 50), (-1, 4), (0, 0), (block / 2, 3 * block as usize)]);
    found.extend([(size / 3, 4096), (2, 1)]);
    found.retain(|&(position, _)| position < size + 20);
    found
}

// A medium as its own bytes in a span of an archive: every window is the
// C's, and so is what refuses — a span past the file's end, a negative
// one, a file that is not there.
#[test]
fn a_plain_span_reads_as_the_c_reads_it() {
    let bytes = medium(5000);
    let (archive, offset) = archive(&bytes);
    let path = file("plain", &archive);
    let path = path.to_str().expect("UTF-8");
    let length = bytes.len() as i64;
    let mut spans = both(path, offset, length, false).expect("opens");
    for (position, want) in windows(length, 1024) {
        window(&mut spans, position, want, "plain");
    }
    let total = archive.len() as i64;
    for (offset, length) in [(0, total), (0, 0), (total, 0), (total - 1, 1), (total - 1, 2), (-1, 4), (4, -1), (offset, length + 78)] {
        if let Some(mut spans) = both(path, offset, length, false) {
            window(&mut spans, 0, 16, "an edge span");
        }
    }
    assert!(both(&format!("{path}.missing"), 0, 1, false).is_none());
    // The C's file shuts out deleting while it is open.
    drop(spans);
    std::fs::remove_file(path).expect("cleanup");
}

// A file that is there, under a path of more wide characters than the C's
// buffer holds: refused rather than cut, by both.
// 🚨ON WINDOWS ONLY, where the buffer is: a path is made wide on Windows
// alone (path.rs — `WIDE` and `wide` are `cfg(windows)`, as the C's
// `qa_widen_path` is), and elsewhere its bytes go to the OS as they are.
// Nor is such a file there to be asked for elsewhere: the Mac refused the
// deep folder itself, its names 255 bytes and its paths 1024 (`File name
// too long`, CI run 42280088098, 관제 native-to-rust 11-07 04:42), and
// Linux's ext4 names are 255 bytes as well.
#[cfg(windows)]
#[test]
fn a_path_past_the_wide_buffer_is_refused_by_both() {
    let bytes = medium(5000);
    let top = std::env::temp_dir().join(format!("미디어-스팬-{}-길다", std::process::id()));
    let deep = (0..5).fold(top.clone(), |dir, k| dir.join(char::from_u32(0xAC00 + k).expect("Hangul").to_string().repeat(200)));
    std::fs::create_dir_all(&deep).expect("a deep folder");
    let far = deep.join("medium.bin");
    std::fs::write(&far, &bytes).expect("a file far down");
    assert!(far.to_str().expect("UTF-8").encode_utf16().count() >= 1024, "LIVENESS — past the buffer");
    assert!(both(far.to_str().expect("UTF-8"), 0, bytes.len() as i64, false).is_none());
    std::fs::remove_dir_all(&top).expect("cleanup");
}

// Framed media at the block sizes the writer has used and others — one
// block, a block and a byte, a short tail — read in the windows a document
// reads: every window's bytes, and the blocks and bytes it cost, the C's.
#[test]
fn a_framed_span_reads_as_the_c_reads_it() {
    for block in [1000usize, 4096, 65536, 512 * 1024] {
        for size in [1, block - 1, block, block + 1, 3 * block + 777] {
            let medium = medium(size);
            let (archive, offset) = archive(&framed(&medium, block));
            let path = file(&format!("framed-{block}-{size}"), &archive);
            let path = path.to_str().expect("UTF-8");
            let what = format!("blocks of {block}, {size} bytes");
            let mut spans = both(path, offset, archive.len() as i64 - offset - 77, true).expect("opens");
            for (position, want) in windows(size as i64, block as i64) {
                window(&mut spans, position, want, &what);
            }
            // The same bytes as a header from the wrong origin, or cut short.
            both(path, offset + 4, archive.len() as i64 - offset - 81, true);
            both(path, offset, archive.len() as i64 - offset - 78, true);
            drop(spans);
            std::fs::remove_file(path).expect("cleanup");
        }
    }
}

/// `blob` with `u32` `value` written at `at`.
fn with_u32(blob: &[u8], at: usize, value: u32) -> Vec<u8> {
    let mut changed = blob.to_vec();
    changed[at..at + 4].copy_from_slice(&value.to_le_bytes());
    changed
}

// Headers that do not hold together — a block size of nothing or past the
// bound, a count the length does not imply, a length past what a signed
// size holds, a block of no bytes or running past the span — and blocks
// that do not decode, or decode to another length: refused where the C
// refuses them, at the door or at the window.
#[test]
fn a_framed_span_that_does_not_hold_together_is_refused_as_the_c_refuses_it() {
    let block = 4096;
    let medium = medium(3 * block + 100);
    let blob = framed(&medium, block);
    let lengths: Vec<u32> = (0..4).map(|k| super::u32_at(&blob, 16 + 4 * k)).collect();
    let second = 32 + lengths[0] as usize;
    // One block of the largest size trusted, so its count still holds when
    // the size goes past it.
    let largest = framed(&medium, 64 << 20);
    let mut broken = vec![
        ("block size 0", with_u32(&blob, 0, 0)),
        ("block size at the bound", largest.clone()),
        ("block size past the bound", with_u32(&largest, 0, (64 << 20) + 1)),
        ("a count too many", with_u32(&blob, 12, 5)),
        ("a count too few", with_u32(&blob, 12, 3)),
        ("a length past a signed size", with_u32(&blob, 8, 0x8000_0000)),
        ("a block of nothing", with_u32(&blob, 20, 0)),
        ("a block past the span", with_u32(&blob, 28, lengths[3] + 1)),
        ("a block short by a byte", with_u32(&blob, 28, lengths[3] - 1)),
        ("the second block's magic broken", {
            let mut changed = blob.clone();
            changed[second] ^= 0xFF;
            changed
        }),
        ("the second and third blocks' lengths swapped", {
            let mut changed = with_u32(&blob, 20, lengths[2]);
            changed[24..28].copy_from_slice(&lengths[1].to_le_bytes());
            changed
        }),
        ("a total a byte longer", with_u32(&blob, 4, medium.len() as u32 + 1)),
        ("a total a byte shorter", with_u32(&blob, 4, medium.len() as u32 - 1)),
    ];
    broken.push(("an empty medium", {
        let mut empty = (block as u32).to_le_bytes().to_vec();
        empty.extend_from_slice(&[0; 12]);
        empty
    }));
    let (mut opened, mut refused_at_a_window) = (0, 0);
    for (what, blob) in broken {
        let (archive, offset) = archive(&blob);
        let path = file(&what.replace(' ', "-"), &archive);
        let path = path.to_str().expect("UTF-8");
        if let Some(mut spans) = both(path, offset, blob.len() as i64, true) {
            opened += 1;
            let size = spans.1.size();
            for (position, want) in windows(size, block as i64) {
                refused_at_a_window += usize::from(window(&mut spans, position, want, what) == -1);
            }
        }
        std::fs::remove_file(path).expect("cleanup");
    }
    // LIVENESS — some were refused at the door, some at a window.
    assert!(opened > 0 && refused_at_a_window > 0, "{opened} opened, {refused_at_a_window} windows refused");
}

// Nothing to read from, nothing to read into: the C's answers.
#[test]
fn nothing_is_read_from_nothing() {
    // SAFETY: null spans and pointers are what is being asked about.
    unsafe {
        assert_eq!(super::qa_media_span_open(std::ptr::null(), 0, 1, 0), std::ptr::null_mut());
        assert_eq!(super::qa_media_span_size(std::ptr::null()), 0);
        let mut out = [0u8; 4];
        assert_eq!(super::qa_media_span_read(std::ptr::null_mut(), 0, out.as_mut_ptr(), 4), 0);
        let (mut blocks, mut bytes) = (7, 7);
        super::qa_media_span_stats(std::ptr::null(), &mut blocks, &mut bytes);
        assert_eq!((blocks, bytes), (0, 0));
        super::qa_media_span_close(std::ptr::null_mut());
    }
    let bytes = medium(64);
    let path = file("null-out", &bytes);
    let name = CString::new(path.to_str().expect("UTF-8")).expect("no NUL");
    // SAFETY: a span of ours, read into nothing, closed once.
    unsafe {
        let span = super::qa_media_span_open(name.as_ptr(), 0, 64, 0);
        assert!(!span.is_null());
        assert_eq!(super::qa_media_span_read(span, 0, std::ptr::null_mut(), 4), 0);
        super::qa_media_span_close(span);
    }
    std::fs::remove_file(path).expect("cleanup");
}
