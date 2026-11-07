//! The device against the engine's C (native/oracle): the transport's
//! races as `qa_audio_transport_test.c` runs them, what a callback hands
//! against the C's mix bus, the buffers' holds, the null backend's devices
//! and capture, and the clock — the Rust's exports and the C's side by
//! side.

use std::cell::Cell;
use std::ffi::c_char;
use std::ptr;
use std::sync::atomic::{AtomicI32, Ordering::SeqCst};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::thread;
use std::time::{Duration, Instant};

use audio_mix::{Clip, EnvelopeKey, Source};

use crate::transport::{MAX_BLOCK, Slot, Transport, mix_slot};
use crate::*;

type Mix =
    unsafe extern "C" fn(*const Clip, i32, *const Source, i32, *const EnvelopeKey, i32, i64, i32, i32, *mut f64);
type SetSchedule = unsafe extern "C" fn(*const Clip, i32, *const Source, i32, *const EnvelopeKey, i32) -> i32;
type Describe = unsafe extern "C" fn(i32, i32, *mut c_char, i32, *mut i32) -> i32;
type Point = unsafe extern "C" fn(*mut i64) -> i32;
type Read = unsafe extern "C" fn(*mut f32, i32) -> i32;

fn c<F: Copy>(name: &str) -> F {
    // SAFETY: each type is its export's C declaration in qa_audio_device.c
    // or qa_engine.c.
    unsafe { oracle::export::<F>(name) }
}

/// One test at a time on the devices: both sides' are process-wide.
fn serial() -> MutexGuard<'static, ()> {
    static SERIAL: Mutex<()> = Mutex::new(());
    SERIAL.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Waits for `done`, up to five seconds of the wall.
fn within(mut done: impl FnMut() -> bool) -> bool {
    let started = Instant::now();
    while started.elapsed() < Duration::from_secs(5) {
        if done() {
            return true;
        }
        thread::sleep(Duration::from_millis(2));
    }
    done()
}

// --- The transport's races (qa_audio_transport_test.c) --------------------

const MIXED: f64 = 0.25;
const FRAMES: usize = 480;

/// A mono transport, as an open leaves it, whose mixer makes every sample
/// [`MIXED`] — and, the first time it mixes after `between` is set, makes
/// that move: the control thread's, landed while the block mixes.
struct Racer {
    transport: Transport,
    between: Cell<Option<fn(&Transport)>>,
    bus: Cell<Vec<f64>>,
}

impl Racer {
    fn new() -> Racer {
        let transport = Transport::new();
        transport.open(48_000, 1);
        Racer { transport, between: Cell::new(None), bus: Cell::new(vec![0.0; MAX_BLOCK]) }
    }

    /// One pull of `frames` by the device: how many came out mixed.
    fn pull(&self, frames: usize) -> usize {
        let mixer = |_: &Slot, _: i64, _: usize, bus: &mut [f64]| {
            bus.fill(MIXED);
            if let Some(between) = self.between.take() {
                between(&self.transport);
            }
        };
        let mut out = vec![0.0f32; frames];
        let mut bus = self.bus.take();
        self.transport.render(&mut out, 1, &mut bus, &mixer);
        self.bus.set(bus);
        out.iter().filter(|&&sample| sample != 0.0).count()
    }
}

#[test]
fn a_seek_that_lands_mid_block_stands() {
    // 🚨THE ONE A TEST MET UNDER LOAD: moved while a block mixed, the
    // transport went back to the block's end.
    let racer = Racer::new();
    racer.transport.play(0, 0, false, 0);
    assert_eq!(racer.pull(FRAMES), FRAMES, "premise: a run's block is handed");
    racer.between.set(Some(|transport| transport.seek(33_600)));
    assert_eq!(racer.pull(FRAMES), 0, "the block mixed from the place the seek left is not handed");
    assert_eq!(racer.transport.position(), 33_600, "the seek stands");
    assert_eq!(racer.pull(FRAMES), FRAMES, "the run goes on from it");
    assert_eq!(racer.transport.position(), 33_600 + FRAMES as i64, "…counted from there");
}

#[test]
fn a_play_that_lands_mid_block_stands() {
    let racer = Racer::new();
    racer.transport.play(0, 0, false, 0);
    racer.pull(FRAMES);
    racer.between.set(Some(|transport| {
        transport.play(96_000, 0, false, 0);
    }));
    racer.pull(FRAMES);
    assert_eq!(racer.transport.position(), 96_000, "a play that lands mid-block stands");
    assert!(racer.transport.is_playing(), "…and its run is playing");
}

#[test]
fn a_run_that_ran_out_ends_only_itself() {
    // Played again from the same place while the run's last block mixed:
    // the run that ran out is not the run now playing.
    let racer = Racer::new();
    racer.transport.play(0, MAX_BLOCK as i64, false, 0);
    racer.between.set(Some(|transport| {
        transport.play(0, MAX_BLOCK as i64, false, 0);
    }));
    racer.pull(MAX_BLOCK + FRAMES);
    assert!(racer.transport.is_playing(), "the run played again is still playing");
}

#[test]
fn a_run_still_runs_out_loops_and_hands_its_lead_silent() {
    let racer = Racer::new();
    racer.transport.play(0, 2 * FRAMES as i64, false, 0);
    for _ in 0..3 {
        racer.pull(FRAMES);
    }
    assert!(!racer.transport.is_playing(), "a run that reaches its stop ends");
    racer.transport.play(0, 2 * FRAMES as i64, true, 0);
    for _ in 0..3 {
        racer.pull(FRAMES);
    }
    assert_eq!(racer.transport.position(), FRAMES as i64, "a loop wraps to its start");
    racer.transport.play(1000, 0, false, FRAMES as i64);
    assert_eq!(racer.pull(FRAMES), 0, "a lead is handed silent");
    assert_eq!(racer.transport.position(), 1000, "…and counted");
    assert_eq!(racer.transport.peak(0), 0.0, "…and metered silent");
}

#[test]
fn a_stop_inside_a_block_cuts_the_block_on_it() {
    // A run ends on its stop sample, and a loop wraps on it — never on the
    // buffer's boundary.
    let racer = Racer::new();
    racer.transport.play(0, 700, false, 0);
    assert_eq!(racer.pull(FRAMES), FRAMES);
    assert_eq!(racer.pull(FRAMES), 700 - FRAMES, "the block stops at the stop");
    assert_eq!((racer.transport.position(), racer.transport.is_playing()), (700, false));
    racer.transport.play(0, 700, true, 0);
    racer.pull(FRAMES);
    assert_eq!(racer.pull(FRAMES), FRAMES, "a loop plays on through its stop…");
    assert_eq!(racer.transport.position(), 2 * FRAMES as i64 - 700, "…wrapped on the stop sample");
}

