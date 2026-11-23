//! THE GPU'S OWN CLOCK, WHERE THE DEVICE HAS ONE (H66, 2026-11-23): while
//! the engine is timed ([`Took`]), a submit is stamped on the GPU before its
//! work and after it, and what the GPU took of it is read once the stamps
//! are written — the engine's thread waits for none of it, so the engine
//! timed is the engine untimed.
//!
//! 🗣️유저 2026-11-23 (card the-galaxy-tab-canvas-went-slow-on-build-1095,
//! 관제 23:24): 「몇번을 임시빌드로 테스트하게 만드는거냐고 테스트하더라도
//! 모든가능성 철저하게 검사해서 디버그화면 만들면되지」 — and 관제: 「⛔재는 것이
//! 잰 것을 바꾸면 안 된다 — 엔진 단계 오버레이처럼 제출마다 GPU 를 기다리지 말
//! 것(시각 쿼리를 나중에 읽는다)」. Waited out, each submit ran alone: 1101's
//! photographs of a stroke, timed so, read a step at 1.4 times its cost.
//!
//! A device that stamps nothing between a submit's commands
//! (`TIMESTAMP_QUERY_INSIDE_ENCODERS`) has no clock here, and nothing is
//! told of its GPU's time: the engine says it has none
//! (`gpu_engine_clocked`), and the screen leaves that column empty — where
//! took.rs's head feared a tablet that answers no query, the screen says
//! so instead of reading nothing. ⛔Not waited out instead (🗣️관제 23:51):
//! 「기다림이 걸음 줄 · 펜→화면 지연 · GPU 줄까지 같이 부풀린다」 — a wait
//! measures an engine the app is not.
//!
//! What a stamp reads is the GPU's: from where it reached the submit's
//! first command to where it was through with its last — a submit queued
//! behind another starts when that one is done, so the time is its own.

use std::panic::Location;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;


use crate::took::Took;

/// How many stamped submits may wait to be read at once: past them a
/// submit goes unstamped — a GPU this far behind is told by the submits
/// it has not finished (`gpu_engine_submits_behind`), not by these.
pub(crate) const ROOM: usize = 256;

/// Where a submit's two stamps are written, resolved and read.
pub(crate) struct Stamps {
    set: wgpu::QuerySet,
    resolved: wgpu::Buffer,
    read: wgpu::Buffer,
}

/// One device's clock: nanoseconds a tick of its GPU's, and its stamps.
pub(crate) struct Clock {
    period: f64,
    stamps: Arc<Kept>,
}

/// A clock's stamps: those free, and how many are out — on the GPU, or
/// written and not yet read.
#[derive(Default)]
struct Kept {
    free: Mutex<Vec<Stamps>>,
    out: Mutex<usize>,
}

impl Clock {
    /// The clock of `device` — none where it stamps nothing between a
    /// submit's commands.
    pub(crate) fn of(device: &wgpu::Device, queue: &wgpu::Queue) -> Option<Self> {
        device.features().contains(stamped()).then(|| Self {
            period: f64::from(queue.get_timestamp_period()),
            stamps: Arc::default(),
        })
    }

    /// `buffers`, a submit's, between a stamp before them and one after —
    /// and the stamps, to be read once written ([`Self::read_after`]);
    /// none where every stamp is out.
    pub(crate) fn around(
        &self,
        device: &wgpu::Device,
        buffers: Vec<wgpu::CommandBuffer>,
    ) -> (Vec<wgpu::CommandBuffer>, Option<Stamps>) {
        let Some(stamps) = self.taken(device) else {
            return (buffers, None);
        };
        let mut before = device.create_command_encoder(&Default::default());
        before.write_timestamp(&stamps.set, 0);
        let mut after = device.create_command_encoder(&Default::default());
        after.write_timestamp(&stamps.set, 1);
        after.resolve_query_set(&stamps.set, 0..2, &stamps.resolved, 0);
        after.copy_buffer_to_buffer(&stamps.resolved, 0, &stamps.read, 0, STAMPS_BYTES);
        let stamped =
            std::iter::once(before.finish()).chain(buffers).chain(std::iter::once(after.finish()));
        (stamped.collect(), Some(stamps))
    }

