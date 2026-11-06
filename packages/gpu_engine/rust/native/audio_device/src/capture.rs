//! Capture (AUDIO-PRO R5): the guide-voice recorder's device side — a
//! second device beside playback, which is never touched, so recording
//! runs DURING playback (watch the cut, speak the line).
//!
//! The realtime rule holds here too: the callback only copies into a ring
//! made at start. Dart drains it from a control-thread timer; if it falls
//! behind the ring absorbs seconds of it, and a true overflow is COUNTED,
//! never hidden — a take with dropped frames must say so, not play back
//! subtly shorter.

use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicI64, AtomicPtr, AtomicU32, Ordering::SeqCst};

use crate::clock;

/// Seconds of audio the ring holds. Dart drains every few tens of ms:
/// three orders of magnitude of slack.
const RING_SECONDS: i64 = 8;

pub(crate) struct Capture {
    open: AtomicBool,
    channels: AtomicI32,
    sample_rate: AtomicI32,
    /// `capacity` floats — a whole number of frames — written by the
    /// callback, read by the drain: one producer, one consumer, each on
    /// its side of the totals below, so neither ever holds the ring whole.
    ring: AtomicPtr<f32>,
    capacity: AtomicI64,
    /// Totals in floats — never wrapped, so space and data are plain
    /// subtractions. Each written on one side.
    write_total: AtomicI64,
    read_total: AtomicI64,
    dropped_frames: AtomicI64,
    /// THE CAPTURE'S CLOCK LINE (take-head-trims-at-the-playback-start,
    /// 10-15), the playback's own shape: each callback says how many frames
    /// the ring had been given when it returned, and when it was asked for
    /// them — so a take is placed by what the microphone had taken in at
    /// the moment its anchor was HEARD. One writer, read whole through
    /// `clock_seq`; a point with no time (0) is no point.
    clock_seq: AtomicU32,
    clock_frames: AtomicI64,
    clock_time_us: AtomicI64,
}

impl Capture {
    pub(crate) const fn new() -> Capture {
        Capture {
            open: AtomicBool::new(false),
            channels: AtomicI32::new(0),
            sample_rate: AtomicI32::new(0),
            ring: AtomicPtr::new(ptr::null_mut()),
            capacity: AtomicI64::new(0),
            write_total: AtomicI64::new(0),
            read_total: AtomicI64::new(0),
            dropped_frames: AtomicI64::new(0),
            clock_seq: AtomicU32::new(0),
            clock_frames: AtomicI64::new(0),
            clock_time_us: AtomicI64::new(0),
        }
    }

    /// A capture of `channels` at `sample_rate` opens: its ring is made and
    /// nothing is in it. Before the device starts — false, nothing made,
    /// when the memory is not there.
    pub(crate) fn open(&self, channels: i32, sample_rate: i32) -> bool {
        let capacity = i64::from(sample_rate) * i64::from(channels) * RING_SECONDS;
        let mut ring = Vec::new();
        if ring.try_reserve_exact(capacity as usize).is_err() {
            return false;
        }
        ring.resize(capacity as usize, 0.0f32);
        self.channels.store(channels, SeqCst);
        self.sample_rate.store(sample_rate, SeqCst);
        self.capacity.store(capacity, SeqCst);
        self.write_total.store(0, SeqCst);
        self.read_total.store(0, SeqCst);
        self.dropped_frames.store(0, SeqCst);
        // No callback of this capture has spoken: the last one's point is
        // gone.
        self.clock_time_us.store(0, SeqCst);
        self.ring.store(Box::into_raw(ring.into_boxed_slice()).cast::<f32>(), SeqCst);
        // Open BEFORE start: the callback checks the ring, and starting
        // makes it live at once.
        self.open.store(true, SeqCst);
        true
    }

    /// The capture closed — called once its callback can no longer run.
    pub(crate) fn close(&self) {
        self.open.store(false, SeqCst);
        let ring = self.ring.swap(ptr::null_mut(), SeqCst);
        if !ring.is_null() {
            let capacity = self.capacity.load(SeqCst) as usize;
            // SAFETY: made by `open` from a boxed slice of `capacity`, and no
            // callback reads it any more.
            drop(unsafe { Box::from_raw(ptr::slice_from_raw_parts_mut(ring, capacity)) });
        }
    }