#[test]
fn every_callback_that_hands_leaves_its_point() {
    let racer = Racer::new();
    racer.transport.play(0, 0, false, 0);
    for pulls in 1..=3 {
        racer.pull(FRAMES);
        assert_eq!(racer.transport.clock().map(|(position, _)| position), Some(pulls * FRAMES as i64));
    }
}

#[test]
fn a_callback_with_no_bus_hands_silence() {
    // The C's callback with no scratch: nothing mixed, nothing handed.
    let transport = Transport::new();
    transport.open(48_000, 1);
    transport.play(0, 0, false, 0);
    let mut out = vec![7.0f32; FRAMES];
    transport.render(&mut out, 1, &mut [], &mix_slot);
    assert!(out.iter().all(|&sample| sample == 0.0));
    assert_eq!(transport.position(), 0);
}

#[test]
fn a_run_is_never_numbered_none() {
    assert_eq!(crate::transport::next_run(0), 1);
    assert_eq!(crate::transport::next_run(41), 42);
    assert_eq!(crate::transport::next_run(u32::MAX), 1, "past the last number, the first — not 0");
}

/// A mono source of 64 samples playing `samples`.
fn mono(samples: *mut f32) -> Source {
    Source { source_start: 0, length: 64, channels: 1, reserved: 0, samples }
}

#[test]
fn a_close_lets_go_of_both_slots() {
    let transport = Transport::new();
    transport.open(48_000, 1);
    let (first, second) = (buffer::new(64), buffer::new(64));
    assert!(transport.set_schedule(&[], &[mono(first)], &[]));
    assert!(transport.set_schedule(&[], &[mono(second)], &[]));
    assert_eq!((buffer::holds(first), buffer::holds(second)), (1, 2), "premise: the slot the flip left let go");
    transport.close(|| {});
    assert_eq!(buffer::holds(second), 1, "the close lets go of the slot that played");
    buffer::release(first);
    buffer::release(second);
}

#[test]
fn a_slot_the_callback_has_left_is_freed_while_it_still_runs() {
    // The callback has said the NEW slot, its blocks still running: the old
    // one is abandoned, and the replacement frees it without waiting the
    // callback out.
    let transport = Transport::new();
    transport.open(48_000, 1);
    let (old, new) = (buffer::new(64), buffer::new(64));
    assert!(transport.set_schedule(&[], &[mono(old)], &[]));
    transport.play(0, 0, false, 0);
    let blocks = Cell::new(0);
    let freed_in_flight = Cell::new(false);
    // The samples' address: a pointer does not cross threads.
    let new_address = new as usize;
    thread::scope(|scope| {
        let mixer = |_: &Slot, _: i64, _: usize, bus: &mut [f64]| {
            bus.fill(MIXED);
            blocks.set(blocks.get() + 1);
            if blocks.get() == 1 {
                // The control thread replaces the schedule while this block
                // mixes, and has flipped it before the next block reads.
                let transport = &transport;
                scope.spawn(move || assert!(transport.set_schedule(&[], &[mono(new_address as *mut f32)], &[])));
                assert!(within(|| buffer::holds(new) == 2), "premise: the replacement holds its buffer");
                thread::sleep(Duration::from_millis(200));
            } else if blocks.get() == 2 {
                freed_in_flight.set(within(|| buffer::holds(old) == 1));
            }
        };
        let mut out = vec![0.0f32; 3 * MAX_BLOCK];
        transport.render(&mut out, 1, &mut vec![0.0; MAX_BLOCK], &mixer);
    });
    assert!(freed_in_flight.get(), "the old slot waited for the callback to end");
    transport.close(|| {});
    buffer::release(old);
    buffer::release(new);
}

#[test]
fn a_players_end_silences_only_its_own_run() {
    let racer = Racer::new();
    let cue = racer.transport.play(0, 0, false, 0);
    let viewer = racer.transport.play(5000, 0, false, 0);
    assert!(cue != viewer && cue != 0, "premise: every run is its own");
    racer.transport.stop_run(cue);
    assert!(racer.transport.is_playing(), "another's run plays on");
    racer.transport.stop_run(viewer);
    assert!(!racer.transport.is_playing(), "its own run stops");
    // A run that ran out leaves its meter up; a device playing nothing is
    // stopped as before — its meter too.
    racer.transport.play(0, FRAMES as i64, false, 0);
    racer.pull(FRAMES);
    racer.pull(FRAMES);
    assert!(!racer.transport.is_playing());
    assert_eq!(racer.transport.peak(0), MIXED, "premise: the meter is up");
    racer.transport.stop_run(cue);
    assert_eq!(racer.transport.peak(0), 0.0);
}

#[test]
fn a_seek_in_the_lead_is_heard_where_it_lands() {
    // A seek starts no run: the lead before the run's first sample is the
    // run's alone, and where a seek lands is heard.
    let racer = Racer::new();
    racer.transport.play(1000, 0, false, FRAMES as i64);
    racer.transport.seek(0);
    assert_eq!(racer.pull(FRAMES), FRAMES);
}

#[test]
fn a_schedule_replaced_mid_block_is_not_freed_under_it() {
    // The callback still reads the slot it said: the replacement waits it
    // out, bounded, and leaves the old slot to the next replacement.
    let racer = Racer::new();
    let old = buffer::new(64);
    assert!(racer.transport.set_schedule(&[], &[mono(old)], &[]));
    assert_eq!(buffer::holds(old), 2, "premise: its maker and the slot");
    racer.transport.play(0, 0, false, 0);
    racer.between.set(Some(|transport| {
        assert!(transport.set_schedule(&[], &[], &[]));
    }));
    racer.pull(FRAMES);
    assert_eq!(buffer::holds(old), 2, "freed under the block that read it");
    assert!(racer.transport.set_schedule(&[], &[], &[]));
    assert_eq!(buffer::holds(old), 1, "the next replacement frees it");
    buffer::release(old);
    racer.transport.close(|| {});
}

// --- The capture's ring ---------------------------------------------------

/// A capture of `channels` at 100Hz — a ring of 800 frames — with
/// `frames` delivered, counting up from 1.
fn a_ring(channels: i32, frames: usize) -> crate::capture::Capture {
    let ring = crate::capture::Capture::new();
    assert!(ring.open(channels, 100));
    let delivered: Vec<f32> = (1..=frames * channels as usize).map(|value| value as f32).collect();
    ring.deliver(&delivered);
    ring
}

