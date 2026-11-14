//! 🚨★**THE EXPORT'S SOUND SAYS WHERE IT STARTS** (유저 2026-11-10, board
//! an-mp4-reopened-loses-its-first-9-ms-of-sound-Q2: 「ffmpeg처럼」).
//!
//! An AAC encoder cannot code the first samples it is handed whole, so a
//! writer hands it a frame to spend first — 1,024 samples — and says in the
//! movie that the sound starts after it: an edit list on the sound track
//! (`edts` · `elst`), as ffmpeg writes it — `test/fixtures/tone.m4a` is the
//! shape. Media Foundation's sink writer does neither and cannot be asked
//! to, so the frame goes in as sound (`windows.rs`) and the list is written
//! here, into the movie the sink has finished.
//!
//! ⚠️The roll group ffmpeg writes beside its list (`sgpd` · `sbgp`) is not
//! written: it tells a decoder how far before a sample to start so that the
//! sample comes out whole, and where the sound starts is the list's to say
//! — this engine's reader asks the list alone (native/audio `start.rs`).

use std::fs::OpenOptions;
use std::io::{Read, Seek, SeekFrom, Write};
use std::ops::Range;
use std::path::Path;

use media::iso_box::{self, Atom};

/// Writes into the movie at `path` that its sound starts `lead` frames in
/// and plays `kept` frames from there — frames at `rate`. None, and nothing
/// written, where the movie is not as the sink writer lays one.
pub(super) fn mark_the_lead(path: &Path, rate: i64, lead: i64, kept: i64) -> Option<()> {
    let mut file = OpenOptions::new().read(true).write(true).open(path).ok()?;
    let length = file.metadata().ok()?.len();
    let mut at = 0;
    let size = loop {
        let mut head = [0u8; 16];
        let have = (length - at).min(16) as usize;
        file.seek(SeekFrom::Start(at)).ok()?;
        file.read_exact(&mut head[..have]).ok()?;
        let head = iso_box::head(&head[..have])?;
        let size = head.size_in(length - at)?;
        if &head.kind == b"moov" {
            break size;
        }
        at += size;
    };
    // ⛔Only a movie box that closes the file grows where it stands: the
    // sample tables say where each chunk is from the file's start (`stco`),
    // and a movie box before the samples would push every one of them. The
    // sink writer lays `ftyp` · `uuid` · `mdat` · `moov` (measured
    // 2026-11-10: this export's movies and `tone_with_video.mp4`).
    if at + size != length {
        return None;
    }
    let mut moov = vec![0u8; usize::try_from(size).ok()?];
    file.seek(SeekFrom::Start(at)).ok()?;
    file.read_exact(&mut moov).ok()?;
    let marked = marked(&moov, rate, lead, kept)?;
    file.seek(SeekFrom::Start(at)).ok()?;
    file.write_all(&marked).ok()
}

