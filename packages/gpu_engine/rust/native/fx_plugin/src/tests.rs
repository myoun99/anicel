//! The host held to answers worked out here: the cases of the C host's own
//! test on the sample plugin, the SDK's example, and what a host must
//! refuse. ↩️Until the connection round (connection-round-checklist H,
//! 2026-11-08) this host was held to the C host it replaced, byte for byte,
//! on those plugins' C builds too; what the C answered was pinned here before
//! it went — the refusals' words, the SDK example's answers in the ledger
//! (`fx/sdk-example-answers`).
//!
//! The plugins are this crate's examples, built against the spec crate as a
//! maker builds one ([`sample`]). The SDK's example is built as WebAssembly
//! too, by a crate of its own (native/fx_sdk_example), and its module opened
//! on each WebAssembly host.

mod wasm;

use std::ffi::{CStr, CString, c_char, c_void};
use std::path::{Path, PathBuf};

use super::*;

type OpenNative = unsafe extern "C" fn(*const c_char, *mut c_char, i32) -> *mut c_void;
type OpenWasm = unsafe extern "C" fn(*const u8, i64, *mut c_char, i32) -> *mut c_void;
type Describe = unsafe extern "C" fn(*mut c_void, *mut c_char, i32) -> i32;
type Reach = unsafe extern "C" fn(*mut c_void, *const f64, i32, i32, f64, f64, f64) -> i32;
type Render = unsafe extern "C" fn(*mut c_void, *const RenderJob) -> i32;
type Close = unsafe extern "C" fn(*mut c_void);
type Interprets = unsafe extern "C" fn(*mut c_void) -> i32;

/// One host's exports.
#[derive(Clone, Copy)]
struct Host {
    name: &'static str,
    open_native: OpenNative,
    open_wasm: OpenWasm,
    describe: Describe,
    reach: Reach,
    render: Render,
    close: Close,
    interprets: Interprets,
}

const RUST: Host = Host {
    name: "Rust",
    open_native: qa_fx_plugin_open_native,
    open_wasm: qa_fx_plugin_open_wasm,
    describe: qa_fx_plugin_describe,
    reach: qa_fx_plugin_reach,
    render: qa_fx_plugin_render,
    close: qa_fx_plugin_close,
    interprets: qa_fx_plugin_interprets,
};

fn c_path(path: &Path) -> CString {
    CString::new(path.to_str().expect("a UTF-8 path")).expect("a path with no NUL")
}

/// One of this crate's examples (Cargo.toml: the sample, the two builds of
/// it a host refuses, and the SDK's example), which `cargo test` builds
/// beside the folder of the test it runs. A run given a test's name, or
/// `--lib`, builds no example: a mutant of the SDK example's source passed
/// so, the test opening the build from before it (2026-11-07). And the
/// target folder is shared, so the last build may be another checkout's.
fn sample(name: &str) -> CString {
    let test = std::env::current_exe().expect("the test's own path");
    let profile = test.parent().and_then(Path::parent).expect("target/<profile>/deps");
    let path = profile.join("examples").join(libloading::library_filename(name));
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let own = Path::new(&crate_dir).join("examples").join(format!("{name}.rs"));
    c_path(&current(&path, &own, "`cargo test` given no test's name builds it"))
}

/// `build`, taken only when it is of this checkout's sources as they are
/// now — its own list of them, cargo's `.d` beside it, names `own`, and
/// none changed since — and refused otherwise, saying `how` it is built.
fn current(build: &Path, own: &Path, how: &str) -> PathBuf {
    let changed = |file: &Path| std::fs::metadata(file).and_then(|meta| meta.modified());
    let built = changed(build).unwrap_or_else(|error| refused(build, how, error));
    let listed = std::fs::read_to_string(build.with_extension("d"))
        .unwrap_or_else(|error| refused(build, how, error));
    let sources: Vec<&Path> = match listed.lines().next().and_then(|line| line.split_once(": ")) {
        Some((_, sources)) => sources.split_whitespace().map(Path::new).collect(),
        None => refused(build, how, "no sources listed"),
    };
    let own = own.canonicalize().unwrap_or_else(|error| panic!("{}: {error}", own.display()));
    let same = |source: &Path| source.canonicalize().is_ok_and(|source| source == own);
    if !sources.iter().any(|source| same(source)) {
        refused(build, how, format!("not built from {}", own.display()));
    }
    for source in sources {
        if changed(source).map_or(true, |at| at > built) {
            refused(build, how, format!("{} changed since", source.display()));
        }
    }
    build.to_owned()
}