#[test]
fn a_full_ring_drops_whole_frames_and_counts_them() {
    let ring = a_ring(2, 700);
    ring.deliver(&[0.5; 2 * 250]);
    assert_eq!((ring.frames(), ring.dropped_frames()), (800, 150));
    // A drain of a frame and a half leaves room for a frame and a half: the
    // half is not taken.
    let mut out = [0.0f32; 3];
    assert_eq!(ring.read(&mut out), 3);
    ring.deliver(&[0.25; 2 * 2]);
    assert_eq!((ring.frames(), ring.dropped_frames()), (801, 151));
    // What it hands back is what it took: from the fourth float on, and
    // the half frame's room left untaken.
    let mut rest = vec![0.0f32; 2 * 800];
    assert_eq!(ring.read(&mut rest), 2 * 800 - 3 + 2);
    assert_eq!(rest[0], 4.0);
    assert_eq!(&rest[1_396..1_398], &[1_400.0, 0.5]);
    assert_eq!(&rest[1_596..1_600], &[0.5, 0.25, 0.25, 0.0]);
    ring.close();
}

#[test]
fn the_ring_hands_back_what_it_took_across_its_end() {
    let ring = a_ring(1, 600);
    let mut out = vec![0.0f32; 500];
    assert_eq!(ring.read(&mut out), 500);
    let more: Vec<f32> = (601..=1_200).map(|value| value as f32).collect();
    ring.deliver(&more);
    let mut out = vec![0.0f32; 2_000];
    assert_eq!(ring.read(&mut out), 700);
    let want: Vec<f32> = (501..=1_200).map(|value| value as f32).collect();
    assert_eq!(&out[..700], &want[..]);
    assert_eq!((ring.frames(), ring.dropped_frames()), (1_200, 0));
    ring.close();
}

#[test]
fn a_closed_ring_hands_nothing_and_opens_again_empty() {
    let ring = a_ring(1, 300);
    ring.deliver(&[0.5; 600]);
    let mut out = vec![0.0f32; 1_000];
    assert_eq!(ring.read(&mut out[..200]), 200);
    assert_eq!(ring.dropped_frames(), 100, "premise: the take dropped frames");
    ring.close();
    assert_eq!(ring.read(&mut out), 0, "a closed ring hands nothing — its tail is gone with it");
    assert!(ring.open(1, 100));
    assert_eq!((ring.frames(), ring.dropped_frames(), ring.clock()), (0, 0, None), "a ring opens empty");
    ring.deliver(&[0.25; 10]);
    assert_eq!(ring.clock().map(|(frames, _)| frames), Some(10), "the point is what the ring had been given");
    assert_eq!(ring.read(&mut out), 10, "…and hands what it took from then");
    ring.close();
    let never = crate::capture::Capture::new();
    never.deliver(&[0.5; 4]);
    assert_eq!(never.frames(), 0, "a capture with no ring takes nothing");
}

// --- What a callback hands, against the C's mix bus -----------------------

/// A schedule over buffers of this crate's, which the C's mix reads as
/// well as any samples.
struct Schedule {
    buffers: Vec<*mut f32>,
    sources: Vec<Source>,
    clips: Vec<Clip>,
    keys: Vec<EnvelopeKey>,
}

impl Schedule {
    fn new() -> Schedule {
        let mut buffers = Vec::new();
        let mut sources = Vec::new();
        for (channels, length, seed) in [(1, 9_000i64, 0.37f32), (2, 20_000, 0.61), (3, 15_000, 0.23)] {
            let floats = length * channels as i64;
            let samples = buffer::new(floats);
            for index in 0..floats as usize {
                // Each channel louder than the one before: a side's meter
                // reads its own channel, not the loudest.
                let level = (1 + index % channels as usize) as f32 / channels as f32;
                // SAFETY: `floats` samples were made.
                unsafe { *samples.add(index) = ((index as f32 * seed).sin() * 0.9 * level).clamp(-1.0, 1.0) };
            }
            buffers.push(samples);
            sources.push(Source { source_start: 0, length, channels, reserved: 0, samples });
        }
        let keys = vec![
            EnvelopeKey { sample: 2_000, gain: 0.5 },
            EnvelopeKey { sample: 6_000, gain: 2.0 },
            EnvelopeKey { sample: 12_000, gain: 0.25 },
        ];
        let clips = vec![
            Clip {
                gain: 1.7,
                pan_left: 1.0,
                pan_right: 0.4,
                start_sample: 500,
                end_sample: 9_000,
                source_offset: 0,
                fade_in_samples: 700,
                fade_out_samples: 1_200,
                source_index: 0,
                fade_curve: 1,
                envelope_offset: 0,
                envelope_count: 3,
            },
            Clip {
                gain: 2.4,
                pan_left: 0.8,
                pan_right: 1.0,
                start_sample: 3_000,
                end_sample: 22_000,
                source_offset: 1_000,
                fade_in_samples: 0,
                fade_out_samples: 2_000,
                source_index: 1,
                fade_curve: 0,
                ..Clip::default()
            },
            Clip {
                gain: 1.3,
                pan_left: 1.0,
                pan_right: 1.0,
                start_sample: 5_000,
                end_sample: 20_000,
                source_index: 2,
                ..Clip::default()
            },
        ];
        Schedule { buffers, sources, clips, keys }
    }

    /// The C's mix bus: `bus`, of `channels`, from `start`.
    fn c_mix(&self, start: i64, channels: usize, bus: &mut [f64]) {
        let mix: Mix = c("qa_audio_mix");
        // SAFETY: every count is its array's; the bus is its frames x channels.
        unsafe {
            mix(
                self.clips.as_ptr(),
                self.clips.len() as i32,
                self.sources.as_ptr(),
                self.sources.len() as i32,
                self.keys.as_ptr(),
                self.keys.len() as i32,
                start,
                (bus.len() / channels) as i32,
                channels as i32,
                bus.as_mut_ptr(),
            )
        };
    }

    /// The Rust's mix bus (audio_mix, held to the C's in its own tests), the
    /// same.
    fn rust_mix(&self, start: i64, channels: usize, bus: &mut [f64]) {
        // SAFETY: every source holds the samples it reads (`Schedule::new`).
        unsafe { audio_mix::mix(&self.clips, &self.sources, &self.keys, start, channels, bus) }
    }

