//! The wgpu device every kernel runs on, opened on the adapter Flutter
//! draws with so a shared texture lives on the GPU that reads it.

use std::cell::Cell;
use std::collections::HashMap;
use std::sync::{mpsc, Arc, Condvar, Mutex, OnceLock, PoisonError};
use std::time::Duration;

use crate::{copy_out, fail, last_error, platform};

/// How long [`Engine::wait`] stays in the driver before it answers that the
/// GPU did not finish: a failure with a name rather than a screen that
/// stands still (관제 2026-11-08, after a pin stood 13 minutes in this wait:
/// 「멈춘 화면보다 이름 있는 실패」).
// ⏳My number, not measured: far past a screen frame's milliseconds, and
// long enough that a heavy export frame does not fail falsely. To be settled
// from the Surface's slowest waits, as the reading watch's three seconds were.
const WAIT_LIMIT: Duration = Duration::from_secs(30);

/// One wgpu device and its queue.
#[derive(Clone)]
pub struct Engine {
    /// Kept for Android's window surfaces, which must come from the
    /// instance the adapter came from.
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    pub(crate) instance: wgpu::Instance,
    pub(crate) adapter: wgpu::Adapter,
    pub(crate) device: wgpu::Device,
    pub(crate) queue: Queue,
    /// What [`Engine::wait`] polls on.
    thread: EngineThread,
    /// Where a kernel's compile enters the driver: a thread of its own, so
    /// that seconds of one made ahead of its first use hold up no frame's
    /// submit behind them on `thread` (🔬the blur brush's ten pipelines,
    /// 10.2 s on the main PC's RTX 4080 with eighteen test files running,
    /// 2026-11-10; 1.2 to 2.5 s each by strips).
    compiling: EngineThread,
    /// Every kernel the engine has compiled ([`Kernels`]).
    pub(crate) kernels: Kernels,
    /// When what is compiled apart may take the compiler ([`Apart`]).
    pub(crate) apart: Apart,
    /// How fast the device spends a plugin's share, once a plugin first
    /// ran (kernels/plugin's `Pace`).
    pub(crate) plugin_pace: OnceLock<crate::kernels::plugin::Pace>,
    /// What the device refused that no wait has told yet, and whether it
    /// is gone ([`Refusals`]).
    refusals: Refusals,
}