fn refused(build: &Path, how: &str, why: impl std::fmt::Display) -> ! {
    panic!("{}: {why} — {how}", build.display())
}

/// What an error room holds, up to its NUL.
fn said(room: &[c_char]) -> String {
    let bytes = room.iter().take_while(|&&byte| byte != 0).map(|&byte| byte as u8);
    String::from_utf8(bytes.collect()).expect("UTF-8 words")
}

/// A plugin one host opened, closed when it goes.
struct Opened {
    host: Host,
    handle: *mut c_void,
}

impl Opened {
    fn new(host: Host, path: &CStr) -> Self {
        let mut error = [0 as c_char; 256];
        // SAFETY: a path and an error room of the size said.
        let handle = unsafe { (host.open_native)(path.as_ptr(), error.as_mut_ptr(), 256) };
        assert!(!handle.is_null(), "{}: {path:?} would not open: {}", host.name, said(&error));
        Self { host, handle }
    }

    fn describe(&self, room: &mut [c_char]) -> i32 {
        // SAFETY: the room is as big as said.
        unsafe { (self.host.describe)(self.handle, room.as_mut_ptr(), room.len() as i32) }
    }

    /// The reach for `values` at frame `index`, `frames` into a 24 fps cut,
    /// at `scale`.
    fn reach(&self, values: &[f64], index: i32, frames: f64, scale: f64) -> i32 {
        let count = (values.len() / 4) as i32;
        let time = frames / 24.0;
        // SAFETY: `count` values of four doubles.
        unsafe { (self.host.reach)(self.handle, values.as_ptr(), count, index, time, 24.0, scale) }
    }

    fn render(&self, job: *const RenderJob) -> i32 {
        // SAFETY: each job the tests make holds what its pointers say.
        unsafe { (self.host.render)(self.handle, job) }
    }
}

impl Drop for Opened {
    fn drop(&mut self) {
        // SAFETY: opened by this host, never asked again.
        unsafe { (self.host.close)(self.handle) };
    }
}

// The C test's pictures. The input: 6×4, rows 32 bytes apart (8 past the
// pixels), its first pixel at canvas (−1, −1); premultiplied, no colour
// above its alpha. The output: rows 36 bytes apart. The map: 3×3 at canvas
// (1, 0), alpha a checkerboard.
const IN_W: usize = 6;
const IN_H: usize = 4;
const IN_STRIDE: usize = IN_W * 4 + 8;
const OUT_STRIDE: usize = IN_W * 4 + 12;
const MAP_W: usize = 3;
const MAP_H: usize = 3;
const MAP_STRIDE: usize = MAP_W * 4 + 4;
const IN_AT: (i32, i32) = (-1, -1);
const MAP_AT: (i32, i32) = (1, 0);

fn input() -> Vec<u8> {
    let mut input = vec![0xAB; IN_H * IN_STRIDE];
    for y in 0..IN_H {
        for x in 0..IN_W {
            let pixel = &mut input[y * IN_STRIDE + x * 4..][..4];
            pixel.copy_from_slice(&[x as u8 * 20, y as u8 * 30, 10 + (x + y) as u8, 0]);
            pixel[3] = (150 + x * 15 + y * 5) as u8;
        }
    }
    input
}

fn map() -> Vec<u8> {
    let mut map = vec![0xCD; MAP_H * MAP_STRIDE];
    for y in 0..MAP_H {
        for x in 0..MAP_W {
            let alpha = if (x + y) % 2 == 0 { 255 } else { 0 };
            map[y * MAP_STRIDE + x * 4..][..4].copy_from_slice(&[0, 0, 0, alpha]);
        }
    }
    map
}

