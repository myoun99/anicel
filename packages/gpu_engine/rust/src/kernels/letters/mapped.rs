//! A face's file the engine maps rather than copies
//! ([`gpu_engine_faces_file_at`](super::abi::gpu_engine_faces_file_at)):
//! its bytes are the file's own pages, read-only, which the OS shares with
//! whoever else maps the same file — and Flutter maps the app's bundled
//! fonts itself (`DirectoryAssetBundle::GetAsMapping`), so the app's faces
//! lie in the memory once, and in none of the process' own.
//!
//! 🗣️유저 (engine-fonts-held-twice): 「사본이나 ram에있는걸 최대한
//! 없애고싶어서」. 🔬공통 11-21, a Windows release run: each of the six
//! bundled files was one mapped view (Flutter's) and one private copy
//! (the engine's, 35 MB of the 505 MB the memory tab calls this app's).

#[cfg(test)]
pub(crate) mod tests;

use std::fs::File;
use std::path::Path;
use std::sync::Arc;

use read_fonts::model::Blob;

/// The file at `path`, mapped read-only for as long as a face holds it —
/// None where it cannot be: no such file, an empty one, or a platform this
/// has no way to map on.
pub(super) fn mapped(path: &Path) -> Option<Blob> {
    let file = File::open(path).ok()?;
    let length = usize::try_from(file.metadata().ok()?.len()).ok()?;
    if length == 0 {
        return None;
    }
    let view: Arc<dyn AsRef<[u8]> + Send + Sync> = Arc::new(os::View::of(&file, length)?);
    Some(Blob::from(view))
}

#[cfg(windows)]
mod os {
    use std::fs::File;
    use std::os::windows::io::AsRawHandle;

    use windows::Win32::Foundation::{CloseHandle, HANDLE};
    use windows::Win32::System::Memory::{
        CreateFileMappingW, FILE_MAP_READ, MEMORY_MAPPED_VIEW_ADDRESS, MapViewOfFile, PAGE_READONLY,
        UnmapViewOfFile,
    };
    use windows::core::PCWSTR;

    /// A read-only view of a whole file.
    pub(super) struct View {
        at: MEMORY_MAPPED_VIEW_ADDRESS,
        length: usize,
    }

    // SAFETY: the view is read-only and lives till it is dropped; no one
    // writes its bytes.
    unsafe impl Send for View {}
    // SAFETY: as above.
    unsafe impl Sync for View {}

    impl View {
        pub(super) fn of(file: &File, length: usize) -> Option<Self> {
            let file = HANDLE(file.as_raw_handle());
            // SAFETY: `file` is open for reading for the call; the mapping
            // is the whole file, read-only, nameless.
            let mapping =
                unsafe { CreateFileMappingW(file, None, PAGE_READONLY, 0, 0, PCWSTR::null()) }.ok()?;
            // SAFETY: `mapping` is the one made above.
            let at = unsafe { MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0) };
            // The view keeps the mapping, and the mapping the file: neither
            // handle need outlive the call.
            // SAFETY: `mapping` is ours and closed once.
            let _ = unsafe { CloseHandle(mapping) };
            (!at.Value.is_null()).then(|| Self { at, length })
        }
    }

    impl AsRef<[u8]> for View {
        fn as_ref(&self) -> &[u8] {
            // SAFETY: the view holds `length` bytes till it is dropped.
            unsafe { std::slice::from_raw_parts(self.at.Value.cast::<u8>(), self.length) }
        }
    }

    impl Drop for View {
        fn drop(&mut self) {
            // SAFETY: the view is ours and unmapped once.
            let _ = unsafe { UnmapViewOfFile(self.at) };
        }
    }
}

#[cfg(unix)]
mod os {
    use std::ffi::c_void;
    use std::fs::File;
    use std::os::fd::AsRawFd;

    /// A read-only view of a whole file.
    pub(super) struct View {
        at: *mut c_void,
        length: usize,
    }

    // SAFETY: the view is read-only and lives till it is dropped; no one
    // writes its bytes.
    unsafe impl Send for View {}
    // SAFETY: as above.
    unsafe impl Sync for View {}

    impl View {
        pub(super) fn of(file: &File, length: usize) -> Option<Self> {
            // SAFETY: `file` is open for reading for the call; the view is
            // the whole file, read-only. The view keeps the file: its
            // descriptor need not outlive the call.
            let at = unsafe {
                libc::mmap(std::ptr::null_mut(), length, libc::PROT_READ, libc::MAP_PRIVATE, file.as_raw_fd(), 0)
            };
            (at != libc::MAP_FAILED).then(|| Self { at, length })
        }
    }

    impl AsRef<[u8]> for View {
        fn as_ref(&self) -> &[u8] {
            // SAFETY: the view holds `length` bytes till it is dropped.
            unsafe { std::slice::from_raw_parts(self.at.cast::<u8>(), self.length) }
        }
    }

    impl Drop for View {
        fn drop(&mut self) {
            // SAFETY: the view is ours and unmapped once.
            unsafe { libc::munmap(self.at, self.length) };
        }
    }
}

#[cfg(not(any(windows, unix)))]
mod os {
    use std::fs::File;

    /// No view: there is no way to map here.
    pub(super) struct View;

    impl View {
        pub(super) fn of(_: &File, _: usize) -> Option<Self> {
            None
        }
    }

    impl AsRef<[u8]> for View {
        fn as_ref(&self) -> &[u8] {
            &[]
        }
    }
}
