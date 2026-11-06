//! A plugin built as WebAssembly, run by Wasmtime in a sandbox: its frames
//! lie in the room the module gave (`anicel_fx_alloc`) in its own linear
//! memory, and its four functions are called on them.
//!
//! 🗣️I-132-Q31 (유저 2026-10-30): Wasmtime 48 LTS — the C host linked its
//! project's prebuilt C library; this host builds it from its crates
//! (native-to-rust-Q3, 유저 2026-11-06: crates.io 에서 받는다).
//! 🗣️fx-plugin-sdk-publish-Q5 (유저 2026-11-04): an iPad makes no machine
//! code as it runs — Apple gives no app the right — so there the engine
//! compiles a module to Pulley, its own interpreter's bytecode, and
//! interprets it: the same engine and this same host, not WebKit's
//! WebAssembly beside them (「웹뷰자체가 사본이란 느낌드니까」), about 10x
//! slower by Wasmtime's docs — 「그 상태에서 최대한 개선하는식으로」. The
//! tests ask it on every machine ([`Wasm::open`]'s `interpret`).

use wasmtime::{Config, Engine, Func, Linker, Memory, Module, Store, Val};
use wasmtime_wasi::WasiCtxBuilder;
use wasmtime_wasi::p1::{self, WasiP1Ctx};

use crate::frame::{self, Plan, SPEC_VERSION};
use crate::job::{FAILED, Head, Job, NO_ROOM, OK, TRAPPED};

/// Whether this device runs a module by interpreting it.
pub(crate) const INTERPRETS: bool = cfg!(target_os = "ios");

/// An opened WebAssembly plugin.
pub(crate) struct Wasm {
    store: Store<WasiP1Ctx>,
    memory: Memory,
    describe: Func,
    reach: Func,
    render: Func,
    alloc: Func,
    /// The room the module gave for frames, where it lies and how big:
    /// grown, never handed back — a module's allocator needs no free for a
    /// block it reuses.
    room: (u32, u32),
}

impl Wasm {
    /// The plugin in `bytes`, compiled to this machine's code or, with
    /// `interpret`, to Pulley's; or why there is none, in the words the app
    /// shows.
    pub(crate) fn open(bytes: &[u8], interpret: bool) -> Result<Self, String> {
        let engine = engine(interpret)?;
        // WASI with no folder, no network and no environment behind it, so
        // a module built against WASI's libc runs and reaches no file
        // (I-132-Q5: 「앱은 샌드박스로 돌려 플러그인이 파일 · 네트워크를 못
        // 건드린다」).
        // 🔬Its clock still reads (a probe built by WASI SDK 34, 2026-11-04):
        // the README tells a render to take frame->time instead.
        let mut store = Store::new(&engine, WasiCtxBuilder::new().build_p1());
        let mut linker = Linker::new(&engine);
        let not_started = |error| said("the module would not start", error);
        p1::add_to_linker_sync(&mut linker, |wasi| wasi).map_err(not_started)?;
        let module = Module::new(&engine, bytes).map_err(not_started)?;
        let instance = linker.instantiate(&mut store, &module).map_err(not_started)?;
        // A reactor module (WASI's libc) starts its runtime here.
        if let Some(start) = instance.get_func(&mut store, "_initialize") {
            start.call(&mut store, &[], &mut []).map_err(|error| said("_initialize", error))?;
        }
        let memory = instance.get_memory(&mut store, "memory");
        let mut func = |name| instance.get_func(&mut store, name);
        let found = (
            func("anicel_fx_spec"),
            func("anicel_fx_describe"),
            func("anicel_fx_reach"),
            func("anicel_fx_render"),
            func("anicel_fx_alloc"),
            memory,
        );
        let (Some(spec), Some(describe), Some(reach), Some(render), Some(alloc), Some(memory)) =
            found
        else {
            return Err("the module exports no fx plugin".into());
        };
        let mut wasm = Self { store, memory, describe, reach, render, alloc, room: (0, 0) };
        match wasm.call(spec, &[]) {
            Some(version) if version as u32 == SPEC_VERSION => Ok(wasm),
            _ => Err("the plugin speaks another spec version".into()),
        }
    }

    pub(crate) fn interprets(&self) -> bool {
        self.store.engine().is_pulley()
    }

    /// The description's length; up to `out`'s length of it in `out`.
    pub(crate) fn describe(&mut self, out: &mut [u8]) -> i32 {
        let capacity = out.len() as u32;
        let Some(at) = self.room(capacity) else {
            return NO_ROOM;
        };
        let Some(length) = self.call(self.describe, &[at as i32, capacity as i32]) else {
            return TRAPPED;
        };
        let written = length.clamp(0, capacity as i32) as usize;
        out[..written].copy_from_slice(&self.memory.data(&self.store)[at as usize..][..written]);
        length
    }

    pub(crate) fn reach(&mut self, head: &Head) -> i32 {
        let size = frame::reach_size(head);
        let Some(at) = u32::try_from(size).ok().and_then(|size| self.room(size)) else {
            return NO_ROOM;
        };
        frame::lay_reach(&mut self.memory.data_mut(&mut self.store)[at as usize..][..size], head);
        self.call(self.reach, &[at as i32]).unwrap_or(TRAPPED)
    }

    pub(crate) fn render(&mut self, job: &mut Job, plan: &Plan) -> i32 {
        let Some(at) = self.room(plan.total as u32) else {
            return NO_ROOM;
        };
        let block = &mut self.memory.data_mut(&mut self.store)[at as usize..][..plan.total];
        frame::lay(block, plan, job);
        match self.call(self.render, &[at as i32]) {
            None => TRAPPED,
            Some(0) => {
                frame::take_output(&self.memory.data(&self.store)[at as usize..], plan, job);
                OK
            }
            Some(_) => FAILED,
        }
    }

    /// Room for `size` bytes in the module, from its allocator, kept for the
    /// next call; `None` where it gives none inside its memory.
    fn room(&mut self, size: u32) -> Option<u32> {
        if self.room.1 >= size {
            return Some(self.room.0);
        }
        let at = self.call(self.alloc, &[size as i32]).filter(|&at| at != 0)? as u32;
        if at as usize + size as usize > self.memory.data_size(&self.store) {
            return None;
        }
        self.room = (at, size);
        Some(at)
    }

    /// `func` called with i32 `args`, its one i32 answer; `None` where it
    /// trapped or the call failed.
    fn call(&mut self, func: Func, args: &[i32]) -> Option<i32> {
        let args: Vec<Val> = args.iter().map(|&arg| Val::I32(arg)).collect();
        let mut answer = [Val::I32(0)];
        func.call(&mut self.store, &args, &mut answer).ok()?;
        match answer {
            [Val::I32(answer)] => Some(answer),
            _ => None,
        }
    }
}

/// The engine a module runs in: compiled to this machine's code, or to
/// Pulley's where none may be made (the file's head).
fn engine(interpret: bool) -> Result<Engine, String> {
    let mut config = Config::new();
    if interpret {
        let target = if size_of::<usize>() == 8 { "pulley64" } else { "pulley32" };
        config.target(target).map_err(|error| said("the interpreter", error))?;
    }
    Engine::new(&config).map_err(|error| said("the engine", error))
}

/// What `doing` met, as the C host put Wasmtime's words.
fn said(doing: &str, error: wasmtime::Error) -> String {
    format!("{doing}: {error:?}")
}
