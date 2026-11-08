//! The CPU's run of a counted kernel: the reach the chain's plan asks
//! before it dispatches anything (design 1/3 — a GPU call and a read-back
//! for one number would stall every frame), and the reference picture the
//! GPU's is held to.
//!
//! It runs the counted module, charges and all, so a plugin is cut at the
//! same turn here as on the device (Q1). It computes what WGSL defines:
//! wrapping integers, `x / 0 == x` and `x % 0 == 0` (and the same for the
//! most negative over -1), shifts by their amount modulo 32, and an index
//! past an array's end read and written at its last element — wgpu's
//! `Restrict` for a checked module, the index taken as unsigned (naga's
//! proc/index.rs names that form; the device's run holds the GPU to it).
//! It runs only what the check lets through.
//!
//! A group runs as the device runs it: each invocation on a thread of its
//! own, the group's shared memory zeroed before it starts (Q6 ⓒ), and the
//! threads meeting at each barrier. What the check proved (group.rs) makes
//! the picture the same in any order the threads take; a group whose
//! invocations meet at different places is a hole in that proof, and the
//! run stops on it rather than wait.

use std::sync::{Condvar, Mutex, MutexGuard, PoisonError};

use naga::{
    AddressSpace, ArraySize, AtomicFunction, BinaryOperator, Binding, Block, BuiltIn, Expression, Function, Handle,
    Literal, MathFunction, Module, RelationalFunction, ScalarKind, Statement, SwitchValue, TypeInner, UnaryOperator,
};

use crate::{Kernel, REACH};

/// The pictures, values and moment one run is handed — what the GPU's
/// bindings hold (prelude.wgsl's `AnicelFrame` and buffers). Places are
/// canvas pixels; a picture is one straight RGBA8 word a pixel, row by row.
#[derive(Clone, Copy, Debug)]
pub struct Frame<'a> {
    pub out_origin: [i32; 2],
    pub out_size: [i32; 2],
    pub in_origin: [i32; 2],
    pub in_size: [i32; 2],
    pub frame: i32,
    pub time_q16: i32,
    pub rate_q16: i32,
    pub scale_q16: i32,
    /// What each invocation may spend (Q5).
    pub fuel: u32,
    pub input: &'a [u32],
    /// The layer planes, each `in_size`, one after another.
    pub rows: &'a [u32],
    pub values: &'a [[i32; 4]],
}

/// The run spent its share somewhere and was cut.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cut;

impl Kernel {
    /// The plugin's reach, as `anicel_reach` answers it with `frame`'s
    /// values and moment — every invocation's share to spend, as one
    /// invocation of the render has.
    pub fn reach(&self, frame: &Frame<'_>) -> Result<u32, Cut> {
        let world = World::new(&self.module, frame, &[], 1);
        let mut machine = Machine::new(&world);
        let reach = machine.function_named(REACH);
        machine.fresh_invocation();
        machine.set_private("anicel_host_fuel", Val::U32(frame.fuel));
        let answer = machine.call(reach, Vec::new());
        world.cut()?;
        match answer {
            Some(Val::U32(reach)) => Ok(reach),
            other => unreachable!("the check holds anicel_reach to a u32, and it answered {other:?}"),
        }
    }

    /// Runs `anicel_render` over every pixel of `frame`'s output, as the
    /// device dispatches it, into `output` (its pixels as the host started
    /// them — a pixel nothing wrote keeps its word).
    pub fn render(&self, frame: &Frame<'_>, output: &mut [u32]) -> Result<(), Cut> {
        let size = self.workgroup_size();
        let groups = [
            (frame.out_size[0].max(0) as u32).div_ceil(size[0]),
            (frame.out_size[1].max(0) as u32).div_ceil(size[1]),
            1,
        ];
        let render = self.render_entry();
        let world = World::new(&self.module, frame, output, size.iter().product::<u32>() as usize);
        std::thread::scope(|scope| {
            for local in grid(size) {
                let world = &world;
                scope.spawn(move || {
                    let _breaks = BreakOnPanic(&world.meet);
                    let mut machine = Machine::new(world);
                    for group in grid(groups) {
                        world.meet.meet(At::Group, || world.zero_group());
                        let global: [u32; 3] = std::array::from_fn(|axis| group[axis] * size[axis] + local[axis]);
                        let index = local[0] + local[1] * size[0] + local[2] * size[0] * size[1];
                        let arguments = render
                            .function
                            .arguments
                            .iter()
                            .map(|argument| match argument.binding {
                                Some(Binding::BuiltIn(BuiltIn::GlobalInvocationId)) => vector(global),
                                Some(Binding::BuiltIn(BuiltIn::LocalInvocationId)) => vector(local),
                                Some(Binding::BuiltIn(BuiltIn::LocalInvocationIndex)) => Val::U32(index),
                                Some(Binding::BuiltIn(BuiltIn::WorkGroupId)) => vector(group),
                                Some(Binding::BuiltIn(BuiltIn::NumWorkGroups)) => vector(groups),
                                ref other => unreachable!("the check refuses {other:?}"),
                            })
                            .map(Ev::V)
                            .collect();
                        machine.fresh_invocation();
                        machine.run(&render.function, arguments);
                    }
                    world.meet.meet(At::Group, || {});
                });
            }
        });
        world.write_back(output);
        world.cut()
    }
}