/// `moov` — a whole movie box — with an edit list on its sound track that
/// takes `lead` frames off its front and plays `kept` — frames at `rate` —
/// and the track and the movie as long as that makes them (ISO/IEC
/// 14496-12, 8.3.2: a track with a list is as long as its edits; 8.2.2: a
/// movie as its longest track). None where it has no sound track, the track
/// has a list already, or a header is not there to read and write.
fn marked(moov: &[u8], rate: i64, lead: i64, kept: i64) -> Option<Vec<u8>> {
    let movie = iso_box::atom(moov, 0, moov.len())?;
    let trak = sound_track(moov, &movie)?;
    if iso_box::find(moov, trak.body, trak.end, &[b"edts"]).is_some() {
        return None;
    }
    let tkhd = iso_box::find(moov, trak.body, trak.end, &[b"tkhd"])?;
    let movie_scale = scale(moov, &iso_box::find(moov, movie.body, movie.end, &[b"mvhd"])?)?;
    let media_scale = scale(moov, &iso_box::find(moov, trak.body, trak.end, &[b"mdia", b"mdhd"])?)?;
    let played = ticks(kept, movie_scale, rate)?;
    let list = edit(played, ticks(lead, media_scale, rate)?);
    // The list goes where ffmpeg puts it: straight after the track's header.
    let mut out = Vec::with_capacity(moov.len() + list.len());
    out.extend_from_slice(&moov[..tkhd.end]);
    out.extend_from_slice(&list);
    out.extend_from_slice(&moov[tkhd.end..]);
    // The movie, the track and its header start before the list, so they
    // stand where they stood; the rest is found again.
    iso_box::grow(&mut out, movie.at, list.len() as u64)?;
    iso_box::grow(&mut out, trak.at, list.len() as u64)?;
    set_length(&mut out, &tkhd, played)?;
    let movie = iso_box::atom(&out, 0, out.len())?;
    let longest = iso_box::atoms(&out, movie.body, movie.end)
        .filter(|atom| &atom.kind == b"trak")
        .filter_map(|trak| length(&out, &iso_box::find(&out, trak.body, trak.end, &[b"tkhd"])?))
        .max()?;
    let mvhd = iso_box::find(&out, movie.body, movie.end, &[b"mvhd"])?;
    set_length(&mut out, &mvhd, longest)?;
    Some(out)
}

