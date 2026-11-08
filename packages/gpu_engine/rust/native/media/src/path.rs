//! A path crosses into native code as UTF-8 and becomes wide exactly once
//! (↩️in the C engine's `qa_platform_path.h`, until the connection round
//! deleted it). Windows has two personalities for
//! a narrow path — UTF-8 or the machine's local codepage — and its narrow
//! entry points pick the second, so on a Korean or Japanese Windows a file
//! whose name is not ASCII fails to open with an error that says nothing
//! about encoding. ⛔A second way of widening one is how that comes back:
//! the span reader and the video writer both widen here.

use std::ffi::CStr;
use std::path::PathBuf;

/// The longest path, in UTF-16 units with its NUL — the C's buffer, kept: a
/// longer one is refused rather than cut (`span/tests.rs`).
#[cfg(windows)]
pub const WIDE: usize = 1024;

/// `qa_widen_path`: UTF-8 `path` made wide, NUL-terminated, an ill-formed
/// sequence replaced. ⚠️None when it does not fit rather than cut: half a
/// path names a different file, and opening the wrong one is worse than
/// not opening.
#[cfg(windows)]
pub fn wide(path: &CStr) -> Option<[u16; WIDE]> {
    use windows::Win32::Globalization::{CP_UTF8, MULTI_BYTE_TO_WIDE_CHAR_FLAGS, MultiByteToWideChar};
    let mut wide = [0u16; WIDE];
    // SAFETY: both buffers are the slices' own lengths; the NUL goes along,
    // so the wide path ends in one.
    let written =
        unsafe { MultiByteToWideChar(CP_UTF8, MULTI_BYTE_TO_WIDE_CHAR_FLAGS(0), path.to_bytes_with_nul(), Some(&mut wide)) };
    (written != 0).then_some(wide)
}

/// The file `path` names, as `qa_open_path_read` opens it: made wide once
/// on Windows, its bytes as they are everywhere else, where there is no
/// second personality to choose between.
pub fn file(path: &CStr) -> Option<PathBuf> {
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStringExt;
        let wide = wide(path)?;
        let end = wide.iter().position(|&unit| unit == 0)?;
        Some(PathBuf::from(std::ffi::OsString::from_wide(&wide[..end])))
    }
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        Some(PathBuf::from(std::ffi::OsStr::from_bytes(path.to_bytes())))
    }
}
