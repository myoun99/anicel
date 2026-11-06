//! A plugin built as a native library (.dll · .dylib · .so): its frames lie
//! in the host's own memory and its four functions are called on them
//! (🗣️I-132-Q5 「a + 데스크톱은 같은 규격의 네이티브(.dll · .dylib)도」).

use std::ffi::{CStr, c_char};

use libloading::Library;

use crate::frame::{self, Plan, SPEC_VERSION};
use crate::job::{FAILED, Head, Job, NO_ROOM, OK};

type Spec = unsafe extern "C" fn() -> u32;
type Describe = unsafe extern "C" fn(*mut c_char, u32) -> u32;
type Reach = unsafe extern "C" fn(*const u8) -> u32;
type Render = unsafe extern "C" fn(*mut u8) -> i32;

/// An opened native plugin.
pub(crate) struct Native {
    describe: Describe,
    reach: Reach,
    render: Render,
    block: Block,
    /// Where the functions above live: held as long as they are.
    _library: Library,
}

impl Native {
    /// The plugin at `path` (UTF-8), or why there is none, in the words the
    /// app shows.
    pub(crate) fn open(path: &CStr) -> Result<Self, &'static str> {
        let library = load(path).ok_or("the library would not load")?;
        // SAFETY: the spec's names, each with the spec's type.
        let found = unsafe {
            (
                symbol::<Spec>(&library, b"anicel_fx_spec"),
                symbol::<Describe>(&library, b"anicel_fx_describe"),
                symbol::<Reach>(&library, b"anicel_fx_reach"),
                symbol::<Render>(&library, b"anicel_fx_render"),
            )
        };
        let (Some(spec), Some(describe), Some(reach), Some(render)) = found else {
            return Err("the library exports no fx plugin");
        };
        // SAFETY: the spec's anicel_fx_spec takes nothing.
        if unsafe { spec() } != SPEC_VERSION {
            return Err("the plugin speaks another spec version");
        }
        Ok(Self { describe, reach, render, block: Block::default(), _library: library })
    }

    /// The description's length; up to `capacity` bytes of it in `out`.
    ///
    /// # Safety
    /// `out` holds `capacity` bytes.
    pub(crate) unsafe fn describe(&self, out: *mut c_char, capacity: u32) -> i32 {
        // SAFETY: the caller's contract — the plugin writes no further.
        unsafe { (self.describe)(out, capacity) as i32 }
    }

    pub(crate) fn reach(&mut self, head: &Head) -> i32 {
        let Some(block) = self.block.room(frame::reach_size(head)) else {
            return NO_ROOM;
        };
        frame::lay_reach(block, head);
        // SAFETY: a frame the spec lays, in room the host holds.
        unsafe { (self.reach)(block.as_ptr()) as i32 }
    }

    pub(crate) fn render(&mut self, job: &mut Job, plan: &Plan) -> i32 {
        let Some(block) = self.block.room(plan.total) else {
            return NO_ROOM;
        };
        frame::lay(block, plan, job);
        // SAFETY: a frame the spec lays, every place it names in the block.
        if unsafe { (self.render)(block.as_mut_ptr()) } != 0 {
            return FAILED;
        }
        frame::take_output(block, plan, job);
        OK
    }
}

/// The library at `path`, as the C host opened it.
#[cfg(windows)]
fn load(path: &CStr) -> Option<Library> {
    use libloading::os::windows::{LOAD_WITH_ALTERED_SEARCH_PATH, Library};
    let path = String::from_utf8_lossy(path.to_bytes()).into_owned();
    // The plugin's own folder first, for what it brings beside it.
    // ⚠️No test plugin brings a library beside it, so no test tells this
    // flag from none (mutant n06, 2026-11-06).
    // SAFETY: opening a plugin runs its library's start, which the person
    // agreed to when they installed it (anicel_fx_plugin.h, THE FILE).
    let library = unsafe { Library::load_with_flags(path, LOAD_WITH_ALTERED_SEARCH_PATH) };
    library.ok().map(Into::into)
}

/// The library at `path`, as the C host opened it.
#[cfg(unix)]
fn load(path: &CStr) -> Option<Library> {
    use std::os::unix::ffi::OsStrExt;

    use libloading::os::unix::{Library, RTLD_LOCAL, RTLD_NOW};
    let path = std::ffi::OsStr::from_bytes(path.to_bytes());
    // SAFETY: as on Windows, above.
    let library = unsafe { Library::open(Some(path), RTLD_NOW | RTLD_LOCAL) };
    library.ok().map(Into::into)
}

/// `library`'s export `name` as `F`, or `None` where it has none.
///
/// # Safety
/// `F` is the export's type.
unsafe fn symbol<F: Copy>(library: &Library, name: &[u8]) -> Option<F> {
    // SAFETY: the caller's contract.
    unsafe { library.get::<F>(name) }.ok().map(|found| *found)
}

/// Room for frames that only grows, kept from one call to the next; on 16
/// bytes, as the frame's doubles and the plan's parts are.
#[derive(Default)]
struct Block(Vec<Chunk>);

#[derive(Clone, Copy)]
#[repr(C, align(16))]
struct Chunk([u8; 16]);

impl Block {
    /// At least `size` bytes; `None` where there is no memory for them.
    // ⚠️Every size the host asks is on 16 bytes — a plan's total, a reach's
    // frame — so no test tells rounding up from down here (mutant n05,
    // 2026-11-06); up keeps the room from ever coming short of the ask.
    fn room(&mut self, size: usize) -> Option<&mut [u8]> {
        let chunks = size.div_ceil(16);
        if self.0.len() < chunks {
            self.0.try_reserve_exact(chunks - self.0.len()).ok()?;
            self.0.resize(chunks, Chunk([0; 16]));
        }
        let bytes = self.0.len() * 16;
        // SAFETY: a chunk is 16 bytes with no padding, so the chunks are
        // that many bytes, and they are this room's alone while it is lent.
        Some(unsafe { std::slice::from_raw_parts_mut(self.0.as_mut_ptr().cast::<u8>(), bytes) })
    }
}
