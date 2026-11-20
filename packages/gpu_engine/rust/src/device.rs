//! The wgpu device every kernel runs on, opened on the adapter Flutter
//! draws with so a shared texture lives on the GPU that reads it.

use std::cell::Cell;
use std::collections::HashMap;
use std::panic::{catch_unwind, resume_unwind, AssertUnwindSafe, Location};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Condvar, Mutex, OnceLock, PoisonError};
use std::thread::ThreadId;
use std::time::{Duration, Instant};

use crate::kernels::shared::{Counted, built_here, put_built_here};
use crate::submits::Submits;
use crate::{copy_out, fail, last_error, platform, put_last_error, take_last_error};

/// How long a wait for the GPU is waited out before it is answered that the
/// GPU did not finish ([`Poll::within`]): a failure with a name rather than
/// a screen that stands still (관제 2026-11-08, after a pin stood 13 minutes
/// in this wait: 「멈춘 화면보다 이름 있는 실패」).
// ⏳My number, not measured: far past a screen frame's milliseconds, and
// long enough that a heavy export frame does not fail falsely. To be settled
// from the Surface's slowest waits, as the reading watch's three seconds were.
const WAIT_LIMIT: Duration = Duration::from_secs(30);

/// The bytes of what stands in for a page given back ([`Engine::no_page`]):
/// a word, the least a buffer is.
pub(crate) const NO_PAGE_BYTES: u64 = 4;

/// One wgpu device and its queue.
#[derive(Clone)]
pub struct Engine {
    /// Kept for Android's window surfaces, which must come from the
    /// instance the adapter came from.
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    pub(crate) instance: wgpu::Instance,
    pub(crate) adapter: wgpu::Adapter,
    /// ⛔Private to this type, as the `wgpu::Queue` is to [`Queue`]: a
    /// kernel takes it by [`Engine::device`], which counts the hands that
    /// are no thread's of the engine.
    device: wgpu::Device,
    pub(crate) queue: Queue,
    /// Where a verb's body runs ([`Engine::on_thread`]).
    thread: EngineThread,
    /// Where the engine stays in the driver till the GPU has finished what
    /// was submitted ([`Engine::poll`]) — a thread of its own, so that no
    /// body stands behind the GPU ([`EngineThread`]).
    ///
    /// ⚠️Letting the engine go waits for none of it (`gpu_engine_close`;
    /// 🗣️관제 2026-11-14 08:14 asked which, of a poll that gave up and is
    /// in the driver still). No thread of an engine's is joined: each ends
    /// once it is through with its job and nothing is left to hand it one,
    /// and a poll under way keeps the device by a hold of its own, which
    /// goes where that poll ends — on this thread, not the bodies'. What a
    /// let-go does wait for is the GPU, by wgpu's own doing: the queue,
    /// let go of with the engine's hold the last on it, waits till the GPU
    /// is idle (wgpu-core 30.0.1, `Queue::drop`: `wait_for_idle`, which
    /// D3D12 gives no limit) — on the bodies' thread, as it did while a
    /// poll was a job there. ⚠️Not measured: a GPU that never finishes.
    polls: EngineThread,
    /// Where a wait no caller stays for is waited out, outside the driver,
    /// and its caller told ([`Engine::done_then`]).
    tells: EngineThread,
    /// Where a kernel's compile enters the driver: threads of its own, so
    /// that seconds of one made ahead of its first use hold up no frame's
    /// submit behind them on `thread` (🔬the blur brush's ten pipelines,
    /// 10.2 s on the main PC's RTX 4080 with eighteen test files running,
    /// 2026-11-10; 1.2 to 2.5 s each by strips) — as many as the device
    /// has cores ([`CompilerTurn`]).
    compiling: EngineThread,
    /// Where a pool's page is made and let go ([`Engine::pages_posted`],
    /// [`Engine::on_pages_thread`]): a thread of its own, so that no body
    /// stands behind a page being made on `thread` — as `compiling` is for
    /// a compile.
    ///
    /// 🔬WHY (card a-picture-lay-holds-the-raster-thread, the Surface,
    /// FNK_02 cut 59 with the onion on, 2026-11-16 02:4x): a page took the
    /// engine's thread 48 to 55 ms, 156 to 195 ms as memory filled, and the
    /// UI's waits handed over behind it — a screen let go, a composite's
    /// done — stood as long (64.5 ms, 93.2 ms).
    ///
    /// ⚖️LET GO AS THE ENGINE IS, NOT JOINED (브러시/렌더링 2026-11-16 08:32
    /// ⑤ asked a page's last free here before the device): a page holds the
    /// device it was made on by wgpu's own hold, so it is freed before the
    /// device wherever its last hold goes. A making holds the engine by a
    /// clone of its own: the engine let go meanwhile, the device goes here
    /// once that making ends — as a poll's goes on `polls`.
    pages: EngineThread,
    /// What stands in the place of a page a pool gave back
    /// ([`Engine::no_page`]).
    no_page: wgpu::Buffer,
    /// Every kernel the engine has compiled ([`Kernels`]).
    pub(crate) kernels: Kernels,
    /// When what is compiled apart may take the compiler ([`Apart`]).
    pub(crate) apart: Apart,
    /// How fast the device spends a plugin's share, once a plugin first
    /// ran (kernels/plugin's `Pace`).
    pub(crate) plugin_pace: OnceLock<crate::kernels::plugin::Pace>,
    /// The pool every picture the engine keeps has its tiles in
    /// (kernels/pool's `Pictures`).
    pub(crate) pictures: crate::kernels::pool::Pictures,
    /// The composite's work buffer, kept from one run to the next
    /// (kernels/composite's `Work`).
    pub(crate) work: crate::kernels::composite::Work,
    /// What the device refused that no wait has told yet, and whether it
    /// is gone ([`Refusals`]).
    refusals: Refusals,
    /// Why each wait no caller stayed for failed, till the caller asks
    /// ([`gpu_engine_done_failure`]).
    ended: Ended,
    /// What the bodies handed over unwaited refused, till a done tells it
    /// ([`Engine::posted`]).
    posted_refused: PostedRefused,
}

/// What the bodies handed to the engine's thread unwaited refused
/// ([`Engine::posted`]) that no done has told yet: the first of each
/// calling thread's since one was told, by that thread — so a worker's
/// fails no done of the UI's.
#[derive(Clone, Default)]
struct PostedRefused(Arc<Mutex<HashMap<ThreadId, String>>>);

impl PostedRefused {
    fn kept(&self) -> std::sync::MutexGuard<'_, HashMap<ThreadId, String>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// `error`, a body of `by`'s, kept where it is the first since one of
    /// `by`'s was told.
    fn note(&self, by: ThreadId, error: String) {
        self.kept().entry(by).or_insert(error);
    }

    /// What a body of `by`'s refused, taken: no done tells it after.
    fn taken(&self, by: ThreadId) -> Option<String> {
        self.kept().remove(&by)
    }
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

/// wgpu's word of a device it loses for want of memory
/// (`hal::DeviceError::OutOfMemory`, as wgpu-core's `Device::lose` hands it
/// to the lost callback) — on every backend: a tablet's too.
const OUT_OF_MEMORY: &str = "Out of memory";

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