    /// What `mix` and the output stage hand for `frames` from `start`,
    /// interleaved `channels` — in blocks of [`MAX_BLOCK`], as a callback
    /// mixes — and the last block's pre-clip peak per side.
    fn hands(&self, mix: fn(&Self, i64, usize, &mut [f64]), start: i64, frames: usize, channels: usize) -> Handed {
        let mut out = Vec::new();
        let (mut left, mut right) = (0.0, 0.0);
        let mut done = 0;
        while done < frames {
            let block = (frames - done).min(MAX_BLOCK);
            let mut bus = vec![0.0f64; block * channels];
            mix(self, start + done as i64, channels, &mut bus);
            (left, right) = (0.0, 0.0);
            for (index, value) in bus.iter().enumerate() {
                // The C's meter: channel 0 the left side, channel 1 the
                // right, any wider channel neither.
                match index % channels {
                    0 => left = f64::max(left, value.abs()),
                    1 => right = f64::max(right, value.abs()),
                    _ => {}
                }
                out.push(value.clamp(-1.0, 1.0) as f32);
            }
            done += block;
        }
        (out.iter().map(|sample| sample.to_bits()).collect(), left, if channels == 1 { left } else { right })
    }
}

/// What a callback hands, as bits, and its peaks.
type Handed = (Vec<u32>, f64, f64);

impl Drop for Schedule {
    fn drop(&mut self) {
        for &samples in &self.buffers {
            buffer::release(samples);
        }
    }
}

#[test]
fn a_callback_hands_what_the_cs_mix_bus_mixes_and_clips() {
    let schedule = Schedule::new();
    for channels in [1usize, 2, 3] {
        let transport = Transport::new();
        transport.open(48_000, channels as i32);
        assert!(transport.set_schedule(&schedule.clips, &schedule.sources, &schedule.keys));
        let lead = 300;
        transport.play(400, 0, false, lead);
        let mut bus = vec![0.0f64; MAX_BLOCK * channels];
        let mut position = 400 - lead;
        let mut loudest = 0.0f64;
        for frames in [480usize, 1, 1000, MAX_BLOCK + 100, 2 * MAX_BLOCK, 777] {
            let mut out = vec![7.0f32; frames * channels];
            transport.render(&mut out, channels, &mut bus, &mix_slot);
            // The lead hands silence up to the first audible sample.
            let silent = (400 - position).clamp(0, frames as i64) as usize;
            assert!(out[..silent * channels].iter().all(|&sample| sample == 0.0), "{channels}ch lead at {position}");
            let from = position + silent as i64;
            let (want, left, right) = schedule.hands(Schedule::rust_mix, from, frames - silent, channels);
            let theirs = schedule.hands(Schedule::c_mix, from, frames - silent, channels);
            assert!(theirs == (want.clone(), left, right), "{channels}ch from {from}: the Rust's mix bus is the C's");
            let got: Vec<u32> = out[silent * channels..].iter().map(|sample| sample.to_bits()).collect();
            assert_eq!(got.len(), want.len());
            let first = got.iter().zip(&want).position(|(got, want)| got != want);
            assert_eq!(first, None, "{channels}ch, {frames} frames from {position}");
            if silent < frames {
                assert_eq!((transport.peak(0), transport.peak(1)), (left as f32 as f64, right as f32 as f64));
                loudest = loudest.max(transport.peak(0));
            }
            position += frames as i64;
            assert_eq!(transport.position(), position);
        }
        assert!(loudest > 1.0, "premise: the bus clipped, and the meter said so");
        transport.close(|| {});
    }
}

// --- The buffers' holds ---------------------------------------------------

type New = extern "C" fn(i64) -> *mut f32;
type Retain = extern "C" fn(*mut f32) -> *mut f32;
type Release = extern "C" fn(*mut f32);
type Holds = extern "C" fn(*mut f32) -> i32;

/// The buffer doors and the schedule's, one side's.
#[derive(Clone, Copy)]
struct Doors {
    new: New,
    retain: Retain,
    release: Release,
    holds: Holds,
    set_schedule: SetSchedule,
}

impl Doors {
    fn c() -> Doors {
        Doors {
            new: c("qa_audio_buffer_new"),
            retain: c("qa_audio_buffer_retain"),
            release: c("qa_audio_buffer_release"),
            holds: c("qa_audio_buffer_holds"),
            set_schedule: c("qa_audio_device_set_schedule"),
        }
    }

    fn rust() -> Doors {
        Doors {
            new: qa_audio_buffer_new,
            retain: qa_audio_buffer_retain,
            release: qa_audio_buffer_release,
            holds: qa_audio_buffer_holds,
            set_schedule: qa_audio_device_set_schedule,
        }
    }

    fn schedule(&self, sources: &[Source]) -> i32 {
        // SAFETY: no clips and no keys; the sources are counted.
        unsafe { (self.set_schedule)(ptr::null(), 0, sources.as_ptr(), sources.len() as i32, ptr::null(), 0) }
    }

    /// The holds after each step of one story, the side's own.
    fn story(self) -> Vec<i64> {
        let mut seen = Vec::new();
        let made = (self.new)(64);
        let stereo = |samples, length| Source { source_start: 0, length, channels: 2, reserved: 0, samples };
        seen.push(i64::from((self.holds)(made)));
        seen.push(((self.retain)(made) == made) as i64);
        seen.push(i64::from((self.holds)(made)));
        (self.release)(made);
        seen.push(i64::from((self.holds)(made)));
        seen.push((self.new)(-1).is_null() as i64);
        let empty = (self.new)(0);
        let another = (self.new)(0);
        seen.push(i64::from((self.holds)(empty)));
        seen.push((empty != another) as i64);
        (self.release)(empty);
        seen.push(i64::from((self.holds)(another)));
        (self.release)(another);
        // Samples that are no buffer's — with zeros before them, where the C
        // looks for a buffer's head.
        let mut padded = vec![0.0f32; 24];
        let foreign = padded[16..].as_mut_ptr();
        seen.push(i64::from((self.holds)(foreign)));
        seen.push((self.retain)(foreign).is_null() as i64);
        // A schedule holds each buffer it plays, once per source.
        seen.push(i64::from(self.schedule(&[stereo(made, 32), stereo(made, 1), stereo(ptr::null_mut(), 9)])));
        seen.push(i64::from((self.holds)(made)));
        // Refused — reading past the buffer, or naming none — it holds none.
        seen.push(i64::from(self.schedule(&[stereo(made, 33)])));
        seen.push(i64::from(self.schedule(&[stereo(made, 4), stereo(foreign, 4)])));
        seen.push(i64::from((self.holds)(made)));
        // Its maker may let go while it plays: the slots keep it.
        (self.release)(made);
        seen.push(i64::from((self.holds)(made)));
        // A length or channels of none reads nothing, wherever it points.
        seen.push(i64::from(self.schedule(&[stereo(made, 0), Source { channels: 0, ..stereo(made, 999) }])));
        seen.push(i64::from((self.holds)(made)));
        // The last slot let go: the buffer goes (not asked of it again —
        // the C's would read freed memory).
        seen.push(i64::from(self.schedule(&[])));
        seen
    }
}

