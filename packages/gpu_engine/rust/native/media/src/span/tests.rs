//! The span reader: every answer, and what each read cost, held to the
//! ledger — the C's answers, pinned before it was deleted
//! (connection-round-checklist A, 관제 2026-11-07) — and every window's
//! bytes to the medium's own. The cost is what tells a reader that reads
//! only the blocks a window lands in from one that quietly reads them all.
//! ↩️Until the connection round deleted the C (connection-round-checklist
//! H, 2026-11-08) the same file was opened by both (native/oracle), and
//! every answer, window and cost held to the C's.

use std::ffi::CString;
use std::path::PathBuf;

use oracle::framed;

use super::Span;

/// A file of this test's own, under a Korean name: what the one widening
/// of a path is for.
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

/// Junk, then `blob`, then junk: the archive a span sits in. The blob's
/// offset in it.
fn archive(blob: &[u8]) -> (Vec<u8>, i64) {
    let mut bytes: Vec<u8> = (0..333u32).map(|k| (k * 31 + 5) as u8).collect();
    let offset = bytes.len() as i64;
    bytes.extend_from_slice(blob);
    bytes.extend((0..77u32).map(|k| (k * 13 + 1) as u8));
    (bytes, offset)
}

/// A test's costs in a row, fingerprinted for the ledger — each opening
/// whether it opened (one byte), then its size and the header's cost; each
/// window the cost so far; every number i64 little-endian — the C's
/// answers, held since the C was deleted. What a window reads is the
/// medium's own, held as that.
#[derive(Default)]
struct Costs(ledger::Running);

impl Costs {
    fn add(&mut self, numbers: &[i64], bytes: &[u8]) {
        for number in numbers {
            self.0.add(&number.to_le_bytes());
        }
        self.0.add(bytes);
    }

    fn pinned(self, id: &str) {
        self.0.assert_pinned(id);
    }
}

/// The span opened: whether it opened, and the size it says and what its
/// header cost, for the ledger.
fn opened(costs: &mut Costs, path: &str, offset: i64, length: i64, framed: bool) -> Option<Span> {
    let span = Span::open(&CString::new(path).expect("no NUL"), offset, length, framed);
    costs.add(&[], &[u8::from(span.is_some())]);
    let span = span?;
    let (blocks, bytes) = span.stats();
    costs.add(&[span.size(), blocks, bytes], &[]);
    Some(span)
}

/// One window: the answer, and the cost so far, for the ledger; and where
/// it is not refused, the bytes the `medium` has there — as many as the
/// window and the span's size leave, the rest of the buffer as it was.
fn window(costs: &mut Costs, span: &mut Span, medium: &[u8], position: i64, want: usize, what: &str) -> i64 {
    let mut out = vec![0xAAu8; want.max(1)];
    let answer = span.read(position, &mut out[..want]).map_or(-1, |wrote| wrote as i64);
    let (blocks, bytes) = span.stats();
    costs.add(&[blocks, bytes], &[]);
    if answer >= 0 {
        let size = span.size();
        let left = if position < 0 || position >= size { 0 } else { size - position };
        assert_eq!(answer, left.min(want as i64), "{what}: window {position} +{want}, how many");
        let (from, wrote) = ((position.max(0) as usize).min(medium.len()), answer as usize);
        assert_eq!(Some(&out[..wrote]), medium.get(from..from + wrote), "{what}: window {position} +{want}, the medium's bytes");
        assert!(out[wrote..].iter().all(|&byte| byte == 0xAA), "{what}: window {position} +{want}, nothing past them");
    }
    answer
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
    let mut costs = Costs::default();
    let mut span = opened(&mut costs, path, offset, length, false).expect("opens");
    for (position, want) in windows(length, 1024) {
        window(&mut costs, &mut span, &bytes, position, want, "plain");
    }
    let total = archive.len() as i64;
    for (offset, length) in [(0, total), (0, 0), (total, 0), (total - 1, 1), (total - 1, 2), (-1, 4), (4, -1), (offset, length + 78)] {
        if let Some(mut span) = opened(&mut costs, path, offset, length, false) {
            let edge = archive.get(offset as usize..(offset + length) as usize).expect("an open span lies in its file");
            window(&mut costs, &mut span, edge, 0, 16, "an edge span");
        }
    }
    assert!(opened(&mut costs, &format!("{path}.missing"), 0, 1, false).is_none());
    costs.pinned("media/span-plain");
    // Closed before it is deleted: ↩️the C's file shut out deleting while
    // it was open.
    drop(span);
    std::fs::remove_file(path).expect("cleanup");
}