    /// Whether the device is gone for want of memory: wgpu gave it up at
    /// an allocation its backend refused, and said so ([`OUT_OF_MEMORY`]).
    fn gone_for_memory(&self) -> bool {
        self.kept().gone.as_deref().is_some_and(|why| why.ends_with(OUT_OF_MEMORY))
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
    ///
    /// ⚠️THE PACKAGE READS `the graphics device is gone` (lib/gpu_engine.dart,
    /// `GpuRefused.ofAGoneDevice` — board
    /// a-late-refusal-of-a-let-go-engine-shows-the-restart-window): the app
    /// tells a refusal of an engine it has let go from one of the engine
    /// it stands on by them, and a refusal reaches it as its words alone.
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
///
/// ⛔Waited for here by the engine's own threads alone — no verb of the C
/// ABI waits for a hold. The app lets go on its isolate, and a worker
/// isolate waiting here outlived it: the app closed while it compiled ahead
/// stayed till it was killed (the-windows-app-stays-after-its-window-closes,
/// 2026-11-16 — `GpuEngine.compilesApartLetGo` has the measure).
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
/// — so a compile runs on one of the engine's threads for compiling,
/// whatever thread asks, as many at once as the device has cores
/// ([`compiling_threads`]).
///
/// ↩️⛔One at a time till 2026-11-13: what DXC makes is not thread-safe —
/// 「objects created by DxcCreateInstance aren't thread-safe」 (DXC wiki,
/// "Using dxc.exe and dxcompiler.dll") — and wgpu-hal 30 compiled on the
/// device's one `IDxcCompiler3` from whatever thread asked, with no lock
/// (dx12/shader_compilation.rs, `CompilerDynamicDxc`). ↩️A plugin's compile
/// ran on its own thread beside the engine's till 2026-11-11, the one
/// compiler under both whenever a plugin was compiled while a kernel of
/// the engine's was; no fault has been traced to it. 🗣️유저 2026-11-13
/// (the-wait-window-stands-seven-seconds-on-the-surface-Q1, 「고친 사본을
/// 묶는다 — 디스크 캐시 + 나란히 컴파일」): wgpu-hal is ours to patch
/// (Cargo.toml, `[patch.crates-io]`), and each compile under way takes a
/// DXC compiler no other holds (vendor/wgpu-hal, `DxcCompilers`).
pub(crate) struct CompilerTurn(());

/// How many threads the engine compiles on ([`CompilerTurn`]): one to each
/// of the device's cores, a tablet's few among them.
fn compiling_threads() -> usize {
    std::thread::available_parallelism().map_or(1, std::num::NonZeroUsize::get)
}

/// The queue the kernels submit to, whose submits enter the driver on the
/// engine's thread ([`EngineThread`]) — ⛔the `wgpu::Queue` stays private
/// to this type so that no kernel can submit on its caller's.
#[derive(Clone)]
pub(crate) struct Queue {
    queue: wgpu::Queue,
    thread: EngineThread,
    /// Every submit through here, and whether the GPU said it finished it
    /// ([`Submits`]).
    pub(crate) submits: Arc<Submits>,
}

impl Queue {
    /// Submits `buffers` and returns once the driver has them, so what the
    /// caller writes next goes after them, as on one thread. A thread that
    /// is gone is the next wait's error. Noted, where its caller made it,
    /// until the GPU says it finished it ([`Submits`]).
    #[track_caller]
    pub(crate) fn submit(&self, buffers: impl IntoIterator<Item = wgpu::CommandBuffer>) {
        let (queue, buffers): (_, Vec<_>) = (self.queue.clone(), buffers.into_iter().collect());
        let (submits, number) = (self.submits.clone(), self.submits.note(Location::caller()));
        #[cfg(test)]
        let by = self.thread.number;
        let _ = self.thread.run(move || {
            // The tests' shared device waits here while a test's own is up
            // (`testing::a_device_of_its_own`) — on the engine's thread,
            // where no caller waits for it with that turn in hand.
            #[cfg(test)]
            let _turn = crate::testing::submitting(by);
            queue.submit(buffers);
            queue.on_submitted_work_done(move || submits.done(number));
        });
    }

    pub(crate) fn write_buffer(&self, buffer: &wgpu::Buffer, offset: wgpu::BufferAddress, data: &[u8]) {
        entered();
        self.queue.write_buffer(buffer, offset, data);
    }

    #[cfg(target_os = "android")]
    pub(crate) fn present(&self, texture: wgpu::SurfaceTexture) {
        entered();
        self.queue.present(texture);
    }

    pub(crate) fn write_texture(
        &self,
        texture: wgpu::TexelCopyTextureInfo<'_>,
        data: &[u8],
        layout: wgpu::TexelCopyBufferLayout,
        size: wgpu::Extent3d,
    ) {
        entered();
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
        Self::first_within(most_storage)
    }

    /// [`Self::open_first`], one binding holding no more than `room` bytes:
    /// a test's device that binds as little as lavapipe's 128 MiB does, of
    /// planes a test makes (board
    /// the-engine-binds-a-plane-past-the-device-limit, 2026-11-17 — the CI
    /// found a plane bound past it, and every device here binds more).
    #[cfg(test)]
    pub(crate) fn open_first_binding(room: u64) -> Option<Self> {
        Self::first_within(|adapter| wgpu::Limits {
            max_storage_buffer_binding_size: room,
            ..most_storage(adapter)
        })
    }

    fn first_within(limits: impl FnOnce(&wgpu::Adapter) -> wgpu::Limits) -> Option<Self> {
        let instance = platform::instance();
        match platform::adapters(&instance).into_iter().next() {
            Some(adapter) => {
                let limits = limits(&adapter);
                Self::within(instance, adapter, limits)
            }
            None => fail("no adapter"),
        }
    }

    pub(crate) fn on(instance: wgpu::Instance, adapter: wgpu::Adapter) -> Option<Self> {
        let limits = most_storage(&adapter);
        Self::within(instance, adapter, limits)
    }

    fn within(
        instance: wgpu::Instance,
        adapter: wgpu::Adapter,
        required_limits: wgpu::Limits,
    ) -> Option<Self> {
        let required_features = adapter.features() & wgpu::Features::BGRA8UNORM_STORAGE;
        let request = adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("gpu_engine"),
            required_features,
            required_limits,
            ..Default::default()
        });
        match pollster::block_on(request) {
            Ok((device, queue)) => {
                platform::keep_shaders(&device);
                let thread = EngineThread::start()?;
                let polls = EngineThread::start()?;
                let tells = EngineThread::start()?;
                let compiling = EngineThread::start_many(compiling_threads())?;
                let pages = EngineThread::start()?;
                let no_page = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("no page"),
                    size: NO_PAGE_BYTES,
                    usage: wgpu::BufferUsages::STORAGE,
                    mapped_at_creation: false,
                });
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
                        submits: Arc::default(),
                    },
                    thread,
                    polls,
                    tells,
                    compiling,
                    pages,
                    no_page,
                    kernels: Kernels::default(),
                    apart: Apart::default(),
                    plugin_pace: OnceLock::new(),
                    pictures: Default::default(),
                    work: Default::default(),
                    refusals,
                    ended: Ended::default(),
                    posted_refused: PostedRefused::default(),
                    instance,
                    adapter,
                    device,
                })
            }
            Err(error) => fail(format!("request_device: {error}")),
        }
    }

    /// Blocks until the GPU has finished everything submitted, or fails by
    /// name at [`WAIT_LIMIT`] — polled on the engine's thread for polls
    /// ([`Self::poll`]), the caller waiting outside the driver — and
    /// fails by what the device refused meanwhile ([`Refusals`]): the word
    /// that a device is lost comes inside a poll, so it is asked after one.
    pub(crate) fn wait(&self) -> Option<()> {
        self.wait_within(WAIT_LIMIT)
    }

    /// 🚨Every wait of a body's for the GPU passes here — a map's, a read's
    /// ([`Self::map`], [`Self::read_buffer`], [`Self::read_texture`]) —
    /// so it is here that a body leaves the engine's thread to the bodies
    /// behind it ([`EngineThread::stands_aside`]), as where it waits for a
    /// compile ([`Self::compiling`]).
    fn wait_within(&self, limit: Duration) -> Option<()> {
        WAITED_HERE.with(|waited| waited.set(waited.get() + 1));
        self.thread.stands_aside();
        self.poll().within(limit, &self.refusals)
    }

    /// Asks the engine's thread for polls to stay in the driver till the
    /// GPU has finished everything submitted — as long as that takes — and
    /// returns at once with what waits it out ([`Poll`]).
    fn poll(&self) -> Poll {
        Poll::asked_of(&self.polls, &self.device)
    }

    /// Whether the device is gone ([`Refusals`]): nothing made on this
    /// engine is of use again.
    pub(crate) fn gone(&self) -> bool {
        self.refusals.gone()
    }

    /// Why the device went, as far as anything says (`platform::WENT_*`):
    /// wgpu, of one it gave up for want of memory; else the platform, of
    /// one its driver took ([`platform::device_went_by`]).
    pub(crate) fn went_by(&self) -> u32 {
        if self.refusals.gone_for_memory() {
            return platform::WENT_BY_MEMORY;
        }
        platform::device_went_by(self.device())
    }

    /// The device — a thread of the engine's has it in hand, and no other:
    /// each time a thread takes it is counted on that thread
    /// ([`gpu_engine_device_entered_here`]), which the app's pin holds at
    /// none on the thread its frames are built on ([`EngineThread`] has
    /// why).
    pub(crate) fn device(&self) -> &wgpu::Device {
        entered();
        &self.device
    }

    /// The number this engine's submits go by (`testing::submitting`).
    #[cfg(test)]
    pub(crate) fn submits_as(&self) -> u64 {
        self.thread.number
    }

    /// Returns once the GPU is through with all this engine was handed —
    /// the engine's one poll ([`Self::poll`]), its answer waited for and
    /// nothing else of a wait's: no wait counted on the caller's thread, a
    /// test's that may count its own, and no refusal told, which another
    /// test's wait is to fail by. The shared device's work, done as a
    /// test's own comes up (`testing::a_device_of_its_own`).
    #[cfg(test)]
    pub(crate) fn through_with_all_submitted(&self) {
        if let Ok(answer) = self.poll().answer {
            let _ = answer.recv_timeout(WAIT_LIMIT);
        }
    }

    /// What `work` answers, run on the engine's thread while the caller
    /// waits ([`EngineThread::run_lent`]): where a verb's body runs,
    /// whatever thread called the verb — one body at a time, in the order
    /// they were called, but past one that waits for a compile
    /// ([`EngineThread::stands_aside`]). On that thread already, it runs
    /// where it is.
    ///
    /// ⏳That a verb's body goes through here is the verb's own word,
    /// which `every_verb.rs` reads the sources for. A device no code can
    /// reach but through a token only this door hands out was weighed and
    /// put off to stage 2 of the-ui-thread-never-enters-the-driver, not
    /// thrown out (관제 2026-11-14 01:21): the stage where a verb hands its
    /// body here and waits for none of it, each family's bodies written
    /// again as it goes — through [`Self::posted`].
    pub(crate) fn on_thread<T>(&self, work: impl FnOnce() -> T) -> T {
        self.thread.run_lent(work)
    }

    /// Whether the calling thread is the engine's — the one a verb's body
    /// runs on ([`Self::on_thread`]).
    pub(crate) fn is_its_thread(&self) -> bool {
        self.thread.is_here()
    }

    /// What stands in the place of a page a pool gave back
    /// (`kernels/pool`): one buffer of [`NO_PAGE_BYTES`], made with the
    /// engine, in the place of each — a `TileAt` names a page by its place
    /// among the pool's. So a page is given back on whatever thread keeps
    /// the pool's books, and no buffer is made for it. ↩️A tile's bytes
    /// made for each page given back, on the engine's thread, till the
    /// pages no tile lies on were given back where a fold is settled —
    /// the UI's thread (F-610, 2026-11-19).
    ///
    /// Too small for a tile, as it is or folded: a place said on it is
    /// refused (`TileAt::stored_on`), where a tile's bytes read whatever
    /// the first slot's were.
    pub(crate) fn no_page(&self) -> wgpu::Buffer {
        self.no_page.clone()
    }

    /// `work`, run on the thread a pool's pages are made on ([`Engine`]'s
    /// `pages`) in its turn, its caller waiting for none of it — dropped
    /// unrun where that thread is gone ([`EngineThread::post`]).
    pub(crate) fn pages_posted(&self, work: impl FnOnce() + Send + 'static) {
        self.pages.post(work);
    }

    /// What `work` answers, run on the thread a pool's pages are made on
    /// while the caller waits ([`EngineThread::run_lent`]): behind what was
    /// posted there before it ([`Self::pages_posted`]).
    pub(crate) fn on_pages_thread<T>(&self, work: impl FnOnce() -> T) -> T {
        self.pages.run_lent(work)
    }

    /// `body`, run on the engine's thread in its turn, its caller waiting
    /// for none of it ([`EngineThread::posts`]) — stage 2's door
    /// (the-ui-thread-never-enters-the-driver B1-a): for a verb whose
    /// caller takes nothing back from its body but whether it worked. That
    /// a done tells: where the body fails, its failure is kept for the
    /// thread that handed it over — the first since one was told
    /// ([`PostedRefused`]) — and that thread's next done fails by it
    /// ([`Self::done_then`]). So a caller that asks for a done in the turn
    /// it hands a body over is told of that body: none of its others comes
    /// between. What the body counts on its thread — its waits, the
    /// compiles it waited for — is counted on its caller's once it has
    /// run ([`POSTED_HERE`]), as a lent body's is ([`Callers`]).
    ///
    /// 🗣️관제 2026-11-15 05:09: 「메모리가 없을 때는 드물지 않다 — 구형 · 약한
    /// 기기 방침상 그 기기가 바로 메모리가 모자란 기기다」 — a body that fails
    /// is a frame's picture baked wrong and kept, where nothing tells it.
    /// ⏳(브러시/렌더링 2026-11-15, the user asleep — theirs to overturn)
    /// ⛔Not noted as an error no scope caught ([`Refusals`]): that one is
    /// told by the first wait to end, and a done asked before the body can
    /// end after it, and take it. ⛔Nor a done of its own for each body: a
    /// screen's frame is put up by the done its screen asks
    /// (`ScreenTexture.present`), in the turn it is shown — 🗣️관제
    /// 2026-11-15 05:20 asked that turn pinned.
    pub(crate) fn posted(&self, body: impl FnOnce() -> Option<()> + Send + 'static) {
        let (caller, refused) = (std::thread::current().id(), self.posted_refused.clone());
        let counted = POSTED_HERE.with(Arc::clone);
        self.thread.posts(move || {
            let (waited, built) = (WAITED_HERE.get(), built_here());
            let worked = catch_unwind(AssertUnwindSafe(body));
            counted.add(WAITED_HERE.get() - waited, built_here() - built);
            match worked {
                Ok(Some(())) => {}
                Ok(None) => refused.note(caller, take_last_error()),
                Err(panic) => {
                    refused.note(caller, "it panicked".to_owned());
                    resume_unwind(panic);
                }
            }
        });
    }

    /// `made`, handed to the caller over the ABI: a pointer to it, good
    /// till it is let go of ([`let_go`], [`let_go_unwaited`]), on this
    /// engine's thread ([`Handed`]).
    pub(crate) fn hands<T>(&self, made: T) -> *mut T {
        self.handed(made, None)
    }

    /// `made`, handed out as [`Self::hands`] hands a thing, with the bytes
    /// it counts ([`Counted`]) beside it: counted off as its free lets go
    /// of it, before the thing goes to its engine's thread
    /// ([`let_go_unwaited`]) — so what reads the count right after the free
    /// reads them gone, as when the free counted them off by hand.
    pub(crate) fn hands_counted<T>(&self, made: T, counted: Counted) -> *mut T {
        self.handed(made, Some(counted))
    }

    fn handed<T>(&self, made: T, counted: Option<Counted>) -> *mut T {
        let thread = self.thread.clone();
        Box::into_raw(Box::new(Handed { kept: made, thread, counted })).cast()
    }

    /// This engine as the ABI hands one out, [`gpu_engine_close`]'s to let
    /// go of: the one thing of the ABI's that is no [`Handed`] — it is what
    /// keeps the thread.
    pub(crate) fn boxed(self) -> *mut Self {
        Box::into_raw(Box::new(self))
    }

    /// What each of `works` answers, in their order, all under way at once
    /// — each on a thread made for it while the caller waits: for works
    /// that each wait for a compile ([`Self::compiling`]; 🗣️유저 2026-11-13,
    /// the-wait-window-stands-seven-seconds-on-the-surface-Q1, 「나란히
    /// 컴파일」). ⚠️A body waits here for those threads, not for a compile
    /// of its own asking, so it is here that it leaves the engine's thread
    /// to the bodies behind it ([`EngineThread::stands_aside`]) —
    /// `one_side_by_side.rs` keeps this the one place a kernel's code waits
    /// for threads of its own making.
    pub(crate) fn side_by_side<T: Send>(
        &self,
        works: impl IntoIterator<Item = impl FnOnce() -> T + Send>,
    ) -> Vec<T> {
        self.thread.stands_aside();
        std::thread::scope(|scope| {
            let working: Vec<_> = works.into_iter().map(|work| scope.spawn(work)).collect();
            working.into_iter().map(|one| one.join().unwrap_or_else(|panic| resume_unwind(panic))).collect()
        })
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
        let buffer = self.device().create_buffer(&wgpu::BufferDescriptor {
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
    /// that long ([`CompilerTurn`]). 🚨Every wait for a kernel passes here,
    /// its own compile's and another caller's of the same one alike
    /// (`kernels::shared`, `Kernel::pipeline`), so it is here that a body
    /// leaves the engine's thread to the bodies behind it
    /// ([`EngineThread::stands_aside`]).
    pub(crate) fn compiling<T: Send + 'static>(
        &self,
        work: impl FnOnce(&CompilerTurn) -> T + Send + 'static,
    ) -> T {
        self.thread.stands_aside();
        self.compiling.run(move || work(&CompilerTurn(()))).expect("the engine's thread")
    }

    /// The texture's bytes, rows top to bottom with no padding — for
    /// fingerprints and tests; the screen path never reads back.
    pub(crate) fn read_texture(&self, texture: &wgpu::Texture) -> Option<Vec<u8>> {
        let texel = texture.format().block_copy_size(None).unwrap_or(0);
        let mut bytes = vec![0; (texture.width() * texel) as usize * texture.height() as usize];
        self.read_texture_into(texture, &mut bytes)?;
        Some(bytes)
    }

    /// [`Self::read_texture`] into `into`, as long as the texture's bytes:
    /// its rows copied there from the mapped buffer each once.
    ///
    /// 🔬A test's screen is read back as each frame of it is laid (the
    /// stand-in for a texture `flutter test` does not show), and the bytes
    /// went through a zeroed buffer, a byte-by-byte gather and a third copy
    /// on their way: 2026-11-17, main PC, the float landing test's file,
    /// 121 s of its 487 in this read (board
    /// ci-heaviest-files-draw-on-the-cpu).
    pub(crate) fn read_texture_into(&self, texture: &wgpu::Texture, into: &mut [u8]) -> Option<()> {
        let Some(texel) = texture.format().block_copy_size(None) else {
            return fail(format!("{:?} has no one size per texel", texture.format()));
        };
        let row = texture.width() * texel;
        let length = row as usize * texture.height() as usize;
        if into.len() != length {
            return fail(format!(
                "a texture of {length} bytes read into {}",
                into.len()
            ));
        }
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
        let padded = row.div_ceil(align) * align;
        let buffer = self.readback(u64::from(padded) * u64::from(texture.height()));
        let mut encoder = self
            .device()
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
        self.map(&buffer)?;
        let view = match buffer.get_mapped_range(..) {
            Ok(view) => view,
            Err(error) => return fail(format!("get_mapped_range: {error}")),
        };
        for (line, out) in view.chunks(padded as usize).zip(into.chunks_exact_mut(row as usize)) {
            out.copy_from_slice(&line[..row as usize]);
        }
        Some(())
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
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, size);
        self.queue.submit([encoder.finish()]);
        readback
    }

    /// A buffer of `size` bytes a copy puts and the CPU maps.
    pub(crate) fn readback(&self, size: u64) -> wgpu::Buffer {
        self.device().create_buffer(&wgpu::BufferDescriptor {
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

    /// [`Self::map`] with no wait for the caller, who goes on, as
    /// [`Self::done_then`] waits — polled where it is asked, a body's own
    /// work: `then` is told `buffer`, mapped, or why it is not.
    pub(crate) fn map_then(
        &self,
        buffer: wgpu::Buffer,
        then: impl FnOnce(Result<wgpu::Buffer, String>) + Send + 'static,
    ) {
        let mapping = asked_to_map(&buffer);
        let mapped = move |done: Result<(), String>| {
            then(done.and_then(|()| {
                answered(&mapping).map(|()| buffer).ok_or_else(last_error)
            }));
        };
        // Polled from here, the body that asks: what a body handed over
        // unwaited refused is no word on this one's map ([`Self::posted`]).
        Told { then: Some(mapped), refusals: self.refusals.clone() }.once_polled(
            &self.tells,
            self.poll(),
            WAIT_LIMIT,
        );
    }

    /// [`Self::wait`] with none for the caller, who goes on: a thread of the
    /// engine's waits in its stead (`tells`), and tells `then` there once
    /// the GPU is done with all that was submitted, or why it is not, as a
    /// wait fails by it — at [`WAIT_LIMIT`] among them. Told once, whatever
    /// becomes of the wait ([`Told`]).
    ///
    /// 🗣️관제 2026-11-12 (a-lost-gpu-device-keeps-the-unsaved-tiles), of the
    /// copies the app keeps of the engine's tiles: 「UI(또는 래스터) 스레드를
    /// 붙잡는가? 붙잡으면 (B) 안에서 엔진 스레드 비동기로 옮긴 뒤 착지한다
    /// (구형 기기 방침 — 서피스는 더 느리다)」 — and a screen's frame, put up
    /// once the GPU has finished it (🗣️유저 2026-11-12,
    /// a-float-in-hand-draws-the-frame-as-it-stands-Q2).
    ///
    /// ↩️Till 2026-11-14 the poll was a job of the thread the submits
    /// entered the driver on, and what the caller submitted meanwhile went
    /// behind it, as long as the GPU still took over what was submitted
    /// before ([`EngineThread`] has what stood there once the bodies did).
    ///
    /// 🚨THE POLL IS ASKED FROM THE BODIES' THREAD, IN TURN BEHIND EVERY
    /// BODY HANDED THERE BEFORE IT (the-ui-thread-never-enters-the-driver
    /// B1-a, 2026-11-15): a body handed over unwaited ([`Self::posted`])
    /// may not have submitted yet as its caller asks, and a poll asked
    /// before that submit answers without it — a screen's frame put up
    /// before the GPU had drawn it. There, too, it takes what such a body
    /// of the caller's refused ([`PostedRefused`]), and fails by it.
    pub(crate) fn done_then(&self, then: impl FnOnce(Result<(), String>) + Send + 'static) {
        self.done_within(WAIT_LIMIT, then);
    }

    fn done_within(&self, limit: Duration, then: impl FnOnce(Result<(), String>) + Send + 'static) {
        let told = Told { then: Some(then), refusals: self.refusals.clone() };
        let (asker, refused) = (std::thread::current().id(), self.posted_refused.clone());
        let (polls, device, tells) = (self.polls.clone(), self.device.clone(), self.tells.clone());
        self.thread.posts(move || match refused.taken(asker) {
            Some(why) => told.tell(Err(format!("a body handed over unwaited failed: {why}"))),
            None => told.once_polled(&tells, Poll::asked_of(&polls, &device), limit),
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
    /// Which of an engine's threads this one is, by the number of the
    /// [`EngineThread`] it works for — [`NO_ENGINE`] on a caller's.
    static WORKS_FOR: Cell<u64> = const { Cell::new(NO_ENGINE) };
    /// How many times this thread has taken a device in hand
    /// ([`gpu_engine_device_entered_here`]) — on a thread of an engine's,
    /// a count no one asks for.
    static ENTERED_HERE: Cell<u64> = const { Cell::new(0) };
    /// Where this thread, an engine's, is with its turn at that engine's
    /// jobs ([`Turn`]) — on a caller's thread, a word no one asks for.
    static TURN: Cell<Turn> = const { Cell::new(Turn::Held) };
    /// Whether the job this thread, an engine's, is in was handed it
    /// unwaited ([`EngineThread::posts`]): it keeps its turn through a
    /// compile ([`EngineThread::stands_aside`]).
    static POSTED: Cell<bool> = const { Cell::new(false) };
    /// What the bodies this thread handed over unwaited counted as they
    /// ran ([`Engine::posted`]), added as each ends — its own counts' share
    /// of theirs, which [`gpu_engine_waits_here`] and
    /// `gpu_engine_kernels_built_here` answer with.
    static POSTED_HERE: Arc<PostedCounts> = Arc::default();
}

/// What a caller's bodies handed over unwaited counted on the engine's
/// thread ([`POSTED_HERE`]): the waits for the GPU they made
/// ([`WAITED_HERE`]) and the kernels whose compile they waited for
/// (`BUILT_HERE`).
#[derive(Default)]
struct PostedCounts {
    waited: AtomicU64,
    built: AtomicU64,
}

impl PostedCounts {
    fn add(&self, waited: u64, built: u64) {
        self.waited.fetch_add(waited, Ordering::Relaxed);
        self.built.fetch_add(built, Ordering::Relaxed);
    }
}

/// How many kernels the bodies the calling thread handed over unwaited
/// waited on a compile of, as far as they have run ([`POSTED_HERE`]).
pub(crate) fn built_by_posted_here() -> u64 {
    POSTED_HERE.with(|counted| counted.built.load(Ordering::Relaxed))
}

/// What [`WORKS_FOR`] holds on a thread that is none of an engine's.
const NO_ENGINE: u64 = 0;

/// The number the next [`EngineThread`] is known by.
static THREAD_NUMBERS: AtomicU64 = AtomicU64::new(NO_ENGINE + 1);

/// One more hand on a device, the calling thread's ([`Engine::device`]).
fn entered() {
    ENTERED_HERE.set(ENTERED_HERE.get() + 1);
}

/// What a caller's thread keeps for itself that a verb's body reads and
/// writes — its last error ([`fail`]), the waits it has made
/// ([`WAITED_HERE`]), the compiles it has waited for (`kernels::shared`,
/// `BUILT_HERE`) — taken off one thread and put on another: over to the
/// engine's with a body handed there, and back with what the body made of
/// them. So a body run there fails by its caller's last error and counts on
/// its caller's thread, as it did when it ran on it.
struct Callers {
    error: String,
    waited: u64,
    built: u64,
    /// The bytes the tests count a thread to hold of the heap
    /// (`testing::held`): what a body takes and gives back is its caller's,
    /// and what handing it over took is no one's — put last, over it.
    #[cfg(test)]
    held: isize,
}

impl Callers {
    /// The calling thread's, its last error taken from it.
    fn taken() -> Self {
        Self {
            error: take_last_error(),
            waited: WAITED_HERE.get(),
            built: built_here(),
            #[cfg(test)]
            held: crate::testing::held(),
        }
    }

    /// These, the calling thread's from here on.
    fn put(self) {
        put_last_error(self.error);
        WAITED_HERE.set(self.waited);
        put_built_here(self.built);
        #[cfg(test)]
        crate::testing::put_held(self.held);
    }
}

/// Polls `device` till the GPU has finished everything submitted — as long
/// as that takes — or says wgpu's own word why not. ⚠️In the driver that
/// long, so on the engine's thread for polls and no other
/// ([`EngineThread`]).
///
/// 🚨⛔NO LIMIT OF wgpu's OWN — the limit is who waits it out's
/// ([`Poll::within`]). A poll that gives up reads how far the GPU has got
/// and then asks the queue what is left of it; a submit on the bodies'
/// thread that sees the rest done between the two leaves the queue empty
/// behind a number that says it is not, and wgpu panics there (wgpu-core
/// 30.0.1, `Device::maintain`: 「If the queue is empty, the current
/// submission index (0) should be at least the wait submission index
/// (1)」). 🔬2026-11-14, the limit inside the poll and the crate's tests
/// at once: the tests' engine lost its thread for polls under the waits
/// of no time of `a_wait_past_its_limit_…`, and 620 of 919 failed behind
/// it. A poll that comes back once the GPU is done reads a number at
/// least the one it waited for. ⚠️No test of behaviour goes red by a
/// limit put back here but by that race — a submit between two reads
/// inside wgpu — so `kernels/shared/one_poll.rs` reads the sources for
/// this line: the one poll of a device, and with no limit.
fn polled(device: &wgpu::Device) -> Result<(), String> {
    let polled = device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None });
    polled.map(|_| ()).map_err(|error| format!("poll: {error}"))
}

/// A poll under way on the engine's thread for polls ([`Engine::poll`]):
/// what a wait waits out, outside the driver.
struct Poll {
    asked: Instant,
    /// What answers how it ended — or why nothing will, that thread gone
    /// before it was asked.
    answer: Result<mpsc::Receiver<Result<(), String>>, String>,
}

impl Poll {
    /// Asks `polls` — an engine's thread for polls — to stay in the driver
    /// till the GPU has finished everything submitted on `device`
    /// ([`Engine::poll`]).
    fn asked_of(polls: &EngineThread, device: &wgpu::Device) -> Self {
        let device = device.clone();
        let answer = polls.asked(move || polled(&device)).ok_or_else(last_error);
        Self { asked: Instant::now(), answer }
    }

    /// Waits for it till `limit` from when it was asked, and fails by name
    /// past that — the poll in the driver still, and whoever asks next
    /// behind it —, by wgpu's word where it ended on one, and by what the
    /// device refused meanwhile (`refusals`).
    fn within(self, limit: Duration, refusals: &Refusals) -> Option<()> {
        let left = limit.saturating_sub(self.asked.elapsed());
        let ended = match self.answer.map(|answer| answer.recv_timeout(left)) {
            Ok(Ok(polled)) => {
                polled.map_or_else(fail, Some)?;
                return refusals.told();
            }
            Ok(Err(mpsc::RecvTimeoutError::Timeout)) => {
                return fail(format!("the GPU did not finish within {limit:?}"));
            }
            Ok(Err(mpsc::RecvTimeoutError::Disconnected)) => {
                format!("the engine's thread never answered: {}", mpsc::RecvError)
            }
            Err(gone) => gone,
        };
        // The thread ended under a panic of wgpu's own — a poll's error is
        // fatal to it (wgpu's `Device::poll`), a device lost under the
        // poll among them — or was gone before the poll was asked for. No
        // wait comes back from this engine again.
        refusals.lose(ended.clone());
        fail(ended)
    }
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

/// Why each wait no caller stayed for failed ([`gpu_engine_done_then`]),
/// by the number its caller knows it by — kept till that caller asks.
#[derive(Clone, Default)]
struct Ended(Arc<Mutex<HashMap<u64, String>>>);

impl Ended {
    fn kept(&self) -> std::sync::MutexGuard<'_, HashMap<u64, String>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// Who is told how a wait ended that its caller did not stay for
/// ([`Engine::done_then`]) — once, whatever becomes of the wait. Dropped
/// untold, the thread that was to wait in its caller's stead ended under
/// the wait or was gone before it: the device is gone, as for a wait whose
/// poll never came back ([`Poll::within`]), and that is what is told.
struct Told<Then: FnOnce(Result<(), String>)> {
    then: Option<Then>,
    refusals: Refusals,
}

impl<Then: FnOnce(Result<(), String>)> Told<Then> {
    fn tell(mut self, ended: Result<(), String>) {
        if let Some(then) = self.then.take() {
            then(ended);
        }
    }

    /// Told on `tells` — an engine's thread for waits no caller stays for
    /// — once `poll` ends, as a wait fails by it, at `limit` among them
    /// ([`Poll::within`]).
    fn once_polled(self, tells: &EngineThread, poll: Poll, limit: Duration)
    where
        Then: Send + 'static,
    {
        tells.post(move || {
            let done = poll.within(limit, &self.refusals);
            self.tell(done.ok_or_else(last_error));
        });
    }
}

impl<Then: FnOnce(Result<(), String>)> Drop for Told<Then> {
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
    made.map_or(std::ptr::null_mut(), Engine::boxed)
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
/// ↩️⛔The rest stayed on their caller's till 2026-11-14: alone on a thread
/// of 1 MiB, `write_buffer` of 4 MiB went 22,319 and `write_texture` of a
/// tile 17,371, and no call but these two has a frame the walk can fault
/// on.
///
/// 🚨★★AND IT TAKES NO DEVICE IN HAND AT ALL
/// (the-ui-thread-never-enters-the-driver, 2026-11-14). 🗣️유저 2026-11-13
/// (H57-Q1): 「C · 합성 전체를 엔진 스레드로 — 이게 가장 근본/구조적인
/// 해결같은데 맞나?」 · 「근본/구조적 해결을 원해. 작업이 크더라도」. The
/// stack was not the only cost of a caller's thread in the device:
/// 🔬Surface Pro 11, S5_BA cut 352 (캔버스 베이스, H57, 2026-11-13), every
/// pause of 33 ms and more as a frame was first filled — sixteen, the
/// longest 77 ms — was one buffer made on the UI thread, the allocator
/// making a 256 MiB block for it under its lock, 32–55 ms; and a block made
/// ahead on another thread held that lock against the UI's small buffers
/// all the same, as every dispatch makes some. So a verb's whole body runs
/// here ([`Engine::on_thread`]), and a hand on the device from a thread
/// that is none of the engine's is counted there ([`Engine::device`]).
///
/// ⏳One thread for every body, as every submit and wait was one thread's
/// already (브러시/렌더링, 2026-11-14, the user asleep — theirs to overturn):
/// what one isolate hands over and another reads after stays in order with
/// no word between the two. ⛔Not a thread to each isolate, and not the UI's
/// bodies alone — a worker isolate's thread is walked as the UI's is.
///
/// 🚨★★BUT NO BODY STANDS BEHIND A COMPILE ([`Self::stands_aside`]). A
/// compile is seconds on a slow device, and behind a body that waited for
/// one here every other isolate's verbs would stand — a stroke's behind a
/// save's — where its caller's thread alone stood till the bodies ran here
/// (🗣️관제 2026-11-14 01:21, the-ui-thread-never-enters-the-driver: 「길
/// 위의 일이 아직 안 된 커널을 만나 길이 컴파일 동안 서면, 전에는 부른
/// 스레드만 서던 것이 다른 아이솔레이트의 동사(획 · 재생)까지 선다 … 새
/// 멈춤을 만들고 다음 단계로 가지 않는다」); and the app compiles ahead
/// what a hand needs side by side (🗣️유저 2026-11-13,
/// the-wait-window-stands-seven-seconds-on-the-surface-Q1, 「나란히
/// 컴파일」 — `compileAppKernelsAhead`, seven verbs at once). So the thread
/// a body waits for a compile on leaves its turn at the jobs for one
/// handed behind it — taken by another of the engine's threads, made
/// where none is there ([`Turns`]; ↩️it ended with its body, and one was
/// made each time, till 2026-11-15) — and takes none till that body is
/// done: two bodies are under way at once only where one of them waits —
/// for a compile, or, lent, for the GPU (🚨NOR BEHIND A BODY'S OWN WAIT,
/// below) — as two callers' were on their own threads.
///
/// ⏳⛔Not the verbs that compile named one by one, each run on a thread
/// made for it (↩️weighed 2026-11-14, 브러시/렌더링 — the user's to
/// overturn): a kernel first asked for under any other verb — an effect
/// chain's, a surface format's pass, an export's read — was a compile here
/// all the same, held off by nothing but a count every test had to read.
///
/// ⚠️What this does not reach: a body that waits for a lock another holds
/// across its compile waits here, and the bodies behind it with it, till
/// that compile is through. So a cell a compile fills is made outside
/// its lock (`kernels::shared`, `kept_or_made`), and the composite's
/// passes lie behind locks nothing that compiles can reach
/// (`kernels/composite/passes.rs`).
///
/// ⚠️ALL OF THEM AT ONCE: a body left on its caller's thread, holding a
/// lock of the engine's as it hands its submit here, waits for a body here
/// that waits for that lock.
///
/// 🚨★★NOR BEHIND THE GPU (the-ui-thread-never-enters-the-driver, 1c,
/// 2026-11-14): a wait's poll is on a thread kept for polls
/// (`Engine::polls`), not on the one the bodies run on. A screen asks to
/// be told of every frame it draws (`ScreenTexture.present`,
/// [`Engine::done_then`]), and that poll stays in the driver as long as
/// the GPU takes over the frame: on the bodies' thread every verb asked
/// meanwhile — the next sample of a stroke, a free — stood behind it that
/// long, where its submit alone did till the bodies ran here. What lets a
/// body go on beside a poll (wgpu-core 30.0.1, read 2026-11-14): the poll
/// holds the device's snatch lock through its wait to read
/// (`Device::poll_and_return_closures`), as a submit and the making of a
/// thing take it; a `destroy` and a surface's `present` take it to write
/// — ⚠️so Android's present (`platform/android.rs`), the one such call a
/// body makes, stands behind a poll under way still: as it did while the
/// poll was a job of this thread, and not measured (🗣️관제 2026-11-14
/// 07:37: 「지금과 같다 · 재지 못했다」로 선언 옆에 적는다).
/// 🔬A body asked while such a wait was on its way, an engine of its own,
/// main PC (RTX 4080), a debug build beside the machine's test line,
/// 2026-11-14: back in 3.9–4.0 ms where the GPU took 3.8–3.9 ms over
/// sixteen copies of 64 MiB, and in 43–63 µs with the poll on the thread
/// for polls, the GPU taking 4.1–4.4 ms. ⚠️Not measured in the app: no
/// screen of a test without a window asks to be told (`_SurfaceTexture`
/// is given no `done`), and six strokes there put no such poll on this
/// thread at all.
///
/// ⏳Every poll on that one thread, a body's own wait among them
/// (브러시/렌더링, 2026-11-14, the user asleep — theirs to overturn): the
/// body waits either way, behind nothing it would not have waited for —
/// the GPU finishes what was submitted in its order — and the engine
/// waits in the driver in one place. ⛔Not a body's wait polled where the
/// body is: two polls at once, for a hand-over of some 50 µs saved.
/// And no poll gives up by a limit of wgpu's own (`polled` has what one
/// did beside a submit): a wait is waited out outside the driver — by
/// the body that asked, or, where no caller stays, by a thread kept to
/// tell of it (`Engine::tells`) — and fails by name at its limit there
/// (🗣️관제 2026-11-08: 「멈춘 화면보다 이름 있는 실패」).
///
/// 🚨★★NOR BEHIND A BODY'S OWN WAIT
/// (the-ui-thread-never-enters-the-driver, 2026-11-15). ↩️「The body waits
/// either way」, above, counted the body that waits and not the bodies
/// behind it: lent, it kept this thread through its wait, and every verb
/// asked meanwhile stood behind the GPU with it, where its caller's
/// thread alone stood till the bodies ran here — what 🗣️관제 said of a
/// compile on the 14th (01:21, above), and of this on the 15th (13:52):
/// 「1c 가 폴을 폴 스레드로 옮긴 것의 남은 반쪽이다」. 🔬Main PC, S5_BA cut
/// 352, a stroke of 120 moves drawn as the band fills (k850–k853,
/// 2026-11-15): each `gpu_engine_stroke_land` of the UI's that waited
/// 300 µs and more for its turn — 9 to 18 of 121, 5.8–36.5 ms a stroke —
/// stood behind a `gpu_engine_stamp_picture_read` another thread had
/// lent, in its wait of 1.3–5.8 ms; none behind a body handed over
/// unwaited. So a body lent leaves the jobs at its wait as at a compile
/// ([`Engine::wait_within`], [`Self::stands_aside`]); one handed over
/// unwaited keeps its turn through it, as through a compile. 🔬With it,
/// the same stroke, before · after · before · after in one sitting (k901
/// – k904): what the UI's `gpu_engine_stroke_land` waited for its turn,
/// 33.1 · 47.7 ms a stroke → 4.4 · 4.2 ms, and of 300 µs and more 8 · 20
/// calls → none (0.3 ms the longest).
///
/// ⏳⛔Not the verbs that read named one by one, each cut into a body
/// that stages, a wait on its caller's thread and a body that copies
/// (↩️weighed 2026-11-15, 브러시/렌더링 — the user's to overturn): a copy
/// of that cut in each of some eighteen, and none for a body that waits
/// midway — `CelPixels::passed` between its count and its write, a
/// flood between its rounds, a plug-in between its chunks.
///
/// What lets the bodies behind it pass (read 2026-11-15; 🗣️관제 13:52
/// asked each written where the law is):
/// - The bodies under way at once are of callers each in a call of its
///   own. The caller of a body lent stays in its call till the body is
///   back, and what it handed over unwaited before was handed before,
///   and has run: nothing of its own passes it. What passes is other
///   callers', as theirs ran beside it on their threads till 2026-11-14.
/// - No lock of the engine's is held through a wait, so none is taken in
///   two orders across one: each is taken and let go inside a call that
///   asks the GPU nothing (`ChainRead`, `HeldChains`, `Work`,
///   `Pictures::with`, the masks' `Kept`, the glyphs' styles,
///   [`Kernels`], [`Refusals`], [`PostedRefused`]).
/// - What a body writes before a wait and reads after it is its own:
///   made in that call, or taken out of what its kernel keeps till it
///   gives it back (the masks' `Kept`). ⚠️One body goes back, after a
///   wait, to what others write — `CelPixels::passed`, to the pool's
///   pages it counted. It is asked by the isolate whose pool that is, in
///   the call still (`cel_pixel_overwrite.dart`): a pool's books are its
///   caller's alone (`gpu_engine_pool_new` has the law), so no slot it
///   counted is let go and given again under it.
/// - A poll waits for what was submitted as it began (`polled`,
///   `submission_index: None`): bodies that go on submitting behind a
///   wait do not hold it.
#[derive(Clone)]
pub(crate) struct EngineThread {
    jobs: mpsc::Sender<Job>,
    /// What its threads know themselves by ([`WORKS_FOR`]).
    number: u64,
    /// Whether work of the driver's own panicked here ([`Self::run`],
    /// [`Self::post`]) — wgpu's poll does, where a device is lost under it.
    /// Ended, it is handed no such work again: a run fails by name and a
    /// post is dropped unrun, as when the thread itself ended with the
    /// panic (↩️till 2026-11-14). It goes on for the bodies handed to it
    /// ([`Self::run_lent`]), which run nowhere else, and fail there by the
    /// device that is gone.
    ended: Arc<AtomicBool>,
    /// What its threads take their jobs from, each the next once it is
    /// through with its own — kept here for the thread made where one
    /// stands aside ([`Self::stands_aside`]).
    asked: Arc<Mutex<mpsc::Receiver<Job>>>,
    /// Which of its threads take them ([`Turns`]).
    turns: Arc<(Mutex<Turns>, Condvar)>,
}

/// The turns at an [`EngineThread`]'s jobs — as many as the threads it was
/// started with, which hold them from the first — and the jobs handed and
/// not yet taken. A thread takes jobs by the turn it holds. Where its job
/// is to wait it leaves the turn ([`EngineThread::stands_aside`]) for a
/// job handed behind it: a thread that holds none takes the turn once
/// there is such a job ([`Self::taken`]), and where none came the thread
/// that left it has it again as its job ends ([`Self::back`]). So bodies
/// that wait with none behind them run on one thread, woken by nothing
/// more than they were; a thread is made where a turn is left and none is
/// there to take it, and for no wait after — an engine has as many
/// threads as it had bodies under way at once.
///
/// ↩️Till 2026-11-15 a thread that stood aside ended with its job and one
/// was made in its place each time — a compile's price, by what was
/// measured for it (🔬50–60 µs, 2026-11-09, [`EngineThread`]). At each wait
/// of a body's for the GPU it was not that. 🔬S5_BA cut 352, main PC,
/// 2026-11-15, the measuring test's 437 waits a run (k901 · k903 with no
/// thread made, k902 · k904 with one made at each wait): a thread was made
/// in 98–101 µs on average, 432–681 µs the longest, and the body that ran
/// first on a thread just made took 0.21–0.27 ms the longer —
/// `gpu_engine_stroke_pile`'s 120 bodies of a stroke on a full band
/// 85.9–90.4 ms → 109.2–121.9 ms, the body after each
/// (`gpu_engine_stroke_land`) as before, 100.7–106.4 → 102.7–109.3 ms.
///
/// ↩️Nor is the turn handed on at each wait, a job behind it or none
/// (weighed the same day, never landed): two threads then took the jobs
/// turn about, one woken at every wait. 🔬The same test so (k912): those
/// 120 bodies 91.2–93.4 ms. And a save of twenty whole-canvas cels, its
/// 6,440 reads one after another with none behind
/// (`a_heavy_save_holds_the_screen_benchmark`, before · after twice each,
/// k913–k920): written whole, 1,727 · 1,750 ms → 1,822 · 1,902 ms, its
/// first report at 1,154 · 1,187 → 1,318 · 1,338 ms; appended, the same
/// (1,501 · 1,596 → 1,518 · 1,523 ms). ⚠️That test's totals stand 100 ms
/// apart on one build, and the engine's own lines say no more of it:
/// the bodies' sum 2,040–2,192 ms either way.
///
/// 🔬With the turn had again where no job came (k922–k926): each of that
/// save's 6,443 waits had its turn again, on one thread, the lock taken
/// for it 0.4 µs a wait, the bodies' sum 2,052 · 2,199 ms; and of the
/// measuring test's 437 waits 419 had it again and 18 found it taken by a
/// job handed behind them — one thread made — the UI's
/// `gpu_engine_stroke_land` waiting 2.7 ms a stroke as the band filled
/// (33.1 · 47.7 ms with no turn left, [`EngineThread`]).
#[derive(Default)]
struct Turns {
    /// The turns no thread holds.
    free: usize,
    /// The threads that hold none and are through with the job they left
    /// theirs in ([`Self::back`]): waiting for a turn left, or on their
    /// way to.
    spare: usize,
    /// The jobs handed and not yet taken ([`EngineThread::hands`]).
    queued: usize,
    /// Whether no job is handed here again: a thread that waits for a turn
    /// ends.
    over: bool,
}

impl Turns {
    /// One more job is handed: where a turn is left free, a thread that
    /// waits for one takes it.
    fn handed(shared: &(Mutex<Self>, Condvar)) {
        let (turns, left) = shared;
        let mut turns = turns.lock().unwrap_or_else(PoisonError::into_inner);
        turns.queued += 1;
        if turns.free > 0 {
            left.notify_one();
        }
    }

    /// A thread that holds a turn has taken a job.
    ///
    /// ⚠️A count that ran short stays at none and is not a panic: here a
    /// panic ends a thread that takes the engine's jobs, and every caller
    /// after it waits for good. Short, the count leaves a turn left to its
    /// leaver alone, which the pins of a body behind a wait say by name.
    fn received(shared: &(Mutex<Self>, Condvar)) {
        let mut turns = shared.0.lock().unwrap_or_else(PoisonError::into_inner);
        turns.queued = turns.queued.saturating_sub(1);
    }

    /// Waits for a turn left free with a job handed behind it, and takes
    /// the turn — or for none to be taken again, and says so.
    fn taken(shared: &(Mutex<Self>, Condvar)) -> bool {
        let (turns, left) = shared;
        let mut turns = turns.lock().unwrap_or_else(PoisonError::into_inner);
        while (turns.free == 0 || turns.queued == 0) && !turns.over {
            turns = left.wait(turns).unwrap_or_else(PoisonError::into_inner);
        }
        if turns.over {
            return false;
        }
        turns.free -= 1;
        turns.spare -= 1;
        TURN.set(Turn::Held);
        true
    }

    /// The calling thread is through with the job it left its turn in: it
    /// has the turn again where no other took it, and is else one more
    /// that waits for a turn — once for a job, whoever says it again.
    ///
    /// 🚨A job whose caller waits for it says so BEFORE its answer goes
    /// ([`EngineThread::run_lent`]), not as its thread comes back for the
    /// next: the caller's next body then finds the turn held, by the
    /// thread its last ran on, and wakes no other for it — one caller, one
    /// thread, by the order and not by which thread was ahead (🗣️관제
    /// 2026-11-15 14:35, of the thread that took the turn at every wait:
    /// 「빌린 본문의 답을 넘기기 전에 자리 장부를 돌려놓거나 … 그러면
    /// 「한 부르는 쪽 = 스레드 둘」이 확률이 아니라 사실이 된다」). Said
    /// after the answer, a caller that got ahead of this thread found the
    /// turn free still and handed its body to another. A job run for the
    /// driver's own work ([`EngineThread::run`]) says so after its answer,
    /// as its thread comes back — none such waits: the bodies' thread is
    /// handed a submit that way and no more ([`Queue::submit`]; the
    /// compiles, the polls and the tells run on threads of their own,
    /// read 2026-11-15, 🗣️관제 15:30).
    /// ⚠️No test turns red where the order is turned back: what it loses
    /// is a race of the tens of microseconds a caller takes to wake, and
    /// nothing here holds a thread in them.
    fn back(shared: &(Mutex<Self>, Condvar)) {
        if TURN.get() != Turn::Left {
            return;
        }
        let mut turns = shared.0.lock().unwrap_or_else(PoisonError::into_inner);
        if turns.free > 0 {
            turns.free -= 1;
            TURN.set(Turn::Held);
        } else {
            turns.spare += 1;
            TURN.set(Turn::Waits);
        }
    }

    /// No job is handed again: the threads that wait for a turn end.
    fn over(shared: &(Mutex<Self>, Condvar)) {
        shared.0.lock().unwrap_or_else(PoisonError::into_inner).over = true;
        shared.1.notify_all();
    }
}

/// Where a thread of an [`EngineThread`]'s is with its turn at the jobs
/// ([`Turns`]).
#[derive(Clone, Copy, PartialEq, Eq)]
enum Turn {
    /// It holds one, and takes the jobs.
    Held,
    /// It left its own in the job it is in, for a job handed behind it
    /// ([`EngineThread::stands_aside`]).
    Left,
    /// It holds none, another having taken the one it left, and is
    /// through with that job ([`Turns::back`]) — or was made to take one
    /// left ([`EngineThread::works`]): counted among the threads that wait
    /// for a turn.
    Waits,
}

impl EngineThread {
    fn start() -> Option<Self> {
        Self::start_many(1)
    }

    /// `count` threads that take what is handed to them in turn, each the
    /// next job once it is through with its own.
    fn start_many(count: usize) -> Option<Self> {
        let (jobs, asked) = mpsc::channel::<Job>();
        let started = Self {
            jobs,
            number: THREAD_NUMBERS.fetch_add(1, Ordering::Relaxed),
            ended: Arc::default(),
            asked: Arc::new(Mutex::new(asked)),
            turns: Arc::default(),
        };
        for _ in 0..count {
            if let Err(error) = started.works(Turn::Held) {
                return fail(format!("no thread for the engine: {error}"));
            }
        }
        Some(started)
    }

    /// One more thread for this one's jobs, `turn` its own from the first
    /// — held, or to be waited for ([`Turns`]): it takes the jobs by the
    /// turn it holds, each the next once it is through with its own, till
    /// none is left to hand it any — and where another took the turn it
    /// left in a job ([`Self::stands_aside`]) it waits, that job done,
    /// for the next left.
    fn works(&self, turn: Turn) -> std::io::Result<()> {
        let (asked, turns) = (Arc::clone(&self.asked), Arc::clone(&self.turns));
        let number = self.number;
        let working = move || {
            WORKS_FOR.set(number);
            TURN.set(turn);
            while TURN.get() == Turn::Held || Turns::taken(&turns) {
                let next = asked.lock().unwrap_or_else(PoisonError::into_inner).recv();
                let Ok(job) = next else {
                    return Turns::over(&turns);
                };
                Turns::received(&turns);
                job();
                // Where the job did not say so itself: no caller waited
                // for it.
                Turns::back(&turns);
            }
        };
        std::thread::Builder::new().name("gpu_engine".into()).spawn(working).map(drop)
    }

    /// Leaves this thread's turn at the jobs for one handed behind the
    /// job it is in, where the calling thread is this one — to be taken by
    /// a thread that left its own before and waits, or by one made here
    /// where none does ([`Turns`]): what its job waits for from here on,
    /// no job behind it waits for ([`EngineThread`] has why — a compile,
    /// the GPU). The calling thread goes on with its job, this thread to
    /// itself still ([`Self::is_here`]) — what the job hands here runs
    /// where it is, as it did — and, the job done, has its turn again
    /// where no job came for it, and else waits for one left
    /// ([`Turns::back`]). Once in a job: it has no turn left to leave.
    ///
    /// With no thread to be had the job goes on where it is and those
    /// behind it wait, as they did: nothing fails that worked.
    ///
    /// ⚠️Under way beside the jobs after it, not before them — so ⛔NOT IN
    /// A JOB HANDED HERE UNWAITED ([`Self::posts`]): no caller waits there
    /// for the job's end, and the jobs behind it are what its caller handed
    /// after — a done of the job's own work among them
    /// ([`Engine::done_then`]), and the free of what it reads. Such a job
    /// keeps its turn through a compile, the jobs behind it waiting, as its
    /// caller's order is (the-ui-thread-never-enters-the-driver B1-a,
    /// 2026-11-15); what it compiles is counted on its caller's thread
    /// ([`Engine::posted`]), where the app's pin holds it at none — the
    /// app compiles ahead what such a body runs.
    fn stands_aside(&self) {
        if !self.is_here() || TURN.get() != Turn::Held || POSTED.get() {
            return;
        }
        let (turns, left) = &*self.turns;
        let mut turns = turns.lock().unwrap_or_else(PoisonError::into_inner);
        if turns.spare == 0 {
            if self.works(Turn::Waits).is_err() {
                return;
            }
            turns.spare += 1;
        }
        turns.free += 1;
        if turns.queued > 0 {
            left.notify_one();
        }
        TURN.set(Turn::Left);
    }

    /// Hands `job` to this one's threads, behind every one handed before
    /// it — and to the turn a job that waits left free, where one did
    /// ([`Turns`]).
    fn hands(&self, job: Job) {
        Turns::handed(&self.turns);
        let _ = self.jobs.send(job);
    }

    /// Whether the calling thread is this one — one of these, where they
    /// are many, one that stood aside among them.
    fn is_here(&self) -> bool {
        WORKS_FOR.get() == self.number
    }

    /// `work`, as this thread runs it: not at all once the thread has
    /// ended, and the thread's end where it panics ([`Self::ended`]).
    ///
    /// 🚨`answers` — what tells who waits that `work` is through — is let
    /// go of once the end is said, so who finds no answer finds the thread
    /// ended. Held by `work` itself it went as the panic unwound, before
    /// the word: a wait asked in between was handed to a thread that then
    /// dropped it unrun, and was told it never answered (🔬2026-11-14,
    /// `an_engine_whose_thread_ended_is_gone` red once, beside 18 suites).
    fn till_it_ends<Answers: Send + 'static, Work: FnOnce(&Answers) + Send + 'static>(
        &self,
        answers: Answers,
        work: Work,
    ) -> impl FnOnce() + Send + 'static + use<Answers, Work> {
        let ended = Arc::clone(&self.ended);
        move || {
            if ended.load(Ordering::Acquire) {
                return;
            }
            if catch_unwind(AssertUnwindSafe(|| work(&answers))).is_err() {
                ended.store(true, Ordering::Release);
            }
        }
    }

    /// What `work` answers, run on this thread while the caller waits —
    /// where it is, on this thread already: a body's submit
    /// ([`Self::run_lent`]), which handed over would wait for itself.
    fn run<T: Send + 'static>(&self, work: impl FnOnce() -> T + Send + 'static) -> Option<T> {
        match self.asked(work)?.recv() {
            Ok(worked) => Some(worked),
            Err(error) => fail(format!("the engine's thread never answered: {error}")),
        }
    }

    /// What answers what `work` answers once this thread has run it — where
    /// it is asked, on this thread already — for the caller to wait for as
    /// long as it will: none where the thread is gone (the last error),
    /// and no answer where it ended under `work`.
    fn asked<T: Send + 'static>(
        &self,
        work: impl FnOnce() -> T + Send + 'static,
    ) -> Option<mpsc::Receiver<T>> {
        if self.ended.load(Ordering::Acquire) {
            return fail("the engine's thread is gone");
        }
        let (answer, answered) = mpsc::channel();
        let job = self.till_it_ends(answer, move |answer| {
            let _ = answer.send(work());
        });
        if self.is_here() {
            job();
        } else {
            self.hands(Box::new(job));
        }
        Some(answered)
    }

    /// Hands `work` to this thread and returns, the caller waiting for
    /// none of it, as a job in the bodies' turn: run behind every one
    /// handed before it, and keeping its turn through a compile
    /// ([`Self::stands_aside`]) — on this thread already, run where it is.
    /// Run even where the driver's own work has ended the thread
    /// ([`Self::ended`]), as a body is: it is run nowhere else. A panic of
    /// it ends the thread as the driver's own work does — no caller is
    /// left to take the panic ([`Self::lets_go`]).
    fn posts(&self, work: impl FnOnce() + Send + 'static) {
        if self.is_here() {
            return work();
        }
        let ended = Arc::clone(&self.ended);
        let job = move || {
            POSTED.set(true);
            let panicked = catch_unwind(AssertUnwindSafe(work)).is_err();
            POSTED.set(false);
            if panicked {
                ended.store(true, Ordering::Release);
            }
        };
        self.hands(Box::new(job));
    }

    /// Hands `work` to this thread and returns, the caller waiting for
    /// none of it. Dropped unrun where the thread is gone.
    fn post(&self, work: impl FnOnce() + Send + 'static) {
        if !self.ended.load(Ordering::Acquire) {
            self.hands(Box::new(self.till_it_ends((), move |()| work())));
        }
    }

    /// What `work` answers, run on this thread while the caller waits, as
    /// a call: with all the caller lends it — what `work` borrows, and what
    /// the caller's thread keeps for itself, which goes over with it and
    /// comes back ([`Callers`]) — and a panic of `work`'s the caller's, as
    /// it was on the caller's thread. On this thread already, it runs where
    /// it is.
    fn run_lent<T>(&self, work: impl FnOnce() -> T) -> T {
        if self.is_here() {
            return work();
        }
        let callers = Callers::taken();
        let mut worked = None;
        let (through, waited) = mpsc::channel::<()>();
        {
            let worked = &mut worked;
            let job: Box<dyn FnOnce() + '_> = Box::new(move || {
                // Dropped as the job ends, run or not: the caller's word to
                // go on.
                let _through = through;
                callers.put();
                let answer = catch_unwind(AssertUnwindSafe(work));
                *worked = Some((answer, Callers::taken()));
                // Before `_through` goes ([`Turns::back`] has why).
                Turns::back(&self.turns);
            });
            // SAFETY: the job borrows from this call's frame and is `Send`
            // in name alone. The caller stays in this frame till the job
            // has run or been dropped — `waited` answers at neither before
            // — so what the job borrows outlives it, in one thread's hands
            // at a time, as what a call is handed.
            let job = unsafe { std::mem::transmute::<Box<dyn FnOnce() + '_>, Job>(job) };
            self.hands(job);
        }
        let _ = waited.recv();
        // Let go before the caller's own are put back, the heap the tests
        // count among them ([`Callers`]).
        drop(waited);
        let Some((answer, callers)) = worked else {
            panic!("the engine's thread is gone");
        };
        callers.put();
        answer.unwrap_or_else(|panic| resume_unwind(panic))
    }

    /// Hands `kept` to this thread to be let go of there and returns, the
    /// caller waiting for none of it — on this thread already, let go of
    /// where it is. Let go of even where the driver's own work has ended
    /// the thread ([`Self::ended`]), as a body is run: it is let go of
    /// nowhere else. A drop that panics there ends the thread as the
    /// driver's own work does — no caller is left to take the panic.
    fn lets_go<T: 'static>(&self, kept: T) {
        if self.is_here() {
            return drop(kept);
        }
        let (kept, ended) = (Sent(kept), Arc::clone(&self.ended));
        let job = move || {
            if catch_unwind(AssertUnwindSafe(move || drop(kept))).is_err() {
                ended.store(true, Ordering::Release);
            }
        };
        self.hands(Box::new(job));
    }
}

/// What is handed to the engine's thread to be let go of there
/// ([`EngineThread::lets_go`]), or read there by a body handed over
/// unwaited ([`Engine::posted`]): the things a verb was handed.
pub(crate) struct Sent<T>(pub(crate) T);

impl<T> Sent<T> {
    /// What was sent, where it was sent to.
    pub(crate) fn taken(self) -> T {
        self.0
    }
}

// SAFETY: what is let go of is in one thread's hands at a time — its
// caller's till it is sent, which reads it no more, and the engine's from
// there, as what a body is lent is ([`EngineThread::run_lent`]). What a
// body handed over unwaited reads is the engine's thread's as long as it
// runs: its caller hands it on to no other body but through the engine's
// thread, in turn behind it, and what any thread reads of it meanwhile is
// kept for that apart (`kernels/composite/abi.rs`, `ScreenAndBytes`).
unsafe impl<T> Send for Sent<T> {}

/// What a maker of the C ABI hands its caller ([`Engine::hands`]): the
/// thing made, and beside it the thread of the engine that made it, where
/// it is let go of ([`let_go`], [`let_go_unwaited`]).
///
/// 🚨★★WHAT THE ABI HANDED OUT IS LET GO OF ON THE ENGINE'S THREAD
/// (the-ui-thread-never-enters-the-driver 1b, 2026-11-14): letting go of a
/// thing is a hand on the device as making it was — a buffer goes back to
/// the allocator under the lock one is made under ([`EngineThread`] has
/// what that lock cost the UI's thread). A free is handed a pointer and no
/// engine, and the GC's finalizer has no more to hand it (🗣️관제 2026-11-14
/// 02:19: 「파이널라이저는 포인터 하나만 넘기므로 1b 의 물건은 자기가 놓일
/// 스레드를 스스로 쥐고 있어야 한다 … 엔진을 인자로 받는 free 는 길이
/// 아니다」), so the thread is kept with the thing: here, once, and in no
/// type of a kernel's.
///
/// So a maker whose thing holds, or comes to hold, anything of the device
/// is handed the engine: of the eleven made with none till then, a plan
/// came to hold a mask, a screen its pages, a grid lay its pipelines, the
/// chains held and a chain's read their buffers and an export its passes,
/// under verbs that are handed the engine — and a readout held a buffer
/// from the first.
///
/// 🚨WHAT HOLDS NOTHING OF A DEVICE IS NO ENGINE'S ([`hands_bytes`]) — a
/// dab's texels, what a plug-in made, the faces, a picture of letters:
/// bytes in memory, which outlive a device that is lost and are named by
/// whichever engine's job uploads them
/// (`test/architecture/a_job_names_what_its_own_engine_made_test.dart`).
/// ↩️⏳브러시/렌더링 2026-11-14 had every maker handed the engine, those
/// too, so that nothing had to tell the two apart; 🗣️관제 2026-11-14 05:16,
/// the-ui-thread-never-enters-the-driver, overturned it: 「생성자의 `engine`
/// 이 어떤 타입에서는 「누구의 디바이스가 만들었나」이고 어떤 타입에서는
/// 「어느 스레드에서 놓이나」가 된다 … 이 카드의 법은 「드라이버에 안
/// 들어간다」이지 「메모리의 바이트도 엔진 스레드에서 놓는다」가 아니다」.
/// What tells the two apart is read, not remembered
/// (`kernels/shared/one_handing_out.rs`).
///
/// The thread stands for as long as a thing of its engine's does, past the
/// engine's own close: what the GC lets go of comes when the GC comes.
///
/// `repr(C)`, the thing first: a pointer to the whole is a pointer to the
/// thing, which every verb reads through.
#[repr(C)]
struct Handed<T> {
    kept: T,
    thread: EngineThread,
    /// The bytes it counts among the engine's live ones, where it counts
    /// any ([`Engine::hands_counted`]).
    counted: Option<Counted>,
}

/// `handed`'s whole, and the thread it is let go of on; none of a null.
///
/// # Safety
/// `handed` came from [`Engine::hands`], and is taken once.
unsafe fn taken<T>(handed: *mut T) -> Option<(EngineThread, Box<Handed<T>>)> {
    if handed.is_null() {
        return None;
    }
    // SAFETY: by the contract, the pointer `Engine::hands` made of a
    // `Handed<T>`'s box, whose first field it points to.
    let whole = unsafe { Box::from_raw(handed.cast::<Handed<T>>()) };
    Some((whole.thread.clone(), whole))
}

/// Lets go of what [`Engine::hands`] handed out — nothing of a null — on
/// the thread of the engine that made it, the caller waiting till it is
/// gone: what the thing counted is counted off as its free returns (the
/// `*_BYTES` the app's tests read right after one), as when the caller's
/// own thread let go of it.
///
/// # Safety
/// `handed` came from [`Engine::hands`], and is let go of once.
pub(crate) unsafe fn let_go<T>(handed: *mut T) {
    // SAFETY: see the function's contract.
    if let Some((thread, whole)) = unsafe { taken(handed) } {
        thread.run_lent(move || drop(whole));
    }
}

/// What `work` answers, run while the caller waits on the thread of the
/// engine that made `handed`, as [`Engine::on_thread`] runs a verb's body:
/// for a verb that is handed a thing and no engine, and takes a hand on the
/// device by it all the same — lets go of what the thing keeps of the
/// device, or asks the driver for its next image.
///
/// 🔬Three of the 71 verbs handed neither an engine nor a thing to free did
/// (2026-11-14, each body read): `gpu_engine_held_let_go` and
/// `gpu_engine_blurs_let_go` let buffers go on their caller's thread, and
/// Android's `gpu_engine_window_target` took the swapchain's image there —
/// past `every_verb.rs`, which read the verbs handed the engine alone till
/// then.
///
/// # Safety
/// `handed` came from [`Engine::hands`], and is live.
pub(crate) unsafe fn on_thread_of<T, Made>(handed: *const T, work: impl FnOnce() -> Made) -> Made {
    // SAFETY: by the contract, the first field of a live `Handed<T>`.
    let thread = unsafe { &(*handed.cast::<Handed<T>>()).thread };
    thread.run_lent(work)
}

/// Hands `work` to the thread of the engine that made `handed` and
/// returns, the caller waiting for none of it, as [`Engine::posted`] hands
/// a verb's body over ([`EngineThread::posts`]): run there in turn, behind
/// every body handed before it. For a verb handed a thing and no engine
/// that lets go, in the turn of a gesture, of what the thing keeps of the
/// device — and takes nothing back.
///
/// 🔬`gpu_engine_held_let_go` stood 48–63 ms on the UI's thread at each
/// value of a blur dragged, all of it the drop of one put of 18–23 MiB
/// — its lock 0, its remove 0 — and before that, every compose ahead of
/// it on this thread (서피스11 캔버스 베이스, the Surface, S5_BA cut 352,
/// 2026-11-20, card a-blur-drag-stops-once-on-its-first-frame). ↩️Till
/// then it waited there ([`on_thread_of`]), as the two that let go at
/// rest still do — the blurs' strokes' and the selection masks', asked
/// where the OS says memory is tight, whose bytes the census reads gone
/// as they return.
///
/// ⛔Not let go of on the caller's thread, ahead of its turn: a compose
/// handed over before it that names the number would miss, run its
/// chain again and keep what it put under a number the app has let go
/// of, for good — the app gives no number twice (`EngineChainHolds.idOf`).
///
/// ⚠️What `work` counts off is counted off as it runs, not as its verb
/// returns: who reads the count asks for a done first
/// ([`Engine::done_then`], in turn behind it).
///
/// # Safety
/// `handed` came from [`Engine::hands`], and is live.
pub(crate) unsafe fn posted_of<T>(handed: *const T, work: impl FnOnce() + Send + 'static) {
    // SAFETY: by the contract, the first field of a live `Handed<T>`.
    let thread = unsafe { &(*handed.cast::<Handed<T>>()).thread };
    thread.posts(work);
}

/// `made`, handed to the caller over the ABI where it holds nothing of a
/// device — bytes in memory ([`Handed`] has which, and why they are no
/// engine's): a bare box, [`let_go_bytes`]'s to let go of on whatever
/// thread frees it, or [`taken_bytes`]'s to take back where a verb uses
/// it up. ⚠️A type that comes to hold anything of the device
/// leaves this door for [`Engine::hands`]: `one_handing_out.rs` reads
/// each type's fields for it — till the device's things are told by a
/// type of their own (stage 2 of the-ui-thread-never-enters-the-driver),
/// where that scan goes.
pub(crate) fn hands_bytes<T>(made: T) -> *mut T {
    Box::into_raw(Box::new(made))
}

/// Lets go of what [`hands_bytes`] handed out — nothing of a null — where
/// its caller is: no device is taken in hand for it.
///
/// # Safety
/// `handed` came from [`hands_bytes`], and is let go of once.
pub(crate) unsafe fn let_go_bytes<T>(handed: *mut T) {
    if !handed.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { taken_bytes(handed) });
    }
}

