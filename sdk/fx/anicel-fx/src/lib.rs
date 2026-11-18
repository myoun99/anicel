//! The Anicel fx plugin spec, version 1 — the one crate a plugin is built
//! against, and the one the app's host reads the same frame through.
//!
//! SPDX-License-Identifier: MIT
//! Copyright (c) 2026 PARK GUNWOO — the Anicel fx plugin SDK's LICENSE.
//!
//! A plugin is one source built twice: as a WebAssembly module
//! (`plugin.wasm`), which Anicel runs on every device in a sandbox, and —
//! where its maker wants — as a native library (`.dll`, `.dylib` or `.so`)
//! that a desktop runs instead. It declares its parameters, takes the row's
//! picture (wider by the reach it declares) and gives back a picture; a
//! `layer` parameter hands it another row's picture as well. It says what it
//! can do in its description (`"can"`), so a later host can offer more and
//! an older plugin still runs.
//!
//! A plugin is a type that is an [`Effect`], exported once:
//!
//! ```ignore
//! struct Invert;
//!
//! impl anicel_fx::Effect for Invert {
//!     const DESCRIPTION: &'static str = r#"{"spec":1, … }"#;
//!     fn reach(_: &anicel_fx::Ask<'_>) -> u32 { 0 }
//!     fn render(job: &mut anicel_fx::Job<'_>) -> Result<(), anicel_fx::Failed> {
//!         …
//!     }
//! }
//!
//! anicel_fx::export!(Invert);
//! ```
//!
//! # What a plugin exports
//!
//! The names are the spec ([`names`]); [`export!`] writes all of them.
//!
//! - `anicel_fx_spec() -> u32` — the spec version it was built against,
//!   [`SPEC_VERSION`].
//! - `anicel_fx_describe(out, capacity) -> u32` — writes its description
//!   (UTF-8 JSON, below) into `out` and returns its length in bytes. A
//!   length past `capacity` asks to be called again with that much room;
//!   nothing past `capacity` is written.
//! - `anicel_fx_reach(frame) -> u32` — how many pixels past each edge of its
//!   input the effect reads and draws, for the values in `frame` (its images
//!   are empty here). The host hands the next render an input that much
//!   wider each way.
//! - `anicel_fx_render(frame) -> i32` — writes every pixel of the output
//!   from the input, the values and the layers. 0 is done; anything else is
//!   a failure, and the host draws the row as if the effect were off.
//! - A WebAssembly module also exports its linear memory as `memory` and
//!   `anicel_fx_alloc(size) -> pointer`, which the host calls for the room it
//!   writes a frame into, and keeps. A native library does not: the host's
//!   own memory is the frame's.
//!
//! # The description
//!
//! ```text
//! {"spec":1, "id":"com.example.invert", "name":"Invert",
//!  "vendor":"Example", "version":"1.0.0", "can":["cpu"],
//!  "params":[
//!    {"id":"amount", "kind":"number", "label":"Amount",
//!     "default":100, "min":0, "max":100},
//!    {"id":"map", "kind":"layer", "label":"Map"}]}
//! ```
//!
//! `"kind"` is one of number, angle, color, point, checkbox, menu or layer —
//! the kinds the app's own effects have, keyed, graphed and linked the same
//! way. What each says beside its id and label:
//!
//! | kind | |
//! | --- | --- |
//! | number, angle | `"default"`, `"min"`, `"max"` (an angle in degrees) |
//! | color | `"default":[r, g, b, a]`, each from 0 to 1 |
//! | checkbox | `"default"`: true or false |
//! | menu | `"choices":[{"id":…,"label":…}, …]`, `"default"`: its place |
//! | point, layer | nothing (a point starts at the paper's middle, a layer names no row until one is picked) |
//!
//! An id is letters, digits and `_ . -`. A description that leaves out what
//! its kind says, or says it past its range, is no plugin: the app makes
//! nothing up for it. A key the spec does not name is passed over, so a
//! later spec's hints do not stop an older host. A parameter's place in
//! `"params"` is its place in the frame's values.
//!
//! # The file (`.anifx`)
//!
//! A zip a person opens with the app's Open:
//!
//! | entry | |
//! | --- | --- |
//! | `plugin.wasm` | the module; every file has it |
//! | `native/windows-x64.dll`, `native/windows-arm64.dll` | Windows builds, each where the plugin has one |
//! | `native/macos.dylib` | a Mac build — one file for both chips |
//! | `native/linux-x64.so`, `native/linux-arm64.so` | Linux builds |
//!
//! The app asks `plugin.wasm` for the description, in its sandbox, and
//! shows it to the person before anything is installed; a native build is
//! never opened before they say yes. A device with a native build of its
//! own runs that, and every other device the module.
//!
//! # Versions
//!
//! Spec 1 does not change once published: a host that speaks it runs every
//! spec-1 plugin. What comes later comes as spec 2 — in the frame's
//! `reserved` room, new kinds and keys in the description, new formats a
//! plugin names in `"can"` — and a spec-1 plugin still runs.
//!
//! 🗣️The spec is this crate, not a C header (유저 Q9 · 옛 플러그인 없음,
//! connection-round-checklist 2026-11-07: 「C로만든 옛 플러그인 없어 …
//! 완벽하게 이전」) — a plugin is a Rust type, and what every plugin did by
//! hand the glue does once: it checks the frame's spec and format, and a
//! panic in a native build answers a failure instead of taking the app down
//! with it (a module's traps already did). The frame's bytes stayed as they
//! were: nothing in it is a pointer, so a 32-bit module and a 64-bit library
//! read one layout (native/fx_plugin's lib.rs keeps why).

