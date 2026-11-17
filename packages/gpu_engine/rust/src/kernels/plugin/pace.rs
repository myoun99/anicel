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

/// The most chunks one batch takes, however quick they come back: a run
/// whose spend leaps from next to nothing to its whole share keeps the
/// engine's own work waiting behind a batch for no more than this many
/// [`CHUNK_BUDGET`]s — each chunk is still a submit of its own, so no
/// submit keeps the device past one.
pub(super) const MOST_IN_A_BATCH: usize = 16;

/// How many of a run's chunks go to the device before its cut is read
/// (`Plugin::chunked`): one at first, twice as many after a batch that
/// came back within half a [`CHUNK_BUDGET`], half as many after one that
/// took longer than one. So a batch keeps the engine's own work waiting
/// behind it no longer than one chunk at its whole share may: a plug-in
/// that spends next to nothing waits for the device a few times a
/// picture, a dear one's chunks go one at a time.
///
/// ⚠️What a batch took is timed from its first submit to its cut read —
/// a wait's own round trip in it, whatever the chunks cost: 🔬a chunk of
/// a few pixels came back in 3–7 ms in the crate's tests (11-17), where
/// the app's waited 0.36 ms. A budget of a few ms never let a batch grow
/// there.
#[derive(Debug, PartialEq, Eq)]
pub(super) struct Batches {
    size: usize,
    /// What a batch is held to ([`Batches::within`]).
    budget: Duration,
}

impl Default for Batches {
    fn default() -> Self {
        Self::within(CHUNK_BUDGET)
    }
}

impl Batches {
    /// Batches held to `budget`: a chunk's at its whole share in every run
    /// ([`Default`]); another only where a test counts the waits apart
    /// from the clock — 🔬the crate's debug run, a thousand tests at once,
    /// came back past a chunk's budget: 73 waits for 512 chunks where
    /// alone there were some forty (11-17).
    pub(super) fn within(budget: Duration) -> Self {
        Self { size: 1, budget }
    }

    /// How many chunks the next batch takes.
    pub(super) fn size(&self) -> usize {
        self.size
    }

    /// The batch just read back `took`, from its first submit to its cut.
    pub(super) fn took(&mut self, took: Duration) {
        if took * 2 <= self.budget {
            self.size = (self.size * 2).min(MOST_IN_A_BATCH);
        } else if took > self.budget {
            self.size = (self.size / 2).max(1);
        }
    }
}

/// What the turns a probe's run is given add to it before they stop
/// growing: long enough that the run's own cost, and how much that jumps,
/// are lost in it ([`turn_time_of`]).
pub(super) const STEP: Duration = Duration::from_millis(10);

/// How many times the turns a probe's run is given grow from one run to
/// the next: a run's own cost is most of it till its turns are many
/// (🔬main PC, 11-18: the 512² probe took 3–6 ms at 256 turns, 11 at 8,192
/// and 28 at 65,536), so a step that taught nothing is passed by quickly —
/// and the run that ends the walk still keeps the device well inside a
/// chunk's [`CHUNK_BUDGET`]: under 4/3 · 4 · [`STEP`].
const GROWTH: u32 = 4;

/// The most turns a probe run is given — a device too slow to reach
/// [`STEP`] under it is measured at it.
pub(super) const MOST_TURNS: u32 = 1 << 24;

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

/// The seconds one turn of the probe takes over a `side`-square picture,
/// its turns from `turns` ([`turn_time_of`]).
fn turn_time(engine: &Engine, plugin: &Plugin, side: usize, turns: u32) -> Option<f64> {
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
        match plugin.run(engine, &frame, &mut output, u64::MAX, Batches::default())? {
            Ok(()) => Some(started.elapsed().as_secs_f64()),
            Err(_) => fail("the probe was cut"),
        }
    };
    turn_time_of(|turns| Some(run(turns)?.min(run(turns)?)), turns)
}

/// The seconds one turn takes, `quicker` the quicker of two runs given so
/// many turns: what the last growth of its turns, from `turns`, added,
/// once it adds [`STEP`] — a growth that added less is a run's own cost
/// jumping, or a device still waking (🔬a fresh engine's first runs on
/// the Surface took 4.3 ms, then 3.8 and 3.0 as their turns doubled,
/// 2026-11-11), and the turns grow past it. At [`MOST_TURNS`], the whole
/// run's time over its turns, which is more: a pace taken too slow only
/// makes chunks smaller.
///
/// ↩️The turns stopped growing once a RUN passed [`STEP`], and doubled
/// (11-11 – 11-18): the 512² probe's run costs 8–14 ms of its own (its
/// picture laid and read back, two waits) and jumps by a few ms, so the
/// first doubling ended the walk with next to no turns in it, and the
/// pace was that jump over the turns. 🔬Main PC, the measuring scene with
/// the fixture's invert on a row, three runs of the app: a pixel's charge
/// measured 0.055, 0.633 and 1.590 ps — chunks of the band's plug-in
/// renders 3, 24 and 96 a render (192 in another), a render 3.4 to 47 ms
/// on the engine's thread, the band's plug-in renders 0.8 to 8.6 s
/// (a-plugin-step-is-keyed-by-a-moment-it-may-not-read). Stopped by what
/// the growth adds: 0.053, 0.059 and 0.078 ps, 2–3 chunks.
pub(super) fn turn_time_of(mut quicker: impl FnMut(u32) -> Option<f64>, mut turns: u32) -> Option<f64> {
    quicker(turns)?;
    let mut before = quicker(turns)?;
    loop {
        let next = turns.saturating_mul(GROWTH);
        let took = quicker(next)?;
        let added = took - before;
        if added > STEP.as_secs_f64() {
            return Some(added / f64::from(next - turns));
        }
        if next >= MOST_TURNS {
            return Some(took / f64::from(next));
        }
        (turns, before) = (next, took);
    }
}