/// What the engine's device refused that no wait has told yet, and whether
/// the device is gone.
///
/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — a device the driver took away (a reset, an update, a wake
/// from sleep) is not the app's end. 🔬wgpu 30.0.1, DX12, RTX 4080,
/// 2026-11-11, a device destroyed in a test of this crate: the word that it
/// was lost came at the next poll; a wait answered that the GPU was done;
/// a buffer made, a write, a submit and a compile each returned as if they
/// had worked; and two things panicked — wgpu's `create_buffer_init`
/// ([`Engine::filled`] is why nothing calls it) and wgpu's own handler of
/// an error no scope catches, at the first copy that named a buffer of the
/// lost device. A panic on the caller's thread crosses `extern "C"`, and
/// that ends the process (↩️as every such error did till 2026-11-11, with
/// the last save all that was left).
///
/// So an error no scope catches is NOTED here, and the next wait fails by
/// it ([`Engine::wait`]) — the law a submit on a thread that is gone
/// already keeps ([`Queue::submit`]). A device that is gone fails every
/// wait from then on. ⚠️What ends without a wait is told nothing: the
/// tests' engine panics as wgpu did (`testing::first_engine`), and the
/// app's tests ask at each test's end ([`gpu_engine_noted`]).
#[derive(Clone, Default)]
pub(crate) struct Refusals(Arc<Mutex<Refused>>);

#[derive(Default)]
struct Refused {
    /// Why the device is gone, once it is.
    gone: Option<String>,
    /// The first error no scope caught since a wait last told one.
    noted: Option<String>,
}

impl Refusals {
    fn kept(&self) -> std::sync::MutexGuard<'_, Refused> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// The device is gone, by `why` — the first word of it stays.
    fn lose(&self, why: String) {
        self.kept().gone.get_or_insert(why);
    }

    /// An error no scope caught: kept where it is the first since one was
    /// told.
    fn note(&self, error: String) {
        self.kept().noted.get_or_insert(error);
    }

    /// Whether the device is gone.
    fn gone(&self) -> bool {
        self.kept().gone.is_some()
    }

    /// The error noted and not yet told, if any.
    #[cfg(test)]
    fn noted(&self) -> Option<String> {
        self.kept().noted.clone()
    }

    /// The error noted, taken by what asks in a wait's place: no wait fails
    /// by it after.
    fn taken(&self) -> Option<String> {
        self.kept().noted.take()
    }

    /// Fails by what the device refused: that it is gone, or else the error
    /// noted — told here, and noted no more.
    fn told(&self) -> Option<()> {
        let mut kept = self.kept();
        if let Some(why) = &kept.gone {
            return fail(format!("the graphics device is gone: {why}"));
        }
        match kept.noted.take() {
            Some(error) => fail(format!("the device refused: {error}")),
            None => Some(()),
        }
    }
}

/// What one of the engine's kernels is compiled of: its sources joined, its
/// entry point, the `override` constants set — each value's bits — and
/// whether its workgroup memory is zeroed.
#[derive(Clone, PartialEq, Eq, Hash)]
pub(crate) struct KernelSource {
    pub(crate) source: String,
    pub(crate) entry: String,
    pub(crate) constants: Vec<(String, u64)>,
    pub(crate) zeroed: bool,
}

/// The engine's own kernels, each compiled once whoever asks, and as many
/// as ask at once: a kernel is what it is compiled of ([`KernelSource`]),
/// and a pipeline is any caller's to run — each binds a group of its own.
///
/// 🗣️관제 2026-11-11 04:09 (gpu-canonical-store ④): 「첫 획 · 첫
/// 들어올리기에서도 UI 스레드가 직접 하는 커널 컴파일 0」. 🔬Surface Pro 11,
/// 2026-11-11: a first stroke 1.6–2.0 s after the canvas came found the
/// list the app compiles ahead not through, and the UI thread compiled the
/// stroke's three again, in turn with the list's — 1.8–2.0 s of a stopped
/// UI; `write_changed` was compiled for a stroke and again for a stamp's
/// landing. ↩️Each owner compiled its own till then, so what was compiling
/// off the isolate was no one else's to wait for.
///
/// Kept as long as the engine: there are as many as the crate has kernels
/// and the composite has passes, which it kept already.
#[derive(Clone, Default)]
pub(crate) struct Kernels(Arc<Mutex<HashMap<KernelSource, Arc<OnceLock<wgpu::ComputePipeline>>>>>);

impl Kernels {
    /// Where the kernel of `source` is, or will be: made by the first to
    /// fill it, and waited for there by whoever comes while it is made.
    pub(crate) fn slot(&self, source: &KernelSource) -> Arc<OnceLock<wgpu::ComputePipeline>> {
        let mut kept = self.0.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some(slot) = kept.get(source) {
            return Arc::clone(slot);
        }
        Arc::clone(kept.entry(source.clone()).or_default())
    }

    /// Test seam: none kept, as a launch finds the engine — what holds a
    /// kernel keeps it, and the next asked for is compiled.
    pub(crate) fn forget(&self) {
        self.0.lock().unwrap_or_else(PoisonError::into_inner).clear();
    }
}

/// When what the engine compiles apart may take the compiler: a
/// composite's own passes, which no one waits for — a plan runs on the pass
/// that takes any till its own is there (`Composite::pass`). Not while a
/// hold is on ([`gpu_engine_apart_hold`]): the app holds while it compiles
/// ahead what a hand on the canvas waits for.
///
/// 🗣️관제 2026-11-11 06:00 (gpu-canonical-store ④): 「선은 첫 획 · 첫
/// 들어올리기의 멈춤 자체다 … 컴파일 차례 안의 순서를 요청자 불문으로
/// 매겨라 — 손이 쓰는 커널 → composite 전용 패스」. 🔬Surface Pro 11,
/// 2026-11-11 05:59: each of a stroke's kernels compiled in 9–200 ms and
/// waited 0.6–1.3 s for its turn, an own pass of 1.0–1.15 s between each
/// two — a stroke ready 2.2–2.6 s after the canvas came and a lift 3.5 s,
/// where the four sets a hand needs compile in 0.96–1.22 s together.
///
/// ⛔Not an order in the compiling thread's queue: who compiles ahead asks
/// for one kernel at a time, and a pass asked for meanwhile would take the
/// turn between two of them — a second that cannot be cut short.
#[derive(Clone, Default)]
pub(crate) struct Apart(Arc<(Mutex<ApartHolds>, Condvar)>);

/// How many hold what is compiled apart, and — for the tests — how many
/// wait for them.
#[derive(Default)]
struct ApartHolds {
    holds: usize,
    #[cfg(test)]
    waiting: usize,
}

impl Apart {
    fn holds(&self) -> std::sync::MutexGuard<'_, ApartHolds> {
        self.0.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// One more hold: what is compiled apart waits till each is let go.
    pub(crate) fn hold(&self) {
        self.holds().holds += 1;
    }

    /// One hold let go; with the last, what waited goes on.
    pub(crate) fn let_go(&self) {
        let mut held = self.holds();
        held.holds = held.holds.saturating_sub(1);
        self.0.1.notify_all();
    }

    /// Returns once no hold is on.
    pub(crate) fn wait(&self) {
        let mut held = self.holds();
        #[cfg(test)]
        {
            held.waiting += 1;
        }
        while held.holds > 0 {
            held = self.0.1.wait(held).unwrap_or_else(PoisonError::into_inner);
        }
        #[cfg(test)]
        {
            held.waiting -= 1;
        }
    }

    /// How many holds are on.
    pub(crate) fn held(&self) -> usize {
        self.holds().holds
    }

    /// How many wait for the holds to be let go.
    #[cfg(test)]
    pub(crate) fn waiting(&self) -> usize {
        self.holds().waiting
    }
}

/// A turn at the device's shader compiler: what [`Engine::compiling`] runs
/// is handed one, and a compile asks for it (`kernels::shared`, `compiled`)
/// — so no two are in the compiler at once, whatever threads ask.
///
/// ⛔One at a time: what DXC makes is not thread-safe — 「objects created by
/// DxcCreateInstance aren't thread-safe」 (DXC wiki, "Using dxc.exe and
/// dxcompiler.dll") — and wgpu-hal 30 compiles on the device's one
/// `IDxcCompiler3` from whatever thread asks, with no lock
/// (dx12/shader_compilation.rs, `CompilerDynamicDxc`). ↩️A plugin's compile
/// ran on its own thread beside the engine's till 2026-11-11, the one
/// compiler under both whenever a plugin was compiled while a kernel of
/// the engine's was; no fault has been traced to it.
pub(crate) struct CompilerTurn(());

/// The queue the kernels submit to, whose submits enter the driver on the
/// engine's thread ([`EngineThread`]) — ⛔the `wgpu::Queue` stays private
/// to this type so that no kernel can submit on its caller's.
#[derive(Clone)]
pub(crate) struct Queue {
    queue: wgpu::Queue,
    thread: EngineThread,
}

impl Queue {
    /// Submits `buffers` and returns once the driver has them, so what the
    /// caller writes next goes after them, as on one thread. A thread that
    /// is gone is the next wait's error.
    pub(crate) fn submit(&self, buffers: impl IntoIterator<Item = wgpu::CommandBuffer>) {
        let (queue, buffers): (_, Vec<_>) = (self.queue.clone(), buffers.into_iter().collect());
        let _ = self.thread.run(move || {
            queue.submit(buffers);
        });
    }

    pub(crate) fn write_buffer(&self, buffer: &wgpu::Buffer, offset: wgpu::BufferAddress, data: &[u8]) {
        self.queue.write_buffer(buffer, offset, data);
    }

    #[cfg(target_os = "android")]
    pub(crate) fn present(&self, texture: wgpu::SurfaceTexture) {
        self.queue.present(texture);
    }

    pub(crate) fn write_texture(
        &self,
        texture: wgpu::TexelCopyTextureInfo<'_>,
        data: &[u8],
        layout: wgpu::TexelCopyBufferLayout,
        size: wgpu::Extent3d,
    ) {
        self.queue.write_texture(texture, data, layout, size);
    }

    #[cfg(test)]
    pub(crate) fn on_submitted_work_done(&self, callback: impl FnOnce() + Send + 'static) {
        self.queue.on_submitted_work_done(callback);
    }
}

impl Engine {
    /// Opens on the adapter whose LUID is `luid`.
    fn open(luid: u64) -> Option<Self> {
        let instance = platform::instance();
        let adapter = platform::adapters(&instance)
            .into_iter()
            .find(|adapter| platform::adapter_luid(adapter) == Some(luid));
        match adapter {
            Some(adapter) => Self::on(instance, adapter),
            None => fail(format!("no adapter has LUID {luid:#x}")),
        }
    }

    /// Opens on the platform's only adapter; with none or several, which
    /// one Flutter draws with is not known.
    fn open_sole() -> Option<Self> {
        let instance = platform::instance();
        let mut adapters = platform::adapters(&instance);
        if adapters.len() != 1 {
            return fail(format!("{} adapters, not one", adapters.len()));
        }
        Self::on(instance, adapters.remove(0))
    }

    /// Opens on the platform's first adapter: the tests', cargo's and
    /// `flutter test`'s alike, where no Flutter names one.
    pub(crate) fn open_first() -> Option<Self> {
        let instance = platform::instance();
        match platform::adapters(&instance).into_iter().next() {
            Some(adapter) => Self::on(instance, adapter),
            None => fail("no adapter"),
        }
    }

    pub(crate) fn on(instance: wgpu::Instance, adapter: wgpu::Adapter) -> Option<Self> {
        let required_features = adapter.features() & wgpu::Features::BGRA8UNORM_STORAGE;
        let request = adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("gpu_engine"),
            required_features,
            required_limits: most_storage(&adapter),
            ..Default::default()
        });
        match pollster::block_on(request) {
            Ok((device, queue)) => {
                let thread = EngineThread::start()?;
                let compiling = EngineThread::start()?;
                let refusals = Refusals::default();
                let (lost, noting) = (refusals.clone(), refusals.clone());
                device.set_device_lost_callback(move |reason, message| {
                    lost.lose(format!("{reason:?} {message}").trim_end().to_owned());
                });
                device.on_uncaptured_error(Arc::new(move |error: wgpu::Error| {
                    noting.note(error.to_string());
                }));
                Some(Self {
                    queue: Queue {
                        queue,
                        thread: thread.clone(),
                    },
                    thread,
                    compiling,
                    kernels: Kernels::default(),
                    apart: Apart::default(),
                    plugin_pace: OnceLock::new(),
                    refusals,
                    instance,
                    adapter,
                    device,
                })
            }
            Err(error) => fail(format!("request_device: {error}")),
        }
    }

    /// Blocks until the GPU has finished everything submitted, or fails by
    /// name at [`WAIT_LIMIT`] — polled on the engine's thread
    /// ([`EngineThread`]), the caller waiting outside the driver — and
    /// fails by what the device refused meanwhile ([`Refusals`]): the word
    /// that a device is lost comes inside a poll, so it is asked after one.
    pub(crate) fn wait(&self) -> Option<()> {
        self.wait_within(WAIT_LIMIT)
    }

    fn wait_within(&self, limit: Duration) -> Option<()> {
        WAITED_HERE.with(|waited| waited.set(waited.get() + 1));
        let device = self.device.clone();
        let polled = self.thread.run(move || polled(&device, limit));
        let Some(polled) = polled else {
            // The thread ended under a panic of wgpu's own: a poll's error
            // that is neither of the two above is fatal to it
            // (wgpu's `Device::poll`), a device lost under the poll among
            // them. No wait comes back from this engine again.
            self.refusals.lose(last_error());
            return None;
        };
        polled.map_or_else(fail, Some)?;
        self.refusals.told()
    }

    /// Whether the device is gone ([`Refusals`]): nothing made on this
    /// engine is of use again.
    pub(crate) fn gone(&self) -> bool {
        self.refusals.gone()
    }

    /// A buffer holding `contents`, as long as they are padded to the
    /// copy alignment, for `usage`.
    ///
    /// ⛔NOT wgpu's `create_buffer_init`, whose bytes and sizes these are:
    /// it `expect`s the new buffer's mapping, and a buffer of a device
    /// that is gone has none ([`Refusals`]) — a panic on the caller's
    /// thread. Here such a buffer is left unwritten: nothing reads it, the
    /// wait that follows failing by name.
    pub(crate) fn filled(
        &self,
        label: &str,
        contents: &[u8],
        usage: wgpu::BufferUsages,
    ) -> wgpu::Buffer {
        let align = wgpu::COPY_BUFFER_ALIGNMENT;
        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: (contents.len() as u64).div_ceil(align) * align,
            usage,
            mapped_at_creation: !contents.is_empty(),
        });
        if contents.is_empty() {
            return buffer;
        }
        if let Ok(mut mapped) = buffer.get_mapped_range_mut(..) {
            mapped.slice(..contents.len()).copy_from_slice(contents);
        }
        buffer.unmap();
        buffer
    }

    /// What `work` answers, run on the engine's thread for compiling
    /// ([`EngineThread`]) while the caller waits — the compiler its own for
    /// that long ([`CompilerTurn`]).
    pub(crate) fn compiling<T: Send + 'static>(
        &self,
        work: impl FnOnce(&CompilerTurn) -> T + Send + 'static,
    ) -> T {
        self.compiling.run(move || work(&CompilerTurn(()))).expect("the engine's thread")
    }

    /// The texture's bytes, rows top to bottom with no padding — for
    /// fingerprints and tests; the screen path never reads back.
    pub(crate) fn read_texture(&self, texture: &wgpu::Texture) -> Option<Vec<u8>> {
        let Some(texel) = texture.format().block_copy_size(None) else {
            return fail(format!("{:?} has no one size per texel", texture.format()));
        };
        let row = texture.width() * texel;
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
        let padded = row.div_ceil(align) * align;
        let buffer = self.readback(u64::from(padded) * u64::from(texture.height()));
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_texture_to_buffer(
            texture.as_image_copy(),
            wgpu::TexelCopyBufferInfo {
                buffer: &buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(padded),
                    rows_per_image: Some(texture.height()),
                },
            },
            texture.size(),
        );
        self.queue.submit([encoder.finish()]);
        let mapped = self.mapped(&buffer)?;
        Some(
            mapped
                .chunks(padded as usize)
                .flat_map(|line| &line[..row as usize])
                .copied()
                .collect(),
        )
    }

    /// The bytes of `buffer` — `COPY_SRC` — once the GPU is done with all
    /// that was submitted: what a verb hands back to the app (the cel pixel
    /// pass's counts and runs) and what the tests read.
    pub(crate) fn read_buffer(&self, buffer: &wgpu::Buffer) -> Option<Vec<u8>> {
        let readback = self.staged(buffer, buffer.size());
        self.mapped(&readback)
    }

    /// A buffer the CPU maps, its copy of `buffer`'s first `size` bytes —
    /// a multiple of 4 — submitted: what [`Self::map`] then maps.
    pub(crate) fn staged(&self, buffer: &wgpu::Buffer, size: u64) -> wgpu::Buffer {
        let readback = self.readback(size);
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, size);
        self.queue.submit([encoder.finish()]);
        readback
    }

    /// A buffer of `size` bytes a copy puts and the CPU maps.
    pub(crate) fn readback(&self, size: u64) -> wgpu::Buffer {
        self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("readback"),
            size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        })
    }

    /// Maps `buffer` — one the CPU maps — for reading, once the GPU is done
    /// with all that was submitted.
    pub(crate) fn map(&self, buffer: &wgpu::Buffer) -> Option<()> {
        let mapping = asked_to_map(buffer);
        self.wait()?;
        answered(&mapping)
    }

    /// [`Self::map`] with its wait on the engine's thread and none for the
    /// caller, who goes on: `then` is told there once the GPU is done with
    /// all that was submitted — `buffer`, mapped, or why it is not, as a
    /// wait fails by it ([`Self::wait`]). Told once, whatever becomes of
    /// the wait ([`Told`]).
    ///
    /// 🗣️관제 2026-11-12 (a-lost-gpu-device-keeps-the-unsaved-tiles), of the
    /// copies the app keeps of the engine's tiles: 「UI(또는 래스터) 스레드를
    /// 붙잡는가? 붙잡으면 (B) 안에서 엔진 스레드 비동기로 옮긴 뒤 착지한다
    /// (구형 기기 방침 — 서피스는 더 느리다)」. ⚠️What the caller submits
    /// while that thread polls goes behind the poll ([`Queue::submit`]): as
    /// long as the GPU still takes over what was submitted before it.
    pub(crate) fn map_then(
        &self,
        buffer: wgpu::Buffer,
        then: impl FnOnce(Result<wgpu::Buffer, String>) + Send + 'static,
    ) {
        let mapping = asked_to_map(&buffer);
        let device = self.device.clone();
        let told = Told { then: Some(then), refusals: self.refusals.clone() };
        self.thread.post(move || {
            let mapped = polled(&device, WAIT_LIMIT)
                .map_or_else(fail, Some)
                .and_then(|()| told.refusals.told())
                .and_then(|()| answered(&mapping));
            told.tell(mapped.map(|()| buffer).ok_or_else(last_error));
        });
    }

    /// `buffer`'s bytes, mapped once the GPU is done with all that was
    /// submitted.
    fn mapped(&self, buffer: &wgpu::Buffer) -> Option<Vec<u8>> {
        let mut bytes = vec![0; buffer.size() as usize];
        self.mapped_into(buffer, &mut bytes)?;
        Some(bytes)
    }

    /// `buffer`'s bytes — one the CPU maps, as long as `into` — copied into
    /// `into`, mapped once the GPU is done with all that was submitted.
    pub(crate) fn mapped_into(&self, buffer: &wgpu::Buffer, into: &mut [u8]) -> Option<()> {
        self.map(buffer)?;
        match buffer.get_mapped_range(..) {
            Ok(view) => {
                into.copy_from_slice(&view);
                Some(())
            }
            Err(error) => fail(format!("get_mapped_range: {error}")),
        }
    }
}

