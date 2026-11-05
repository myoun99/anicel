//! Anicel's GPU engine, stage 0 (gpu-engine-skeleton): one wgpu device,
//! one integer-only compute pass that fills a texture, and that texture
//! handed to Flutter's screen without a copy. Measurement only — nothing
//! in the app calls it yet.
//!
//! Windows first. The texture is a D3D12 committed resource shared by NT
//! handle, which Flutter's ANGLE opens with OpenSharedResource1; why this
//! path and not the others is on the board card.

mod pattern;
#[cfg(windows)]
mod shared_texture;

use std::cell::RefCell;
use std::ffi::c_void;
use std::sync::mpsc;
use std::time::Instant;

use pattern::{Fnv1a64, Order};

thread_local! {
    static LAST_ERROR: RefCell<String> = const { RefCell::new(String::new()) };
}

fn fail<T>(message: impl Into<String>) -> Option<T> {
    LAST_ERROR.with(|last| *last.borrow_mut() = message.into());
    None
}

/// One wgpu device on the adapter Flutter draws with.
pub struct Engine {
    adapter: wgpu::Adapter,
    device: wgpu::Device,
    queue: wgpu::Queue,
    params: wgpu::Buffer,
    pipelines: [Option<wgpu::ComputePipeline>; 2],
}

/// A texture the compute pass fills and Flutter shows.
pub struct Surface {
    texture: wgpu::Texture,
    bind_group: wgpu::BindGroup,
    order: Order,
    width: u32,
    height: u32,
    #[cfg(windows)]
    shared: shared_texture::SharedHandle,
}

impl Surface {
    fn extent(&self) -> wgpu::Extent3d {
        wgpu::Extent3d {
            width: self.width,
            height: self.height,
            depth_or_array_layers: 1,
        }
    }
}

const fn slot(order: Order) -> usize {
    match order {
        Order::Bgra => 0,
        Order::Rgba => 1,
    }
}

const fn format(order: Order) -> wgpu::TextureFormat {
    match order {
        Order::Bgra => wgpu::TextureFormat::Bgra8Unorm,
        Order::Rgba => wgpu::TextureFormat::Rgba8Unorm,
    }
}

