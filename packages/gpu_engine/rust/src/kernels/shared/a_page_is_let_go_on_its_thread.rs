//! A page's buffer leaves a pool by one door (F-610, 2026-11-19): a
//! buffer let go is the driver's, and the pool's books are kept on the
//! thread its verbs are called on — the UI's, on a memory warning and at
//! every rest that leaves a page with no tile lying on it. So what takes
//! a buffer out of the pages hands it to the pages' thread
//! (`let_go_on_the_pages_thread`), which a test of the door itself tells
//! of (`pool/tests.rs`). Dropped where it was taken instead, a buffer
//! goes as surely and no test of behaviour can tell on which thread — so
//! this one reads the source.

use super::source_scan::sources;

/// The pool's own files.
const POOL: [&str; 2] = ["kernels/pool/mod.rs", "kernels/pool/folded.rs"];

/// A buffer taken out of the pool's pages — the last one, or one swapped
/// for what stands in its place — and a page made ahead called off.
const LEAVES: [&str; 3] = ["self.buffers.pop()", "mem::replace(&mut self.buffers[", ".called_off()"];

/// The door.
const DOOR: &str = "let_go_on_the_pages_thread(";

#[test]
fn a_page_s_buffer_leaves_its_pool_through_the_pages_thread() {
    let (sources, mut found) = (sources(), 0);
    for file in POOL {
        let lines: Vec<&str> = sources[file].lines().collect();
        for (at, line) in lines.iter().enumerate() {
            let code = line.trim_start();
            if code.starts_with("//") || code.starts_with("fn ") || !LEAVES.iter().any(|leaves| code.contains(leaves)) {
                continue;
            }
            found += 1;
            // Handed to the door where it is taken, or on the line after
            // (`Pool::buffer_let_go`).
            let through = code.contains(DOOR) || lines.get(at + 1).is_some_and(|next| next.contains(DOOR));
            assert!(through, "{file}:{}: hand it to {DOOR}…): {code}", at + 1);
        }
    }
    assert_eq!(found, 3, "LIVENESS — the last page popped, a page swapped for the stand-in, the page ahead called off");
}
