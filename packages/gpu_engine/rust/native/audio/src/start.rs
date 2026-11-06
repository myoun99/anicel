//! 🚨★★★**WHERE A SOUND STARTS — SAID ONCE, COUNTED IN ONE PLACE** (user
//! 2026-10-09, board sound-lands-on-its-exact-sample-Q3 · Q4).
//!
//! An encoder puts frames of its own before the sound (priming), and a
//! decoder hands them back unless something takes them off: half a frame of
//! animation late at 48 kHz, more for Apple's encoder. What is taken off is
//! decided here, from the file — a movie's edit list or the note iTunes
//! leaves in it, an MP3's LAME tag — and where the format has no place to
//! say it, from the format's standard delay (an MP3 without the tag: 1,105,
//! LAME's own; AAC's: 1,024, one frame). A decoder that already took some
//! off says how much, and only the rest is taken.
//!
//! A MOVIE THAT SAYS NOTHING — no edit list on its sound track, and no note
//! of iTunes' — takes the standard of its sound's format off too (user
//! 2026-10-09, Q6: 「Q3 그대로 — 말하지 않는 MP4 · MOV 도 1,024 를 걷는다」),
//! unless Media Foundation wrote it (Q7: 「윈도 기록기의 표지가 있으면 걷지
//! 않는다」): its sink writer puts no edit list in and its sound is already
//! in place — this app's own exports, 48 kHz and 44.1 kHz, and the test
//! movie, measured 2026-10-09 — and it marks every movie it writes
//! ([MEDIA_FOUNDATION_MARK]). The mark is the writer's own name for itself,
//! not a guess from the sound.

use crate::container::Container;

/// The standard delays, for a file that does not say its own. An MP3's is
/// LAME's: 576 encoder frames and the decoder's 529. AAC's is one frame — a
/// bare ADTS stream's, and a movie's that says nothing.
pub(crate) const MP3_STANDARD_LEAD: i64 = 1105;
pub(crate) const AAC_STANDARD_LEAD: i64 = 1024;

/// Where a decoded sound starts and how long it runs, in frames of what the
/// decoder hands back.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Start {
    /// Frames before the sound: what the file says, or its format's standard.
    pub(crate) lead: i64,
    /// Of [Start::lead], the frames the decoder already took off itself.
    pub(crate) taken: i64,
    /// Frames of sound after the lead, or -1: everything that came.
    pub(crate) keep: i64,
}

impl Default for Start {
    /// No file a bundled decoder reads puts frames of its own before its
    /// sound but an MP3, whose opener counts its lead.
    fn default() -> Start {
        Start { lead: 0, taken: 0, keep: -1 }
    }
}

pub(crate) fn big_endian(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0, |value, &byte| value << 8 | u64::from(byte))
}

/// A box of an ISO or QuickTime file: its type, where its body starts and
/// one past its end.
#[derive(Clone, Copy)]
pub(crate) struct Atom {
    pub(crate) kind: [u8; 4],
    pub(crate) body: i64,
    pub(crate) end: i64,
}

/// The box at `at`, when a whole one fits before `end`.
///
/// ⛔A size of 0 — 「to the end of the file」, which the format allows the
/// last box — is no box here: Media Foundation refuses a movie whose movie
/// box says it (measured 2026-10-09), so a reading of it would be a branch
/// nothing here can ask, and such a movie keeps what the decoder gave.
pub(crate) fn box_at(container: &Container, at: i64, end: i64) -> Option<Atom> {
    let mut head = [0u8; 16];
    if end - at < 8 || !container.read_all_at(at, &mut head[..8]) {
        return None;
    }
    let mut size = big_endian(&head[..4]);
    let mut header = 8;
    if size == 1 {
        // A 64-bit size follows the type.
        if end - at < 16 || !container.read_all_at(at + 8, &mut head[8..]) {
            return None;
        }
        size = big_endian(&head[8..]);
        header = 16;
    }
    if size < header as u64 || size > (end - at) as u64 {
        return None;
    }
    Some(Atom { kind: head[4..8].try_into().expect("4 bytes"), body: at + header, end: at + size as i64 })
}

/// The first box of `kind` directly inside `[start, end)`.
pub(crate) fn box_find(container: &Container, start: i64, end: i64, kind: &[u8; 4]) -> Option<Atom> {
    let mut at = start;
    while let Some(atom) = box_at(container, at, end) {
        if &atom.kind == kind {
            return Some(atom);
        }
        at = atom.end;
    }
    None
}