impl Engine {
    fn open(luid: u64) -> Option<Self> {
        let mut desc = wgpu::InstanceDescriptor::new_without_display_handle();
        desc.backends = wgpu::Backends::DX12;
        let instance = wgpu::Instance::new(desc);
        let adapters = pollster::block_on(instance.enumerate_adapters(wgpu::Backends::DX12));
        let Some(adapter) = adapters
            .into_iter()
            .find(|adapter| adapter_luid(adapter) == Some(luid))
        else {
            return fail(format!("no DX12 adapter has LUID {luid:#x}"));
        };
        let required_features = adapter.features() & wgpu::Features::BGRA8UNORM_STORAGE;
        let request = adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("gpu_engine"),
            required_features,
            ..Default::default()
        });
        let (device, queue) = match pollster::block_on(request) {
            Ok(pair) => pair,
            Err(error) => return fail(format!("request_device: {error}")),
        };
        let params = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("fill params"),
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        Some(Self {
            adapter,
            device,
            queue,
            params,
            pipelines: [None, None],
        })
    }

    fn pipeline(&mut self, order: Order) -> &wgpu::ComputePipeline {
        let device = &self.device;
        self.pipelines[slot(order)].get_or_insert_with(|| {
            let token = match order {
                Order::Bgra => "bgra8unorm",
                Order::Rgba => "rgba8unorm",
            };
            let source = include_str!("fill.wgsl").replace("__FORMAT__", token);
            let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("fill"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
            device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("fill"),
                layout: None,
                module: &module,
                entry_point: Some("fill"),
                compilation_options: Default::default(),
                cache: None,
            })
        })
    }

    #[cfg(windows)]
    fn surface(&mut self, width: u32, height: u32, order: Order) -> Option<Surface> {
        if order == Order::Bgra && !self.device.features().contains(wgpu::Features::BGRA8UNORM_STORAGE) {
            return fail("this adapter cannot store to bgra8unorm from a compute pass");
        }
        let (texture, shared) =
            match shared_texture::create(&self.device, width, height, format(order)) {
                Ok(pair) => pair,
                Err(error) => return fail(error),
            };
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let layout = self.pipeline(order).get_bind_group_layout(0);
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("fill"),
            layout: &layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: self.params.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(&view),
                },
            ],
        });
        Some(Surface {
            texture,
            bind_group,
            order,
            width,
            height,
            shared,
        })
    }

    #[cfg(not(windows))]
    fn surface(&mut self, _width: u32, _height: u32, _order: Order) -> Option<Surface> {
        fail("stage 0 shares textures on Windows only")
    }

    /// Fills `surface` and waits until the GPU is done, because nothing
    /// else tells Flutter when to read it: the Windows descriptor has no
    /// fence, and ANGLE never takes a keyed mutex itself. Returns the
    /// wall time from submit to completion, in nanoseconds.
    fn fill(&mut self, surface: &Surface, seed: u32) -> Option<u64> {
        let params: Vec<u8> = [seed, surface.width, surface.height, 0]
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect();
        self.queue.write_buffer(&self.params, 0, &params);
        let pipeline = self.pipeline(surface.order).clone();
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(&pipeline);
            pass.set_bind_group(0, &surface.bind_group, &[]);
            pass.dispatch_workgroups(surface.width.div_ceil(8), surface.height.div_ceil(8), 1);
        }
        let start = Instant::now();
        self.queue.submit([encoder.finish()]);
        if let Err(error) = self.device.poll(wgpu::PollType::wait_indefinitely()) {
            return fail(format!("poll: {error}"));
        }
        Some(start.elapsed().as_nanos() as u64)
    }

    /// The FNV-1a hash of the surface's bytes, rows top to bottom, read
    /// back for the measurement — the screen path never reads back.
    fn read_hash(&self, surface: &Surface) -> Option<u64> {
        let row = surface.width * 4;
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
        let padded = row.div_ceil(align) * align;
        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("readback"),
            size: u64::from(padded) * u64::from(surface.height),
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo {
                texture: &surface.texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::TexelCopyBufferInfo {
                buffer: &buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(padded),
                    rows_per_image: Some(surface.height),
                },
            },
            surface.extent(),
        );
        self.queue.submit([encoder.finish()]);
        let (sender, receiver) = mpsc::channel();
        buffer.map_async(wgpu::MapMode::Read, .., move |result| {
            let _ = sender.send(result);
        });
        if let Err(error) = self.device.poll(wgpu::PollType::wait_indefinitely()) {
            return fail(format!("poll: {error}"));
        }
        match receiver.recv() {
            Ok(Ok(())) => {}
            Ok(Err(error)) => return fail(format!("map_async: {error}")),
            Err(error) => return fail(format!("map_async never answered: {error}")),
        }
        let bytes = match buffer.get_mapped_range(..) {
            Ok(view) => view,
            Err(error) => return fail(format!("get_mapped_range: {error}")),
        };
        let mut hash = Fnv1a64::new();
        for y in 0..surface.height as usize {
            let start = y * padded as usize;
            hash.write(&bytes[start..start + row as usize]);
        }
        Some(hash.finish())
    }
}

#[cfg(windows)]
fn adapter_luid(adapter: &wgpu::Adapter) -> Option<u64> {
    shared_texture::adapter_luid(adapter)
}

#[cfg(not(windows))]
fn adapter_luid(_adapter: &wgpu::Adapter) -> Option<u64> {
    None
}

fn order_of(bgra: bool) -> Order {
    if bgra { Order::Bgra } else { Order::Rgba }
}

fn copy_out(text: &str, buffer: *mut u8, capacity: usize) -> usize {
    let bytes = text.as_bytes();
    if !buffer.is_null() && capacity > 0 {
        let count = bytes.len().min(capacity);
        // SAFETY: the caller hands a buffer of `capacity` bytes.
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, count) };
    }
    bytes.len()
}