thread_local! {
    /// How many waits for the GPU this thread has made
    /// ([`gpu_engine_waits_here`]).
    static WAITED_HERE: Cell<u64> = const { Cell::new(0) };
}

/// Polls `device` till the GPU has finished everything submitted, or says
/// why not: that it did not within `limit`, or wgpu's own word. ⚠️In the
/// driver that long, so on the engine's thread ([`EngineThread`]).
fn polled(device: &wgpu::Device, limit: Duration) -> Result<(), String> {
    let polled = device.poll(wgpu::PollType::Wait { submission_index: None, timeout: Some(limit) });
    polled.map(|_| ()).map_err(|error| match error {
        wgpu::PollError::Timeout => format!("the GPU did not finish within {limit:?}"),
        error => format!("poll: {error}"),
    })
}

/// What answers whether a buffer asked to be mapped was ([`asked_to_map`]).
type Mapping = mpsc::Receiver<Result<(), wgpu::BufferAsyncError>>;

/// Asks that `buffer` — one the CPU maps — be mapped for reading: it is
/// inside a poll that comes once the GPU is done with it ([`answered`]).
fn asked_to_map(buffer: &wgpu::Buffer) -> Mapping {
    let (sender, receiver) = mpsc::channel();
    buffer.map_async(wgpu::MapMode::Read, .., move |result| {
        let _ = sender.send(result);
    });
    receiver
}