/// A movie header's (`mvhd`) or a media header's (`mdhd`) time scale — at
/// the same place in both: after the dates, which version 1 makes 64-bit.
fn time_scale(container: &Container, header: &Atom) -> u32 {
    let mut bytes = [0u8; 24];
    if header.end - header.body < 24 || !container.read_all_at(header.body, &mut bytes) {
        return 0;
    }
    let at = if bytes[0] == 1 { 20 } else { 12 };
    big_endian(&bytes[at..at + 4]) as u32
}

/// `value` ticks at `scale` as frames at `rate`, to the nearest frame.
fn ticks_to_frames(value: i64, scale: u32, rate: i32) -> i64 {
    ((value as f64 * f64::from(rate)) / f64::from(scale) + 0.5) as i64
}

/// Whether `head`'s second word is one of the boxes a QuickTime movie can
/// open with — `ftyp` is the ISO file's first box, and the older movies
/// start with whatever the editor wrote first.
///
/// ⚠️Not the question `qa_apple_container_type` (qa_video_apple.m) answers:
/// that one is handed a movie and names its kind. Two heads read, two
/// questions — a third reader is the time to make them one.
pub(crate) fn head_is_a_movie_box(head: &[u8; 8]) -> bool {
    [b"ftyp", b"moov", b"mdat", b"wide", b"free", b"skip", b"pnot"].iter().any(|kind| head[4..] == kind[..])
}

/// Whether the MP3 decoder may be handed `container`, by its first bytes.
///
/// It is the one decoder in the chain that says yes to anything — its
/// frame-sync scan finds frames in the quiet stretches of uncompressed
/// sound — so a head that names another container keeps it away: a WAV's
/// own first words (`RIFF` · `RIFX` · `RF64` · W64's `riff` · AIFF's
/// `FORM`), FLAC's `fLaC`, ogg's `OggS`, a QuickTime box (MP4 · MOV · M4A ·
/// 3GP). Nothing else is gated: the other decoders recognize their own
/// containers and refuse the rest, and a head nobody knows, an MP3's among
/// them, runs the whole chain.
///
/// ⛔Not a mask of every bundled decoder per head, the user's table written
/// out row by row (「ID3 · MPEG sync → MP3」 and the rest). The rows for the
/// strict decoders would change nothing but one thing, and break it: the
/// FLAC reader skips an ID3 tag, so 「ID3 → MP3 only」 takes a tagged FLAC
/// away from the one decoder that reads it.
pub(crate) fn mp3_may_try(container: &Container) -> bool {
    let head = container.head();
    let others = [b"RIFF", b"RIFX", b"RF64", b"riff", b"FORM", b"fLaC", b"OggS"];
    !others.iter().any(|other| head[..4] == other[..]) && !head_is_a_movie_box(&head)
}

/// Where the bytes after a leading ID3v2 tag start — 0 when there is none.
/// The tag's size is four 7-bit bytes, a footer ten more.
pub(crate) fn past_id3(container: &Container) -> i64 {
    let mut head = [0u8; 10];
    container.read_at(0, &mut head);
    if &head[..3] != b"ID3" {
        return 0;
    }
    let size = head[6..10].iter().fold(0i64, |size, &byte| size << 7 | i64::from(byte & 0x7F));
    10 + size + if head[5] & 0x10 != 0 { 10 } else { 0 }
}

/// A movie's first sound track — the one that answers, whatever it says:
/// its `trak` and `mdia` boxes, the media information and sample table in
/// them (`minf` · `stbl`), the movie's and the media's time scales (0: not
/// said), and the movie box they are in, whose user data iTunes leaves its
/// note in.
pub(crate) struct MovieSound {
    pub(crate) moov: Atom,
    pub(crate) trak: Atom,
    pub(crate) minf: Atom,
    pub(crate) stbl: Atom,
    pub(crate) movie_scale: u32,
    pub(crate) media_scale: u32,
}

/// The first sound track of the `size` bytes of movie, or None when it has
/// none.
pub(crate) fn first_sound(container: &Container, size: i64) -> Option<MovieSound> {
    let moov = box_find(container, 0, size, b"moov")?;
    let mvhd = box_find(container, moov.body, moov.end, b"mvhd")?;
    let mut at = moov.body;
    while let Some(trak) = box_at(container, at, moov.end) {
        at = trak.end;
        let sound = || {
            let mdia = box_find(container, trak.body, trak.end, b"mdia")?;
            let hdlr = box_find(container, mdia.body, mdia.end, b"hdlr")?;
            let mut handler = [0u8; 12];
            if !container.read_all_at(hdlr.body, &mut handler) || &handler[8..] != b"soun" {
                return None;
            }
            let minf = box_find(container, mdia.body, mdia.end, b"minf")?;
            let stbl = box_find(container, minf.body, minf.end, b"stbl")?;
            let media_scale =
                box_find(container, mdia.body, mdia.end, b"mdhd").map_or(0, |mdhd| time_scale(container, &mdhd));
            Some(MovieSound { moov, trak, minf, stbl, movie_scale: time_scale(container, &mvhd), media_scale })
        };
        if &trak.kind == b"trak"
            && let Some(sound) = sound()
        {
            return Some(sound);
        }
    }
    None
}

