//! The host's WebAssembly side held to the C host's on the C test's modules
//! (qa_fx_plugin_test.c): the sample's twin, written from its C line for
//! line, and the modules a host must start, clear, keep in their memory and
//! refuse — on the C host, on this one, and on this one interpreting as an
//! iPad's does, on every machine (the C test's second build,
//! qa_fx_plugin_interpreted_test).

use super::*;
use crate::wasm::Wasm;

/// This host with its engine interpreting.
///
/// # Safety
/// `bytes` holds `length` bytes; `error` holds `capacity` bytes.
unsafe extern "C" fn open_interpreted(
    bytes: *const u8,
    length: i64,
    error: *mut c_char,
    capacity: i32,
) -> *mut c_void {
    // SAFETY: the caller's contract.
    let bytes = unsafe { std::slice::from_raw_parts(bytes, length as usize) };
    // SAFETY: the caller's contract.
    unsafe { handle(Wasm::open(bytes, true).map(Plugin::Wasm), error, capacity) }
}

const INTERPRETED: Host = Host { name: "Rust interpreted", open_wasm: open_interpreted, ..RUST };

fn wasm_hosts() -> [Host; 3] {
    [c(), RUST, INTERPRETED]
}

/// `text` opened on `host`: the plugin, or why there is none.
fn open(host: Host, text: &str) -> Result<Opened, String> {
    let bytes = wat::parse_str(text).expect("WebAssembly text");
    let mut error = [0 as c_char; 512];
    let length = bytes.len() as i64;
    // SAFETY: the module's bytes, and an error room of 512.
    let handle = unsafe { (host.open_wasm)(bytes.as_ptr(), length, error.as_mut_ptr(), 512) };
    if handle.is_null() { Err(said(&error)) } else { Ok(Opened { host, handle }) }
}

fn opened(host: Host, text: &str) -> Opened {
    open(host, text).unwrap_or_else(|why| panic!("{}: {why}", host.name))
}

/// A module of one page whose five functions' bodies are these, after
/// `before` — what the C test writes out whole for each module it opens.
fn module(before: &str, [spec, alloc, describe, reach, render]: [&str; 5]) -> String {
    format!(
        r#"(module {before} (memory (export "memory") 1)
 (func (export "anicel_fx_spec") (result i32) {spec})
 (func (export "anicel_fx_alloc") (param i32) (result i32) {alloc})
 (func (export "anicel_fx_describe") (param i32 i32) (result i32) {describe})
 (func (export "anicel_fx_reach") (param i32) (result i32) {reach})
 (func (export "anicel_fx_render") (param i32) (result i32) {render}))"#
    )
}

/// A plugin that answers 0 to everything, its room at 1024.
const QUIET: [&str; 5] =
    ["i32.const 1", "i32.const 1024", "i32.const 0", "i32.const 0", "i32.const 0"];