/// Every place of a grid `size`, x fastest.
fn grid(size: [u32; 3]) -> impl Iterator<Item = [u32; 3]> {
    (0..size[2]).flat_map(move |z| (0..size[1]).flat_map(move |y| (0..size[0]).map(move |x| [x, y, z])))
}

fn vector(components: [u32; 3]) -> Val {
    Val::Comp(components.iter().map(|&c| Val::U32(c)).collect())
}

/// A value: a scalar, or the components of a vector, array or struct.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Val {
    Bool(bool),
    I32(i32),
    U32(u32),
    Comp(Vec<Val>),
}

impl Val {
    fn parts(&self) -> &[Val] {
        match self {
            Val::Comp(parts) => parts,
            other => unreachable!("a composite was expected, not {other:?}"),
        }
    }

    fn truth(&self) -> bool {
        match *self {
            Val::Bool(truth) => truth,
            ref other => unreachable!("a bool was expected, not {other:?}"),
        }
    }

    fn index(&self) -> u32 {
        match *self {
            Val::I32(index) => index as u32,
            Val::U32(index) => index,
            ref other => unreachable!("an index was expected, not {other:?}"),
        }
    }
}

/// Where a pointer points: a global or a call's local, then the path of
/// components down to the place.
#[derive(Clone, Debug)]
enum Root {
    Global(usize),
    Local { call: usize, local: usize },
}

#[derive(Clone, Debug)]
struct Ptr {
    root: Root,
    path: Vec<usize>,
}

/// An expression's value: a value, or a pointer.
#[derive(Clone, Debug)]
enum Ev {
    V(Val),
    P(Ptr),
}

impl Ev {
    fn val(self) -> Val {
        match self {
            Ev::V(val) => val,
            Ev::P(ptr) => unreachable!("a value was expected, not the pointer {ptr:?}"),
        }
    }
}

/// How a block ended.
enum Flow {
    Next,
    Break,
    Continue,
    Return(Option<Val>),
}

/// One call's expressions as they were evaluated.
struct Activation {
    arguments: Vec<Ev>,
    values: Vec<Option<Ev>>,
}

/// Where a global lives in a run.
#[derive(Clone, Copy)]
enum Home {
    /// A binding no invocation writes: the frame, the pictures, the values.
    Fixed,
    /// The output, the cut and a group's shared memory, behind one lock.
    Shared,
    /// Each invocation's own.
    Private,
}

/// What every invocation of a run reads and writes alike.
struct World<'m> {
    module: &'m Module,
    homes: Vec<Home>,
    fixed: Vec<Option<Val>>,
    shared: Mutex<Vec<Option<Val>>>,
    /// Each shared memory variable's zero, set again before each group.
    group_zero: Vec<(usize, Val)>,
    output_global: Option<usize>,
    cut_global: usize,
    meet: Meet,
}

impl<'m> World<'m> {
    fn new(module: &'m Module, frame: &Frame<'_>, output: &[u32], invocations: usize) -> Self {
        let plane = (frame.in_size[0].max(0) * frame.in_size[1].max(0)) as usize;
        let rows = if plane == 0 { 0 } else { frame.rows.len() / plane };
        let words = |words: &[u32]| Val::Comp(words.iter().map(|&w| Val::U32(w)).collect());
        let mut world = World {
            module,
            homes: Vec::new(),
            fixed: Vec::new(),
            shared: Mutex::new(Vec::new()),
            group_zero: Vec::new(),
            output_global: None,
            cut_global: usize::MAX,
            meet: Meet::new(invocations),
        };
        let mut shared = Vec::new();
        for (handle, global) in module.global_variables.iter() {
            let index = handle.index();
            let (home, val) = match global.name.as_deref() {
                Some("anicel_host_frame") => (Home::Fixed, Some(frame_val(frame, rows, frame.values.len()))),
                Some("anicel_host_input") => (Home::Fixed, Some(words(frame.input))),
                Some("anicel_host_rows") => (Home::Fixed, Some(words(frame.rows))),
                Some("anicel_host_values") => (
                    Home::Fixed,
                    Some(Val::Comp(
                        frame.values.iter().map(|v| Val::Comp(v.iter().map(|&w| Val::I32(w)).collect())).collect(),
                    )),
                ),
                Some("anicel_host_output") => {
                    world.output_global = Some(index);
                    (Home::Shared, Some(words(output)))
                }
                Some("anicel_host_cut") => {
                    world.cut_global = index;
                    (Home::Shared, Some(Val::U32(0)))
                }
                _ if global.space == AddressSpace::WorkGroup => {
                    let zero = zero(module, global.ty);
                    world.group_zero.push((index, zero.clone()));
                    (Home::Shared, Some(zero))
                }
                _ => (Home::Private, None),
            };
            world.homes.push(home);
            let fixed = matches!(home, Home::Fixed);
            world.fixed.push(if fixed { val.clone() } else { None });
            shared.push(if fixed { None } else { val });
        }
        world.shared = Mutex::new(shared);
        world
    }

