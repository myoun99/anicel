//! What the driver made of a pipeline, kept and handed back
//! (vendor/wgpu-hal, auxil/compile_cache.rs) — the pins every platform
//! whose backend keeps it runs: D3D12 on Windows, Vulkan on Linux (and
//! Android, whose engine no test opens). What DXC made is D3D12's alone
//! (windows.rs).
//!
//! 🗣️관제 2026-11-24 (card the-galaxy-tab-canvas-went-slow-on-build-1095):
//! 「보관 파일이 깨지거나 드라이버가 바뀌어도 앱이 서야 한다 — 깨진 보관 ·
//! 다른 장치의 보관을 넣고 끄면 빨개지는 시험으로 (갤탭에서 첫 실행이 죽으면
//! 그 빌드는 못 쓴다)」 — each kept file below that is not what was made of
//! what is asked now is handed to no one, and the pipeline still comes.

use crate::kernels::shared::pipeline;
use crate::testing::{DeviceTurn, a_device_of_its_own};

// Each test's engines are its own, so that no other test's compiles go
// into its folder, and the folder is its own.
pub(crate) const WRITES_SEVEN: &str = "
@group(0) @binding(0) var<storage, read_write> out: array<u32>;
@compute @workgroup_size(1)
fn main() { out[0] = 7u; }
";

/// The test's folder to keep in, gone with the test — at its end, or as
/// it panics (oracle's `TempFile`). ↩️Each test removed its folder at
/// its last line, which a test that failed first never reached: 33 were
/// left in Temp on the main PC on 11-18 (card
/// engine-kept-tests-leave-their-folder-when-they-fail).
pub(crate) fn kept_in(name: &str) -> oracle::TempFile {
    oracle::TempFile::at(&format!("gpu_engine_kept_{name}"))
}

pub(crate) fn keeping(turn: &DeviceTurn, folder: &std::path::Path) -> crate::device::Engine {
    let engine = turn.engine();
    super::native::keep_shaders(engine.device(), Some(folder.to_path_buf()));
    engine
}

pub(crate) fn pipelines_found(engine: &crate::device::Engine) -> u64 {
    super::pipelines_found(engine.device()).expect("a backend that keeps")
}

/// The files of `folder` whose extension is `extension` — `dxil` what
/// DXC made, `pso` what the driver made of a pipeline, `turn` a turn.
pub(crate) fn kept_files(folder: &std::path::Path, extension: &str) -> Vec<(std::path::PathBuf, u64)> {
    let mut files: Vec<_> = std::fs::read_dir(folder)
        .map(|entries| {
            entries
                .filter_map(|entry| {
                    let entry = entry.ok()?;
                    Some((entry.path(), entry.metadata().ok()?.len()))
                })
                .filter(|(path, _)| path.extension().is_some_and(|it| it == extension))
                .collect()
        })
        .unwrap_or_default();
    files.sort();
    files
}

/// What `pipeline` writes to the first word of the buffer at binding 0.
pub(crate) fn first_word(engine: &crate::device::Engine, pipeline: &wgpu::ComputePipeline) -> u32 {
    use crate::kernels::shared::{Encoded, encode, whole};
    let out = engine.filled(
        "kept pipeline",
        &[0; 4],
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
    );
    encode(engine, &[Encoded { pipeline, bound: whole(&[(0, &out)]), groups: (1, 1, 1) }]);
    let bytes = crate::testing::read_buffer(engine, &out);
    u32::from_le_bytes(bytes[..4].try_into().unwrap())
}

/// `WRITES_SEVEN`'s pipeline as an engine keeping in `folder` kept it:
/// its file.
fn seven_kept(turn: &DeviceTurn, folder: &std::path::Path) -> std::path::PathBuf {
    let _ = pipeline(&keeping(turn, folder), &[WRITES_SEVEN], "main");
    let Ok([(path, _)]) = <[_; 1]>::try_from(kept_files(folder, "pso")) else {
        panic!("what the driver made is kept, in one file");
    };
    path
}