/// The first track of `movie` whose media says it is sound (its `hdlr`'s
/// handler, `soun`).
///
/// ⚠️The sound decoder asks the same of a file it reads box by box
/// (native/audio `start.rs`, `first_sound`). Two readers — a third is the
/// time to make them one.
fn sound_track(moov: &[u8], movie: &Atom) -> Option<Atom> {
    iso_box::atoms(moov, movie.body, movie.end).filter(|atom| &atom.kind == b"trak").find(|trak| {
        iso_box::find(moov, trak.body, trak.end, &[b"mdia", b"hdlr"])
            .is_some_and(|hdlr| hdlr.end - hdlr.body >= 12 && &moov[hdlr.body + 8..hdlr.body + 12] == b"soun")
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
fn length_field(bytes: &[u8], header: &Atom) -> Option<Range<usize>> {
    let wide = *bytes.get(header.body)? == 1;
    let (dates, width) = if wide { (16, 8) } else { (8, 4) };
    let more = if &header.kind == b"tkhd" { 8 } else { 4 };
    let at = header.body + 4 + dates + more;
    (at + width <= header.end).then_some(at..at + width)
}

/// A movie's or a media's time scale: the word before its length. None for
/// a scale of 0, which counts nothing.
fn scale(bytes: &[u8], header: &Atom) -> Option<u32> {
    let length = length_field(bytes, header)?;
    let scale = u32::from_be_bytes(bytes[length.start - 4..length.start].try_into().ok()?);
    (scale > 0).then_some(scale)
}

fn length(bytes: &[u8], header: &Atom) -> Option<u64> {
    let field = &bytes[length_field(bytes, header)?];
    let mut wide = [0u8; 8];
    wide[8 - field.len()..].copy_from_slice(field);
    Some(u64::from_be_bytes(wide))
}

/// None where the header's field is too narrow to say `ticks`.
fn set_length(bytes: &mut [u8], header: &Atom, ticks: u64) -> Option<()> {
    let field = length_field(bytes, header)?;
    let wide = ticks.to_be_bytes();
    let (over, said) = wide.split_at(8 - field.len());
    if over.iter().any(|&byte| byte != 0) {
        return None;
    }
    bytes[field].copy_from_slice(said);
    Some(())
}

/// `frames` at `rate` as ticks of `scale`, to the nearest tick — as the
/// reader turns them back, to the nearest frame. The sink writer's scales,
/// the movie's and the sound's, are the sound's own rate (measured
/// 2026-11-10), where a tick is a frame.
fn ticks(frames: i64, scale: u32, rate: i64) -> Option<u64> {
    if frames < 0 || rate <= 0 {
        return None;
    }
    u64::try_from(frames.checked_mul(i64::from(scale))?.checked_add(rate / 2)? / rate).ok()
}

/// A box of `kind` holding `parts`, one after another.
fn boxed(kind: &[u8; 4], parts: &[&[u8]]) -> Vec<u8> {
    let size = 8 + parts.iter().map(|part| part.len()).sum::<usize>();
    let mut out = Vec::with_capacity(size);
    out.extend_from_slice(&(size as u32).to_be_bytes());
    out.extend_from_slice(kind);
    for part in parts {
        out.extend_from_slice(part);
    }
    out
}

/// The edit box (`edts`) of one edit: `played` ticks of the movie's scale,
/// from `lead` ticks of the media's in, at the media's own speed. In 32
/// bits — version 0, as ffmpeg writes it — where the length fits them, in
/// 64 where it does not (24 hours of sound at 48 kHz).
fn edit(played: u64, lead: u64) -> Vec<u8> {
    const ONE_EDIT: [u8; 4] = [0, 0, 0, 1];
    const OWN_SPEED: [u8; 4] = [0, 1, 0, 0];
    let narrow = u32::try_from(played).ok().zip(i32::try_from(lead).ok());
    let (version, times) = match narrow {
        Some((played, lead)) => (0u8, [played.to_be_bytes(), lead.to_be_bytes()].concat()),
        None => (1, [played.to_be_bytes(), lead.to_be_bytes()].concat()),
    };
    boxed(b"edts", &[&boxed(b"elst", &[&[version, 0, 0, 0], &ONE_EDIT, &times, &OWN_SPEED])])
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    /// A file of this checkout's own test fixtures.
    fn fixture(name: &str) -> Vec<u8> {
        let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
        let path = PathBuf::from(crate_dir).join("../../../../../test/fixtures").join(name);
        std::fs::read(&path).unwrap_or_else(|why| panic!("{}: {why}", path.display()))
    }

    /// The movie box of `movie`, whole.
    fn moov_of(movie: &[u8]) -> &[u8] {
        let moov = iso_box::find(movie, 0, movie.len(), &[b"moov"]).expect("a movie box");
        &movie[moov.at..moov.end]
    }

    /// The tracks of `moov`, a whole movie box, in its order.
    fn tracks(moov: &[u8]) -> Vec<Atom> {
        let movie = iso_box::atom(moov, 0, moov.len()).expect("a movie box");
        iso_box::atoms(moov, movie.body, movie.end).filter(|atom| &atom.kind == b"trak").collect()
    }

    /// The edit list's body under `trak`: its version and flags, its count
    /// and its edits.
    fn list<'a>(moov: &'a [u8], trak: &Atom) -> Option<&'a [u8]> {
        iso_box::find(moov, trak.body, trak.end, &[b"edts", b"elst"]).map(|elst| &moov[elst.body..elst.end])
    }

    fn header_length(moov: &[u8], start: usize, end: usize, kind: &[u8; 4]) -> u64 {
        length(moov, &iso_box::find(moov, start, end, &[kind]).expect("the header")).expect("its length")
    }

    // The fixtures' movie is the sink writer's own: 12 pictures at 24 and
    // half a second of 44.1 kHz sound, its movie scale the sound's rate.
    // The list it gets is the one ffmpeg wrote into `tone.m4a`, but for how
    // long it plays — said in each movie's own scale.
    #[test]
    fn the_sink_writer_s_movie_gets_the_list_ffmpeg_writes() {
        let movie = fixture("tone_with_video.mp4");
        let before = moov_of(&movie);
        let after = marked(before, 44100, 1024, 21000).expect("it is marked");
        let (pictures, sound) = (tracks(&after)[0], tracks(&after)[1]);
        let said = list(&after, &sound).expect("the sound's list");
        let ffmpeg = fixture("tone.m4a");
        let ffmpeg_moov = moov_of(&ffmpeg);
        let ffmpeg_said = list(ffmpeg_moov, &tracks(ffmpeg_moov)[0]).expect("ffmpeg's list");
        assert_eq!(said[..8], ffmpeg_said[..8], "its version and its one edit");
        assert_eq!(said[8..12], 21000u32.to_be_bytes(), "how long it plays, in the movie's scale");
        assert_eq!(said[12..], ffmpeg_said[12..], "1,024 in, at the media's own speed");
        assert_eq!(said[12..16], 1024u32.to_be_bytes());
        assert_eq!(list(&after, &pictures), None, "the pictures get none");
        let kinds: Vec<_> = iso_box::atoms(&after, sound.body, sound.end).map(|atom| atom.kind).collect();
        assert_eq!(kinds, [*b"tkhd", *b"edts", *b"mdia"], "where ffmpeg puts it");
    }

    // Every box still ends where the one after it starts, and nothing but
    // the list, two sizes and two lengths is new.
    #[test]
    fn a_marked_movie_is_the_same_movie_with_the_list_in_it() {
        let movie = fixture("tone_with_video.mp4");
        let before = moov_of(&movie);
        let after = marked(before, 44100, 1024, 21000).expect("it is marked");
        let whole = iso_box::atom(&after, 0, after.len()).expect("a movie box");
        assert_eq!((whole.end, after.len()), (before.len() + 36, before.len() + 36));
        let (was, is) = (tracks(before), tracks(&after));
        assert_eq!(is.len(), 2);
        assert_eq!(after[is[0].at..is[0].end], before[was[0].at..was[0].end], "the pictures' track, byte for byte");
        assert_eq!((is[1].at, is[1].end), (was[1].at, was[1].end + 36));
        assert_eq!(after[is[1].end..], before[was[1].end..], "what follows the sound's track");
        let tkhd = iso_box::find(&after, is[1].body, is[1].end, &[b"tkhd"]).expect("its header");
        let mdia = iso_box::find(&after, is[1].body, is[1].end, &[b"mdia"]).expect("its media");
        assert_eq!(after[mdia.at..mdia.end], before[mdia.at - 36..mdia.end - 36], "the sound's media, byte for byte");
        let changed: Vec<_> = (0..tkhd.end).filter(|&at| after[at] != before[at]).collect();
        let mvhd = iso_box::find(&after, whole.body, whole.end, &[b"mvhd"]).expect("the movie's header");
        let fields = [0..4, length_field(&after, &mvhd).unwrap(), is[1].at..is[1].at + 4, length_field(&after, &tkhd).unwrap()];
        assert!(changed.iter().all(|at| fields.iter().any(|field| field.contains(at))), "{changed:?} in {fields:?}");
        assert!(!changed.is_empty());
    }

    // A track with a list is as long as its edits, and a movie as its
    // longest track: the pictures' 22,049 ticks where the sound plays
    // fewer, the sound's where it plays more.
    #[test]
    fn the_track_and_the_movie_are_as_long_as_the_list_says() {
        let movie = fixture("tone_with_video.mp4");
        let before = moov_of(&movie);
        for (kept, movie_length) in [(21000, 22049), (22050, 22050), (30000, 30000)] {
            let after = marked(before, 44100, 1024, kept).expect("it is marked");
            let whole = iso_box::atom(&after, 0, after.len()).unwrap();
            let sound = tracks(&after)[1];
            assert_eq!(header_length(&after, sound.body, sound.end, b"tkhd"), kept as u64, "the sound's track");
            assert_eq!(header_length(&after, whole.body, whole.end, b"mvhd"), movie_length, "the movie, {kept} kept");
        }
    }

    // What is not the sink writer's movie is left alone: ffmpeg's, whose
    // sound has its list; a movie box with no sound in it.
    #[test]
    fn a_movie_that_is_not_the_sink_writer_s_is_not_marked() {
        let ffmpeg = fixture("tone.m4a");
        assert_eq!(marked(moov_of(&ffmpeg), 44100, 1024, 21000), None, "a list is there already");
        let movie = fixture("tone_with_video.mp4");
        let moov = moov_of(&movie);
        let pictures = tracks(moov)[0];
        let mut silent = moov[..pictures.end].to_vec();
        silent[..4].copy_from_slice(&(pictures.end as u32).to_be_bytes());
        assert_eq!(marked(&silent, 44100, 1024, 21000), None, "no sound track");
        assert_eq!(marked(moov, 0, 1024, 21000), None, "no rate to count by");
        assert_eq!(marked(moov, 44100, 1024, -1), None, "fewer frames than none");
    }

    // The file: the movie box rewritten where it stood, the rest as it was
    // — and a movie box that does not close the file not touched.
    #[test]
    fn the_file_grows_by_the_list_and_nothing_before_the_movie_box_moves() {
        let movie = fixture("tone_with_video.mp4");
        let dir = std::env::temp_dir();
        let path = dir.join(format!("anicel-edit-list-{}.mp4", std::process::id()));
        std::fs::write(&path, &movie).unwrap();
        assert_eq!(mark_the_lead(&path, 44100, 1024, 21000), Some(()));
        let written = std::fs::read(&path).unwrap();
        let moov = iso_box::find(&movie, 0, movie.len(), &[b"moov"]).unwrap();
        assert_eq!(written.len(), movie.len() + 36);
        assert_eq!(written[..moov.at], movie[..moov.at], "everything before the movie box");
        assert_eq!(written[moov.at..], marked(moov_of(&movie), 44100, 1024, 21000).unwrap()[..]);

        let mut followed = movie.clone();
        followed.extend_from_slice(&[0, 0, 0, 8, b'f', b'r', b'e', b'e']);
        std::fs::write(&path, &followed).unwrap();
        assert_eq!(mark_the_lead(&path, 44100, 1024, 21000), None, "a box follows the movie box");
        assert_eq!(std::fs::read(&path).unwrap(), followed, "and the file is as it was");
        std::fs::write(&path, &movie[..moov.at]).unwrap();
        assert_eq!(mark_the_lead(&path, 44100, 1024, 21000), None, "no movie box at all");
        std::fs::remove_file(&path).unwrap();
    }

    #[test]
    fn a_list_is_said_in_32_bits_where_they_hold_it_and_in_64_where_not() {
        let narrow = edit(48000, 1024);
        let mut want = vec![0, 0, 0, 36];
        want.extend_from_slice(b"edts");
        want.extend_from_slice(&[0, 0, 0, 28]);
        want.extend_from_slice(b"elst");
        want.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 1]);
        want.extend_from_slice(&48000u32.to_be_bytes());
        want.extend_from_slice(&1024u32.to_be_bytes());
        want.extend_from_slice(&[0, 1, 0, 0]);
        assert_eq!(narrow, want);
        let long = u64::from(u32::MAX) + 1;
        let wide = edit(long, 1024);
        let mut want = vec![0, 0, 0, 44];
        want.extend_from_slice(b"edts");
        want.extend_from_slice(&[0, 0, 0, 36]);
        want.extend_from_slice(b"elst");
        want.extend_from_slice(&[1, 0, 0, 0, 0, 0, 0, 1]);
        want.extend_from_slice(&long.to_be_bytes());
        want.extend_from_slice(&1024u64.to_be_bytes());
        want.extend_from_slice(&[0, 1, 0, 0]);
        assert_eq!(wide, want);
    }

    #[test]
    fn frames_are_ticks_to_the_nearest() {
        assert_eq!(ticks(48000, 48000, 48000), Some(48000), "the sink writer's scales: a tick is a frame");
        assert_eq!(ticks(22050, 1000, 44100), Some(500), "ffmpeg's movie scale");
        assert_eq!(ticks(22071, 1000, 44100), Some(500));
        assert_eq!(ticks(22073, 1000, 44100), Some(501), "half a tick and over rounds up");
        assert_eq!(ticks(0, 48000, 48000), Some(0));
    }
}