/// What [`hands_bytes`] handed out, taken back whole where its caller is
/// — by a verb handed its thing to use up, which no free lets go of
/// after it (`gpu_engine_faces_of` sets up the faces it was handed a
/// file at a time).
///
/// # Safety
/// `handed` came from [`hands_bytes`], is not null, and is taken back
/// once.
pub(crate) unsafe fn taken_bytes<T>(handed: *mut T) -> T {
    // SAFETY: see the function's contract.
    *unsafe { Box::from_raw(handed) }
}

/// Lets go of what [`Engine::hands`] handed out as [`let_go`] does, but
/// the caller waiting for none of it: the frees the GC calls of an
/// engine's things — the ones the app binds a native finalizer to — and,
/// past them, only frees each named with why: of things that count
/// nothing, and a screen's, which counts its part off first
/// (`test/architecture/a_free_the_gc_calls_waits_for_nothing_test.dart`
/// reads both sides; a thing of bytes the GC lets go of is let go of where
/// the GC is, [`let_go_bytes`]).
///
/// 🔬A native finalizer's callback holds every isolate of its group for as
/// long as it takes (Dart 3.13.3, `dart run`, the main PC, 2026-11-14: a
/// callback of 300 ms — kernel32's `Sleep` — and the main isolate and a
/// worker each stood 315 ms, six times of six; 2.5 ms with none). Waiting
/// here, the GC would hold the UI for every body ahead on the engine's
/// thread, a save's read back among them, where it let go at once on its
/// own thread till now.
///
/// ⏳So what the GC lets go of is not waited for, and the rest is
/// (브러시/렌더링 2026-11-14, the user asleep — theirs to overturn). ⛔Not
/// every free unwaited before stage 2 of
/// the-ui-thread-never-enters-the-driver: three of the counts are counted
/// off where the thing is dropped (`HELD_BYTES`, `READOUT_BYTES`,
/// `FLOOD_BYTES`; `KEPT_BYTES` was the fourth till a screen's free came
/// here, 2026-11-16 — kernels/composite/abi.rs) and would read late, to
/// the app's tests and the leak pins alike. What its thing counts
/// ([`Engine::hands_counted`]) is counted off here, on its caller's
/// thread, before the rest goes — no free has the counting off to forget.
/// ↩️Each free counted off its own by hand till 2026-11-17 (`MASK_BYTES`,
/// `STAMP_PICTURE_BYTES` — live-bytes-are-counted-by-hand-in-four-places);
/// a screen counts off its part itself, by what its last body told
/// (kernels/composite/abi.rs).
///
/// # Safety
/// `handed` came from [`Engine::hands`], and is let go of once.
pub(crate) unsafe fn let_go_unwaited<T: 'static>(handed: *mut T) {
    // SAFETY: see the function's contract.
    if let Some((thread, mut whole)) = unsafe { taken(handed) } {
        drop(whole.counted.take());
        thread.lets_go(whole);
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
/// on it has been freed — but what the GC lets go of, which comes when the
/// GC does ([`Handed`]).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_close(engine: *mut Engine) {
    if !engine.is_null() {
        // SAFETY: see the function's contract.
        let engine = unsafe { Box::from_raw(engine) };
        // Let go on its own thread, as all it held of the device was taken
        // there — this hold on the thread keeping it till then. ⛔And
        // waited for no further: a poll under way is not (`Engine::polls`).
        let thread = engine.thread.clone();
        thread.run_lent(move || drop(engine));
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

/// What [`gpu_engine_video_memory`] says, field by field: each number where
/// its bit of `flags` says the OS said it ([`platform::VideoMemory`]).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VideoMemoryReport {
    pub used: u64,
    pub budget: u64,
    pub in_system: u64,
    pub total: u64,
    pub flags: u32,
}

// `VideoMemoryReport::flags`.
pub const USED_SAID: u32 = 1;
pub const BUDGET_SAID: u32 = 2;
pub const IN_SYSTEM_SAID: u32 = 4;
/// The adapter shares the system's RAM (wgpu's `DeviceType::IntegratedGpu`).
pub const INTEGRATED: u32 = 8;
pub const TOTAL_SAID: u32 = 16;

/// Writes into `report` this process's use of the adapter's local video
/// memory, the budget the OS gives it there, what of its video memory
/// lies in the system's RAM and all the adapter's own memory, where the
/// OS says those — and whether the adapter is one that shares the
/// system's RAM.
///
/// 🗣️관제 11-12 (vram-in-use-shown-in-the-memory-tab): ONE EXPORT for all a
/// memory census reads of the GPU — the memory tab's VRAM line and whether
/// what the GPU holds is counted in the process's RAM read from it alike.
///
/// # Safety
/// `engine` is live and `report` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_video_memory(
    engine: *const Engine,
    report: *mut VideoMemoryReport,
) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    let integrated = engine.adapter.get_info().device_type == wgpu::DeviceType::IntegratedGpu;
    let mut said = VideoMemoryReport {
        flags: if integrated { INTEGRATED } else { 0 },
        ..VideoMemoryReport::default()
    };
    if let Some(memory) = platform::video_memory(&engine.adapter) {
        said.used = memory.used;
        said.flags |= USED_SAID;
        if let Some(budget) = memory.budget {
            said.budget = budget;
            said.flags |= BUDGET_SAID;
        }
        if let Some(in_system) = memory.in_system {
            said.in_system = in_system;
            said.flags |= IN_SYSTEM_SAID;
        }
        if let Some(total) = memory.total {
            said.total = total;
            said.flags |= TOTAL_SAID;
        }
    }
    // SAFETY: see the function's contract.
    unsafe { report.write(said) };
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