/// What the next engine keeping in `folder` makes of `WRITES_SEVEN`, and
/// how many pipelines the folder answered it.
fn seven_next(turn: &DeviceTurn, folder: &std::path::Path) -> (u32, u64) {
    let next = keeping(turn, folder);
    let made = pipeline(&next, &[WRITES_SEVEN], "main");
    (first_word(&next, &made), pipelines_found(&next))
}

// 🔬What the driver made of a pipeline, the next engine is handed — and
// it is that pipeline (board two-tests-spend-the-wait-windows-minute-
// under-load, 11-18: from the eleventh process on, NVIDIA's own cache
// made every pipeline again; card the-galaxy-tab-canvas-went-slow-on-
// build-1095, 11-24: the Galaxy Tab's Vulkan kept none at all).
#[test]
fn what_the_driver_made_of_a_pipeline_is_handed_to_the_next_engine() {
    let turn = a_device_of_its_own();
    let kept = kept_in("pso_handed");
    let folder = kept.path();
    let first = keeping(&turn, &folder);
    let _ = pipeline(&first, &[WRITES_SEVEN], "main");
    assert_eq!(pipelines_found(&first), 0, "nothing was kept before");
    assert_eq!(kept_files(&folder, "pso").len(), 1, "what the driver made is kept, in one file");
    let next = keeping(&turn, &folder);
    let made = pipeline(&next, &[WRITES_SEVEN], "main");
    assert_eq!(first_word(&next, &made), 7, "the next engine is handed it, and it is seven's");
    assert_eq!(pipelines_found(&next), 1);
    let mut said = [0u64; 6];
    // SAFETY: `next` is live and `said` holds six words.
    unsafe { crate::device::gpu_engine_compiles(&next, said.as_mut_ptr()) };
    assert_eq!(said[5], 1, "the frame statistics' COMPILE line says it was handed");
}

// A kept pipeline cut short — a crash as it was written, a disk — is
// made again, and kept whole.
#[test]
fn a_kept_pipeline_cut_short_is_made_again() {
    let turn = a_device_of_its_own();
    let kept = kept_in("pso_cut");
    let folder = kept.path();
    let path = seven_kept(&turn, &folder);
    let whole = std::fs::metadata(&path).expect("the file").len();
    std::fs::File::options()
        .write(true)
        .open(&path)
        .and_then(|file| file.set_len(whole - 1))
        .expect("the file cut short");
    assert_eq!(seven_next(&turn, &folder), (7, 0), "made again, handed to no one");
    assert_eq!(kept_files(&folder, "pso"), [(path, whole)], "kept whole again");
}

// A kept pipeline whose bytes changed on the disk, its length kept, is
// made again: the hash the file holds says so — ⛔never handed to a driver,
// which may take a blob its own checks pass and fault on it.
#[test]
fn a_kept_pipeline_changed_on_the_disk_is_made_again() {
    let turn = a_device_of_its_own();
    let kept = kept_in("pso_changed");
    let folder = kept.path();
    let path = seven_kept(&turn, &folder);
    let mut bytes = std::fs::read(&path).expect("the file");
    *bytes.last_mut().expect("a byte the driver made") ^= 1;
    std::fs::write(&path, &bytes).expect("the file changed");
    assert_eq!(seven_next(&turn, &folder), (7, 0), "what changed is handed to no one");
}

// A pipeline another adapter or driver made, under this one's name — as a
// folder carried to another device, or kept before a driver update, holds
// — is not handed: the adapter and its driver are the first of what was
// asked, and the whole of it is in the file.
#[test]
fn a_pipeline_kept_for_another_adapter_is_not_handed() {
    let turn = a_device_of_its_own();
    let kept = kept_in("pso_other_adapter");
    let folder = kept.path();
    let path = seven_kept(&turn, &folder);
    let mut bytes = std::fs::read(&path).expect("the file");
    // A kept file (compile_cache.rs): the magic, what was asked's length,
    // what was made's length and hash — eight bytes each — then what was
    // asked, its first part the adapter's name after its own length.
    bytes[32 + 8] ^= 1;
    std::fs::write(&path, &bytes).expect("another adapter's");
    assert_eq!(seven_next(&turn, &folder), (7, 0), "what another adapter made is handed to no one");
}