// A file that is there, under a path of more wide characters than the
// buffer holds (the C's size, `path::WIDE`): refused rather than cut —
// ↩️by both, until the connection round deleted the C.
// 🚨ON WINDOWS ONLY, where the buffer is: a path is made wide on Windows
// alone (path.rs — `WIDE` and `wide` are `cfg(windows)`, as the C's
// `qa_widen_path` is), and elsewhere its bytes go to the OS as they are.
// Nor is such a file there to be asked for elsewhere: the Mac refused the
// deep folder itself, its names 255 bytes and its paths 1024 (`File name
// too long`, CI run 42280088098, 관제 native-to-rust 11-07 04:42), and
// Linux's ext4 names are 255 bytes as well.
#[cfg(windows)]
#[test]
fn a_path_past_the_wide_buffer_is_refused() {
    let bytes = medium(5000);
    let top = std::env::temp_dir().join(format!("미디어-스팬-{}-길다", std::process::id()));
    let deep = (0..5).fold(top.clone(), |dir, k| dir.join(char::from_u32(0xAC00 + k).expect("Hangul").to_string().repeat(200)));
    std::fs::create_dir_all(&deep).expect("a deep folder");
    let far = deep.join("medium.bin");
    std::fs::write(&far, &bytes).expect("a file far down");
    assert!(far.to_str().expect("UTF-8").encode_utf16().count() >= 1024, "LIVENESS — past the buffer");
    assert!(opened(&mut Costs::default(), far.to_str().expect("UTF-8"), 0, bytes.len() as i64, false).is_none());
    std::fs::remove_dir_all(&top).expect("cleanup");
}

// Framed media at the block sizes the writer has used and others — one
// block, a block and a byte, a short tail — read in the windows a document
// reads: every window's bytes, and the blocks and bytes it cost, the C's.
#[test]
fn a_framed_span_reads_as_the_c_reads_it() {
    let mut costs = Costs::default();
    for block in [1000usize, 4096, 65536, 512 * 1024] {
        for size in [1, block - 1, block, block + 1, 3 * block + 777] {
            let medium = medium(size);
            let (archive, offset) = archive(&framed(&medium, block));
            let path = file(&format!("framed-{block}-{size}"), &archive);
            let path = path.to_str().expect("UTF-8");
            let what = format!("blocks of {block}, {size} bytes");
            let mut span = opened(&mut costs, path, offset, archive.len() as i64 - offset - 77, true).expect("opens");
            for (position, want) in windows(size as i64, block as i64) {
                window(&mut costs, &mut span, &medium, position, want, &what);
            }
            // The same bytes as a header from the wrong origin, or cut short.
            opened(&mut costs, path, offset + 4, archive.len() as i64 - offset - 81, true);
            opened(&mut costs, path, offset, archive.len() as i64 - offset - 78, true);
            drop(span);
            std::fs::remove_file(path).expect("cleanup");
        }
    }
    costs.pinned("media/span-framed");
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
// Each one's verdict is the C's, measured 2026-11-07 — refused at the door
// (`None`), or opened at a size with so many of its windows refused — and
// so held once the C is gone (connection-round-checklist A).
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
    let broken = [
        ("block size 0", with_u32(&blob, 0, 0), None),
        ("block size at the bound", largest.clone(), Some((12_388, 0))),
        ("block size past the bound", with_u32(&largest, 0, (64 << 20) + 1), None),
        ("a count too many", with_u32(&blob, 12, 5), None),
        ("a count too few", with_u32(&blob, 12, 3), None),
        ("a length past a signed size", with_u32(&blob, 8, 0x8000_0000), None),
        ("a block of nothing", with_u32(&blob, 20, 0), None),
        ("a block past the span", with_u32(&blob, 28, lengths[3] + 1), None),
        ("a block short by a byte", with_u32(&blob, 28, lengths[3] - 1), Some((12_388, 5))),
        // At its magic number: a flipped byte deeper in could still decode,
        // to the wrong bytes, and prove nothing.
        (
            "the second block's magic broken",
            {
                let mut changed = blob.clone();
                changed[second] ^= 0xFF;
                changed
            },
            Some((12_388, 29)),
        ),
        (
            "the second and third blocks' lengths swapped",
            {
                let mut changed = with_u32(&blob, 20, lengths[2]);
                changed[24..28].copy_from_slice(&lengths[1].to_le_bytes());
                changed
            },
            Some((12_388, 0)),
        ),
        ("a total a byte longer", with_u32(&blob, 4, medium.len() as u32 + 1), Some((12_389, 5))),
        ("a total a byte shorter", with_u32(&blob, 4, medium.len() as u32 - 1), Some((12_387, 5))),
        (
            "an empty medium",
            {
                let mut empty = (block as u32).to_le_bytes().to_vec();
                empty.extend_from_slice(&[0; 12]);
                empty
            },
            Some((0, 0)),
        ),
    ];
    let mut costs = Costs::default();
    for (what, blob, verdict) in broken {
        let (archive, offset) = archive(&blob);
        let path = file(&what.replace(' ', "-"), &archive);
        let path = path.to_str().expect("UTF-8");
        let mut answered = None;
        if let Some(mut span) = opened(&mut costs, path, offset, blob.len() as i64, true) {
            let size = span.size();
            let refused = windows(size, block as i64)
                .into_iter()
                .filter(|&(position, want)| window(&mut costs, &mut span, &medium, position, want, what) == -1)
                .count();
            answered = Some((size, refused));
        }
        assert_eq!(answered, verdict, "{what}");
        std::fs::remove_file(path).expect("cleanup");
    }
    costs.pinned("media/span-framed-broken");
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
