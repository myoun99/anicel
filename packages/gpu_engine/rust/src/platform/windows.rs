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

/// What DXC makes for `device` kept in `folder`, or nowhere where it is
/// `None` (vendor/wgpu-hal, dxil_cache.rs).
pub fn keep_dxil(device: &wgpu::Device, folder: Option<PathBuf>) {
    // SAFETY: names only where the hal device keeps what DXC made.
    if let Some(hal_device) = unsafe { device.as_hal::<Dx12>() } {
        hal_device.keep_dxil_in(folder);
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
    use crate::kernels::shared::{pipeline, pipeline_or_why};
    use crate::testing::{DeviceTurn, a_device_of_its_own, first_engine};

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

    // ---- What DXC made, kept (vendor/wgpu-hal, dxil_cache.rs) ----

    // Each test's engines are its own, so that no other test's compiles go
    // into its folder, and the folder is its own.
    const WRITES_SEVEN: &str = "
@group(0) @binding(0) var<storage, read_write> out: array<u32>;
@compute @workgroup_size(1)
fn main() { out[0] = 7u; }
";

    fn kept_in(name: &str) -> std::path::PathBuf {
        let folder = std::env::temp_dir().join(format!("gpu_engine_dxil_{}_{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        folder
    }

    fn keeping(turn: &DeviceTurn, folder: &std::path::Path) -> crate::device::Engine {
        let engine = turn.engine();
        super::keep_dxil(&engine.device, Some(folder.to_path_buf()));
        engine
    }

    fn found(engine: &crate::device::Engine) -> u64 {
        // SAFETY: only reads a count.
        unsafe { engine.device.as_hal::<super::Dx12>() }.expect("DX12").dxil_found()
    }

    fn kept_files(folder: &std::path::Path) -> Vec<(std::path::PathBuf, u64)> {
        let mut files: Vec<_> = std::fs::read_dir(folder)
            .map(|entries| {
                entries
                    .filter_map(|entry| {
                        let entry = entry.ok()?;
                        Some((entry.path(), entry.metadata().ok()?.len()))
                    })
                    .collect()
            })
            .unwrap_or_default();
        files.sort();
        files
    }

    /// What `pipeline` writes to the first word of the buffer at binding 0.
    fn first_word(engine: &crate::device::Engine, pipeline: &wgpu::ComputePipeline) -> u32 {
        use crate::kernels::shared::{Encoded, encode, whole};
        let out = engine.filled(
            "kept DXIL",
            &[0; 4],
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        );
        encode(engine, &[Encoded { pipeline, bound: whole(&[(0, &out)]), groups: (1, 1, 1) }]);
        let bytes = crate::testing::read_buffer(engine, &out);
        u32::from_le_bytes(bytes[..4].try_into().unwrap())
    }

    // 🗣️유저 2026-11-13 (the-wait-window-stands-seven-seconds-on-the-surface-Q1,
    // 「디스크 캐시」): what one engine's DXC made, the next is handed — and
    // it is that kernel.
    #[test]
    fn what_dxc_made_is_handed_to_the_next_engine() {
        let turn = a_device_of_its_own();
        let folder = kept_in("handed");
        let first = keeping(&turn, &folder);
        let _ = pipeline(&first, &[WRITES_SEVEN], "main");
        assert_eq!(found(&first), 0, "nothing was kept before");
        let Ok([(path, _)]) = <[_; 1]>::try_from(kept_files(&folder)) else {
            panic!("what DXC made is kept, in one file");
        };
        // Used an hour ago — and used again now, so the last to go when the
        // folder lets its oldest go.
        let an_hour_ago = std::time::SystemTime::now() - std::time::Duration::from_secs(3600);
        let file = std::fs::File::options().write(true).open(&path).expect("the file");
        file.set_modified(an_hour_ago).expect("its age");
        drop(file);
        let next = keeping(&turn, &folder);
        let handed = pipeline(&next, &[WRITES_SEVEN], "main");
        assert_eq!(found(&next), 1, "the next engine is handed it");
        assert_eq!(first_word(&next, &handed), 7);
        let used = std::fs::metadata(&path).and_then(|meta| meta.modified()).expect("its age");
        assert!(used > an_hour_ago + std::time::Duration::from_secs(1800), "used now");
        let _ = std::fs::remove_dir_all(&folder);
    }

    // A file cut short — a crash as it was written, a disk — is compiled
    // again, and kept whole.
    #[test]
    fn a_kept_file_cut_short_is_compiled_again() {
        let turn = a_device_of_its_own();
        let folder = kept_in("cut");
        let _ = pipeline(&keeping(&turn, &folder), &[WRITES_SEVEN], "main");
        let Ok([(path, whole)]) = <[_; 1]>::try_from(kept_files(&folder)) else {
            panic!("one file is kept");
        };
        std::fs::File::options()
            .write(true)
            .open(&path)
            .and_then(|file| file.set_len(whole - 1))
            .expect("the file cut short");
        let next = keeping(&turn, &folder);
        let compiled = pipeline(&next, &[WRITES_SEVEN], "main");
        assert_eq!(found(&next), 0, "what was cut short is handed to no one");
        assert_eq!(first_word(&next, &compiled), 7);
        assert_eq!(kept_files(&folder), [(path, whole)], "kept whole again");
        let _ = std::fs::remove_dir_all(&folder);
    }

    // A file whose DXIL changed on the disk, its length kept, is compiled
    // again: the hash it holds says so.
    #[test]
    fn a_kept_file_changed_on_the_disk_is_compiled_again() {
        let turn = a_device_of_its_own();
        let folder = kept_in("changed");
        let _ = pipeline(&keeping(&turn, &folder), &[WRITES_SEVEN], "main");
        let Ok([(path, _)]) = <[_; 1]>::try_from(kept_files(&folder)) else {
            panic!("one file is kept");
        };
        let mut bytes = std::fs::read(&path).expect("the file");
        *bytes.last_mut().expect("a byte of DXIL") ^= 1;
        std::fs::write(&path, &bytes).expect("the file changed");
        let next = keeping(&turn, &folder);
        let compiled = pipeline(&next, &[WRITES_SEVEN], "main");
        assert_eq!(found(&next), 0, "what changed is handed to no one");
        assert_eq!(first_word(&next, &compiled), 7);
        let _ = std::fs::remove_dir_all(&folder);
    }

    // What one asking kept, under the name of another's — as two whose
    // hashes are one would be — is not handed for that other: the whole of
    // what was asked is in the file.
    #[test]
    fn a_file_under_another_s_name_is_not_handed() {
        let turn = a_device_of_its_own();
        let folder = kept_in("renamed");
        let first = keeping(&turn, &folder);
        let _ = pipeline(&first, &[WRITES_SEVEN], "main");
        let Ok([(seven, _)]) = <[_; 1]>::try_from(kept_files(&folder)) else {
            panic!("one file is kept");
        };
        let _ = pipeline(&first, &[&WRITES_SEVEN.replace("7u", "8u")], "main");
        let eight = kept_files(&folder).into_iter().map(|(path, _)| path).find(|path| *path != seven);
        std::fs::rename(eight.expect("the second file"), &seven).expect("put under the first's name");
        let next = keeping(&turn, &folder);
        let compiled = pipeline(&next, &[WRITES_SEVEN], "main");
        assert_eq!(found(&next), 0, "what another asked is handed to no one");
        assert_eq!(first_word(&next, &compiled), 7);
        let _ = std::fs::remove_dir_all(&folder);
    }

    // The app names its folder before it opens its engine
    // (`gpu_engine_keep_shaders_in`): each engine opened from then on keeps
    // what DXC made there, and hands it to the next.
    #[test]
    fn engines_opened_once_the_app_names_a_folder_keep_their_shaders_there() {
        let turn = a_device_of_its_own();
        let folder = kept_in("named");
        let named = folder.to_string_lossy().into_owned();
        // SAFETY: `named` holds its length.
        unsafe { crate::platform::gpu_engine_keep_shaders_in(named.as_ptr(), named.len()) };
        let (first, next) = (turn.engine(), turn.engine());
        // SAFETY: a length of 0 reads nothing.
        unsafe { crate::platform::gpu_engine_keep_shaders_in(std::ptr::null(), 0) };
        let _ = pipeline(&first, &[WRITES_SEVEN], "main");
        let handed = pipeline(&next, &[WRITES_SEVEN], "main");
        assert_eq!(found(&next), 1, "the next engine is handed it");
        assert_eq!(first_word(&next, &handed), 7);
        let _ = std::fs::remove_dir_all(&folder);
    }

    // What another source asked is not handed for this one: each is kept
    // by all that was asked, and each handed its own. (⚠️By the HLSL naga
    // makes of it: two sources that differ in a comment are one.)
    #[test]
    fn what_was_asked_otherwise_is_kept_apart() {
        let turn = a_device_of_its_own();
        let folder = kept_in("apart");
        let writes_eight = WRITES_SEVEN.replace("7u", "8u");
        let first = keeping(&turn, &folder);
        let _ = pipeline(&first, &[WRITES_SEVEN], "main");
        let _ = pipeline(&first, &[&writes_eight], "main");
        assert_eq!(found(&first), 0);
        assert_eq!(kept_files(&folder).len(), 2);
        let next = keeping(&turn, &folder);
        let (seven, eight) = (
            pipeline(&next, &[WRITES_SEVEN], "main"),
            pipeline(&next, &[&writes_eight], "main"),
        );
        assert_eq!(found(&next), 2, "each is handed");
        assert_eq!((first_word(&next, &seven), first_word(&next, &eight)), (7, 8));
        let _ = std::fs::remove_dir_all(&folder);
    }

    // A folder past what it may hold lets go of what was used longest ago,
    // as a device starts to keep its shaders there.
    #[test]
    fn a_folder_past_its_most_lets_its_oldest_go() {
        let turn = a_device_of_its_own();
        let folder = kept_in("most");
        std::fs::create_dir_all(&folder).expect("the folder");
        let old = folder.join("old.dxil");
        let new = folder.join("new.dxil");
        for (path, mib, age) in [(&old, 40, 3600), (&new, 30, 0)] {
            let file = std::fs::File::create(path).expect("a file");
            file.set_len(mib << 20).expect("its length");
            let then = std::time::SystemTime::now() - std::time::Duration::from_secs(age);
            file.set_modified(then).expect("its age");
        }
        drop(keeping(&turn, &folder));
        assert!(!old.exists(), "the one used longest ago went");
        assert!(new.exists(), "what fits stayed");
        let _ = std::fs::remove_dir_all(&folder);
    }
}