use std::marker::PhantomData;
use std::mem::offset_of;
use std::panic::{AssertUnwindSafe, catch_unwind};

#[cfg(not(target_endian = "little"))]
compile_error!(
    "the frame is laid little-endian: WebAssembly's memory is, and so is every machine the app \
     runs on"
);

/// The spec version.
pub const SPEC_VERSION: u32 = 1;

/// Premultiplied 8-bit RGBA, rows top to bottom — the only format of spec
/// 1. A new format comes with a new number here and the plugin's `"can"`
/// naming it; a plugin that names none of them is handed this one.
pub const RGBA8_PREMULTIPLIED: u32 = 1;

/// The names a plugin exports.
pub mod names {
    pub const SPEC: &str = "anicel_fx_spec";
    pub const DESCRIBE: &str = "anicel_fx_describe";
    pub const REACH: &str = "anicel_fx_reach";
    pub const RENDER: &str = "anicel_fx_render";
    /// A WebAssembly module's alone, with its [`MEMORY`].
    pub const ALLOC: &str = "anicel_fx_alloc";
    pub const MEMORY: &str = "memory";

    /// What a native library's exports are, as a host calls them.
    pub type Spec = unsafe extern "C" fn() -> u32;
    pub type Describe = unsafe extern "C" fn(*mut u8, u32) -> u32;
    pub type Reach = unsafe extern "C" fn(*const super::Frame) -> u32;
    pub type Render = unsafe extern "C" fn(*mut super::Frame) -> i32;
}

/// One picture: its first pixel lies `pixels` bytes past the frame. Its
/// columns start at canvas x `left` and its rows at canvas y `top`, in the
/// output's pixels — the reach included, so `left` is negative where the
/// input reaches past the paper.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Image {
    pub pixels: u32,
    pub width: u32,
    pub height: u32,
    /// Bytes from one row to the next.
    pub stride: u32,
    pub left: i32,
    pub top: i32,
}

/// One parameter's value at this frame. number, angle (degrees), checkbox
/// (0 or 1) and menu (the choice's place) are `.0[0]`; a point is `.0[0]`,
/// `.0[1]` in canvas pixels; a color is r, g, b, a from 0 to 1; a layer is
/// the place of its picture in the frame's layers, or -1 where it names no
/// row.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Value(pub [f64; 4]);

impl Value {
    /// A number's or an angle's value.
    pub fn number(&self) -> f64 {
        self.0[0]
    }

    /// A color's r, g, b and a.
    pub fn color(&self) -> [f64; 4] {
        self.0
    }

    /// The place a layer's picture has in the frame's layers ([`Layers::get`]),
    /// or `None` where it names no row.
    pub fn layer(&self) -> Option<usize> {
        usize::try_from(self.0[0] as i64).ok()
    }
}