/// What the sample's render gives (examples/invert.rs), worked out here
/// on its own: inverted where Amount is at least 50 and the map, read at the
/// same canvas place, has alpha over 127 — everywhere, with no map — and
/// the output's padding untouched.
fn expected(amount: f64, with_map: bool) -> Vec<u8> {
    let (input, map) = (input(), map());
    let mut out = vec![0xEE; IN_H * OUT_STRIDE];
    for y in 0..IN_H {
        for x in 0..IN_W {
            let p = &input[y * IN_STRIDE + x * 4..][..4];
            let (mx, my) = (IN_AT.0 + x as i32 - MAP_AT.0, IN_AT.1 + y as i32 - MAP_AT.1);
            let on_map = (0..MAP_W as i32).contains(&mx) && (0..MAP_H as i32).contains(&my);
            let allows = !with_map
                || on_map && map[my as usize * MAP_STRIDE + mx as usize * 4 + 3] > 127;
            let inverts = amount >= 50.0 && allows;
            let q = &mut out[y * OUT_STRIDE + x * 4..][..4];
            for c in 0..3 {
                q[c] = if inverts { p[3] - p[c] } else { p[c] };
            }
            q[3] = p[3];
        }
    }
    out
}

/// The C test's rows, `stride` apart in `bytes`, with no padding.
fn packed(bytes: &[u8], stride: usize) -> Vec<u8> {
    bytes.chunks(stride).flat_map(|row| &row[..IN_W * 4]).copied().collect()
}

/// A job with nothing in it.
fn empty() -> RenderJob {
    let none = Picture {
        pixels: std::ptr::null(),
        width: 0,
        height: 0,
        stride: 0,
        left: 0,
        top: 0,
    };
    RenderJob {
        input: none,
        output: std::ptr::null_mut(),
        output_stride: 0,
        value_count: 0,
        values: std::ptr::null(),
        layers: std::ptr::null(),
        layer_count: 0,
        frame_index: 0,
        time: 0.0,
        frame_rate: 0.0,
        scale: 0.0,
    }
}

/// The C test's job: its input, `values` and `layers`, into `out`.
fn job(input: &[u8], out: &mut [u8], values: &[f64], layers: &[Picture]) -> RenderJob {
    RenderJob {
        input: Picture {
            pixels: input.as_ptr(),
            width: IN_W as i32,
            height: IN_H as i32,
            stride: IN_STRIDE as i32,
            left: IN_AT.0,
            top: IN_AT.1,
        },
        output: out.as_mut_ptr(),
        output_stride: OUT_STRIDE as i32,
        value_count: (values.len() / 4) as i32,
        values: values.as_ptr(),
        layers: layers.as_ptr(),
        layer_count: layers.len() as i32,
        frame_index: 3,
        time: 3.0 / 24.0,
        frame_rate: 24.0,
        scale: 1.0,
    }
}

fn map_layer(map: &[u8]) -> Picture {
    Picture {
        pixels: map.as_ptr(),
        width: MAP_W as i32,
        height: MAP_H as i32,
        stride: MAP_STRIDE as i32,
        left: MAP_AT.0,
        top: MAP_AT.1,
    }
}

/// The sample's render of the C test's input with `amount` and the map —
/// or no map — into an output whose padding holds 0xEE.
fn render(plugin: &Opened, amount: f64, with_map: bool) -> (i32, Vec<u8>) {
    let (input, map) = (input(), map());
    let mut out = vec![0xEE; IN_H * OUT_STRIDE];
    let values = [amount, 0.0, 0.0, 0.0, if with_map { 0.0 } else { -1.0 }, 0.0, 0.0, 0.0];
    let layers = [map_layer(&map)];
    let job = job(&input, &mut out, &values, &layers);
    (plugin.render(&job), out)
}

