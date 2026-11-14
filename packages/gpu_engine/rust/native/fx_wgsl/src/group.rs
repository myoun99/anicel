//! A group's shared memory, its barriers and its atomics, in
//! `anicel_render` alone (Q6 answer 「허락한다 — ⓐⓑⓒ 규칙으로, 첫
//! 약속부터」 · Q8 · Q9 · Q10, 2026-11-08):
//!
//! - ⓐ A loop that waits at a barrier is left by the whole group at once:
//!   every way out of it is taken under uniform conditions (uniform.rs),
//!   and count.rs charges it with the group's word, so a cut takes the
//!   group out together.
//! - ⓑ An atomic is an add, a min or a max, and what it gives back is not
//!   read: the last value is then the same in any order (check.rs).
//! - ⓒ Shared memory starts zeroed — wgpu's
//!   `zero_initialize_workgroup_memory`, on by default; the CPU's run
//!   zeroes it for each group.
//! - 🗣️Q8 「barrier 뒤에만 읽게 한다」: an atomic is read only after a
//!   barrier has followed its last write, and not written again once read.
//! - 🗣️Q9 「호출마다 제 칸에만 쓰게 한다」: a plain store into shared
//!   memory goes to the invocation's own cell — the index its own
//!   `local_invocation_index`, or its `local_invocation_id`'s components
//!   for each axis the group spans, within the array's length.
//! - 🗣️Q10 「제자리 꼴은 거절하고, 두 단계 꼴만 받는다」 (보드
//!   an-endless-plugin-stalls-the-app 15:17): between two barriers a shared
//!   array is read past the own cell or written, not both — a tree's sum is
//!   read → barrier → write.
//!
//! What it cannot prove it refuses: shared memory and barriers belong to
//! `anicel_render` itself (the proof does not follow calls), and a cell
//! chosen by data is not the own one.

use std::collections::HashMap;

use naga::valid::FunctionInfo;
use naga::{
    AddressSpace, Binding, Block, BuiltIn, EntryPoint, Expression, Handle, Module, Span, Statement,
    TypeInner,
};

use crate::{Refusal, uniform};

/// Whether `block` waits at a barrier anywhere in it.
pub(crate) fn holds_barrier(block: &Block) -> bool {
    block.iter().any(|statement| match statement {
        Statement::ControlBarrier(_) | Statement::WorkGroupUniformLoad { .. } => true,
        Statement::Block(inner) => holds_barrier(inner),
        Statement::If { accept, reject, .. } => holds_barrier(accept) || holds_barrier(reject),
        Statement::Switch { cases, .. } => cases.iter().any(|case| holds_barrier(&case.body)),
        Statement::Loop { body, continuing, .. } => holds_barrier(body) || holds_barrier(continuing),
        _ => false,
    })
}

/// The most bytes a group's shared memory may hold, the host's word
/// included: the engine's device asks wgpu's default for this limit
/// (src/device.rs `most_storage`), and each variable counts rounded up to
/// 16 bytes, as WebGPU's pipeline rule counts it.
pub(crate) const MOST_SHARED_BYTES: u32 = 16384;

/// The host's own word in shared memory: prelude.wgsl's
/// `anicel_host_group_cut`, one `atomic<u32>`, rounded up.
const HOST_SHARED_BYTES: u32 = 16;