// What the driver made of another shader's pipeline, kept whole under
// this one's asking — as nothing in the folder can make it — is not taken
// by the driver, and the pipeline is made again and kept over it: D3D12's
// refuses it out loud, Vulkan's passes over it and says so
// (`VkPipelineCreationFeedback`, vendor/wgpu-hal, vulkan/device.rs) —
// ⛔where it says nothing, what was handed is counted as taken.
// 🧪What a refusal looks like whatever refuses: a driver updated past
// what the key names refuses alike, and the pipeline must still come.
#[test]
fn a_pipeline_the_driver_does_not_take_is_made_again_and_kept_over() {
    let turn = a_device_of_its_own();
    let kept = kept_in("pso_refused");
    let folder = kept.path();
    let first = keeping(&turn, &folder);
    let _ = pipeline(&first, &[WRITES_SEVEN], "main");
    let Ok([(seven, _)]) = <[_; 1]>::try_from(kept_files(&folder, "pso")) else {
        panic!("one pipeline is kept");
    };
    let _ = pipeline(&first, &[&WRITES_SEVEN.replace("7u", "8u")], "main");
    let eight = kept_files(&folder, "pso").into_iter().map(|(path, _)| path).find(|path| *path != seven);
    let (seven_file, eight_file) = (
        std::fs::read(&seven).expect("seven's"),
        std::fs::read(eight.expect("eight's")).expect("eight's"),
    );
    // A kept file (compile_cache.rs): the magic, what was asked's length,
    // what was made's length and hash — eight bytes each — then what
    // was asked, then what was made.
    let made_from = |file: &[u8]| 32 + u64::from_le_bytes(file[8..16].try_into().unwrap()) as usize;
    let forged = [
        &seven_file[..16],
        &eight_file[16..32],
        &seven_file[32..made_from(&seven_file)],
        &eight_file[made_from(&eight_file)..],
    ]
    .concat();
    std::fs::write(&seven, &forged).expect("eight's pipeline under seven's asking");
    let next = keeping(&turn, &folder);
    let made = pipeline(&next, &[WRITES_SEVEN], "main");
    assert_eq!(pipelines_found(&next), 0, "not taken, so made again");
    assert_eq!(first_word(&next, &made), 7, "and it is seven's");
    let last = keeping(&turn, &folder);
    let handed = pipeline(&last, &[WRITES_SEVEN], "main");
    assert_eq!(pipelines_found(&last), 1, "kept over what was not taken");
    assert_eq!(first_word(&last, &handed), 7);
}

// A turn is let go as its holder is done: no compile leaves one in the
// folder, where every later compile of that pipeline would wait on it.
// Windows lets go of the file itself; elsewhere the turn removes it.
#[test]
fn a_compile_leaves_no_turn_behind() {
    let turn = a_device_of_its_own();
    let kept = kept_in("pso_no_turn");
    let folder = kept.path();
    let _ = seven_kept(&turn, &folder);
    assert_eq!(kept_files(&folder, "turn"), [], "no turn left");
}

// A turn whose holder ended — the app killed as it compiled, its next
// launch a new process — is not waited for: the compile takes it past at
// its first look, not after `TURN_STANDS`.
#[cfg(target_os = "linux")]
#[test]
fn a_turn_whose_holder_ended_is_not_waited_for() {
    let turn = a_device_of_its_own();
    let made = kept_in("pso_ended_made");
    let name = seven_kept(&turn, &made.path()).file_name().expect("a name").to_owned();
    let kept = kept_in("pso_ended");
    let folder = kept.path();
    std::fs::create_dir_all(&folder).expect("the folder");
    // No process is u32::MAX: Linux numbers them below 2^22.
    std::fs::write(folder.join(&name).with_extension("turn"), u32::MAX.to_string()).expect("the turn");
    let next = keeping(&turn, &folder);
    let made = pipeline(&next, &[WRITES_SEVEN], "main");
    assert_eq!(super::vulkan::pipelines_waited(next.device()), 0, "its holder is gone, so not waited for");
    assert_eq!(first_word(&next, &made), 7);
}
