//! WAVs, AIFFs and MPEG frames made up here, each decoded by both.

use super::{Span, TempFile, between_junk, c_window, expect_same, framed, noise, rust_window};

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
/// multiple of eight, so that each family's padding is what finds the next.
fn families_of(format: &[u8], data: &[u8], junk: bool) -> [(&'static str, Vec<u8>); 3] {
    let other: &[u8] = &[1, 2, 3, 4, 5];
    let mut chunks: Vec<(&[u8; 4], &[u8])> = if junk { vec![(b"JUNK", other)] } else { Vec::new() };
    chunks.extend([(b"fmt ", format), (b"data", data)]);

    let mut ds64 = Vec::new();
    ds64.extend_from_slice(&0u64.to_le_bytes());
    ds64.extend_from_slice(&(data.len() as u64).to_le_bytes());
    ds64.extend_from_slice(&0u64.to_le_bytes());
    ds64.extend_from_slice(&0u32.to_le_bytes());
    let mut rf64 = riff(b"WAVE", &[&[(b"ds64", &ds64[..])], &chunks[..]].concat());
    rf64[..8].copy_from_slice(b"RF64\xFF\xFF\xFF\xFF");
    let data_size_at = rf64.len() - data.len() - data.len() % 2 - 4;
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
/// information, so every granule decodes to silence (the C's own test).
fn mp3_frames(count: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; count * 417];
    for frame in bytes.chunks_exact_mut(417) {
        frame[..3].copy_from_slice(&[0xFF, 0xFB, 0x90]);
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

#[test]
fn a_frame_of_other_channels_is_passed_over() {
    // Twelve stereo frames, four of one channel, eight stereo again.
    // symphonia's decoder refuses a frame of other channels than its
    // stream's, and a packet that does not decode is passed over: twenty
    // frames, less the standard lead. ⚠️The C's dr_mp3 kept the four in
    // their place, as noise — whether they keep it here is the board's
    // (audio-mp3-channel-change).
    let mut mono = mp3_frames(4);
    mono.chunks_exact_mut(417).for_each(|frame| frame[3] = 0xC0);
    let file = TempFile::new("mixed.mp3", &[mp3_frames(12), mono, mp3_frames(8)].concat());
    let rust = rust_window(&Span::whole(file.path()), 0, -1);
    assert_eq!((rust.format, rust.channels), (crate::FORMAT_MP3, 2));
    assert_eq!(rust.samples.len(), (20 * 1152 - 1105) * 2);
}

#[test]
fn a_head_that_names_another_container_keeps_the_mp3_decoder_away() {
    // MPEG frames behind each head the MP3 decoder is kept from: nothing
    // reads them, where the frames alone read as an MP3.
    for head in [b"RIFF", b"RIFX", b"RF64", b"riff", b"FORM", b"fLaC", b"OggS"] {
        let mut bytes = head.to_vec();
        bytes.extend_from_slice(&[0, 0, 0, 0]);
        bytes.extend(mp3_frames(24));
        let file = TempFile::new("head.bin", &bytes);
        let span = Span::whole(file.path());
        let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
        // On Windows Media Foundation finds the frames behind a RIFX: what
        // only the OS stage reads, nothing reads here until it comes.
        let (format, frames) =
            if c.format == crate::FORMAT_OS { (crate::FORMAT_UNKNOWN, 0) } else { (c.format, c.samples.len()) };
        assert_eq!(rust.format, format, "{}", String::from_utf8_lossy(head));
        assert_eq!(rust.samples.len(), frames, "{}", String::from_utf8_lossy(head));
    }
}