    fn lock(&self) -> MutexGuard<'_, Vec<Option<Val>>> {
        self.shared.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Ⓒ: the group's shared memory starts zeroed.
    fn zero_group(&self) {
        let mut shared = self.lock();
        for (index, zero) in &self.group_zero {
            shared[*index] = Some(zero.clone());
        }
    }

    fn cut(&self) -> Result<(), Cut> {
        if self.lock()[self.cut_global] == Some(Val::U32(0)) { Ok(()) } else { Err(Cut) }
    }

    fn write_back(&self, output: &mut [u32]) {
        if let Some(index) = self.output_global {
            let shared = self.lock();
            for (word, val) in output.iter_mut().zip(shared[index].as_ref().expect("the output").parts()) {
                *word = val.index();
            }
        }
    }
}

/// Where a group's invocations meet: before a group starts, and at a
/// barrier statement (by its place in the module).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum At {
    Group,
    Barrier(usize),
}

/// The group's meeting place: every invocation waits there until all have
/// come — to the same place, or the run stops.
struct Meet {
    size: usize,
    state: Mutex<Meeting>,
    woken: Condvar,
}

struct Meeting {
    come: usize,
    round: u64,
    at: Option<At>,
    broken: bool,
}

impl Meet {
    fn new(size: usize) -> Self {
        Meet { size, state: Mutex::new(Meeting { come: 0, round: 0, at: None, broken: false }), woken: Condvar::new() }
    }

    /// Waits at `at` until the whole group is there; the last to come runs
    /// `last` before any goes on.
    fn meet(&self, at: At, last: impl FnOnce()) {
        let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        assert!(!state.broken, "another invocation of the group stopped");
        let waiting = *state.at.get_or_insert(at);
        assert!(
            waiting == at,
            "the group met at different places, {waiting:?} and {at:?}: the check let a barrier through \
             that not every invocation meets"
        );
        state.come += 1;
        if state.come == self.size {
            last();
            state.come = 0;
            state.at = None;
            state.round += 1;
            self.woken.notify_all();
            return;
        }
        let round = state.round;
        while state.round == round && !state.broken {
            state = self.woken.wait(state).unwrap_or_else(PoisonError::into_inner);
        }
        assert!(!state.broken, "another invocation of the group stopped");
    }

    fn break_off(&self) {
        self.state.lock().unwrap_or_else(PoisonError::into_inner).broken = true;
        self.woken.notify_all();
    }
}

/// Wakes the rest of the group when an invocation's thread panics, so
/// they stop too instead of waiting at a barrier for ever.
struct BreakOnPanic<'a>(&'a Meet);

impl Drop for BreakOnPanic<'_> {
    fn drop(&mut self) {
        if std::thread::panicking() {
            self.0.break_off();
        }
    }
}

/// One invocation's run: its privates and the locals of every call on
/// its stack.
struct Machine<'w, 'm> {
    world: &'w World<'m>,
    module: &'m Module,
    privates: Vec<Option<Val>>,
    /// Each private's starting value, for a fresh invocation.
    private_start: Vec<(usize, Val)>,
    locals: Vec<Vec<Val>>,
    constants: Vec<Option<Val>>,
}

impl<'w, 'm> Machine<'w, 'm> {
    fn new(world: &'w World<'m>) -> Self {
        let module = world.module;
        let mut machine = Machine {
            world,
            module,
            privates: vec![None; module.global_variables.len()],
            private_start: Vec::new(),
            locals: Vec::new(),
            constants: vec![None; module.global_expressions.len()],
        };
        for (handle, global) in module.global_variables.iter() {
            if matches!(world.homes[handle.index()], Home::Private) {
                let start = match global.init {
                    Some(init) => machine.constant(init),
                    None => zero(module, global.ty),
                };
                machine.private_start.push((handle.index(), start));
            }
        }
        machine
    }

    fn function_named(&self, name: &str) -> Handle<Function> {
        self.module.functions.iter().find(|(_, f)| f.name.as_deref() == Some(name)).map(|(h, _)| h).expect("checked")
    }

    fn fresh_invocation(&mut self) {
        for (index, start) in &self.private_start {
            self.privates[*index] = Some(start.clone());
        }
    }

    fn set_private(&mut self, name: &str, val: Val) {
        let (handle, _) =
            self.module.global_variables.iter().find(|(_, g)| g.name.as_deref() == Some(name)).expect("the prelude's");
        self.privates[handle.index()] = Some(val);
    }

    fn call(&mut self, function: Handle<Function>, arguments: Vec<Ev>) -> Option<Val> {
        let module = self.module;
        self.run(&module.functions[function], arguments)
    }

    fn run(&mut self, function: &'m Function, arguments: Vec<Ev>) -> Option<Val> {
        let mut activation = Activation { arguments, values: vec![None; function.expressions.len()] };
        let call = self.locals.len();
        self.locals.push(Vec::with_capacity(function.local_variables.len()));
        for (_, local) in function.local_variables.iter() {
            let start = match local.init {
                Some(init) => self.eval(function, &mut activation, call, init).val(),
                None => zero(self.module, local.ty),
            };
            self.locals[call].push(start);
        }
        let flow = self.block(function, &mut activation, call, &function.body);
        self.locals.pop();
        match flow {
            Flow::Return(value) => value,
            _ => None,
        }
    }