// Each step's answer the C's, and — measured of the C 2026-11-07, so held
// once it is gone (connection-round-checklist A) — these.
#[test]
fn the_buffers_are_held_and_let_go_as_the_cs_are() {
    let _serial = serial();
    let (c, rust) = (Doors::c(), Doors::rust());
    let ours = rust.story();
    assert_eq!(ours, c.story());
    assert_eq!(ours, [1, 1, 2, 1, 1, 1, 1, 1, -1, 1, 1, 3, 0, 0, 3, 2, 1, 2, 1]);
}

#[test]
fn a_buffer_let_go_by_every_holder_is_gone() {
    let _serial = serial();
    let made = qa_audio_buffer_new(16);
    let source = Source { source_start: 0, length: 16, channels: 1, reserved: 0, samples: made };
    assert_eq!(Doors::rust().schedule(&[source]), 1);
    qa_audio_buffer_release(made);
    assert_eq!(qa_audio_buffer_holds(made), 1, "the slot holds it");
    assert_eq!(Doors::rust().schedule(&[]), 1);
    assert_eq!(qa_audio_buffer_holds(made), -1, "gone");
}

#[test]
fn a_negative_count_refuses_the_schedule_as_the_cs_does() {
    let _serial = serial();
    for set in [Doors::c().set_schedule, Doors::rust().set_schedule] {
        for (clips, sources, keys) in [(-1, 0, 0), (0, -1, 0), (0, 0, -1)] {
            // SAFETY: refused before anything is read.
            assert_eq!(unsafe { set(ptr::null(), clips, ptr::null(), sources, ptr::null(), keys) }, 0);
        }
    }
}

// --- The null backend -----------------------------------------------------

/// The listing and output doors, one side's.
#[derive(Clone, Copy)]
struct Output {
    count: extern "C" fn(i32, i32) -> i32,
    describe: Describe,
    open: extern "C" fn(i32, i32, i32, i32) -> i32,
    close: extern "C" fn(),
    is_open: extern "C" fn() -> i32,
    sample_rate: extern "C" fn() -> i32,
    channels: extern "C" fn() -> i32,
    latency: extern "C" fn() -> i64,
}

impl Output {
    fn c() -> Output {
        Output {
            count: c("qa_audio_device_count"),
            describe: c("qa_audio_device_describe"),
            open: c("qa_audio_device_open"),
            close: c("qa_audio_device_close"),
            is_open: c("qa_audio_device_is_open"),
            sample_rate: c("qa_audio_device_sample_rate"),
            channels: c("qa_audio_device_channels"),
            latency: c("qa_audio_device_latency_samples"),
        }
    }

    fn rust() -> Output {
        Output {
            count: qa_audio_device_count,
            describe: qa_audio_device_describe,
            open: qa_audio_device_open,
            close: qa_audio_device_close,
            is_open: qa_audio_device_is_open,
            sample_rate: qa_audio_device_sample_rate,
            channels: qa_audio_device_channels,
            latency: qa_audio_device_latency_samples,
        }
    }

    /// What describe tells of `index` of `kind` into `capacity` bytes:
    /// the length, the bytes, whether it is the default.
    fn describe(&self, kind: i32, index: i32, capacity: i32) -> (i32, Vec<u8>, i32) {
        let mut name = vec![UNWRITTEN; 64];
        let mut is_default = 7;
        // SAFETY: `capacity` is at most the name's 64 bytes.
        let length = unsafe { (self.describe)(kind, index, name.as_mut_ptr().cast(), capacity, &mut is_default) };
        name.truncate(capacity.max(0) as usize);
        (length, name, is_default)
    }

    /// What one story tells, step by step.
    fn story(self) -> Vec<String> {
        let mut seen = Vec::new();
        let mut say = |what: &str, value: String| seen.push(format!("{what}: {value}"));
        for kind in [0, 1] {
            say("count", (self.count)(kind, 1).to_string());
            for (index, capacity) in [(0, 64), (0, 5), (0, 2), (0, 1), (0, 0), (1, 64), (-1, 64)] {
                let (length, name, is_default) = self.describe(kind, index, capacity);
                say("describe", format!("{length} {} {is_default}", room(&name)));
            }
        }
        // SAFETY: a null name is refused before anything is written.
        say("no name", unsafe { (self.describe)(0, 0, ptr::null_mut(), 64, ptr::null_mut()) }.to_string());
        // SAFETY: a null default is not written.
        say("no default", unsafe { (self.describe)(0, 0, [0u8; 64].as_mut_ptr().cast(), 64, ptr::null_mut()) }.to_string());
        for (rate, channels) in [(0, 2), (-48_000, 2), (48_000, 0), (48_000, 9), (48_000, -1)] {
            say("refused", (self.open)(rate, channels, 1, -1).to_string());
        }
        say("a bogus index", (self.open)(48_000, 2, 1, 999).to_string());
        say("one past the list", (self.open)(48_000, 2, 1, 1).to_string());
        say("open", (self.open)(48_000, 2, 1, 0).to_string());
        say("geometry", format!("{} {} {} {}", (self.is_open)(), (self.sample_rate)(), (self.channels)(), (self.latency)()));
        say("again, another rate", (self.open)(44_100, 1, 1, -1).to_string());
        // An open output keeps its context: the OS's asked for, the null's
        // answers.
        say("the open one's list", (self.count)(0, 0).to_string());
        (self.close)();
        say("closed", format!("{} {} {} {}", (self.is_open)(), (self.sample_rate)(), (self.channels)(), (self.latency)()));
        say("by default", (self.open)(44_100, 1, 1, -1).to_string());
        say("geometry", format!("{} {} {} {}", (self.is_open)(), (self.sample_rate)(), (self.channels)(), (self.latency)()));
        (self.close)();
        (self.close)();
        seen
    }
}

/// Room no describe wrote.
const UNWRITTEN: u8 = 0x55;

/// A name's room as text: the bytes written — its NUL as `\0` — and how
/// many after them were left as they were.
fn room(bytes: &[u8]) -> String {
    let untouched = bytes.iter().rev().take_while(|&&byte| byte == UNWRITTEN).count();
    format!("{:?} +{untouched}", String::from_utf8_lossy(&bytes[..bytes.len() - untouched]))
}