/// What the host hands a plugin, every place in it a byte distance from the
/// frame's own address.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Frame {
    /// The host's spec version.
    pub spec: u32,
    /// [`RGBA8_PREMULTIPLIED`].
    pub format: u32,
    pub input: Image,
    /// The input's size and place.
    pub output: Image,
    pub value_count: u32,
    /// Bytes past the frame to `value_count` [`Value`]s.
    pub values: u32,
    pub layer_count: u32,
    /// Bytes past the frame to `layer_count` [`Image`]s.
    pub layers: u32,
    /// Seconds from the cut's first frame.
    pub time: f64,
    /// Frames per second.
    pub frame_rate: f64,
    /// Output pixels per canvas pixel — below 1 in a draft.
    pub scale: f64,
    pub frame_index: i32,
    /// 0 — room for spec 2 without moving a field.
    pub reserved: u32,
}

// The layout on every target a plugin is built for: a 32-bit module and a
// 64-bit library read the same bytes. Each size is its fields' sum, so no
// type has padding — every byte of one is a field's.
const _: () = {
    assert!(size_of::<Image>() == 24);
    assert!(size_of::<Value>() == 32);
    assert!(offset_of!(Frame, input) == 8);
    assert!(offset_of!(Frame, output) == 32);
    assert!(offset_of!(Frame, value_count) == 56);
    assert!(offset_of!(Frame, layer_count) == 64);
    assert!(offset_of!(Frame, time) == 72);
    assert!(offset_of!(Frame, frame_index) == 96);
    assert!(size_of::<Frame>() == 104);
};

/// The parts of a frame, as a host writes them.
trait Laid: Copy {}
impl Laid for Frame {}
impl Laid for Image {}
impl Laid for Value {}

fn bytes_of<T: Laid>(part: &T) -> &[u8] {
    // SAFETY: a part has no padding (the sizes above), so each of its
    // bytes is a field's, set.
    unsafe { std::slice::from_raw_parts((part as *const T).cast::<u8>(), size_of::<T>()) }
}

impl Frame {
    /// The frame's bytes, as a host lays them.
    pub fn as_bytes(&self) -> &[u8] {
        bytes_of(self)
    }
}

impl Image {
    pub fn as_bytes(&self) -> &[u8] {
        bytes_of(self)
    }
}

impl Value {
    pub fn as_bytes(&self) -> &[u8] {
        bytes_of(self)
    }
}

/// When a frame is asked for.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Moment {
    pub frame_index: i32,
    /// Seconds from the cut's first frame.
    pub time: f64,
    pub frame_rate: f64,
    /// Output pixels per canvas pixel. Values are canvas pixels and
    /// pictures output pixels: multiply a distance by this.
    pub scale: f64,
}

/// What a reach is asked of: the values and the moment, no picture.
pub struct Ask<'a> {
    pub values: &'a [Value],
    pub moment: Moment,
}

/// What a render is asked of.
pub struct Job<'a> {
    /// In the order of the description's `"params"`.
    pub values: &'a [Value],
    pub moment: Moment,
    pub input: Picture<'a>,
    /// The input's size and place, every pixel to be written.
    pub output: PictureMut<'a>,
    pub layers: Layers<'a>,
}

/// A picture a plugin reads.
#[derive(Clone, Copy)]
pub struct Picture<'a> {
    pixels: &'a [u8],
    pub width: u32,
    pub height: u32,
    /// Bytes from one row to the next.
    pub stride: u32,
    /// Where its first column lies on the canvas, in output pixels.
    pub left: i32,
    /// Where its first row lies on the canvas, in output pixels.
    pub top: i32,
}

impl<'a> Picture<'a> {
    /// Row `y`, `width × 4` bytes.
    pub fn row(&self, y: u32) -> &'a [u8] {
        &self.pixels[y as usize * self.stride as usize..][..self.width as usize * 4]
    }

    /// The pixel at column `x` and row `y` of the picture, or `None`
    /// outside it.
    pub fn get(&self, x: i64, y: i64) -> Option<[u8; 4]> {
        let inside = (0..i64::from(self.width)).contains(&x) && (0..i64::from(self.height)).contains(&y);
        inside.then(|| {
            let at = y as usize * self.stride as usize + x as usize * 4;
            self.pixels[at..at + 4].try_into().expect("four bytes")
        })
    }

    /// The pixel at canvas place (`x`, `y`), in output pixels, or `None`
    /// outside the picture.
    pub fn at(&self, x: i32, y: i32) -> Option<[u8; 4]> {
        self.get(i64::from(x) - i64::from(self.left), i64::from(y) - i64::from(self.top))
    }
}

