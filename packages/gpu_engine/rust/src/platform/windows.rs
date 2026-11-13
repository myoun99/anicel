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

use std::ffi::{OsString, c_void};
use std::os::windows::ffi::OsStringExt;
use std::path::PathBuf;

use windows::Win32::Foundation::{CloseHandle, E_OUTOFMEMORY, GENERIC_ALL, HANDLE, HMODULE};
use windows::Win32::Graphics::Direct3D12::{
    D3D12_HEAP_FLAG_SHARED, D3D12_HEAP_PROPERTIES, D3D12_HEAP_TYPE_DEFAULT, D3D12_RESOURCE_DESC,
    D3D12_RESOURCE_DIMENSION_TEXTURE2D, D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET,
    D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,
    D3D12_RESOURCE_STATE_COMMON, D3D12_TEXTURE_LAYOUT_UNKNOWN, ID3D12Resource,
};
use windows::Win32::Graphics::Dxgi::Common::{
    DXGI_FORMAT, DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_FORMAT_R8G8B8A8_UNORM, DXGI_SAMPLE_DESC,
};
use windows::Win32::Graphics::Dxgi::{
    DXGI_ERROR_DEVICE_HUNG, DXGI_ERROR_DEVICE_REMOVED, DXGI_ERROR_DEVICE_RESET,
    DXGI_ERROR_DRIVER_INTERNAL_ERROR, DXGI_ERROR_INVALID_CALL, DXGI_MEMORY_SEGMENT_GROUP_LOCAL,
};
use windows::Win32::System::LibraryLoader::{
    GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
    GetModuleFileNameW, GetModuleHandleExW,
};
use windows::core::{HRESULT, PCWSTR};
use wgpu::hal::api::Dx12;

/// Flutter's ANGLE sits on D3D11, which opens a D3D12 resource by NT
/// handle; no other wgpu backend makes one.
pub const BACKENDS: wgpu::Backends = wgpu::Backends::DX12;

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

/// This process's use of the adapter's local video memory and the budget
/// the OS gives it there — past it, WDDM moves the process's video memory
/// out to system memory (F-569, RTX 4080: dedicated 4.9 → 2.4 GB).
pub fn video_memory(adapter: &wgpu::Adapter) -> Option<super::VideoMemory> {
    // SAFETY: only reads the adapter's memory report.
    let hal = unsafe { adapter.as_hal::<Dx12>() }?;
    let info = hal
        .raw_adapter()
        .query_video_memory_info(DXGI_MEMORY_SEGMENT_GROUP_LOCAL)
        .ok()?;
    Some(super::VideoMemory { used: info.CurrentUsage, budget: Some(info.Budget) })
}

/// Why the device went, as D3D12 says it was removed
/// (`GetDeviceRemovedReason`, [`removed_by`]) — unsaid while D3D12 names
/// no reason: the device is there still, or went by no word of its
/// driver's.
///
/// wgpu's own word of a lost device says none of this: its hal folds
/// `DXGI_ERROR_DEVICE_RESET` and `DXGI_ERROR_DEVICE_REMOVED` into one
/// `DeviceError::Lost` and every code else into `Unexpected`
/// (wgpu-hal-30.0.1/src/auxil/dxgi/result.rs), and the device is lost by
/// `DeviceLostReason::Unknown` whichever it was
/// (wgpu-core-30.0.1/src/device/resource.rs, `Device::lose`).
pub fn device_went_by(device: &wgpu::Device) -> u32 {
    // SAFETY: only asks the device why it was removed.
    let Some(hal) = (unsafe { device.as_hal::<Dx12>() }) else {
        return super::WENT_UNSAID;
    };
    // SAFETY: as above.
    match unsafe { hal.raw_device().GetDeviceRemovedReason() } {
        Ok(()) => super::WENT_UNSAID,
        Err(reason) => removed_by(reason.code()),
    }
}