/// The sample's C as WebAssembly text, one line of the C per few here:
/// DESCRIPTION is its description, escaped, and LENGTH its length. At most
/// two pages: a host that took new room for each render would run out of it
/// long before the 400 renders asked of it. Far below zero it traps, as a
/// broken module would.
const TWIN: &str = r#"(module
 (memory (export "memory") 1 2)
 (global $bump (mut i32) (i32.const 4096))
 (data (i32.const 64) "DESCRIPTION")
 (func (export "anicel_fx_spec") (result i32) (i32.const 1))
 (func (export "anicel_fx_alloc") (param $size i32) (result i32)
  (local $at i32) (local $end i32)
  (local.set $at (global.get $bump))
  (local.set $end (i32.and (i32.add (i32.add (local.get $at)
   (local.get $size)) (i32.const 15)) (i32.const -16)))
  (block $ok (loop $grow
   (br_if $ok (i32.le_u (local.get $end)
    (i32.mul (memory.size) (i32.const 65536))))
   (if (i32.eq (memory.grow (i32.const 1)) (i32.const -1))
    (then (return (i32.const 0))))
   (br $grow)))
  (global.set $bump (local.get $end))
  (local.get $at))
 (func (export "anicel_fx_describe") (param $out i32) (param $cap i32)
  (result i32)
  (memory.copy (local.get $out) (i32.const 64)
   (select (i32.const LENGTH) (local.get $cap)
    (i32.lt_u (i32.const LENGTH) (local.get $cap))))
  (i32.const LENGTH))
 (func $speaks (param $f i32) (result i32)
  (i32.and (i32.eq (i32.load (local.get $f)) (i32.const 1))
   (i32.eq (i32.load offset=4 (local.get $f)) (i32.const 1))))
 (func (export "anicel_fx_reach") (param $f i32) (result i32)
  (if (i32.eqz (call $speaks (local.get $f)))
   (then (return (i32.const 0))))
  (i32.add (i32.add
   (i32.trunc_sat_f64_u (f64.mul (f64.div (f64.load (i32.add
    (local.get $f) (i32.load offset=60 (local.get $f))))
    (f64.const 10)) (f64.load offset=88 (local.get $f))))
   (i32.load offset=96 (local.get $f)))
   (i32.trunc_sat_f64_u (f64.add (f64.mul
    (f64.load offset=72 (local.get $f))
    (f64.load offset=80 (local.get $f))) (f64.const 0.5)))))
 (func $map_allows (param $f i32) (param $map i32) (param $x i32)
  (param $y i32) (result i32) (local $mx i32) (local $my i32)
  (if (i32.eqz (local.get $map)) (then (return (i32.const 1))))
  (local.set $mx (i32.sub (local.get $x)
   (i32.load offset=16 (local.get $map))))
  (local.set $my (i32.sub (local.get $y)
   (i32.load offset=20 (local.get $map))))
  (if (i32.or (i32.or (i32.lt_s (local.get $mx) (i32.const 0))
               (i32.lt_s (local.get $my) (i32.const 0)))
       (i32.or (i32.ge_s (local.get $mx)
                (i32.load offset=4 (local.get $map)))
               (i32.ge_s (local.get $my)
                (i32.load offset=8 (local.get $map)))))
   (then (return (i32.const 0))))
  (i32.gt_u (i32.load8_u offset=3 (i32.add (i32.add (local.get $f)
    (i32.load (local.get $map))) (i32.add (i32.mul (local.get $my)
    (i32.load offset=12 (local.get $map))) (i32.shl (local.get $mx)
    (i32.const 2))))) (i32.const 127)))
 (func (export "anicel_fx_render") (param $f i32) (result i32)
  (local $vals i32) (local $amount f64) (local $mapat i32)
  (local $map i32) (local $w i32) (local $h i32) (local $x i32)
  (local $y i32) (local $p i32) (local $q i32) (local $inv i32)
  (local $a i32) (local $c i32)
  (local.set $vals (i32.add (local.get $f)
   (i32.load offset=60 (local.get $f))))
  (if (i32.eqz (call $speaks (local.get $f)))
   (then (return (i32.const 2))))
  (local.set $amount (f64.load (local.get $vals)))
  (if (f64.lt (local.get $amount) (f64.const -100)) (then unreachable))
  (if (f64.lt (local.get $amount) (f64.const 0))
   (then (return (i32.const 1))))
  (local.set $mapat (i32.trunc_sat_f64_s
   (f64.load offset=32 (local.get $vals))))
  (if (i32.and (i32.ge_s (local.get $mapat) (i32.const 0))
   (i32.lt_u (local.get $mapat) (i32.load offset=64 (local.get $f))))
   (then (local.set $map (i32.add (i32.add (local.get $f)
    (i32.load offset=68 (local.get $f)))
    (i32.mul (local.get $mapat) (i32.const 24))))))
  (local.set $w (i32.load offset=12 (local.get $f)))
  (local.set $h (i32.load offset=16 (local.get $f)))
  (block $ydone (loop $yl
   (br_if $ydone (i32.ge_u (local.get $y) (local.get $h)))
   (local.set $x (i32.const 0))
   (block $xdone (loop $xl
    (br_if $xdone (i32.ge_u (local.get $x) (local.get $w)))
    (local.set $p (i32.add (i32.add (local.get $f)
     (i32.load offset=8 (local.get $f))) (i32.add (i32.mul
     (local.get $y) (i32.load offset=20 (local.get $f)))
     (i32.shl (local.get $x) (i32.const 2)))))
    (local.set $q (i32.add (i32.add (local.get $f)
     (i32.load offset=32 (local.get $f))) (i32.add (i32.mul
     (local.get $y) (i32.load offset=44 (local.get $f)))
     (i32.shl (local.get $x) (i32.const 2)))))
    (local.set $inv (i32.and (f64.ge (local.get $amount)
     (f64.const 50)) (call $map_allows (local.get $f) (local.get $map)
     (i32.add (i32.load offset=24 (local.get $f)) (local.get $x))
     (i32.add (i32.load offset=28 (local.get $f)) (local.get $y)))))
    (local.set $a (i32.load8_u offset=3 (local.get $p)))
    (local.set $c (i32.const 0))
    (block $cdone (loop $cl
     (br_if $cdone (i32.ge_u (local.get $c) (i32.const 3)))
     (i32.store8 (i32.add (local.get $q) (local.get $c))
      (select (i32.sub (local.get $a) (i32.load8_u (i32.add
       (local.get $p) (local.get $c)))) (i32.load8_u (i32.add
       (local.get $p) (local.get $c))) (local.get $inv)))
     (local.set $c (i32.add (local.get $c) (i32.const 1)))
     (br $cl)))
    (i32.store8 offset=3 (local.get $q) (local.get $a))
    (local.set $x (i32.add (local.get $x) (i32.const 1)))
    (br $xl)))
   (local.set $y (i32.add (local.get $y) (i32.const 1)))
   (br $yl)))
  (i32.const 0)))"#;

