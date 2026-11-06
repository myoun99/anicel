//! Movies whose sound is uncompressed, made up here in the shapes the C's
//! own test makes (`qa_audio_range_test.c`), each decoded by both.

use super::{Span, TempFile, between_junk, c_window, expect_same, framed, noise, rust_window};
use crate::FORMAT_MOVIE_PCM;

/// How a writer stores a movie's sound: the description's type, its
/// version and the bits it says, the bytes of a sample, and where an `enda`
/// of 1 is (0 nowhere, 1 in a `wave`, 2 the description's own); a
/// version-2 description's flags, and the frames it says a packet holds;
/// whether a version-1 description leaves its own four fields out.
#[derive(Clone, Copy)]
struct Sound {
    kind: &'static [u8; 4],
    version: u16,
    bits: u32,
    sample_bytes: usize,
    enda: u8,
    flags: u32,
    packet_frames: u32,
    cut_short: bool,
}

const SOWT: Sound =
    Sound { kind: b"sowt", version: 0, bits: 16, sample_bytes: 2, enda: 0, flags: 0, packet_frames: 1, cut_short: false };

/// How a movie lays its sound out: the frames of each chunk, the bytes of
/// something else before each, whether the movie box comes first, the
/// offsets 64-bit, the edits (media time, duration), the frames the size
/// table counts (None: the chunks'), the data references (None: no `dinf`;
/// each one's self flag), the ticks a sample lasts, and how many
/// descriptions; the movie's clock, whether its headers are the 64-bit
/// kind (version 1), whether its data box says a 64-bit size, and the text
/// of an iTunes note in it, in an ISO `meta` or a QuickTime one; how many
/// runs the sample-to-chunk table says it has (None: the ones it has), and
/// the handler of a track of something else before the sound's.
#[derive(Clone)]
struct Layout {
    chunks: Vec<usize>,
    between: usize,
    movie_first: bool,
    wide: bool,
    edits: Vec<(i32, u32)>,
    frames_said: Option<u32>,
    references: Option<Vec<bool>>,
    tick: u32,
    descriptions: u32,
    movie_scale: u32,
    long_headers: bool,
    wide_mdat: bool,
    itunes: Option<(&'static str, bool)>,
    runs_said: Option<u32>,
    track_before: Option<&'static [u8; 4]>,
}

impl Default for Layout {
    fn default() -> Layout {
        Layout {
            chunks: vec![1000, 1000, 345],
            between: 0,
            movie_first: false,
            wide: false,
            edits: Vec::new(),
            frames_said: None,
            references: Some(vec![true]),
            tick: 1,
            descriptions: 1,
            movie_scale: 600,
            long_headers: false,
            wide_mdat: false,
            itunes: None,
            runs_said: None,
            track_before: None,
        }
    }
}

fn atom(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
    let mut bytes = ((body.len() + 8) as u32).to_be_bytes().to_vec();
    bytes.extend_from_slice(kind);
    bytes.extend_from_slice(body);
    bytes
}

fn full(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
    versioned(kind, 0, body)
}

/// A box with a version and flags (all clear) before `body`.
fn versioned(kind: &[u8; 4], version: u8, body: &[u8]) -> Vec<u8> {
    let mut with_flags = vec![version, 0, 0, 0];
    with_flags.extend_from_slice(body);
    atom(kind, &with_flags)
}

/// A movie header's (`mvhd`) or a media header's (`mdhd`) body: the dates,
/// the clock and the duration — 64-bit dates and duration in version 1 —
/// then `rest`.
fn header(kind: &[u8; 4], long: bool, scale: u32, duration: u32, rest: &[u8]) -> Vec<u8> {
    let mut body = vec![0u8; if long { 16 } else { 8 }];
    body.extend_from_slice(&scale.to_be_bytes());
    if long {
        body.extend_from_slice(&u64::from(duration).to_be_bytes());
    } else {
        body.extend_from_slice(&duration.to_be_bytes());
    }
    body.extend_from_slice(rest);
    versioned(kind, u8::from(long), &body)
}

/// The note iTunes leaves — an item of a writer's own (`----`) named
/// `iTunSMPB` holding `text` — in the user data of a movie: an ISO `meta`
/// (version and flags first) or a QuickTime one (none).
fn itunes_note(text: &str, iso: bool) -> Vec<u8> {
    let mut data = vec![0u8; 4];
    data.extend_from_slice(text.as_bytes());
    let item = [full(b"mean", b"com.apple.iTunes"), full(b"name", b"iTunSMPB"), full(b"data", &data)].concat();
    let mut meta = if iso { vec![0u8; 4] } else { Vec::new() };
    meta.extend(full(b"hdlr", b"\0\0\0\0mdirappl\0\0\0\0\0\0\0\0\0"));
    meta.extend(atom(b"ilst", &atom(b"----", &item)));
    atom(b"udta", &atom(b"meta", &meta))
}

fn be32(values: &[u32]) -> Vec<u8> {
    values.iter().flat_map(|value| value.to_be_bytes()).collect()
}

/// The sample description of `sound`, `channels` at `rate`, naming data
/// reference `reference`.
fn description(sound: &Sound, channels: u16, rate: u32, reference: u16) -> Vec<u8> {
    let mut body = vec![0u8; 6];
    body.extend_from_slice(&reference.to_be_bytes());
    body.extend_from_slice(&sound.version.to_be_bytes());
    body.extend_from_slice(&[0u8; 6]);
    if sound.version == 2 {
        body.extend_from_slice(&[0, 3, 0, 16, 0xFF, 0xFE, 0, 0]);
        body.extend_from_slice(&be32(&[0x0001_0000, 72]));
        body.extend_from_slice(&f64::from(rate).to_bits().to_be_bytes());
        body.extend_from_slice(&be32(&[u32::from(channels), 0x7F00_0000, sound.bits, sound.flags]));
        let packet_bytes = u32::from(channels) * sound.bits / 8 * sound.packet_frames;
        body.extend_from_slice(&be32(&[packet_bytes, sound.packet_frames]));
    } else {
        body.extend_from_slice(&channels.to_be_bytes());
        body.extend_from_slice(&(sound.bits as u16).to_be_bytes());
        body.extend_from_slice(&[0, 0, 0, 0]);
        body.extend_from_slice(&(rate << 16).to_be_bytes());
        if sound.version == 1 && !sound.cut_short {
            let frame = (usize::from(channels) * sound.sample_bytes) as u32;
            body.extend_from_slice(&be32(&[1, sound.sample_bytes as u32, frame, sound.sample_bytes as u32]));
        }
    }
    // An `enda` is no full box: its body is the 16-bit flag alone.
    let enda = atom(b"enda", &[0, 1]);
    match sound.enda {
        1 => body.extend(atom(b"wave", &enda)),
        2 => body.extend(enda),
        _ => {}
    }
    atom(sound.kind, &body)
}

/// A movie of `layout`, its sound `channels` of `sound` at 48 kHz.
fn movie(sound: &Sound, channels: u16, layout: &Layout) -> Vec<u8> {
    movie_naming(sound, channels, layout, 1)
}

/// The same, its description naming data reference `reference`.
fn movie_naming(sound: &Sound, channels: u16, layout: &Layout, reference: u16) -> Vec<u8> {
    const RATE: u32 = 48_000;
    let frame_bytes = usize::from(channels) * sound.sample_bytes;
    let frames: usize = layout.chunks.iter().sum();
    let samples = noise(frames * frame_bytes, 5);
    let ftyp = atom(b"ftyp", b"qt  \0\0\0\0qt  ");

    // A track of `handler`, its descriptions of `kind`.
    let trak = |offsets: &[u64], handler: &[u8; 4], kind: &'static [u8; 4]| {
        let mdhd = header(b"mdhd", layout.long_headers, RATE, frames as u32, &[0u8; 4]);
        let mut hdlr = b"mhlr".to_vec();
        hdlr.extend_from_slice(handler);
        hdlr.extend(vec![0u8; 13]);
        let mut stsd = be32(&[layout.descriptions]);
        for _ in 0..layout.descriptions {
            stsd.extend(description(&Sound { kind, ..*sound }, channels, RATE, reference));
        }
        let mut runs = Vec::new();
        for (index, &chunk) in layout.chunks.iter().enumerate() {
            if runs.last().is_none_or(|&(_, frames)| frames != chunk) {
                runs.push((index + 1, chunk));
            }
        }
        let mut stsc = be32(&[layout.runs_said.unwrap_or(runs.len() as u32)]);
        runs.iter().for_each(|&(first, frames)| stsc.extend(be32(&[first as u32, frames as u32, 1])));
        let mut chunk_table = be32(&[offsets.len() as u32]);
        for &offset in offsets {
            if layout.wide {
                chunk_table.extend_from_slice(&offset.to_be_bytes());
            } else {
                chunk_table.extend_from_slice(&(offset as u32).to_be_bytes());
            }
        }
        let stbl = [
            full(b"stsd", &stsd),
            full(b"stts", &be32(&[1, frames as u32, layout.tick])),
            full(b"stsc", &stsc),
            full(b"stsz", &be32(&[1, layout.frames_said.unwrap_or(frames as u32)])),
            full(if layout.wide { b"co64" } else { b"stco" }, &chunk_table),
        ]
        .concat();
        let mut minf = Vec::new();
        if let Some(references) = &layout.references {
            let mut dref = be32(&[references.len() as u32]);
            for &own in references {
                let mut reference = full(b"alis", &[]);
                reference[11] = u8::from(own);
                dref.extend(reference);
            }
            minf.extend(atom(b"dinf", &full(b"dref", &dref)));
        }
        minf.extend(atom(b"stbl", &stbl));
        let mdia = [mdhd, full(b"hdlr", &hdlr), atom(b"minf", &minf)].concat();
        let mut trak = Vec::new();
        if !layout.edits.is_empty() {
            let mut elst = be32(&[layout.edits.len() as u32]);
            for &(media_time, duration) in &layout.edits {
                elst.extend(be32(&[duration, media_time as u32, 0x0001_0000]));
            }
            trak.extend(atom(b"edts", &full(b"elst", &elst)));
        }
        trak.extend(atom(b"mdia", &mdia));
        atom(b"trak", &trak)
    };
    let moov = |offsets: &[u64]| {
        let mvhd = header(b"mvhd", layout.long_headers, layout.movie_scale, 0, &[vec![0, 1, 0, 0], vec![0u8; 76]].concat());
        let mut moov = mvhd;
        if let Some(handler) = layout.track_before {
            moov.extend(trak(offsets, handler, handler));
        }
        moov.extend(trak(offsets, b"soun", sound.kind));
        if let Some((text, iso)) = layout.itunes {
            moov.extend(itunes_note(text, iso));
        }
        atom(b"moov", &moov)
    };

