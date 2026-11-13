use alloc::{string::String, vec::Vec};
use core::ffi::CStr;
use std::path::PathBuf;

use crate::auxil::dxgi::result::HResult;
use parking_lot::Mutex;
use thiserror::Error;
use windows::{
    core::{Interface, PCSTR, PCWSTR},
    Win32::Graphics::Direct3D::{Dxc, Fxc, ID3DBlob, D3D_SHADER_MACRO},
};

pub(super) enum CompilerContainer {
    Fxc(CompilerFxc),
    DynamicDxc(CompilerDynamicDxc),
    #[cfg_attr(not(static_dxc), allow(unused))]
    StaticDxc(CompilerStaticDxc),
}

pub(super) struct CompilerFxc {
    fxc: FxcLib,
}

pub(super) struct CompilerDynamicDxc {
    max_shader_model: wgt::DxcShaderModel,
    compilers: DxcCompilers,
    // Has to be held onto for the lifetime of the device otherwise shaders will fail to compile.
    // Only needed when using dynamic linking.
    dxc: DxcLib,
}

pub(super) struct CompilerStaticDxc {
    max_shader_model: wgt::DxcShaderModel,
    compilers: DxcCompilers,
}

/// ANICEL — not wgpu's: the DXC compilers one device compiles with, one to
/// each compile under way, and what DXC made kept on disk
/// ([`super::dxil_cache`]).
///
/// ↩️wgpu-hal 30 made one compiler and compiled on it from whatever thread
/// asked, with no lock — and 「objects created by DxcCreateInstance aren't
/// thread-safe」 (DXC wiki, "Using dxc.exe and dxcompiler.dll") — so the
/// app compiled one at a time (gpu_engine's `CompilerTurn`). 🗣️유저
/// 2026-11-13 (the-wait-window-stands-seven-seconds-on-the-surface-Q1,
/// 「디스크 캐시 + 나란히 컴파일」): a compile takes a compiler no other holds,
/// made where none is spare, and gives it back.
pub(super) struct DxcCompilers {
    /// Which DXC these are, by version and commit — what the disk knows
    /// what it holds by. None where DXC does not say, and nothing is kept.
    identity: Option<String>,
    spare: Mutex<Vec<Dxc::IDxcCompiler3>>,
}

