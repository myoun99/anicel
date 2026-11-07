//! WAVs, AIFFs and MPEG frames made up here, each decoded by both.

use super::{Span, TempFile, between_junk, c_window, expect_left_to_the_os, expect_same, framed, noise, rust_window};

/// A WAV's `fmt ` chunk body.
fn fmt(tag: u16, channels: u16, rate: u32, bits: u16, block_align: u16, extensible: Option<(u16, u16)>) -> Vec<u8> {
    let mut body = Vec::new();
    body.extend_from_slice(&(if extensible.is_some() { 0xFFFE } else { tag }).to_le_bytes());
    body.extend_from_slice(&channels.to_le_bytes());
    body.extend_from_slice(&rate.to_le_bytes());
    body.extend_from_slice(&(rate * u32::from(block_align)).to_le_bytes());
    body.extend_from_slice(&block_align.to_le_bytes());
    body.extend_from_slice(&bits.to_le_bytes());
    if let Some((valid, mask)) = extensible {
        body.extend_from_slice(&22u16.to_le_bytes());
        body.extend_from_slice(&valid.to_le_bytes());
        body.extend_from_slice(&u32::from(mask).to_le_bytes());
        // The subformat GUID: the tag, then KSDATAFORMAT's tail.
        body.extend_from_slice(&u32::from(tag).to_le_bytes());
        body.extend_from_slice(&[0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]);
    }
    body
}

/// A RIFF of `chunks`, each padded to an even size as the format says.
fn riff(form: &[u8; 4], chunks: &[(&[u8; 4], &[u8])]) -> Vec<u8> {
    let mut body = form.to_vec();
    for (id, data) in chunks {
        body.extend_from_slice(*id);
        body.extend_from_slice(&(data.len() as u32).to_le_bytes());
        body.extend_from_slice(data);
        if data.len() % 2 == 1 {
            body.push(0);
        }
    }
    let mut bytes = b"RIFF".to_vec();
    bytes.extend_from_slice(&(body.len() as u32).to_le_bytes());
    bytes.extend(body);
    bytes
}

fn wav(tag: u16, channels: u16, bits: u16, container: u16, frames: usize, seed: u32) -> Vec<u8> {
    let align = channels * container / 8;
    let data = noise(frames * usize::from(align), seed);
    riff(b"WAVE", &[(b"fmt ", &fmt(tag, channels, 44_100, bits, align, None)), (b"data", &data)])
}

/// Floats in a WAV — finite ones, some past full scale.
fn float_wav(bits: u16, frames: usize) -> Vec<u8> {
    let raw = noise(frames * 2 * 4, 99);
    let data: Vec<u8> = if bits == 32 {
        raw.chunks_exact(4).flat_map(|c| (f32::from(c[0] as i8) / 50.0 + f32::from(c[1]) / 65_536.0).to_le_bytes()).collect()
    } else {
        raw.chunks_exact(4).flat_map(|c| (f64::from(c[0] as i8) / 50.0 + f64::from(c[1]) / 65_536.0).to_le_bytes()).collect()
    };
    riff(b"WAVE", &[(b"fmt ", &fmt(3, 2, 48_000, bits, bits / 4, None)), (b"data", &data)])
}

