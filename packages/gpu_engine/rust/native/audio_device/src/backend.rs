//! The devices a context lists and opens: the OS's, through cpal — or the
//! null backend's, which runs the real callback on a real thread with no
//! hardware: how the transport is tested on a runner with no sound card.
//! The null devices are miniaudio's, as the C opened them: one of each,
//! the default, a period of 10ms and three of them in the buffer.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering::SeqCst};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

/// Which devices a context reaches: the door's `backend` — 1 the null
/// backend, anything else the OS's.
#[derive(Clone, Copy, PartialEq)]
pub(crate) enum Backend {
    System,
    Null,
}

impl Backend {
    pub(crate) fn of(backend: i32) -> Backend {
        if backend == 1 { Backend::Null } else { Backend::System }
    }
}

/// Which way a device's sound goes: the door's `kind` — 1 capture,
/// anything else playback.
#[derive(Clone, Copy, PartialEq)]
pub(crate) enum Direction {
    Playback,
    Capture,
}

impl Direction {
    pub(crate) fn of(kind: i32) -> Direction {
        if kind == 1 { Direction::Capture } else { Direction::Playback }
    }
}

/// One listed device, as `qa_audio_device_describe` tells it.
pub(crate) struct Info {
    pub(crate) name: String,
    pub(crate) is_default: bool,
}

const NULL_PERIOD_MS: i64 = 10;
const NULL_PERIODS: i64 = 3;
const NULL_CHANNELS: i32 = 2;

/// The context (AUDIO-PRO R4): it outlives devices — listing and opening
/// by index both need one — with the list the last count cached, which a
/// describe reads.
pub(crate) struct Context {
    pub(crate) backend: Backend,
    host: Option<cpal::Host>,
    playback: Vec<Info>,
    capture: Vec<Info>,
}

impl Context {
    /// The context of `backend` — or none when the OS's will not come up.
    pub(crate) fn new(backend: Backend) -> Option<Context> {
        let host = match backend {
            Backend::Null => None,
            Backend::System => {
                session::begin()?;
                Some(cpal::default_host())
            }
        };
        Some(Context { backend, host, playback: Vec::new(), capture: Vec::new() })
    }

    /// Lists the devices again, the cache with them; false when the OS
    /// cannot say.
    pub(crate) fn refresh(&mut self) -> bool {
        let Some(host) = &self.host else {
            self.playback = vec![null_info(Direction::Playback)];
            self.capture = vec![null_info(Direction::Capture)];
            return true;
        };
        let (Some(playback), Some(capture)) =
            (system_list(host, Direction::Playback), system_list(host, Direction::Capture))
        else {
            return false;
        };
        self.playback = playback.into_iter().map(|(info, _)| info).collect();
        self.capture = capture.into_iter().map(|(info, _)| info).collect();
        true
    }

    /// The cached list of `direction`.
    pub(crate) fn listed(&self, direction: Direction) -> &[Info] {
        match direction {
            Direction::Playback => &self.playback,
            Direction::Capture => &self.capture,
        }
    }

    /// The device `index` names in a FRESH list — the cache refreshed with
    /// it — or the system's default for none. ⛔A stale or bad index finds
    /// nothing rather than something else: the caller's fallback to the
    /// default is an informed one.
    fn pick(&mut self, direction: Direction, index: Option<usize>) -> Option<Picked> {
        let Some(index) = index else {
            return Some(match &self.host {
                None => Picked::Null,
                Some(host) => Picked::System(match direction {
                    Direction::Playback => host.default_output_device()?,
                    Direction::Capture => host.default_input_device()?,
                }),
            });
        };
        if !self.refresh() || index >= self.listed(direction).len() {
            return None;
        }
        match &self.host {
            None => Some(Picked::Null),
            Some(host) => system_list(host, direction)?.into_iter().nth(index).map(|(_, device)| Picked::System(device)),
        }
    }