// Each step's answer the C's, and — measured of the C 2026-11-07, so held
// once it is gone (connection-round-checklist A) — these.
#[test]
fn the_null_backend_lists_and_opens_as_the_cs_does() {
    let _serial = serial();
    let (c, rust) = (Output::c(), Output::rust());
    let ours = rust.story();
    assert_eq!(ours, c.story());
    assert_eq!(
        ours,
        [
            "count: 1",
            r#"describe: 20 "NULL Playback Device\0" +43 1"#,
            r#"describe: 4 "NULL\0" +0 1"#,
            r#"describe: 1 "N\0" +0 1"#,
            r#"describe: -1 "" +1 7"#,
            r#"describe: -1 "" +0 7"#,
            r#"describe: -1 "" +64 7"#,
            r#"describe: -1 "" +64 7"#,
            "count: 1",
            r#"describe: 19 "NULL Capture Device\0" +44 1"#,
            r#"describe: 4 "NULL\0" +0 1"#,
            r#"describe: 1 "N\0" +0 1"#,
            r#"describe: -1 "" +1 7"#,
            r#"describe: -1 "" +0 7"#,
            r#"describe: -1 "" +64 7"#,
            r#"describe: -1 "" +64 7"#,
            "no name: -1",
            "no default: 20",
            "refused: 0",
            "refused: 0",
            "refused: 0",
            "refused: 0",
            "refused: 0",
            "a bogus index: 0",
            "one past the list: 0",
            "open: 48000",
            "geometry: 1 48000 2 1440",
            "again, another rate: 48000",
            "the open one's list: 1",
            "closed: 0 48000 2 0",
            "by default: 44100",
            "geometry: 1 44100 1 1323",
        ]
    );
}

#[test]
fn the_null_device_plays_and_stamps_its_clock() {
    let _serial = serial();
    let schedule = Schedule::new();
    assert_eq!(qa_audio_device_open(48_000, 2, 1, -1), 48_000);
    // SAFETY: each count is its array's.
    let set = unsafe {
        qa_audio_device_set_schedule(
            schedule.clips.as_ptr(),
            schedule.clips.len() as i32,
            schedule.sources.as_ptr(),
            schedule.sources.len() as i32,
            schedule.keys.as_ptr(),
            schedule.keys.len() as i32,
        )
    };
    assert_eq!(set, 1);
    thread::sleep(Duration::from_millis(50));
    assert_eq!(qa_audio_device_position(), 0, "the position advances only while playing");
    let mut point = [0i64; 2];
    let run = qa_audio_device_play(3_000, 0, 0, 0);
    assert!(run > 0);
    // SAFETY: two values.
    assert!(within(|| unsafe { qa_audio_device_clock(point.as_mut_ptr()) } == 1), "no callback spoke");
    let now = qa_audio_clock_now_us();
    assert!(point[0] > 3_000 && point[1] <= now && now - point[1] < 1_000_000, "{point:?} at {now}");
    assert!(within(|| qa_audio_device_peak(0) > 0.0), "the meter reads the mix");
    qa_audio_device_seek(100_000);
    // SAFETY: two values.
    let after_seek = unsafe { qa_audio_device_clock(point.as_mut_ptr()) };
    assert!(after_seek == 0 || point[0] > 100_000, "a point of the arm before the seek: {point:?}");
    assert!(within(|| qa_audio_device_position() > 100_000), "the run goes on from the seek");
    // SAFETY: two values.
    let spoke = within(|| unsafe { qa_audio_device_clock(point.as_mut_ptr()) } == 1);
    assert!(spoke, "premise: the seek's arm has a point");
    let run = qa_audio_device_play(200_000, 0, 0, 0);
    // SAFETY: two values.
    let after_play = unsafe { qa_audio_device_clock(point.as_mut_ptr()) };
    assert!(after_play == 0 || point[0] > 200_000, "a point of the run before the play: {point:?}");
    qa_audio_device_stop_run(run + 1);
    assert_eq!(qa_audio_device_is_playing(), 1, "another's end leaves this run");
    qa_audio_device_stop();
    assert_eq!((qa_audio_device_is_playing(), qa_audio_device_peak(0), qa_audio_device_peak(1)), (0, 0.0, 0.0));
    // SAFETY: two values.
    assert_eq!(unsafe { qa_audio_device_clock(point.as_mut_ptr()) }, 0, "a stopped run's points are not the clock's");
    // SAFETY: a null out is refused.
    assert_eq!(unsafe { qa_audio_device_clock(ptr::null_mut()) }, 0);
    qa_audio_device_play(0, 960, 0, 0);
    assert!(within(|| qa_audio_device_is_playing() == 0), "a stop point ends the run");
    assert_eq!(qa_audio_device_position(), 960);
    // SAFETY: two values.
    assert_eq!(unsafe { qa_audio_device_clock(point.as_mut_ptr()) }, 1, "a run that ran out keeps its last point");
    qa_audio_device_close();
    assert_eq!(qa_audio_device_open(48_000, 2, 1, -1), 48_000);
    // SAFETY: two values.
    assert_eq!(unsafe { qa_audio_device_clock(point.as_mut_ptr()) }, 0, "a device just opened has no point");
    qa_audio_device_play(0, 0, 0, 0);
    qa_audio_device_close();
    assert_eq!(qa_audio_device_is_playing(), 0, "a closed device plays nothing");
    assert_eq!(qa_audio_device_play(0, 0, 0, 0), 0, "no device, no run");
}

// --- Capture --------------------------------------------------------------

#[derive(Clone, Copy)]
struct Capture {
    start: extern "C" fn(i32, i32, i32) -> i32,
    read: Read,
    stop: extern "C" fn(),
    is_open: extern "C" fn() -> i32,
    channels: extern "C" fn() -> i32,
    sample_rate: extern "C" fn() -> i32,
    dropped: extern "C" fn() -> i64,
    frames: extern "C" fn() -> i64,
    clock: Point,
    latency: extern "C" fn() -> i64,
}

impl Capture {
    fn c() -> Capture {
        Capture {
            start: c("qa_audio_capture_start"),
            read: c("qa_audio_capture_read"),
            stop: c("qa_audio_capture_stop"),
            is_open: c("qa_audio_capture_is_open"),
            channels: c("qa_audio_capture_channels"),
            sample_rate: c("qa_audio_capture_sample_rate"),
            dropped: c("qa_audio_capture_dropped_frames"),
            frames: c("qa_audio_capture_frames"),
            clock: c("qa_audio_capture_clock"),
            latency: c("qa_audio_capture_latency_samples"),
        }
    }