#[test]
fn every_wav_reads_as_the_c_reads_it() {
    let mut cases: Vec<(String, Vec<u8>)> = vec![
        ("8-bit mono".into(), wav(1, 1, 8, 8, 1001, 1)),
        ("8-bit stereo".into(), wav(1, 2, 8, 8, 1000, 2)),
        ("16-bit mono".into(), wav(1, 1, 16, 16, 777, 3)),
        ("16-bit stereo".into(), wav(1, 2, 16, 16, 5000, 4)),
        ("16-bit, six channels".into(), wav(1, 6, 16, 16, 900, 5)),
        ("24-bit stereo".into(), wav(1, 2, 24, 24, 3000, 6)),
        ("32-bit stereo".into(), wav(1, 2, 32, 32, 3000, 7)),
        ("12 bits in 16".into(), wav(1, 2, 12, 16, 3000, 8)),
        ("no frames".into(), wav(1, 2, 16, 16, 0, 1)),
        ("a-law".into(), wav(6, 2, 8, 8, 2000, 9)),
        ("mu-law".into(), wav(7, 2, 8, 8, 2000, 10)),
        ("32-bit floats".into(), float_wav(32, 2000)),
        ("64-bit floats".into(), float_wav(64, 2000)),
    ];
    for (bits, valid, mask) in [(16, 16, 0x3), (24, 24, 0x3), (24, 20, 0x3), (32, 32, 0x3F)] {
        let channels = if mask == 0x3F { 6 } else { 2 };
        let align = channels * bits / 8;
        let format = fmt(1, channels, 96_000, bits, align, Some((valid, mask)));
        let data = noise(1500 * usize::from(align), u32::from(valid));
        cases.push((format!("extensible, {valid} of {bits} bits"), riff(b"WAVE", &[(b"fmt ", &format), (b"data", &data)])));
    }
    // A-law and μ-law as most writers write them, the size of the format's
    // extension said — read by symphonia, where the two above are not.
    for (what, tag) in [("a-law, its extension said", 6), ("mu-law, its extension said", 7)] {
        let mut format = fmt(tag, 2, 8_000, 8, 2, None);
        format.extend_from_slice(&0u16.to_le_bytes());
        let data = noise(4000, u32::from(tag));
        cases.push((what.into(), riff(b"WAVE", &[(b"fmt ", &format), (b"data", &data)])));
    }
    // A chunk of something else first, an odd one, padded.
    let data = noise(4000, 11);
    let format = fmt(1, 2, 44_100, 16, 4, None);
    cases.push(("junk before fmt".into(), riff(b"WAVE", &[(b"JUNK", &[1, 2, 3]), (b"fmt ", &format), (b"data", &data)])));
    cases.push(("a list after the data".into(), riff(b"WAVE", &[(b"fmt ", &format), (b"data", &data), (b"LIST", b"INFOisft")])));
    // Cut short: the data chunk says more than the file holds.
    let mut cut = wav(1, 2, 16, 16, 2000, 12);
    cut.truncate(cut.len() - 1001);
    cases.push(("cut short".into(), cut));

    for (what, bytes) in &cases {
        let file = TempFile::new("wav.wav", bytes);
        expect_same(what, &Span::whole(file.path()), 0, -1);
        let (carried, offset) = between_junk("carried.wav", bytes);
        let span = Span { path: carried.path(), offset, length: bytes.len() as i64, framed: false };
        expect_same(&format!("{what}, carried"), &span, 0, -1);
    }
}