/// Every question of the C test, of the sample or its twin, and the
/// description it gave: the description, whole and in a room too small;
/// the reach, which reads the values and every number of the frame; renders
/// with the map placed elsewhere on the canvas, without it, below the
/// plugin's threshold, again on the same room and with rows of no padding;
/// a plugin's failure; and a job with nothing in it.
fn ask(plugin: &Opened) -> String {
    let who = plugin.host.name;
    let mut room = [0 as c_char; 512];
    let length = plugin.describe(&mut room);
    let description = said(&room);
    assert!(description.starts_with(r#"{"spec":1,"id":"app.anicel.test.invert""#), "{who}");
    assert_eq!(length as usize, description.len(), "{who}");
    let mut small = [b'x' as c_char; 9];
    assert_eq!(plugin.describe(&mut small[..8]), length, "{who}: a room too small");
    assert_eq!(said(&small[..8]).as_bytes(), &description.as_bytes()[..8], "{who}");
    assert_eq!(small[8], b'x' as c_char, "{who}: nothing past the room");

    let values = [80.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    assert_eq!(plugin.reach(&values, 3, 3.0, 1.0), 14, "{who}: 80 / 10 · 1 + 3 + 3");
    assert_eq!(plugin.reach(&values, 5, 7.0, 0.5), 16, "{who}: 80 / 10 · 0.5 + 5 + 7");

    for (amount, with_map) in [(80.0, true), (80.0, false), (30.0, true), (80.0, true)] {
        let (answer, out) = render(plugin, amount, with_map);
        assert_eq!(answer, OK, "{who}: amount {amount}, map {with_map}");
        assert_eq!(out, expected(amount, with_map), "{who}: amount {amount}, map {with_map}");
    }
    let (input, map) = (input(), map());
    let packed_input = packed(&input, IN_STRIDE);
    let mut out = vec![0xEE; IN_H * IN_W * 4];
    let layers = [map_layer(&map)];
    let mut job = job(&packed_input, &mut out, &values, &layers);
    (job.input.stride, job.output_stride) = (IN_W as i32 * 4, IN_W as i32 * 4);
    assert_eq!(plugin.render(&job), OK, "{who}: rows with no padding");
    assert_eq!(out, packed(&expected(80.0, true), OUT_STRIDE), "{who}: rows with no padding");

    assert_eq!(render(plugin, -5.0, true).0, FAILED, "{who}: the plugin's failure");
    assert_eq!(plugin.render(&empty()), BAD_JOB, "{who}: a job with nothing in it");
    description
}

/// The sample asked every question of the C test.
#[test]
fn the_sample_answers_as_worked_out_here() {
    let plugin = Opened::new(RUST, &sample("qa_fx_plugin_sample"));
    // SAFETY: an open plugin.
    assert_eq!(unsafe { qa_fx_plugin_interprets(plugin.handle) }, 0, "compiled");
    ask(&plugin);
}

/// A picture of `width` × `height` with 4 bytes of padding a row, hashed
/// and premultiplied — no colour above its alpha.
fn hashed(width: usize, height: usize) -> Vec<u8> {
    let stride = width * 4 + 4;
    (0..height * stride)
        .map(|at| (at as u32).wrapping_mul(0x9E37_79B9).rotate_left(13) >> 24)
        .collect::<Vec<u32>>()
        .chunks(4)
        .flat_map(|four| {
            let alpha = four.get(3).copied().unwrap_or(0);
            four.iter().enumerate().map(move |(c, &byte)| {
                if c == 3 { byte as u8 } else { (byte * alpha / 255) as u8 }
            })
        })
        .collect()
}

/// The SDK's example (sdk/fx/example) — the plugin a maker starts from —
/// asked its description, and its reach and render across offsets, colours
/// and scales: its native build on each host, and its module, the one every
/// device runs, on each WebAssembly host (유저,
/// connection-round-checklist-Q11: 「받고, CI 가 매번 확인」), all byte for
/// byte the answers the ledger pinned — its C build's on the C host, which
/// stand now the connection round has deleted the C
/// (connection-round-checklist A).
#[test]
fn the_sdk_example_answers_as_the_ledger_pinned() {
    let native = Opened::new(RUST, &sample("qa_fx_sdk_example"));
    let module = wasm::sdk_module();
    let mut asked = vec![("Rust".to_owned(), native)];
    asked.extend(wasm::wasm_hosts().map(|host| {
        (format!("the module on {}", host.name), wasm::opened_module(host, &module))
    }));
    let answers: Vec<_> =
        asked.iter().map(|(who, plugin)| (who, sdk_answers(plugin, who))).collect();
    let (native, key) = &answers[0];
    ledger::assert_pinned("fx/sdk-example-answers", key);
    for (who, answer) in &answers[1..] {
        assert_eq!(key.len(), answer.len(), "{who}");
        if let Some(at) = (0..key.len()).find(|&at| key[at] != answer[at]) {
            panic!("{who} parts from the {native} build at byte {at} of {}", key.len());
        }
    }
}

/// What the SDK's example answers: its description and its length, then its
/// reach and render across offsets, colours and scales.
fn sdk_answers(plugin: &Opened, who: &str) -> Vec<u8> {
    let (width, height) = (13, 9);
    let input = hashed(width, height);
    let cases = [
        ([4.0, 2.0], [0.0, 0.0, 0.0, 0.75], 1.0),
        ([-3.0, 5.0], [1.0, 0.25, 0.5, 1.0], 1.0),
        ([7.5, -2.5], [0.2, 0.9, 0.4, 0.5], 0.5),
        ([0.0, 0.0], [1.0, 1.0, 1.0, 0.0], 2.0),
    ];
    let mut room = [0 as c_char; 1024];
    let length = plugin.describe(&mut room);
    let mut answers = said(&room).into_bytes();
    answers.extend(length.to_le_bytes());
    for ([x, y], [r, g, b, a], scale) in cases {
        let values = [x, 0.0, 0.0, 0.0, y, 0.0, 0.0, 0.0, r, g, b, a];
        answers.extend(plugin.reach(&values, 2, 2.0, scale).to_le_bytes());
        let mut out = vec![0xEE; height * (width * 4 + 8)];
        let mut job = job(&input, &mut out, &values, &[]);
        job.input = Picture {
            pixels: input.as_ptr(),
            width: width as i32,
            height: height as i32,
            stride: (width * 4 + 4) as i32,
            left: -2,
            top: 3,
        };
        job.output_stride = (width * 4 + 8) as i32;
        job.scale = scale;
        assert_eq!(plugin.render(&job), OK, "{who}: offset ({x}, {y})");
        assert!(out.iter().any(|&byte| byte != 0xEE), "LIVENESS — {who}: written");
        answers.extend(out);
    }
    answers
}

/// A job with no values and no layers, their pointers null, is taken, as
/// the C host took it. The sample reads its first value anyway; with none
/// there its slice is not read past — it panics, and the spec crate answers
/// that as the plugin's failure, the output untouched.
#[test]
fn a_job_with_no_values_and_no_layers_is_taken() {
    let input = input();
    let plugin = Opened::new(RUST, &sample("qa_fx_plugin_sample"));
    let mut out = vec![0xEE; IN_H * OUT_STRIDE];
    let job = RenderJob {
        values: std::ptr::null(),
        value_count: 0,
        layers: std::ptr::null(),
        layer_count: 0,
        ..job(&input, &mut out, &[], &[])
    };
    assert_eq!(plugin.render(&job), FAILED, "taken, and the plugin fails");
    assert_eq!(out, vec![0xEE; IN_H * OUT_STRIDE], "the output untouched");
}

/// Bytes this thread holds from the heap, so a test sees a host give back
/// what it took — a leak answers like a host that frees.
struct Counting;

thread_local! {
    static HELD: std::cell::Cell<isize> = const { std::cell::Cell::new(0) };
}

fn held() -> isize {
    HELD.with(std::cell::Cell::get)
}

fn count(bytes: isize) {
    let _ = HELD.try_with(|held| held.set(held.get() + bytes));
}

// SAFETY: the system's allocator, counted.
unsafe impl std::alloc::GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: std::alloc::Layout) -> *mut u8 {
        count(layout.size() as isize);
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.alloc(layout) }
    }

    unsafe fn dealloc(&self, at: *mut u8, layout: std::alloc::Layout) {
        count(-(layout.size() as isize));
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.dealloc(at, layout) }
    }
}

