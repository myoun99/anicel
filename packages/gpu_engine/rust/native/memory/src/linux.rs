//! Linux and Android — every OS the C's last arm took: the kernel's
//! sysinfo, and the process's own sum of its mappings.

use std::mem::zeroed;

fn info() -> Option<libc::sysinfo> {
    // SAFETY: plain integers, for the kernel to fill.
    let mut info: libc::sysinfo = unsafe { zeroed() };
    // SAFETY: a sysinfo to fill.
    (unsafe { libc::sysinfo(&mut info) } == 0).then_some(info)
}

pub(crate) fn physical() -> Option<u64> {
    info().map(|info| info.totalram as u64 * u64::from(info.mem_unit))
}

/// /proc/self/smaps_rollup is the kernel's own sum over every mapping
/// (4.14 on), so this is one small read instead of a walk of
/// /proc/self/smaps. Private_Clean + Private_Dirty is the same quantity the
/// other platforms answer — pages no other process shares.
pub(crate) fn footprint() -> Option<u64> {
    let rollup = std::fs::read_to_string("/proc/self/smaps_rollup").ok()?;
    private_bytes(&rollup)
}

/// The private pages a rollup names, or None where it names neither line.
/// A line is read as the C's `sscanf("Private_Clean: %lld kB")` read it:
/// the number after the name, whatever follows it.
fn private_bytes(rollup: &str) -> Option<u64> {
    let kilobytes: Vec<u64> = rollup
        .lines()
        .filter_map(|line| {
            let rest = line
                .strip_prefix("Private_Clean:")
                .or_else(|| line.strip_prefix("Private_Dirty:"))?
                .trim_start();
            let end = rest.find(|c: char| !c.is_ascii_digit()).unwrap_or(rest.len());
            rest[..end].parse().ok()
        })
        .collect();
    (!kilobytes.is_empty()).then(|| kilobytes.iter().sum::<u64>() * 1024)
}

pub(crate) fn available() -> Option<u64> {
    info().map(|info| info.freeram as u64 * u64::from(info.mem_unit))
}

pub(crate) fn app_limit() -> Option<u64> {
    None
}

#[cfg(test)]
mod tests {
    use super::private_bytes;

    // The two lines a rollup sums, as the kernel writes them. The C read them
    // with sscanf("Private_Clean: %lld kB"), which takes the number and asks
    // nothing of what follows; any other line, or a rollup with neither,
    // says nothing.
    #[test]
    fn a_rollup_says_its_private_pages() {
        let rollup = "Rss:               20480 kB\nPrivate_Clean:      1024 kB\n\
                      Private_Dirty:      3072 kB\nShared_Clean:      8192 kB\n";
        assert_eq!(private_bytes(rollup), Some(4096 * 1024));
        assert_eq!(private_bytes("Rss: 20480 kB\nShared_Dirty: 4 kB\n"), None);
        assert_eq!(private_bytes("Private_Dirty: 0 kB\n"), Some(0));
        assert_eq!(private_bytes("Private_Clean:7\nPrivate_Dirty: 1 MB\n"), Some(8 * 1024));
    }
}
