//! The host held to the C host it replaces (qa_fx_plugin.c, through the
//! engine — native/oracle) and to answers worked out here, so two hosts
//! that agree on a wrong answer still fail: the C's own test's cases
//! (qa_fx_plugin_test.c) on the sample plugin, the SDK's example, and what a
//! host must refuse.
//!
//! The plugins are this crate's examples, built against the spec crate as a
//! maker builds one ([`sample`]) and opened by both hosts — the C host
//! reading a Rust plugin is the spec crate held to the header it replaces.
//! ⏳Until the connection round the C builds of the sample and the example
//! (CMakeLists.txt, beside the engine) answer beside them, the key each
//! Rust plugin is held to; that round deletes them with the C host.

mod wasm;

use std::ffi::{CStr, CString, c_char, c_void};
use std::path::Path;

use super::*;

type OpenNative = unsafe extern "C" fn(*const c_char, *mut c_char, i32) -> *mut c_void;
type OpenWasm = unsafe extern "C" fn(*const u8, i64, *mut c_char, i32) -> *mut c_void;
type Describe = unsafe extern "C" fn(*mut c_void, *mut c_char, i32) -> i32;
type Reach = unsafe extern "C" fn(*mut c_void, *const f64, i32, i32, f64, f64, f64) -> i32;
type Render = unsafe extern "C" fn(*mut c_void, *const RenderJob) -> i32;
type Close = unsafe extern "C" fn(*mut c_void);
type Interprets = unsafe extern "C" fn(*mut c_void) -> i32;
type Size = unsafe extern "C" fn() -> i32;

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

/// The C host's, through the engine.
fn c() -> Host {
    // SAFETY: each as qa_fx_plugin.c declares it.
    unsafe {
        Host {
            name: "C",
            open_native: oracle::export("qa_fx_plugin_open_native"),
            open_wasm: oracle::export("qa_fx_plugin_open_wasm"),
            describe: oracle::export("qa_fx_plugin_describe"),
            reach: oracle::export("qa_fx_plugin_reach"),
            render: oracle::export("qa_fx_plugin_render"),
            close: oracle::export("qa_fx_plugin_close"),
            interprets: oracle::export("qa_fx_plugin_interprets"),
        }
    }
}

fn hosts() -> [Host; 2] {
    [c(), RUST]
}

fn c_path(path: &Path) -> CString {
    CString::new(path.to_str().expect("a UTF-8 path")).expect("a path with no NUL")
}

/// One of this crate's examples (Cargo.toml: the sample, the two builds of
/// it a host refuses, and the SDK's example), which `cargo test` builds
/// beside the folder of the test it runs.
fn sample(name: &str) -> CString {
    let test = std::env::current_exe().expect("the test's own path");
    let profile = test.parent().and_then(Path::parent).expect("target/<profile>/deps");
    let path = profile.join("examples").join(libloading::library_filename(name));
    assert!(path.is_file(), "no {} — `cargo test` builds it, `--lib` alone does not", path.display());
    c_path(&path)
}