    let between = noise(layout.between, 77);
    let mut mdat_body = Vec::new();
    let mut at_in_mdat = Vec::new();
    let mut from = 0;
    for &chunk in &layout.chunks {
        mdat_body.extend_from_slice(&between);
        at_in_mdat.push(mdat_body.len());
        mdat_body.extend_from_slice(&samples[from..from + chunk * frame_bytes]);
        from += chunk * frame_bytes;
    }
    let mdat = if layout.wide_mdat {
        // Size 1: the size is the 64-bit word after the type.
        let mut mdat = be32(&[1]);
        mdat.extend_from_slice(b"mdat");
        mdat.extend_from_slice(&(mdat_body.len() as u64 + 16).to_be_bytes());
        mdat.extend(mdat_body);
        mdat
    } else {
        atom(b"mdat", &mdat_body)
    };
    let moov_bytes = moov(&vec![0; layout.chunks.len()]).len();
    let mdat_head = if layout.wide_mdat { 16 } else { 8 };
    let mdat_body_at = ftyp.len() + if layout.movie_first { moov_bytes } else { 0 } + mdat_head;
    let offsets: Vec<u64> = at_in_mdat.iter().map(|&at| (mdat_body_at + at) as u64).collect();
    let moov = moov(&offsets);
    if layout.movie_first { [ftyp, moov, mdat].concat() } else { [ftyp, mdat, moov].concat() }
}