#[derive(Debug, Error)]
pub(super) enum GetContainerError {
    #[error(transparent)]
    Device(#[from] crate::DeviceError),
    #[error("Failed to load {0}: {1}")]
    FailedToLoad(&'static str, libloading::Error),
}

impl CompilerContainer {
    pub(super) fn new_fxc() -> Result<Self, GetContainerError> {
        FxcLib::new_dynamic().map(|fxc| Self::Fxc(CompilerFxc { fxc }))
    }

    pub(super) fn new_dynamic_dxc(dxc_path: PathBuf) -> Result<Self, GetContainerError> {
        let dxc = DxcLib::new_dynamic(dxc_path)
            .map_err(|e| GetContainerError::FailedToLoad("dxcompiler.dll", e))?;

        let compiler = dxc.create_instance::<Dxc::IDxcCompiler3>()?;

        let (mut major, mut minor) = (1, 0);
        // DXC 1.0 didn't support this. If the cast fails assume it is DXC 1.0.
        if let Ok(version_info) = compiler.cast::<Dxc::IDxcVersionInfo>() {
            unsafe {
                version_info.GetVersion(&mut major, &mut minor).unwrap();
            }
        }

        Ok(Self::DynamicDxc(CompilerDynamicDxc {
            max_shader_model: wgt::DxcShaderModel::from_dxc_version(major, minor),
            compilers: DxcCompilers::new(compiler),
            dxc,
        }))
    }

    /// Creates a [`CompilerContainer`] that delegates to the statically-linked version of DXC.
    pub(super) fn new_static_dxc() -> Result<CompilerContainer, crate::DeviceError> {
        Ok(CompilerContainer::StaticDxc(CompilerStaticDxc {
            max_shader_model: wgt::DxcShaderModel::V6_7,
            compilers: DxcCompilers::new(static_compiler()?),
        }))
    }

    pub(super) fn max_shader_model(&self) -> Option<wgt::DxcShaderModel> {
        match self {
            CompilerContainer::Fxc(..) => None,
            CompilerContainer::DynamicDxc(CompilerDynamicDxc {
                max_shader_model, ..
            })
            | CompilerContainer::StaticDxc(CompilerStaticDxc {
                max_shader_model, ..
            }) => Some(max_shader_model.clone()),
        }
    }

    pub(super) fn compile(
        &self,
        device: &super::Device,
        source: &str,
        source_name: Option<&CStr>,
        raw_ep: &str,
        stage_bit: wgt::ShaderStages,
        full_stage: &str,
    ) -> Result<super::CompiledShader, crate::PipelineError> {
        match self {
            CompilerContainer::Fxc(CompilerFxc { fxc }) => compile_fxc(
                device,
                source,
                source_name,
                raw_ep,
                stage_bit,
                full_stage,
                fxc,
            ),
            CompilerContainer::DynamicDxc(CompilerDynamicDxc { compilers, dxc, .. }) => compilers
                .compile(
                    device,
                    source,
                    source_name,
                    raw_ep,
                    stage_bit,
                    full_stage,
                    || dxc.create_instance::<Dxc::IDxcCompiler3>(),
                ),
            CompilerContainer::StaticDxc(CompilerStaticDxc { compilers, .. }) => compilers
                .compile(
                    device,
                    source,
                    source_name,
                    raw_ep,
                    stage_bit,
                    full_stage,
                    static_compiler,
                ),
        }
    }
}

/// ANICEL: what [`CompilerContainer::new_static_dxc`] made its one
/// compiler with, now each of [`DxcCompilers`]'s.
fn static_compiler() -> Result<Dxc::IDxcCompiler3, crate::DeviceError> {
    #[cfg(static_dxc)]
    {
        unsafe {
            dxc_create_instance::<Dxc::IDxcCompiler3>(|clsid, iid, ppv| {
                windows_core::HRESULT(mach_dxcompiler_rs::DxcCreateInstance(
                    clsid.cast(),
                    iid.cast(),
                    ppv,
                ))
            })
        }
    }
    #[cfg(not(static_dxc))]
    {
        panic!("Attempted to create a static DXC shader compiler, but the static-dxc feature was not enabled")
    }
}

impl DxcCompilers {
    fn new(first: Dxc::IDxcCompiler3) -> Self {
        Self {
            identity: identity(&first),
            spare: Mutex::new(alloc::vec![first]),
        }
    }

    /// What DXC makes of `source`: what an earlier compile kept on disk
    /// where all that is asked is the same, else compiled on a compiler no
    /// other compile holds — one of [`Self::spare`], or `make`'s where none
    /// is — and kept.
    #[allow(clippy::too_many_arguments)]
    fn compile(
        &self,
        device: &super::Device,
        source: &str,
        source_name: Option<&CStr>,
        raw_ep: &str,
        stage_bit: wgt::ShaderStages,
        full_stage: &str,
        make: impl FnOnce() -> Result<Dxc::IDxcCompiler3, crate::DeviceError>,
    ) -> Result<super::CompiledShader, crate::PipelineError> {
        let args = dxc_args(device, source_name, raw_ep, full_stage);
        let asked = self.identity.as_ref().map(|identity| {
            super::dxil_cache::asked(
                [identity.as_bytes()]
                    .into_iter()
                    .chain(args.iter().map(|arg| arg.text.as_bytes()))
                    .chain([source.as_bytes()]),
            )
        });
        if let Some(dxil) = asked.as_ref().and_then(|asked| device.dxil_cache.read(asked)) {
            return Ok(super::CompiledShader::Precompiled(dxil));
        }
        let compiler = {
            let mut spare = self.spare.lock();
            match spare.pop() {
                Some(compiler) => compiler,
                None => make()?,
            }
        };
        let compiled = compile_dxc(source, &args, stage_bit, &compiler);
        self.spare.lock().push(compiler);
        let blob = compiled?;
        if let Some(asked) = &asked {
            let dxil = unsafe {
                core::slice::from_raw_parts(
                    blob.GetBufferPointer().cast::<u8>(),
                    blob.GetBufferSize(),
                )
            };
            device.dxil_cache.write(asked, dxil);
        }
        Ok(super::CompiledShader::Dxc(blob))
    }
}

/// Which DXC `compiler` is — its version and the commit it was built from
/// — or None where it does not say.
fn identity(compiler: &Dxc::IDxcCompiler3) -> Option<String> {
    let (mut major, mut minor) = (0, 0);
    unsafe { compiler.cast::<Dxc::IDxcVersionInfo>().ok()?.GetVersion(&mut major, &mut minor) }
        .ok()?;
    let (mut commits, mut hash) = (0, core::ptr::null_mut());
    unsafe {
        compiler
            .cast::<Dxc::IDxcVersionInfo2>()
            .ok()?
            .GetCommitInfo(&mut commits, &mut hash)
    }
    .ok()?;
    if hash.is_null() {
        return None;
    }
    // 「Must be CoTaskMemFree()'d」 (DXC 1.9.2609's dxcapi.h, GetCommitInfo).
    let commit = unsafe { CStr::from_ptr(hash) }.to_string_lossy().into_owned();
    unsafe { windows::Win32::System::Com::CoTaskMemFree(Some(hash.cast_const().cast())) };
    Some(format!("DXC {major}.{minor} {commits} {commit}"))
}

type D3DCompileFn = unsafe extern "system" fn(
    psrcdata: *const core::ffi::c_void,
    srcdatasize: usize,
    psourcename: PCSTR,
    pdefines: *const D3D_SHADER_MACRO,
    pinclude: *mut core::ffi::c_void,
    pentrypoint: PCSTR,
    ptarget: PCSTR,
    flags1: u32,
    flags2: u32,
    ppcode: *mut *mut core::ffi::c_void,
    pperrormsgs: *mut *mut core::ffi::c_void,
) -> windows_core::HRESULT;

#[derive(Debug)]
struct FxcLib {
    // `d3dcompile_fn` points into `_lib`, so `_lib` must be held for as long
    // as we want to keep compiling shaders with FXC.
    _lib: crate::dx12::DynLib,
    d3dcompile_fn: D3DCompileFn,
}

impl FxcLib {
    const PATH: &str = "d3dcompiler_47.dll";

    fn new_dynamic() -> Result<Self, GetContainerError> {
        unsafe {
            let lib = crate::dx12::DynLib::new(Self::PATH)
                .map_err(|e| GetContainerError::FailedToLoad(FxcLib::PATH, e))?;
            let d3dcompile_fn: D3DCompileFn = *lib.get::<D3DCompileFn>(c"D3DCompile".to_bytes())?;

            Ok(Self {
                _lib: lib,
                d3dcompile_fn,
            })
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn compile(
        &self,
        source: &str,
        source_name: Option<&CStr>,
        raw_ep: &str,
        full_stage: &str,
        compile_flags: u32,
        shader_data: &mut Option<ID3DBlob>,
        error: &mut Option<ID3DBlob>,
    ) -> Result<windows_core::Result<()>, crate::DeviceError> {
        unsafe {
            let raw_ep = alloc::ffi::CString::new(raw_ep).unwrap();
            let full_stage = alloc::ffi::CString::new(full_stage).unwrap();

            // If no name has been set, D3DCompile wants the null pointer.
            let source_name = source_name
                .map(|cstr| cstr.as_ptr().cast())
                .unwrap_or(core::ptr::null());

            let shader_data: *mut Option<ID3DBlob> = shader_data;
            let error: *mut Option<ID3DBlob> = error;

            {
                profiling::scope!("Fxc::D3DCompile");
                Ok((self.d3dcompile_fn)(
                    source.as_ptr().cast(),
                    source.len(),
                    PCSTR(source_name),
                    core::ptr::null(),
                    core::ptr::null_mut(),
                    PCSTR(raw_ep.as_ptr().cast()),
                    PCSTR(full_stage.as_ptr().cast()),
                    compile_flags,
                    0,
                    shader_data.cast(),
                    error.cast(),
                )
                .ok())
            }
        }
    }
}

fn compile_fxc(
    device: &super::Device,
    source: &str,
    source_name: Option<&CStr>,
    raw_ep: &str,
    stage_bit: wgt::ShaderStages,
    full_stage: &str,
    fxc: &FxcLib,
) -> Result<super::CompiledShader, crate::PipelineError> {
    profiling::scope!("compile_fxc");
    let mut compile_flags = Fxc::D3DCOMPILE_ENABLE_STRICTNESS;
    if device
        .shared
        .private_caps
        .instance_flags
        .contains(wgt::InstanceFlags::DEBUG)
    {
        compile_flags |= Fxc::D3DCOMPILE_DEBUG | Fxc::D3DCOMPILE_SKIP_OPTIMIZATION;
    }

    let mut shader_data = None;
    let mut error = None;
    let hr = fxc.compile(
        source,
        source_name,
        raw_ep,
        full_stage,
        compile_flags,
        &mut shader_data,
        &mut error,
    )?;

    match hr {
        Ok(()) => {
            let shader_data = shader_data.unwrap();
            Ok(super::CompiledShader::Fxc(shader_data))
        }
        Err(e) => {
            let mut full_msg = format!("FXC D3DCompile error ({e})");
            if let Some(error) = error {
                use core::fmt::Write as _;
                let message = unsafe {
                    core::slice::from_raw_parts(
                        error.GetBufferPointer().cast(),
                        error.GetBufferSize(),
                    )
                };
                let _ = write!(full_msg, ": {}", String::from_utf8_lossy(message));
            }
            Err(crate::PipelineError::Linkage(stage_bit, full_msg))
        }
    }
}

trait DxcObj: Interface {
    const CLSID: windows::core::GUID;
}
impl DxcObj for Dxc::IDxcCompiler3 {
    const CLSID: windows::core::GUID = Dxc::CLSID_DxcCompiler;
}
impl DxcObj for Dxc::IDxcUtils {
    const CLSID: windows::core::GUID = Dxc::CLSID_DxcUtils;
}
impl DxcObj for Dxc::IDxcValidator {
    const CLSID: windows::core::GUID = Dxc::CLSID_DxcValidator;
}

#[derive(Debug)]
struct DxcLib {
    lib: crate::dx12::DynLib,
}

impl DxcLib {
    fn new_dynamic(lib_path: PathBuf) -> Result<Self, libloading::Error> {
        unsafe { crate::dx12::DynLib::new(lib_path).map(|lib| Self { lib }) }
    }

    pub fn create_instance<T: DxcObj>(&self) -> Result<T, crate::DeviceError> {
        unsafe {
            type DxcCreateInstanceFn = unsafe extern "system" fn(
                rclsid: *const windows_core::GUID,
                riid: *const windows_core::GUID,
                ppv: *mut *mut core::ffi::c_void,
            )
                -> windows_core::HRESULT;

            let func: libloading::Symbol<DxcCreateInstanceFn> =
                self.lib.get(c"DxcCreateInstance".to_bytes())?;
            dxc_create_instance::<T>(|clsid, iid, ppv| func(clsid, iid, ppv))
        }
    }
}

/// Invokes the provided library function to create a DXC object.
unsafe fn dxc_create_instance<T: DxcObj>(
    f: impl Fn(
        *const windows_core::GUID,
        *const windows_core::GUID,
        *mut *mut core::ffi::c_void,
    ) -> windows_core::HRESULT,
) -> Result<T, crate::DeviceError> {
    let mut result__ = None;
    f(&T::CLSID, &T::IID, <*mut _>::cast(&mut result__))
        .ok()
        .into_device_result("DxcCreateInstance")?;
    result__.ok_or(crate::DeviceError::Unexpected)
}

/// Owned PCWSTR
#[allow(clippy::upper_case_acronyms)]
struct OPCWSTR {
    inner: Vec<u16>,
    /// ANICEL: what it says, for what DXC was asked to be known by
    /// ([`super::dxil_cache::asked`]).
    text: String,
}

impl OPCWSTR {
    fn new(s: &str) -> Self {
        let mut inner: Vec<_> = s.encode_utf16().collect();
        inner.push(0);
        Self {
            inner,
            text: s.into(),
        }
    }

    /// ANICEL: one of DXC's own argument words, owned.
    fn of(arg: PCWSTR) -> Self {
        Self::new(&unsafe { arg.to_string() }.unwrap_or_default())
    }

    fn ptr(&self) -> PCWSTR {
        PCWSTR(self.inner.as_ptr())
    }
}

fn get_output<T: Interface>(
    res: &Dxc::IDxcResult,
    kind: Dxc::DXC_OUT_KIND,
) -> Result<T, crate::DeviceError> {
    let mut result__: Option<T> = None;
    unsafe { res.GetOutput::<T>(kind, &mut None, <*mut _>::cast(&mut result__)) }
        .into_device_result("GetOutput")?;
    result__.ok_or(crate::DeviceError::Unexpected)
}

fn as_err_str(blob: &Dxc::IDxcBlobUtf8) -> Result<&str, crate::DeviceError> {
    let ptr = unsafe { blob.GetStringPointer() };
    let len = unsafe { blob.GetStringLength() };
    core::str::from_utf8(unsafe { core::slice::from_raw_parts(ptr.0, len) })
        .map_err(|_| crate::DeviceError::Unexpected)
}

/// ANICEL: the arguments [`compile_dxc`] gives DXC — wgpu-hal 30's, each
/// owned, so that what DXC is asked can be told whole
/// ([`DxcCompilers::compile`]).
fn dxc_args(
    device: &crate::dx12::Device,
    source_name: Option<&CStr>,
    raw_ep: &str,
    full_stage: &str,
) -> Vec<OPCWSTR> {
    let source_name = source_name.and_then(|cstr| cstr.to_str().ok());

    let mut compile_args = Vec::with_capacity(13);

    if let Some(source_name) = source_name {
        compile_args.push(OPCWSTR::new(source_name))
    }

    compile_args.extend([
        OPCWSTR::new("-E"),
        OPCWSTR::new(raw_ep),
        OPCWSTR::new("-T"),
        OPCWSTR::new(full_stage),
        OPCWSTR::new("-HV"),
        OPCWSTR::new("2018"), // Use HLSL 2018, Naga doesn't supported 2021 yet.
        OPCWSTR::new("-no-warnings"),
        OPCWSTR::of(Dxc::DXC_ARG_ENABLE_STRICTNESS),
    ]);

    if device
        .shared
        .private_caps
        .instance_flags
        .contains(wgt::InstanceFlags::DEBUG)
        && !device
            .shared
            .private_caps
            .workarounds
            .avoid_shader_debug_info
    {
        compile_args.push(OPCWSTR::of(Dxc::DXC_ARG_DEBUG));
        compile_args.push(OPCWSTR::of(Dxc::DXC_ARG_SKIP_OPTIMIZATIONS));
    }

    if device
        .features
        .intersects(wgt::Features::SHADER_F16 | wgt::Features::SHADER_I16)
    {
        compile_args.push(OPCWSTR::new("-enable-16bit-types"));
    }

    compile_args
}

fn compile_dxc(
    source: &str,
    args: &[OPCWSTR],
    stage_bit: wgt::ShaderStages,
    compiler: &Dxc::IDxcCompiler3,
) -> Result<Dxc::IDxcBlob, crate::PipelineError> {
    profiling::scope!("compile_dxc");

    let compile_args: Vec<PCWSTR> = args.iter().map(OPCWSTR::ptr).collect();

    let buffer = Dxc::DxcBuffer {
        Ptr: source.as_ptr().cast(),
        Size: source.len(),
        Encoding: Dxc::DXC_CP_UTF8.0,
    };

    let compile_res: Dxc::IDxcResult =
        unsafe { compiler.Compile(&buffer, Some(&compile_args), None) }
            .into_device_result("Compile")?;

    drop(compile_args);

    let err_blob = get_output::<Dxc::IDxcBlobUtf8>(&compile_res, Dxc::DXC_OUT_ERRORS)?;

    let len = unsafe { err_blob.GetStringLength() };
    if len != 0 {
        let err = as_err_str(&err_blob)?;
        return Err(crate::PipelineError::Linkage(
            stage_bit,
            format!("DXC compile error: {err}"),
        ));
    }

    let blob = get_output::<Dxc::IDxcBlob>(&compile_res, Dxc::DXC_OUT_OBJECT)?;

    Ok(blob)
}