    /// A playback device of `channels` at `sample_rate` — or at the
    /// device's own rate when it refuses that one ([`at_rate_or_its_own`]) —
    /// made and not yet started. `make_render` makes the callback that fills
    /// each buffer it asks for, interleaved; `lost` is asked for when the
    /// system's default, opened as `index` none, is lost ([`on_error`]).
    pub(crate) fn build_playback<R: FnMut(&mut [f32]) + Send + 'static>(
        &mut self,
        index: Option<usize>,
        (sample_rate, channels): (i32, i32),
        latency: &'static AtomicI64,
        make_render: impl Fn() -> Option<R>,
        lost: impl Fn() + Clone + Send + 'static,
    ) -> Option<Built> {
        match self.pick(Direction::Playback, index)? {
            Picked::Null => {
                let period = null_period(sample_rate);
                latency.store(period as i64 * NULL_PERIODS, SeqCst);
                let mut render = make_render()?;
                let mut buffer = vec![0.0f32; period * channels as usize];
                let body = move |stop: &AtomicBool| {
                    // Handed up to a full buffer ahead of what the wall has played.
                    paced(stop, sample_rate, period, period as i64 * NULL_PERIODS, || render(&mut buffer));
                };
                Some(Built::null(body, sample_rate, channels))
            }
            Picked::System(device) => {
                let build = |rate: i32| {
                    let config = cpal::StreamConfig {
                        channels: u16::try_from(channels).ok()?,
                        sample_rate: u32::try_from(rate).ok()?,
                        buffer_size: cpal::BufferSize::Default,
                    };
                    let mut render = make_render()?;
                    let callback = move |out: &mut [f32], info: &cpal::OutputCallbackInfo| {
                        let stamp = info.timestamp();
                        report(latency, stamp.playback.duration_since(stamp.callback), rate);
                        render(out);
                    };
                    latency.store(0, SeqCst);
                    let errors = on_error(index.is_none(), lost.clone());
                    device.build_output_stream::<f32, _, _>(config, callback, errors, None).ok()
                };
                let own = || Some(device.default_output_config().ok()?.sample_rate() as i32);
                let (stream, sample_rate) = at_rate_or_its_own(sample_rate, own, build)?;
                latency.fetch_max(stream.buffer_size().map_or(0, i64::from), SeqCst);
                Some(Built { device: Starting::System(stream), sample_rate, channels })
            }
        }
    }

    /// A capture device at `sample_rate` — or at its own rate, as the
    /// playback's — of its own channel count, made and not yet started:
    /// `deliver` takes each buffer it fills, interleaved. `lost` as the
    /// playback's.
    pub(crate) fn build_capture(
        &mut self,
        index: Option<usize>,
        sample_rate: i32,
        latency: &'static AtomicI64,
        deliver: fn(&[f32]),
        lost: impl Fn() + Clone + Send + 'static,
    ) -> Option<Built> {
        match self.pick(Direction::Capture, index)? {
            Picked::Null => {
                let period = null_period(sample_rate);
                latency.store(period as i64 * NULL_PERIODS, SeqCst);
                let buffer = vec![0.0f32; period * NULL_CHANNELS as usize];
                let body = move |stop: &AtomicBool| {
                    // Delivered once the wall has taken it in: silence.
                    paced(stop, sample_rate, period, 0, || deliver(&buffer));
                };
                Some(Built::null(body, sample_rate, NULL_CHANNELS))
            }
            Picked::System(device) => {
                let native = device.default_input_config().ok()?;
                let build = |rate: i32| {
                    let config = cpal::StreamConfig {
                        channels: native.channels(),
                        sample_rate: u32::try_from(rate).ok()?,
                        buffer_size: cpal::BufferSize::Default,
                    };
                    let callback = move |input: &[f32], info: &cpal::InputCallbackInfo| {
                        let stamp = info.timestamp();
                        report(latency, stamp.callback.duration_since(stamp.capture), rate);
                        deliver(input);
                    };
                    latency.store(0, SeqCst);
                    let errors = on_error(index.is_none(), lost.clone());
                    device.build_input_stream::<f32, _, _>(config, callback, errors, None).ok()
                };
                let own = || Some(native.sample_rate() as i32);
                let (stream, sample_rate) = at_rate_or_its_own(sample_rate, own, build)?;
                latency.fetch_max(stream.buffer_size().map_or(0, i64::from), SeqCst);
                Some(Built { device: Starting::System(stream), sample_rate, channels: i32::from(native.channels()) })
            }
        }
    }
}

