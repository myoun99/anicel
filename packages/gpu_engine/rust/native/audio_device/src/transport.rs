//! The transport (audio program 2C) — where "audio is the master clock"
//! becomes literal. The device pulls blocks on its own realtime thread;
//! each pull mixes the next span and advances a counter, and the playback
//! position IS that counter — the samples handed to the device — so it
//! cannot drift from what is heard. A free-running timer can; that is the
//! defect the program started from.
//!
//! NON-NEGOTIABLE: no Dart runs in the callback, and nothing in it waits,
//! locks, allocates or frees. Dart makes the PCM in buffers
//! ([`crate::buffer`]), hands over the schedule that names them, starts and
//! stops the transport and polls the position.
//!
//! The schedule lives in TWO slots (AUDIO-PRO R3): the callback reads the
//! active one, a replacement builds in the standby one, and a flip
//! publishes it — an edit during playback is heard at the next block. The
//! control thread then waits, bounded, for the callback to acknowledge the
//! new slot before freeing the old one.

use std::cell::UnsafeCell;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicI64, AtomicU32, Ordering::SeqCst};
use std::thread;
use std::time::Duration;

use audio_mix::{Clip, EnvelopeKey, Source};

use crate::{buffer, clock};

/// The longest block one mix runs: a callback asked for more mixes it in
/// blocks of this.
pub(crate) const MAX_BLOCK: usize = 8192;

/// One complete schedule: everything a mixed block reads.
pub(crate) struct Slot {
    pub(crate) clips: Vec<Clip>,
    /// Each holding the buffer it plays.
    pub(crate) sources: Vec<Source>,
    /// The clips' shared envelope keys.
    pub(crate) keys: Vec<EnvelopeKey>,
}

impl Slot {
    const EMPTY: Slot = Slot { clips: Vec::new(), sources: Vec::new(), keys: Vec::new() };

    fn free(&mut self) {
        buffer::let_go_all(&self.sources);
        *self = Slot::EMPTY;
    }
}

/// How one callback's blocks ended.
enum Ending {
    /// Every frame handed, the last block leaving the position here: the
    /// callback's point on the clock's line.
    Handed(i64),
    /// A play or a seek landed while a block mixed: the frames before it
    /// handed, the rest not.
    Moved(usize),
    /// The run ran out at its stop, ending itself: no point.
    Stopped,
}

/// What mixes a block of a slot from a timeline position into a bus: the
/// mix bus itself ([`mix_slot`]) — or, in the transport's tests, one that
/// moves the transport while the block mixes, as the control thread can.
pub(crate) type Mixer<'a> = &'a dyn Fn(&Slot, i64, usize, &mut [f64]);

/// The mix bus over a slot.
pub(crate) fn mix_slot(slot: &Slot, start: i64, channels: usize, out: &mut [f64]) {
    // SAFETY: every source of a slot holds the buffer it plays, which
    // holds every sample it reads (`buffer::hold_all`).
    unsafe { audio_mix::mix(&slot.clips, &slot.sources, &slot.keys, start, channels, out) }
}

