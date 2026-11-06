//! Movies whose sound is uncompressed, made up here in the shapes the C's
//! own test makes (`qa_audio_range_test.c`), each decoded by both.

use super::{Span, TempFile, between_junk, c_window, expect_same, framed, noise, rust_window};
use crate::FORMAT_MOVIE_PCM;

/// How a writer stores a movie's sound: the description's type, its
/// version and the bits it says, the bytes of a sample, and where an `enda`
/// of 1 is (0 nowhere, 1 in a `wave`, 2 the description's own); a
/// version-2 description's flags.
#[derive(Clone, Copy)]
struct Sound {
    kind: &'static [u8; 4],
    version: u16,
    bits: u32,
    sample_bytes: usize,
    enda: u8,
    flags: u32,
}

const SOWT: Sound = Sound { kind: b"sowt", version: 0, bits: 16, sample_bytes: 2, enda: 0, flags: 0 };

/// How a movie lays its sound out: the frames of each chunk, the bytes of
/// something else before each, whether the movie box comes first, the
/// offsets 64-bit, an edit (media time, duration), the frames the size
/// table counts (None: the chunks'), the data reference's self flag, the
/// ticks a sample lasts, and how many descriptions.
#[derive(Clone)]
struct Layout {
    chunks: Vec<usize>,
    between: usize,
    movie_first: bool,
    wide: bool,
    edit: Option<(i32, u32)>,
    frames_said: Option<u32>,
    self_reference: bool,
    tick: u32,
    descriptions: u32,
}

