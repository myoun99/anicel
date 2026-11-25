//! What /proc/self/smaps says, read as text: the Linux
//! kernel's account of a process's mappings (`linux.rs` reads the files).
//! Compiled on every platform so its tests run wherever the crate's do —
//! the files are only Linux's and Android's.
#![cfg_attr(any(windows, target_vendor = "apple"), allow(dead_code))]

/// The kilobytes one Private_Clean or Private_Dirty line names — the
/// rollup's lines and each mapping's in /proc/self/smaps are the same.
pub(crate) fn private_kilobytes(line: &str) -> Option<u64> {
    let rest = line
        .strip_prefix("Private_Clean:")
        .or_else(|| line.strip_prefix("Private_Dirty:"))?
        .trim_start();
    let end = rest.find(|c: char| !c.is_ascii_digit()).unwrap_or(rest.len());
    rest[..end].parse().ok()
}

/// The private bytes of each mapping name in an smaps text, the most first.
/// A mapping's line is its address range and four fields, then its name —
/// a file's last part, a kernel's or the allocator's own in brackets, none
/// for plain anonymous memory.
pub(crate) fn private_by_mapping(smaps: &str) -> Vec<(String, u64)> {
    let mut held: Vec<(String, u64)> = Vec::new();
    let mut at: Option<usize> = None;
    for line in smaps.lines() {
        if let Some(name) = mapping_name(line) {
            let i = held.iter().position(|(n, _)| *n == name).unwrap_or_else(|| {
                held.push((name, 0));
                held.len() - 1
            });
            at = Some(i);
        } else if let (Some(i), Some(kilobytes)) = (at, private_kilobytes(line)) {
            held[i].1 += kilobytes * 1024;
        }
    }
    held.retain(|(_, bytes)| *bytes > 0);
    held.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    held
}

/// The name a mapping's first line gives it, or None for any other line.
fn mapping_name(line: &str) -> Option<String> {
    let range = line.split_whitespace().next()?;
    let (start, end) = range.split_once('-')?;
    let hex = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_hexdigit());
    if !hex(start) || !hex(end) {
        return None;
    }
    let mut rest = line;
    for _ in 0..5 {
        rest = rest.trim_start();
        rest = &rest[rest.find(char::is_whitespace).unwrap_or(rest.len())..];
    }
    let name = rest.trim();
    Some(match name {
        "" => "[anon]".to_owned(),
        path if path.starts_with('/') => path.rsplit('/').next().unwrap_or(path).to_owned(),
        other => other.to_owned(),
    })
}

#[cfg(test)]
mod tests {
    use super::private_by_mapping;

    // Two mappings of one file, an allocator's own, a driver's and plain
    // anonymous memory, as /proc/self/smaps writes them: each name's private
    // pages summed, the most first, the ones holding none left out.
    #[test]
    fn each_mapping_says_its_private_pages_by_name() {
        let smaps = "\
7f0000000000-7f0000100000 r-xp 00000000 fd:01 1234     /system/lib64/libc.so
Rss:                1024 kB
Private_Clean:       100 kB
Private_Dirty:        20 kB
VmFlags: rd ex mr mw me
7f0000100000-7f0000200000 rw-p 00100000 fd:01 1234     /system/lib64/libc.so
Private_Dirty:         8 kB
7f0000200000-7f0010200000 rw-s 00000000 00:0d 77       /dev/kgsl-3d0
Private_Clean:         0 kB
Private_Dirty:    262144 kB
7f0010200000-7f0010300000 rw-p 00000000 00:00 0        [anon:scudo:primary]
Private_Dirty:      2048 kB
7f0010300000-7f0010400000 rw-p 00000000 00:00 0
Private_Dirty:      4096 kB
7f0010400000-7f0010500000 r--p 00000000 00:00 0        [vvar]
Private_Dirty:         0 kB
";
        assert_eq!(
            private_by_mapping(smaps),
            vec![
                ("kgsl-3d0".to_owned(), 262144 * 1024),
                ("[anon]".to_owned(), 4096 * 1024),
                ("[anon:scudo:primary]".to_owned(), 2048 * 1024),
                ("libc.so".to_owned(), 128 * 1024),
            ],
        );
        assert_eq!(private_by_mapping("Private_Dirty: 4 kB\n"), vec![]);
    }
}
