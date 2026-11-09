//! The wgpu device every kernel runs on, opened on the adapter Flutter
//! draws with so a shared texture lives on the GPU that reads it.

use std::sync::mpsc;
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
}

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
                Some(Self {
                    queue: Queue {
                        queue,
                        thread: thread.clone(),
                    },
                    thread,
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

    /// What `work` answers, run on the engine's thread ([`EngineThread`])
    /// while the caller waits.
    pub(crate) fn on_its_thread<T: Send + 'static>(
        &self,
        work: impl FnOnce() -> T + Send + 'static,
    ) -> T {
        self.thread.run(work).expect("the engine's thread")
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

#[cfg(test)]
mod tests {
    use super::{Engine, gpu_engine_close, opened};
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
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for _ in 0..16 {
            encoder.copy_buffer_to_buffer(&from, 0, &to, 0, SIDE);
        }
        engine.queue.submit([encoder.finish()]);

        assert_eq!(engine.wait_within(std::time::Duration::ZERO), None);
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
