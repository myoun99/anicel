//! How fast the engine's device spends a plugin's share — what a run's
//! chunks are sized by (an-endless-plugin-stalls-the-app 11-10 16:44 ① ·
//! 11-11 11:25 ⑤): a chunk holds as many workgroups as finish within
//! [`CHUNK_BUDGET`] were every invocation of them to spend its whole
//! share, so no submit keeps the device past it however a plugin spends.
//!
//! 🗣️관제 2026-11-11 11:25: measured on the device the app opened at the
//! first plugin run of that run of the app — ⛔never as the app starts
//! (Q15: what the app compiles ahead holds back every user's first
//! picture) — its kernel compiled at the engine's compiler turn as any
//! plugin's is (`Plugin::open`), then kept on the engine.
//!
//! The probe spends its share on the slowest charge measured (🔬Surface
//! Pro 11, 2026-11-11 11:22: an unsigned division, of six forms — a
//! multiply-add took a tenth of it), so a share spent on anything
//! else takes less.

use std::time::{Duration, Instant};

use fx_wgsl::{Frame, open};

use super::Plugin;
use crate::device::Engine;
use crate::fail;

/// The longest one chunk keeps the device: a value no picture shows, so
/// the host's (16:44 ①) — what else the device draws waits no longer, and
/// it is far under Windows' ~2 s reset.
pub(super) const CHUNK_BUDGET: Duration = Duration::from_millis(100);

/// What a timed probe run reaches before its turns stop doubling: long
/// enough that a submit's cost and the timer's are lost in it.
const STEP: Duration = Duration::from_millis(10);

/// The most turns a probe run is given — a device too slow to reach
/// [`STEP`] under it is measured at it.
const MOST_TURNS: u32 = 1 << 24;

/// Each invocation divides its word as many turns as value 0 says.
const PROBE: &str = "@compute @workgroup_size(16, 16)\n\
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {\n\
  let here = anicel_here();\n\
  var n = anicel_in(here.x, here.y);\n\
  let turns = u32(anicel_value(0, 0));\n\
  for (var i = 0u; i < turns; i++) { n = (n / ((n & 7u) + 1u)) ^ (i * 2654435761u); }\n\
  anicel_out(n);\n\
}\n\
fn anicel_reach() -> u32 { return 0u; }\n";

/// The probe's workgroup, across and down.
const GROUP: usize = 16;

/// The side of the probe's picture that fills the device: 1,024 groups.
const FULL: usize = 512;

/// One charge's time on the engine's device, in seconds.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Pace {
    /// On a lane of a workgroup alone on the device — its latency.
    lane: f64,
    /// Over a pixel of a picture that fills the device — its throughput.
    pixel: f64,
}

impl Pace {
    /// The engine's, measured at the first ask.
    pub(super) fn of(engine: &Engine) -> Option<Self> {
        if let Some(&pace) = engine.plugin_pace.get() {
            return Some(pace);
        }
        let measured = Self::measured(engine)?;
        Some(*engine.plugin_pace.get_or_init(|| measured))
    }

    fn measured(engine: &Engine) -> Option<Self> {
        let kernel = open(PROBE).unwrap_or_else(|refusal| panic!("the host's probe: {refusal}"));
        let turn = kernel.turns()[0] as f64;
        let plugin = match Plugin::open(engine, kernel) {
            Ok(plugin) => plugin,
            Err(why) => return fail(format!("the device refused the probe: {why}")),
        };
        let lane = turn_time(engine, &plugin, GROUP, 1 << 12)? / turn;
        let pixel = turn_time(engine, &plugin, FULL, 1 << 8)? / turn / (FULL * FULL) as f64;
        Some(Self { lane, pixel })
    }

    /// The most workgroups of `group` pixels one chunk takes when each
    /// invocation may spend `share`: as many as finish within
    /// [`CHUNK_BUDGET`] — or within the time one lane takes to spend it,
    /// where that is longer — and one at least.
    pub(super) fn chunk(&self, share: u32, group: u32) -> u64 {
        let share = f64::from(share.max(1));
        let within = CHUNK_BUDGET.as_secs_f64().max(share * self.lane);
        let groups = within / (share * self.pixel * f64::from(group.max(1)));
        (groups as u64).max(1)
    }

    #[cfg(test)]
    pub(super) fn new(lane: f64, pixel: f64) -> Self {
        Self { lane, pixel }
    }
}

/// The seconds one turn of the probe takes over a `side`-square picture:
/// what the last doubling of its turns, from `turns`, added to the
/// quicker of two runs, once a run passes [`STEP`] — a doubling that
/// added nothing is a device still waking (🔬a fresh engine's first runs
/// on the Surface took 4.3 ms, then 3.8 and 3.0 as their turns doubled,
/// 2026-11-11), and the turns double past it. At [`MOST_TURNS`], the whole
/// run's time over its turns, which is more: a pace taken too slow only
/// makes chunks smaller.
fn turn_time(engine: &Engine, plugin: &Plugin, side: usize, mut turns: u32) -> Option<f64> {
    let input: Vec<u32> = (0..(side * side) as u32).map(|at| at.wrapping_mul(2654435761) | 1).collect();
    let mut output = vec![0; side * side];
    let mut run = |turns: u32| -> Option<f64> {
        let values = [[turns as i32, 0, 0, 0]];
        let edge = side as i32;
        let frame = Frame {
            out_origin: [0, 0],
            out_size: [edge, edge],
            in_origin: [0, 0],
            in_size: [edge, edge],
            frame: 0,
            time_q16: 0,
            rate_q16: 24 << 16,
            scale_q16: 1 << 16,
            fuel: u32::MAX,
            input: &input,
            rows: &[],
            values: &values,
        };
        let started = Instant::now();
        match plugin.run(engine, &frame, &mut output, u64::MAX)? {
            Ok(()) => Some(started.elapsed().as_secs_f64()),
            Err(_) => fail("the probe was cut"),
        }
    };
    let mut quicker = |turns: u32| -> Option<f64> { Some(run(turns)?.min(run(turns)?)) };
    quicker(turns)?;
    let mut before = quicker(turns)?;
    loop {
        let next = turns * 2;
        let took = quicker(next)?;
        let added = took - before;
        if added > 0.0 && took > STEP.as_secs_f64() {
            return Some(added / f64::from(next - turns));
        }
        if next >= MOST_TURNS {
            return Some(took / f64::from(next));
        }
        (turns, before) = (next, took);
    }
}