/// The transport, shared by the control thread and the device's realtime
/// callback: every field the callback reads is an atomic, but for the two
/// slots, whose hand-over the fields prove. The mix bus is not here: each
/// device's callback owns its own.
pub(crate) struct Transport {
    open: AtomicBool,
    /// The run playing — [`Transport::play`] numbers each one — or 0 for
    /// none. Ending a run that ran out is the one write the callback makes
    /// here, and it compares and swaps from the run it read: a run ended
    /// outright could be the one play() armed while the block was in
    /// flight (2026-10-23, the position's race).
    playing: AtomicU32,
    /// The control thread's alone.
    runs: AtomicU32,
    /// Samples HANDED TO THE DEVICE: it advances only when audio leaves,
    /// so it cannot run ahead of what is heard.
    position: AtomicI64,
    start_position: AtomicI64,
    /// Exclusive; at or below the start means "no end".
    stop_position: AtomicI64,
    looping: AtomicBool,
    /// THE LEAD (a-start-is-heard-ahead-of-its-first-picture, 2026-10-17).
    /// A run's first sample must be HEARD as its first picture is SHOWN, and
    /// a picture is shown refreshes after the look that starts the run —
    /// longer than the device takes to play what it is handed. So a run
    /// starts that far AHEAD of its first sample, and what it hands before
    /// this is silence, counted on the clock like any sample. ⛔Not the
    /// sound from before the start: that would be heard over the first
    /// picture. Written by the control thread alone (play, seek).
    audible_from: AtomicI64,
    /// THE CLOCK'S LINE (2026-10-08). `position` is a STAIR: read between
    /// two callbacks it says what the last one handed, and the device has
    /// played on since — a picture that reads the stair changes frame up to
    /// a step late, by a different amount each frame. So each callback also
    /// says WHEN it handed what it handed, and a reader draws the line
    /// through the latest point: the samples handed by then, plus the time
    /// since at the device's rate.
    ///
    /// `clock_serial` is the ARM (play, seek) the point belongs to: a
    /// callback in flight when the transport is armed again writes a point
    /// of the old arm, and the reader drops it. One writer — the callback —
    /// read whole through `clock_seq`, odd while being written. A point
    /// with no time (0) is no point.
    arm_serial: AtomicU32,
    clock_seq: AtomicU32,
    clock_serial: AtomicU32,
    clock_position: AtomicI64,
    clock_time_us: AtomicI64,
    slots: [UnsafeCell<Slot>; 2],
    active_slot: AtomicU32,
    callback_slot: AtomicU32,
    /// True while a callback body runs. With `callback_slot` this is what
    /// lets the control thread PROVE the old slot abandoned before freeing
    /// it — the just-stopped mid-block window included.
    in_flight: AtomicBool,
    /// The last mixed block's PRE-CLIP bus peak per side (float bits) — the
    /// meter's feed (AUDIO-PRO R2). Pre-clip on purpose: a peak past 1.0 is
    /// the "why does it sound squashed" answer the meter exists to show.
    peak_left_bits: AtomicU32,
    peak_right_bits: AtomicU32,
    /// The open device's geometry — or the last one's, as the C's stayed.
    sample_rate: AtomicI32,
    channels: AtomicI32,
}

// SAFETY: the callback and the control thread share the transport. Every
// field either of them writes while the other may read is an atomic, but
// for the two slots — the callback reads only the one `active_slot` names
// and says so through `callback_slot` and `in_flight`, and the control
// thread writes only the other and frees the one it flipped from only once
// the callback has said it left it (`set_schedule`).
unsafe impl Sync for Transport {}

impl Transport {
    pub(crate) const fn new() -> Transport {
        Transport {
            open: AtomicBool::new(false),
            playing: AtomicU32::new(0),
            runs: AtomicU32::new(0),
            position: AtomicI64::new(0),
            start_position: AtomicI64::new(0),
            stop_position: AtomicI64::new(0),
            looping: AtomicBool::new(false),
            audible_from: AtomicI64::new(0),
            arm_serial: AtomicU32::new(0),
            clock_seq: AtomicU32::new(0),
            clock_serial: AtomicU32::new(0),
            clock_position: AtomicI64::new(0),
            clock_time_us: AtomicI64::new(0),
            slots: [UnsafeCell::new(Slot::EMPTY), UnsafeCell::new(Slot::EMPTY)],
            active_slot: AtomicU32::new(0),
            callback_slot: AtomicU32::new(0),
            in_flight: AtomicBool::new(false),
            peak_left_bits: AtomicU32::new(0),
            peak_right_bits: AtomicU32::new(0),
            sample_rate: AtomicI32::new(0),
            channels: AtomicI32::new(0),
        }
    }

    /// A device of `channels` at `sample_rate` opens, and nothing plays —
    /// before it starts.
    pub(crate) fn open(&self, sample_rate: i32, channels: i32) {
        self.sample_rate.store(sample_rate, SeqCst);
        self.channels.store(channels, SeqCst);
        self.playing.store(0, SeqCst);
        self.position.store(0, SeqCst);
        // A device just opened has no run: whatever the one before it left
        // is not its point.
        self.begin_arm();
        self.open.store(true, SeqCst);
    }

    /// The device opened did not start: none is open, and the schedule is
    /// as it was.
    pub(crate) fn not_started(&self) {
        self.open.store(false, SeqCst);
    }

    /// The device closes: silenced, then `unmake` — after which its
    /// callback can no longer run — then its schedule freed.
    pub(crate) fn close(&self, unmake: impl FnOnce()) {
        self.playing.store(0, SeqCst);
        unmake();
        // SAFETY: no callback runs any more: both slots are the control
        // thread's.
        unsafe {
            (*self.slots[0].get()).free();
            (*self.slots[1].get()).free();
        }
        self.open.store(false, SeqCst);
    }

    pub(crate) fn is_open(&self) -> bool {
        self.open.load(SeqCst)
    }

    pub(crate) fn sample_rate(&self) -> i32 {
        self.sample_rate.load(SeqCst)
    }

    pub(crate) fn channels(&self) -> i32 {
        self.channels.load(SeqCst)
    }

