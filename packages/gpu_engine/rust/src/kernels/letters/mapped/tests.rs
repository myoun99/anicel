//! A face's file mapped is the file's own pages — what the OS says of the
//! memory its bytes lie in — and its bytes are the file's.

use super::*;

/// Where the app's bundled face `name` lies, beside the crate.
pub(crate) fn path_of(name: &str) -> String {
    let dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    format!("{dir}/../../../assets/fonts/{name}")
}

#[test]
fn a_mapped_file_is_the_file_s_bytes() {
    let path = path_of("NanumGothic-Regular.ttf");
    let file = mapped(Path::new(&path)).expect("mapped");
    assert!(file.as_ref() == std::fs::read(&path).expect("read").as_slice());
}

/// 🚨THE BYTES ARE THE FILE'S PAGES, NOT A COPY OF THEM: what the OS says of
/// the memory they lie in. A copy holds the same bytes, so only this tells
/// the two apart.
#[cfg(windows)]
#[test]
fn a_mapped_file_lies_in_a_view_of_the_file_not_in_the_process_own_memory() {
    use windows::Win32::System::Memory::{MEM_MAPPED, MEMORY_BASIC_INFORMATION, VirtualQuery};

    let file = mapped(Path::new(&path_of("NanumGothic-Regular.ttf"))).expect("mapped");
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
    let file = mapped(&path).expect("mapped");
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
    assert!(mapped(Path::new(&path_of("no-such-face.ttf"))).is_none());
    let empty = std::env::temp_dir().join(format!("anicel-empty-face-{}.ttf", std::process::id()));
    std::fs::write(&empty, []).expect("written");
    let none = mapped(&empty);
    std::fs::remove_file(&empty).expect("removed");
    assert!(none.is_none(), "an empty file");
}