pub(crate) fn check(module: &Module, render: &EntryPoint, info: &FunctionInfo, plugin: &str) -> Result<(), Refusal> {
    let function = &render.function;
    let arguments: Vec<bool> = (0..function.arguments.len()).map(|i| uniform::uniform_argument(function, i)).collect();
    let uniformity = uniform::analyse(module, function, &arguments, &mut HashMap::new());
    // The loop first: a barrier in a loop left apart is passed by apart
    // too, and the loop is what to change.
    leave_together(&function.body, &uniformity, plugin)?;
    if let Some(span) = uniformity.barrier_apart() {
        return Err(Refusal::at(
            plugin,
            span,
            "a barrier is met by the whole group: it stands where every invocation goes alike (Q6 ⓐ)",
        ));
    }
    let shared: Vec<Handle<naga::GlobalVariable>> = module
        .global_variables
        .iter()
        .filter(|(handle, global)| {
            global.space == AddressSpace::WorkGroup && crate::check::is_plugins(module.global_variables.get_span(*handle), plugin)
        })
        .map(|(handle, _)| handle)
        .collect();
    let bytes: u64 = shared
        .iter()
        .map(|&global| u64::from(module.types[module.global_variables[global].ty].inner.size(module.to_ctx())).next_multiple_of(16))
        .sum();
    if bytes + u64::from(HOST_SHARED_BYTES) > u64::from(MOST_SHARED_BYTES) {
        return Err(Refusal::at(
            plugin,
            module.global_variables.get_span(shared[0]),
            format!("a group's shared memory is at most {} bytes, each variable rounded up to 16", MOST_SHARED_BYTES - HOST_SHARED_BYTES),
        ));
    }
    if shared.is_empty() {
        return Ok(());
    }
    let walk = Intervals { module, render, info, plugin, shared: &shared };
    walk.block(&function.body, vec![Interval::default(); shared.len()], &mut Exits::default()).map(|_| ())
}

/// ⓐ: every loop that waits at a barrier is left by the group together.
fn leave_together(block: &Block, uniformity: &uniform::Uniformity, plugin: &str) -> Result<(), Refusal> {
    for (statement, span) in block.span_iter() {
        match statement {
            Statement::Loop { body, continuing, .. } => {
                if (holds_barrier(body) || holds_barrier(continuing)) && !uniformity.leaves_together(body) {
                    return Err(Refusal::at(
                        plugin,
                        *span,
                        "a loop that waits at a barrier is left by the whole group at once: its way out \
                         is decided by values every invocation holds alike (Q6 ⓐ)",
                    ));
                }
                leave_together(body, uniformity, plugin)?;
                leave_together(continuing, uniformity, plugin)?;
            }
            Statement::Block(inner) => leave_together(inner, uniformity, plugin)?,
            Statement::If { accept, reject, .. } => {
                leave_together(accept, uniformity, plugin)?;
                leave_together(reject, uniformity, plugin)?;
            }
            Statement::Switch { cases, .. } => {
                for case in cases {
                    leave_together(&case.body, uniformity, plugin)?;
                }
            }
            _ => {}
        }
    }
    Ok(())
}

/// What one shared variable has had since the last barrier, and its
/// atomic's whole run.
#[derive(Clone, Copy, Default, PartialEq, Eq)]
struct Interval {
    written: bool,
    read_past_own: bool,
    atomic_written: bool,
    atomic_read: bool,
}

fn join(a: &[Interval], b: &[Interval]) -> Vec<Interval> {
    a.iter()
        .zip(b)
        .map(|(a, b)| Interval {
            written: a.written || b.written,
            read_past_own: a.read_past_own || b.read_past_own,
            atomic_written: a.atomic_written || b.atomic_written,
            atomic_read: a.atomic_read || b.atomic_read,
        })
        .collect()
}

/// What the ways out of the loop or switch being walked carry: the state
/// at each `break`, and at each `continue` (which goes to the continuing).
#[derive(Default)]
struct Exits {
    breaks: Option<Vec<Interval>>,
    continues: Option<Vec<Interval>>,
}

/// `state` joined into what a way out has carried so far.
fn carry(into: &mut Option<Vec<Interval>>, state: &[Interval]) {
    *into = Some(match into.take() {
        Some(known) => join(&known, state),
        None => state.to_vec(),
    });
}

/// `state` with what a way out carried, if it carried anything.
fn with(state: Vec<Interval>, carried: &Option<Vec<Interval>>) -> Vec<Interval> {
    match carried {
        Some(carried) => join(&state, carried),
        None => state,
    }
}

/// A place in shared memory a pointer names.
struct Place {
    slot: usize,
    atomic: bool,
    own: bool,
}

