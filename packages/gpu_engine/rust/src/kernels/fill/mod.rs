//! Stage 0's kernel: every texel an integer function of (x, y, seed), so
//! every device must write the same bytes — `fill.wgsl` has why.

#[cfg(test)]
mod tests;

use std::time::Instant;

use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::storage_format;

/// The fill pass, one pipeline per texture format it has been run on.
pub struct Fill {
    params: wgpu::Buffer,
    pipelines: Vec<(wgpu::TextureFormat, wgpu::ComputePipeline)>,
}

impl Fill {
    pub(crate) fn new(engine: &Engine) -> Self {
        let params = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("fill params"),
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        Self {
            params,
            pipelines: Vec::new(),
        }
    }

    fn pipeline(
        &mut self,
        engine: &Engine,
        format: wgpu::TextureFormat,
    ) -> Option<wgpu::ComputePipeline> {
        if let Some((_, pipeline)) = self.pipelines.iter().find(|(made, _)| *made == format) {
            return Some(pipeline.clone());
        }
        let Some(token) = storage_format(format) else {
            return fail(format!("the fill pass cannot store to {format:?}"));
        };
        let source = include_str!("fill.wgsl").replace("__FORMAT__", token);
        let module = engine
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("fill"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
        let pipeline = engine
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("fill"),
                layout: None,
                module: &module,
                entry_point: Some("fill"),
                compilation_options: Default::default(),
                cache: None,
            });
        self.pipelines.push((format, pipeline.clone()));
        Some(pipeline)
    }

    /// Fills `texture` with the pattern for `seed` and waits until the GPU
    /// is done, because nothing else tells Flutter when to read it: the
    /// Windows descriptor has no fence, and ANGLE never takes a keyed
    /// mutex itself; Android hands Flutter a fence, but Flutter waits on it
    /// only from API 33 (FlutterRenderer.java:788-811). Returns the wall
    /// time from submit to completion, in nanoseconds.
    pub(crate) fn run(&mut self, engine: &Engine, texture: &wgpu::Texture, seed: u32) -> Option<u64> {
        let pipeline = self.pipeline(engine, texture.format())?;
        let (width, height) = (texture.width(), texture.height());
        let params: Vec<u8> = [seed, width, height, 0]
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect();
        engine.queue.write_buffer(&self.params, 0, &params);
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("fill"),
            layout: &pipeline.get_bind_group_layout(0),
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
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(&pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.dispatch_workgroups(width.div_ceil(8), height.div_ceil(8), 1);
        }
        let start = Instant::now();
        engine.queue.submit([encoder.finish()]);
        engine.wait()?;
        Some(start.elapsed().as_nanos() as u64)
    }
}

/// # Safety
/// `engine` is live; the kernel is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_fill_new(engine: *const Engine) -> *mut Fill {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    Box::into_raw(Box::new(Fill::new(engine)))
}

/// # Safety
/// `fill` came from `gpu_engine_fill_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_fill_free(fill: *mut Fill) {
    if !fill.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(fill) });
    }
}

/// Fills `texture` with the pattern for `seed` and waits for the GPU.
/// Returns the submit-to-done time in nanoseconds, or -1 on failure.
///
/// # Safety
/// `fill`, `engine` and `texture` are live, and `fill` and `texture` were
/// made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_fill_run(
    fill: *mut Fill,
    engine: *const Engine,
    texture: *const wgpu::Texture,
    seed: u32,
) -> i64 {
    // SAFETY: see the function's contract.
    let (fill, engine, texture) = unsafe { (&mut *fill, &*engine, &*texture) };
    fill.run(engine, texture, seed)
        .map_or(-1, |nanos| nanos as i64)
}