    fn block(&mut self, function: &'m Function, act: &mut Activation, call: usize, block: &'m Block) -> Flow {
        for statement in block.iter() {
            let flow = self.statement(function, act, call, statement);
            if !matches!(flow, Flow::Next) {
                return flow;
            }
        }
        Flow::Next
    }

    fn statement(&mut self, function: &'m Function, act: &mut Activation, call: usize, statement: &'m Statement) -> Flow {
        match *statement {
            Statement::Emit(ref range) => {
                for handle in range.clone() {
                    let value = self.compute(function, act, call, handle);
                    act.values[handle.index()] = Some(value);
                }
                Flow::Next
            }
            Statement::Block(ref inner) => self.block(function, act, call, inner),
            Statement::If { condition, ref accept, ref reject } => {
                let taken = if self.eval(function, act, call, condition).val().truth() { accept } else { reject };
                self.block(function, act, call, taken)
            }
            Statement::Switch { selector, ref cases } => {
                let chosen = self.eval(function, act, call, selector).val();
                let matches = |value: &SwitchValue| match (*value, &chosen) {
                    (SwitchValue::I32(case), Val::I32(chosen)) => case == *chosen,
                    (SwitchValue::U32(case), Val::U32(chosen)) => case == *chosen,
                    _ => false,
                };
                let first = cases
                    .iter()
                    .position(|case| matches(&case.value))
                    .or_else(|| cases.iter().position(|case| case.value == SwitchValue::Default))
                    .expect("a switch has a default");
                for case in &cases[first..] {
                    match self.block(function, act, call, &case.body) {
                        Flow::Next if case.fall_through => continue,
                        Flow::Next | Flow::Break => return Flow::Next,
                        other => return other,
                    }
                }
                Flow::Next
            }
            Statement::Loop { ref body, ref continuing, break_if } => loop {
                match self.block(function, act, call, body) {
                    Flow::Break => return Flow::Next,
                    Flow::Return(value) => return Flow::Return(value),
                    Flow::Next | Flow::Continue => {}
                }
                if let Flow::Return(value) = self.block(function, act, call, continuing) {
                    return Flow::Return(value);
                }
                if let Some(condition) = break_if {
                    if self.eval(function, act, call, condition).val().truth() {
                        return Flow::Next;
                    }
                }
            },
            Statement::Break => Flow::Break,
            Statement::Continue => Flow::Continue,
            Statement::Return { value } => Flow::Return(value.map(|value| self.eval(function, act, call, value).val())),
            Statement::Store { pointer, value } => {
                let Ev::P(ptr) = self.eval(function, act, call, pointer) else { unreachable!("a store's pointer") };
                let value = self.eval(function, act, call, value).val();
                self.change(&ptr, |place| *place = value);
                Flow::Next
            }
            Statement::Call { function: callee, ref arguments, result } => {
                let arguments = arguments.iter().map(|&argument| self.eval(function, act, call, argument)).collect();
                let answer = self.call(callee, arguments);
                if let (Some(result), Some(answer)) = (result, answer) {
                    act.values[result.index()] = Some(Ev::V(answer));
                }
                Flow::Next
            }
            Statement::Atomic { pointer, ref fun, value, result } => {
                let Ev::P(ptr) = self.eval(function, act, call, pointer) else { unreachable!("an atomic's pointer") };
                let operand = self.eval(function, act, call, value).val();
                let before = self.change(&ptr, |place| {
                    let before = place.clone();
                    *place = match fun {
                        AtomicFunction::Add => binary(BinaryOperator::Add, &before, &operand),
                        AtomicFunction::Min => math2(MathFunction::Min, &before, &operand),
                        AtomicFunction::Max => math2(MathFunction::Max, &before, &operand),
                        other => unreachable!("the check refuses {other:?}"),
                    };
                    before
                });
                if let Some(result) = result {
                    act.values[result.index()] = Some(Ev::V(before));
                }
                Flow::Next
            }
            Statement::ControlBarrier(_) => {
                self.world.meet.meet(At::Barrier(statement as *const Statement as usize), || {});
                Flow::Next
            }
            Statement::WorkGroupUniformLoad { pointer, result } => {
                // As the device runs it: a barrier, the load, a barrier —
                // so no invocation writes before all have read.
                let at = At::Barrier(statement as *const Statement as usize);
                self.world.meet.meet(at, || {});
                let Ev::P(ptr) = self.eval(function, act, call, pointer) else { unreachable!("a load's pointer") };
                let value = self.look(&ptr, Val::clone);
                self.world.meet.meet(at, || {});
                act.values[result.index()] = Some(Ev::V(value));
                Flow::Next
            }
            ref other => unreachable!("the check refuses {other:?}"),
        }
    }

    /// An expression's value: kept from its Emit, or computed now (one the
    /// IR never emits — a literal, a constant, an argument, a variable).
    fn eval(&mut self, function: &'m Function, act: &mut Activation, call: usize, handle: Handle<Expression>) -> Ev {
        if let Some(value) = &act.values[handle.index()] {
            return value.clone();
        }
        let value = self.compute(function, act, call, handle);
        act.values[handle.index()] = Some(value.clone());
        value
    }