    fn rust() -> Capture {
        Capture {
            start: qa_audio_capture_start,
            read: qa_audio_capture_read,
            stop: qa_audio_capture_stop,
            is_open: qa_audio_capture_is_open,
            channels: qa_audio_capture_channels,
            sample_rate: qa_audio_capture_sample_rate,
            dropped: qa_audio_capture_dropped_frames,
            frames: qa_audio_capture_frames,
            clock: qa_audio_capture_clock,
            latency: qa_audio_capture_latency_samples,
        }
    }

    fn point(&self) -> Option<[i64; 2]> {
        let mut point = [0i64; 2];
        // SAFETY: two values.
        (unsafe { (self.clock)(point.as_mut_ptr()) } == 1).then_some(point)
    }

    fn read(&self, out: &mut [f32], max: i32) -> i32 {
        // SAFETY: `max` is at most `out`'s length.
        unsafe { (self.read)(out.as_mut_ptr(), max) }
    }

    /// What one story tells — and, apart, what came out of the ring.
    fn story(self) -> (Vec<String>, Vec<f32>) {
        let mut seen = Vec::new();
        let mut say = |what: &str, value: String| seen.push(format!("{what}: {value}"));
        let geometry =
            || format!("{} {} {} {}", (self.is_open)(), (self.channels)(), (self.sample_rate)(), (self.latency)());
        say("a point with none open", format!("{:?}", self.point()));
        say("refused", format!("{} {}", (self.start)(0, 1, -1), (self.start)(-1, 1, -1)));
        say("a bogus index", format!("{} {}", (self.start)(48_000, 1, 9_999), (self.is_open)()));
        say("one past the list", format!("{} {}", (self.start)(48_000, 1, 1), (self.is_open)()));
        say("start", (self.start)(44_100, 1, 0).to_string());
        say("geometry", geometry());
        say("again", (self.start)(48_000, 1, -1).to_string());
        let mut drained = Vec::new();
        let mut scratch = vec![0.0f32; 48_000];
        say("nothing asked for", format!("{} {}", self.read(&mut scratch, 0), self.read(&mut scratch, -5)));
        // SAFETY: a null out is refused.
        say("no out", unsafe { (self.read)(ptr::null_mut(), 64) }.to_string());
        let spoke = within(|| self.point().is_some_and(|[frames, _]| frames > 0));
        say("a callback spoke", spoke.to_string());
        let ok = within(|| {
            let read = self.read(&mut scratch, 48_000);
            drained.extend_from_slice(&scratch[..read as usize]);
            drained.len() > 9_600 * 2
        });
        say("drained a fifth of a second", ok.to_string());
        say("whole frames", (drained.len() % 2).to_string());
        say("dropped", (self.dropped)().to_string());
        let point = self.point().expect("a point");
        say("the stair at or past the point", ((self.frames)() >= point[0]).to_string());
        (self.stop)();
        say("stopped", format!("{} {:?} {}", geometry(), self.point(), (self.frames)()));
        say("read stopped", self.read(&mut scratch, 64).to_string());
        say("restart", (self.start)(48_000, 1, -1).to_string());
        say("its own point", self.point().is_none_or(|[frames, _]| frames < 9_600).to_string());
        (self.stop)();
        (self.stop)();
        (seen, drained)
    }
}

// Each step's answer the C's, and — measured of the C 2026-11-07, so held
// once it is gone (connection-round-checklist A) — these.
#[test]
fn the_null_capture_runs_as_the_cs_does() {
    let _serial = serial();
    let (c, rust) = (Capture::c(), Capture::rust());
    let (said, drained) = rust.story();
    let (c_said, c_drained) = c.story();
    assert_eq!(said, c_said);
    assert_eq!(
        said,
        [
            "a point with none open: None",
            "refused: 0 0",
            "a bogus index: 0 0",
            "one past the list: 0 0",
            "start: 44100",
            "geometry: 1 2 44100 1323",
            "again: 0",
            "nothing asked for: 0 0",
            "no out: 0",
            "a callback spoke: true",
            "drained a fifth of a second: true",
            "whole frames: 0",
            "dropped: 0",
            "the stair at or past the point: true",
            "stopped: 0 2 44100 0 None 0",
            "read stopped: 0",
            "restart: 48000",
            "its own point: true",
        ]
    );
    assert!(drained.iter().chain(&c_drained).all(|&sample| sample == 0.0), "the null microphone hears silence");
}

#[test]
fn capture_runs_beside_playback() {
    let _serial = serial();
    assert_eq!(qa_audio_device_open(48_000, 2, 1, -1), 48_000);
    assert_eq!(qa_audio_capture_start(48_000, 1, -1), 48_000);
    assert_eq!((qa_audio_device_is_open(), qa_audio_capture_is_open()), (1, 1));
    qa_audio_capture_stop();
    assert_eq!(qa_audio_device_is_open(), 1, "the output is never touched");
    qa_audio_device_close();
}

// --- Following the system's default (native-to-rust-Q7) -------------------

/// The open that made the device `side` names now.
fn opened(side: fn(&Devices) -> &Option<Opened>) -> Option<u64> {
    side(&devices()).as_ref().map(|opened| opened.open)
}

/// The null device `side` names loses its device, as the system's default
/// changing under it would.
fn lose(side: fn(&Devices) -> &Option<Opened>) {
    let devices = devices();
    let Some(Opened { running: Running::Null(thread), .. }) = side(&devices) else {
        panic!("premise: a null device");
    };
    thread.lose();
}

#[test]
fn an_output_that_lost_its_device_plays_on_from_the_default() {
    let _serial = serial();
    let schedule = Schedule::new();
    // A geometry of its own: the one opened again is the transport's.
    assert_eq!(qa_audio_device_open(44_100, 1, 1, -1), 44_100);
    let latency = qa_audio_device_latency_samples();
    assert!(PLAYBACK.set_schedule(&schedule.clips, &schedule.sources, &schedule.keys));
    qa_audio_device_play(0, 0, 0, 0);
    assert!(within(|| qa_audio_device_position() > 0), "premise: the run plays");
    let lost = opened(|devices| &devices.playback).expect("premise: an output");
    let before = qa_audio_device_position();
    lose(|devices| &devices.playback);
    assert!(within(|| opened(|devices| &devices.playback).is_some_and(|open| open != lost)), "not opened again");
    assert_eq!((qa_audio_device_is_open(), qa_audio_device_is_playing()), (1, 1), "the run plays on…");
    assert!(qa_audio_device_position() >= before, "…from where it was");
    assert!(within(|| qa_audio_device_position() > before + 4_410), "…on the device opened again");
    assert_eq!(qa_audio_device_latency_samples(), latency, "…at the rate it ran at");
    let reopened = opened(|devices| &devices.playback);
    reopen_output(lost);
    assert_eq!(opened(|devices| &devices.playback), reopened, "an ask for an output since opened again does nothing");
    qa_audio_device_close();
    reopen_output(reopened.unwrap());
    assert_eq!((opened(|devices| &devices.playback), qa_audio_device_is_open()), (None, 0), "…nor for one closed");
}