/// The same sound as an RF64, a Wave64 and a RIFX — the WAVs symphonia does
/// not open (`wav_family`).
fn families(tag: u16, channels: u16, bits: u16, frames: usize) -> [(&'static str, Vec<u8>); 3] {
    let align = channels * bits / 8;
    let data = noise(frames * usize::from(align), u32::from(bits) + 40);
    families_of(&fmt(tag, channels, 44_100, bits, align, None), &data, false)
}

/// `data` of `format` as an RF64, a Wave64 and a RIFX, with a chunk of
/// something else first when `junk` — one whose size is odd, and no
/// multiple of eight, so that each family's padding is what finds the next
/// — and a list after the data, which is no sound.
fn families_of(format: &[u8], data: &[u8], junk: bool) -> [(&'static str, Vec<u8>); 3] {
    let other: &[u8] = &[1, 2, 3, 4, 5];
    let mut chunks: Vec<(&[u8; 4], &[u8])> = if junk { vec![(b"JUNK", other)] } else { Vec::new() };
    chunks.extend([(b"fmt ", format), (b"data", data), (b"LIST", b"INFOisft")]);

    let mut ds64 = Vec::new();
    ds64.extend_from_slice(&0u64.to_le_bytes());
    ds64.extend_from_slice(&(data.len() as u64).to_le_bytes());
    ds64.extend_from_slice(&0u64.to_le_bytes());
    ds64.extend_from_slice(&0u32.to_le_bytes());
    let mut rf64 = riff(b"WAVE", &[&[(b"ds64", &ds64[..])], &chunks[..]].concat());
    rf64[..8].copy_from_slice(b"RF64\xFF\xFF\xFF\xFF");
    // The data chunk says all ones, and its size is in the ds64.
    let data_size_at = rf64.windows(4).position(|name| name == b"data").expect("a data chunk") + 4;
    rf64[data_size_at..data_size_at + 4].copy_from_slice(&[0xFF; 4]);

    let guid = |name: &[u8; 4]| {
        let mut guid = name.to_vec();
        guid.extend_from_slice(b"\xF3\xAC\xD3\x11\x8C\xD1\x00\xC0\x4F\x8E\xDB\x8A");
        guid
    };
    let mut w64 = b"riff\x2E\x91\xCF\x11\xA5\xD6\x28\xDB\x04\xC1\x00\x00".to_vec();
    w64.extend_from_slice(&0u64.to_le_bytes());
    w64.extend(guid(b"wave"));
    for &(name, body) in &chunks {
        w64.extend(guid(name));
        w64.extend_from_slice(&(body.len() as u64 + 24).to_le_bytes());
        w64.extend_from_slice(body);
        w64.resize(w64.len().next_multiple_of(8), 0);
    }
    let size = w64.len() as u64;
    w64[16..24].copy_from_slice(&size.to_le_bytes());

    // A RIFX: the same chunks, every number in them big-endian.
    let mut format_be = Vec::new();
    for (at, bytes) in [(0, 2), (2, 2), (4, 4), (8, 4), (12, 2), (14, 2)] {
        format_be.extend(format[at..at + bytes].iter().rev());
    }
    let mut chunks_be = chunks.clone();
    chunks_be[usize::from(junk)].1 = &format_be;
    let mut rifx = riff(b"WAVE", &chunks_be);
    rifx[..4].copy_from_slice(b"RIFX");
    let mut at = 4;
    while at + 4 <= rifx.len() {
        let size = u32::from_le_bytes(rifx[at..at + 4].try_into().expect("4"));
        rifx[at..at + 4].copy_from_slice(&size.to_be_bytes());
        at = if at == 4 { 16 } else { at + 8 + (size + size % 2) as usize };
    }
    [("RF64", rf64), ("Wave64", w64), ("RIFX", rifx)]
}

#[test]
fn the_wavs_symphonia_does_not_open_read_as_the_c_reads_them() {
    for (what, tag, channels, bits) in
        [("8-bit", 1, 2, 8), ("16-bit", 1, 2, 16), ("24-bit", 1, 1, 24), ("32-bit", 1, 2, 32), ("floats", 3, 2, 32)]
    {
        for (family, bytes) in families(tag, channels, bits, 3001) {
            let (carried, offset) = between_junk("family.wav", &bytes);
            let span = Span { path: carried.path(), offset, length: bytes.len() as i64, framed: false };
            let decoded = expect_same(&format!("{family}, {what}"), &span, 0, -1);
            assert_eq!(decoded.samples.len(), 3001 * usize::from(channels), "{family}, {what}: every frame");
        }
    }
    let data = noise(2000 * 6, 61);
    for (what, format) in [
        ("a chunk of something else first", fmt(1, 2, 44_100, 16, 4, None)),
        // dr_wav's frame is the bits' bytes where they are whole, not the
        // block's.
        ("16 bits in a block of 6", fmt(1, 2, 44_100, 16, 6, None)),
        ("12 bits in 16", fmt(1, 2, 44_100, 12, 4, None)),
        ("a-law", fmt(6, 2, 8_000, 8, 2, None)),
        ("mu-law", fmt(7, 2, 8_000, 8, 2, None)),
        ("extensible", fmt(1, 2, 44_100, 24, 6, Some((24, 3)))),
    ] {
        let junk = what.starts_with("a chunk");
        let files = families_of(&format, &data, junk);
        for (family, bytes) in &files {
            // A RIFX's extension would be big-endian too, and the RIFX
            // here turns only the first sixteen bytes.
            if *family == "RIFX" && what == "extensible" {
                continue;
            }
            let file = TempFile::new("family.wav", bytes);
            let span = Span::whole(file.path());
            // ⚠️dr_wav pads a Wave64 chunk by its size mod 8, where the
            // format puts each chunk on the next eight-byte bound: past a
            // chunk of odd size it found nothing (measured 2026-11-06),
            // and this reads on — the same sound the RF64 holds.
            if *family == "Wave64" && junk {
                let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
                assert_ne!(c.format, crate::FORMAT_WAV, "the C's {family}, {what}");
                let file = TempFile::new("family.wav", &files[0].1);
                let rf64 = expect_same("RF64, the same", &Span::whole(file.path()), 0, -1);
                assert!(rust.samples.iter().map(|s| s.to_bits()).eq(rf64.samples.iter().map(|s| s.to_bits())));
                continue;
            }
            let decoded = expect_same(&format!("{family}, {what}"), &span, 0, -1);
            assert_eq!(decoded.format, crate::FORMAT_WAV, "{family}, {what}");
        }
    }
}

#[test]
fn a_framed_wav_reads_as_the_c_reads_it() {
    let bytes = wav(1, 2, 16, 16, 40_000, 13);
    let blob = framed(&bytes, 4096);
    let (carried, offset) = between_junk("framed.bin", &blob);
    let span = Span { path: carried.path(), offset, length: blob.len() as i64, framed: true };
    expect_same("framed", &span, 0, -1);
    expect_same("framed, a window", &span, 12_345, 999);
}

/// An AIFF (or AIFC, when `compression` is said) of 16-bit-word fields,
/// big-endian, with an 80-bit rate.
fn aiff(compression: Option<&[u8; 4]>, channels: u16, bits: u16, frames: u32, data: &[u8]) -> Vec<u8> {
    let mut comm = Vec::new();
    comm.extend_from_slice(&channels.to_be_bytes());
    comm.extend_from_slice(&frames.to_be_bytes());
    comm.extend_from_slice(&bits.to_be_bytes());
    // 44,100 as an 80-bit extended float.
    comm.extend_from_slice(&[0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]);
    if let Some(compression) = compression {
        comm.extend_from_slice(compression);
        comm.extend_from_slice(&[0, 0]);
    }
    let mut ssnd = vec![0u8; 8];
    ssnd.extend_from_slice(data);
    let mut body = if compression.is_some() { b"AIFC".to_vec() } else { b"AIFF".to_vec() };
    for (id, chunk) in [(b"COMM", &comm), (b"SSND", &ssnd)] {
        body.extend_from_slice(id);
        body.extend_from_slice(&(chunk.len() as u32).to_be_bytes());
        body.extend_from_slice(chunk);
        if chunk.len() % 2 == 1 {
            body.push(0);
        }
    }
    let mut bytes = b"FORM".to_vec();
    bytes.extend_from_slice(&(body.len() as u32).to_be_bytes());
    bytes.extend(body);
    bytes
}

#[test]
fn every_aiff_reads_as_the_c_reads_it() {
    for (what, compression, channels, bits) in [
        ("8-bit", None, 2, 8),
        ("16-bit", None, 2, 16),
        ("24-bit", None, 1, 24),
        ("32-bit", None, 2, 32),
        ("AIFC, little-endian", Some(b"sowt"), 2, 16),
        ("AIFC, uncompressed", Some(b"NONE"), 2, 16),
    ] {
        let frames = 1500;
        let data = noise(frames * usize::from(channels * bits / 8), u32::from(bits));
        let bytes = aiff(compression, channels, bits, frames as u32, &data);
        let file = TempFile::new("aiff.aif", &bytes);
        expect_same(what, &Span::whole(file.path()), 0, -1);
    }
}

/// `count` MPEG-1 Layer III frames of silence — a header and zeros, no side
/// information, so every granule decodes to silence (the C's own test):
/// 128 kbit/s at 44.1 kHz.
fn mp3_frames(count: usize) -> Vec<u8> {
    mp3_frames_at(count, 0x90, 417)
}

/// The same at another bitrate: the header's third byte, and the frame's
/// bytes at it.
fn mp3_frames_at(count: usize, rate_byte: u8, frame_bytes: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; count * frame_bytes];
    for frame in bytes.chunks_exact_mut(frame_bytes) {
        frame[..3].copy_from_slice(&[0xFF, 0xFB, rate_byte]);
    }
    bytes
}

/// The same frames, the first made the tag LAME writes: `Info` after the
/// side information, then the LAME extension, whose bytes 21-23 carry the
/// encoder delay (576) and the padding with the decoder's 529 added.
fn tagged_mp3_frames(count: usize, frames_said: Option<u32>, padding: u16) -> Vec<u8> {
    let mut bytes = mp3_frames(count);
    let tag = 4 + 32;
    bytes[tag..tag + 4].copy_from_slice(b"Info");
    let mut at = tag + 8;
    if let Some(frames) = frames_said {
        bytes[tag + 7] = 1;
        bytes[at..at + 4].copy_from_slice(&frames.to_be_bytes());
        at += 4;
    }
    bytes[at..at + 9].copy_from_slice(b"LAME3.100");
    let padding = padding + 529;
    bytes[at + 21] = (576 >> 4) as u8;
    bytes[at + 22] = ((576 & 0x0F) << 4) as u8 | (padding >> 8) as u8;
    bytes[at + 23] = padding as u8;
    bytes
}

#[test]
fn an_mp3_starts_and_ends_where_the_c_s_does() {
    let id3 = |body: Vec<u8>| {
        let mut tagged = b"ID3\x04\x00\x00\x00\x00\x02\x01".to_vec();
        tagged.extend(vec![0u8; 257]);
        tagged.extend(body);
        tagged
    };
    for (what, bytes) in [
        ("no tag", mp3_frames(24)),
        // 320 kbit/s first, then 128: a length guessed from the first
        // frame's bitrate would cut the sound short.
        ("no tag, two bitrates", [mp3_frames_at(20, 0xE0, 1044), mp3_frames(4)].concat()),
        ("a LAME tag", tagged_mp3_frames(24, None, 0)),
        ("a LAME tag counting the frames", tagged_mp3_frames(24, Some(23), 0)),
        ("a LAME tag with padding", tagged_mp3_frames(24, Some(23), 700)),
        ("a count short of the frames", tagged_mp3_frames(24, Some(10), 100)),
        ("behind an ID3 tag", id3(tagged_mp3_frames(24, Some(23), 0))),
        ("behind an ID3 tag with a footer", [super::id3(100, true), tagged_mp3_frames(24, Some(23), 0)].concat()),
    ] {
        let file = TempFile::new("mp3.mp3", &bytes);
        let span = Span::whole(file.path());
        let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
        assert_eq!((rust.format, rust.channels, rust.rate), (c.format, c.channels, c.rate), "{what}");
        assert_eq!(rust.samples.len(), c.samples.len(), "{what}: the frames");
        assert!(rust.samples.iter().all(|&s| s == 0.0), "{what}: silence");
    }
}

/// `count` MPEG-1 Layer III frames, 128 kbit/s at 44.1 kHz, of one channel
/// for each of `gains` — each granule of each channel one spectral line, at
/// that channel's global gain, so that they sound and two channels differ.
/// Stereo is plain stereo (not joint), and each frame's main data starts in
/// it: a frame decodes alone.
fn tone_frames(count: usize, gains: &[u32]) -> Vec<u8> {
    tone_frames_at(count, gains, 0x90, 417)
}

/// The same at another rate: the header's third byte, and the frame's bytes
/// at it.
fn tone_frames_at(count: usize, gains: &[u32], rate_byte: u8, frame_bytes: usize) -> Vec<u8> {
    let channels = gains.len();
    let mut bits = Bits::default();
    bits.put(0, 9); // main_data_begin
    bits.put(0, if channels == 1 { 5 } else { 3 }); // private bits
    bits.put(0, 4 * channels as u32); // scfsi
    for _granule in 0..2 {
        for &gain in gains {
            // part2_3_length: three bits of Huffman code; one pair of big
            // values; table 1 for the first region; long blocks.
            bits.put(3, 12);
            bits.put(1, 9);
            bits.put(gain, 8);
            bits.put(0, 4 + 1);
            bits.put(1, 5);
            bits.put(0, 5 + 5 + 4 + 3 + 3);
        }
    }
    // Table 1's code for the pair (1, 0) — `01` — and the 1's sign, +.
    for _ in 0..2 * channels {
        bits.put(0b010, 3);
    }
    let body = bits.bytes();
    let mut frame = vec![0u8; frame_bytes];
    frame[..4].copy_from_slice(&[0xFF, 0xFB, rate_byte, if channels == 1 { 0xC0 } else { 0x00 }]);
    frame[4..4 + body.len()].copy_from_slice(&body);
    frame.repeat(count)
}

/// Bits written from the top of each byte down.
#[derive(Default)]
struct Bits {
    bits: Vec<bool>,
}

impl Bits {
    fn put(&mut self, value: u32, count: u32) {
        self.bits.extend((0..count).rev().map(|k| value >> k & 1 == 1));
    }

    fn bytes(&self) -> Vec<u8> {
        let byte = |bits: &[bool]| bits.iter().enumerate().fold(0, |b, (k, &on)| b | u8::from(on) << (7 - k));
        self.bits.chunks(8).map(byte).collect()
    }
}

/// The interleaved samples a whole MP3 of `bytes` reads as, and its
/// channels.
fn mp3_read(bytes: &[u8]) -> (Vec<f32>, i32) {
    let file = TempFile::new("pieces.mp3", bytes);
    let read = rust_window(&Span::whole(file.path()), 0, -1);
    assert_eq!(read.format, crate::FORMAT_MP3);
    (read.samples, read.channels)
}

/// The frames of the standard lead that every sound here loses at its
/// start (`start::MP3_STANDARD_LEAD`).
const LEAD: usize = 1105;

#[test]
fn a_mono_piece_of_a_stereo_mp3_is_heard_in_both_at_0_707() {
    // Twelve stereo frames of silence, four mono frames that sound, eight
    // of silence again: the four are read by a decoder of their own, in
    // their place, at 1/√2 in both channels (native-to-rust-Q8 · Q12).
    let piece = tone_frames(4, &[230]);
    let (alone, _) = mp3_read(&piece);
    assert!(alone.iter().any(|&s| s != 0.0), "the piece sounds");
    let (read, channels) = mp3_read(&[mp3_frames(12), piece, mp3_frames(8)].concat());
    assert_eq!(channels, 2);
    assert_eq!(read.len(), (24 * 1152 - LEAD) * 2, "every frame in its place");
    // The piece's frame j stands at 12 · 1152 + j, less the lead; read
    // alone, its first frames are the lead.
    let at = 12 * 1152 - LEAD;
    for (j, &sample) in alone.iter().enumerate() {
        let frame = at + LEAD + j;
        let both = [read[2 * frame], read[2 * frame + 1]];
        assert_eq!(both, [std::f32::consts::FRAC_1_SQRT_2 * sample; 2], "frame {j} of the piece");
    }
    assert!(read[..2 * at].iter().chain(&read[2 * (at + 4 * 1152)..]).all(|&s| s == 0.0), "silence around it");
}

/// `count` MPEG-1 Layer III frames of silence of one channel.
fn mono_mp3_frames(count: usize) -> Vec<u8> {
    let mut frames = mp3_frames(count);
    frames.chunks_exact_mut(417).for_each(|frame| frame[3] = 0xC0);
    frames
}

#[test]
fn a_mono_mp3_with_a_stereo_piece_opens_as_stereo() {
    // The other way: four mono frames that sound, four stereo frames that
    // sound — their two channels apart — and sixteen mono of silence. The
    // sound opens with two channels, as an editor puts each piece in its
    // project's: the stereo piece as it is, the mono at 1/√2 in both
    // (native-to-rust-Q13 · Q12).
    let (mono, stereo) = (tone_frames(4, &[230]), tone_frames(4, &[230, 222]));
    let (mono_alone, _) = mp3_read(&mono);
    let (stereo_alone, two) = mp3_read(&stereo);
    assert_eq!(two, 2);
    assert!(stereo_alone.chunks_exact(2).any(|lr| lr[0] != lr[1]), "the channels differ");
    let (read, channels) = mp3_read(&[mono, stereo, mono_mp3_frames(16)].concat());
    assert_eq!(channels, 2);
    assert_eq!(read.len(), (24 * 1152 - LEAD) * 2, "every frame in its place");
    // The mono piece opens the sound, its lead off as when it is alone.
    for (k, &sample) in mono_alone.iter().enumerate() {
        assert_eq!([read[2 * k], read[2 * k + 1]], [std::f32::consts::FRAC_1_SQRT_2 * sample; 2], "mono frame {k}");
    }
    let at = 4 * 1152 - LEAD;
    for (j, lr) in stereo_alone.chunks_exact(2).enumerate() {
        let frame = at + LEAD + j;
        assert_eq!([read[2 * frame], read[2 * frame + 1]], [lr[0], lr[1]], "stereo frame {j}");
    }
    assert!(read[2 * (at + 4 * 1152)..].iter().all(|&s| s == 0.0), "silence after them");
}

#[test]
fn a_mono_mp3_stays_mono() {
    // No stereo frame anywhere: one channel, as its frames say — the look to
    // the end widens only a sound that turns stereo.
    let (read, channels) = mp3_read(&[tone_frames(4, &[230]), mono_mp3_frames(20)].concat());
    assert_eq!(channels, 1);
    assert_eq!(read.len(), 24 * 1152 - LEAD);
}

#[test]
fn a_piece_lasts_its_time_at_the_stream_s_rate() {
    use crate::bundled::frames_lasting;
    use symphonia::core::units::TimeBase;
    // An MP3's track counts frames; a movie's counts its own ticks — an AAC
    // frame of 1,024 at 48 kHz is 1,920 of a 90 kHz track.
    assert_eq!(frames_lasting(1152, TimeBase::try_new(1, 44_100), 44_100), 1152);
    assert_eq!(frames_lasting(1920, TimeBase::try_new(1, 90_000), 48_000), 1024);
    assert_eq!(frames_lasting(1, TimeBase::try_new(1001, 24_000), 48_000), 2002);
    assert_eq!(frames_lasting(777, None, 48_000), 777);
}

type Resample = unsafe extern "C" fn(*const f32, i64, i32, i32, i32, f64, f64, *mut f32) -> i64;
type ResampleFrames = extern "C" fn(i64, i32, i32) -> i64;

/// Interleaved `samples` of `channels` at `from` as the C conforms a whole
/// sound to `to`.
fn c_conformed(samples: &[f32], channels: usize, from: i32, to: i32) -> Vec<f32> {
    // SAFETY: each type above is its export's C declaration in qa_engine.c.
    let (frames_of, resample) = unsafe {
        (oracle::export::<ResampleFrames>("qa_audio_resample_frames"), oracle::export::<Resample>("qa_audio_resample"))
    };
    let frames = (samples.len() / channels) as i64;
    let mut out = vec![0.0; frames_of(frames, from, to) as usize * channels];
    // SAFETY: `out` holds the frames qa_audio_resample_frames answers.
    let (stopband, bandwidth) = (audio_mix::DEFAULT_STOPBAND_DB, audio_mix::DEFAULT_BANDWIDTH);
    let written = unsafe { resample(samples.as_ptr(), frames, channels as i32, from, to, stopband, bandwidth, out.as_mut_ptr()) };
    out.truncate(written as usize * channels);
    out
}

/// A piece of MPEG frames as a decoder reads it from its first frame on —
/// read alone, with the lead that takes put back: the piece opens with
/// frames of silence enough for it.
fn decoded(piece: &[u8]) -> Vec<f32> {
    let (alone, channels) = mp3_read(piece);
    [vec![0.0; LEAD * channels as usize], alone].concat()
}

/// Two frames of silence, then four that sound — a channel for each of
/// `gains` — at the rate of a header's third byte.
fn piece_at(rate_byte: u8, frame_bytes: usize, gains: &[u32]) -> Vec<u8> {
    let mut silence = tone_frames_at(2, gains, rate_byte, frame_bytes);
    silence.chunks_exact_mut(frame_bytes).for_each(|frame| frame[4..].fill(0));
    [silence, tone_frames_at(4, gains, rate_byte, frame_bytes)].concat()
}

#[test]
fn a_piece_at_another_rate_is_heard_at_the_stream_s() {
    // Six frames at 48 kHz (384 bytes at 128 kbit/s) amid a 44.1 kHz sound,
    // and six at 32 kHz (576) at its end: each read by a decoder of its own
    // and put in the sound's rate as the C conforms a whole sound — what a
    // conversion fed piece by piece writes, bit for bit — and the sound's
    // frames after it keep their place (native-to-rust-Q11).
    for (what, rate, piece, after) in [
        ("amid it", 48_000, piece_at(0x94, 384, &[230, 222]), 8),
        ("at its end", 32_000, piece_at(0x98, 576, &[230, 222]), 0),
    ] {
        let conformed = c_conformed(&decoded(&piece), 2, rate, 44_100);
        assert!(conformed.chunks_exact(2).any(|lr| lr[0] != lr[1]), "{what}: the channels differ");
        let (read, channels) = mp3_read(&[mp3_frames(12), piece, mp3_frames(after)].concat());
        assert_eq!(channels, 2);
        let at = 12 * 1152 - LEAD;
        assert_eq!(read.len(), 2 * at + conformed.len() + 2 * after * 1152, "{what}: every frame in its place");
        assert_eq!(read[2 * at..2 * at + conformed.len()], conformed, "{what}: the piece");
        assert!(read[..2 * at].iter().chain(&read[2 * at + conformed.len()..]).all(|&s| s == 0.0), "{what}: around it");
    }
}

#[test]
fn a_piece_at_a_third_rate_ends_the_run_before_it() {
    // 48 kHz, then 32 kHz of one channel, then the sound's 44.1 kHz: the
    // first run is converted to its end where the second starts, and the
    // second's one channel is in both at 1/√2 before it is converted
    // (native-to-rust-Q11 · Q12).
    let (first, second) = (piece_at(0x94, 384, &[230, 222]), piece_at(0x98, 576, &[230]));
    let widened: Vec<f32> = decoded(&second).iter().flat_map(|&s| [std::f32::consts::FRAC_1_SQRT_2 * s; 2]).collect();
    let conformed = [c_conformed(&decoded(&first), 2, 48_000, 44_100), c_conformed(&widened, 2, 32_000, 44_100)].concat();
    let (read, channels) = mp3_read(&[mp3_frames(12), first, second, mp3_frames(8)].concat());
    assert_eq!(channels, 2);
    let at = 12 * 1152 - LEAD;
    assert_eq!(read.len(), 2 * at + conformed.len() + 2 * 8 * 1152, "every frame in its place");
    assert_eq!(read[2 * at..2 * at + conformed.len()], conformed, "the two runs");
}

#[test]
fn a_run_hands_back_what_is_ready_as_its_pieces_come() {
    // 22.05 kHz to 44.1 kHz: each piece of 576 frames makes 1,152 once the
    // filter has what it reads. A block that kept a piece's size would hand
    // back half of them and keep the rest, the run holding more with each
    // piece; handed all that is ready, it holds no more than its filter.
    use crate::bundled::Other;
    let mut other = Other::new(2, 22_050, 44_100).expect("a conversion");
    let mut handed = 0;
    for _ in 0..200 {
        let mut block = vec![0.25; 576 * 2];
        let got = other.feed(&mut block, 576, 2).expect("room for it");
        assert_eq!(block.len(), 2 * got, "the block holds what it hands");
        handed += got;
    }
    assert!(handed > 200 * 1152 - 1152, "all but what the filter still reads: {handed}");
}

#[test]
fn a_piece_nothing_reads_is_its_length_of_silence() {
    // A Layer II frame among Layer III ones: the reader hands it on, and no
    // decoder here reads it — so it keeps its 1,152 frames as silence, and
    // the frames after it keep theirs (native-to-rust-Q8).
    // Layer II's 128 kbit/s is its eighth bitrate, where Layer III's is its
    // ninth: so the frame keeps its 417 bytes.
    let mut frames = [mp3_frames(12), tone_frames(12, &[230, 230])].concat();
    frames[11 * 417 + 1..11 * 417 + 3].copy_from_slice(&[0xFD, 0x80]);
    let (read, channels) = mp3_read(&frames);
    assert_eq!(channels, 2);
    assert_eq!(read.len(), (24 * 1152 - LEAD) * 2, "every frame in its place");
    let (tone, _) = mp3_read(&[mp3_frames(12), tone_frames(12, &[230, 230])].concat());
    assert_eq!(read, tone, "the broken frame was silence where it stands");
}

#[test]
fn a_head_that_names_another_container_keeps_the_mp3_decoder_away() {
    // MPEG frames behind each head the MP3 decoder is kept from: no bundled
    // decoder reads them, where the frames alone read as an MP3.
    for head in [b"RIFF", b"RIFX", b"RF64", b"riff", b"FORM", b"fLaC", b"OggS"] {
        let mut bytes = head.to_vec();
        bytes.extend_from_slice(&[0, 0, 0, 0]);
        bytes.extend(mp3_frames(24));
        let file = TempFile::new("head.bin", &bytes);
        let span = Span::whole(file.path());
        // On Windows Media Foundation finds the frames behind a RIFX.
        expect_left_to_the_os(&String::from_utf8_lossy(head), &span);
    }
}
