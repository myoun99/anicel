//! The output device and the transport, and the capture beside it —
//! `qa_audio_device.c` in Rust (native-to-rust, 타임라인/콘티). The OS's
//! sound comes through cpal (native-to-rust-Q7, user 2026-11-06); the
//! exports keep the C's names and contracts (`qa_audio_device.dart` binds
//! them unchanged), and until the connection round the C is the answer key.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod backend;
mod buffer;
mod capture;
mod clock;
mod transport;
#[cfg(test)]
mod tests;

use std::ffi::c_char;
use std::slice;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering::SeqCst};
use std::sync::{Mutex, MutexGuard, PoisonError};
use std::thread;

use audio_mix::{Clip, EnvelopeKey, Source, slice_or_empty};

use backend::{Backend, Built, Context, Direction, Running};
use capture::Capture;
use transport::{MAX_BLOCK, Transport};

static PLAYBACK: Transport = Transport::new();
static CAPTURE: Capture = Capture::new();
static PLAYBACK_LATENCY: AtomicI64 = AtomicI64::new(0);
static CAPTURE_LATENCY: AtomicI64 = AtomicI64::new(0);

/// 🚨A DEVICE IS MADE, UNMADE AND LISTED ONE CALL AT A TIME
/// (play-press-first-frame-stall, 10-15). The output opens on a worker, off
/// the thread that draws, while that thread may list the outputs, open the
/// microphone or hand over a schedule — so every door that makes, unmakes
/// or lists a device holds this, and so does the schedule's, whose slots a
/// close frees. ⛔Never a callback and never a transport field: those are
/// atomics, read on the realtime thread, which must never wait.
static DEVICES: Mutex<Devices> = Mutex::new(Devices { context: None, playback: None, capture: None });

struct Devices {
    context: Option<Context>,
    playback: Option<Opened>,
    capture: Option<Opened>,
}

/// A device running, and the open that made it.
struct Opened {
    #[expect(dead_code, reason = "held for its drop, which unmakes the device")]
    running: Running,
    open: u64,
}

/// Each open of a device, the output's or the capture's — again on a new
/// default too: what a lost device's ask names, so an ask for one since
/// opened again or closed finds it gone.
static OPENS: AtomicU64 = AtomicU64::new(0);

fn devices() -> MutexGuard<'static, Devices> {
    DEVICES.lock().unwrap_or_else(PoisonError::into_inner)
}

impl Devices {
    /// The context of `backend`, made when there is none of it — but
    /// ⛔never yanked out from under an open output: then the one there is.
    fn context(&mut self, backend: Backend) -> Option<&mut Context> {
        let matches = self.context.as_ref().is_some_and(|context| context.backend == backend);
        if !matches && self.playback.is_none() {
            // The old one ends before the new one begins: on iOS both are
            // the app's one session.
            self.context = None;
            self.context = Context::new(backend);
        }
        self.context.as_mut()
    }
}

/// The output's callback for `channels`: the transport rendered through a
/// mix bus of its own — or none when the memory is not there.
fn playback_render(channels: i32) -> Option<impl FnMut(&mut [f32]) + Send + 'static> {
    let lanes = channels as usize;
    let mut bus = Vec::new();
    bus.try_reserve_exact(MAX_BLOCK * lanes).ok()?;
    bus.resize(MAX_BLOCK * lanes, 0.0);
    Some(move |out: &mut [f32]| PLAYBACK.render(out, lanes, &mut bus, &transport::mix_slot))
}

/// The output of `index` at `(sample_rate, channels)`, made and not yet
/// started, as open `open`.
fn build_output(context: &mut Context, index: Option<usize>, geometry: (i32, i32), open: u64) -> Option<Built> {
    let lost = move || follow_default(move || reopen_output(open));
    context.build_playback(index, geometry, &PLAYBACK_LATENCY, || playback_render(geometry.1), lost)
}

/// The capture of `index` at `sample_rate`, made and not yet started, as
/// open `open`.
fn build_input(context: &mut Context, index: Option<usize>, sample_rate: i32, open: u64) -> Option<Built> {
    let lost = move || follow_default(move || reopen_input(open));
    context.build_capture(index, sample_rate, &CAPTURE_LATENCY, |input| CAPTURE.deliver(input), lost)
}