/// Whether the buffer `mapping` was asked of is mapped, after the poll
/// that waited for the GPU.
fn answered(mapping: &Mapping) -> Option<()> {
    match mapping.recv() {
        Ok(Ok(())) => Some(()),
        Ok(Err(error)) => fail(format!("map_async: {error}")),
        Err(error) => fail(format!("map_async never answered: {error}")),
    }
}

/// Who is told how a wait ended that its caller did not stay for
/// ([`Engine::map_then`]) — once, whatever becomes of the wait. Dropped
/// untold, the engine's thread ended under the wait — wgpu's poll panics
/// where the device is lost under one — or was gone before it: the device
/// is gone, as for a wait that never came back ([`Engine::wait`]), and
/// that is what is told.
struct Told<Then: FnOnce(Result<wgpu::Buffer, String>)> {
    then: Option<Then>,
    refusals: Refusals,
}

impl<Then: FnOnce(Result<wgpu::Buffer, String>)> Told<Then> {
    fn tell(mut self, ended: Result<wgpu::Buffer, String>) {
        if let Some(then) = self.then.take() {
            then(ended);
        }
    }
}

impl<Then: FnOnce(Result<wgpu::Buffer, String>)> Drop for Told<Then> {
    fn drop(&mut self) {
        if let Some(then) = self.then.take() {
            self.refusals.lose("the engine's thread ended under a wait".into());
            let _gone: Option<()> = self.refusals.told();
            then(Err(last_error()));
        }
    }
}

/// The defaults, but with the most `adapter` gives of the three limits a
/// pool's pages are bounded by: storage buffers a stage, the size of one
/// binding, the size of one buffer. That is 1a's ④ (브러시/렌더링,
/// gpu-canonical-store 2026-11-05 13:19), which names these three. The
/// composite reads `device.limits()`, and a bigger limit only means fewer
/// passes, never other bytes (its tests pin every page count).
fn most_storage(adapter: &wgpu::Adapter) -> wgpu::Limits {
    let most = adapter.limits();
    wgpu::Limits {
        max_storage_buffers_per_shader_stage: most.max_storage_buffers_per_shader_stage,
        max_storage_buffer_binding_size: most.max_storage_buffer_binding_size,
        max_buffer_size: most.max_buffer_size,
        ..wgpu::Limits::default()
    }
}