/// The sample's description, and its twin's text carrying it.
fn twin() -> (String, String) {
    let sample = Opened::new(RUST, "qa_fx_plugin_sample");
    let mut room = [0 as c_char; 512];
    sample.describe(&mut room);
    let description = said(&room);
    let escaped = description.replace('\\', r"\\").replace('"', r#"\""#);
    let text = TWIN.replace("LENGTH", &description.len().to_string());
    let text = text.replace("DESCRIPTION", &escaped);
    (description, text)
}

/// The twin asked every question of the sample, and how its engine runs it;
/// a trap ends the render it is in and not the plugin, and the frame's room
/// in the module is reused, not taken anew each time — asked of a twin
/// asked nothing before, whose room is no bigger than one render's frame.
#[test]
fn the_twin_answers_as_the_sample_does_on_every_host() {
    let (description, text) = twin();
    for host in wasm_hosts() {
        let twin = opened(host, &text);
        let who = host.name;
        assert_eq!(ask(&twin), description, "{who}");
        let interprets = host.name == INTERPRETED.name;
        // SAFETY: an open plugin.
        assert_eq!(unsafe { (host.interprets)(twin.handle) }, i32::from(interprets), "{who}");
        assert_eq!(render(&twin, -200.0, true).0, TRAPPED, "{who}: a trap");
        let after = render(&twin, 80.0, true);
        assert_eq!(after, (OK, expected(80.0, true)), "{who}: a render after a trap");
        let fresh = opened(host, &text);
        for time in 0..400 {
            assert_eq!(render(&fresh, 80.0, true).0, OK, "{who}: render {time}");
        }
    }
}

/// A plugin that writes nothing gives a clear picture, never the last
/// render's: this one copies its input at frame 0 and leaves the output be
/// at any other.
#[test]
fn a_render_that_writes_nothing_gives_a_clear_picture() {
    let render = r#"(if (i32.eqz (i32.load offset=96 (local.get 0))) (then
  (memory.copy
   (i32.add (local.get 0) (i32.load offset=32 (local.get 0)))
   (i32.add (local.get 0) (i32.load offset=8 (local.get 0)))
   (i32.mul (i32.load offset=20 (local.get 0)) (i32.load offset=16 (local.get 0))))))
  i32.const 0"#;
    let alloc = "(local $at i32) (local.set $at (global.get $bump)) \
        (global.set $bump (i32.add (local.get $at) (local.get 0))) (local.get $at)";
    let lazy = module(
        "(global $bump (mut i32) (i32.const 1024))",
        ["i32.const 1", alloc, "i32.const 0", "i32.const 0", render],
    );
    let (input, map) = (input(), map());
    let values = [80.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    let layers = [map_layer(&map)];
    let mut clear = vec![0xEE; IN_H * OUT_STRIDE];
    for row in clear.chunks_mut(OUT_STRIDE) {
        row[..IN_W * 4].fill(0);
    }
    for host in wasm_hosts() {
        let lazy = opened(host, &lazy);
        let at = |frame_index| {
            let mut out = vec![0xEE; IN_H * OUT_STRIDE];
            let job = RenderJob { frame_index, ..job(&input, &mut out, &values, &layers) };
            (lazy.render(&job), out)
        };
        let (answer, copied) = at(0);
        assert_eq!(answer, OK, "{}", host.name);
        assert_ne!(copied, clear, "LIVENESS — {}: frame 0 copies its input", host.name);
        assert_eq!(at(1), (OK, clear.clone()), "{}: a render that wrote nothing", host.name);
    }
}

/// A module that gives room past its own memory, or none, is refused the
/// frame, not written past.
#[test]
fn room_the_module_does_not_have_is_refused() {
    for room in ["i32.const 65500", "i32.const 0"] {
        let astray = module("", ["i32.const 1", room, "i32.const 0", "i32.const 0", "i32.const 0"]);
        for host in wasm_hosts() {
            let astray = opened(host, &astray);
            assert_eq!(astray.reach(&[], 0, 0.0, 1.0), NO_ROOM, "{}: {room}", host.name);
        }
    }
}