/// Why `engine`'s device went, as far as anything says — one of
/// `platform::WENT_*`, unsaid where nothing does and while the device is
/// there ([`Engine::went_by`]): what the app tells the person of a device
/// it has opened another in place of.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_went_by(engine: *const Engine) -> u32 {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| engine.went_by())
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

/// Copies what `engine` submitted that the GPU has not said it finished,
/// and the newest it has ([`Submits::told`]), into `buffer` (UTF-8) and
/// returns its full length. Asks nothing of the engine's thread or the
/// device: what the app writes down as a device goes (H63).
///
/// # Safety
/// `engine` is live and `buffer` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_unfinished(
    engine: *const Engine,
    buffer: *mut u8,
    capacity: usize,
) -> usize {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    copy_out(&engine.queue.submits.told(), buffer, capacity)
}

/// [`Engine::done_then`] across the boundary: a thread of the engine's
/// calls `then` with `wait` — the number its caller knows this wait by: one
/// `then` serves every wait of a caller — and whether the GPU finished all
/// that was submitted; where it did not, why is kept under that number for
/// [`gpu_engine_done_failure`]. From that thread; from this one where that
/// thread is gone.
///
/// # Safety
/// `engine` is live. `then` is one any thread may call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_done_then(
    engine: *const Engine,
    then: extern "C" fn(u64, bool),
    wait: u64,
) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    let ended = engine.ended.clone();
    engine.done_then(move |done| {
        if let Err(why) = &done {
            ended.kept().insert(wait, why.clone());
        }
        then(wait, done.is_ok());
    });
}