    /// 🚨THE CALLBACK MOVES THE POSITION ONLY FROM WHAT ITS BLOCK READ
    /// (a-seek-lost-to-the-block-in-flight, 2026-10-23). The position has
    /// two writers: the callback, which advances it by what it hands, and
    /// the control thread, which moves it (play, seek). A callback that
    /// stored its advance outright wrote over a seek that landed while its
    /// block mixed (a test read 960 where the seek put 33600). So the
    /// callback compares and swaps, and loses: what the control thread
    /// wrote stands.
    fn claim(&self, read: i64, to: i64) -> bool {
        self.position.compare_exchange(read, to, SeqCst, SeqCst).is_ok()
    }

    /// A new arm: the points written under the old one are no longer the
    /// transport's. The control thread's alone, AFTER the position it arms
    /// is written: a callback that reads this arm reads that position or a
    /// later one.
    fn begin_arm(&self) {
        self.arm_serial.store(self.arm_serial.load(SeqCst).wrapping_add(1), SeqCst);
    }

    /// The callback's last word: what it handed, when it was asked for it,
    /// under which arm. ⚠️The capture's stamp is the same seqlock without
    /// the arm — a third would make them one.
    fn stamp_clock(&self, serial: u32, position: i64, time_us: i64) {
        let seq = self.clock_seq.load(SeqCst);
        self.clock_seq.store(seq.wrapping_add(1), SeqCst);
        self.clock_serial.store(serial, SeqCst);
        self.clock_position.store(position, SeqCst);
        self.clock_time_us.store(time_us, SeqCst);
        self.clock_seq.store(seq.wrapping_add(2), SeqCst);
    }

    fn set_peaks(&self, left: f32, right: f32) {
        self.peak_left_bits.store(left.to_bits(), SeqCst);
        self.peak_right_bits.store(right.to_bits(), SeqCst);
    }

    /// The realtime callback: `out`, interleaved `channels`, filled with
    /// the next span the transport plays — silence when it plays none —
    /// mixed in `bus`, the callback's own, of [`MAX_BLOCK`] × `channels`.
    pub(crate) fn render(&self, out: &mut [f32], channels: usize, bus: &mut [f64], mixer: Mixer) {
        out.fill(0.0);
        // The arm BEFORE the look at `playing`: a callback that saw the old
        // arm and then finds the transport armed again stamps its point
        // with the old serial, and the reader drops it.
        let arm = self.arm_serial.load(SeqCst);
        let asked_at_us = clock::now_us();
        let run = self.playing.load(SeqCst);
        if run == 0 || bus.len() < MAX_BLOCK * channels {
            return;
        }
        // Everything below reads a slot: bracketed by `in_flight` so the
        // control thread can wait a block out instead of freeing under it.
        self.in_flight.store(true, SeqCst);
        match self.render_blocks(out, channels, mixer, run, bus) {
            Ending::Handed(handed) => self.stamp_clock(arm, handed, asked_at_us),
            // A play or a seek moved the transport while this callback
            // mixed. What it mixed from the place left behind is not
            // handed, and its point is not the clock's: the next callback
            // starts where the move put it.
            Ending::Moved(done) => out[done * channels..].fill(0.0),
            Ending::Stopped => {}
        }
        self.in_flight.store(false, SeqCst);
    }

    /// The blocks of one callback, and how it ended.
    fn render_blocks(&self, out: &mut [f32], channels: usize, mixer: Mixer, run: u32, bus: &mut [f64]) -> Ending {
        let frames = out.len() / channels;
        let mut handed = self.position.load(SeqCst);
        let mut done = 0;
        while done < frames {
            // The position FIRST: play() and seek() write it after the
            // fields that go with it, so those read here are its own or
            // newer.
            let mut position = self.position.load(SeqCst);
            let start_position = self.start_position.load(SeqCst);
            let stop_position = self.stop_position.load(SeqCst);
            let bounded = stop_position > start_position;
            if bounded && position >= stop_position {
                if !self.looping.load(SeqCst) {
                    let _ = self.playing.compare_exchange(run, 0, SeqCst, SeqCst);
                    return Ending::Stopped;
                }
                if !self.claim(position, start_position) {
                    return Ending::Moved(done);
                }
                position = start_position;
            }
            let mut block = (frames - done).min(MAX_BLOCK);
            // Never mix past the stop point in one block: a wrap lands on
            // the sample, not on the buffer's boundary.
            if bounded && stop_position - position < block as i64 {
                block = (stop_position - position) as usize;
            }
            if block == 0 {
                return Ending::Stopped;
            }
            // Which slot this block reads, said BEFORE mixing so the control
            // thread can prove the old one abandoned.
            let slot_index = self.active_slot.load(SeqCst) & 1;
            self.callback_slot.store(slot_index, SeqCst);
            // SAFETY: the active slot is the callback's to read (see `Sync`).
            let slot = unsafe { &*self.slots[slot_index as usize].get() };
            // The lead: handed, and silent (`out` is zeroed). Never past the
            // first audible sample in one block — the sound begins on it.
            let audible_from = self.audible_from.load(SeqCst);
            if position < audible_from {
                let silent = audible_from - position;
                let block = if block as i64 > silent { silent as usize } else { block };
                handed = position + block as i64;
                if !self.claim(position, handed) {
                    return Ending::Moved(done);
                }
                self.set_peaks(0.0, 0.0);
                done += block;
                continue;
            }
            let bus = &mut bus[..block * channels];
            mixer(slot, position, channels, bus);
            let (left, right) = clip_into(bus, &mut out[done * channels..][..block * channels], channels);
            handed = position + block as i64;
            if !self.claim(position, handed) {
                return Ending::Moved(done);
            }
            self.set_peaks(left as f32, if channels == 1 { left } else { right } as f32);
            done += block;
        }
        Ending::Handed(handed)
    }

