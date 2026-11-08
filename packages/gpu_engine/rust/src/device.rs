//! The wgpu device every kernel runs on, opened on the adapter Flutter
//! draws with so a shared texture lives on the GPU that reads it.

use std::sync::mpsc;

use crate::{copy_out, fail, last_error, platform};

/// One wgpu device and its queue.
#[derive(Clone)]
pub struct Engine {
    /// Kept for Android's window surfaces, which must come from the
    /// instance the adapter came from.
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    pub(crate) instance: wgpu::Instance,
    pub(crate) adapter: wgpu::Adapter,
    pub(crate) device: wgpu::Device,
    pub(crate) queue: wgpu::Queue,
    /// Where [`Engine::wait`] sends to the thread its waits block on
    /// ([`waiter`]).
    waits: mpsc::Sender<Wait>,
}

/// What a wait sends its thread: the device to poll, and where to answer.
type Wait = (wgpu::Device, mpsc::Sender<Result<(), String>>);

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
            Ok((device, queue)) => Some(Self {
                waits: waiter()?,
                instance,
                adapter,
                device,
                queue,
            }),
            Err(error) => fail(format!("request_device: {error}")),
        }
    }

    /// Blocks until the GPU has finished everything submitted — polled on
    /// the thread the engine's waits block on ([`waiter`]), the caller
    /// waiting outside the driver.
    pub(crate) fn wait(&self) -> Option<()> {
        let (answer, answered) = mpsc::channel();
        if self.waits.send((self.device.clone(), answer)).is_err() {
            return fail("the engine's wait thread is gone");
        }
        match answered.recv() {
            Ok(Ok(())) => Some(()),
            Ok(Err(error)) => fail(error),
            Err(error) => fail(format!("the engine's wait thread never answered: {error}")),
        }
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

/// The engine `open` makes, made on a thread of the engine's own while
/// the caller waits — its failure, if it fails, the caller's last error.
///
/// 🚨★★A DEVICE IS NEVER OPENED ON THE CALLER'S THREAD
/// (an-engine-setup-hangs-in-a-batch, 2026-11-08): the caller is a Dart
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
fn opened(open: impl FnOnce() -> Option<Engine> + Send) -> *mut Engine {
    let made = std::thread::scope(|scope| {
        let thread = std::thread::Builder::new().name("gpu_engine open".into());
        let opening = thread.spawn_scoped(scope, || open().ok_or_else(last_error));
        match opening {
            Ok(opening) => opening.join().unwrap_or_else(|_| Err("opening panicked".into())),
            Err(error) => Err(format!("no thread to open on: {error}")),
        }
    });
    match made {
        Ok(engine) => Box::into_raw(Box::new(engine)),
        Err(error) => {
            let _ = fail::<()>(error);
            std::ptr::null_mut()
        }
    }
}

/// The thread an engine's waits block on ([`Engine::wait`]), polling the
/// device each one sends till no engine is left to send.
///
/// 🚨★★A WAIT NEVER BLOCKS IN THE DRIVER ON THE CALLER'S THREAD, for the
/// reason a device is never opened there ([`opened`]): the profiler walks
/// that thread's stack, and a wait stays in the driver as long as the GPU
/// takes. 🔬Flip lane ⓓ (2026-11-09) put a read back in every save, park
/// and cooling: eight `flutter test` files at once lost one at its first
/// read, three runs of three, each passing alone. A thread made for each
/// wait took 50–60 µs on the main PC against 1 µs handed to this one, and
/// the screen waits every frame. The device comes with each wait, so none
/// is kept between them.
fn waiter() -> Option<mpsc::Sender<Wait>> {
    let (waits, asked) = mpsc::channel::<Wait>();
    let polling = move || {
        for (device, answer) in asked {
            let polled = device.poll(wgpu::PollType::wait_indefinitely());
            let _ = answer.send(polled.map(|_| ()).map_err(|error| format!("poll: {error}")));
        }
    };
    match std::thread::Builder::new().name("gpu_engine wait".into()).spawn(polling) {
        Ok(_) => Some(waits),
        Err(error) => fail(format!("no thread to wait on: {error}")),
    }
}

/// Opens the engine on the adapter whose LUID is `luid` (high part in the
/// upper 32 bits) — Flutter's own. Null on failure; see the last error.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_open(luid: u64) -> *mut Engine {
    opened(|| Engine::open(luid))
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
        let caller = std::thread::current().id();
        let mut on = None;
        let made = opened(|| {
            on = Some(std::thread::current().id());
            Engine::open_first()
        });
        assert!(!made.is_null(), "{}", last_error());
        assert!(on.is_some_and(|on| on != caller));
        // SAFETY: `made` came from `opened`, nothing made on it.
        unsafe { gpu_engine_close(made) };
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
