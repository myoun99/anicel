//! 🚨★**WHAT THIS CRATE ASKS OF A MOVIE BOX — ASKED IN ONE PLACE.** Where a
//! file's movie box is, a track by what its media says it is, a header's
//! time scale and length, and where a track's edit list says its media
//! starts: the export's edit list asks them of the movie the sink writer
//! finished (`export/edit_list.rs`), and Windows' reader of a movie it
//! opens (`decode/windows.rs`). ↩️The export's own until 2026-11-17, when
//! the reader came to need them (card video-frame-count-two-past).
//!
//! ⚠️The sound decoder asks the same of a file it reads box by box (native/
//! audio `start.rs`: `first_sound`, `time_scale`, `sound_edit`) — this
//! crate's are one reader with two callers. A third reader is the time to
//! make them one.

use std::ops::Range;

use media::iso_box::{self, Atom};

/// Where the movie box of a file of `length` bytes is — its first byte and
/// its size — its boxes' heads read through `read` (exactly as many bytes
/// as asked from where asked, or false). None where a head will not read
/// or a box does not fit before the movie box comes.
pub(crate) fn moov_in(length: u64, mut read: impl FnMut(u64, &mut [u8]) -> bool) -> Option<(u64, u64)> {
    let mut at = 0;
    loop {
        let mut head = [0u8; 16];
        let have = (length.checked_sub(at)?).min(16) as usize;
        if !read(at, &mut head[..have]) {
            return None;
        }
        let head = iso_box::head(&head[..have])?;
        let size = head.size_in(length - at)?;
        if &head.kind == b"moov" {
            return Some((at, size));
        }
        at += size;
    }
}

/// The first track of `movie` whose media says it is `handler` — its
/// `hdlr`'s handler: `soun` for sound, `vide` for pictures.
///
/// ⚠️The sound decoder asks the same of a file it reads box by box
/// (native/audio `start.rs`, `first_sound`). Two readers — a third is the
/// time to make them one.
pub(crate) fn track(moov: &[u8], movie: &Atom, handler: &[u8; 4]) -> Option<Atom> {
    iso_box::atoms(moov, movie.body, movie.end).filter(|atom| &atom.kind == b"trak").find(|trak| {
        iso_box::find(moov, trak.body, trak.end, &[b"mdia", b"hdlr"])
            .is_some_and(|hdlr| hdlr.end - hdlr.body >= 12 && &moov[hdlr.body + 8..hdlr.body + 12] == handler)
    })
}

/// Where a movie's (`mvhd`), a track's (`tkhd`) or a media's (`mdhd`)
/// header says how long it runs: after its version and flags, its two dates
/// — 64 bits each in version 1, as the length is — and one thing more: a
/// movie's or a media's time scale, a track's id and the reserved word
/// after it.
///
/// ⚠️The sound decoder reads the time scale off the same layout
/// (native/audio `start.rs`, `time_scale`). Two readers — a third is the
/// time to make them one.
pub(crate) fn length_field(bytes: &[u8], header: &Atom) -> Option<Range<usize>> {
    let wide = *bytes.get(header.body)? == 1;
    let (dates, width) = if wide { (16, 8) } else { (8, 4) };
    let more = if &header.kind == b"tkhd" { 8 } else { 4 };
    let at = header.body + 4 + dates + more;
    (at + width <= header.end).then_some(at..at + width)
}

/// A movie's or a media's time scale: the word before its length. None for
/// a scale of 0, which counts nothing.
pub(crate) fn scale(bytes: &[u8], header: &Atom) -> Option<u32> {
    let length = length_field(bytes, header)?;
    let scale = u32::from_be_bytes(bytes[length.start - 4..length.start].try_into().ok()?);
    (scale > 0).then_some(scale)
}

pub(crate) fn length(bytes: &[u8], header: &Atom) -> Option<u64> {
    let field = &bytes[length_field(bytes, header)?];
    let mut wide = [0u8; 8];
    wide[8 - field.len()..].copy_from_slice(field);
    Some(u64::from_be_bytes(wide))
}

