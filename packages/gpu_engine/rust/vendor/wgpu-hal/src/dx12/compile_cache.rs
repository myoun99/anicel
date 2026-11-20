//! ANICEL — not wgpu's: what a compile made, kept in a folder by everything
//! that was asked of it to make it — what DXC made of a shader ([`Made::Dxil`])
//! and what the driver made of a pipeline on it ([`Made::Pipeline`]) — so
//! that a launch after the first hands it back instead of compiling it again.
//!
//! 🗣️유저 2026-11-13 (the-wait-window-stands-seven-seconds-on-the-surface-Q1,
//! 「고친 사본을 묶는다 — 디스크 캐시 + 나란히 컴파일」): DXC was nine tenths
//! of every compile of the app's wait window on the Surface Pro 11, and
//! wgpu-hal 30 keeps what it makes in memory only (`ShaderCache`, one
//! device's), so every launch compiled all of it again.
//!
//! A file is named by the hash of what was asked and holds the whole of what
//! was asked beside what was made: ⛔a file is used only where all of it is
//! the same — for DXIL the compiler (version and commit), every argument it
//! was given and the HLSL; for a pipeline the adapter and its driver, the
//! root signature and the shader — so a hash that two askings share hands
//! neither the other's, and a file a crash cut short or a disk changed is a
//! miss, not what was made. The driver checks both besides.

use alloc::vec::Vec;
use std::{
    fs,
    io::{ErrorKind, Write as _},
    os::windows::fs::OpenOptionsExt as _,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, SystemTime},
};

use parking_lot::RwLock;

/// What a file starts with: what it is and which layout follows.
///
/// ⛔Named for DXIL, and kept so when pipelines came to be kept too
/// (2026-11-18): a test run's folder is one of the machine's, every
/// checkout's runs sharing it (test/flutter_test_config.dart), and a
/// checkout from before reads a DXIL file of this one's — the same name,
/// the same layout — only where the magic is the same. Another magic had
/// each side compile again whatever the other kept last.
const MAGIC: &[u8; 8] = b"ANIDXIL1";

/// The magic, then the lengths of what was asked and of what was made,
/// then the hash of what was made, each a little-endian `u64`.
const HEAD: usize = 32;

/// How much the folder may hold, the files used longest ago going first
/// once it holds more, as a device starts to keep what it makes there.
///
/// 🔬 What the app compiled from launch to the wait window's lifting was
/// 50 files, 2,567,829 bytes (Surface Pro 11, 11-13): this holds some 25
/// such sets, so the builds before an update are let go a few later.
const MOST_BYTES: u64 = 64 << 20;

/// How old a turn another holds ([`CompileCache::turn`]) may be and still
/// be waited for: past it, its holder is taken to have gone without letting
/// it go — the power cut as it compiled — and this one compiles past it.
///
/// ⚠️Estimated, not measured: a compile of the app's is a second or so of
/// one core (the Surface Pro 11's blur brush, ten kernels, 7.1–7.4 s), and
/// a test's patience with the wait window is a minute.
const TURN_STANDS: Duration = Duration::from_secs(30);

/// How long a compile waits between two looks at another's turn.
const TURN_LOOK: Duration = Duration::from_millis(10);

/// `FILE_FLAG_DELETE_ON_CLOSE`: a turn's file goes when its holder lets go
/// of it — closing it, or ending, however it ends.
const GOES_WITH_ITS_HOLDER: u32 = 0x0400_0000;

/// What a kept file holds.
#[derive(Clone, Copy)]
pub(super) enum Made {
    /// What DXC made of a shader.
    Dxil,
    /// What the driver made of a compute pipeline (`GetCachedBlob`), to be
    /// handed back to it (`CachedPSO`).
    ///
    /// 🔬Main PC, 18 test suites at once (timeline/conte, 11-18, board
    /// two-tests-spend-the-wait-windows-minute-under-load): NVIDIA's own
    /// cache of what it made answered ten processes at once; from the
    /// eleventh on, every pipeline was made in the driver again — even
    /// wgpu's own, 26–30 ms against 1–3 — some 12–25 s of a core a process,
    /// past the wait window's minute with the machine full. DXIL was handed
    /// in every process (~110 ms); what was left was the driver's.
    /// 🧭관제 11-18 「권고대로 가라: 파이프라인 블롭(GetCachedBlob →
    /// CachedPSO)을 DXIL 캐시 옆 · 같은 차례 파일 법으로」.
    Pipeline,
}

impl Made {
    fn extension(self) -> &'static str {
        match self {
            Self::Dxil => "dxil",
            Self::Pipeline => "pso",
        }
    }
}

/// What a compile of what was asked comes to ([`CompileCache::turn`]).
pub(super) enum Turn {
    /// What was made of it before — in this process or in another.
    Kept(Vec<u8>),
    /// Compiled here — and by no other process that keeps what it makes in
    /// the same folder, where this holds the turn: till it is let go, after
    /// what was made is kept.
    Compile(Option<fs::File>),
}

