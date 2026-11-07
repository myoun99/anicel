//! The wgpu device every kernel runs on, opened on the adapter Flutter
//! draws with so a shared texture lives on the GPU that reads it.

use std::sync::mpsc;

use crate::{copy_out, fail, platform};

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
                instance,
                adapter,
                device,
                queue,
            }),
            Err(error) => fail(format!("request_device: {error}")),
        }
    }

    /// Blocks until the GPU has finished everything submitted.
    pub(crate) fn wait(&self) -> Option<()> {
        match self.device.poll(wgpu::PollType::wait_indefinitely()) {
            Ok(_) => Some(()),
            Err(error) => fail(format!("poll: {error}")),
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
        let readback = self.readback(buffer.size());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, buffer.size());
        self.queue.submit([encoder.finish()]);
        self.mapped(&readback)
    }

    /// A buffer of `size` bytes a copy puts and the CPU maps.
    fn readback(&self, size: u64) -> wgpu::Buffer {
        self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("readback"),
            size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        })
    }

    /// `buffer`'s bytes, mapped once the GPU is done with all that was
    /// submitted.
    fn mapped(&self, buffer: &wgpu::Buffer) -> Option<Vec<u8>> {
        let (sender, receiver) = mpsc::channel();
        buffer.map_async(wgpu::MapMode::Read, .., move |result| {
            let _ = sender.send(result);
        });
        self.wait()?;
        match receiver.recv() {
            Ok(Ok(())) => {}
            Ok(Err(error)) => return fail(format!("map_async: {error}")),
            Err(error) => return fail(format!("map_async never answered: {error}")),
        }
        match buffer.get_mapped_range(..) {
            Ok(view) => Some(view.to_vec()),
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

fn boxed(engine: Option<Engine>) -> *mut Engine {
    engine.map_or(std::ptr::null_mut(), |engine| Box::into_raw(Box::new(engine)))
}

/// Opens the engine on the adapter whose LUID is `luid` (high part in the
/// upper 32 bits) — Flutter's own. Null on failure; see the last error.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_open(luid: u64) -> *mut Engine {
    boxed(Engine::open(luid))
}

/// Opens the engine on the platform's only adapter — Android's, where
/// Flutter draws with the one GPU there is. Null on failure; see the last
/// error.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_open_sole() -> *mut Engine {
    boxed(Engine::open_sole())
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
    use crate::testing::first_engine;

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