/// Where `trak`'s edit list says its media starts: the media time of its
/// first edit that plays media, in ticks of the media's own scale. None
/// where it has no list, or no edit of it plays media.
///
/// A leading empty edit (media time -1) holds the track back on the
/// movie's timeline — where it is PLACED, not where it starts — and is
/// passed over, as the sound decoder passes it over.
///
/// ⚠️The sound decoder reads the same of its track's list (native/audio
/// `start.rs`, `sound_edit`). Two readers — a third is the time to make
/// them one.
///
/// 🔬A movie x264 wrote with its B-frames stores its first picture two
/// frames into its media, and ffmpeg's list takes them off (11-17,
/// `test/fixtures/ladder_two_frames_late.mp4`: 1024 of 12288 at 24).
pub(crate) fn media_start(moov: &[u8], trak: &Atom) -> Option<i64> {
    let elst = iso_box::find(moov, trak.body, trak.end, &[b"edts", b"elst"])?;
    let list = &moov[elst.body..elst.end];
    let wide = *list.first()? == 1;
    let entry = if wide { 20 } else { 12 };
    let count = u32::from_be_bytes(list.get(4..8)?.try_into().ok()?) as usize;
    for index in 0..count {
        let edit = list.get(8 + index * entry..8 + (index + 1) * entry)?;
        let media_time = if wide {
            i64::from_be_bytes(edit[8..16].try_into().ok()?)
        } else {
            i64::from(i32::from_be_bytes(edit[4..8].try_into().ok()?))
        };
        if media_time >= 0 {
            return Some(media_time);
        }
    }
    None
}

/// A file of this checkout's own test fixtures.
#[cfg(test)]
pub(crate) fn fixture(name: &str) -> Vec<u8> {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let path = std::path::PathBuf::from(crate_dir).join("../../../../../test/fixtures").join(name);
    std::fs::read(&path).unwrap_or_else(|why| panic!("{}: {why}", path.display()))
}

/// The movie box of `movie`, whole — found as a file's is ([`moov_in`]).
#[cfg(test)]
pub(crate) fn moov_of(movie: &[u8]) -> &[u8] {
    let (at, size) = moov_in(movie.len() as u64, |at, head| {
        let at = at as usize;
        movie.get(at..at + head.len()).map(|bytes| head.copy_from_slice(bytes)).is_some()
    })
    .expect("a movie box");
    &movie[at as usize..(at + size) as usize]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Where `movie`'s pictures start, as their media's ticks and scale.
    fn pictures_start(movie: &[u8]) -> Option<(i64, u32)> {
        let moov = moov_of(movie);
        let box_of_it = iso_box::atom(moov, 0, moov.len())?;
        let trak = track(moov, &box_of_it, b"vide")?;
        let mdhd = iso_box::find(moov, trak.body, trak.end, &[b"mdia", b"mdhd"])?;
        Some((media_start(moov, &trak)?, scale(moov, &mdhd)?))
    }

    #[test]
    fn a_list_that_takes_two_frames_off_says_its_media_starts_there() {
        assert_eq!(pictures_start(&fixture("ladder_two_frames_late.mp4")), Some((1024, 12288)));
    }

    // The sink writer's movie has no list on its pictures; its sound's is
    // not theirs.
    #[test]
    fn pictures_with_no_list_say_nothing() {
        assert_eq!(pictures_start(&fixture("tone_with_video.mp4")), None);
    }

    #[test]
    fn a_leading_empty_edit_is_passed_over_and_a_wide_list_is_read() {
        // A movie box of one picture track: its media's header (version 0,
        // scale 600) and a version-1 list — an empty edit, then one from 90.
        fn boxed(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
            [&((8 + body.len()) as u32).to_be_bytes()[..], kind, body].concat()
        }
        let hdlr = boxed(b"hdlr", &[[0u8; 8].as_slice(), b"vide", &[0; 12]].concat());
        let mdhd = boxed(b"mdhd", &[[0u8; 12].as_slice(), &600u32.to_be_bytes(), &[0; 8]].concat());
        let edits: Vec<u8> = [-1i64, 90]
            .iter()
            .flat_map(|time| [&48u64.to_be_bytes()[..], &time.to_be_bytes(), &[0, 1, 0, 0]].concat())
            .collect();
        let elst = boxed(b"elst", &[[1u8, 0, 0, 0].as_slice(), &2u32.to_be_bytes(), &edits].concat());
        let trak = boxed(b"trak", &[boxed(b"edts", &elst), boxed(b"mdia", &[hdlr, mdhd].concat())].concat());
        let moov = boxed(b"moov", &trak);
        assert_eq!(pictures_start(&moov), Some((90, 600)));
    }
}