/// Room the module gives flush against the end of its memory is taken: the
/// host asks for all it will lay there and all the plugin is told it may
/// write.
#[test]
fn room_up_to_the_end_of_the_module_s_memory_is_taken() {
    let flush = module(
        "",
        [
            QUIET[0],
            "(i32.sub (i32.const 65536) (local.get 0))",
            "(memory.fill (local.get 0) (i32.const 65) (local.get 1)) (local.get 1)",
            "(i32.load offset=96 (local.get 0))",
            QUIET[4],
        ],
    );
    for host in wasm_hosts() {
        let flush = opened(host, &flush);
        let who = host.name;
        let mut room = [0 as c_char; 8];
        assert_eq!(flush.describe(&mut room), 8, "{who}: describe");
        assert_eq!(room, [65; 8], "{who}: described");
        assert_eq!(flush.reach(&[], 9, 0.0, 1.0), 9, "{who}: reach");
        assert_eq!(render(&flush, 80.0, true).0, OK, "{who}: render");
    }
}

/// A trap in any question answers it as one, and a render's non-zero as a
/// failure.
#[test]
fn a_module_s_traps_and_failures_answer_as_such() {
    let broken = module("", [QUIET[0], QUIET[1], "unreachable", "unreachable", "i32.const 7"]);
    for host in wasm_hosts() {
        let broken = opened(host, &broken);
        let who = host.name;
        assert_eq!(broken.describe(&mut [0; 8]), TRAPPED, "{who}: describe");
        assert_eq!(broken.reach(&[], 0, 0.0, 1.0), TRAPPED, "{who}: reach");
        assert_eq!(render(&broken, 80.0, true).0, FAILED, "{who}: render");
    }
}

/// A module built on WASI's libc starts its runtime in `_initialize`: this
/// one names its spec only once started; one whose start traps is refused.
#[test]
fn a_module_is_started_before_it_is_asked() {
    let ready = "(global $ready (mut i32) (i32.const 0)) \
        (func (export \"_initialize\") (global.set $ready (i32.const 1)))";
    let started = module(ready, ["(global.get $ready)", QUIET[1], QUIET[2], QUIET[3], QUIET[4]]);
    let failing = module("(func (export \"_initialize\") unreachable)", QUIET);
    for host in wasm_hosts() {
        opened(host, &started);
        let why = open(host, &failing).err().unwrap_or_else(|| panic!("{} opened", host.name));
        assert!(why.starts_with("_initialize: "), "{}: {why}", host.name);
    }
}

/// WASI is there to link against and reaches nothing: the first folder a
/// host could open to a module is descriptor 3, and there is none (EBADF).
#[test]
fn wasi_is_there_and_reaches_nothing() {
    let import = r#"(import "wasi_snapshot_preview1" "fd_prestat_get"
  (func $prestat (param i32 i32) (result i32)))"#;
    let reach = "(call $prestat (i32.const 3) (i32.const 512))";
    let sandboxed = module(import, [QUIET[0], QUIET[1], QUIET[2], reach, QUIET[4]]);
    for host in wasm_hosts() {
        let sandboxed = opened(host, &sandboxed);
        assert_eq!(sandboxed.reach(&[], 0, 0.0, 1.0), 8, "{}: fd_prestat_get(3)", host.name);
    }
}

/// A module the host cannot run is refused: in the C host's own words where
/// they are the host's, and with its first words where the rest is
/// Wasmtime's.
#[test]
fn a_module_the_host_cannot_run_is_refused_in_the_c_host_s_words() {
    let spec_2 = module("", ["i32.const 2", QUIET[1], QUIET[2], QUIET[3], QUIET[4]]);
    let cases = [
        (r#"(module (memory (export "memory") 1))"#.to_owned(), "the module exports no fx plugin"),
        (spec_2, "the plugin speaks another spec version"),
    ];
    for (text, words) in &cases {
        for host in wasm_hosts() {
            assert_eq!(open(host, text).err().as_deref(), Some(*words), "{}", host.name);
        }
    }
    let absent = wat::parse_str(r#"(module (import "env" "absent" (func)))"#).expect("a module");
    for bytes in [&[1u8, 2, 3, 4, 5, 6, 7, 8][..], &absent] {
        for host in wasm_hosts() {
            let mut error = [0 as c_char; 512];
            let length = bytes.len() as i64;
            // SAFETY: the bytes, and an error room of 512.
            let handle =
                unsafe { (host.open_wasm)(bytes.as_ptr(), length, error.as_mut_ptr(), 512) };
            assert!(handle.is_null(), "{} opened it", host.name);
            let why = said(&error);
            assert!(why.starts_with("the module would not start: "), "{}: {why}", host.name);
        }
    }
    let one = [1u8];
    for host in hosts() {
        for (bytes, length) in [(std::ptr::null(), 8), (one.as_ptr(), 0)] {
            let mut error = [0 as c_char; 64];
            // SAFETY: no bytes or none of them, and an error room of 64.
            let handle = unsafe { (host.open_wasm)(bytes, length, error.as_mut_ptr(), 64) };
            assert!(handle.is_null() && said(&error) == "no module", "{}", host.name);
        }
    }
}