/// The picture a plugin writes.
pub struct PictureMut<'a> {
    pixels: &'a mut [u8],
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub left: i32,
    pub top: i32,
}

impl PictureMut<'_> {
    /// Row `y`, `width × 4` bytes.
    pub fn row_mut(&mut self, y: u32) -> &mut [u8] {
        let width = self.width as usize * 4;
        &mut self.pixels[y as usize * self.stride as usize..][..width]
    }
}

/// The pictures of the frame's layers, by place — a layer parameter's
/// [`Value::layer`].
pub struct Layers<'a> {
    frame: *const u8,
    images: &'a [Image],
    _frame: PhantomData<&'a [u8]>,
}

impl<'a> Layers<'a> {
    pub fn len(&self) -> usize {
        self.images.len()
    }

    pub fn is_empty(&self) -> bool {
        self.images.is_empty()
    }

    /// The picture at `place`, or `None` past the last.
    pub fn get(&self, place: usize) -> Option<Picture<'a>> {
        // SAFETY: the frame's own image, its pixels where it says.
        self.images.get(place).map(|image| unsafe { picture(self.frame, image) })
    }
}

/// The bytes of `image`'s rows, from its first pixel to its last.
fn extent(image: &Image) -> usize {
    match image.height {
        0 => 0,
        height => (height as usize - 1) * image.stride as usize + image.width as usize * 4,
    }
}

/// # Safety
/// `image` is one of the frame at `frame`'s, and the host laid its pixels
/// where it says, apart from the output's.
unsafe fn picture<'a>(frame: *const u8, image: &Image) -> Picture<'a> {
    // SAFETY: the caller's contract.
    let pixels = unsafe { std::slice::from_raw_parts(frame.add(image.pixels as usize), extent(image)) };
    let Image { width, height, stride, left, top, .. } = *image;
    Picture { pixels, width, height, stride, left, top }
}

/// A plugin's failure: the host draws the row as if the effect were off.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Failed;

/// An effect a plugin exports ([`export!`]).
pub trait Effect {
    /// What it says of itself — UTF-8 JSON, as the crate's head says.
    const DESCRIPTION: &'static str;

    /// How many pixels past each edge of its input it reads and draws, for
    /// these values.
    fn reach(ask: &Ask<'_>) -> u32;

    /// Writes every pixel of `job.output`.
    fn render(job: &mut Job<'_>) -> Result<(), Failed>;
}

/// Exports `$effect` as the plugin: the four functions the spec names and,
/// built as WebAssembly, the room the host writes a frame into.
#[macro_export]
macro_rules! export {
    ($effect:ty) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn anicel_fx_spec() -> u32 {
            $crate::SPEC_VERSION
        }

        /// # Safety
        /// `out` holds `capacity` bytes.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn anicel_fx_describe(out: *mut u8, capacity: u32) -> u32 {
            // SAFETY: the caller's contract.
            unsafe { $crate::glue::describe::<$effect>(out, capacity) }
        }

        /// # Safety
        /// `frame` is a frame the host laid.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn anicel_fx_reach(frame: *const $crate::Frame) -> u32 {
            // SAFETY: the caller's contract.
            unsafe { $crate::glue::reach::<$effect>(frame) }
        }

        /// # Safety
        /// `frame` is a frame the host laid.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn anicel_fx_render(frame: *mut $crate::Frame) -> i32 {
            // SAFETY: the caller's contract.
            unsafe { $crate::glue::render::<$effect>(frame) }
        }

        #[cfg(target_family = "wasm")]
        #[unsafe(no_mangle)]
        pub extern "C" fn anicel_fx_alloc(size: u32) -> *mut u8 {
            $crate::glue::alloc(size)
        }

        // Each export as the spec types it.
        const _: [$crate::names::Spec; 1] = [anicel_fx_spec];
        const _: [$crate::names::Describe; 1] = [anicel_fx_describe];
        const _: [$crate::names::Reach; 1] = [anicel_fx_reach];
        const _: [$crate::names::Render; 1] = [anicel_fx_render];
    };
}