    fn compute(&mut self, function: &'m Function, act: &mut Activation, call: usize, handle: Handle<Expression>) -> Ev {
        let val = |machine: &mut Self, act: &mut Activation, h| machine.eval(function, act, call, h).val();
        Ev::V(match function.expressions[handle] {
            Expression::Literal(literal) => literal_val(literal),
            Expression::Constant(constant) => {
                let init = self.module.constants[constant].init;
                self.constant(init)
            }
            Expression::ZeroValue(ty) => zero(self.module, ty),
            Expression::Compose { ty, ref components } => {
                let parts: Vec<Val> = components.iter().map(|&c| val(self, act, c)).collect();
                compose(self.module, ty, parts)
            }
            Expression::Splat { size, value } => Val::Comp(vec![val(self, act, value); size as usize]),
            Expression::Swizzle { size, vector, pattern } => {
                let vector = val(self, act, vector);
                Val::Comp(pattern[..size as usize].iter().map(|&c| vector.parts()[c as usize].clone()).collect())
            }
            Expression::FunctionArgument(index) => return act.arguments[index as usize].clone(),
            Expression::GlobalVariable(global) => {
                return Ev::P(Ptr { root: Root::Global(global.index()), path: Vec::new() });
            }
            Expression::LocalVariable(local) => {
                return Ev::P(Ptr { root: Root::Local { call, local: local.index() }, path: Vec::new() });
            }
            Expression::Access { base, index } => {
                let index = val(self, act, index).index();
                return self.access(function, act, call, base, index);
            }
            Expression::AccessIndex { base, index } => return self.access(function, act, call, base, index),
            Expression::Load { pointer } => {
                let Ev::P(ptr) = self.eval(function, act, call, pointer) else { unreachable!("a load's pointer") };
                self.look(&ptr, Val::clone)
            }
            Expression::Unary { op, expr } => unary(op, &val(self, act, expr)),
            Expression::Binary { op, left, right } => binary(op, &val(self, act, left), &val(self, act, right)),
            Expression::Select { condition, accept, reject } => {
                select(&val(self, act, condition), &val(self, act, accept), &val(self, act, reject))
            }
            Expression::Relational { fun, argument } => {
                let parts = val(self, act, argument);
                let truths = parts.parts().iter().map(Val::truth);
                Val::Bool(match fun {
                    RelationalFunction::All => truths.into_iter().all(|t| t),
                    RelationalFunction::Any => truths.into_iter().any(|t| t),
                    other => unreachable!("the check refuses {other:?}"),
                })
            }
            Expression::Math { fun, arg, arg1, arg2, arg3 } => {
                let args: Vec<Val> =
                    [Some(arg), arg1, arg2, arg3].into_iter().flatten().map(|a| val(self, act, a)).collect();
                math(fun, &args)
            }
            Expression::As { expr, kind, .. } => cast(&val(self, act, expr), kind),
            Expression::CallResult(_) | Expression::AtomicResult { .. } | Expression::WorkGroupUniformLoadResult { .. } => {
                unreachable!("a result is set by its statement before it is read")
            }
            Expression::ArrayLength(array) => {
                let Ev::P(ptr) = self.eval(function, act, call, array) else { unreachable!("an array's pointer") };
                Val::U32(self.look(&ptr, |array| array.parts().len()) as u32)
            }
            ref other => unreachable!("the check refuses {other:?}"),
        })
    }

    /// Component `index` of `base` — a pointer further in, or the value —
    /// at the last component where `index` is past the end (Restrict).
    fn access(&mut self, function: &'m Function, act: &mut Activation, call: usize, base: Handle<Expression>, index: u32) -> Ev {
        match self.eval(function, act, call, base) {
            Ev::P(mut ptr) => {
                let last = self.look(&ptr, |place| place.parts().len()) - 1;
                ptr.path.push((index as usize).min(last));
                Ev::P(ptr)
            }
            Ev::V(value) => {
                let parts = value.parts();
                Ev::V(parts[(index as usize).min(parts.len() - 1)].clone())
            }
        }
    }

    /// `f` of the place `ptr` points at.
    fn look<R>(&self, ptr: &Ptr, f: impl FnOnce(&Val) -> R) -> R {
        let shared;
        let root = match ptr.root {
            Root::Local { call, local } => &self.locals[call][local],
            Root::Global(index) => match self.world.homes[index] {
                Home::Private => self.privates[index].as_ref().expect("a private is set"),
                Home::Fixed => self.world.fixed[index].as_ref().expect("a binding is set"),
                Home::Shared => {
                    shared = self.world.lock();
                    shared[index].as_ref().expect("a shared variable is set")
                }
            },
        };
        f(descend(root, &ptr.path))
    }