/// 🚨A DEVICE OPENED ON THE SYSTEM'S DEFAULT FOLLOWS IT
/// (native-to-rust-Q7 ①, user 2026-11-06). miniaudio moved such a device
/// to each new default; cpal's stays on the one it opened and says it lost
/// it (`backend::on_error`). So the lost device is opened again on the
/// default — on a thread of its own, never the device's, which waits for
/// nothing — with the transport or the ring untouched: what played plays
/// on where it was, and a take goes on counting.
fn follow_default(reopen: impl FnOnce() + Send + 'static) {
    thread::spawn(reopen);
}

/// The output open `open` made, opened again on the system's default.
/// ⛔Only at the rate and channels the transport runs at — Dart conformed
/// every sound to them: a default that will not take them closes the
/// output, which Dart's next arm opens again, and conforms to. An ask for
/// an output since opened again or closed does nothing.
fn reopen_output(open: u64) {
    let mut devices = devices();
    let Some(lost) = devices.playback.take_if(|opened| opened.open == open) else {
        return;
    };
    let geometry = (PLAYBACK.sample_rate(), PLAYBACK.channels());
    let next = OPENS.fetch_add(1, SeqCst) + 1;
    let built = devices.context.as_mut().and_then(|context| build_output(context, None, geometry, next));
    // The lost device's callback ends before the new one's starts: two
    // would both move the transport.
    drop(lost);
    match built.filter(|built| (built.sample_rate, built.channels) == geometry).and_then(Built::start) {
        Some(running) => devices.playback = Some(Opened { running, open: next }),
        None => PLAYBACK.close(|| {}),
    }
}

/// The capture open `open` made, opened again on the system's default —
/// as the output's, at the ring's rate and channels or not at all.
fn reopen_input(open: u64) {
    let mut devices = devices();
    let Some(lost) = devices.capture.take_if(|opened| opened.open == open) else {
        return;
    };
    let geometry = (CAPTURE.sample_rate(), CAPTURE.channels());
    let next = OPENS.fetch_add(1, SeqCst) + 1;
    let built = devices.context.as_mut().and_then(|context| build_input(context, None, geometry.0, next));
    drop(lost);
    match built.filter(|built| (built.sample_rate, built.channels) == geometry).and_then(Built::start) {
        Some(running) => devices.capture = Some(Opened { running, open: next }),
        None => CAPTURE.close(),
    }
}

/// The device index a door names: -1 (or below) for the system's default.
fn index_of(device_index: i32) -> Option<usize> {
    usize::try_from(device_index).ok()
}

/// A clock's point into `out2` — `[0]` what it counts, `[1]` when — and
/// whether there was one.
///
/// # Safety
/// `out2` is null or points at two values.
unsafe fn give_point(point: Option<(i64, i64)>, out2: *mut i64) -> i32 {
    let Some((count, time_us)) = point else {
        return 0;
    };
    // SAFETY: the caller's contract.
    unsafe {
        *out2 = count;
        *out2.add(1) = time_us;
    }
    1
}