/// D3D12's reason for a device removed, as the app names it. Each as
/// Microsoft says it (Learn, "Handle device removed scenarios in Direct3D
/// 11", read 2026-11-13): hung — the driver stopped responding over
/// commands this app sent; an invalid call — this app's own; removed —
/// the device taken out or turned off, or its driver upgraded; reset — a
/// command badly formed, with no word of whose; the driver's internal
/// error — the driver failed and reset the device.
fn removed_by(reason: HRESULT) -> u32 {
    match reason {
        DXGI_ERROR_DEVICE_HUNG | DXGI_ERROR_INVALID_CALL => super::WENT_BY_THIS_APP,
        DXGI_ERROR_DEVICE_REMOVED => super::WENT_BY_REMOVAL,
        DXGI_ERROR_DEVICE_RESET => super::WENT_BY_RESET,
        DXGI_ERROR_DRIVER_INTERNAL_ERROR => super::WENT_BY_DRIVER,
        E_OUTOFMEMORY => super::WENT_BY_MEMORY,
        _ => super::WENT_UNSAID,
    }
}

/// The pinned DXC (rust/build.rs), named by its full path — never wgpu's
/// `Auto`, which takes whatever dxcompiler.dll the DLL search reaches and
/// FXC when there is none (wgpu-hal-30.0.1/src/dx12/instance.rs:64-90).
/// A file that is not there opens no DX12 adapter at all rather than FXC
/// (instance.rs:50-57). gpu-engine-feasibility-Q4 (유저 2026-11-05:
/// 「DXC 로 바꾼다」).
pub fn shader_compiler() -> wgpu::Dx12Compiler {
    wgpu::Dx12Compiler::DynamicDxc {
        dxc_path: dxcompiler().to_string_lossy().into_owned(),
    }
}

/// cargo test's engine is the test binary, beside which nothing installs
/// the DLL: it takes build.rs's checked copy.
#[cfg(test)]
fn dxcompiler() -> PathBuf {
    PathBuf::from(env!("GPU_ENGINE_DXC"))
}

#[cfg(not(test))]
fn dxcompiler() -> PathBuf {
    beside_engine()
}

/// dxcompiler.dll beside the module this code is in: Flutter installs
/// every bundled code asset in one folder (windows/CMakeLists.txt,
/// NATIVE_ASSETS_DIR), and the build hook ships dxcompiler.dll as one.
/// Empty if the module cannot be named — a path that loads nothing.
fn beside_engine() -> PathBuf {
    let mut module = HMODULE::default();
    let here = PCWSTR(beside_engine as fn() -> PathBuf as *const u16);
    // SAFETY: `here` is an address inside this module; the handle is not
    // counted, so there is nothing to release.
    let found = unsafe {
        GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            here,
            &mut module,
        )
    };
    if found.is_err() {
        return PathBuf::new();
    }
    let mut name = vec![0u16; 32_768];
    // SAFETY: writes at most `name.len()` units.
    let length = unsafe { GetModuleFileNameW(Some(module), &mut name) } as usize;
    if length == 0 || length == name.len() {
        return PathBuf::new();
    }
    PathBuf::from(OsString::from_wide(&name[..length])).with_file_name("dxcompiler.dll")
}

#[cfg(test)]
mod tests {
    use crate::kernels::shared::pipeline_or_why;
    use crate::testing::first_engine;

    // The shape R1's vote table was first written in (gpu-canonical-store,
    // 브러시/렌더링 2026-11-05): indexed writes into arrays inside a struct
    // passed by pointer. FXC fails it with X3500 · X3511 (reproduced on this
    // PC, 보드/인프라 2026-11-05); DXC compiles it. R1 itself keeps the table
    // at module scope (shared/resample.wgsl) — the struct measured slower
    // under DXC too (브러시/렌더링 2026-11-05) — so this asks the compiler,
    // not R1.
    const FXC_CANNOT: &str = r#"
struct Wide { lo: u32, hi: u32 }
struct Table { keys: array<u32, 16>, weights: array<Wide, 16>, slots: u32, evicted: bool }
@group(0) @binding(0) var<storage, read_write> out: array<u32>;

fn vote(t: ptr<function, Table>, token: u32, w: Wide) {
  var slot = 16u;
  for (var s = 0u; s < (*t).slots; s = s + 1u) {
    if (slot == 16u && (*t).keys[s] == token) { slot = s; }
  }
  if (slot == 16u) {
    if ((*t).slots < 16u) {
      slot = (*t).slots;
      (*t).slots = (*t).slots + 1u;
      (*t).keys[slot] = token;
      (*t).weights[slot] = Wide(0u, 0u);
    } else {
      (*t).evicted = true;
      return;
    }
  }
  (*t).weights[slot].lo = (*t).weights[slot].lo + w.lo;
  (*t).weights[slot].hi = (*t).weights[slot].hi + w.hi;
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  var t: Table;
  for (var y = 0u; y < 8u; y = y + 1u) {
    for (var x = 0u; x < 8u; x = x + 1u) {
      vote(&t, (id.x * 31u + x * 7u + y) % 23u, Wide(x + y, 0u));
    }
  }
  var best = 0u;
  for (var s = 0u; s < t.slots; s = s + 1u) {
    if (t.weights[s].lo > t.weights[best].lo) { best = s; }
  }
  out[id.x] = t.keys[best];
}
"#;