/// What `sound`'s edit list says, at `rate` — the lead and the keep — or
/// None when it has none.
///
/// The edit that says it is the first that plays media: a leading empty edit
/// (media time -1) holds the track back on the movie's timeline, which is
/// where the sound is PLACED, not where it starts — ⚠️not read here.
fn sound_edit(container: &Container, sound: &MovieSound, rate: i32) -> Option<(i64, i64)> {
    let edts = box_find(container, sound.trak.body, sound.trak.end, b"edts")?;
    let elst = box_find(container, edts.body, edts.end, b"elst")?;
    let mut list = [0u8; 8];
    if sound.movie_scale == 0 || sound.media_scale == 0 || !container.read_all_at(elst.body, &mut list) {
        return None;
    }
    let wide = list[0] == 1;
    let entry_bytes: i64 = if wide { 20 } else { 12 };
    let entries = big_endian(&list[4..]) as u32;
    for index in 0..entries {
        let at = elst.body + 8 + i64::from(index) * entry_bytes;
        let mut entry = [0u8; 20];
        if at + entry_bytes > elst.end || !container.read_all_at(at, &mut entry[..entry_bytes as usize]) {
            return None;
        }
        let (duration, media_time) = if wide {
            (big_endian(&entry[..8]) as i64, big_endian(&entry[8..16]) as i64)
        } else {
            (big_endian(&entry[..4]) as i64, i64::from(big_endian(&entry[4..8]) as u32 as i32))
        };
        if media_time < 0 {
            continue;
        }
        let keep = if duration > 0 { ticks_to_frames(duration, sound.movie_scale, rate) } else { -1 };
        return Some((ticks_to_frames(media_time, sound.media_scale, rate), keep));
    }
    None
}

/// The next word of hexadecimal in `text` from `*at`, past the spaces
/// before it — -1 when none is there.
fn hex_word(text: &[u8], at: &mut usize) -> i64 {
    while *at < text.len() && text[*at] == b' ' {
        *at += 1;
    }
    let mut value: u64 = 0;
    let mut digits = 0;
    while let Some(digit) = text.get(*at).and_then(|&c| char::from(c).to_digit(16)) {
        value = value.wrapping_mul(16).wrapping_add(u64::from(digit));
        *at += 1;
        digits += 1;
    }
    if digits > 0 && digits <= 16 && value <= i64::MAX as u64 { value as i64 } else { -1 }
}

/// What the note iTunes leaves in `sound`'s movie says — the lead and the
/// keep — or None when it left none: an item of the movie's metadata
/// (`udta` · `meta` · `ilst`) named `iTunSMPB`, whose text is words of
/// hexadecimal — 0, the frames before the sound, the frames padded after
/// it, the sound's own length — counted in frames as decoded. iTunes and
/// Apple Music write it, and qaac and fdkaac as they come (⚠️known, not
/// measured here), with no edit list: such a movie took AAC's 1,024 off
/// where Apple's encoder put 2,112 — 1,088 frames early, 25 ms at 44.1 kHz.
///
/// ⚠️Asked only of a sound track without an edit list: the edit list is the
/// format's own place to say it, and the one every player plays by (this
/// engine's choice, 2026-10-15 — board
/// itunes-gapless-note-is-what-an-m4a-says).
fn itunes_note(container: &Container, sound: &MovieSound) -> Option<(i64, i64)> {
    let udta = box_find(container, sound.moov.body, sound.moov.end, b"udta")?;
    let meta = box_find(container, udta.body, udta.end, b"meta")?;
    let mut head = [0u8; 8];
    if !container.read_all_at(meta.body, &mut head) {
        return None;
    }
    // ISO's `meta` has four bytes of version and flags before its boxes and
    // QuickTime's none; either begins with its handler (`hdlr`).
    let boxes = if &head[4..] == b"hdlr" { meta.body } else { meta.body + 4 };
    let ilst = box_find(container, boxes, meta.end, b"ilst")?;
    let mut at = ilst.body;
    while let Some(item) = box_at(container, at, ilst.end) {
        at = item.end;
        // An item of a writer's own (`----`) is the kind with a `name`: it
        // holds that and its `data`, each with four bytes of version and
        // flags first — and `data` four of locale after them, before its
        // text.
        let mut said = [0u8; 8];
        let Some(name) = box_find(container, item.body, item.end, b"name") else { continue };
        if name.end - name.body != 4 + 8 || !container.read_all_at(name.body + 4, &mut said) || &said != b"iTunSMPB" {
            continue;
        }
        let Some(data) = box_find(container, item.body, item.end, b"data") else { continue };
        // The four words take 44 characters of it.
        let from = data.body + 8;
        let length = (data.end - from).min(64);
        let mut text = [0u8; 64];
        if length <= 0 || !container.read_all_at(from, &mut text[..length as usize]) {
            return None;
        }
        let text = &text[..length as usize];
        let mut at_text = 0;
        let mut words = [0i64; 4];
        for word in &mut words {
            *word = hex_word(text, &mut at_text);
            if *word < 0 {
                return None;
            }
        }
        // A length of 0 says none, as an edit's duration of 0 does.
        return Some((words[1], if words[3] > 0 { words[3] } else { -1 }));
    }
    None
}

