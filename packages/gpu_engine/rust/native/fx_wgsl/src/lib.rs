//! A GPU fx plugin (fx spec 2): one WGSL compute kernel, read, checked and
//! counted here before any device compiles it — the same function for the
//! host that opens a plugin and the SDK's check command (design 2/3 ③,
//! an-endless-plugin-stalls-the-app).
//!
//! 🗣️Q4 (유저 2026-11-08): plugins are GPU kernels (WGSL), not WebAssembly
//! or native libraries. A plugin is `plugin.wgsl` with
//! `@compute fn anicel_render(@builtin(global_invocation_id) …)`, one
//! invocation per output pixel, and `fn anicel_reach() -> u32`, how many
//! pixels past each edge it reads; it reaches its pictures and values
//! through the host's prelude (prelude.wgsl) alone.
//!
//! 🗣️Q1 · Q19: a plugin that does not end is cut, at the same place on
//! every device. count.rs puts a charge at the top of every loop — the
//! turn's size in IR, fixed by the source — against each invocation's
//! share: one pixel's, the setting itself (🗣️Q19, 유저 2026-11-10 16:36 —
//! ↩️the limit over the pixels till then, Q5). Straight code is bounded by
//! the program's size and WGSL has no recursion, so every invocation ends.
//!
//! The integer law (gpu-int-spec-canvas): no float anywhere — the values
//! cross as integers once, on the CPU, and from there every device draws
//! the same picture. The CPU runs the same counted module (run.rs) for the
//! reach, which the chain's plan needs before anything is dispatched, and
//! for the reference picture the GPU's is held to.
//!
//! 🗣️Q6 (2026-11-08: 「화소마다 꼴(설계 ①)을 먼저 짓고 바로 다음 레인에서
//! 공유 메모리 · 동기화 · 원자 연산을 ⓐⓑⓒ 와 함께 연다」): a group's shared
//! memory, `workgroupBarrier` and atomics are open to `anicel_render`,
//! under the rules group.rs proves — the group leaves a barrier's loop
//! together (ⓐ, uniform.rs, and count.rs's group charge), an atomic only
//! adds, mins or maxes (ⓑ), shared memory starts zeroed (ⓒ), and the
//! answers to Q8 · Q9 · Q10 make every read see one value on every device.
//! The CPU's run takes each invocation of a group on its own thread and
//! meets them at each barrier.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod check;
mod count;
mod frame;
mod group;
mod run;
mod scan;
mod uniform;

#[cfg(test)]
mod tests;

use naga::valid::{Capabilities, ModuleInfo, ValidationFlags, Validator};

pub use frame::{Bound, CHUNK_WORD, CUT, Cut, FRAME, Frame, OUTPUT};

/// The host's prelude, appended after every plugin's source.
pub const PRELUDE: &str = include_str!("prelude.wgsl");

/// The entry point a plugin draws with.
pub const RENDER: &str = "anicel_render";

/// The function a plugin answers its reach with.
pub const REACH: &str = "anicel_reach";

/// The most invocations one workgroup may have (WebGPU's default limit,
/// the one every device the app runs on gives).
pub const MOST_INVOCATIONS: u32 = 256;

/// Why a plugin was not opened, and where in its source when a place is
/// known (1-based; 0 when none is).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Refusal {
    pub line: u32,
    pub column: u32,
    pub why: String,
}

impl Refusal {
    fn nowhere(why: impl Into<String>) -> Self {
        Refusal { line: 0, column: 0, why: why.into() }
    }

    fn at(source: &str, span: naga::Span, why: impl Into<String>) -> Self {
        match span.to_range() {
            Some(range) if range.start < source.len() => {
                let location = span.location(source);
                Refusal { line: location.line_number, column: location.line_position, why: why.into() }
            }
            _ => Refusal::nowhere(why),
        }
    }
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.line == 0 {
            write!(f, "{}", self.why)
        } else {
            write!(f, "{}:{}: {}", self.line, self.column, self.why)
        }
    }
}