// --- The device's own PCM -------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_buffer_new(floats: i64) -> *mut f32 {
    buffer::new(floats)
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_buffer_retain(samples: *mut f32) -> *mut f32 {
    buffer::retain(samples)
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_buffer_release(samples: *mut f32) {
    buffer::release(samples)
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_buffer_holds(samples: *mut f32) -> i32 {
    buffer::holds(samples)
}

// --- Listing --------------------------------------------------------------

/// Lists the devices again and how many `kind` has (0 playback, 1
/// capture), or -1 when the context cannot ask. Call before
/// [`qa_audio_device_describe`], which reads the list this caches.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_count(kind: i32, backend: i32) -> i32 {
    let mut devices = devices();
    let Some(context) = devices.context(Backend::of(backend)) else {
        return -1;
    };
    if !context.refresh() {
        return -1;
    }
    context.listed(Direction::of(kind)).len() as i32
}

/// Device `index`'s UTF-8 name into `out_name`, NUL-terminated and cut to
/// `capacity`, and whether it is the system's default: the name's byte
/// length, or -1 for a bad index or capacity.
///
/// # Safety
/// `out_name` is null or points at `capacity` bytes; `out_is_default` is
/// null or points at one value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_device_describe(
    kind: i32,
    index: i32,
    out_name: *mut c_char,
    capacity: i32,
    out_is_default: *mut i32,
) -> i32 {
    let devices = devices();
    let Some(context) = &devices.context else {
        return -1;
    };
    let listed = context.listed(Direction::of(kind));
    let Some(info) = usize::try_from(index).ok().and_then(|index| listed.get(index)) else {
        return -1;
    };
    if out_name.is_null() || capacity <= 1 {
        return -1;
    }
    let name = info.name.as_bytes();
    let length = name.iter().take(capacity as usize - 1).take_while(|&&byte| byte != 0).count();
    // SAFETY: the caller's contract; `length` < `capacity`.
    unsafe {
        let out = slice::from_raw_parts_mut(out_name.cast::<u8>(), length + 1);
        out[..length].copy_from_slice(&name[..length]);
        out[length] = 0;
        if !out_is_default.is_null() {
            *out_is_default = i32::from(info.is_default);
        }
    }
    length as i32
}

// --- The output -----------------------------------------------------------