    /// `f` of the place `ptr` points at, to change it — in one hold of the
    /// lock for what the group shares, so an atomic is one step.
    fn change<R>(&mut self, ptr: &Ptr, f: impl FnOnce(&mut Val) -> R) -> R {
        match ptr.root {
            Root::Local { call, local } => f(descend_mut(&mut self.locals[call][local], &ptr.path)),
            Root::Global(index) => match self.world.homes[index] {
                Home::Private => f(descend_mut(self.privates[index].as_mut().expect("a private is set"), &ptr.path)),
                Home::Fixed => unreachable!("the bindings the host fills are read alone"),
                Home::Shared => {
                    let mut shared = self.world.lock();
                    f(descend_mut(shared[index].as_mut().expect("a shared variable is set"), &ptr.path))
                }
            },
        }
    }

    /// A module-scope constant expression's value.
    fn constant(&mut self, handle: Handle<Expression>) -> Val {
        if let Some(known) = &self.constants[handle.index()] {
            return known.clone();
        }
        let module = self.module;
        let value = match module.global_expressions[handle] {
            Expression::Literal(literal) => literal_val(literal),
            Expression::Constant(constant) => self.constant(module.constants[constant].init),
            Expression::ZeroValue(ty) => zero(module, ty),
            Expression::Compose { ty, ref components } => {
                let parts = components.iter().map(|&c| self.constant(c)).collect();
                compose(module, ty, parts)
            }
            Expression::Splat { size, value } => Val::Comp(vec![self.constant(value); size as usize]),
            ref other => unreachable!("naga folds a constant to literals, and this one is {other:?}"),
        };
        self.constants[handle.index()] = Some(value.clone());
        value
    }
}

fn descend<'v>(mut place: &'v Val, path: &[usize]) -> &'v Val {
    for &step in path {
        place = &place.parts()[step];
    }
    place
}

fn descend_mut<'v>(mut place: &'v mut Val, path: &[usize]) -> &'v mut Val {
    for &step in path {
        place = match place {
            Val::Comp(parts) => &mut parts[step],
            other => unreachable!("a pointer into {other:?}"),
        };
    }
    place
}

fn compose(module: &Module, ty: Handle<naga::Type>, parts: Vec<Val>) -> Val {
    match module.types[ty].inner {
        TypeInner::Vector { .. } => Val::Comp(
            parts
                .into_iter()
                .flat_map(|part| match part {
                    Val::Comp(inner) => inner,
                    scalar => vec![scalar],
                })
                .collect(),
        ),
        _ => Val::Comp(parts),
    }
}

fn zero(module: &Module, ty: Handle<naga::Type>) -> Val {
    let scalar = |kind: ScalarKind| match kind {
        ScalarKind::Sint => Val::I32(0),
        ScalarKind::Uint => Val::U32(0),
        ScalarKind::Bool => Val::Bool(false),
        other => unreachable!("the check refuses {other:?}"),
    };
    match module.types[ty].inner {
        TypeInner::Scalar(s) | TypeInner::Atomic(s) => scalar(s.kind),
        TypeInner::Vector { size, scalar: s } => Val::Comp(vec![scalar(s.kind); size as usize]),
        TypeInner::Array { base, size: ArraySize::Constant(count), .. } => {
            Val::Comp(vec![zero(module, base); count.get() as usize])
        }
        TypeInner::Array { size: ArraySize::Dynamic, .. } => Val::Comp(Vec::new()),
        TypeInner::Struct { ref members, .. } => Val::Comp(members.iter().map(|m| zero(module, m.ty)).collect()),
        ref other => unreachable!("the check refuses {other:?}"),
    }
}

/// The prelude's `AnicelFrame`, member by member (tests.rs holds the
/// order to the prelude's).
fn frame_val(frame: &Frame<'_>, rows: usize, values: usize) -> Val {
    let pair = |[x, y]: [i32; 2]| Val::Comp(vec![Val::I32(x), Val::I32(y)]);
    Val::Comp(vec![
        pair(frame.out_origin),
        pair(frame.out_size),
        pair(frame.in_origin),
        pair(frame.in_size),
        Val::I32(rows as i32),
        Val::I32(values as i32),
        Val::I32(frame.frame),
        Val::I32(frame.time_q16),
        Val::I32(frame.rate_q16),
        Val::I32(frame.scale_q16),
        Val::U32(frame.fuel),
        Val::U32(0),
    ])
}

fn literal_val(literal: Literal) -> Val {
    match literal {
        Literal::I32(v) => Val::I32(v),
        Literal::U32(v) => Val::U32(v),
        Literal::Bool(v) => Val::Bool(v),
        Literal::AbstractInt(v) => Val::I32(v as i32),
        other => unreachable!("the check refuses {other:?}"),
    }
}

/// `f` over the components of `a` and `b`, a scalar standing for every
/// component of a vector beside it.
fn zip(a: &Val, b: &Val, f: &dyn Fn(&Val, &Val) -> Val) -> Val {
    match (a, b) {
        (Val::Comp(a), Val::Comp(b)) => Val::Comp(a.iter().zip(b).map(|(a, b)| zip(a, b, f)).collect()),
        (Val::Comp(a), b) => Val::Comp(a.iter().map(|a| zip(a, b, f)).collect()),
        (a, Val::Comp(b)) => Val::Comp(b.iter().map(|b| zip(a, b, f)).collect()),
        (a, b) => f(a, b),
    }
}