/// Opens the engine on the DX12 adapter whose LUID is `luid` (high part
/// in the upper 32 bits) — Flutter's own adapter, so the shared texture
/// lives on the GPU that reads it. Null on failure; see the last error.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_open(luid: u64) -> *mut Engine {
    Engine::open(luid).map_or(std::ptr::null_mut(), |engine| Box::into_raw(Box::new(engine)))
}

/// # Safety
/// `engine` came from `gpu_engine_open` and every surface made on it has
/// been freed.
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

/// This process's use of the adapter's local video memory, in bytes
/// (DXGI QueryVideoMemoryInfo, CurrentUsage); 0 when it cannot be read.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_video_memory(engine: *const Engine) -> u64 {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    #[cfg(windows)]
    {
        shared_texture::video_memory(&engine.adapter).unwrap_or(0)
    }
    #[cfg(not(windows))]
    {
        let _ = engine;
        0
    }
}

/// Makes a `width` × `height` texture of BGRA or RGBA 8-bit unorm texels,
/// shareable with Flutter. Null on failure; see the last error.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_new(
    engine: *mut Engine,
    width: u32,
    height: u32,
    bgra: bool,
) -> *mut Surface {
    // SAFETY: see the function's contract.
    let engine = unsafe { &mut *engine };
    engine
        .surface(width, height, order_of(bgra))
        .map_or(std::ptr::null_mut(), |surface| Box::into_raw(Box::new(surface)))
}

/// # Safety
/// `surface` came from `gpu_engine_surface_new` and Flutter no longer
/// shows it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_free(surface: *mut Surface) {
    if !surface.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(surface) });
    }
}

/// The NT handle Flutter opens the surface by (a Windows HANDLE).
///
/// # Safety
/// `surface` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_handle(surface: *const Surface) -> *mut c_void {
    // SAFETY: see the function's contract.
    let surface = unsafe { &*surface };
    #[cfg(windows)]
    {
        surface.shared.raw()
    }
    #[cfg(not(windows))]
    {
        let _ = surface;
        std::ptr::null_mut()
    }
}

/// Fills `surface` with the pattern for `seed` and waits for the GPU.
/// Returns the submit-to-done time in nanoseconds, or -1 on failure.
///
/// # Safety
/// `engine` and `surface` are live and `surface` was made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_fill(
    engine: *mut Engine,
    surface: *const Surface,
    seed: u32,
) -> i64 {
    // SAFETY: see the function's contract.
    let (engine, surface) = unsafe { (&mut *engine, &*surface) };
    engine.fill(surface, seed).map_or(-1, |nanos| nanos as i64)
}

/// Reads the surface back and writes the FNV-1a hash of its bytes to
/// `hash`. False on failure; see the last error.
///
/// # Safety
/// `engine` and `surface` are live, `surface` was made on `engine`, and
/// `hash` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_read_hash(
    engine: *const Engine,
    surface: *const Surface,
    hash: *mut u64,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, surface) = unsafe { (&*engine, &*surface) };
    match engine.read_hash(surface) {
        Some(value) => {
            // SAFETY: see the function's contract.
            unsafe { *hash = value };
            true
        }
        None => false,
    }
}

/// The hash the surface's bytes must have, worked out on the CPU.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_expected_hash(width: u32, height: u32, seed: u32, bgra: bool) -> u64 {
    pattern::expected_hash(width, height, seed, order_of(bgra))
}

/// The FNV-1a hash of `length` bytes — for bytes read off Flutter's
/// screen, so they are fingerprinted by the same code as the GPU's.
///
/// # Safety
/// `bytes` holds `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_hash_bytes(bytes: *const u8, length: usize) -> u64 {
    let mut hash = Fnv1a64::new();
    if !bytes.is_null() {
        // SAFETY: see the function's contract.
        hash.write(unsafe { std::slice::from_raw_parts(bytes, length) });
    }
    hash.finish()
}

/// Copies this thread's last error (UTF-8) into `buffer`; returns its
/// full length.
///
/// # Safety
/// `buffer` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_last_error(buffer: *mut u8, capacity: usize) -> usize {
    LAST_ERROR.with(|last| copy_out(&last.borrow(), buffer, capacity))
}