/// A texture of the engine's own that a compute pass stores to and a copy
/// reads — shared with nothing.
#[cfg(any(test, target_os = "android"))]
pub(crate) fn storage_texture(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
) -> wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label: Some("storage"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    })
}

/// The engine `open` makes, made on a thread of the engine's while the
/// caller waits ([`EngineThread`]) — its failure, if it fails, the caller's
/// last error.
fn opened(open: impl FnOnce() -> Option<Engine> + Send + 'static) -> *mut Engine {
    let made = EngineThread::start()
        .and_then(|thread| thread.run(move || open().ok_or_else(last_error)))
        .and_then(|opened| opened.map_or_else(fail, Some));
    made.map_or(std::ptr::null_mut(), |engine| Box::into_raw(Box::new(engine)))
}

/// Work for an [`EngineThread`].
type Job = Box<dyn FnOnce() + Send>;

/// A thread of the engine's, where what is handed to [`EngineThread::run`]
/// enters the driver while its caller waits outside it, till no engine is
/// left to hand it anything.
///
/// 🚨★★THE CALLER'S THREAD NEVER OPENS A DEVICE, WAITS ON ONE OR SUBMITS TO
/// ONE (an-engine-setup-hangs-in-a-batch, 2026-11-08): the caller is a Dart
/// isolate's, and the Dart VM's sampling profiler — on in every
/// `flutter test` (flutter_tools `flutter_tester_device.dart`,
/// `--enable-dart-profiling`) and every debug run — walks that thread's
/// stack from a thread of its own. While that thread was inside the NVIDIA
/// driver, wgpu trying a device on each adapter, the walk read its stack
/// below what was committed and the process died — 0xC0000005 or
/// 0x80000001, no WER report: 17 of 1368 `flutter test` files eighteen at
/// once on the main PC's RTX 4080, every one in the adapters' enumeration
/// (the Surface's setUpAll `did not complete` is the same death). The
/// profiler walks the isolate's thread, so the driver runs on this one.
///
/// A wait stays in the driver as long as the GPU takes. 🔬Flip lane ⓓ
/// (2026-11-09) put a read back in every save, park and cooling: eight
/// `flutter test` files at once lost one at its first read, three runs of
/// three, each passing alone. A submit is the same death, 🔬four of the
/// four caught at the fault over two runs of 356 files eighteen at once
/// (2026-11-09), each in `gpu_engine_pool_store`'s submit, inside
/// `nvwgf2umx.dll`, `rbp` holding no frame 7–25 KB below the commit floor
/// and the walk reading exactly it — and none in two runs more with the
/// submit moved here. A thread made for each wait took 50–60 µs on the main
/// PC against 1 µs handed to this one, and the screen waits every frame.
/// Each job brings what it works on, so none is kept between them.
///
/// 🔬A kernel's compile runs here too, though none has been seen to die in
/// one: it goes deeper than a submit (관제, 2026-11-09). The frames the walk
/// faulted on lay 41 and 65 KB below `rsp`, so a call that never writes
/// that far has no such frame. Measured with the stack painted around every
/// call, a release build, the 28 `flutter test` files that call the engine,
/// on the main PC's RTX 4080 — bytes below the caller at the deepest, and
/// how many calls passed 40 KiB:
///
/// | call | calls | deepest | past 40 KiB |
/// |---|---|---|---|
/// | `create_compute_pipeline` | 95 | 91,935 | 64 |
/// | submit | 1,630 | 78,606 | 1,294 |
/// | `create_shader_module` | 102 | 34,590 | 0 |
/// | `finish` | 1,630 | 26,406 | 0 |
/// | `create_buffer` | 2,493 | 24,711 | 0 |
/// | `create_texture` | 5 | 19,359 | 0 |
/// | `write_buffer` | 5 | 15,903 | 0 |
/// | `create_command_encoder` | 1,630 | 15,223 | 0 |
/// | `create_bind_group` | 1,028 | 8,271 | 0 |
/// | `create_view` | 172 | 6,287 | 0 |
///
/// ⛔So the rest stay on their caller's: alone on a thread of 1 MiB,
/// `write_buffer` of 4 MiB went 22,319 and `write_texture` of a tile 17,371,
/// and no call but these two has a frame the walk can fault on. A device
/// or driver that goes deeper is what would change that; this is one card.
#[derive(Clone)]
pub(crate) struct EngineThread(mpsc::Sender<Job>);

impl EngineThread {
    fn start() -> Option<Self> {
        let (jobs, asked) = mpsc::channel::<Job>();
        let working = move || {
            for job in asked {
                job();
            }
        };
        match std::thread::Builder::new().name("gpu_engine".into()).spawn(working) {
            Ok(_) => Some(Self(jobs)),
            Err(error) => fail(format!("no thread for the engine: {error}")),
        }
    }

    /// What `work` answers, run on this thread while the caller waits.
    fn run<T: Send + 'static>(&self, work: impl FnOnce() -> T + Send + 'static) -> Option<T> {
        let (answer, answered) = mpsc::channel();
        let job: Job = Box::new(move || {
            let _ = answer.send(work());
        });
        if self.0.send(job).is_err() {
            return fail("the engine's thread is gone");
        }
        match answered.recv() {
            Ok(worked) => Some(worked),
            Err(error) => fail(format!("the engine's thread never answered: {error}")),
        }
    }

    /// Hands `work` to this thread and returns, the caller waiting for
    /// none of it. Dropped unrun where the thread is gone.
    fn post(&self, work: impl FnOnce() + Send + 'static) {
        let _ = self.0.send(Box::new(work));
    }
}

/// Opens the engine on the adapter whose LUID is `luid` (high part in the
/// upper 32 bits) — Flutter's own. Null on failure; see the last error.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_open(luid: u64) -> *mut Engine {
    opened(move || Engine::open(luid))
}

/// Opens the engine on the platform's only adapter — Android's, where
/// Flutter draws with the one GPU there is. Null on failure; see the last
/// error.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_open_sole() -> *mut Engine {
    opened(Engine::open_sole)
}

/// Opens the engine on the platform's first adapter — `flutter test`'s,
/// where no Flutter names one. Null on failure; see the last error.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_open_first() -> *mut Engine {
    opened(Engine::open_first)
}

