//! The wgpu device every kernel runs on, opened on the adapter Flutter
//! draws with so a shared texture lives on the GPU that reads it.

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
                Some(Self {
                    queue: Queue {
                        queue,
                        thread: thread.clone(),
                    },
                    thread,
                    compiling,
                    kernels: Kernels::default(),
                    apart: Apart::default(),
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
    /// ([`EngineThread`]), the caller waiting outside the driver.
    pub(crate) fn wait(&self) -> Option<()> {
        self.wait_within(WAIT_LIMIT)
    }

    fn wait_within(&self, limit: Duration) -> Option<()> {
        let device = self.device.clone();
        let polled = self.thread.run(move || {
            let polled = device.poll(wgpu::PollType::Wait {
                submission_index: None,
                timeout: Some(limit),
            });
            polled.map(|_| ()).map_err(|error| match error {
                wgpu::PollError::Timeout => {
                    format!("the GPU did not finish within {limit:?}")
                }
                error => format!("poll: {error}"),
            })
        })?;
        polled.map_or_else(fail, Some)
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
        let (sender, receiver) = mpsc::channel();
        buffer.map_async(wgpu::MapMode::Read, .., move |result| {
            let _ = sender.send(result);
        });
        self.wait()?;
        match receiver.recv() {
            Ok(Ok(())) => Some(()),
            Ok(Err(error)) => fail(format!("map_async: {error}")),
            Err(error) => fail(format!("map_async never answered: {error}")),
        }
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
