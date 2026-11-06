//! 🚨★★★**A MOVIE'S UNCOMPRESSED SOUND IS READ HERE, ON EVERY PLATFORM**
//! (2026-10-16, board mac-reads-no-movie-pcm). AudioToolbox read nothing of
//! the tests' PCM movie on the macOS CI runner (2026-10-15) where Media
//! Foundation reads it to the sample, and a ProRes movie this app exports
//! on a Mac carries its sound as PCM (`qa_video_apple.m`), as editors'
//! reels do. Uncompressed sound needs no codec — it is bytes the movie's
//! sample table lays out — so it is read here, into floats by dr_wav's
//! conversions (what a WAV of the same samples gets), and no OS stack is
//! asked for it. Where it starts is the movie's to say
//! (`start::container_start`).
//!
//! What is read is the layout ffmpeg's movie reader reads (⚠️known from it
//! and from Apple's file format, not from a file of every writer):
//!   - the first sound track, the one its start is read from, and its one
//!     sample description: `twos` · `sowt` (signed, big- and little-endian,
//!     8 to 32 bits), `raw ` (unsigned 8-bit), `in24` · `in32` · `fl32` ·
//!     `fl64` (big-endian unless an `enda` says little), or `lpcm` (a
//!     version-2 description, by its flags);
//!   - a sample is a frame, whatever the size table says its size is (old
//!     QuickTime wrote 1) — so every sample lasts one frame of the media's
//!     clock, or it is not read;
//!   - the chunks in order, each holding the frames its run of the
//!     sample-to-chunk table says, as many as the size table counts.
//!
//! ⛔A movie whose data reference says its sound is in another file is not
//! read: its offsets are that file's, and read here they would be noise.
//! Nor is one whose description names a reference its list does not have.
//!
//! Media Foundation, which read these movies before, reads every shape and
//! layout the C's `qa_audio_range_test.c` builds to the same samples and
//! refuses what it refuses (measured 2026-10-16), but:
//!   - 8-bit sound by a convention of its own (up to 1/128 off what a WAV of
//!     it gives), 32-bit integers a last bit off (2^-23), and a `twos` of 24
//!     bits and an `enda` outside a `wave` as noise;
//!   - a sound to the end of its chunks, past what the size table counts,
//!     and a chunk cut short not at all, where this reads it to its last
//!     whole frame as dr_wav reads a WAV cut short;
//!   - what this reads, it does not: an `in24` in a version-2 description,
//!     and a sound the second of two data references names, this file's;
//!   - what this does not read, it does: samples two frames long, a sound
//!     described two ways, an `lpcm` whose flags say its channels come one
//!     after another (read as interleaved), or 24 bits in 32-bit words, or
//!     two frames a packet, or unsigned 16 bits, and a `raw ` of 16 bits
//!     (read little-endian — ffmpeg reads it big-endian, and Apple's format
//!     says 8 bits).

use crate::FORMAT_MOVIE_PCM;
use crate::container::Container;
use crate::convert::{Interleaved, Kind, Pcm};
use crate::start::{Atom, Start, big_endian, box_at, box_find, first_sound, head_is_a_movie_box};
use crate::stream::{BLOCK_FRAMES, Decode, Opened};

/// A movie's uncompressed sound — its start the movie's to say, once the
/// stream has its rate.
pub(crate) fn open(container: &Container) -> Option<Opened> {
    let (movie, channels, sample_rate) = MoviePcm::open(container)?;
    Some(Opened { decoder: Box::new(movie), format: FORMAT_MOVIE_PCM, channels, sample_rate, start: Start::default() })
}

/// One table of a movie's sample table, read a batch of entries at a time:
/// the span keeps one block (`media::span`), so a movie kept FRAMED would
/// decode the block its table is in again for every chunk of sound.
struct Table {
    /// The first entry, how many there are, and how wide each is.
    at: i64,
    count: u32,
    entry_bytes: u32,
    /// The entries read last: `batch_count` of them from `batch_first`.
    batch_first: u32,
    batch_count: u32,
    batch: [u8; 4096],
}