/// # Safety
/// `engine` came from `gpu_engine_open`, and every surface and kernel made
/// on it has been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_close(engine: *mut Engine) {
    if !engine.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(engine) });
    }
}

/// Copies the adapter's name (UTF-8) into `buffer`; returns its full
/// length, which may exceed `capacity`.
///
/// # Safety
/// `engine` is live and `buffer` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_adapter_name(
    engine: *const Engine,
    buffer: *mut u8,
    capacity: usize,
) -> usize {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    copy_out(&engine.adapter.get_info().name, buffer, capacity)
}

/// This process's use of the adapter's local video memory, in bytes; 0
/// when it cannot be read.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_video_memory(engine: *const Engine) -> u64 {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    platform::video_memory(&engine.adapter).map_or(0, |memory| memory.used)
}

/// Whether `engine`'s device is gone ([`Refusals`]) — lost to the driver,
/// or its thread ended under it: every wait on it fails from then on, and
/// what the app holds of it is of no use again.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_gone(engine: *const Engine) -> bool {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.gone()
}

/// Takes the error `engine` noted that no wait has told yet ([`Refusals`]):
/// copies it (UTF-8) into `buffer` and returns its full length, 0 where
/// there is none — and no wait fails by it after. For the app's tests,
/// which ask as each one ends: an error on a way that never waits would
/// pass them by, and one left noted would fail the next test's wait.
///
/// # Safety
/// `engine` is live and `buffer` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_noted(
    engine: *const Engine,
    buffer: *mut u8,
    capacity: usize,
) -> usize {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.refusals.taken().map_or(0, |error| copy_out(&error, buffer, capacity))
}

/// How many waits for the GPU the thread that asks has made
/// ([`Engine::wait`]): what a test holds at none on the thread an app's
/// frames are built on, over work that is to wait there for nothing
/// ([`Engine::map_then`]).
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_waits_here() -> u64 {
    WAITED_HERE.with(Cell::get)
}

/// Test seam: `engine`'s device destroyed — the nearest a test comes to a
/// driver taking it away, which no test does. The word that it is lost
/// comes at the next wait ([`Refusals`]).
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_lose(engine: *const Engine) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.device.destroy();
}

/// Test seam: `engine` keeps none of its kernels ([`Kernels`]), as a launch
/// finds it. For the app's pins of what is compiled where and when, which
/// a kernel an earlier test compiled would answer for.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_kernels_forget(engine: *const Engine) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.kernels.forget();
}

/// What `engine` compiles apart waits from here ([`Apart`]) till
/// [`gpu_engine_apart_let`] has been called as many times.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_apart_hold(engine: *const Engine) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.apart.hold();
}

/// One [`gpu_engine_apart_hold`] let go.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_apart_let(engine: *const Engine) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.apart.let_go();
}

/// Returns once no [`gpu_engine_apart_hold`] is on: where what the app
/// compiles apart of its own — the frame grids' kernels, each row drawing
/// itself till they are there — waits before it asks for the compiler.
/// ⛔Not on the thread that lets go: it would wait for itself.
///
/// # Safety
/// `engine` is live as this is called.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_apart_wait(engine: *const Engine) {
    // SAFETY: see the function's contract.
    let apart = unsafe { &*engine }.apart.clone();
    apart.wait();
}

/// How many [`gpu_engine_apart_hold`]s are on: none once whoever held has
/// let go, whatever came of what it compiled meanwhile.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_apart_held(engine: *const Engine) -> u64 {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.apart.held() as u64
}

#[cfg(test)]
mod tests {
    use super::{Apart, Engine, gpu_engine_close, opened};
    use crate::testing::first_engine;
    use crate::{fail, last_error};

    #[test]
    fn a_device_is_opened_on_a_thread_of_its_own_not_the_callers() {
        let (sender, on) = std::sync::mpsc::channel();
        let made = opened(move || {
            let _ = sender.send(std::thread::current().id());
            Engine::open_first()
        });
        assert!(!made.is_null(), "{}", last_error());
        assert_ne!(on.try_recv().expect("the open ran"), std::thread::current().id());
        // SAFETY: `made` came from `opened`, nothing made on it.
        unsafe { gpu_engine_close(made) };
    }

    #[test]
    fn a_submit_enters_the_driver_on_a_thread_of_the_engines_not_the_callers() {
        let engine = Engine::open_first().expect("an adapter");
        let (sender, answered) = std::sync::mpsc::channel();
        // What a submit refuses reaches this handler on the thread that
        // submitted.
        engine.device.on_uncaptured_error(std::sync::Arc::new(move |_| {
            let _ = sender.send(std::thread::current().id());
        }));
        let source = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: 4,
            usage: wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let mut encoder = engine.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_buffer_to_buffer(&source, 0, &engine.readback(4), 0, 4);
        let commands = encoder.finish();
        source.destroy();
        engine.queue.submit([commands]);
        let submitted_on = answered.try_recv().expect("the submit was refused inside it");
        assert_ne!(submitted_on, std::thread::current().id());
    }

    #[test]
    fn a_compile_under_way_holds_up_no_submit() {
        let engine = Engine::open_first().expect("an adapter");
        let (release, released) = std::sync::mpsc::channel::<()>();
        let (submitted, answered) = std::sync::mpsc::channel();
        std::thread::scope(|scope| {
            scope.spawn(|| {
                engine.compiling(move |_| {
                    let _ = released.recv();
                })
            });
            scope.spawn(|| {
                engine.queue.submit([]);
                let _ = submitted.send(());
            });
            let got_through = answered.recv_timeout(std::time::Duration::from_secs(20));
            let _ = release.send(());
            assert!(got_through.is_ok(), "the submit waited behind the compile");
        });
    }

    // 🚨What is compiled apart waits while a hold is on, and goes on once
    // each is let go (gpu-canonical-store ④, 2026-11-11; `Apart` has why).
    #[test]
    fn what_is_compiled_apart_waits_till_each_hold_is_let_go() {
        let apart = Apart::default();
        apart.hold();
        apart.hold();
        let (through, went) = std::sync::mpsc::channel();
        let waiting = apart.clone();
        std::thread::spawn(move || {
            waiting.wait();
            let _ = through.send(());
        });
        let soon = std::time::Duration::from_millis(50);
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(20);
        while apart.waiting() == 0 {
            assert!(went.try_recv().is_err(), "it went through two holds");
            assert!(std::time::Instant::now() < deadline, "it never came to its wait");
            std::thread::yield_now();
        }
        apart.let_go();
        assert_eq!(apart.held(), 1);
        assert!(went.recv_timeout(soon).is_err(), "it went through the hold left");
        apart.let_go();
        assert!(went.recv_timeout(std::time::Duration::from_secs(20)).is_ok());
        // One let go that was never held holds nothing back, and owes none.
        apart.let_go();
        assert_eq!(apart.held(), 0);
        apart.hold();
        assert_eq!(apart.held(), 1);
    }