    /// Replaces the schedule — legal at ANY time (AUDIO-PRO R3): built in the
    /// standby slot and flipped, then — waiting, bounded, on THIS thread,
    /// never the realtime one — the old slot is freed once the callback has
    /// left it. Every source plays a buffer or nothing, and the slot holds
    /// each buffer it plays, copying no samples; a source naming anything
    /// else, or reading past its buffer, refuses the schedule.
    pub(crate) fn set_schedule(&self, clips: &[Clip], sources: &[Source], keys: &[EnvelopeKey]) -> bool {
        // ALWAYS into the standby slot and flipped — even stopped, a just-
        // stopped callback can be mid-block in the active slot for another
        // ~10ms, and the handshake below makes the free safe in every case.
        let active = self.active_slot.load(SeqCst) & 1;
        let target = active ^ 1;
        if !buffer::hold_all(sources) {
            return false;
        }
        // SAFETY: the standby slot is the control thread's (see `Sync`).
        let slot = unsafe { &mut *self.slots[target as usize].get() };
        // A bounded wait before may have bailed and left this slot full;
        // freeing it here is what makes that leak heal itself.
        slot.free();
        let (Some(clips), Some(keys)) = (copied(clips), copied(keys)) else {
            buffer::let_go_all(sources);
            return false;
        };
        let Some(copied_sources) = copied(sources) else {
            buffer::let_go_all(sources);
            return false;
        };
        *slot = Slot { clips, sources: copied_sources, keys };
        // Publish, then prove the hand-over before freeing the old slot: it
        // is abandoned once the callback has said the NEW one (it reads
        // `active_slot` every block) or is not running at all. A stalled
        // device thread leaves the old slot to the next swap's free rather
        // than risking a use after free.
        self.active_slot.store(target, SeqCst);
        for _ in 0..500 {
            let in_flight = self.in_flight.load(SeqCst);
            let said = self.callback_slot.load(SeqCst) & 1;
            if !in_flight || said == target {
                // SAFETY: the callback has left it (above).
                unsafe { (*self.slots[active as usize].get()).free() };
                break;
            }
            thread::sleep(Duration::from_millis(1));
        }
        true
    }

    /// Starts playback at `start_sample`, `lead_samples` of silence ahead of
    /// it. `stop_sample` is exclusive; at or below the start for "no end". A
    /// loop wraps to `start_sample`: the lead is its first lap's alone.
    /// ⛔No floor here: a lead is never below none by
    /// `HeardOnTheDevice.leadFor`, the one place that says so. The RUN it
    /// starts — a number no run before it on this device had, never 0 — or
    /// 0 with no device open.
    pub(crate) fn play(&self, start_sample: i64, stop_sample: i64, looping: bool, lead_samples: i64) -> i32 {
        if !self.is_open() {
            return 0;
        }
        // A restart while audible: silence the callback FIRST so it never
        // mixes with a half-updated transport, then the fields — the
        // position last, which a callback reads first — then the arm. The
        // seq-cst stores double as the release fence `playing` needs on ARM.
        self.playing.store(0, SeqCst);
        self.audible_from.store(start_sample, SeqCst);
        self.start_position.store(start_sample, SeqCst);
        self.stop_position.store(stop_sample, SeqCst);
        self.looping.store(looping, SeqCst);
        self.position.store(start_sample.wrapping_sub(lead_samples), SeqCst);
        self.begin_arm();
        let run = next_run(self.runs.load(SeqCst));
        self.runs.store(run, SeqCst);
        self.playing.store(run, SeqCst);
        run as i32
    }