#[global_allocator]
static COUNTING: Counting = Counting;

/// A frame of another spec or format is answered — a reach of 0, a
/// failure — before the effect sees it: the spec crate's glue, asked
/// through the sample's own exports with frames laid here, as no host lays
/// them.
#[test]
fn a_frame_the_plugin_does_not_speak_never_reaches_its_effect() {
    use anicel_fx::{Frame, Value, names};

    #[repr(C, align(16))]
    struct Block([u8; 176]);

    let path = sample("qa_fx_plugin_sample");
    // SAFETY: the sample, its exports the spec's.
    let library = unsafe { libloading::Library::new(path.to_str().expect("UTF-8")) }
        .expect("the sample");
    // SAFETY: each export with the spec's type.
    let (reach, render) = unsafe {
        let reach = *library.get::<names::Reach>(names::REACH.as_bytes()).expect("its reach");
        let render = *library.get::<names::Render>(names::RENDER.as_bytes()).expect("its render");
        (reach, render)
    };
    let asked = |spec, format| {
        let frame = Frame {
            spec,
            format,
            value_count: 2,
            values: 112,
            frame_rate: 24.0,
            scale: 1.0,
            frame_index: 3,
            ..Frame::default()
        };
        let mut block = Block([0; 176]);
        block.0[..104].copy_from_slice(frame.as_bytes());
        block.0[112..144].copy_from_slice(Value([80.0, 0.0, 0.0, 0.0]).as_bytes());
        block.0[144..176].copy_from_slice(Value([-1.0, 0.0, 0.0, 0.0]).as_bytes());
        let at = block.0.as_mut_ptr().cast::<Frame>();
        // SAFETY: a frame with its two values, its pictures empty.
        unsafe { (reach(at), render(at)) }
    };
    assert_eq!(asked(1, 1), (11, 0), "LIVENESS — spoken: 80 / 10 + 3, and done");
    assert_eq!(asked(2, 1), (0, 1), "another spec");
    assert_eq!(asked(1, 2), (0, 1), "another format");
}