impl Table {
    /// The table `atom` holds — its version and flags, a count, and then
    /// `entry_bytes` an entry — or None when its entries do not fit in it.
    fn open(container: &Container, atom: &Atom, entry_bytes: u32) -> Option<Table> {
        let mut head = [0u8; 8];
        if atom.end - atom.body < 8 || !container.read_all_at(atom.body, &mut head) {
            return None;
        }
        let at = atom.body + 8;
        let count = big_endian(&head[4..]) as u32;
        (i64::from(count) * i64::from(entry_bytes) <= atom.end - at).then_some(Table {
            at,
            count,
            entry_bytes,
            batch_first: 0,
            batch_count: 0,
            batch: [0; 4096],
        })
    }

    /// Entry `index`'s bytes, or None when it is not there or would not
    /// read.
    fn entry(&mut self, container: &Container, index: u32) -> Option<&[u8]> {
        if index >= self.count {
            return None;
        }
        if index < self.batch_first || index - self.batch_first >= self.batch_count {
            let fit = self.batch.len() as u32 / self.entry_bytes;
            let take = (self.count - index).min(fit);
            let want = (take * self.entry_bytes) as usize;
            self.batch_count = 0;
            if !container.read_all_at(self.at + i64::from(index) * i64::from(self.entry_bytes), &mut self.batch[..want]) {
                return None;
            }
            self.batch_first = index;
            self.batch_count = take;
        }
        let from = ((index - self.batch_first) * self.entry_bytes) as usize;
        Some(&self.batch[from..from + self.entry_bytes as usize])
    }
}

/// What a sample description says: how its samples are stored, its
/// channels and rate, and the data reference it names.
struct Description {
    pcm: Pcm,
    channels: i32,
    rate: i32,
    reference: u32,
}

/// Whether every sample the time table `stts` times lasts one frame at
/// `rate` of a media clock of `scale` — as a sample of uncompressed sound
/// does.
fn samples_are_frames(container: &Container, stts: &Atom, scale: u32, rate: i32) -> bool {
    let Some(mut times) = Table::open(container, stts, 8) else { return false };
    (0..times.count).all(|index| {
        times.entry(container, index).is_some_and(|entry| {
            big_endian(&entry[4..8]).wrapping_mul(rate as u64) == u64::from(scale)
        })
    })
}

/// Whether the extensions of a sample description — `from` to `end` — say
/// its samples are little-endian: an `enda` of 1, the description's own or
/// in its `wave`.
fn says_little(container: &Container, from: i64, end: i64) -> bool {
    let enda = box_find(container, from, end, b"enda").or_else(|| {
        let wave = box_find(container, from, end, b"wave")?;
        box_find(container, wave.body, wave.end, b"enda")
    });
    let mut value = [0u8; 2];
    enda.is_some_and(|enda| enda.end - enda.body >= 2 && container.read_all_at(enda.body, &mut value) && value[1] == 1)
}