    #[test]
    fn a_compile_enters_the_driver_on_a_thread_of_the_engines_not_the_callers() {
        let engine = Engine::open_first().expect("an adapter");
        let (sender, answered) = std::sync::mpsc::channel();
        // What a compile refuses reaches this handler on the thread that
        // compiled.
        engine.device.on_uncaptured_error(std::sync::Arc::new(move |_| {
            let _ = sender.send(std::thread::current().id());
        }));
        let _ = crate::kernels::shared::pipeline(&engine, &["not a shader"], "main");
        let compiled_on = answered.try_recv().expect("the compile was refused inside it");
        assert_ne!(compiled_on, std::thread::current().id());
    }

    #[test]
    fn a_wait_blocks_in_the_driver_on_a_thread_of_the_engines_not_the_callers() {
        let engine = first_engine();
        let buffer = engine.readback(4);
        let (sender, answered) = std::sync::mpsc::channel();
        // A map answers inside the poll that sees it done: on the thread
        // that polled.
        buffer.map_async(wgpu::MapMode::Read, .., move |_| {
            let _ = sender.send(std::thread::current().id());
        });
        assert_eq!(engine.wait(), Some(()), "{}", last_error());
        let polled_on = answered.try_recv().expect("the map answered inside the wait");
        assert_ne!(polled_on, std::thread::current().id());
    }

    #[test]
    fn a_wait_past_its_limit_says_the_gpu_did_not_finish_and_the_engine_stands() {
        const SIDE: u64 = 64 << 20;
        let engine = first_engine();
        let buffer = |usage| {
            engine.device.create_buffer(&wgpu::BufferDescriptor {
                label: None,
                size: SIDE,
                usage,
                mapped_at_creation: false,
            })
        };
        let from = buffer(wgpu::BufferUsages::COPY_SRC);
        let to = buffer(wgpu::BufferUsages::COPY_DST);
        // Another test's wait on the shared engine can have waited this copy
        // out, and a GPU can finish one before the poll: some round is late.
        let late = (0..64).any(|_| {
            let mut encoder = engine
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
            for _ in 0..16 {
                encoder.copy_buffer_to_buffer(&from, 0, &to, 0, SIDE);
            }
            engine.queue.submit([encoder.finish()]);
            engine.wait_within(std::time::Duration::ZERO).is_none()
        });
        assert!(late, "every wait of no time found the GPU done");
        assert_eq!(last_error(), "the GPU did not finish within 0ns");
        assert_eq!(engine.wait(), Some(()), "{}", last_error());
    }