/// A device's folder for what its compiles made — none till one is named.
#[derive(Default)]
pub(super) struct CompileCache {
    folder: RwLock<Option<PathBuf>>,
    /// How many compiles of each [`Made`] the folder has answered
    /// ([`Self::used`]).
    found: [AtomicU64; 2],
    /// How many looks of a compile of each [`Made`] found another's turn
    /// held and waited ([`Self::turn`]).
    waited: [AtomicU64; 2],
}

impl CompileCache {
    /// Keeps what is made in `folder` from now on — made where it is not
    /// there, its oldest let go past [`MOST_BYTES`] — or nowhere where
    /// `folder` is `None`.
    pub(super) fn keep_in(&self, folder: Option<PathBuf>) {
        if let Some(folder) = &folder {
            if let Err(error) = fs::create_dir_all(folder) {
                log::warn!("compile cache {folder:?}: {error}");
            }
            let_go_past(folder, MOST_BYTES);
        }
        *self.folder.write() = folder;
    }

    /// What was made of `asked` before, if it is in the folder whole.
    fn read(&self, made: Made, asked: &[u8]) -> Option<Vec<u8>> {
        let path = self.path(made, asked)?;
        let file = fs::read(&path).ok()?;
        let kept = kept(&file, asked)?;
        // Used now: the last to go (`let_go_past`).
        if let Ok(touched) = fs::File::options().write(true).open(&path) {
            let _ = touched.set_modified(SystemTime::now());
        }
        Some(kept.to_vec())
    }

    /// What was made of `asked` before, else the turn to compile it: while
    /// another process holds it, this one waits for what that one keeps,
    /// rather than compiling the same beside it.
    ///
    /// 🚨★**A NEW KERNEL IS COMPILED ONCE ON A MACHINE, NOT ONCE A PROCESS.**
    /// 🔬Main PC, 17–18 test suites at once (brush/rendering, 11-13, board
    /// two-tests-spend-the-wait-windows-minute-under-load): with nothing in
    /// the folder each suite compiled every kernel at once beside the rest,
    /// and the Drive test's open window stood 60.8 s, against 5.9 s with
    /// the folder full. A lane that changes a kernel meets its first run
    /// so, the folder holding the kernel as it was.
    /// 🔬With the turn (timeline/conte, 11-17, main PC): nine copies of the
    /// Drive test sharing one folder of their own, empty, nine suites beside
    /// another run's nine — their first open windows 29.9–45.7 s, each
    /// making all twenty compiles itself, and 19.5–23.4 s, each waiting for
    /// one another's. ⚠️What is left is the twenty one after another, as each
    /// suite asks for them in the same order: a lane's first run still
    /// waits for its new kernels, though no longer once for each suite.
    ///
    /// A turn is a file beside the kept one, made where none is and gone
    /// with its holder ([`GOES_WITH_ITS_HOLDER`]). Where the folder cannot
    /// make one, this compiles with no turn, as it did before.
    ///
    /// 🚨**LOOKED AT AGAIN ONCE THE TURN IS HAD OR PASSED** (board
    /// a-kernel-wait-test-goes-red-under-load, 11-18): a holder keeps what it
    /// made before it lets go, so what it made is there for whoever comes
    /// after it. ↩️Looked at only before the turn was asked for, a holder
    /// that kept and let go between the look and the asking had what it
    /// made compiled again — and so had one whose turn was going as it was
    /// asked for. Under load the two steps stand apart: the pin of a kernel
    /// waited for found it compiled twice, in two lanes' gates that day.
    pub(super) fn turn(&self, made: Made, asked: &[u8]) -> Turn {
        let Some(turn) = self.path(made, asked).map(|path| path.with_extension("turn")) else {
            return Turn::Compile(None);
        };
        if let Some(kept) = self.read(made, asked) {
            return Turn::Kept(kept);
        }
        let held = loop {
            let taken = fs::File::options()
                .write(true)
                .create_new(true)
                .custom_flags(GOES_WITH_ITS_HOLDER)
                .open(&turn);
            match taken {
                Ok(held) => break Some(held),
                Err(error)
                    if error.kind() == ErrorKind::AlreadyExists && held_for(&turn, TURN_STANDS) =>
                {
                    self.waited[made as usize].fetch_add(1, Ordering::Relaxed);
                    std::thread::sleep(TURN_LOOK);
                }
                // A turn its holder never let go of, a turn going this very
                // moment, or a folder that makes none: compiled with no
                // turn, as before — a compile twice over at worst. One left
                // where it stands is past by the first compile, whose kernel
                // is read from then on.
                Err(_) => break None,
            }
        };
        // Kept by the turn's last holder: handed, and the turn let go here.
        match self.read(made, asked) {
            Some(kept) => Turn::Kept(kept),
            None => Turn::Compile(held),
        }
    }