/// A C build of a plugin the engine's build made beside the engine
/// (CMakeLists.txt), the key its Rust build is held to.
fn c_built(name: &str) -> CString {
    c_path(&oracle::beside(name))
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

/// The sample asked every question of the C test, on each host — and its C
/// build on the C host, the key it is held to.
#[test]
fn the_sample_answers_as_the_c_host_does_and_as_worked_out_here() {
    let rust = sample("qa_fx_plugin_sample");
    let c_build = c_built("qa_fx_plugin_sample");
    let asked = [(c(), &c_build), (c(), &rust), (RUST, &rust)];
    let descriptions = asked.map(|(host, path)| {
        let plugin = Opened::new(host, path);
        // SAFETY: an open plugin.
        assert_eq!(unsafe { (host.interprets)(plugin.handle) }, 0, "{}: compiled", host.name);
        ask(&plugin)
    });
    assert_eq!(descriptions[0], descriptions[1]);
    assert_eq!(descriptions[1], descriptions[2]);
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
/// and scales, on each host: the answers of its C build on the C host, the
/// key it is held to, byte for byte.
/// ⏳That key goes with the C at the connection round; the example then
/// needs answers worked out here, as the Dart pin has them
/// (an_fx_plugin_answers_through_the_engine's `shadowed`).
#[test]
fn the_sdk_example_answers_as_the_c_host_does() {
    let (width, height) = (13, 9);
    let input = hashed(width, height);
    let cases = [
        ([4.0, 2.0], [0.0, 0.0, 0.0, 0.75], 1.0),
        ([-3.0, 5.0], [1.0, 0.25, 0.5, 1.0], 1.0),
        ([7.5, -2.5], [0.2, 0.9, 0.4, 0.5], 0.5),
        ([0.0, 0.0], [1.0, 1.0, 1.0, 0.0], 2.0),
    ];
    let rust = sample("qa_fx_sdk_example");
    let c_build = c_built("qa_fx_sdk_example");
    let asked = [(c(), &c_build, "C on C"), (c(), &rust, "Rust on C"), (RUST, &rust, "Rust")];
    let answers = asked.map(|(host, path, who)| {
        let plugin = Opened::new(host, path);
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
        (who, answers)
    });
    let (_, key) = &answers[0];
    for (who, answer) in &answers[1..] {
        assert_eq!(key.len(), answer.len(), "{who}");
        if let Some(at) = (0..key.len()).find(|&at| key[at] != answer[at]) {
            panic!("{who} parts from the C at byte {at} of {}", key.len());
        }
    }
}

/// A job with no values and no layers, their pointers null, is taken as the
/// C host takes it. The sample reads its first value anyway; with none
/// there its slice is not read past — it panics, and the spec crate answers
/// that as the plugin's failure, on both hosts alike, the output untouched.
#[test]
fn a_job_with_no_values_and_no_layers_is_taken_as_the_c_host_takes_it() {
    let input = input();
    let path = sample("qa_fx_plugin_sample");
    let answers = hosts().map(|host| {
        let plugin = Opened::new(host, &path);
        let mut out = vec![0xEE; IN_H * OUT_STRIDE];
        let job = RenderJob {
            values: std::ptr::null(),
            value_count: 0,
            layers: std::ptr::null(),
            layer_count: 0,
            ..job(&input, &mut out, &[], &[])
        };
        (plugin.render(&job), out)
    });
    assert_eq!(answers[0].0, FAILED, "the C host takes it, and the plugin fails");
    assert_eq!(answers[0], answers[1]);
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
/// none: refused in the C host's words, cut to the room as it cut them.
#[test]
fn the_host_refuses_what_the_c_host_refuses_in_its_words() {
    let paths = [
        None,
        Some(CString::new("no/such/plugin.dll").expect("a path")),
        Some(sample("qa_fx_plugin_sample_spec2")),
        Some(sample("qa_fx_plugin_sample_no_render")),
    ];
    for path in &paths {
        let path = path.as_ref().map_or(std::ptr::null(), |path| path.as_ptr());
        for capacity in [64, 5, 1, 0] {
            let words = hosts().map(|host| {
                let mut error = [0x7f as c_char; 64];
                // SAFETY: a path or none, and a room of at least `capacity`.
                let handle = unsafe { (host.open_native)(path, error.as_mut_ptr(), capacity) };
                assert!(handle.is_null(), "{} opened it", host.name);
                error
            });
            assert_eq!(words[0], words[1], "a room of {capacity}");
            assert_eq!(words[0][0] == 0x7f, capacity == 0, "LIVENESS — the room is written");
        }
    }
    let garbage = [1u8, 2, 3, 4, 5, 6, 7, 8];
    for host in hosts() {
        let mut error = [0 as c_char; 256];
        // SAFETY: eight bytes, and a room of 256.
        let handle =
            unsafe { (host.open_wasm)(garbage.as_ptr(), 8, error.as_mut_ptr(), 256) };
        let refused = handle.is_null() && !said(&error).is_empty();
        assert!(refused, "{}: bytes that are no module", host.name);
    }
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
    for host in hosts() {
        let plugin = Opened::new(host, &path);
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
        let who = host.name;
        for (case, spoil) in cases {
            let mut job = good;
            spoil(&mut job);
            assert_eq!(plugin.render(&job), BAD_JOB, "{who}: {case}");
        }
        let layers = [(&[no_width][..], "a layer with no width"), (&bigs[..], "past 4 GB")];
        for (layers, case) in layers {
            let count = layers.len() as i32;
            let job = RenderJob { layers: layers.as_ptr(), layer_count: count, ..good };
            assert_eq!(plugin.render(&job), BAD_JOB, "{who}: {case}");
        }
        assert_eq!(plugin.render(std::ptr::null()), BAD_JOB, "{who}: no job");
        // SAFETY: no plugin, a job that holds what it says.
        assert_eq!(unsafe { (host.render)(std::ptr::null_mut(), &good) }, BAD_JOB, "{who}");
        assert!(out.iter().all(|&byte| byte == 0xEE), "{who}: the output was written");

        let mut room = [0 as c_char; 8];
        // SAFETY: no plugin; no room; a room said to be none.
        unsafe {
            assert_eq!((host.describe)(std::ptr::null_mut(), room.as_mut_ptr(), 8), BAD_JOB);
            assert_eq!((host.describe)(plugin.handle, std::ptr::null_mut(), 8), BAD_JOB);
            assert_eq!((host.describe)(plugin.handle, room.as_mut_ptr(), 0), BAD_JOB);
        }
        let reach = |handle, values: *const f64, count| {
            // SAFETY: what each case says it holds.
            unsafe { (host.reach)(handle, values, count, 0, 0.0, 24.0, 1.0) }
        };
        assert_eq!(reach(std::ptr::null_mut(), values.as_ptr(), 2), BAD_JOB, "{who}: no plugin");
        assert_eq!(reach(plugin.handle, values.as_ptr(), -1), BAD_JOB, "{who}: below none");
        assert_eq!(reach(plugin.handle, std::ptr::null(), 1), BAD_JOB, "{who}: no pointer");
    }
}

/// The job and the picture are the C host's size, which the Dart structs
/// that mirror them are held to.
#[test]
fn the_job_is_laid_out_as_the_c_host_lays_it() {
    // SAFETY: as qa_fx_plugin.c declares them.
    let (job, picture) = unsafe {
        (
            oracle::export::<Size>("qa_fx_render_job_sizeof")(),
            oracle::export::<Size>("qa_fx_picture_sizeof")(),
        )
    };
    assert_eq!((qa_fx_render_job_sizeof(), qa_fx_picture_sizeof()), (job, picture));
}