/// What [`export!`]'s functions call — public for the macro, not a plugin's
/// to call.
#[doc(hidden)]
pub mod glue {
    use super::*;

    /// What render answers for a failure.
    const FAILED: i32 = 1;

    /// # Safety
    /// `out` is null or holds `capacity` bytes.
    pub unsafe fn describe<E: Effect>(out: *mut u8, capacity: u32) -> u32 {
        let description = E::DESCRIPTION.as_bytes();
        if !out.is_null() {
            let written = description.len().min(capacity as usize);
            // SAFETY: the caller's contract; `written` is at most `capacity`.
            unsafe { std::ptr::copy_nonoverlapping(description.as_ptr(), out, written) };
        }
        description.len() as u32
    }

    /// The frame at `frame`, where it speaks this spec and format.
    ///
    /// # Safety
    /// `frame` is null or a frame the host laid.
    unsafe fn spoken(frame: *const Frame) -> Option<Frame> {
        // SAFETY: the caller's contract.
        let head = unsafe { frame.as_ref() }.copied()?;
        (head.spec == SPEC_VERSION && head.format == RGBA8_PREMULTIPLIED).then_some(head)
    }

    /// # Safety
    /// `frame` is the frame `head` was read from, its values where it says.
    unsafe fn values<'a>(frame: *const u8, head: &Frame) -> &'a [Value] {
        let count = head.value_count as usize;
        // SAFETY: the caller's contract; the host lays the values on 16
        // bytes, past the frame.
        unsafe { std::slice::from_raw_parts(frame.add(head.values as usize).cast(), count) }
    }

    fn moment(head: &Frame) -> Moment {
        let Frame { frame_index, time, frame_rate, scale, .. } = *head;
        Moment { frame_index, time, frame_rate, scale }
    }

    /// # Safety
    /// `frame` is null or a frame the host laid.
    pub unsafe fn reach<E: Effect>(frame: *const Frame) -> u32 {
        // SAFETY: the caller's contract.
        let Some(head) = (unsafe { spoken(frame) }) else {
            return 0;
        };
        // SAFETY: the frame `head` was read from.
        let values = unsafe { values(frame.cast(), &head) };
        let ask = Ask { values, moment: moment(&head) };
        catch_unwind(AssertUnwindSafe(|| E::reach(&ask))).unwrap_or(0)
    }

    /// # Safety
    /// `frame` is null or a frame the host laid, every part where it says
    /// and none on another.
    pub unsafe fn render<E: Effect>(frame: *mut Frame) -> i32 {
        // SAFETY: the caller's contract.
        let Some(head) = (unsafe { spoken(frame) }) else {
            return FAILED;
        };
        let at = frame.cast::<u8>();
        let output = head.output;
        // SAFETY: the frame's own parts, apart from each other.
        let mut job = unsafe {
            Job {
                values: values(at, &head),
                moment: moment(&head),
                input: picture(at, &head.input),
                output: PictureMut {
                    pixels: std::slice::from_raw_parts_mut(
                        at.add(output.pixels as usize),
                        extent(&output),
                    ),
                    width: output.width,
                    height: output.height,
                    stride: output.stride,
                    left: output.left,
                    top: output.top,
                },
                layers: Layers {
                    frame: at,
                    images: std::slice::from_raw_parts(
                        at.add(head.layers as usize).cast(),
                        head.layer_count as usize,
                    ),
                    _frame: PhantomData,
                },
            }
        };
        match catch_unwind(AssertUnwindSafe(|| E::render(&mut job))) {
            Ok(Ok(())) => 0,
            Ok(Err(Failed)) | Err(_) => FAILED,
        }
    }

    /// Room for `size` bytes on 16, kept by the host; null where there is
    /// none.
    pub fn alloc(size: u32) -> *mut u8 {
        match std::alloc::Layout::from_size_align(size.max(1) as usize, 16) {
            // SAFETY: a layout of at least one byte.
            Ok(layout) => unsafe { std::alloc::alloc(layout) },
            Err(_) => std::ptr::null_mut(),
        }
    }
}
