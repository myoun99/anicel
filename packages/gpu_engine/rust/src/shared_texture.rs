//! A wgpu texture that Flutter's ANGLE can open: a D3D12 committed
//! resource made on wgpu's own device, shared by NT handle.
//!
//! Each flag below is there because a source says so (gpu-engine-skeleton):
//! - HEAP_FLAG_SHARED + CreateSharedHandle: D3D11 opens a D3D12 resource
//!   with OpenSharedResource1 (MS docs, ID3D12Device::CreateSharedHandle),
//!   and Flutter's pinned ANGLE falls back to exactly that
//!   (Renderer11.cpp:1768-1771, SwapChain11.cpp:220-225).
//! - ALLOW_RENDER_TARGET: ANGLE refuses a client texture that is not
//!   renderable (SwapChain11.cpp:251-257).
//! - shader resource left allowed: without it ANGLE reads through a copy
//!   of its own (SwapChain11.cpp:343-360, mNeedsOffscreenTextureCopy).
//! - ALLOW_SIMULTANEOUS_ACCESS: such a texture decays to COMMON once its
//!   ExecuteCommandLists finishes (MS docs, "State decay to common"), so
//!   it is handed over without a barrier wgpu cannot express.
//! - ALLOW_UNORDERED_ACCESS: the compute pass stores into it.

use std::ffi::c_void;

use windows::Win32::Foundation::{CloseHandle, GENERIC_ALL, HANDLE};
use windows::Win32::Graphics::Direct3D12::{
    D3D12_HEAP_FLAG_SHARED, D3D12_HEAP_PROPERTIES, D3D12_HEAP_TYPE_DEFAULT, D3D12_RESOURCE_DESC,
    D3D12_RESOURCE_DIMENSION_TEXTURE2D, D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET,
    D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,
    D3D12_RESOURCE_STATE_COMMON, D3D12_TEXTURE_LAYOUT_UNKNOWN, ID3D12Resource,
};
use windows::Win32::Graphics::Dxgi::Common::{
    DXGI_FORMAT, DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_FORMAT_R8G8B8A8_UNORM, DXGI_SAMPLE_DESC,
};
use windows::Win32::Graphics::Dxgi::DXGI_MEMORY_SEGMENT_GROUP_LOCAL;
use windows::core::PCWSTR;
use wgpu::hal::api::Dx12;

/// The NT handle Flutter opens the texture by. Closing it does not free
/// the texture — wgpu and ANGLE each hold their own reference.
pub struct SharedHandle(HANDLE);

impl SharedHandle {
    pub fn raw(&self) -> *mut c_void {
        self.0.0
    }
}

impl Drop for SharedHandle {
    fn drop(&mut self) {
        // SAFETY: the handle came from CreateSharedHandle and is closed once.
        let _ = unsafe { CloseHandle(self.0) };
    }
}

fn dxgi_format(format: wgpu::TextureFormat) -> Result<DXGI_FORMAT, String> {
    match format {
        wgpu::TextureFormat::Bgra8Unorm => Ok(DXGI_FORMAT_B8G8R8A8_UNORM),
        wgpu::TextureFormat::Rgba8Unorm => Ok(DXGI_FORMAT_R8G8B8A8_UNORM),
        other => Err(format!("{other:?} is not a format Flutter's ANGLE shows")),
    }
}

pub fn create(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
) -> Result<(wgpu::Texture, SharedHandle), String> {
    // SAFETY: the raw device is only used to make a resource, never to
    // change wgpu's own state.
    let hal_device = unsafe { device.as_hal::<Dx12>() }.ok_or("not a DX12 device")?;
    let raw = hal_device.raw_device();
    let desc = D3D12_RESOURCE_DESC {
        Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
        Alignment: 0,
        Width: u64::from(width),
        Height: height,
        DepthOrArraySize: 1,
        MipLevels: 1,
        Format: dxgi_format(format)?,
        SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
        Layout: D3D12_TEXTURE_LAYOUT_UNKNOWN,
        Flags: D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS
            | D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET
            | D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS,
    };
    let heap = D3D12_HEAP_PROPERTIES {
        Type: D3D12_HEAP_TYPE_DEFAULT,
        ..Default::default()
    };
    let mut resource: Option<ID3D12Resource> = None;
    // SAFETY: every pointer is to a local that outlives the call.
    unsafe {
        raw.CreateCommittedResource(
            &heap,
            D3D12_HEAP_FLAG_SHARED,
            &desc,
            D3D12_RESOURCE_STATE_COMMON,
            None,
            &mut resource,
        )
    }
    .map_err(|error| format!("CreateCommittedResource: {error}"))?;
    let resource = resource.ok_or("CreateCommittedResource gave no resource")?;
    // SAFETY: the resource is live; GENERIC_ALL is the only access the
    // call accepts.
    let handle = unsafe { raw.CreateSharedHandle(&resource, None, GENERIC_ALL.0, PCWSTR::null()) }
        .map_err(|error| format!("CreateSharedHandle: {error}"))?;
    let shared = SharedHandle(handle);
    let size = wgpu::Extent3d {
        width,
        height,
        depth_or_array_layers: 1,
    };
    // SAFETY: the resource is a single-mip, single-sample 2D texture of
    // exactly this size and format.
    let hal_texture = unsafe {
        wgpu::hal::dx12::Device::texture_from_raw(
            resource,
            format,
            wgpu::TextureDimension::D2,
            size,
            1,
            1,
        )
    };
    // SAFETY: the texture matches the descriptor, and it starts in COMMON,
    // which is what UNINITIALIZED maps to in wgpu-hal's DX12 backend.
    let texture = unsafe {
        device.create_texture_from_hal::<Dx12>(
            hal_texture,
            &wgpu::TextureDescriptor {
                label: Some("shared surface"),
                size,
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format,
                usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::COPY_SRC,
                view_formats: &[],
            },
            wgpu::TextureUses::UNINITIALIZED,
        )
    };
    Ok((texture, shared))
}

/// The adapter's LUID, high part in the upper 32 bits.
pub fn adapter_luid(adapter: &wgpu::Adapter) -> Option<u64> {
    // SAFETY: only reads the adapter's description.
    let hal = unsafe { adapter.as_hal::<Dx12>() }?;
    // SAFETY: as above.
    let desc = unsafe { hal.raw_adapter().GetDesc2() }.ok()?;
    let luid = desc.AdapterLuid;
    Some((u64::from(luid.HighPart as u32) << 32) | u64::from(luid.LowPart))
}

/// This process's use of the adapter's local video memory, in bytes.
pub fn video_memory(adapter: &wgpu::Adapter) -> Option<u64> {
    // SAFETY: only reads the adapter's memory report.
    let hal = unsafe { adapter.as_hal::<Dx12>() }?;
    let info = hal
        .raw_adapter()
        .query_video_memory_info(DXGI_MEMORY_SEGMENT_GROUP_LOCAL)
        .ok()?;
    Some(info.CurrentUsage)
}