/// How the sample description `entry` says its samples are stored, or None
/// when it is not uncompressed sound this reads.
fn describe(container: &Container, entry: &Atom) -> Option<Description> {
    // Six reserved bytes and the data reference; the description's version,
    // revision and vendor; then its own fields, which version 2 rewrote.
    let mut field = [0u8; 64];
    let have = entry.end - entry.body;
    let want = have.min(64) as usize;
    if have < 28 || !container.read_all_at(entry.body, &mut field[..want]) {
        return None;
    }
    let reference = big_endian(&field[6..8]) as u32;
    let version = big_endian(&field[8..10]);
    let (channels, rate, bits, flags, extensions) = if version == 2 && have >= 64 {
        let hertz = f64::from_bits(big_endian(&field[32..40]));
        let count = big_endian(&field[40..44]) as u32;
        // ⚠️No more channels than a version-0 description can say: the count
        // is 32 bits here, and a broken one would size every block.
        if !(1.0..=2_147_483_647.0).contains(&hertz) || count == 0 || count > 65535 {
            return None;
        }
        let bits = big_endian(&field[48..52]) as u32;
        let flags = big_endian(&field[52..56]) as u32;
        (count as i32, (hertz + 0.5) as i32, bits, flags, entry.body + 64)
    } else if version == 0 || (version == 1 && have >= 44) {
        let channels = big_endian(&field[16..18]) as i32;
        let bits = big_endian(&field[18..20]) as u32;
        let rate = (big_endian(&field[24..28]) >> 16) as i32;
        if channels == 0 || rate == 0 {
            return None;
        }
        (channels, rate, bits, 0, entry.body + if version == 1 { 44 } else { 28 })
    } else {
        return None;
    };

    // The formats a description names: how each stores a sample — its bytes
    // (0: the description's bits say), and its byte order (None: big unless
    // an `enda` says little).
    let formats: [(&[u8; 4], Kind, usize, Option<bool>); 7] = [
        (b"twos", Kind::Signed, 0, Some(true)),
        (b"sowt", Kind::Signed, 0, Some(false)),
        (b"raw ", Kind::Unsigned, 1, Some(false)),
        (b"in24", Kind::Signed, 3, None),
        (b"in32", Kind::Signed, 4, None),
        (b"fl32", Kind::Float, 4, None),
        (b"fl64", Kind::Float, 8, None),
    ];
    let mut pcm = None;
    if let Some(&(_, kind, bytes, big)) = formats.iter().find(|format| *format.0 == entry.kind) {
        // `raw ` is 8-bit; the others' bits are their names'.
        if (bytes == 1 && bits != 8) || (bytes == 0 && bits % 8 != 0) {
            return None;
        }
        pcm = Some(Pcm {
            kind,
            sample_bytes: if bytes != 0 { bytes } else { (bits / 8) as usize },
            big_endian: big.unwrap_or_else(|| !says_little(container, extensions, entry.end)),
        });
    }
    if &entry.kind == b"lpcm" && version == 2 {
        // Core Audio's flags: float 1, big-endian 2, signed 4, and 32 for one
        // channel after another rather than frames, which this does not
        // read. A packet is one frame of the samples packed, or it is not
        // read: its bytes say both.
        let packet_bytes = big_endian(&field[56..60]);
        if flags & 32 != 0 || bits % 8 != 0 || packet_bytes != channels as u64 * u64::from(bits / 8) {
            return None;
        }
        let kind = if flags & 1 != 0 {
            Kind::Float
        } else if flags & 4 != 0 {
            Kind::Signed
        } else {
            Kind::Unsigned
        };
        pcm = Some(Pcm { kind, sample_bytes: (bits / 8) as usize, big_endian: flags & 2 != 0 });
    }
    let pcm = pcm?;
    pcm.readable().then_some(Description { pcm, channels, rate, reference })
}

/// Whether `minf`'s data reference `index` — counted from 1 — says its
/// samples are in this movie's own file: flag 1, 「self reference」. A movie
/// with no data references at all is read as holding its own sound, and one
/// whose description names a reference its list does not have is not read
/// — as Media Foundation reads both (measured 2026-10-16).
fn holds_its_sound(container: &Container, minf: &Atom, index: u32) -> bool {
    let Some(dref) = box_find(container, minf.body, minf.end, b"dinf")
        .and_then(|dinf| box_find(container, dinf.body, dinf.end, b"dref"))
    else {
        return true;
    };
    let mut at = dref.body + 8;
    let mut number = 1;
    while let Some(entry) = box_at(container, at, dref.end) {
        if number == index {
            let mut flags = [0u8; 4];
            return entry.end - entry.body >= 4 && container.read_all_at(entry.body, &mut flags) && flags[3] & 1 != 0;
        }
        at = entry.end;
        number += 1;
    }
    false
}

/// A movie's uncompressed sound, read through its sample table a chunk at a
/// time.
pub(crate) struct MoviePcm {
    container: Container,
    /// Where each chunk starts (`stco` · `co64`), and the runs of chunks that
    /// hold the same number of frames (`stsc`).
    offsets: Table,
    runs: Table,
    /// The run in force (-1 before the first), its frames per chunk, and the
    /// chunk the next run starts at — counted from 1, as the table counts.
    run: i64,
    run_frames: u32,
    next_run_chunk: u32,
    /// Chunks begun; where the one being read is up to, and its frames left.
    chunks_begun: u32,
    chunk_at: i64,
    chunk_frames: i64,
    /// Frames of the sound left: of the size table's count.
    frames_left: i64,
    samples: Interleaved,
}