fn expect_movie(what: &str, bytes: &[u8]) {
    let file = TempFile::new("movie.mov", bytes);
    let decoded = expect_same(what, &Span::whole(file.path()), 0, -1);
    assert_eq!(decoded.format, FORMAT_MOVIE_PCM, "{what}: read as a movie's uncompressed sound");
}

#[test]
fn every_shape_of_a_movie_s_sound_reads_as_the_c_reads_it() {
    let lpcm = Sound { kind: b"lpcm", version: 2, enda: 0, ..SOWT };
    let sounds = [
        ("sowt 16", SOWT),
        ("twos 16", Sound { kind: b"twos", ..SOWT }),
        ("twos 8", Sound { kind: b"twos", bits: 8, sample_bytes: 1, ..SOWT }),
        ("sowt 24", Sound { bits: 24, sample_bytes: 3, ..SOWT }),
        ("sowt 32", Sound { bits: 32, sample_bytes: 4, ..SOWT }),
        ("raw 8", Sound { kind: b"raw ", bits: 8, sample_bytes: 1, ..SOWT }),
        ("in24, big", Sound { kind: b"in24", bits: 24, sample_bytes: 3, version: 1, ..SOWT }),
        ("in24, little in a wave", Sound { kind: b"in24", bits: 24, sample_bytes: 3, version: 1, enda: 1, ..SOWT }),
        ("in32, little of its own", Sound { kind: b"in32", bits: 32, sample_bytes: 4, version: 1, enda: 2, ..SOWT }),
        ("fl32, little in a wave", Sound { kind: b"fl32", bits: 32, sample_bytes: 4, version: 1, enda: 1, ..SOWT }),
        ("fl64, big", Sound { kind: b"fl64", bits: 64, sample_bytes: 8, version: 1, ..SOWT }),
        ("lpcm, float little", Sound { bits: 32, sample_bytes: 4, flags: 1, ..lpcm }),
        ("lpcm, float big", Sound { bits: 64, sample_bytes: 8, flags: 1 | 2, ..lpcm }),
        ("lpcm, signed 24 big", Sound { bits: 24, sample_bytes: 3, flags: 4 | 2, ..lpcm }),
        ("lpcm, unsigned 8", Sound { bits: 8, sample_bytes: 1, flags: 0, ..lpcm }),
    ];
    for (what, sound) in sounds {
        for channels in [1, 2] {
            let bytes = movie(&sound, channels, &Layout::default());
            // The float ones are noise read as floats: some are NaN, and a
            // NaN's bits are held like any other's.
            expect_movie(&format!("{what}, {channels} channels"), &bytes);
        }
    }
}