    fn encoder(engine: &Engine) -> wgpu::CommandEncoder {
        engine.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default())
    }

    // 🚨A device that is gone ends no process: every wait on it fails by
    // name, and what panicked on one — a buffer filled, a copy naming a
    // buffer of it (`Refusals` has the measurement) — returns.
    #[test]
    fn a_device_that_is_gone_fails_every_wait_by_name_and_panics_nowhere() {
        let engine = Engine::open_first().expect("an adapter");
        let before = engine.filled("before", &[1, 2, 3, 4], wgpu::BufferUsages::COPY_SRC);
        assert_eq!(engine.read_buffer(&before), Some(vec![1, 2, 3, 4]), "{}", last_error());
        assert!(!engine.gone());
        engine.device.destroy();
        assert_eq!(engine.wait(), None, "a wait on a device destroyed came back done");
        assert_eq!(last_error(), "the graphics device is gone: Destroyed");
        assert!(engine.gone());
        // The first word of it stays, whatever is said after.
        engine.refusals.lose("a word said after".to_owned());
        // The two that panicked.
        let after = engine.filled("after", &[5, 6, 7, 8], wgpu::BufferUsages::COPY_SRC);
        assert_eq!(engine.read_buffer(&before), None);
        assert_eq!(engine.read_buffer(&after), None);
        assert_eq!(last_error(), "the graphics device is gone: Destroyed");
        // What returned as if it had worked still does, and the wait tells.
        engine.queue.write_buffer(&before, 0, &[0; 4]);
        engine.queue.submit([encoder(&engine).finish()]);
        assert_eq!(engine.wait(), None);
        assert_eq!(last_error(), "the graphics device is gone: Destroyed");
    }

    // 🚨An error no scope catches is the next wait's failure, by name, told
    // once — the engine stands, and its thread with it.
    #[test]
    fn an_error_no_scope_catches_fails_the_next_wait_and_is_told_once() {
        let engine = Engine::open_first().expect("an adapter");
        assert_eq!(engine.wait(), Some(()), "{}", last_error());
        let small = engine.readback(4);
        let source = engine.filled("source", &[1, 2, 3, 4], wgpu::BufferUsages::COPY_SRC);
        let mut encoder = encoder(&engine);
        // Eight bytes of a buffer of four: refused where the copy is named.
        encoder.copy_buffer_to_buffer(&source, 0, &small, 0, 8);
        engine.queue.submit([encoder.finish()]);
        let first = engine.refusals.noted().expect("the device took the copy");
        // One more, of another copy: the first is the one told.
        let mut onto_itself = self::encoder(&engine);
        onto_itself.copy_buffer_to_buffer(&small, 0, &small, 0, 4);
        let _ = onto_itself.finish();
        assert_eq!(engine.wait(), None, "the wait passed the refusal by");
        assert_eq!(last_error(), format!("the device refused: {first}"));
        assert_eq!(engine.refusals.noted(), None);
        assert!(!engine.gone());
        assert_eq!(engine.wait(), Some(()), "{}", last_error());
        assert_eq!(engine.read_buffer(&source), Some(vec![1, 2, 3, 4]), "{}", last_error());
    }

    // 🚨An engine whose thread ended — as it does under a poll wgpu cannot
    // go on from — is gone: no wait comes back from it, and the app is told
    // so as of a device lost.
    #[test]
    fn an_engine_whose_thread_ended_is_gone() {
        let engine = Engine::open_first().expect("an adapter");
        let ended = engine.thread.run(|| -> () { panic!("as wgpu's poll does") });
        assert_eq!(ended, None);
        assert!(!engine.gone(), "gone before a wait found the thread ended");
        assert_eq!(engine.wait(), None);
        assert_eq!(last_error(), "the engine's thread is gone");
        assert!(engine.gone());
    }

    // The tests' own engine keeps the alarm the process had: an error no
    // scope catches ends the test that raised it, where it is raised
    // (`testing::first_engine`).
    #[test]
    #[should_panic(expected = "wgpu error")]
    fn on_the_tests_engine_an_error_no_scope_catches_still_panics() {
        let engine = first_engine();
        let small = engine.readback(4);
        let source = engine.filled("source", &[1, 2, 3, 4], wgpu::BufferUsages::COPY_SRC);
        let mut encoder = encoder(engine);
        encoder.copy_buffer_to_buffer(&source, 0, &small, 0, 8);
        // On this thread: the encoder's errors are raised as it is finished.
        let _ = encoder.finish();
    }

    // What is filled holds its bytes and is as long as wgpu's own made it:
    // padded to the copy alignment, and of no length for none.
    #[test]
    fn a_buffer_filled_holds_its_bytes_padded_to_the_copy_alignment() {
        let engine = first_engine();
        let usage = wgpu::BufferUsages::COPY_SRC;
        let five = engine.filled("five", &[1, 2, 3, 4, 5], usage);
        assert_eq!(five.size(), 8);
        let held = engine.read_buffer(&five);
        assert_eq!(held, Some(vec![1, 2, 3, 4, 5, 0, 0, 0]), "{}", last_error());
        let like = wgpu::util::DeviceExt::create_buffer_init(
            &engine.device,
            &wgpu::util::BufferInitDescriptor { label: None, contents: &[1, 2, 3, 4, 5], usage },
        );
        assert_eq!(five.size(), like.size());
        assert_eq!(held, engine.read_buffer(&like));
        assert_eq!(engine.filled("none", &[], usage).size(), 0);
    }

    // The app asks through the ABI: gone or not, what was noted and is not
    // yet told — taken as it is asked, so no wait fails by it after — and,
    // a test's, a device destroyed.
    #[test]
    fn the_abi_says_whether_a_device_is_gone_and_what_it_noted() {
        use super::{gpu_engine_gone, gpu_engine_lose, gpu_engine_noted};
        let made = opened(Engine::open_first);
        assert!(!made.is_null(), "{}", last_error());
        // SAFETY: `made` is live till the close below, and `noted` holds its
        // length.
        unsafe {
            let engine = &*made;
            let mut noted = [0u8; 2048];
            assert_eq!(gpu_engine_noted(made, noted.as_mut_ptr(), noted.len()), 0);
            let small = engine.readback(4);
            let mut encoder = encoder(engine);
            encoder.copy_buffer_to_buffer(&small, 0, &small, 0, 4);
            let _ = encoder.finish();
            let raised = engine.refusals.noted().expect("a buffer copied onto itself");
            let length = gpu_engine_noted(made, noted.as_mut_ptr(), noted.len());
            assert_eq!(std::str::from_utf8(&noted[..length]).expect("UTF-8"), raised);
            assert_eq!(gpu_engine_noted(made, noted.as_mut_ptr(), noted.len()), 0);
            assert_eq!(engine.wait(), Some(()), "a wait failed by what was taken");
            assert!(!gpu_engine_gone(made));
            gpu_engine_lose(made);
            assert!(!gpu_engine_gone(made), "the word came before a wait");
            assert_eq!(engine.wait(), None);
            assert!(gpu_engine_gone(made));
            gpu_engine_close(made);
        }
    }

    // A buffer mapped with no wait for who asked: the engine's thread waits
    // and tells, there, and the thread that asked has waited for no GPU —
    // a wait of its own is one it has.
    #[test]
    fn a_buffer_is_mapped_then_with_no_wait_on_the_thread_that_asked() {
        use super::gpu_engine_waits_here;
        let engine = first_engine();
        let four = engine.filled("four", &[1, 2, 3, 4], wgpu::BufferUsages::COPY_SRC);
        let (tell, told) = std::sync::mpsc::channel();
        let waits = gpu_engine_waits_here();
        engine.map_then(engine.staged(&four, 4), move |mapped| {
            let _ = tell.send((mapped, std::thread::current().id()));
        });
        let (mapped, on) = told.recv().expect("told");
        assert_ne!(on, std::thread::current().id(), "told on the engine's thread");
        assert_eq!(gpu_engine_waits_here(), waits, "who asked waited for no GPU");
        let mapped = mapped.unwrap_or_else(|why| panic!("{why}"));
        assert_eq!(&mapped.get_mapped_range(..).expect("mapped")[..], [1, 2, 3, 4]);
        assert_eq!(engine.wait(), Some(()));
        assert_eq!(gpu_engine_waits_here(), waits + 1, "a wait here is counted here");
    }

    // Who is told of a wait is told whatever becomes of it: dropped untold
    // — the engine's thread ended under the wait, or was gone before it —
    // it tells that the device is gone, which it then is.
    #[test]
    fn a_wait_that_never_came_back_tells_that_the_device_is_gone() {
        use super::{Refusals, Told};
        let refusals = Refusals::default();
        let (tell, told) = std::sync::mpsc::channel();
        let then = move |ended: Result<wgpu::Buffer, String>| {
            let _ = tell.send(ended.map(|_| ()));
        };
        drop(Told { then: Some(then), refusals: refusals.clone() });
        let gone = "the graphics device is gone: the engine's thread ended under a wait";
        assert_eq!(told.recv(), Ok(Err(gone.to_string())));
        assert!(refusals.gone());
    }

    #[test]
    fn what_fails_on_that_thread_is_the_callers_last_error() {
        let made = opened(|| fail("no adapter here"));
        assert!(made.is_null());
        assert_eq!(last_error(), "no adapter here");
    }

    #[test]
    fn the_device_has_the_most_storage_the_adapter_gives() {
        let engine = first_engine();
        let (most, got) = (engine.adapter.limits(), engine.device.limits());
        println!(
            "{}: {} storage buffers a stage, {} B a binding, {} B a buffer",
            engine.adapter.get_info().name,
            got.max_storage_buffers_per_shader_stage,
            got.max_storage_buffer_binding_size,
            got.max_buffer_size,
        );
        assert_eq!(got.max_storage_buffers_per_shader_stage, most.max_storage_buffers_per_shader_stage);
        assert_eq!(got.max_storage_buffer_binding_size, most.max_storage_buffer_binding_size);
        assert_eq!(got.max_buffer_size, most.max_buffer_size);
    }
}