impl MoviePcm {
    /// The movie's uncompressed sound, with its channels and rate — None
    /// when `container` is not a movie whose sound this reads.
    pub(crate) fn open(container: &Container) -> Option<(MoviePcm, i32, i32)> {
        if !head_is_a_movie_box(&container.head()) {
            return None;
        }
        let sound = first_sound(container, container.size())?;
        let stbl = sound.stbl;
        // One sample description: a sound stored two ways is not one stream.
        let stsd = box_find(container, stbl.body, stbl.end, b"stsd")?;
        let mut counts = [0u8; 12];
        if stsd.end - stsd.body < 8 || !container.read_all_at(stsd.body, &mut counts[..8]) || big_endian(&counts[4..8]) != 1 {
            return None;
        }
        let entry = box_at(container, stsd.body + 8, stsd.end)?;
        let description = describe(container, &entry)?;
        if !holds_its_sound(container, &sound.minf, description.reference) {
            return None;
        }
        let stts = box_find(container, stbl.body, stbl.end, b"stts")?;
        if !samples_are_frames(container, &stts, sound.media_scale, description.rate) {
            return None;
        }
        let stsz = box_find(container, stbl.body, stbl.end, b"stsz")?;
        if stsz.end - stsz.body < 12 || !container.read_all_at(stsz.body, &mut counts) {
            return None;
        }
        let stsc = box_find(container, stbl.body, stbl.end, b"stsc")?;
        let runs = Table::open(container, &stsc, 12)?;
        let offsets = match box_find(container, stbl.body, stbl.end, b"co64") {
            Some(co64) => Table::open(container, &co64, 8)?,
            None => Table::open(container, &box_find(container, stbl.body, stbl.end, b"stco")?, 4)?,
        };
        let Description { pcm, channels, rate, .. } = description;
        let movie = MoviePcm {
            container: container.clone(),
            offsets,
            runs,
            run: -1,
            run_frames: 0,
            next_run_chunk: 0,
            chunks_begun: 0,
            chunk_at: 0,
            chunk_frames: 0,
            // The size table's count is the sound's frames; its sizes are not
            // read.
            frames_left: big_endian(&counts[8..12]) as i64,
            samples: Interleaved::new(pcm, channels as usize, BLOCK_FRAMES),
        };
        Some((movie, channels, rate))
    }

    /// Begins the next chunk: false when there is none, or its table would
    /// not read.
    fn next_chunk(&mut self) -> bool {
        if self.chunks_begun >= self.offsets.count {
            return false;
        }
        let number = self.chunks_begun + 1;
        while number >= self.next_run_chunk {
            self.run += 1;
            let Some(run) = self.runs.entry(&self.container, self.run as u32) else { return false };
            self.run_frames = big_endian(&run[4..8]) as u32;
            self.next_run_chunk = u32::MAX;
            if (self.run as u32).wrapping_add(1) < self.runs.count {
                let Some(next) = self.runs.entry(&self.container, self.run as u32 + 1) else { return false };
                self.next_run_chunk = big_endian(&next[..4]) as u32;
            }
        }
        let Some(offset) = self.offsets.entry(&self.container, self.chunks_begun) else { return false };
        let Ok(at) = i64::try_from(big_endian(offset)) else { return false };
        self.chunk_at = at;
        self.chunk_frames = i64::from(self.run_frames);
        self.chunks_begun += 1;
        true
    }
}

impl Decode for MoviePcm {
    fn next(&mut self, block: &mut Vec<f32>) -> usize {
        if self.frames_left == 0 {
            return 0;
        }
        while self.chunk_frames == 0 {
            if !self.next_chunk() {
                return 0;
            }
        }
        let frames = self.chunk_frames.min(self.samples.capacity()).min(self.frames_left);
        let got = self.samples.read(&self.container, self.chunk_at, frames, block);
        if got < frames {
            // A movie cut short ends where its bytes do, as dr_wav ends a WAV.
            self.frames_left = got;
        }
        self.chunk_at += got * self.samples.frame_bytes();
        self.chunk_frames -= got;
        self.frames_left -= got;
        got as usize
    }
}