#[test]
fn a_device_chosen_by_name_that_lost_it_is_not_moved() {
    let _serial = serial();
    assert_eq!(qa_audio_device_count(0, 1), 1);
    assert_eq!(qa_audio_device_open(48_000, 2, 1, 0), 48_000);
    let chosen = opened(|devices| &devices.playback);
    qa_audio_device_play(0, 0, 0, 0);
    lose(|devices| &devices.playback);
    // A block in flight when it was lost is handed whole.
    thread::sleep(Duration::from_millis(30));
    let before = qa_audio_device_position();
    thread::sleep(Duration::from_millis(100));
    assert_eq!(opened(|devices| &devices.playback), chosen, "the device chosen stays the one chosen…");
    assert_eq!(qa_audio_device_position(), before, "…and, lost, hands nothing more");
    qa_audio_device_close();
}

#[test]
fn a_device_with_no_default_to_open_again_on_is_closed() {
    let _serial = serial();
    assert_eq!(qa_audio_device_open(48_000, 2, 1, -1), 48_000);
    assert_eq!(qa_audio_capture_start(48_000, 1, -1), 48_000);
    qa_audio_device_play(0, 0, 0, 0);
    let (output, capture) = (opened(|devices| &devices.playback), opened(|devices| &devices.capture));
    devices().context = None;
    reopen_output(output.unwrap());
    reopen_input(capture.unwrap());
    assert_eq!((qa_audio_device_is_open(), qa_audio_device_is_playing(), qa_audio_capture_is_open()), (0, 0, 0));
    assert_eq!((opened(|devices| &devices.playback), opened(|devices| &devices.capture)), (None, None));
}

#[test]
fn a_capture_that_lost_its_device_counts_on_from_the_default() {
    let _serial = serial();
    assert_eq!(qa_audio_capture_start(48_000, 1, -1), 48_000);
    assert!(within(|| qa_audio_capture_frames() > 0), "premise: the take runs");
    let lost = opened(|devices| &devices.capture).expect("premise: a capture");
    let before = qa_audio_capture_frames();
    lose(|devices| &devices.capture);
    assert!(within(|| opened(|devices| &devices.capture).is_some_and(|open| open != lost)), "not opened again");
    let reopened = opened(|devices| &devices.capture);
    assert_eq!(qa_audio_capture_is_open(), 1);
    assert!(qa_audio_capture_frames() >= before, "the take goes on counting…");
    assert!(within(|| qa_audio_capture_frames() > before + 4_800), "…from the device opened again");
    reopen_input(lost);
    assert_eq!(opened(|devices| &devices.capture), reopened, "an ask for a capture since opened again does nothing");
    qa_audio_capture_stop();
}

#[test]
fn only_a_stream_on_the_default_that_lost_its_device_asks_again() {
    use cpal::ErrorKind::{DeviceBusy, DeviceNotAvailable, StreamInvalidated};
    let asked = |follows: bool, kind: cpal::ErrorKind| {
        let asks = Arc::new(AtomicI32::new(0));
        let counted = Arc::clone(&asks);
        let mut errors = crate::backend::on_error(follows.then_some(move || {
            counted.fetch_add(1, SeqCst);
        }));
        errors(kind.into());
        asks.load(SeqCst)
    };
    assert_eq!(asked(true, StreamInvalidated), 1, "the default changed under it");
    assert_eq!(asked(true, DeviceNotAvailable), 1, "no default is left");
    assert_eq!(asked(true, DeviceBusy), 0, "any other error is not a lost device");
    assert_eq!(asked(false, StreamInvalidated), 0, "a device chosen by name stays the one chosen");
}

#[test]
fn a_refused_rate_opens_at_the_devices_own() {
    use crate::backend::at_rate_or_its_own;
    let takes = |taken: i32| move |rate: i32| (rate == taken).then_some(rate);
    assert_eq!(at_rate_or_its_own(48_000, || Some(44_100), takes(48_000)), Some((48_000, 48_000)));
    assert_eq!(at_rate_or_its_own(48_000, || Some(44_100), takes(44_100)), Some((44_100, 44_100)));
    assert_eq!(at_rate_or_its_own(48_000, || Some(48_000), takes(44_100)), None, "its own is the one refused");
    let mut tried = Vec::new();
    at_rate_or_its_own(48_000, || Some(48_000), |rate| {
        tried.push(rate);
        None::<()>
    });
    assert_eq!(tried, [48_000], "…and is not asked again");
    assert_eq!(at_rate_or_its_own(48_000, || None, takes(44_100)), None, "it has none to say");
    let mut tried = Vec::new();
    let refused = at_rate_or_its_own(48_000, || Some(44_100), |rate| {
        tried.push(rate);
        None::<()>
    });
    assert_eq!((refused, &tried[..]), (None, &[48_000, 44_100][..]), "the asked rate first, its own once");
}

// --- The clock ------------------------------------------------------------

#[test]
fn the_clock_is_the_cs_clock() {
    let now: extern "C" fn() -> i64 = c("qa_audio_clock_now_us");
    for _ in 0..1000 {
        let before = now();
        let ours = qa_audio_clock_now_us();
        let after = now();
        assert!(before <= ours && ours <= after, "{before} {ours} {after}");
    }
}

// The OS's monotonic clock in microseconds, asked here through another
// door — std's `Instant` — so held once the C is gone (connection-round-
// checklist A, 관제 판정 ①㉠): what it says passed lies within what
// `Instant` saw pass around it, and it never runs back.
#[test]
fn the_clock_runs_as_the_os_s_monotonic_clock() {
    let started = Instant::now();
    let from = qa_audio_clock_now_us();
    let inner = Instant::now();
    let mut last = from;
    for _ in 0..1000 {
        let now = qa_audio_clock_now_us();
        assert!(now >= last, "{last} then {now}");
        last = now;
    }
    thread::sleep(Duration::from_millis(30));
    let inner = inner.elapsed();
    let to = qa_audio_clock_now_us();
    let outer = started.elapsed();
    let passed = Duration::from_micros((to - from) as u64);
    // A microsecond either way: each clock is cut to its own.
    let micro = Duration::from_micros(1);
    assert!(inner <= passed + micro && passed <= outer + micro, "{passed:?} between {inner:?} and {outer:?}");
}