/// Takes why the wait `wait` failed ([`gpu_engine_done_then`]): copies it
/// (UTF-8) into `buffer` and returns its full length, 0 where none failed
/// under that number — and it is kept no more.
///
/// # Safety
/// `engine` is live and `buffer` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_done_failure(
    engine: *const Engine,
    wait: u64,
    buffer: *mut u8,
    capacity: usize,
) -> usize {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.ended.kept().remove(&wait).map_or(0, |why| copy_out(&why, buffer, capacity))
}

/// How many waits for the GPU the thread that asks has made
/// ([`Engine::wait`]) — its bodies handed over unwaited among them, as far
/// as they have run ([`POSTED_HERE`]): what a test holds at none on the
/// thread an app's frames are built on, over work that is to wait there for
/// nothing ([`Engine::map_then`]).
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_waits_here() -> u64 {
    let posted = POSTED_HERE.with(|counted| counted.waited.load(Ordering::Relaxed));
    WAITED_HERE.with(Cell::get) + posted
}

/// How many times the thread that asks has taken a device in hand
/// ([`Engine::device`]) — made on it, encoded for it or written to it:
/// what a test holds at none on the thread an app's frames are built on, a
/// verb's body being the engine's thread's ([`EngineThread`] has what a
/// caller's thread paid in the device).
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_device_entered_here() -> u64 {
    ENTERED_HERE.with(Cell::get)
}