/// A plugin opened, asked and closed leaves the heap as it found it.
#[test]
fn a_closed_plugin_gives_back_what_the_host_took() {
    let path = sample("qa_fx_plugin_sample");
    let before = held();
    {
        let plugin = Opened::new(RUST, &path);
        assert_eq!(render(&plugin, 80.0, true).0, OK);
        assert!(held() > before, "LIVENESS — the host holds its plugin and room");
    }
    assert_eq!(held(), before);
}

/// A library the host must not open — none at all, one that is not there,
/// one of another spec version, one with no render — and a module that is
/// none: refused in the words the C host chose, cut to the room as it cut
/// them (pinned here from the C host before it went).
#[test]
fn the_host_refuses_what_it_cannot_open_in_its_words() {
    let paths = [
        (None, "no path"),
        (Some(CString::new("no/such/plugin.dll").expect("a path")), "the library would not load"),
        (Some(sample("qa_fx_plugin_sample_spec2")), "the plugin speaks another spec version"),
        (Some(sample("qa_fx_plugin_sample_no_render")), "the library exports no fx plugin"),
    ];
    for (path, words) in &paths {
        let path = path.as_ref().map_or(std::ptr::null(), |path| path.as_ptr());
        for capacity in [64, 5, 1, 0] {
            // The words as far as the room holds them and their NUL, the
            // rest of it untouched; a room of none, untouched.
            let mut cut = [0x7f as c_char; 64];
            if capacity > 0 {
                let said = words.len().min(capacity as usize - 1);
                for (at, &byte) in words.as_bytes()[..said].iter().enumerate() {
                    cut[at] = byte as c_char;
                }
                cut[said] = 0;
            }
            let mut error = [0x7f as c_char; 64];
            // SAFETY: a path or none, and a room of at least `capacity`.
            let handle = unsafe { qa_fx_plugin_open_native(path, error.as_mut_ptr(), capacity) };
            assert!(handle.is_null(), "opened it");
            assert_eq!(error, cut, "{words:?} in a room of {capacity}");
        }
    }
    let garbage = [1u8, 2, 3, 4, 5, 6, 7, 8];
    let mut error = [0 as c_char; 256];
    // SAFETY: eight bytes, and a room of 256.
    let handle = unsafe { qa_fx_plugin_open_wasm(garbage.as_ptr(), 8, error.as_mut_ptr(), 256) };
    assert!(handle.is_null() && !said(&error).is_empty(), "bytes that are no module");
}