    /// The capture callback: `input`, interleaved, into the ring — whole
    /// frames only, the ones with no room counted as dropped.
    pub(crate) fn deliver(&self, input: &[f32]) {
        let asked_at_us = clock::now_us();
        let ring = self.ring.load(SeqCst);
        let channels = i64::from(self.channels.load(SeqCst));
        if ring.is_null() {
            return;
        }
        let capacity = self.capacity.load(SeqCst);
        let frames = input.len() as i64 / channels;
        let mut floats = frames * channels;
        let written = self.write_total.load(SeqCst);
        let read = self.read_total.load(SeqCst);
        let space = capacity - (written - read);
        if floats > space {
            // Whole frames only: a partial frame in the ring would shift
            // every later sample by a channel and turn the take to garbage.
            let keep_frames = space / channels;
            self.dropped_frames.store(self.dropped_frames.load(SeqCst) + frames - keep_frames, SeqCst);
            floats = keep_frames * channels;
        }
        let offset = written % capacity;
        let first = (capacity - offset).min(floats);
        // SAFETY: the producer's side of the ring — [written, written +
        // floats) lies in what the drain has freed — inside `capacity`.
        unsafe {
            ptr::copy_nonoverlapping(input.as_ptr(), ring.add(offset as usize), first as usize);
            ptr::copy_nonoverlapping(input.as_ptr().add(first as usize), ring, (floats - first) as usize);
        }
        // Published AFTER the copy: the drain must never see a total that
        // covers samples still being written.
        self.write_total.store(written + floats, SeqCst);
        self.stamp_clock((written + floats) / channels, asked_at_us);
    }

    /// The capture callback's last word. ⚠️The playback's stamp is the same
    /// seqlock with an arm serial on top — a third would make them one.
    fn stamp_clock(&self, frames: i64, time_us: i64) {
        let seq = self.clock_seq.load(SeqCst);
        self.clock_seq.store(seq.wrapping_add(1), SeqCst);
        self.clock_frames.store(frames, SeqCst);
        self.clock_time_us.store(time_us, SeqCst);
        self.clock_seq.store(seq.wrapping_add(2), SeqCst);
    }

    /// Drains up to `out`'s length from the ring; the floats copied. The
    /// control thread's alone — the far end from the callback.
    pub(crate) fn read(&self, out: &mut [f32]) -> usize {
        if !self.is_open() {
            return 0;
        }
        // Open AFTER its ring was made (`open`): read after it, the ring is.
        let ring = self.ring.load(SeqCst);
        let capacity = self.capacity.load(SeqCst);
        let written = self.write_total.load(SeqCst);
        let read = self.read_total.load(SeqCst);
        let available = (written - read).min(out.len() as i64);
        if available <= 0 {
            return 0;
        }
        let offset = read % capacity;
        let first = (capacity - offset).min(available);
        // SAFETY: the consumer's side — [read, read + available) the
        // callback has published — inside `capacity`.
        unsafe {
            ptr::copy_nonoverlapping(ring.add(offset as usize), out.as_mut_ptr(), first as usize);
            ptr::copy_nonoverlapping(ring, out.as_mut_ptr().add(first as usize), (available - first) as usize);
        }
        self.read_total.store(read + available, SeqCst);
        available as usize
    }

    pub(crate) fn is_open(&self) -> bool {
        self.open.load(SeqCst)
    }

    pub(crate) fn channels(&self) -> i32 {
        self.channels.load(SeqCst)
    }

    pub(crate) fn sample_rate(&self) -> i32 {
        self.sample_rate.load(SeqCst)
    }

    /// Frames the ring had to drop for the drain fell behind. Nonzero means
    /// the take is DAMAGED — the recorder must say so.
    pub(crate) fn dropped_frames(&self) -> i64 {
        self.dropped_frames.load(SeqCst)
    }

    /// Frames the ring has been given so far — the capture's stair.
    pub(crate) fn frames(&self) -> i64 {
        let channels = i64::from(self.channels());
        if !self.is_open() || channels <= 0 {
            return 0;
        }
        self.write_total.load(SeqCst) / channels
    }

    /// The latest point of the capture's line — (the frames the ring had
    /// been given when that callback returned, when it was asked for them)
    /// — or none: none open, or no callback of it has spoken yet.
    pub(crate) fn clock(&self) -> Option<(i64, i64)> {
        if !self.is_open() {
            return None;
        }
        for _ in 0..16 {
            let before = self.clock_seq.load(SeqCst);
            if before & 1 != 0 {
                continue;
            }
            let frames = self.clock_frames.load(SeqCst);
            let time_us = self.clock_time_us.load(SeqCst);
            if self.clock_seq.load(SeqCst) != before {
                continue;
            }
            return if time_us == 0 { None } else { Some((frames, time_us)) };
        }
        None
    }
}
