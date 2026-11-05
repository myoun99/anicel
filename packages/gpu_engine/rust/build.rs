//! Fetches the one DXC the engine compiles DX12 shaders with, checks it
//! against the pin below, and puts dxcompiler.dll where the engine's tests
//! and the build hook take it (gpu-engine-feasibility-Q4 · Q5, 유저
//! 2026-11-05: 「DXC 로 바꾼다」 · 「GitHub 릴리스 zip 을 받는다」).
//!
//! ⛔No other source and no fallback: not the build machine's Windows SDK
//! copy, whose version moves with every SDK update (관제 2026-11-05), and a
//! missing or mismatched file fails the build rather than leaving the
//! engine on FXC.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use sha2::{Digest, Sha256};

/// DirectXShaderCompiler v1.9.2609, the latest stable release on
/// 2026-11-05. From v1.8.2505 dxcompiler.dll validates inside itself and
/// never looks for a dxil.dll (that release's notes), so none is shipped
/// and none on the PC can change what it does.
const ZIP_URL: &str = "https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2609/dxc_2026_09_29.zip";
/// GitHub's digest of that asset (32,287,592 bytes).
const ZIP_SHA256: &str = "ad31b1fc8443175d204f77a611fdb3ef2ec42759bdc2f1167368de24a4a7e7f1";
/// The dxcompiler.dll in it for each Windows architecture the engine
/// builds for — Microsoft-signed, version 1.9.2609.5. Its licence is the
/// LLVM Release License (NCSA): the notice ships with the app.
const DLLS: [(&str, &str, &str); 2] = [
    (
        "x86_64",
        "bin/x64/dxcompiler.dll",
        "0689e2fee0a1c9df8662a59680469f24e2a3ad7ce6bbbcc9284f7a83172bfc59",
    ),
    (
        "aarch64",
        "bin/arm64/dxcompiler.dll",
        "ec234595c270a908da183eb04f1f5a1a667d3ce81e69f5bc55370503dab48373",
    ),
];

/// Where the build hook asks for a copy (hook/build.dart).
const HOOK_DIR: &str = "GPU_ENGINE_DXC_OUT";

fn sha256(path: &Path) -> Option<String> {
    let bytes = fs::read(path).ok()?;
    Some(Sha256::digest(bytes).iter().map(|byte| format!("{byte:02x}")).collect())
}

fn check(path: &Path, pinned: &str) {
    let found = sha256(path);
    assert_eq!(found.as_deref(), Some(pinned), "{} is not the pinned file", path.display());
}

fn run(command: &mut Command) {
    let status = command.status().unwrap_or_else(|error| panic!("{command:?}: {error}"));
    assert!(status.success(), "{command:?}: {status}");
}

/// curl and tar as Windows 10 and later ship them: a shell's PATH may put
/// another tar first (Git Bash's GNU tar), which cannot read a zip.
fn windows_tool(name: &str) -> Command {
    let root = env::var("SystemRoot").expect("SystemRoot");
    Command::new(Path::new(&root).join("System32").join(name))
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed={HOOK_DIR}");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    let arch = env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH");
    let (_, member, pinned) = DLLS
        .iter()
        .find(|(dll_arch, ..)| *dll_arch == arch)
        .unwrap_or_else(|| panic!("no dxcompiler.dll is pinned for {arch}"));
    let out = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let dll = out.join("dxcompiler.dll");
    if sha256(&dll).as_deref() != Some(pinned) {
        let zip = out.join("dxc.zip");
        if sha256(&zip).as_deref() != Some(ZIP_SHA256) {
            run(windows_tool("curl.exe").args(["-sSfL", "--retry", "3", "-o"]).arg(&zip).arg(ZIP_URL));
            check(&zip, ZIP_SHA256);
        }
        run(windows_tool("tar.exe").arg("-xf").arg(&zip).arg("-C").arg(&out).arg(member));
        fs::rename(out.join(member), &dll).expect("move dxcompiler.dll out of the zip's folders");
        check(&dll, pinned);
    }
    println!("cargo:rerun-if-changed={}", dll.display());
    println!("cargo:rustc-env=GPU_ENGINE_DXC={}", dll.display());
    if let Ok(dir) = env::var(HOOK_DIR) {
        let copy = PathBuf::from(dir).join("dxcompiler.dll");
        fs::create_dir_all(copy.parent().unwrap()).expect("make the hook's folder");
        fs::copy(&dll, &copy).expect("copy dxcompiler.dll for the hook");
        println!("cargo:rerun-if-changed={}", copy.display());
    }
}