/// An opened plugin: its source as the device compiles it, and the
/// counted module the CPU runs.
pub struct Kernel {
    source: String,
    module: naga::Module,
    info: ModuleInfo,
    turns: Vec<u64>,
    cut: bool,
}

impl Kernel {
    /// The WGSL the device compiles — the plugin with its charges, or with
    /// none where it was opened not to be cut ([`open_uncut`]), then the
    /// prelude.
    pub fn source(&self) -> &str {
        &self.source
    }

    /// Whether the device's run is cut once an invocation spends its
    /// share: false for a plugin opened by [`open_uncut`].
    pub fn cut(&self) -> bool {
        self.cut
    }

    /// What one turn of each of the plugin's loops spends of an
    /// invocation's share, in the order the loops are written.
    pub fn turns(&self) -> &[u64] {
        &self.turns
    }

    /// The counted module, validated.
    pub fn module(&self) -> &naga::Module {
        &self.module
    }

    /// The module's validation info.
    pub fn info(&self) -> &ModuleInfo {
        &self.info
    }

    /// The render entry point's workgroup size.
    pub fn workgroup_size(&self) -> [u32; 3] {
        self.render_entry().workgroup_size
    }

    fn render_entry(&self) -> &naga::EntryPoint {
        &self.module.entry_points[self.render_index()]
    }

    fn render_index(&self) -> usize {
        self.module.entry_points.iter().position(|entry| entry.name == RENDER).expect("the check found it")
    }
}

/// Reads `plugin`, checks it, counts its loops and reads the counted
/// source again — the kernel, or why not.
pub fn open(plugin: &str) -> Result<Kernel, Refusal> {
    opened(plugin, true)
}

/// [`open`], the device's source left without its charges: no run of it
/// is cut on the device. 🗣️an-endless-plugin-stalls-the-app-Q18 (유저
/// 2026-11-10): 「기본은 끊고, 설정에 『끊지 않음』을 더한다」 — the CPU's
/// module is counted all the same, so the reach still ends at the share
/// it is given.
pub fn open_uncut(plugin: &str) -> Result<Kernel, Refusal> {
    opened(plugin, false)
}

fn opened(plugin: &str, cut: bool) -> Result<Kernel, Refusal> {
    let whole = format!("{plugin}\n{PRELUDE}");
    let (module, info) = read(&whole, plugin)?;
    check::check(&module, &info, plugin)?;
    let reread = |text: String| {
        let text = format!("{text}\n{PRELUDE}");
        let (module, info) = read(&text, &text)
            .map_err(|refusal| Refusal::nowhere(format!("the host's counting broke the plugin: {refusal}")))?;
        Ok((text, module, info))
    };
    let (counted, turns) = count::count(&module, plugin, true);
    let (counted, counted_module, counted_info) = reread(counted)?;
    let source = if cut { counted } else { reread(count::count(&module, plugin, false).0)?.0 };
    Ok(Kernel { source, module: counted_module, info: counted_info, turns, cut })
}

/// Parses and validates `whole`, placing an error in `plugin` (its first
/// part) where it lies there.
fn read(whole: &str, plugin: &str) -> Result<(naga::Module, ModuleInfo), Refusal> {
    let module = naga::front::wgsl::parse_str(whole).map_err(|error| match error.location(whole) {
        Some(location) if (location.offset as usize) < plugin.len() => Refusal {
            line: location.line_number,
            column: location.line_position,
            why: error.message().to_string(),
        },
        _ => Refusal::nowhere(error.emit_to_string(whole)),
    })?;
    let info = Validator::new(ValidationFlags::all(), Capabilities::empty()).validate(&module).map_err(|error| {
        let why = error.as_inner().to_string();
        match error.spans().next() {
            Some((span, _)) => Refusal::at(plugin, *span, why),
            None => Refusal::nowhere(why),
        }
    })?;
    Ok((module, info))
}