    /// Counts a compile of `made` the folder answered: what [`Self::turn`]
    /// handed was used.
    pub(super) fn used(&self, made: Made) {
        self.found[made as usize].fetch_add(1, Ordering::Relaxed);
    }

    /// Keeps `bytes`, what was made of `asked`, for the next to ask —
    /// written beside its name and then renamed to it, so that no reader
    /// meets half of it. A failure leaves the folder as it was.
    pub(super) fn write(&self, made: Made, asked: &[u8], bytes: &[u8]) {
        let Some(path) = self.path(made, asked) else {
            return;
        };
        static WRITES: AtomicU64 = AtomicU64::new(0);
        let beside = path.with_extension(alloc::format!(
            "{}-{}.tmp",
            std::process::id(),
            WRITES.fetch_add(1, Ordering::Relaxed)
        ));
        let written = fs::File::create(&beside).and_then(|mut file| {
            file.write_all(&head(asked, bytes))?;
            file.write_all(asked)?;
            file.write_all(bytes)
        });
        if let Err(error) = written.and_then(|()| fs::rename(&beside, &path)) {
            log::warn!("compile cache {path:?}: {error}");
            let _ = fs::remove_file(&beside);
        }
    }

    fn path(&self, made: Made, asked: &[u8]) -> Option<PathBuf> {
        let folder = self.folder.read();
        let name = alloc::format!("{:016x}.{}", fnv1a(asked), made.extension());
        folder.as_ref().map(|folder| folder.join(name))
    }

    /// How many compiles of `made` the folder has answered since the device
    /// opened.
    pub(super) fn found(&self, made: Made) -> u64 {
        self.found[made as usize].load(Ordering::Relaxed)
    }

    /// How many looks of a compile of `made` have found another's turn
    /// held, since the device opened.
    pub(super) fn waited(&self, made: Made) -> u64 {
        self.waited[made as usize].load(Ordering::Relaxed)
    }
}

fn head(asked: &[u8], made: &[u8]) -> [u8; HEAD] {
    let mut head = [0; HEAD];
    head[..8].copy_from_slice(MAGIC);
    head[8..16].copy_from_slice(&(asked.len() as u64).to_le_bytes());
    head[16..24].copy_from_slice(&(made.len() as u64).to_le_bytes());
    head[24..].copy_from_slice(&fnv1a(made).to_le_bytes());
    head
}

/// What was made, in `file`, where the file is whole and was made of
/// `asked`.
fn kept<'a>(file: &'a [u8], asked: &[u8]) -> Option<&'a [u8]> {
    let word = |at: usize| u64::from_le_bytes(file[at..at + 8].try_into().unwrap());
    if file.len() < HEAD || &file[..8] != MAGIC {
        return None;
    }
    let (asked_len, made_len) = (word(8), word(16));
    if asked_len != asked.len() as u64
        || (HEAD as u64).checked_add(asked_len)?.checked_add(made_len)? != file.len() as u64
    {
        return None;
    }
    let (kept_asked, made) = file[HEAD..].split_at(asked.len());
    (kept_asked == asked && fnv1a(made) == word(24)).then_some(made)
}

/// Whether the turn at `path` was taken less than `stands` ago — or is
/// gone already, which the next look finds.
fn held_for(path: &Path, stands: Duration) -> bool {
    let Ok(taken) = fs::metadata(path).and_then(|meta| meta.modified()) else {
        return true;
    };
    taken.elapsed().map_or(true, |age| age < stands)
}

/// Deletes the files of `folder` used longest ago till it holds no more
/// than `most` bytes.
fn let_go_past(folder: &Path, most: u64) {
    let Ok(entries) = fs::read_dir(folder) else {
        return;
    };
    let mut files: Vec<(SystemTime, u64, PathBuf)> = entries
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let meta = entry.metadata().ok().filter(fs::Metadata::is_file)?;
            Some((meta.modified().ok()?, meta.len(), entry.path()))
        })
        .collect();
    let mut held: u64 = files.iter().map(|(_, len, _)| len).sum();
    files.sort();
    for (_, len, path) in files {
        if held <= most {
            break;
        }
        if fs::remove_file(&path).is_ok() {
            held -= len;
        }
    }
}

/// FNV-1a, 64 bits: the same on every machine and every Rust, so a name
/// written by one build is found by the next.
fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325, |hash, &byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x0100_0000_01b3)
    })
}

/// What was asked of a compile, as a key: each part its length and its
/// bytes, so that no two askings run together into one.
pub(super) fn asked<'a>(parts: impl IntoIterator<Item = &'a [u8]>) -> Vec<u8> {
    let mut asked = Vec::new();
    for part in parts {
        asked.extend_from_slice(&(part.len() as u64).to_le_bytes());
        asked.extend_from_slice(part);
    }
    asked
}