fn map(a: &Val, f: &dyn Fn(&Val) -> Val) -> Val {
    match a {
        Val::Comp(parts) => Val::Comp(parts.iter().map(|part| map(part, f)).collect()),
        scalar => f(scalar),
    }
}

pub(crate) fn binary(op: BinaryOperator, a: &Val, b: &Val) -> Val {
    use BinaryOperator as B;
    zip(a, b, &|a, b| match (a.clone(), b.clone()) {
        (Val::I32(a), Val::I32(b)) => match op {
            B::Add => Val::I32(a.wrapping_add(b)),
            B::Subtract => Val::I32(a.wrapping_sub(b)),
            B::Multiply => Val::I32(a.wrapping_mul(b)),
            B::Divide => Val::I32(if b == 0 || (a == i32::MIN && b == -1) { a } else { a / b }),
            B::Modulo => Val::I32(if b == 0 || (a == i32::MIN && b == -1) { 0 } else { a % b }),
            B::And => Val::I32(a & b),
            B::InclusiveOr => Val::I32(a | b),
            B::ExclusiveOr => Val::I32(a ^ b),
            _ => compare(op, a.cmp(&b)),
        },
        (Val::U32(a), Val::U32(b)) => match op {
            B::Add => Val::U32(a.wrapping_add(b)),
            B::Subtract => Val::U32(a.wrapping_sub(b)),
            B::Multiply => Val::U32(a.wrapping_mul(b)),
            B::Divide => Val::U32(if b == 0 { a } else { a / b }),
            B::Modulo => Val::U32(if b == 0 { 0 } else { a % b }),
            B::And => Val::U32(a & b),
            B::InclusiveOr => Val::U32(a | b),
            B::ExclusiveOr => Val::U32(a ^ b),
            B::ShiftLeft => Val::U32(a << (b & 31)),
            B::ShiftRight => Val::U32(a >> (b & 31)),
            _ => compare(op, a.cmp(&b)),
        },
        (Val::I32(a), Val::U32(b)) => match op {
            B::ShiftLeft => Val::I32(a << (b & 31)),
            B::ShiftRight => Val::I32(a >> (b & 31)),
            other => unreachable!("i32 {other:?} u32"),
        },
        (Val::Bool(a), Val::Bool(b)) => Val::Bool(match op {
            B::And | B::LogicalAnd => a && b,
            B::InclusiveOr | B::LogicalOr => a || b,
            B::Equal => a == b,
            B::NotEqual => a != b,
            other => unreachable!("bool {other:?}"),
        }),
        (a, b) => unreachable!("{a:?} {op:?} {b:?}"),
    })
}

fn compare(op: BinaryOperator, order: std::cmp::Ordering) -> Val {
    use std::cmp::Ordering::{Equal, Greater, Less};
    Val::Bool(match op {
        BinaryOperator::Equal => order == Equal,
        BinaryOperator::NotEqual => order != Equal,
        BinaryOperator::Less => order == Less,
        BinaryOperator::LessEqual => order != Greater,
        BinaryOperator::Greater => order == Greater,
        BinaryOperator::GreaterEqual => order != Less,
        other => unreachable!("{other:?} is no comparison"),
    })
}

fn unary(op: UnaryOperator, a: &Val) -> Val {
    map(a, &|a| match (op, a.clone()) {
        (UnaryOperator::Negate, Val::I32(a)) => Val::I32(a.wrapping_neg()),
        (UnaryOperator::LogicalNot, Val::Bool(a)) => Val::Bool(!a),
        (UnaryOperator::BitwiseNot, Val::I32(a)) => Val::I32(!a),
        (UnaryOperator::BitwiseNot, Val::U32(a)) => Val::U32(!a),
        (op, a) => unreachable!("{op:?} {a:?}"),
    })
}

fn select(condition: &Val, accept: &Val, reject: &Val) -> Val {
    match condition {
        Val::Bool(true) => accept.clone(),
        Val::Bool(false) => reject.clone(),
        Val::Comp(truths) => Val::Comp(
            truths
                .iter()
                .zip(accept.parts().iter().zip(reject.parts()))
                .map(|(t, (a, r))| if t.truth() { a.clone() } else { r.clone() })
                .collect(),
        ),
        other => unreachable!("a select on {other:?}"),
    }
}

fn cast(a: &Val, kind: ScalarKind) -> Val {
    map(a, &|a| {
        let bits = match *a {
            Val::I32(v) => v as u32,
            Val::U32(v) => v,
            Val::Bool(v) => u32::from(v),
            Val::Comp(_) => unreachable!("map reaches scalars"),
        };
        match kind {
            ScalarKind::Sint => Val::I32(bits as i32),
            ScalarKind::Uint => Val::U32(bits),
            ScalarKind::Bool => Val::Bool(bits != 0),
            other => unreachable!("the check refuses {other:?}"),
        }
    })
}

fn math2(fun: MathFunction, a: &Val, b: &Val) -> Val {
    math(fun, &[a.clone(), b.clone()])
}

