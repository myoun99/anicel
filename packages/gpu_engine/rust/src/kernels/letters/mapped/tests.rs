//! A face's file mapped is the file's own pages — what the OS says of the
//! memory its bytes lie in — and its bytes are the file's; a span of one,
//! the bytes it spans.

use super::*;

/// Where the app's bundled face `name` lies, beside the crate.
pub(crate) fn path_of(name: &str) -> String {
    let dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    format!("{dir}/../../../assets/fonts/{name}")
}

/// The file at `path` mapped whole — the span from 0 to its end.
fn whole(path: &Path) -> Option<Blob> {
    mapped(path, 0, std::fs::metadata(path).ok()?.len())
}

/// A file of `length` bytes each its place's, named for `name`, removed
/// when dropped.
struct Counted(std::path::PathBuf);

impl Counted {
    fn new(name: &str, length: usize) -> Self {
        let path = std::env::temp_dir().join(format!("anicel-{name}-{}.bin", std::process::id()));
        std::fs::write(&path, (0..length).map(|at| (at % 251) as u8).collect::<Vec<_>>()).expect("written");
        Self(path)
    }
}

impl Drop for Counted {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// 🚨A SPAN IS THE BYTES IT SPANS, wherever it begins — on no view's step
/// and past one (64 KiB on Windows, a page on unix) — and to the file's
/// very end.
#[test]
fn a_mapped_span_is_the_bytes_it_spans() {
    let file = Counted::new("span-of-a-file", 65_536 * 3 + 17);
    let bytes = std::fs::read(&file.0).expect("read");
    for (offset, length) in [(0, 10), (3, 4_096), (65_536 * 2 + 5, 12), (bytes.len() - 9, 9)] {
        let span = mapped(&file.0, offset as u64, length as u64).expect("mapped");
        assert!(span.as_ref() == &bytes[offset..offset + length], "{offset}+{length}");
    }
}

/// 🚨NOTHING PAST THE FILE'S END, and nothing of no length.
#[test]
fn a_span_past_the_end_or_of_nothing_is_none() {
    let file = Counted::new("span-past-the-end", 100);
    assert!(mapped(&file.0, 0, 100).is_some(), "LIVENESS: the whole of it is");
    assert!(mapped(&file.0, 1, 100).is_none(), "one past the end");
    assert!(mapped(&file.0, 101, 0).is_none(), "begun past the end");
    assert!(mapped(&file.0, 4, 0).is_none(), "of no length");
    assert!(mapped(&file.0, u64::MAX, 2).is_none(), "an end past every number");
}

#[test]
fn a_mapped_file_is_the_file_s_bytes() {
    let path = path_of("NanumGothic-Regular.ttf");
    let file = whole(Path::new(&path)).expect("mapped");
    assert!(file.as_ref() == std::fs::read(&path).expect("read").as_slice());
}

/// 🚨THE BYTES ARE THE FILE'S PAGES, NOT A COPY OF THEM: what the OS says of
/// the memory they lie in. A copy holds the same bytes, so only this tells
/// the two apart.
#[cfg(windows)]
#[test]
fn a_mapped_file_lies_in_a_view_of_the_file_not_in_the_process_own_memory() {
    use windows::Win32::System::Memory::{MEM_MAPPED, MEMORY_BASIC_INFORMATION, VirtualQuery};

    let file = whole(Path::new(&path_of("NanumGothic-Regular.ttf"))).expect("mapped");
    let mut told = MEMORY_BASIC_INFORMATION::default();
    // SAFETY: `told` is as long as it is said to be.
    let length = unsafe {
        VirtualQuery(Some(file.as_ref().as_ptr().cast()), &mut told, size_of::<MEMORY_BASIC_INFORMATION>())
    };
    assert_ne!(length, 0, "the OS says of the address");
    assert_eq!(told.Type, MEM_MAPPED);
}

/// As above, where the OS lists its views by the file they show.
#[cfg(any(target_os = "linux", target_os = "android"))]
#[test]
fn a_mapped_file_lies_in_a_view_of_the_file_not_in_the_process_own_memory() {
    let path = std::fs::canonicalize(path_of("NanumGothic-Regular.ttf")).expect("there");
    let file = whole(&path).expect("mapped");
    let at = file.as_ref().as_ptr() as usize;
    let maps = std::fs::read_to_string("/proc/self/maps").expect("the process' views");
    let view = maps
        .lines()
        .find(|line| {
            let (span, _) = line.split_once(' ').unwrap_or_default();
            let (from, to) = span.split_once('-').unwrap_or_default();
            let from = usize::from_str_radix(from, 16).unwrap_or(usize::MAX);
            let to = usize::from_str_radix(to, 16).unwrap_or(0);
            (from..to).contains(&at)
        })
        .expect("a view holds the bytes");
    assert!(view.ends_with(path.to_str().expect("UTF-8")), "{view}");
}

#[test]
fn what_cannot_be_mapped_is_none() {
    assert!(mapped(Path::new(&path_of("no-such-face.ttf")), 0, 1).is_none());
    let empty = std::env::temp_dir().join(format!("anicel-empty-face-{}.ttf", std::process::id()));
    std::fs::write(&empty, []).expect("written");
    let none = whole(&empty);
    std::fs::remove_file(&empty).expect("removed");
    assert!(none.is_none(), "an empty file");
}
