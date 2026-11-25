//! Linux and Android — every OS the C's last arm took: the kernel's
//! sysinfo, and the process's own sum of its mappings.

use std::mem::zeroed;

use crate::smaps::{private_by_mapping, private_kilobytes};

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
    let kilobytes: Vec<u64> = rollup.lines().filter_map(private_kilobytes).collect();
    (!kilobytes.is_empty()).then(|| kilobytes.iter().sum::<u64>() * 1024)
}

/// What each mapping of this process holds of [`footprint`]: the private
/// pages of /proc/self/smaps, summed by the mapping's name (card
/// the-first-pen-down-adds-850-mb-on-the-galaxy-tab — a Galaxy Tab's
/// footprint grew 850 MB at the first pen-down and no number of the app's
/// own said whose). 🚨Far dearer than the rollup: the kernel walks every
/// mapping's pages under the mmap lock, so it is read off the UI thread
/// and seldom (`crate::mappings`).
pub(crate) fn mappings() -> Option<Vec<(String, u64)>> {
    let smaps = std::fs::read_to_string("/proc/self/smaps").ok()?;
    Some(private_by_mapping(&smaps))
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