/// The integer builtins (check.rs `INTEGER_MATHS`), as WGSL defines them.
fn math(fun: MathFunction, args: &[Val]) -> Val {
    use MathFunction as M;
    let a = &args[0];
    match fun {
        M::Abs => map(a, &|a| match *a {
            Val::I32(v) => Val::I32(v.wrapping_abs()),
            ref other => other.clone(),
        }),
        M::Min | M::Max => zip(a, &args[1], &|a, b| {
            let less = matches!(binary(BinaryOperator::Less, a, b), Val::Bool(true));
            if less == (fun == M::Min) { a.clone() } else { b.clone() }
        }),
        M::Clamp => math2(M::Min, &math2(M::Max, a, &args[1]), &args[2]),
        M::Sign => map(a, &|a| match *a {
            Val::I32(v) => Val::I32(v.signum()),
            ref other => unreachable!("sign of {other:?}"),
        }),
        M::Dot => {
            let products = binary(BinaryOperator::Multiply, a, &args[1]);
            let mut parts = products.parts().iter();
            let first = parts.next().expect("a vector").clone();
            parts.fold(first, |sum, part| binary(BinaryOperator::Add, &sum, part))
        }
        M::CountTrailingZeros => bits(a, &|v| v.trailing_zeros()),
        M::CountLeadingZeros => bits(a, &|v| v.leading_zeros()),
        M::CountOneBits => bits(a, &|v| v.count_ones()),
        M::ReverseBits => bits(a, &|v| v.reverse_bits()),
        M::FirstTrailingBit => bits(a, &|v| if v == 0 { u32::MAX } else { v.trailing_zeros() }),
        M::FirstLeadingBit => map(a, &|a| match *a {
            Val::U32(v) => Val::U32(if v == 0 { u32::MAX } else { 31 - v.leading_zeros() }),
            Val::I32(v) => Val::I32(match v {
                0 | -1 => -1,
                v if v < 0 => 31 - v.leading_ones() as i32,
                v => 31 - v.leading_zeros() as i32,
            }),
            ref other => unreachable!("firstLeadingBit of {other:?}"),
        }),
        M::ExtractBits => {
            let (offset, count) = (args[1].index().min(32), args[2].index());
            let count = count.min(32 - offset);
            map(a, &|a| match *a {
                _ if count == 0 => zero_like(a),
                Val::U32(v) => Val::U32((v >> offset) & (u32::MAX >> (32 - count))),
                Val::I32(v) => Val::I32((v << (32 - offset - count)) >> (32 - count)),
                ref other => unreachable!("extractBits of {other:?}"),
            })
        }
        M::InsertBits => {
            let (offset, count) = (args[2].index().min(32), args[3].index());
            let count = count.min(32 - offset);
            let mask = if count == 0 { 0 } else { (u32::MAX >> (32 - count)) << offset };
            zip(a, &args[1], &|e, new| {
                let (e_bits, new_bits) = (cast(e, ScalarKind::Uint).index(), cast(new, ScalarKind::Uint).index());
                let bits = (e_bits & !mask) | ((new_bits << offset) & mask);
                match e {
                    Val::I32(_) => Val::I32(bits as i32),
                    _ => Val::U32(bits),
                }
            })
        }
        M::Pack4xU8 | M::Pack4xI8 | M::Pack4xU8Clamp | M::Pack4xI8Clamp => {
            let word = a.parts().iter().enumerate().fold(0u32, |word, (i, part)| {
                let byte = match (fun, part) {
                    (M::Pack4xU8Clamp, Val::U32(v)) => (*v).min(255),
                    (M::Pack4xI8Clamp, Val::I32(v)) => ((*v).clamp(-128, 127) as u32) & 0xff,
                    (_, part) => part.index() & 0xff,
                };
                word | (byte << (8 * i))
            });
            Val::U32(word)
        }
        M::Unpack4xU8 => Val::Comp((0..4).map(|i| Val::U32((a.index() >> (8 * i)) & 0xff)).collect()),
        M::Unpack4xI8 => Val::Comp((0..4).map(|i| Val::I32(((a.index() >> (8 * i)) as u8 as i8).into())).collect()),
        M::Dot4U8Packed => {
            let (x, y) = (a.index(), args[1].index());
            Val::U32((0..4).map(|i| ((x >> (8 * i)) & 0xff) * ((y >> (8 * i)) & 0xff)).sum())
        }
        M::Dot4I8Packed => {
            let (x, y) = (a.index(), args[1].index());
            let byte = |w: u32, i: u32| i32::from((w >> (8 * i)) as u8 as i8);
            Val::I32((0..4).map(|i| byte(x, i) * byte(y, i)).sum())
        }
        other => unreachable!("the check refuses {other:?}"),
    }
}

/// `f` over the bits of an integer, keeping its type.
fn bits(a: &Val, f: &dyn Fn(u32) -> u32) -> Val {
    map(a, &|a| match *a {
        Val::U32(v) => Val::U32(f(v)),
        Val::I32(v) => Val::I32(f(v as u32) as i32),
        ref other => unreachable!("bits of {other:?}"),
    })
}

fn zero_like(a: &Val) -> Val {
    match a {
        Val::I32(_) => Val::I32(0),
        _ => Val::U32(0),
    }
}