impl Drop for Context {
    fn drop(&mut self) {
        if self.host.is_some() {
            session::end();
        }
    }
}

/// The stream `build` makes at `asked`, and that rate — or, refused, the
/// one it makes at the device's `own` rate when that is another, and that
/// rate. ↩️miniaudio converted a refused rate itself; cpal does not, so the
/// rate the device runs at goes back to the caller, who conforms to it, as
/// the doors always said a device's rate might (`qa_audio_device_open`).
pub(crate) fn at_rate_or_its_own<T>(
    asked: i32,
    own: impl FnOnce() -> Option<i32>,
    mut build: impl FnMut(i32) -> Option<T>,
) -> Option<(T, i32)> {
    if let Some(built) = build(asked) {
        return Some((built, asked));
    }
    let own = own().filter(|&own| own != asked)?;
    build(own).map(|built| (built, own))
}

/// A stream's error callback. A stream opened on the system's default
/// whose device is lost asks for `lost`: cpal's WASAPI stream never moves
/// to a new default, and says it lost the old one instead — invalidated,
/// or unavailable when no default is left. ⚠️On the device's thread: `lost`
/// waits for nothing.
pub(crate) fn on_error(
    follows: bool,
    lost: impl Fn() + Send + 'static,
) -> impl FnMut(cpal::Error) + Send + 'static {
    use cpal::ErrorKind::{DeviceNotAvailable, StreamInvalidated};
    move |error| {
        if follows && matches!(error.kind(), StreamInvalidated | DeviceNotAvailable) {
            lost();
        }
    }
}

/// F-190 (user 2026-09-27: a Bluetooth headset plays every other app, and
/// this one out of the speaker). iOS keeps ONE audio session per app, and
/// the C set it to PlayAndRecord — the voice take needs the input — with
/// DefaultToSpeaker and AllowBluetoothA2DP: under PlayAndRecord a headset
/// is an allowed output only when the session says so. cpal sets no
/// category at all (native-to-rust-Q7 ②), so the context does, and
/// activates the session as miniaudio's did; elsewhere there is none.
#[cfg(target_os = "ios")]
mod session {
    use objc2_avf_audio::{AVAudioSession, AVAudioSessionCategoryOptions, AVAudioSessionCategoryPlayAndRecord};

    /// The session set and active — or none, and the OS's context does not
    /// come up, as the C's did not.
    pub(super) fn begin() -> Option<()> {
        // SAFETY: the app's one session, and a category the framework
        // defines.
        unsafe {
            let session = AVAudioSession::sharedInstance();
            let options =
                AVAudioSessionCategoryOptions::DefaultToSpeaker | AVAudioSessionCategoryOptions::AllowBluetoothA2DP;
            session.setCategory_withOptions_error(AVAudioSessionCategoryPlayAndRecord?, options).ok()?;
            session.setActive_error(true).ok()
        }
    }

    pub(super) fn end() {
        // SAFETY: as above.
        let _ = unsafe { AVAudioSession::sharedInstance().setActive_error(false) };
    }
}

#[cfg(not(target_os = "ios"))]
mod session {
    pub(super) fn begin() -> Option<()> {
        Some(())
    }

    pub(super) fn end() {}
}

enum Picked {
    Null,
    System(cpal::Device),
}

/// A device made: the geometry it runs at, and its callback not yet
/// asked to run.
pub(crate) struct Built {
    device: Starting,
    pub(crate) sample_rate: i32,
    pub(crate) channels: i32,
}

enum Starting {
    Null(Box<dyn FnOnce() -> Option<NullThread> + Send>),
    System(cpal::Stream),
}

impl Built {
    fn null(body: impl FnOnce(&AtomicBool) + Send + 'static, sample_rate: i32, channels: i32) -> Built {
        let start = move || NullThread::spawn(body);
        Built { device: Starting::Null(Box::new(start)), sample_rate, channels }
    }