/// A job the host cannot take, and questions it cannot answer, refused
/// before the plugin sees them — the output untouched.
#[test]
fn what_the_host_cannot_take_is_refused_before_the_plugin_sees_it() {
    let (input, map) = (input(), map());
    let values = [80.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    // 1100 layers of 4 MiB, one picture under them all, lay past 4 GB.
    let big = vec![0u8; 1024 * 1024 * 4];
    let big_layer = Picture {
        pixels: big.as_ptr(),
        width: 1024,
        height: 1024,
        stride: 4096,
        left: 0,
        top: 0,
    };
    let bigs = vec![big_layer; 1100];
    let path = sample("qa_fx_plugin_sample");
    let no_width = Picture { width: 0, ..map_layer(&map) };
    let plugin = Opened::new(RUST, &path);
    let mut out = vec![0xEE; IN_H * OUT_STRIDE];
    let good = job(&input, &mut out, &values, &[]);
    let cases: [(&str, fn(&mut RenderJob)); 10] = [
        ("no pixels", |job| job.input.pixels = std::ptr::null()),
        ("no width", |job| job.input.width = 0),
        ("a height below none", |job| job.input.height = -1),
        ("a stride short of a row", |job| job.input.stride = IN_W as i32 * 4 - 1),
        ("no output", |job| job.output = std::ptr::null_mut()),
        ("an output short of a row", |job| job.output_stride = IN_W as i32 * 4 - 1),
        ("values below none", |job| job.value_count = -1),
        ("values with no pointer", |job| job.values = std::ptr::null()),
        ("layers below none", |job| job.layer_count = -1),
        ("layers with no pointer", |job| {
            job.layers = std::ptr::null();
            job.layer_count = 1;
        }),
    ];
    for (case, spoil) in cases {
        let mut job = good;
        spoil(&mut job);
        assert_eq!(plugin.render(&job), BAD_JOB, "{case}");
    }
    let layers = [(&[no_width][..], "a layer with no width"), (&bigs[..], "past 4 GB")];
    for (layers, case) in layers {
        let count = layers.len() as i32;
        let job = RenderJob { layers: layers.as_ptr(), layer_count: count, ..good };
        assert_eq!(plugin.render(&job), BAD_JOB, "{case}");
    }
    assert_eq!(plugin.render(std::ptr::null()), BAD_JOB, "no job");
    // SAFETY: no plugin, a job that holds what it says.
    assert_eq!(unsafe { qa_fx_plugin_render(std::ptr::null_mut(), &good) }, BAD_JOB);
    assert!(out.iter().all(|&byte| byte == 0xEE), "the output was written");

    let mut room = [0 as c_char; 8];
    // SAFETY: no plugin; no room; a room said to be none.
    unsafe {
        assert_eq!(qa_fx_plugin_describe(std::ptr::null_mut(), room.as_mut_ptr(), 8), BAD_JOB);
        assert_eq!(qa_fx_plugin_describe(plugin.handle, std::ptr::null_mut(), 8), BAD_JOB);
        assert_eq!(qa_fx_plugin_describe(plugin.handle, room.as_mut_ptr(), 0), BAD_JOB);
    }
    let reach = |handle, values: *const f64, count| {
        // SAFETY: what each case says it holds.
        unsafe { qa_fx_plugin_reach(handle, values, count, 0, 0.0, 24.0, 1.0) }
    };
    assert_eq!(reach(std::ptr::null_mut(), values.as_ptr(), 2), BAD_JOB, "no plugin");
    assert_eq!(reach(plugin.handle, values.as_ptr(), -1), BAD_JOB, "below none");
    assert_eq!(reach(plugin.handle, std::ptr::null(), 1), BAD_JOB, "no pointer");
}