/// Whether `sound` is MPEG-4 audio — its first sample description `mp4a`:
/// AAC, in every movie an animator hands this app (an MP3 carried that way
/// says so only deeper, in its decoder config, and is not looked for).
fn sound_is_aac(container: &Container, sound: &MovieSound) -> bool {
    let mut head = [0u8; 16];
    box_find(container, sound.stbl.body, sound.stbl.end, b"stsd").is_some_and(|stsd| {
        stsd.end - stsd.body >= 16 && container.read_all_at(stsd.body, &mut head) && &head[12..] == b"mp4a"
    })
}

/// The mark Media Foundation's sink writer leaves on every movie it writes:
/// a `uuid` box of the file's top level — straight after its `ftyp` on
/// every one measured — always this user type, the Windows version after it
/// (`10.0.26200.0` on the measured ones). Measured 2026-10-09 on this app's
/// exports and on the test movie; ffmpeg's movies carry none.
const MEDIA_FOUNDATION_MARK: [u8; 16] =
    [0x5C, 0xA7, 0x08, 0xFB, 0x32, 0x8E, 0x42, 0x05, 0xA8, 0x61, 0x65, 0x0E, 0xCA, 0x0A, 0x95, 0x96];

/// Whether Media Foundation wrote the `size` bytes of movie — by its mark.
fn written_by_media_foundation(container: &Container, size: i64) -> bool {
    let mut at = 0;
    while let Some(atom) = box_at(container, at, size) {
        at = atom.end;
        let mut user_type = [0u8; 16];
        if &atom.kind == b"uuid"
            && atom.end - atom.body >= 16
            && container.read_all_at(atom.body, &mut user_type)
            && user_type == MEDIA_FOUNDATION_MARK
        {
            return true;
        }
    }
    false
}

/// Whether `container` is a bare ADTS stream — AAC with no box to say
/// anything in — by its first frame header, behind an ID3 tag or not.
fn is_adts(container: &Container) -> bool {
    let mut head = [0u8; 2];
    container.read_at(past_id3(container), &mut head);
    // Twelve sync bits, then layer 00: an MPEG audio frame's layer is never
    // 00.
    head[0] == 0xFF && head[1] & 0xF6 == 0xF0
}

/// What the file says about a sound whose decoder does not read it — a
/// movie's, and a bare AAC stream's — into `start`: the decoders that know
/// their own file (the MP3 reader) said it as they opened.
pub(crate) fn container_start(container: &Container, rate: i32, start: &mut Start) {
    if head_is_a_movie_box(&container.head()) {
        // A movie says it in its edit list, or else in iTunes' note; one that
        // says nothing takes its format's standard, unless Media Foundation
        // wrote it (the law at the head of this file).
        let Some(sound) = first_sound(container, container.size()) else { return };
        if let Some((lead, keep)) = sound_edit(container, &sound, rate).or_else(|| itunes_note(container, &sound)) {
            start.lead = lead;
            start.keep = keep;
        } else if !written_by_media_foundation(container, container.size()) && sound_is_aac(container, &sound) {
            start.lead = AAC_STANDARD_LEAD;
        }
    } else if is_adts(container) {
        start.lead = AAC_STANDARD_LEAD;
    }
}