impl Default for Layout {
    fn default() -> Layout {
        Layout {
            chunks: vec![1000, 1000, 345],
            between: 0,
            movie_first: false,
            wide: false,
            edit: None,
            frames_said: None,
            self_reference: true,
            tick: 1,
            descriptions: 1,
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
    let mut with_flags = vec![0u8; 4];
    with_flags.extend_from_slice(body);
    atom(kind, &with_flags)
}

fn be32(values: &[u32]) -> Vec<u8> {
    values.iter().flat_map(|value| value.to_be_bytes()).collect()
}

/// The sample description of `sound`, `channels` at `rate`.
fn description(sound: &Sound, channels: u16, rate: u32) -> Vec<u8> {
    let mut body = vec![0u8; 6];
    body.extend_from_slice(&1u16.to_be_bytes());
    body.extend_from_slice(&sound.version.to_be_bytes());
    body.extend_from_slice(&[0u8; 6]);
    if sound.version == 2 {
        body.extend_from_slice(&[0, 3, 0, 16, 0xFF, 0xFE, 0, 0]);
        body.extend_from_slice(&be32(&[0x0001_0000, 72]));
        body.extend_from_slice(&f64::from(rate).to_bits().to_be_bytes());
        body.extend_from_slice(&be32(&[u32::from(channels), 0x7F00_0000, sound.bits, sound.flags]));
        body.extend_from_slice(&be32(&[u32::from(channels) * sound.bits / 8, 1]));
    } else {
        body.extend_from_slice(&channels.to_be_bytes());
        body.extend_from_slice(&(sound.bits as u16).to_be_bytes());
        body.extend_from_slice(&[0, 0, 0, 0]);
        body.extend_from_slice(&(rate << 16).to_be_bytes());
        if sound.version == 1 {
            let frame = (usize::from(channels) * sound.sample_bytes) as u32;
            body.extend_from_slice(&be32(&[1, sound.sample_bytes as u32, frame, sound.sample_bytes as u32]));
        }
    }
    let enda = full(b"enda", &[0, 1]);
    match sound.enda {
        1 => body.extend(atom(b"wave", &enda)),
        2 => body.extend(enda),
        _ => {}
    }
    atom(sound.kind, &body)
}

/// A movie of `layout`, its sound `channels` of `sound` at 48 kHz.
fn movie(sound: &Sound, channels: u16, layout: &Layout) -> Vec<u8> {
    const RATE: u32 = 48_000;
    let frame_bytes = usize::from(channels) * sound.sample_bytes;
    let frames: usize = layout.chunks.iter().sum();
    let samples = noise(frames * frame_bytes, 5);
    let ftyp = atom(b"ftyp", b"qt  \0\0\0\0qt  ");

    let moov = |offsets: &[u64]| {
        let mut mvhd = vec![0u8; 8];
        mvhd.extend_from_slice(&be32(&[600, 0, 0x0001_0000]));
        mvhd.extend(vec![0u8; 80]);
        let mut mdhd = vec![0u8; 8];
        mdhd.extend_from_slice(&be32(&[RATE, frames as u32, 0]));
        let mut hdlr = b"mhlrsoun".to_vec();
        hdlr.extend(vec![0u8; 13]);
        let reference = full(b"alis", &[]);
        let mut reference = reference.clone();
        reference[11] = u8::from(layout.self_reference);
        let mut dref = be32(&[1]);
        dref.extend(reference);
        let mut stsd = be32(&[layout.descriptions]);
        for _ in 0..layout.descriptions {
            stsd.extend(description(sound, channels, RATE));
        }
        let mut runs = Vec::new();
        for (index, &chunk) in layout.chunks.iter().enumerate() {
            if runs.last().is_none_or(|&(_, frames)| frames != chunk) {
                runs.push((index + 1, chunk));
            }
        }
        let mut stsc = be32(&[runs.len() as u32]);
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
        let minf = [atom(b"dinf", &full(b"dref", &dref)), atom(b"stbl", &stbl)].concat();
        let mdia = [full(b"mdhd", &mdhd), full(b"hdlr", &hdlr), atom(b"minf", &minf)].concat();
        let mut trak = Vec::new();
        if let Some((media_time, duration)) = layout.edit {
            let elst = be32(&[1, duration, media_time as u32, 0x0001_0000]);
            trak.extend(atom(b"edts", &full(b"elst", &elst)));
        }
        trak.extend(atom(b"mdia", &mdia));
        atom(b"moov", &[full(b"mvhd", &mvhd), atom(b"trak", &trak)].concat())
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
    let mdat = atom(b"mdat", &mdat_body);
    let moov_bytes = moov(&vec![0; layout.chunks.len()]).len();
    let mdat_body_at = ftyp.len() + if layout.movie_first { moov_bytes } else { 0 } + 8;
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
        ("lpcm, float little", Sound { kind: b"lpcm", version: 2, bits: 32, sample_bytes: 4, enda: 0, flags: 1 }),
        ("lpcm, signed 24 big", Sound { kind: b"lpcm", version: 2, bits: 24, sample_bytes: 3, enda: 0, flags: 4 | 2 }),
        ("lpcm, unsigned 8", Sound { kind: b"lpcm", version: 2, bits: 8, sample_bytes: 1, enda: 0, flags: 0 }),
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
    let layouts = [
        ("a reel", reel.clone()),
        ("a reel, the movie box first", Layout { movie_first: true, ..reel.clone() }),
        ("64-bit offsets", Layout { wide: true, ..reel.clone() }),
        ("an edit holding back 1,024", Layout { edit: Some((1024, 600)), ..reel.clone() }),
        ("an edit past the sound", Layout { edit: Some((5000, 0)), ..reel.clone() }),
        ("an empty edit only", Layout { edit: Some((-1, 600)), ..reel.clone() }),
        ("fewer frames said than the chunks hold", Layout { frames_said: Some(600), ..reel.clone() }),
        ("more frames said than the chunks hold", Layout { frames_said: Some(9000), ..reel.clone() }),
        ("one chunk", Layout { chunks: vec![4801], ..Layout::default() }),
    ];
    for (what, layout) in layouts {
        expect_movie(what, &movie(&SOWT, 2, &layout));
    }
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
    for (what, sound, layout) in [
        ("its sound in another file", SOWT, Layout { self_reference: false, ..reel.clone() }),
        ("a sample two frames long", SOWT, Layout { tick: 2, ..reel.clone() }),
        ("described two ways", SOWT, Layout { descriptions: 2, ..reel.clone() }),
        ("raw of 16 bits", Sound { kind: b"raw ", ..SOWT }, reel.clone()),
        ("12 bits", Sound { bits: 12, ..SOWT }, reel.clone()),
        ("lpcm one channel after another", Sound { kind: b"lpcm", version: 2, bits: 16, sample_bytes: 2, enda: 0, flags: 4 | 32 }, reel.clone()),
    ] {
        let file = TempFile::new("refused.mov", &movie(&sound, 2, &layout));
        let span = Span::whole(file.path());
        let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
        assert_ne!(rust.format, FORMAT_MOVIE_PCM, "{what}");
        assert_ne!(c.format, FORMAT_MOVIE_PCM, "{what}: the C's");
    }
}