    pub(crate) fn stop(&self) {
        self.playing.store(0, SeqCst);
        // The run is over, and its points with it. (A device that runs OUT
        // by itself is not stopped here: its last point stands.)
        self.begin_arm();
        // A stopped transport meters silence — the bars must not freeze at
        // the last audible block.
        self.set_peaks(0.0, 0.0);
    }

    /// A player's own end: [`Transport::stop`], unless ANOTHER run than
    /// `run` holds the device — a sound that player did not start plays on.
    /// ↩️Each player stopped the device whatever played, and a cue's end
    /// silenced a viewer's sound pressed during it (board
    /// a-cue-ending-silences-a-viewer-sound-it-did-not-make).
    pub(crate) fn stop_run(&self, run: i32) {
        let playing = self.playing.load(SeqCst) as i32;
        if playing != 0 && playing != run {
            return;
        }
        self.stop();
    }

    pub(crate) fn is_playing(&self) -> bool {
        self.playing.load(SeqCst) != 0
    }

    /// Samples handed to the device so far — THE clock.
    pub(crate) fn position(&self) -> i64 {
        self.position.load(SeqCst)
    }

    /// Moves the transport without restarting anything: the mixer builds a
    /// mix rather than starting clips, so a seek only changes where the
    /// next block reads. A block in flight loses to it ([`Transport::claim`]).
    ///
    /// The position before the arm: a callback that reads the new arm reads
    /// the new position with it. 🧪MUTATION: the arm ahead of the position
    /// here, or play()'s position ahead of its fields, passes the transport
    /// tests — both orders matter only between two loads at a callback's
    /// entry, where a test's mixer cannot stand. This order and this note
    /// are what hold them.
    pub(crate) fn seek(&self, sample: i64) {
        // A seek starts no run: where it lands is heard, and all after it.
        self.audible_from.store(i64::MIN, SeqCst);
        self.position.store(sample, SeqCst);
        self.begin_arm();
    }

    /// The latest point of the clock's line for the arm the transport is in
    /// — (the samples handed when that callback returned, when it was asked
    /// for them) — or none: no callback has spoken since the last arm, and
    /// there is only the stair to read.
    pub(crate) fn clock(&self) -> Option<(i64, i64)> {
        for _ in 0..16 {
            let before = self.clock_seq.load(SeqCst);
            if before & 1 != 0 {
                continue;
            }
            let serial = self.clock_serial.load(SeqCst);
            let position = self.clock_position.load(SeqCst);
            let time_us = self.clock_time_us.load(SeqCst);
            if self.clock_seq.load(SeqCst) != before {
                continue;
            }
            if time_us == 0 || serial != self.arm_serial.load(SeqCst) {
                return None;
            }
            return Some((position, time_us));
        }
        None
    }

    /// The last mixed block's pre-clip peak of `channel` (0 left, 1 right; a
    /// mono device mirrors left). Past 1.0 the output stage is clipping.
    pub(crate) fn peak(&self, channel: i32) -> f64 {
        let bits = if channel == 1 { &self.peak_right_bits } else { &self.peak_left_bits };
        f64::from(f32::from_bits(bits.load(SeqCst)))
    }
}

/// The run numbered after `runs`: never 0, which is none.
pub(crate) fn next_run(runs: u32) -> u32 {
    if runs == u32::MAX { 1 } else { runs + 1 }
}

/// `bus` clipped into `out` — the bus has headroom, the DEVICE does not —
/// and its pre-clip peak per side, metered BEFORE the clip: the peak that
/// matters is the one the bus reached.
fn clip_into(bus: &[f64], out: &mut [f32], channels: usize) -> (f64, f64) {
    let (mut left, mut right) = (0.0f64, 0.0f64);
    for (index, (&value, out)) in bus.iter().zip(out).enumerate() {
        let magnitude = if value < 0.0 { -value } else { value };
        let side = if channels == 1 { 0 } else { index % channels };
        if side == 0 && magnitude > left {
            left = magnitude;
        } else if side == 1 && magnitude > right {
            right = magnitude;
        }
        let clipped = if value > 1.0 {
            1.0
        } else if value < -1.0 {
            -1.0
        } else {
            value
        };
        *out = clipped as f32;
    }
    (left, right)
}

/// `items` copied, or none when the memory is not there.
fn copied<T: Copy>(items: &[T]) -> Option<Vec<T>> {
    let mut copy = Vec::new();
    copy.try_reserve_exact(items.len()).ok()?;
    copy.extend_from_slice(items);
    Some(copy)
}