    #[test]
    fn the_engine_compiles_what_fxc_cannot() {
        let engine = first_engine();
        let compiled = pipeline_or_why(engine, &[FXC_CANNOT], "main");
        assert!(compiled.is_ok(), "{:?}", compiled.err());
    }

    #[test]
    fn a_missing_dxcompiler_opens_no_adapter() {
        let mut desc = wgpu::InstanceDescriptor::new_without_display_handle();
        desc.backends = super::BACKENDS;
        desc.backend_options.dx12.shader_compiler = wgpu::Dx12Compiler::DynamicDxc {
            dxc_path: r"C:\nowhere\dxcompiler.dll".into(),
        };
        let instance = wgpu::Instance::new(desc);
        assert!(super::super::adapters(&instance).is_empty());
    }

    // The test binary is the module here, so the engine's own lookup
    // answers with the test binary's folder.
    #[test]
    fn dxcompiler_is_looked_for_beside_the_engine() {
        let exe = std::env::current_exe().expect("the test binary's path");
        assert_eq!(super::beside_engine(), exe.with_file_name("dxcompiler.dll"));
    }

    // Windows says the budget it gives this process — what a pool makes no
    // page past (kernels/pool) — and the app reads what the engine's own
    // device holds of it.
    #[test]
    fn windows_says_the_budget_it_gives_this_process() {
        let engine = first_engine();
        let memory = super::video_memory(&engine.adapter).expect("a memory report");
        assert!(memory.budget.is_some_and(|budget| budget > 0), "{memory:?}");
        // SAFETY: the test process's engine lives as long as the process.
        assert!(unsafe { crate::device::gpu_engine_video_memory(engine) } > 0);
    }

    // Each reason D3D12 gives for a device removed is the cause the app
    // says, and one it gives none for is unsaid — a device that is there
    // among them.
    #[test]
    fn a_device_removed_is_named_by_what_d3d12_says_took_it() {
        use windows::Win32::Foundation::{E_FAIL, E_OUTOFMEMORY, S_OK};
        use windows::Win32::Graphics::Dxgi::{
            DXGI_ERROR_DEVICE_HUNG, DXGI_ERROR_DEVICE_REMOVED, DXGI_ERROR_DEVICE_RESET,
            DXGI_ERROR_DRIVER_INTERNAL_ERROR, DXGI_ERROR_INVALID_CALL,
        };

        use crate::platform::{
            WENT_BY_DRIVER, WENT_BY_MEMORY, WENT_BY_REMOVAL, WENT_BY_RESET, WENT_BY_THIS_APP,
            WENT_UNSAID,
        };

        for (reason, named) in [
            (DXGI_ERROR_DEVICE_HUNG, WENT_BY_THIS_APP),
            (DXGI_ERROR_INVALID_CALL, WENT_BY_THIS_APP),
            (DXGI_ERROR_DEVICE_REMOVED, WENT_BY_REMOVAL),
            (DXGI_ERROR_DEVICE_RESET, WENT_BY_RESET),
            (DXGI_ERROR_DRIVER_INTERNAL_ERROR, WENT_BY_DRIVER),
            (E_OUTOFMEMORY, WENT_BY_MEMORY),
            (E_FAIL, WENT_UNSAID),
            (S_OK, WENT_UNSAID),
        ] {
            assert_eq!(super::removed_by(reason), named, "{reason:?}");
        }
        assert_eq!(super::device_went_by(&first_engine().device), WENT_UNSAID);
    }
}