    /// `stamps`, of a submit made `by` there of `groups` workgroups, told
    /// to `took` once the GPU has written them: read where the device is
    /// polled next — a thread of the engine's ([`crate::device::Poll`]), or
    /// its own as it submits — and let go of there. Stamps that could not
    /// be mapped are let go of, and made anew when next taken.
    pub(crate) fn read_after(
        &self,
        stamps: Stamps,
        by: &'static Location<'static>,
        groups: u64,
        took: Arc<Took>,
    ) {
        let (read, kept, period) = (stamps.read.clone(), self.stamps.clone(), self.period);
        read.map_async(wgpu::MapMode::Read, .., move |mapped| {
            *lock(&kept.out) -= 1;
            let view = match (mapped, stamps.read.get_mapped_range(..)) {
                (Ok(()), Ok(view)) => view,
                _ => return,
            };
            let ticks = ticks_of(&view);
            drop(view);
            stamps.read.unmap();
            took.stamped(by, Duration::from_secs_f64(ticks as f64 * period / 1e9), groups);
            lock(&kept.free).push(stamps);
        });
    }

    /// Stamps of this clock's that are not out — made where none is free,
    /// none where [`ROOM`] are out.
    fn taken(&self, device: &wgpu::Device) -> Option<Stamps> {
        let mut out = lock(&self.stamps.out);
        if *out == ROOM {
            return None;
        }
        let stamps = lock(&self.stamps.free).pop().unwrap_or_else(|| made(device));
        *out += 1;
        Some(stamps)
    }
}

/// What a device needs to stamp a submit's work before and after it.
pub(crate) fn stamped() -> wgpu::Features {
    wgpu::Features::TIMESTAMP_QUERY | wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS
}

/// A submit's two stamps, resolved: two ticks.
const STAMPS_BYTES: u64 = 16;

fn made(device: &wgpu::Device) -> Stamps {
    let buffer = |label, usage| {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: STAMPS_BYTES,
            usage,
            mapped_at_creation: false,
        })
    };
    Stamps {
        set: device.create_query_set(&wgpu::QuerySetDescriptor {
            label: Some("a submit's stamps"),
            ty: wgpu::QueryType::Timestamp,
            count: 2,
        }),
        resolved: buffer(
            "a submit's stamps, resolved",
            wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC,
        ),
        read: buffer(
            "a submit's stamps, read",
            wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        ),
    }
}

/// The ticks between a submit's two stamps, as resolved: none where the
/// second reads before the first, as a GPU's clock may where it wraps.
fn ticks_of(bytes: &[u8]) -> u64 {
    let tick = |at: usize| u64::from_le_bytes(bytes[at..at + 8].try_into().expect("8 bytes"));
    tick(8).saturating_sub(tick(0))
}

fn lock<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_submit_took_the_ticks_between_its_stamps() {
        let bytes: Vec<u8> = [100u64, 350].iter().flat_map(|tick| tick.to_le_bytes()).collect();
        assert_eq!(ticks_of(&bytes), 250);
        let wrapped: Vec<u8> = [350u64, 100].iter().flat_map(|tick| tick.to_le_bytes()).collect();
        assert_eq!(ticks_of(&wrapped), 0, "a clock read backwards took nothing");
    }

    #[test]
    fn no_more_stamps_are_out_than_their_room() {
        let turn = crate::testing::a_device_of_its_own();
        let engine = turn.engine();
        let has = engine.adapter.features().contains(stamped());
        assert_eq!(engine.queue.clock.is_some(), has, "a clock wherever the adapter can stamp, none where not");
        let Some(clock) = engine.queue.clock.as_ref() else {
            return;
        };
        let out: Vec<_> = (0..ROOM).map(|_| clock.taken(engine.device()).expect("in the room")).collect();
        assert!(clock.taken(engine.device()).is_none(), "past the room, a submit goes unstamped");
        assert_eq!(out.len(), ROOM);
    }

    // Stamps are taken by a timed submit alone, and kept once read for the
    // next: an untimed engine pays the GPU's clock nothing, and a timed one
    // makes its stamps once.
    #[test]
    fn stamps_are_taken_by_a_timed_submit_alone_and_kept_for_the_next() {
        let turn = crate::testing::a_device_of_its_own();
        let engine = turn.engine();
        let Some(clock) = engine.queue.clock.clone() else {
            return;
        };
        let kept = || (*lock(&clock.stamps.out), lock(&clock.stamps.free).len());
        engine.queue.submit([]);
        crate::testing::done_here(&engine).expect("the GPU done");
        assert_eq!(kept(), (0, 0), "an untimed submit takes no stamps");
        // SAFETY: a live engine.
        unsafe { crate::device::gpu_engine_timed(&raw const engine, true) };
        for _ in 0..3 {
            engine.queue.submit([]);
            crate::testing::done_here(&engine).expect("the GPU done");
            assert_eq!(kept(), (0, 1), "a timed submit's stamps, read, kept for the next");
        }
    }
}