#[test]
fn every_layout_of_a_movie_s_sound_reads_as_the_c_reads_it() {
    let reel = Layout { chunks: vec![250, 250, 70, 250, 30], between: 1000, ..Layout::default() };
    // iTunes' words: 0, the frames before the sound, the frames after it,
    // the sound's own length.
    let note = " 00000000 00000100 000000AB 00000000000001F4";
    let layouts = [
        ("a reel", reel.clone()),
        ("a reel, the movie box first", Layout { movie_first: true, ..reel.clone() }),
        ("64-bit offsets", Layout { wide: true, ..reel.clone() }),
        ("a 64-bit data box", Layout { wide_mdat: true, ..reel.clone() }),
        ("an edit holding back 1,024", Layout { edits: vec![(1024, 600)], ..reel.clone() }),
        ("an edit past the sound", Layout { edits: vec![(5000, 0)], ..reel.clone() }),
        ("an edit of no duration", Layout { edits: vec![(300, 0)], ..reel.clone() }),
        ("a track of time codes before the sound's", Layout { track_before: Some(b"tmcd"), ..reel.clone() }),
        ("an empty edit only", Layout { edits: vec![(-1, 600)], ..reel.clone() }),
        ("an empty edit, then one holding back 300", Layout { edits: vec![(-1, 600), (300, 4)], ..reel.clone() }),
        // 1 tick of a clock of 70 is 685.7 frames, kept as 686.
        ("an edit in a clock of 70", Layout { edits: vec![(17, 1)], movie_scale: 70, ..reel.clone() }),
        ("an edit, and 64-bit headers", Layout { edits: vec![(64, 3)], long_headers: true, ..reel.clone() }),
        ("an edit, and a clock not said", Layout { edits: vec![(64, 3)], movie_scale: 0, ..reel.clone() }),
        ("iTunes' note", Layout { itunes: Some((note, false)), ..reel.clone() }),
        ("iTunes' note, in an ISO meta", Layout { itunes: Some((note, true)), ..reel.clone() }),
        ("iTunes' note of no length", Layout { itunes: Some((" 0 80 0 0", true)), ..reel.clone() }),
        ("iTunes' note, cut short", Layout { itunes: Some((" 00000000 00000100", true)), ..reel.clone() }),
        ("iTunes' note and an edit", Layout { itunes: Some((note, true)), edits: vec![(32, 600)], ..reel.clone() }),
        ("no data references", Layout { references: None, ..reel.clone() }),
        ("fewer frames said than the chunks hold", Layout { frames_said: Some(600), ..reel.clone() }),
        ("more frames said than the chunks hold", Layout { frames_said: Some(9000), ..reel.clone() }),
        ("one chunk", Layout { chunks: vec![4801], ..Layout::default() }),
        // More runs and chunks than one read of a table holds.
        ("1,500 chunks", Layout { chunks: (0..1500).map(|index| 3 + index % 2).collect(), ..Layout::default() }),
    ];
    for (what, layout) in layouts {
        expect_movie(what, &movie(&SOWT, 2, &layout));
    }
    // The second of two data references named, this file's.
    let two = Layout { references: Some(vec![false, true]), ..reel.clone() };
    expect_movie("the second data reference", &movie_naming(&SOWT, 2, &two, 2));
    // Carried, and framed as a save frames it.
    let bytes = movie(&SOWT, 2, &reel);
    let (carried, offset) = between_junk("carried.mov", &bytes);
    let span = Span { path: carried.path(), offset, length: bytes.len() as i64, framed: false };
    expect_same("carried", &span, 0, -1);
    let blob = framed(&bytes, 1000);
    let (kept, offset) = between_junk("framed.mov", &blob);
    let span = Span { path: kept.path(), offset, length: blob.len() as i64, framed: true };
    expect_same("framed", &span, 0, -1);
    expect_same("framed, a window", &span, 333, 222);
    // Cut short in the middle of a chunk.
    let mut cut = movie(&SOWT, 2, &Layout { movie_first: true, ..reel });
    cut.truncate(cut.len() - 1801);
    expect_movie("cut short", &cut);
}