struct Intervals<'a> {
    module: &'a Module,
    render: &'a EntryPoint,
    info: &'a FunctionInfo,
    plugin: &'a str,
    shared: &'a [Handle<naga::GlobalVariable>],
}

impl Intervals<'_> {
    fn refuse<T>(&self, span: Span, why: &str) -> Result<T, Refusal> {
        Err(Refusal::at(self.plugin, span, why))
    }

    fn block(&self, block: &Block, mut state: Vec<Interval>, exits: &mut Exits) -> Result<Vec<Interval>, Refusal> {
        for (statement, span) in block.span_iter() {
            state = self.statement(statement, *span, state, exits)?;
        }
        Ok(state)
    }

    fn statement(
        &self,
        statement: &Statement,
        span: Span,
        mut state: Vec<Interval>,
        exits: &mut Exits,
    ) -> Result<Vec<Interval>, Refusal> {
        let function = &self.render.function;
        match *statement {
            Statement::Emit(ref range) => {
                for handle in range.clone() {
                    if let Expression::Load { pointer } = function.expressions[handle] {
                        if let Some(place) = self.place(pointer) {
                            self.read(&mut state, &place, function.expressions.get_span(handle))?;
                        }
                    }
                }
            }
            Statement::Store { pointer, .. } => {
                if let Some(place) = self.place(pointer) {
                    let interval = &mut state[place.slot];
                    if place.atomic {
                        return self.refuse(span, "an atomic is added to, or taken the min or max of, alone (Q6 ⓑ)");
                    }
                    if !place.own {
                        return self.refuse(
                            span,
                            "a store into shared memory goes to the invocation's own cell: its \
                             local_invocation_index, or its local_invocation_id for each axis (Q9)",
                        );
                    }
                    if interval.read_past_own {
                        return self.refuse(
                            span,
                            "between two barriers shared memory is read past the own cell or written, not \
                             both: read, then a barrier, then write (Q10)",
                        );
                    }
                    interval.written = true;
                }
            }
            Statement::Atomic { pointer, .. } => {
                if let Some(place) = self.place(pointer) {
                    let interval = &mut state[place.slot];
                    if interval.atomic_read {
                        return self.refuse(span, "an atomic once read is not written again in the run (Q8)");
                    }
                    interval.atomic_written = true;
                }
            }
            // `workgroupBarrier`, the one the check lets through.
            Statement::ControlBarrier(_) => state = barrier_passed(&state),
            Statement::WorkGroupUniformLoad { pointer, .. } => {
                state = barrier_passed(&state);
                if let Some(place) = self.place(pointer) {
                    self.read(&mut state, &Place { own: false, ..place }, span)?;
                }
            }
            Statement::Break => carry(&mut exits.breaks, &state),
            Statement::Continue => carry(&mut exits.continues, &state),
            Statement::Block(ref inner) => state = self.block(inner, state, exits)?,
            Statement::If { ref accept, ref reject, .. } => {
                let accepted = self.block(accept, state.clone(), exits)?;
                let rejected = self.block(reject, state, exits)?;
                state = join(&accepted, &rejected);
            }
            Statement::Switch { ref cases, .. } => {
                // A break leaves the switch; a continue, the loop around it.
                // Each case starts from the switch's state: a case WGSL
                // falls through from is one of `case 1, 2:`'s selectors,
                // and its body is empty.
                let mut inner = Exits { breaks: None, continues: exits.continues.take() };
                let mut out = state.clone();
                for case in cases {
                    out = join(&out, &self.block(&case.body, state.clone(), &mut inner)?);
                }
                exits.continues = inner.continues;
                state = with(out, &inner.breaks);
            }
            Statement::Loop { ref body, ref continuing, .. } => {
                // Round the back edge until nothing new reaches the top; the
                // loop is left by a break, or by its `break if` after the
                // continuing.
                let mut top = state.clone();
                loop {
                    let mut inner = Exits::default();
                    let end = self.block(body, top.clone(), &mut inner)?;
                    let after = self.block(continuing, with(end, &inner.continues), &mut Exits::default())?;
                    let next = join(&state, &after);
                    if next == top {
                        state = with(after, &inner.breaks);
                        break;
                    }
                    top = next;
                }
            }
            _ => {}
        }
        Ok(state)
    }

    fn read(&self, state: &mut [Interval], place: &Place, span: Span) -> Result<(), Refusal> {
        let interval = &mut state[place.slot];
        if place.atomic {
            if interval.atomic_written {
                return self.refuse(span, "an atomic is read only after a barrier has followed its last write (Q8)");
            }
            interval.atomic_read = true;
        } else if !place.own {
            if interval.written {
                return self.refuse(
                    span,
                    "shared memory past the own cell is read only after a barrier has followed the writes \
                     (Q9 · Q10: read, then a barrier, then write)",
                );
            }
            interval.read_past_own = true;
        }
        Ok(())
    }

    /// The shared place `pointer` names, if it names one.
    fn place(&self, pointer: Handle<Expression>) -> Option<Place> {
        let function = &self.render.function;
        let mut steps = Vec::new();
        let mut at = pointer;
        let global = loop {
            match function.expressions[at] {
                Expression::Access { base, index } => {
                    steps.push(Some(index));
                    at = base;
                }
                Expression::AccessIndex { base, .. } => {
                    steps.push(None);
                    at = base;
                }
                Expression::GlobalVariable(global) => break global,
                _ => return None,
            }
        };
        let slot = self.shared.iter().position(|&shared| shared == global)?;
        steps.reverse();
        let pointee = match *self.info[pointer].ty.inner_with(&self.module.types) {
            TypeInner::Pointer { base, .. } => &self.module.types[base].inner,
            ref other => other,
        };
        let atomic = matches!(pointee, TypeInner::Atomic(_));
        Some(Place { slot, atomic, own: self.own(self.module.global_variables[global].ty, &steps) })
    }

    /// Whether every array level down from `ty` is indexed by the
    /// invocation's own number alone (Q9), each long enough that no index
    /// is clamped onto another's (Restrict), and together they tell the
    /// group's invocations apart — the whole index, or each axis the group
    /// spans.
    fn own(&self, mut ty: Handle<naga::Type>, steps: &[Option<Handle<Expression>>]) -> bool {
        let size = self.render.workgroup_size;
        let mut covered = [false; 3];
        let mut whole = false;
        for step in steps {
            let TypeInner::Array { base, size: naga::ArraySize::Constant(length), .. } = self.module.types[ty].inner else {
                break;
            };
            let Some(index) = step else { return false };
            let reach = match self.own_index(*index) {
                Some(Own::Whole) => {
                    whole = true;
                    size.iter().product::<u32>()
                }
                Some(Own::Axis(axis)) => {
                    covered[axis] = true;
                    size[axis]
                }
                None => return false,
            };
            if length.get() < reach {
                return false;
            }
            ty = base;
        }
        whole || (0..3).all(|axis| covered[axis] || size[axis] == 1)
    }

    fn own_index(&self, index: Handle<Expression>) -> Option<Own> {
        let function = &self.render.function;
        let builtin = |argument: u32| match function.arguments[argument as usize].binding {
            Some(Binding::BuiltIn(builtin)) => Some(builtin),
            _ => None,
        };
        match function.expressions[index] {
            Expression::FunctionArgument(argument) if builtin(argument) == Some(BuiltIn::LocalInvocationIndex) => {
                Some(Own::Whole)
            }
            Expression::AccessIndex { base, index: axis } => match function.expressions[base] {
                Expression::FunctionArgument(argument) if builtin(argument) == Some(BuiltIn::LocalInvocationId) => {
                    Some(Own::Axis(axis as usize))
                }
                _ => None,
            },
            Expression::As { expr, .. } => self.own_index(expr),
            _ => None,
        }
    }
}

enum Own {
    Whole,
    Axis(usize),
}

fn barrier_passed(state: &[Interval]) -> Vec<Interval> {
    state
        .iter()
        .map(|interval| Interval { written: false, read_past_own: false, atomic_written: false, ..*interval })
        .collect()
}