    /// Starts it — or none, and it is gone.
    pub(crate) fn start(self) -> Option<Running> {
        match self.device {
            Starting::Null(start) => start().map(Running::Null),
            Starting::System(stream) => stream.play().ok().map(|()| Running::System(stream)),
        }
    }
}

/// A device running. ⚠️Dropped, it stops, and once the drop returns its
/// callback can no longer run — the C's ma_device_uninit, which joins the
/// device thread: cpal's streams join theirs or stop their unit.
#[expect(dead_code, reason = "held for its drop, which unmakes the device")]
pub(crate) enum Running {
    Null(NullThread),
    System(cpal::Stream),
}

/// The null backend's device thread.
pub(crate) struct NullThread {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl NullThread {
    fn spawn(body: impl FnOnce(&AtomicBool) + Send + 'static) -> Option<NullThread> {
        let stop = Arc::new(AtomicBool::new(false));
        let seen = Arc::clone(&stop);
        let thread = thread::Builder::new().name("null audio device".into()).spawn(move || body(&seen)).ok()?;
        Some(NullThread { stop, thread: Some(thread) })
    }
}

impl Drop for NullThread {
    fn drop(&mut self) {
        self.stop.store(true, SeqCst);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

fn null_info(direction: Direction) -> Info {
    let name = match direction {
        Direction::Playback => "NULL Playback Device",
        Direction::Capture => "NULL Capture Device",
    };
    Info { name: name.to_owned(), is_default: true }
}

fn null_period(sample_rate: i32) -> usize {
    (i64::from(sample_rate) * NULL_PERIOD_MS / 1000) as usize
}

/// Runs `tick` once a `period`, on the wall: each `period` frames ticked no
/// further than `ahead` frames past what the wall has run — until `stop`.
fn paced(stop: &AtomicBool, sample_rate: i32, period: usize, ahead: i64, mut tick: impl FnMut()) {
    let started = Instant::now();
    let mut ticked = 0i64;
    while !stop.load(SeqCst) {
        let ran = frames_in(started.elapsed(), sample_rate);
        if ticked + period as i64 <= ran + ahead {
            tick();
            ticked += period as i64;
        } else {
            thread::sleep(Duration::from_millis(1));
        }
    }
}

/// THE DEVICE'S LATENCY, in frames: how long after its callback what it
/// hands is heard — or before it what it is handed was taken in — the
/// span the picture is pulled forward by. The LARGEST the stream has
/// reported, not the latest: the first callbacks find the buffer empty and
/// report too little, and a figure that moved at every callback would move
/// the picture with it; the largest is bounded by the buffer. Seeded with
/// a callback's frames until one has spoken. ↩️miniaudio's period ×
/// periods — the buffer — fixed at open.
fn report(latency: &AtomicI64, span: Duration, sample_rate: i32) {
    latency.fetch_max(frames_in(span, sample_rate), SeqCst);
}

/// The frames `span` lasts at `sample_rate`.
fn frames_in(span: Duration, sample_rate: i32) -> i64 {
    (span.as_nanos() * sample_rate as u128 / 1_000_000_000) as i64
}

/// The OS's devices of `direction`, each with what describe tells of it —
/// or none when the OS cannot say.
fn system_list(host: &cpal::Host, direction: Direction) -> Option<Vec<(Info, cpal::Device)>> {
    let (devices, default) = match direction {
        Direction::Playback => (host.output_devices().ok()?.collect::<Vec<_>>(), host.default_output_device()),
        Direction::Capture => (host.input_devices().ok()?.collect::<Vec<_>>(), host.default_input_device()),
    };
    let default = default.and_then(|device| device.id().ok());
    let listed = devices
        .into_iter()
        .map(|device| {
            let is_default = default.is_some() && device.id().ok() == default;
            let name = device.description().map_or_else(|_| String::new(), |description| description.name().to_owned());
            (Info { name, is_default }, device)
        })
        .collect();
    Some(listed)
}