#[test]
fn a_movie_whose_sound_this_does_not_read_is_left_as_the_c_leaves_it() {
    let reel = Layout { chunks: vec![250, 250, 70], between: 100, ..Layout::default() };
    let lpcm = Sound { kind: b"lpcm", version: 2, bits: 16, sample_bytes: 2, enda: 0, flags: 4, ..SOWT };
    for (what, sound, layout, reference) in [
        ("its sound in another file", SOWT, Layout { references: Some(vec![false]), ..reel.clone() }, 1),
        ("a reference the list does not have", SOWT, reel.clone(), 2),
        ("a sample two frames long", SOWT, Layout { tick: 2, ..reel.clone() }, 1),
        ("described two ways", SOWT, Layout { descriptions: 2, ..reel.clone() }, 1),
        ("raw of 16 bits", Sound { kind: b"raw ", ..SOWT }, reel.clone(), 1),
        ("12 bits", Sound { bits: 12, ..SOWT }, reel.clone(), 1),
        ("lpcm one channel after another", Sound { flags: 4 | 32, ..lpcm }, reel.clone(), 1),
        ("lpcm, two frames a packet", Sound { packet_frames: 2, ..lpcm }, reel.clone(), 1),
        ("lpcm of 12 bits", Sound { bits: 12, ..lpcm }, reel.clone(), 1),
        ("lpcm, unsigned 16", Sound { flags: 0, ..lpcm }, reel.clone(), 1),
        ("a version-1 description cut short", Sound { version: 1, cut_short: true, ..SOWT }, reel.clone(), 1),
        ("more runs said than the table holds", SOWT, Layout { runs_said: Some(1000), ..reel.clone() }, 1),
    ] {
        expect_refused(what, &movie_naming(&sound, 2, &layout, reference));
    }
    // A sample table that says it runs past the box it is in.
    let mut past = movie(&SOWT, 2, &reel);
    let at = past.windows(4).position(|kind| kind == b"stbl").expect("a sample table") - 4;
    let size = u32::from_be_bytes(past[at..at + 4].try_into().expect("4 bytes")) + 100;
    past[at..at + 4].copy_from_slice(&size.to_be_bytes());
    expect_refused("a sample table past its box", &past);
}

fn expect_refused(what: &str, bytes: &[u8]) {
    let file = TempFile::new("refused.mov", bytes);
    let span = Span::whole(file.path());
    let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
    assert_ne!(rust.format, FORMAT_MOVIE_PCM, "{what}");
    assert_ne!(c.format, FORMAT_MOVIE_PCM, "{what}: the C's");
}
