//! ANICEL — not wgpu's: what DXC made, kept in a folder by everything that
//! was asked of DXC to make it, so that a launch after the first hands the
//! driver what an earlier one compiled instead of compiling it again.
//!
//! 🗣️유저 2026-11-13 (the-wait-window-stands-seven-seconds-on-the-surface-Q1,
//! 「고친 사본을 묶는다 — 디스크 캐시 + 나란히 컴파일」): DXC was nine tenths
//! of every compile of the app's wait window on the Surface Pro 11, and
//! wgpu-hal 30 keeps what it makes in memory only (`ShaderCache`, one
//! device's), so every launch compiled all of it again.
//!
//! A file is named by the hash of what was asked and holds the whole of what
//! was asked beside the DXIL: ⛔a file is used only where all of it is the
//! same — the compiler (version and commit), every argument it was given and
//! the HLSL — so a hash that two askings share hands neither the other's
//! shader, and a file a crash cut short or a disk changed is a miss, not a
//! shader. The driver checks DXIL's own hash besides.

use alloc::vec::Vec;
use std::{
    fs,
    io::Write as _,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::SystemTime,
};

use parking_lot::RwLock;

/// What a file starts with: what it is and which layout follows.
const MAGIC: &[u8; 8] = b"ANIDXIL1";

/// The magic, then the lengths of what was asked and of the DXIL, then the
/// DXIL's hash, each a little-endian `u64`.
const HEAD: usize = 32;

/// How much the folder may hold, the files used longest ago going first
/// once it holds more, as a device starts to keep its shaders there.
///
/// 🔬 What the app compiled from launch to the wait window's lifting was
/// 50 files, 2,567,829 bytes (Surface Pro 11, 11-13): this holds some 25
/// such sets, so the builds before an update are let go a few later.
const MOST_BYTES: u64 = 64 << 20;

/// A device's folder for what DXC made — none till one is named.
#[derive(Default)]
pub(super) struct DxilCache {
    folder: RwLock<Option<PathBuf>>,
    /// How many compiles [`Self::read`] has answered.
    found: AtomicU64,
}

impl DxilCache {
    /// Keeps what DXC makes in `folder` from now on — made where it is not
    /// there, its oldest let go past [`MOST_BYTES`] — or nowhere where
    /// `folder` is `None`.
    pub(super) fn keep_in(&self, folder: Option<PathBuf>) {
        if let Some(folder) = &folder {
            if let Err(error) = fs::create_dir_all(folder) {
                log::warn!("DXIL cache {folder:?}: {error}");
            }
            let_go_past(folder, MOST_BYTES);
        }
        *self.folder.write() = folder;
    }

    /// What DXC made of `asked` before, if it is in the folder whole.
    pub(super) fn read(&self, asked: &[u8]) -> Option<Vec<u8>> {
        let path = self.path(asked)?;
        let file = fs::read(&path).ok()?;
        let dxil = kept_dxil(&file, asked)?;
        // Used now: the last to go (`let_go_past`).
        if let Ok(touched) = fs::File::options().write(true).open(&path) {
            let _ = touched.set_modified(SystemTime::now());
        }
        self.found.fetch_add(1, Ordering::Relaxed);
        Some(dxil.to_vec())
    }

    /// Keeps `dxil`, what DXC made of `asked`, for the next to ask —
    /// written beside its name and then renamed to it, so that no reader
    /// meets half of it. A failure leaves the folder as it was.
    pub(super) fn write(&self, asked: &[u8], dxil: &[u8]) {
        let Some(path) = self.path(asked) else {
            return;
        };
        static WRITES: AtomicU64 = AtomicU64::new(0);
        let beside = path.with_extension(alloc::format!(
            "{}-{}.tmp",
            std::process::id(),
            WRITES.fetch_add(1, Ordering::Relaxed)
        ));
        let written = fs::File::create(&beside).and_then(|mut file| {
            file.write_all(&head(asked, dxil))?;
            file.write_all(asked)?;
            file.write_all(dxil)
        });
        if let Err(error) = written.and_then(|()| fs::rename(&beside, &path)) {
            log::warn!("DXIL cache {path:?}: {error}");
            let _ = fs::remove_file(&beside);
        }
    }

    fn path(&self, asked: &[u8]) -> Option<PathBuf> {
        let folder = self.folder.read();
        let name = alloc::format!("{:016x}.dxil", fnv1a(asked));
        folder.as_ref().map(|folder| folder.join(name))
    }

    /// How many compiles the folder has answered since the device opened.
    pub(super) fn found(&self) -> u64 {
        self.found.load(Ordering::Relaxed)
    }
}

fn head(asked: &[u8], dxil: &[u8]) -> [u8; HEAD] {
    let mut head = [0; HEAD];
    head[..8].copy_from_slice(MAGIC);
    head[8..16].copy_from_slice(&(asked.len() as u64).to_le_bytes());
    head[16..24].copy_from_slice(&(dxil.len() as u64).to_le_bytes());
    head[24..].copy_from_slice(&fnv1a(dxil).to_le_bytes());
    head
}

/// The DXIL in `file` where the file is whole and was made of `asked`.
fn kept_dxil<'a>(file: &'a [u8], asked: &[u8]) -> Option<&'a [u8]> {
    let word = |at: usize| u64::from_le_bytes(file[at..at + 8].try_into().unwrap());
    if file.len() < HEAD || &file[..8] != MAGIC {
        return None;
    }
    let (asked_len, dxil_len) = (word(8), word(16));
    if asked_len != asked.len() as u64
        || (HEAD as u64).checked_add(asked_len)?.checked_add(dxil_len)? != file.len() as u64
    {
        return None;
    }
    let (kept_asked, dxil) = file[HEAD..].split_at(asked.len());
    (kept_asked == asked && fnv1a(dxil) == word(24)).then_some(dxil)
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

/// What was asked of DXC, as a key: each part its length and its bytes, so
/// that no two askings run together into one.
pub(super) fn asked<'a>(parts: impl IntoIterator<Item = &'a [u8]>) -> Vec<u8> {
    let mut asked = Vec::new();
    for part in parts {
        asked.extend_from_slice(&(part.len() as u64).to_le_bytes());
        asked.extend_from_slice(part);
    }
    asked
}
