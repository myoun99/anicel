//! A face's file the engine maps rather than copies
//! ([`gpu_engine_faces_file_at`](super::abi::gpu_engine_faces_file_at)):
//! its bytes are the file's own pages, read-only, which the OS shares with
//! whoever else maps the same file — and Flutter maps the app's bundled
//! fonts itself (`DirectoryAssetBundle::GetAsMapping`, and on Android the
//! APK's stored entries through `AAsset_getBuffer`), so the app's faces
//! lie in the memory once, and in none of the process' own.
//!
//! 🗣️유저 (engine-fonts-held-twice): 「사본이나 ram에있는걸 최대한
//! 없애고싶어서」. 🔬공통 11-21, a Windows release run: each of the six
//! bundled files was one mapped view (Flutter's) and one private copy
//! (the engine's, 35 MB of the 505 MB the memory tab calls this app's).
//!
//! ⚠️A SPAN OF A FILE, not a whole one: on Android a bundled face is an
//! entry lying stored in the APK (유저 11-22, engine-fonts-held-twice-Q1
//! 「글꼴을 압축 없이 두고 둘 다 비춰 쓴다」), so where it lies is the APK,
//! a start and a length — and a whole file is the span from 0 to its end.

#[cfg(test)]
pub(crate) mod tests;

use std::fs::File;
use std::path::Path;
use std::sync::Arc;

use read_fonts::model::Blob;

/// The `length` bytes at `offset` of the file at `path`, mapped read-only
/// for as long as a face holds them — None where they cannot be: no such
/// file, an empty span, one past the file's end, or a platform this has no
/// way to map on.
pub(super) fn mapped(path: &Path, offset: u64, length: u64) -> Option<Blob> {
    let file = File::open(path).ok()?;
    let end = offset.checked_add(length)?;
    if length == 0 || end > file.metadata().ok()?.len() {
        return None;
    }
    let view: Arc<dyn AsRef<[u8]> + Send + Sync> =
        Arc::new(os::View::of(&file, offset, usize::try_from(length).ok()?)?);
    Some(Blob::from(view))
}

/// Where a view that shows the bytes at `offset` begins — the last place
/// at or before it a view may begin at, every `step` bytes — and how far
/// into the view they lie.
fn view_from(offset: u64, step: u64) -> (u64, usize) {
    let begins = offset - offset % step;
    (begins, (offset - begins) as usize)
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
    use windows::Win32::System::SystemInformation::{GetSystemInfo, SYSTEM_INFO};
    use windows::core::PCWSTR;

    /// A read-only view of a span of a file.
    pub(super) struct View {
        at: MEMORY_MAPPED_VIEW_ADDRESS,
        skip: usize,
        length: usize,
    }

    // SAFETY: the view is read-only and lives till it is dropped; no one
    // writes its bytes.
    unsafe impl Send for View {}
    // SAFETY: as above.
    unsafe impl Sync for View {}

    impl View {
        pub(super) fn of(file: &File, offset: u64, length: usize) -> Option<Self> {
            let mut system = SYSTEM_INFO::default();
            // SAFETY: `system` is as long as the call fills.
            unsafe { GetSystemInfo(&mut system) };
            // A view begins where the system allocates.
            let (begins, skip) = super::view_from(offset, u64::from(system.dwAllocationGranularity));
            let file = HANDLE(file.as_raw_handle());
            // SAFETY: `file` is open for reading for the call; the mapping
            // is the whole file, read-only, nameless.
            let mapping =
                unsafe { CreateFileMappingW(file, None, PAGE_READONLY, 0, 0, PCWSTR::null()) }.ok()?;
            // SAFETY: `mapping` is the one made above, and the view lies
            // within the file (`mapped`).
            let at = unsafe {
                MapViewOfFile(mapping, FILE_MAP_READ, (begins >> 32) as u32, begins as u32, skip + length)
            };
            // The view keeps the mapping, and the mapping the file: neither
            // handle need outlive the call.
            // SAFETY: `mapping` is ours and closed once.
            let _ = unsafe { CloseHandle(mapping) };
            (!at.Value.is_null()).then(|| Self { at, skip, length })
        }
    }

    impl AsRef<[u8]> for View {
        fn as_ref(&self) -> &[u8] {
            // SAFETY: the view holds `skip + length` bytes till it is
            // dropped.
            unsafe { std::slice::from_raw_parts(self.at.Value.cast::<u8>().add(self.skip), self.length) }
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

    /// A read-only view of a span of a file.
    pub(super) struct View {
        at: *mut c_void,
        skip: usize,
        length: usize,
    }

    // SAFETY: the view is read-only and lives till it is dropped; no one
    // writes its bytes.
    unsafe impl Send for View {}
    // SAFETY: as above.
    unsafe impl Sync for View {}

    impl View {
        pub(super) fn of(file: &File, offset: u64, length: usize) -> Option<Self> {
            // SAFETY: a query of the system, no memory handed.
            let page = u64::try_from(unsafe { libc::sysconf(libc::_SC_PAGESIZE) }).ok()?;
            // A view begins on a page.
            let (begins, skip) = super::view_from(offset, page);
            // SAFETY: `file` is open for reading for the call; the view
            // lies within the file (`mapped`), read-only. The view keeps
            // the file: its descriptor need not outlive the call.
            let at = unsafe {
                libc::mmap(
                    std::ptr::null_mut(),
                    skip + length,
                    libc::PROT_READ,
                    libc::MAP_PRIVATE,
                    file.as_raw_fd(),
                    libc::off_t::try_from(begins).ok()?,
                )
            };
            (at != libc::MAP_FAILED).then(|| Self { at, skip, length })
        }
    }

    impl AsRef<[u8]> for View {
        fn as_ref(&self) -> &[u8] {
            // SAFETY: the view holds `skip + length` bytes till it is
            // dropped.
            unsafe { std::slice::from_raw_parts(self.at.cast::<u8>().add(self.skip), self.length) }
        }
    }

    impl Drop for View {
        fn drop(&mut self) {
            // SAFETY: the view is ours and unmapped once.
            unsafe { libc::munmap(self.at, self.skip + self.length) };
        }
    }
}

#[cfg(not(any(windows, unix)))]
mod os {
    use std::fs::File;

    /// No view: there is no way to map here.
    pub(super) struct View;

    impl View {
        pub(super) fn of(_: &File, _: u64, _: usize) -> Option<Self> {
            None
        }
    }

    impl AsRef<[u8]> for View {
        fn as_ref(&self) -> &[u8] {
            &[]
        }
    }
}