/// Opens the output: `backend` 0 the OS's, 1 the null backend;
/// `device_index` from the last listing, -1 the system's default — a stale
/// or bad index FAILS rather than opening something else. The device's
/// sample rate — the one asked for, or the device's own when it refuses
/// that one — or 0 when it did not open. Open already, the open one's.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_open(sample_rate: i32, channels: i32, backend: i32, device_index: i32) -> i32 {
    let mut devices = devices();
    if devices.playback.is_some() {
        return PLAYBACK.sample_rate();
    }
    if sample_rate <= 0 || channels <= 0 || channels > 8 {
        return 0;
    }
    let Some(context) = devices.context(Backend::of(backend)) else {
        return 0;
    };
    let open = OPENS.fetch_add(1, SeqCst) + 1;
    let Some(built) = build_output(context, index_of(device_index), (sample_rate, channels), open) else {
        return 0;
    };
    PLAYBACK.open(built.sample_rate, built.channels);
    let Some(running) = built.start() else {
        PLAYBACK.not_started();
        return 0;
    };
    devices.playback = Some(Opened { running, open });
    PLAYBACK.sample_rate()
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_close() {
    let mut devices = devices();
    if let Some(opened) = devices.playback.take() {
        PLAYBACK.close(|| drop(opened));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_is_open() -> i32 {
    i32::from(PLAYBACK.is_open())
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_sample_rate() -> i32 {
    PLAYBACK.sample_rate()
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_channels() -> i32 {
    PLAYBACK.channels()
}

/// The output's own latency in samples — what the picture is pulled
/// forward by so it matches what is heard; what this cannot account for is
/// the residual the user's A/V offset removes.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_latency_samples() -> i64 {
    if !PLAYBACK.is_open() {
        return 0;
    }
    PLAYBACK_LATENCY.load(SeqCst)
}

// --- The transport --------------------------------------------------------

/// Replaces the schedule (see `Transport::set_schedule`): 1, or 0 for a
/// negative count or a source that plays no buffer of its whole length.
///
/// # Safety
/// Each pointer is null or points at its count of values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_device_set_schedule(
    clips: *const Clip,
    clip_count: i32,
    sources: *const Source,
    source_count: i32,
    envelope_keys: *const EnvelopeKey,
    envelope_key_count: i32,
) -> i32 {
    let _devices = devices();
    if clip_count < 0 || source_count < 0 || envelope_key_count < 0 {
        return 0;
    }
    // SAFETY: the caller's contract.
    let (clips, sources, keys) = unsafe {
        (
            slice_or_empty(clips, clip_count),
            slice_or_empty(sources, source_count),
            slice_or_empty(envelope_keys, envelope_key_count),
        )
    };
    i32::from(PLAYBACK.set_schedule(clips, sources, keys))
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_play(start_sample: i64, stop_sample: i64, looping: i32, lead_samples: i64) -> i32 {
    PLAYBACK.play(start_sample, stop_sample, looping != 0, lead_samples)
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_peak(channel: i32) -> f64 {
    PLAYBACK.peak(channel)
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_stop() {
    PLAYBACK.stop()
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_stop_run(run: i32) {
    PLAYBACK.stop_run(run)
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_is_playing() -> i32 {
    i32::from(PLAYBACK.is_playing())
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_position() -> i64 {
    PLAYBACK.position()
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_device_seek(sample: i64) {
    PLAYBACK.seek(sample)
}

/// The latest point of the clock's line into `out2` — `[0]` the samples
/// handed when that callback returned, `[1]` when it was asked for them,
/// on [`qa_audio_clock_now_us`]'s clock: 1, or 0 when there is none yet.
///
/// # Safety
/// `out2` is null or points at two values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_device_clock(out2: *mut i64) -> i32 {
    if out2.is_null() {
        return 0;
    }
    // SAFETY: the caller's contract.
    unsafe { give_point(PLAYBACK.clock(), out2) }
}

/// The time now on the clock the lines' points are stamped with.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_clock_now_us() -> i64 {
    clock::now_us()
}

// --- Capture --------------------------------------------------------------

/// Opens the capture at `sample_rate` — the project's, so what lands in
/// the ring needs no conform, unless the device refuses it and runs at its
/// own — of the device's own channel count (read
/// [`qa_audio_capture_channels`] after), and starts it delivering into the
/// ring. `device_index` as the output's. The delivered rate, or 0 — which
/// on macOS, iOS and Android includes "no microphone permission".
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_capture_start(sample_rate: i32, backend: i32, device_index: i32) -> i32 {
    let mut devices = devices();
    if CAPTURE.is_open() || sample_rate <= 0 {
        return 0;
    }
    let Some(context) = devices.context(Backend::of(backend)) else {
        return 0;
    };
    let open = OPENS.fetch_add(1, SeqCst) + 1;
    let Some(built) = build_input(context, index_of(device_index), sample_rate, open) else {
        return 0;
    };
    if !CAPTURE.open(built.channels, built.sample_rate) {
        return 0;
    }
    let Some(running) = built.start() else {
        CAPTURE.close();
        return 0;
    };
    devices.capture = Some(Opened { running, open });
    CAPTURE.sample_rate()
}

/// Drains up to `max_floats` from the ring into `out`: the floats copied.
/// The control thread's alone — the far end from the callback.
///
/// # Safety
/// `out` is null or points at `max_floats` values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_capture_read(out: *mut f32, max_floats: i32) -> i32 {
    if out.is_null() || max_floats <= 0 {
        return 0;
    }
    // SAFETY: the caller's contract.
    let out = unsafe { slice::from_raw_parts_mut(out, max_floats as usize) };
    CAPTURE.read(out) as i32
}

/// Stops the capture: once its device is unmade its callback can no
/// longer run, and the ring goes. Read the tail BEFORE.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_capture_stop() {
    let mut devices = devices();
    if let Some(opened) = devices.capture.take() {
        drop(opened);
        CAPTURE.close();
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_capture_is_open() -> i32 {
    i32::from(CAPTURE.is_open())
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_capture_channels() -> i32 {
    CAPTURE.channels()
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_capture_sample_rate() -> i32 {
    CAPTURE.sample_rate()
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_capture_dropped_frames() -> i64 {
    CAPTURE.dropped_frames()
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_capture_frames() -> i64 {
    CAPTURE.frames()
}

/// The latest point of the capture's line into `out2` — `[0]` the frames
/// the ring had been given when that callback returned, `[1]` when it was
/// asked for them: 1, or 0 with none open or none spoken yet.
///
/// # Safety
/// `out2` is null or points at two values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_capture_clock(out2: *mut i64) -> i32 {
    if out2.is_null() {
        return 0;
    }
    // SAFETY: the caller's contract.
    unsafe { give_point(CAPTURE.clock(), out2) }
}

/// The capture's own buffering in samples — how far behind now the newest
/// delivered sample is. NOT applied here: the recorder decides what
/// alignment means.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_capture_latency_samples() -> i64 {
    if !CAPTURE.is_open() {
        return 0;
    }
    CAPTURE_LATENCY.load(SeqCst)
}