/// Test seam: `engine`'s device destroyed — the nearest a test comes to a
/// driver taking it away, which no test does. The word that it is lost
/// comes at the next wait ([`Refusals`]) — but where `for_memory`: that
/// one is said here, as wgpu says it of a device it gave up for want of
/// memory ([`OUT_OF_MEMORY`]), the one cause of a loss a test can name.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_lose(engine: *const Engine, for_memory: bool) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        if for_memory {
            // As the lost callback keeps it ([`Engine::on`]).
            engine.refusals.lose(format!("{:?} {OUT_OF_MEMORY}", wgpu::DeviceLostReason::Unknown));
        }
        engine.device().destroy();
    })
}

/// Test seam: `engine`'s thread stands still for `millis` ms in its turn,
/// its caller waiting for none of it ([`Engine::posted`]) — what a test
/// does meanwhile meets a body handed over behind it before it has run
/// (`gpu_engine_pool_store`'s tiles, held till their copy reads them).
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stand_still(engine: *const Engine, millis: u32) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.posted(move || {
        std::thread::sleep(Duration::from_millis(u64::from(millis)));
        Some(())
    });
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
    engine.on_thread(|| engine.kernels.forget())
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
    use crate::testing::{a_device_of_its_own, done_here, first_engine};
    use crate::{fail, last_error};

    #[test]
    fn a_device_is_opened_on_a_thread_of_its_own_not_the_callers() {
        let _turn = a_device_of_its_own();
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
        let turn = a_device_of_its_own();
        let engine = turn.engine();
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
        let turn = a_device_of_its_own();
        let engine = turn.engine();
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

    // 🗣️유저 2026-11-13 (the-wait-window-stands-seven-seconds-on-the-surface-Q1,
    // 「나란히 컴파일」): a compile under way holds up no other — each on a
    // thread of the engine's for compiling of its own (`CompilerTurn`).
    #[test]
    fn a_compile_under_way_holds_up_no_other() {
        let turn = a_device_of_its_own();
        let engine = turn.engine();
        let (release, released) = std::sync::mpsc::channel::<()>();
        let (compiled, answered) = std::sync::mpsc::channel();
        std::thread::scope(|scope| {
            scope.spawn(|| {
                engine.compiling(move |_| {
                    let _ = released.recv_timeout(std::time::Duration::from_secs(60));
                })
            });
            scope.spawn(|| {
                let source = "@compute @workgroup_size(1)\nfn main() {}\n// held up by none";
                let _ = crate::kernels::shared::pipeline(&engine, &[source], "main");
                let _ = compiled.send(());
            });
            let got_through = answered.recv_timeout(std::time::Duration::from_secs(20));
            let _ = release.send(());
            assert!(got_through.is_ok(), "the compile waited behind the other");
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
        let turn = a_device_of_its_own();
        let engine = turn.engine();
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

    // A body's wait, as every verb's is: in the driver neither on its
    // caller's thread nor on the one the body runs on.
    #[test]
    fn a_wait_blocks_in_the_driver_on_the_engines_thread_for_polls() {
        // An engine of its own: a map answers inside the call that sees
        // it done, a submit as a poll, and on the tests' engine another
        // test's submit can be that call (🔬red so, 2026-11-14). Here
        // nothing is submitted, so it is the wait's poll: on the thread
        // that polled.
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let buffer = engine.readback(4);
        let (sender, answered) = std::sync::mpsc::channel();
        buffer.map_async(wgpu::MapMode::Read, .., move |_| {
            let _ = sender.send(std::thread::current().id());
        });
        let body_on = engine.on_thread(|| {
            assert_eq!(engine.wait(), Some(()), "{}", last_error());
            std::thread::current().id()
        });
        let polled_on = answered.try_recv().expect("the map answered inside the wait");
        assert_ne!(polled_on, std::thread::current().id());
        assert_ne!(polled_on, body_on, "polled where the body runs");
    }

    // 🚨A wait no caller stays for holds up no body: a screen asks one of
    // every frame it draws, and the GPU takes as long over it as it takes
    // (`EngineThread` has what stood behind it). A map answers inside the
    // poll that sees it done, and this one stays there — the poll in the
    // driver's call still — till the test has seen a body through, its
    // submit and all.
    #[test]
    fn a_wait_no_caller_stays_for_holds_up_no_body() {
        use std::sync::mpsc;
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let (began, begun) = mpsc::channel();
        let (tell, told) = mpsc::channel();
        let buffer = engine.readback(4);
        let got_through = std::thread::scope(|scope| {
            let (let_go, released) = mpsc::channel::<()>();
            buffer.map_async(wgpu::MapMode::Read, .., move |_| {
                let _ = began.send(());
                let _ = released.recv_timeout(std::time::Duration::from_secs(60));
            });
            engine.done_then(move |done| {
                let _ = tell.send(done);
            });
            begun.recv_timeout(IN_TIME).expect("the poll saw the map done");
            let (through, went) = mpsc::channel();
            scope.spawn(move || {
                engine.on_thread(|| engine.queue.submit([encoder(engine).finish()]));
                let _ = through.send(());
            });
            let got_through = went.recv_timeout(IN_TIME).is_ok();
            assert!(told.try_recv().is_err(), "told before its poll came back");
            let _ = let_go.send(());
            got_through
        });
        assert!(got_through, "a body stood behind a wait no caller stayed for");
        assert_eq!(told.recv_timeout(IN_TIME), Ok(Ok(())));
    }

    // 🚨A wait no caller stays for is told at its limit that the GPU did
    // not finish (🗣️관제 2026-11-08: 「멈춘 화면보다 이름 있는 실패」) —
    // whatever its poll does, which has no limit of its own (`polled` has
    // why): this one stays in the driver's call, inside a map's answer,
    // till the test has been told. Each by its own limit, from when it
    // was asked: two asked together are told together, not one limit
    // after another. And the engine stands.
    #[test]
    fn a_wait_no_caller_stays_for_is_told_at_its_limit_whatever_its_poll_does() {
        use std::sync::mpsc;
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let (let_go, released) = mpsc::channel::<()>();
        let (tell, told) = mpsc::channel();
        let buffer = engine.readback(4);
        buffer.map_async(wgpu::MapMode::Read, .., move |_| {
            let _ = released.recv_timeout(std::time::Duration::from_secs(60));
        });
        let limit = std::time::Duration::from_secs(1);
        for _ in 0..2 {
            let tell = tell.clone();
            engine.done_within(limit, move |done| {
                let _ = tell.send((done, std::time::Instant::now()));
            });
        }
        let late = Err("the GPU did not finish within 1s".to_string());
        let (first, at) = told.recv_timeout(IN_TIME).expect("the first was told");
        let (second, after) = told.recv_timeout(IN_TIME).expect("the second was told");
        assert_eq!((first, second), (late.clone(), late));
        assert!(after - at < limit / 2, "the second was told {:?} after the first", after - at);
        let _ = let_go.send(());
        assert_eq!(engine.wait(), Some(()), "{}", last_error());
    }

    // 🚨Letting an engine go waits for no poll under way (`Engine::polls`
    // has what it does wait for): this one stays in the driver's call,
    // inside a map's answer, till the test has seen the engine closed. The
    // wait is told once its poll is back all the same, and the poll's own
    // hold on the device is gone by then.
    //
    // ⚠️The buffer is the test's till the poll is back: dropped with its
    // map unanswered it answers where it is dropped — on the test's
    // thread, no poll in the driver at all, and the test green by nothing
    // (🔬2026-11-14, so written first: a minute, the answer's own wait).
    #[test]
    fn an_engine_is_let_go_of_with_a_poll_still_in_the_driver() {
        use std::sync::mpsc;
        let _turn = a_device_of_its_own();
        let engine = opened(Engine::open_first);
        assert!(!engine.is_null(), "{}", last_error());
        let (began, begun) = mpsc::channel();
        let (let_go, released) = mpsc::channel::<()>();
        let (tell, told) = mpsc::channel();
        // SAFETY: opened above, live.
        let buffer = unsafe { (*engine).readback(4) };
        buffer.map_async(wgpu::MapMode::Read, .., move |_| {
            let _ = began.send(std::thread::current().id());
            let _ = released.recv_timeout(std::time::Duration::from_secs(60));
        });
        let tells = move |done| {
            let _ = tell.send(done);
        };
        // SAFETY: opened above, live.
        unsafe { (*engine).done_then(tells) };
        let polled_on = begun.recv_timeout(IN_TIME).expect("the poll saw the map done");
        assert_ne!(polled_on, std::thread::current().id(), "the map answered here, in no poll");
        let (closed, went) = mpsc::channel();
        let made = engine as usize;
        std::thread::spawn(move || {
            // SAFETY: opened above, closed once.
            unsafe { gpu_engine_close(made as *mut Engine) };
            let _ = closed.send(());
        });
        let let_go_of = went.recv_timeout(IN_TIME).is_ok();
        let polling_still = told.try_recv().is_err();
        let _ = let_go.send(());
        assert!(let_go_of, "the engine's let-go stood behind a poll under way");
        assert!(polling_still, "the poll was back before the engine was let go of");
        assert_eq!(told.recv_timeout(IN_TIME), Ok(Ok(())));
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
        let turn = a_device_of_its_own();
        let engine = turn.engine();
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
        let turn = a_device_of_its_own();
        let engine = turn.engine();
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

    // 🚨An engine whose thread for polls ended — as it does under a poll
    // wgpu cannot go on from — is gone: no wait comes back from it, and the
    // app is told so as of a device lost.
    #[test]
    fn an_engine_whose_thread_ended_is_gone() {
        let turn = a_device_of_its_own();
        let engine = turn.engine();
        let ended = engine.polls.run(|| -> () { panic!("as wgpu's poll does") });
        assert_eq!(ended, None);
        // Ended by its own word, said before the run above is answered.
        // ↩️Till 2026-11-14 the thread itself ended with the panic, and a
        // wait asked at once was at times handed to it still unwinding, and
        // told it never answered — 1 run in 20 in release (2026-11-12).
        assert!(!engine.gone(), "gone before a wait found the thread ended");
        assert_eq!(engine.wait(), None);
        assert_eq!(last_error(), "the engine's thread is gone");
        assert!(engine.gone());
        // 🚨And a body handed to it still runs: a verb's body runs nowhere
        // else, and fails there by the device that is gone.
        assert_eq!(engine.on_thread(|| engine.wait()), None);
        assert_eq!(last_error(), "the engine's thread is gone");
    }

    // 🚨A run whose work panicked is answered once the thread has said it
    // ended, and not before (`EngineThread::till_it_ends` has what a wait
    // asked in between was told). What the panic carried is let go of
    // between the two, and this one's stops there till the test has seen
    // that no answer came.
    #[test]
    fn a_run_whose_work_panicked_is_answered_once_the_thread_said_it_ended() {
        use std::sync::mpsc;
        struct Stops(mpsc::Sender<()>, mpsc::Receiver<()>);
        impl Drop for Stops {
            fn drop(&mut self) {
                let _ = self.0.send(());
                let _ = self.1.recv_timeout(IN_TIME);
            }
        }
        let thread = super::EngineThread::start().expect("a thread");
        let ((stopped, stops), (goes, go), (answered, answer)) = (mpsc::channel(), mpsc::channel(), mpsc::channel());
        std::thread::scope(|scope| {
            let thread = &thread;
            scope.spawn(move || {
                let ran = thread.run(move || -> () { std::panic::panic_any(Stops(stopped, go)) });
                let _ = answered.send((ran, thread.ended.load(std::sync::atomic::Ordering::Acquire)));
            });
            stops.recv_timeout(IN_TIME).expect("the panic unwound");
            let early = answer.recv_timeout(std::time::Duration::from_millis(300));
            let _ = goes.send(());
            assert!(early.is_err(), "answered before the thread said it ended: {early:?}");
        });
        assert_eq!(answer.recv_timeout(IN_TIME), Ok((None, true)));
    }

    // 🚨A verb's body runs on the engine's thread, whatever thread calls the
    // verb (the-ui-thread-never-enters-the-driver; `EngineThread` has why)
    // — as a call: it borrows what its caller holds, fails by its caller's
    // last error, and its waits, and the compiles it waits for, are counted
    // on its caller's thread (the app's pin of the kernels the thread its
    // frames are built on waits for reads that count there).
    #[test]
    fn a_body_runs_on_the_engines_thread_as_a_call_of_its_callers() {
        use crate::kernels::shared::{gpu_engine_kernels_built_here, pipeline};
        let turn = a_device_of_its_own();
        let engine = turn.engine();
        let mut lent = vec![1, 2, 3];
        let _: Option<()> = fail("the caller's own");
        let (waited, built) = (super::gpu_engine_waits_here(), gpu_engine_kernels_built_here());
        let on = engine.on_thread(|| {
            lent.push(4);
            assert_eq!(last_error(), "the caller's own");
            let _: Option<()> = fail("the body's");
            // Its wait, and a body it hands the thread, run where it is:
            // handed over, each would wait for itself.
            assert_eq!(engine.wait(), Some(()));
            let here = std::thread::current().id();
            assert_eq!(engine.on_thread(|| std::thread::current().id()), here);
            let source = "@compute @workgroup_size(1)\nfn main() {}\n// device.rs, a body's own";
            let _ = pipeline(&engine, &[source], "main");
            here
        });
        assert_ne!(on, std::thread::current().id());
        assert_eq!(lent, [1, 2, 3, 4]);
        assert_eq!(last_error(), "the body's");
        assert_eq!(super::gpu_engine_waits_here(), waited + 1);
        assert_eq!(gpu_engine_kernels_built_here(), built + 1);
    }

    // A panic of a body's is its caller's, as it was on the caller's thread
    // — the engine's thread goes on to the next, and has not ended.
    #[test]
    fn a_bodys_panic_is_its_callers_and_the_thread_goes_on() {
        let turn = a_device_of_its_own();
        let engine = turn.engine();
        let body = || engine.on_thread(|| -> () { panic!("the body's own") });
        let why = std::panic::catch_unwind(std::panic::AssertUnwindSafe(body))
            .expect_err("the panic stayed on the engine's thread");
        assert_eq!(why.downcast_ref::<&str>(), Some(&"the body's own"));
        assert_eq!(engine.on_thread(|| 7), 7);
        assert_eq!(engine.wait(), Some(()), "{}", last_error());
    }

    // 🚨A hand on the device is counted on the thread that takes it — a
    // body's on the engine's thread, and none of it on its caller's: what
    // the app's pin holds at none on the thread its frames are built on.
    #[test]
    fn a_hand_on_the_device_is_counted_on_the_thread_that_takes_it() {
        let turn = a_device_of_its_own();
        let engine = turn.engine();
        let entered = super::gpu_engine_device_entered_here;
        let before = entered();
        let small = engine.readback(4);
        assert_eq!(entered(), before + 1, "a buffer made");
        engine.queue.write_buffer(&small, 0, &[0; 4]);
        assert_eq!(entered(), before + 2, "a buffer written");
        engine.on_thread(|| {
            let small = engine.readback(4);
            engine.queue.write_buffer(&small, 0, &[0; 4]);
        });
        assert_eq!(entered(), before + 2, "a body's hand is the engine's thread's");
    }

    /// Whether a body gets through `engine`'s thread within `within` while
    /// one handed there before it is in `waits`, which returns once it is
    /// let go.
    fn a_body_gets_through_behind(
        engine: &Engine,
        within: std::time::Duration,
        waits: impl FnOnce(std::sync::mpsc::Receiver<()>) + Send,
    ) -> bool {
        let (let_go, released) = std::sync::mpsc::channel::<()>();
        let (began, begun) = std::sync::mpsc::channel();
        let (through, went) = std::sync::mpsc::channel();
        std::thread::scope(|scope| {
            scope.spawn(move || {
                engine.on_thread(|| {
                    let _ = began.send(());
                    waits(released);
                })
            });
            begun.recv().expect("the body that waits began");
            scope.spawn(move || {
                engine.on_thread(|| ());
                let _ = through.send(());
            });
            let got_through = went.recv_timeout(within).is_ok();
            let _ = let_go.send(());
            got_through
        })
    }

    /// Long enough for a body that is held up by nothing.
    const IN_TIME: std::time::Duration = std::time::Duration::from_secs(20);

    // 🚨A body that waits for a compile leaves the engine's thread to the
    // bodies behind it (🗣️관제 2026-11-14 01:21,
    // the-ui-thread-never-enters-the-driver: 「새 멈춤을 만들고 다음 단계로
    // 가지 않는다」; `EngineThread` has why) — and goes on where it was, the
    // engine's thread to itself still.
    #[test]
    fn a_body_that_waits_for_a_compile_holds_up_no_body_behind_it() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let got_through = a_body_gets_through_behind(engine, IN_TIME, |released| {
            let here = std::thread::current().id();
            engine.compiling(move |_| {
                let _ = released.recv_timeout(std::time::Duration::from_secs(60));
            });
            // Its wait, and a body it hands the thread, run where it is.
            assert_eq!(engine.on_thread(|| std::thread::current().id()), here);
            assert_eq!(engine.wait(), Some(()), "{}", last_error());
        });
        assert!(got_through, "a body waited behind one that waits for a compile");
        // The thread that took the turn is the engine's from there on.
        assert_eq!(engine.on_thread(|| 7), 7);
        assert_eq!(engine.wait(), Some(()), "{}", last_error());
        // And the one that stood aside takes no job till a turn is left it
        // (↩️it ended with its body, till 2026-11-15): one body at a time
        // again, the next behind one that waits for no compile.
        let a_moment = std::time::Duration::from_millis(300);
        let got_through = a_body_gets_through_behind(engine, a_moment, |released| {
            let _ = released.recv_timeout(std::time::Duration::from_secs(60));
        });
        assert!(!got_through, "two threads took the engine's jobs at once");
    }

    // 🚨A body that waits for the GPU leaves the engine's thread to the
    // bodies behind it, as one that waits for a compile (🗣️관제 2026-11-15
    // 13:52, the-ui-thread-never-enters-the-driver: 「1c 가 폴을 폴 스레드로
    // 옮긴 것의 남은 반쪽이다」; `EngineThread` has what stood behind one).
    // Its poll stays in the driver's call, inside a map's answer — as
    // `a_wait_no_caller_stays_for_holds_up_no_body`'s does — till the test
    // has seen a body through.
    #[test]
    fn a_body_that_waits_for_the_gpu_holds_up_no_body_behind_it() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let got_through = a_body_gets_through_behind(engine, IN_TIME, |released| {
            let here = std::thread::current().id();
            let buffer = engine.readback(4);
            buffer.map_async(wgpu::MapMode::Read, .., move |_| {
                let _ = released.recv_timeout(std::time::Duration::from_secs(60));
            });
            assert_eq!(engine.wait(), Some(()), "{}", last_error());
            // What it hands the thread after its wait runs where it is.
            assert_eq!(engine.on_thread(|| std::thread::current().id()), here);
        });
        assert!(got_through, "a body waited behind one that waits for the GPU");
        // The thread that took the turn is the engine's from there on.
        assert_eq!(engine.on_thread(|| 7), 7);
        assert_eq!(engine.wait(), Some(()), "{}", last_error());
    }

    // 🚨A body that waits with none handed behind it wakes no other
    // thread: the turn it left is its own again as it ends (`Turns` has
    // what a thread woken at every wait cost a save) — before its caller
    // has the answer to hand the next body by (`Turns::back`). Bodies that
    // each wait, one after another, run on one thread — the first of them
    // through a wait long enough for the thread made at it to be up: that
    // one takes no turn with no job behind the wait (`Turns::taken`).
    #[test]
    fn a_body_that_waits_with_none_behind_it_keeps_the_engine_s_thread() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let long = std::time::Duration::from_millis(300);
        let ran_on: std::collections::HashSet<_> = (0..6)
            .map(|nth| {
                engine.on_thread(|| {
                    if nth == 0 {
                        engine.compiling(move |_| std::thread::sleep(long));
                    }
                    assert_eq!(engine.wait(), Some(()), "{}", last_error());
                    std::thread::current().id()
                })
            })
            .collect();
        assert_eq!(ran_on.len(), 1, "threads that ran six bodies that each waited, none behind");
    }

    // 🚨Nor is a thread made for each body that gets through behind a
    // wait: the one that left its turn and found it taken waits for a turn
    // left, and takes the next (`Turns` has what a thread made at every
    // wait cost a stroke). Three bodies through, each behind a wait: one
    // thread more than the engine began with.
    #[test]
    fn a_thread_that_found_its_turn_taken_takes_the_next_one_left() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        for round in 0..3 {
            let got_through = a_body_gets_through_behind(engine, IN_TIME, |released| {
                let buffer = engine.readback(4);
                buffer.map_async(wgpu::MapMode::Read, .., move |_| {
                    let _ = released.recv_timeout(std::time::Duration::from_secs(60));
                });
                assert_eq!(engine.wait(), Some(()), "{}", last_error());
            });
            assert!(got_through, "a body waited behind one that waits for the GPU, round {round}");
        }
        // Every body is back: a thread holds the turn, and the rest wait.
        assert_eq!(engine.on_thread(|| 7), 7);
        let spare = engine.thread.turns.0.lock().unwrap().spare;
        assert_eq!(spare, 1, "threads that wait for a turn, three bodies through behind a wait");
    }

    // 🚨Nor behind two that wait at once: where the thread a turn would be
    // left to is in a wait of its own still, one is made — an engine has
    // as many threads as bodies under way at once. Each body here is
    // handed once the one ahead is in its wait: the turn left before it
    // came is taken as it is handed (`Turns::handed`).
    #[test]
    fn a_body_gets_through_behind_two_that_wait_at_once() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        // A wait gone through first: a thread is there that waits for a
        // turn.
        engine.on_thread(|| assert_eq!(engine.wait(), Some(()), "{}", last_error()));
        let (let_go, released) = std::sync::mpsc::channel::<()>();
        let (began, begun) = std::sync::mpsc::channel();
        let (through, went) = std::sync::mpsc::channel();
        let got_through = std::thread::scope(|scope| {
            let first = began.clone();
            scope.spawn(move || {
                engine.on_thread(|| {
                    // Its poll stays in the driver's call — where it says
                    // it began: in its wait, its turn left — till the test
                    // has seen a body through, and the next body's wait
                    // behind it.
                    let buffer = engine.readback(4);
                    buffer.map_async(wgpu::MapMode::Read, .., move |_| {
                        let _ = first.send(());
                        let _ = released.recv_timeout(std::time::Duration::from_secs(60));
                    });
                    assert_eq!(engine.wait(), Some(()), "{}", last_error());
                })
            });
            begun.recv_timeout(IN_TIME).expect("the first body that waits began");
            scope.spawn(move || {
                engine.on_thread(|| {
                    let _ = began.send(());
                    assert_eq!(engine.wait(), Some(()), "{}", last_error());
                })
            });
            begun.recv_timeout(IN_TIME).expect("the second body that waits began");
            scope.spawn(move || {
                engine.on_thread(|| ());
                let _ = through.send(());
            });
            let got_through = went.recv_timeout(IN_TIME).is_ok();
            let _ = let_go.send(());
            got_through
        });
        assert!(got_through, "a body waited behind two that wait for the GPU");
    }

    // 🚨And a body handed while the one ahead of it was not yet in its
    // wait is taken as that one leaves its turn
    // (`EngineThread::stands_aside`): no job handed after is there to wake
    // a thread for it.
    #[test]
    fn a_body_handed_before_the_wait_ahead_of_it_gets_through_at_that_wait() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        // A wait gone through first: a thread is there that waits for a
        // turn.
        engine.on_thread(|| assert_eq!(engine.wait(), Some(()), "{}", last_error()));
        let (let_go, released) = std::sync::mpsc::channel::<()>();
        let (began, begun) = std::sync::mpsc::channel();
        let (through, went) = std::sync::mpsc::channel();
        let got_through = std::thread::scope(|scope| {
            scope.spawn(move || {
                engine.on_thread(|| {
                    let _ = began.send(());
                    // In no wait till the next body is handed behind it —
                    // a failure by name where none is counted handed.
                    let asked = std::time::Instant::now();
                    while engine.thread.turns.0.lock().unwrap().queued == 0 {
                        let in_time = asked.elapsed() < IN_TIME;
                        assert!(in_time, "no body was counted handed behind this one");
                        std::thread::yield_now();
                    }
                    let buffer = engine.readback(4);
                    buffer.map_async(wgpu::MapMode::Read, .., move |_| {
                        let _ = released.recv_timeout(std::time::Duration::from_secs(60));
                    });
                    assert_eq!(engine.wait(), Some(()), "{}", last_error());
                })
            });
            begun.recv_timeout(IN_TIME).expect("the body that waits began");
            scope.spawn(move || {
                engine.on_thread(|| ());
                let _ = through.send(());
            });
            let got_through = went.recv_timeout(IN_TIME).is_ok();
            let _ = let_go.send(());
            got_through
        });
        assert!(got_through, "a body handed before a wait stood behind it");
    }

    // 🗣️유저 2026-11-13 (the-wait-window-stands-seven-seconds-on-the-surface-Q1,
    // 「나란히 컴파일」): works side by side are under way at once and answer
    // in their order — and the body that waits for them leaves the engine's
    // thread to the bodies behind it, as one that waits for a compile.
    #[test]
    fn a_body_whose_works_run_side_by_side_holds_up_no_body_behind_it() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let got_through = a_body_gets_through_behind(engine, IN_TIME, |released| {
            let (meets, met) = std::sync::mpsc::channel::<()>();
            let works: [Box<dyn FnOnce() -> &'static str + Send>; 2] = [
                Box::new(move || {
                    let met = met.recv_timeout(std::time::Duration::from_secs(20)).is_ok();
                    let _ = released.recv_timeout(std::time::Duration::from_secs(60));
                    if met { "met the other" } else { "ran alone" }
                }),
                Box::new(move || {
                    let _ = meets.send(());
                    "the other"
                }),
            ];
            assert_eq!(engine.side_by_side(works), ["met the other", "the other"]);
        });
        assert!(got_through, "a body waited behind one whose works ran side by side");
    }

    // 🚨What a body makes of its caller's own after it left the engine's
    // thread goes back to that caller — its last error, its panic — and
    // none of it to the caller of a body run meanwhile on the thread made
    // in its place (🗣️관제 2026-11-14 02:29,
    // the-ui-thread-never-enters-the-driver).
    #[test]
    fn a_body_that_left_the_thread_fails_and_panics_on_its_own_caller() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        for panics in [false, true] {
            let (let_go, released) = std::sync::mpsc::channel::<()>();
            let (began, begun) = std::sync::mpsc::channel();
            std::thread::scope(|scope| {
                let left = scope.spawn(move || {
                    let _: Option<()> = fail("its caller's own");
                    let body = || {
                        engine.on_thread(|| {
                            let _ = began.send(());
                            engine.compiling(move |_| {
                                let _ = released.recv_timeout(std::time::Duration::from_secs(60));
                            });
                            assert_eq!(last_error(), "its caller's own");
                            let _: Option<()> = fail("its own, after it left the thread");
                            assert!(!panics, "its own panic");
                        })
                    };
                    let ended = std::panic::catch_unwind(std::panic::AssertUnwindSafe(body));
                    (ended.is_err(), last_error())
                });
                begun.recv().expect("the body began");
                let _: Option<()> = fail("another caller's own");
                engine.on_thread(|| {
                    assert_eq!(last_error(), "another caller's own");
                    let _: Option<()> = fail("another body's");
                });
                let _ = let_go.send(());
                let (panicked, error) = left.join().expect("its caller caught the panic");
                assert_eq!(panicked, panics);
                assert_eq!(error, "its own, after it left the thread");
                assert_eq!(last_error(), "another body's", "the other caller's is its own body's");
            });
        }
    }

    /// What a test hands out and watches let go of: it tells the engine
    /// whose thread let go of it, by that thread's number — `NO_ENGINE` on
    /// a thread that is none's.
    struct Watched(std::sync::mpsc::Sender<u64>);

    impl Drop for Watched {
        fn drop(&mut self) {
            let _ = self.0.send(super::WORKS_FOR.get());
        }
    }

    // 🚨A body handed over unwaited (the-ui-thread-never-enters-the-driver
    // B1-a; `Engine::posted` has why): its caller is back before it has
    // run, and it keeps its turn through a compile — no body handed after
    // it overtakes it, as one that waits for a compile lent is overtaken.
    #[test]
    fn a_body_handed_over_unwaited_keeps_its_turn_through_a_compile() {
        use std::sync::mpsc;
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let (let_go, released) = mpsc::channel::<()>();
        let (ran, order) = mpsc::channel();
        let (its, first) = (engine.clone(), ran.clone());
        engine.posted(move || {
            its.compiling(move |_| {
                let _ = released.recv_timeout(std::time::Duration::from_secs(60));
            });
            let _ = first.send("the body handed over");
            Some(())
        });
        let _ = ran.send("its caller, back");
        drop(ran);
        std::thread::scope(|scope| {
            let (through, went) = mpsc::channel();
            scope.spawn(move || {
                engine.on_thread(|| ());
                let _ = through.send(());
            });
            let a_moment = std::time::Duration::from_millis(300);
            assert!(went.recv_timeout(a_moment).is_err(), "a body overtook one handed over unwaited");
            let _ = let_go.send(());
            assert!(went.recv_timeout(IN_TIME).is_ok(), "the body behind it never got through");
        });
        assert_eq!(order.iter().collect::<Vec<_>>(), ["its caller, back", "the body handed over"]);
        assert_eq!(done_here(engine), Ok(()));
    }

    // 🚨What a body handed over unwaited refused is told by the next done
    // of the thread that handed it over — the first since one was told,
    // once — and by no done asked before it, as an error no scope caught
    // would be by the first wait to end (`Refusals`): a done answers for
    // the bodies its thread handed over before it, in their order. So a
    // caller that asks in the turn it hands one over is told of that one
    // (`ScreenTexture.present` asks in the turn it shows — 🗣️관제
    // 2026-11-15 05:20 asked that pinned, in the app's tests); one that
    // hands another over and asks between is told of the one before.
    #[test]
    fn a_done_is_told_what_the_bodies_its_thread_handed_over_before_it_refused() {
        let engine = first_engine();
        let refuses = |why: &'static str| move || fail::<()>(why);
        let failed = |why: &str| Err(format!("a body handed over unwaited failed: {why}"));
        let (tell, told) = std::sync::mpsc::channel();
        engine.done_then(move |done| {
            let _ = tell.send(done);
        });
        engine.posted(refuses("the first refused"));
        engine.posted(refuses("the second refused"));
        assert_eq!(told.recv(), Ok(Ok(())), "a done asked before took what came after it");
        assert_eq!(done_here(engine), failed("the first refused"));
        assert_eq!(done_here(engine), Ok(()), "told twice");
        engine.posted(refuses("the one before"));
        engine.posted(|| Some(()));
        assert_eq!(done_here(engine), failed("the one before"));
    }

    // What a body handed over unwaited refused is no word to another
    // thread's done — a worker's body to the UI's frame.
    #[test]
    fn what_a_body_refused_is_told_to_the_thread_that_handed_it_over_alone() {
        use std::sync::mpsc;
        let engine = first_engine();
        std::thread::scope(|scope| {
            let (handed, over) = mpsc::channel();
            let (asked, ask) = mpsc::channel::<()>();
            let other = scope.spawn(move || {
                engine.posted(|| fail("the other thread's"));
                let _ = handed.send(());
                let _ = ask.recv();
                done_here(engine)
            });
            over.recv().expect("handed over");
            assert_eq!(done_here(engine), Ok(()), "told of another thread's body");
            let _ = asked.send(());
            let theirs = other.join().expect("its done");
            assert_eq!(theirs, Err("a body handed over unwaited failed: the other thread's".to_owned()));
        });
    }

    // What a body handed over unwaited counts on the engine's thread — a
    // wait, a compile waited for — is counted on the thread that handed it
    // over once it has run, as a lent body's is (`Callers`): the app's pins
    // read those on the thread its frames are built on.
    #[test]
    fn what_a_body_handed_over_unwaited_counts_is_its_callers() {
        use crate::kernels::shared::{Kernel, gpu_engine_kernels_built_here};
        let engine = first_engine();
        let (waits, built) = (super::gpu_engine_waits_here(), gpu_engine_kernels_built_here());
        engine.posted(move || {
            let source = "@compute @workgroup_size(1)\nfn main() {}\n// device.rs, a body handed over unwaited";
            Kernel::of(engine, &[source], "main").pipeline(engine);
            engine.wait()
        });
        assert_eq!(done_here(engine), Ok(()), "{}", last_error());
        assert_eq!(super::gpu_engine_waits_here() - waits, 1, "its wait");
        assert_eq!(gpu_engine_kernels_built_here() - built, 1, "its compile");
    }

    // 🚨A done is asked of the GPU behind every body handed over before it
    // (`Engine::done_then`'s 🚨): one asked while such a body is still to
    // submit is told once that body's work is done, not before.
    #[test]
    fn a_done_is_told_once_the_work_of_a_body_handed_over_before_it_is_done() {
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::{Arc, mpsc};
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        let (let_go, released) = mpsc::channel::<()>();
        let seen = Arc::new(AtomicBool::new(false));
        let (its, flag) = (engine.clone(), Arc::clone(&seen));
        engine.posted(move || {
            let _ = released.recv_timeout(std::time::Duration::from_secs(60));
            its.queue.submit([encoder(&its).finish()]);
            its.queue.on_submitted_work_done(move || flag.store(true, Ordering::SeqCst));
            Some(())
        });
        let (tell, told) = mpsc::channel();
        engine.done_then(move |done| {
            let _ = tell.send(done);
        });
        let a_moment = std::time::Duration::from_millis(300);
        assert!(told.recv_timeout(a_moment).is_err(), "told before the body handed over before it ran");
        let _ = let_go.send(());
        assert_eq!(told.recv_timeout(IN_TIME), Ok(Ok(())));
        assert!(seen.load(Ordering::SeqCst), "told before that body's work was done");
    }

    // A body handed over unwaited that panics has no caller to take the
    // panic: the next done of its thread fails by it, and the bodies go on.
    #[test]
    fn a_body_handed_over_unwaited_that_panics_fails_the_next_done() {
        let turn = a_device_of_its_own();
        let engine = &turn.engine();
        engine.posted(|| panic!("a body handed over unwaited, panicking"));
        assert_eq!(done_here(engine), Err("a body handed over unwaited failed: it panicked".to_owned()));
        assert_eq!(engine.on_thread(|| 7), 7, "the bodies went on");
    }

    // 🚨What the ABI handed out is let go of on the thread of the engine
    // that made it (the-ui-thread-never-enters-the-driver 1b; `Handed` has
    // why) — gone as its free returns, and read through meanwhile as the
    // thing itself. A verb handed the thing and no engine reaches that
    // thread by it too.
    #[test]
    fn what_is_handed_out_is_let_go_of_on_its_engines_thread_as_its_free_returns() {
        let engine = first_engine();
        let (told, let_go_on) = std::sync::mpsc::channel();
        let handed = engine.hands((7u8, Watched(told)));
        // SAFETY: handed out above, live.
        assert_eq!(unsafe { (*handed).0 }, 7, "the pointer is to the thing");
        // SAFETY: handed out above, live.
        let on = unsafe { super::on_thread_of(handed, || super::WORKS_FOR.get()) };
        assert_eq!(on, engine.thread.number, "a verb handed the thing runs on its engine's thread");
        assert_ne!(super::WORKS_FOR.get(), on, "a test's thread is no engine's");
        // SAFETY: handed out above, let go of once.
        unsafe { super::let_go(handed) };
        assert_eq!(let_go_on.try_recv(), Ok(on), "let go of off its engine's thread, or not yet");
        // Nothing of a null.
        // SAFETY: a null is let go of as nothing.
        unsafe { super::let_go(std::ptr::null_mut::<Watched>()) };
        // SAFETY: the same.
        unsafe { super::let_go_unwaited(std::ptr::null_mut::<Watched>()) };
    }

    // 🚨What the GC lets go of waits for nothing (`let_go_unwaited` has the
    // measure): its free is back while a body ahead still has the engine's
    // thread, and the thing is let go of there once that body is through.
    #[test]
    fn what_the_gc_lets_go_of_waits_for_no_body_and_goes_on_its_engines_thread() {
        let engine = first_engine();
        let (told, let_go_on) = std::sync::mpsc::channel();
        let handed = engine.hands(Watched(told));
        let (lets, released) = std::sync::mpsc::channel::<()>();
        let (began, begun) = std::sync::mpsc::channel();
        std::thread::scope(|scope| {
            scope.spawn(move || {
                engine.on_thread(|| {
                    let _ = began.send(());
                    let _ = released.recv_timeout(IN_TIME);
                })
            });
            begun.recv().expect("the body ahead began");
            // SAFETY: handed out above, let go of once.
            unsafe { super::let_go_unwaited(handed) };
            let so_far = let_go_on.try_recv();
            let _ = lets.send(());
            assert_eq!(so_far, Err(std::sync::mpsc::TryRecvError::Empty), "waited for, or let go of here");
        });
        assert_eq!(let_go_on.recv_timeout(IN_TIME), Ok(engine.thread.number));
    }

    // 🚨Work a verb hands over by its thing, its caller waiting for none
    // of it (`posted_of` has why, and what it is for): back while a body
    // ahead still has the engine's thread, and run there in turn — behind
    // what was handed before it, ahead of what is handed after.
    #[test]
    fn work_handed_over_by_a_thing_waits_for_no_body_and_runs_in_turn_on_its_engines_thread() {
        let engine = first_engine();
        let handed = engine.hands(7u8);
        let (told, ran) = std::sync::mpsc::channel();
        let (lets, released) = std::sync::mpsc::channel::<()>();
        let (began, begun) = std::sync::mpsc::channel();
        std::thread::scope(|scope| {
            scope.spawn(move || {
                engine.on_thread(|| {
                    let _ = began.send(());
                    let _ = released.recv_timeout(IN_TIME);
                })
            });
            begun.recv().expect("the body ahead began");
            let by_the_thing = told.clone();
            let work = move || {
                let _ = by_the_thing.send(("by the thing", super::WORKS_FOR.get()));
            };
            // SAFETY: handed out above, live.
            unsafe { super::posted_of(handed, work) };
            let so_far = ran.try_recv();
            engine.posted(move || told.send(("after", super::WORKS_FOR.get())).ok());
            let _ = lets.send(());
            assert_eq!(so_far, Err(std::sync::mpsc::TryRecvError::Empty), "waited for, or run here");
        });
        let on = engine.thread.number;
        assert_eq!(ran.recv_timeout(IN_TIME), Ok(("by the thing", on)));
        assert_eq!(ran.recv_timeout(IN_TIME), Ok(("after", on)), "in turn");
        // SAFETY: handed out above, let go of once.
        unsafe { super::let_go(handed) };
    }

    // 🚨The thread stands for as long as a thing of its engine's does: the
    // GC comes when it comes, and what it lets go of after the engine was
    // closed — a lost device's pictures, the app's at its end — is let go
    // of on that engine's thread all the same.
    #[test]
    fn what_outlives_its_engine_is_let_go_of_on_that_engines_thread_still() {
        let _turn = a_device_of_its_own();
        let engine = opened(Engine::open_first);
        assert!(!engine.is_null(), "{}", last_error());
        let (told, let_go_on) = std::sync::mpsc::channel();
        // SAFETY: opened above, live.
        let (handed, its_thread) = unsafe { ((*engine).hands(Watched(told)), (*engine).thread.number) };
        // SAFETY: opened above, closed once.
        unsafe { gpu_engine_close(engine) };
        // SAFETY: handed out above, let go of once.
        unsafe { super::let_go_unwaited(handed) };
        assert_eq!(let_go_on.recv_timeout(IN_TIME), Ok(its_thread));
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
        use super::{gpu_engine_gone, gpu_engine_lose, gpu_engine_noted, gpu_engine_went_by};
        use crate::platform::WENT_UNSAID;
        let _turn = a_device_of_its_own();
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
            assert_eq!(gpu_engine_went_by(made), WENT_UNSAID, "a device that is there");
            gpu_engine_lose(made, false);
            assert!(!gpu_engine_gone(made), "the word came before a wait");
            assert_eq!(engine.wait(), None);
            assert!(gpu_engine_gone(made));
            assert_eq!(gpu_engine_went_by(made), WENT_UNSAID, "destroyed: no driver took it");
            gpu_engine_close(made);
        }
    }

    // A device wgpu gave up for want of memory went by that, whatever the
    // platform says of it — wgpu's word for it read as wgpu says it — and
    // one lost by any other word did not. The test seam's is that word.
    #[test]
    fn a_device_wgpu_lost_for_want_of_memory_went_by_that() {
        use super::{gpu_engine_gone, gpu_engine_lose, gpu_engine_went_by, Refusals};
        use crate::platform::{WENT_BY_MEMORY, WENT_UNSAID};
        let lost = |why: wgpu::hal::DeviceError| {
            let refusals = Refusals::default();
            // As the lost callback keeps it ([`Engine::on`]).
            refusals.lose(format!("{:?} {why}", wgpu::DeviceLostReason::Unknown));
            refusals
        };
        assert!(lost(wgpu::hal::DeviceError::OutOfMemory).gone_for_memory());
        assert!(!lost(wgpu::hal::DeviceError::Lost).gone_for_memory());
        assert!(!lost(wgpu::hal::DeviceError::Unexpected).gone_for_memory());
        assert!(!Refusals::default().gone_for_memory(), "one that is there");

        let _turn = a_device_of_its_own();
        let made = opened(Engine::open_first);
        assert!(!made.is_null(), "{}", last_error());
        // SAFETY: `made` is live till the close below.
        unsafe {
            assert_eq!(gpu_engine_went_by(made), WENT_UNSAID);
            gpu_engine_lose(made, true);
            assert!(gpu_engine_gone(made), "said where it was lost");
            assert_eq!(gpu_engine_went_by(made), WENT_BY_MEMORY);
            super::gpu_engine_close(made);
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
        let then = move |ended: Result<(), String>| {
            let _ = tell.send(ended);
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
