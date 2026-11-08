//! Which values every invocation of a group holds alike, and which loops
//! every invocation leaves together (Q6 ⓐ: 「끊는 판단은 무리 전체가 한
//! 번에」 — a loop that waits at a barrier must be left by the whole group
//! at once, or the ones left behind wait for ever).
//!
//! ↩️naga's own analysis answers neither for a loop: it takes every local
//! variable for non-uniform (valid/analyzer.rs, `E::LocalVariable(_) =>
//! non_uniform_result: Some`), so `for (var i = 0; i < 4; i++)` could not be
//! shown uniform with it, and it does not look at a loop's breaks at all
//! (`S::Break => FunctionUniformity::new()`) — measured 2026-11-08.
//!
//! This one is the greatest fixed point: every local and every loop starts
//! uniform, and one that a store or an exit shows otherwise is lowered,
//! until nothing changes. A local is uniform when every store to it is a
//! uniform value in uniform control flow; a loop is, when every way out of
//! it — a break or continue of its own, a return, its `break if` — is
//! taken under uniform conditions alone.

use std::collections::HashMap;

use naga::{AddressSpace, Binding, Block, BuiltIn, Expression, Function, Handle, Module, Span, Statement};

/// The prelude's functions whose answer is the same for every invocation
/// given the same arguments: the values and the moment.
const UNIFORM_PRELUDE: [&str; 5] = ["anicel_value", "anicel_frame", "anicel_time", "anicel_rate", "anicel_scale"];

/// The answer for one function.
pub(crate) struct Uniformity {
    /// Each loop, by its body's place, and whether the group leaves it
    /// together.
    loops: HashMap<*const Block, bool>,
    /// The first barrier some invocations may pass by.
    apart: Option<Span>,
}

impl Uniformity {
    /// Whether the group leaves the loop whose body is `body` together.
    pub(crate) fn leaves_together(&self, body: &Block) -> bool {
        self.loops.get(&(body as *const Block)).copied().unwrap_or(false)
    }

    /// The first barrier that stands where control flow is not uniform —
    /// after a return some invocations took, or under a condition they do
    /// not hold alike — if one does. naga's validator asks this too, with
    /// its own analysis; this one does not lean on it.
    pub(crate) fn barrier_apart(&self) -> Option<Span> {
        self.apart
    }
}

/// Analyses `function`, its arguments uniform where `arguments` says, and
/// every plugin function it calls, each answer kept in `callees`.
pub(crate) fn analyse(
    module: &Module,
    function: &Function,
    arguments: &[bool],
    callees: &mut HashMap<Handle<Function>, bool>,
) -> Uniformity {
    let mut walk = Walk::new(module, function, arguments.to_vec(), callees);
    loop {
        walk.changed = false;
        walk.apart = None;
        walk.memo = vec![None; function.expressions.len()];
        walk.block(&function.body, true);
        if !walk.changed {
            break;
        }
    }
    Uniformity { loops: walk.loops, apart: walk.apart }
}

/// Whether `render`'s argument `index` is the same for the whole group.
pub(crate) fn uniform_argument(function: &Function, index: usize) -> bool {
    matches!(
        function.arguments[index].binding,
        Some(Binding::BuiltIn(BuiltIn::WorkGroupId | BuiltIn::NumWorkGroups))
    )
}

struct Walk<'m, 'c> {
    module: &'m Module,
    function: &'m Function,
    arguments: Vec<bool>,
    locals: Vec<bool>,
    loops: HashMap<*const Block, bool>,
    /// Each call's result, with what was called and with what.
    calls: HashMap<Handle<Expression>, (Handle<Function>, &'m [Handle<Expression>])>,
    callees: &'c mut HashMap<Handle<Function>, bool>,
    memo: Vec<Option<bool>>,
    /// Whether this function's every return gives a uniform value in
    /// uniform control flow.
    returns_alike: bool,
    apart: Option<Span>,
    changed: bool,
}

impl<'m, 'c> Walk<'m, 'c> {
    fn new(
        module: &'m Module,
        function: &'m Function,
        arguments: Vec<bool>,
        callees: &'c mut HashMap<Handle<Function>, bool>,
    ) -> Self {
        let mut walk = Walk {
            module,
            function,
            arguments,
            locals: vec![true; function.local_variables.len()],
            loops: HashMap::new(),
            calls: HashMap::new(),
            callees,
            memo: Vec::new(),
            returns_alike: true,
            apart: None,
            changed: false,
        };
        walk.gather(&function.body);
        walk
    }

    /// The calls and loops, once; a local handed to a call by pointer is
    /// one the callee may write, and is not taken for uniform.
    fn gather(&mut self, block: &'m Block) {
        for statement in block.iter() {
            match statement {
                Statement::Call { function: callee, arguments, result } => {
                    if let Some(result) = result {
                        self.calls.insert(*result, (*callee, arguments.as_slice()));
                    }
                    for &argument in arguments {
                        if let Some(local) = self.local_root(argument) {
                            self.locals[local] = false;
                        }
                    }
                    self.callee(*callee);
                }
                Statement::Block(inner) => self.gather(inner),
                Statement::If { accept, reject, .. } => {
                    self.gather(accept);
                    self.gather(reject);
                }
                Statement::Switch { cases, .. } => cases.iter().for_each(|case| self.gather(&case.body)),
                Statement::Loop { body, continuing, .. } => {
                    self.loops.insert(body as *const Block, true);
                    self.gather(body);
                    self.gather(continuing);
                }
                _ => {}
            }
        }
    }

    /// Whether `callee` answers alike for alike arguments.
    fn callee(&mut self, callee: Handle<Function>) -> bool {
        if let Some(&known) = self.callees.get(&callee) {
            return known;
        }
        let function = &self.module.functions[callee];
        let name = function.name.as_deref().unwrap_or("");
        let alike = if name.starts_with("anicel_") {
            UNIFORM_PRELUDE.contains(&name)
        } else {
            let mut inner = Walk::new(self.module, function, vec![true; function.arguments.len()], self.callees);
            loop {
                inner.changed = false;
                inner.returns_alike = true;
                inner.memo = vec![None; function.expressions.len()];
                inner.block(&function.body, true);
                if !inner.changed {
                    break;
                }
            }
            inner.returns_alike
        };
        self.callees.insert(callee, alike);
        alike
    }

    fn lower_local(&mut self, local: usize) {
        if self.locals[local] {
            self.locals[local] = false;
            self.changed = true;
        }
    }

    /// Walks `block` in control flow uniform or not; answers whether the
    /// flow after it still is.
    fn block(&mut self, block: &'m Block, mut alike: bool) -> bool {
        for (statement, span) in block.span_iter() {
            let barrier = matches!(statement, Statement::ControlBarrier(_) | Statement::WorkGroupUniformLoad { .. });
            if barrier && !alike && self.apart.is_none() {
                self.apart = Some(*span);
            }
            alike = self.statement(statement, alike);
        }
        alike
    }

    fn statement(&mut self, statement: &'m Statement, alike: bool) -> bool {
        match *statement {
            Statement::Block(ref inner) => self.block(inner, alike),
            Statement::If { condition, ref accept, ref reject } => {
                let uniform = self.expr(condition);
                self.block(accept, alike && uniform);
                self.block(reject, alike && uniform);
                alike && (uniform || !(leaves(accept) || leaves(reject)))
            }
            Statement::Switch { selector, ref cases } => {
                let uniform = self.expr(selector);
                for case in cases {
                    self.block(&case.body, alike && uniform);
                }
                alike && (uniform || !cases.iter().any(|case| leaves(&case.body)))
            }
            Statement::Loop { ref body, ref continuing, break_if } => {
                let key = body as *const Block;
                let together = self.loops[&key];
                self.block(body, alike && together);
                self.block(continuing, alike && together);
                let exits = self.exits_alike(body, true, false, false)
                    && self.exits_alike(continuing, true, false, false)
                    && break_if.is_none_or(|condition| self.expr(condition));
                if together && !exits {
                    self.loops.insert(key, false);
                    self.changed = true;
                }
                // Past the loop the group is together again — unless some
                // returned from inside it and the others did not.
                alike && (self.loops[&key] || !(leaves_but_by_breaking(body) || leaves_but_by_breaking(continuing)))
            }
            Statement::Store { pointer, value } => {
                if let Some(local) = self.local_root(pointer) {
                    if !(alike && self.expr(value) && self.chain_alike(pointer)) {
                        self.lower_local(local);
                    }
                }
                alike
            }
            Statement::Return { value } => {
                if !(alike && value.is_none_or(|value| self.expr(value))) {
                    self.returns_alike = false;
                }
                alike
            }
            _ => alike,
        }
    }

    /// Whether every way out of the loop being walked in `block` is taken
    /// under uniform conditions alone.
    fn exits_alike(&mut self, block: &'m Block, path: bool, in_switch: bool, in_inner: bool) -> bool {
        block.iter().all(|statement| match *statement {
            Statement::Break => in_switch || in_inner || path,
            Statement::Continue => in_inner || path,
            Statement::Return { .. } => path,
            Statement::Block(ref inner) => self.exits_alike(inner, path, in_switch, in_inner),
            Statement::If { condition, ref accept, ref reject } => {
                let path = path && self.expr(condition);
                self.exits_alike(accept, path, in_switch, in_inner) && self.exits_alike(reject, path, in_switch, in_inner)
            }
            Statement::Switch { selector, ref cases } => {
                let path = path && self.expr(selector);
                cases.iter().all(|case| self.exits_alike(&case.body, path, true, in_inner))
            }
            Statement::Loop { ref body, ref continuing, .. } => {
                let path = path && self.loops[&(body as *const Block)];
                self.exits_alike(body, path, false, true) && self.exits_alike(continuing, path, false, true)
            }
            _ => true,
        })
    }

    /// The local a pointer reaches into, if it reaches into one.
    fn local_root(&self, pointer: Handle<Expression>) -> Option<usize> {
        match self.function.expressions[pointer] {
            Expression::LocalVariable(local) => Some(local.index()),
            Expression::Access { base, .. } | Expression::AccessIndex { base, .. } => self.local_root(base),
            _ => None,
        }
    }

    /// Whether every index on the way to the place is uniform.
    fn chain_alike(&mut self, pointer: Handle<Expression>) -> bool {
        let function = self.function;
        match function.expressions[pointer] {
            Expression::Access { base, index } => self.expr(index) && self.chain_alike(base),
            Expression::AccessIndex { base, .. } => self.chain_alike(base),
            _ => true,
        }
    }

    /// Whether the value a load reads is the same for the whole group.
    fn load_alike(&mut self, pointer: Handle<Expression>) -> bool {
        let function = self.function;
        match function.expressions[pointer] {
            Expression::LocalVariable(local) => self.locals[local.index()],
            Expression::GlobalVariable(global) => self.module.global_variables[global].space == AddressSpace::Uniform,
            Expression::Access { base, index } => self.expr(index) && self.load_alike(base),
            Expression::AccessIndex { base, .. } => self.load_alike(base),
            _ => false,
        }
    }

    /// Whether `handle`'s value is the same for the whole group.
    fn expr(&mut self, handle: Handle<Expression>) -> bool {
        if let Some(known) = self.memo[handle.index()] {
            return known;
        }
        let function = self.function;
        let alike = match function.expressions[handle] {
            Expression::Literal(_)
            | Expression::Constant(_)
            | Expression::ZeroValue(_)
            | Expression::GlobalVariable(_)
            | Expression::LocalVariable(_)
            | Expression::ArrayLength(_)
            | Expression::WorkGroupUniformLoadResult { .. } => true,
            Expression::FunctionArgument(index) => self.arguments[index as usize],
            Expression::Load { pointer } => self.load_alike(pointer),
            Expression::Access { base, index } => self.expr(base) && self.expr(index),
            Expression::AccessIndex { base, .. } => self.expr(base),
            Expression::Splat { value, .. } => self.expr(value),
            Expression::Swizzle { vector, .. } => self.expr(vector),
            Expression::Unary { expr, .. } | Expression::As { expr, .. } => self.expr(expr),
            Expression::Relational { argument, .. } => self.expr(argument),
            Expression::Binary { left, right, .. } => self.expr(left) && self.expr(right),
            Expression::Select { condition, accept, reject } => {
                self.expr(condition) && self.expr(accept) && self.expr(reject)
            }
            Expression::Compose { ref components, .. } => components.iter().all(|&c| self.expr(c)),
            Expression::Math { arg, arg1, arg2, arg3, .. } => {
                [Some(arg), arg1, arg2, arg3].into_iter().flatten().all(|a| self.expr(a))
            }
            Expression::CallResult(_) => match self.calls.get(&handle).copied() {
                Some((callee, arguments)) => self.callee(callee) && arguments.iter().all(|&a| self.expr(a)),
                None => false,
            },
            _ => false,
        };
        self.memo[handle.index()] = Some(alike);
        alike
    }
}

/// Whether `block` holds a way out of what encloses it.
fn leaves(block: &Block) -> bool {
    block.iter().any(|statement| match statement {
        Statement::Break | Statement::Continue | Statement::Return { .. } => true,
        Statement::Block(inner) => leaves(inner),
        Statement::If { accept, reject, .. } => leaves(accept) || leaves(reject),
        Statement::Switch { cases, .. } => cases.iter().any(|case| leaves(&case.body)),
        Statement::Loop { body, continuing, .. } => leaves_but_by_breaking(body) || leaves_but_by_breaking(continuing),
        _ => false,
    })
}

/// Whether a loop's `block` leaves more than the loop — a return.
fn leaves_but_by_breaking(block: &Block) -> bool {
    block.iter().any(|statement| match statement {
        Statement::Return { .. } => true,
        Statement::Block(inner) => leaves_but_by_breaking(inner),
        Statement::If { accept, reject, .. } => leaves_but_by_breaking(accept) || leaves_but_by_breaking(reject),
        Statement::Switch { cases, .. } => cases.iter().any(|case| leaves_but_by_breaking(&case.body)),
        Statement::Loop { body, continuing, .. } => leaves_but_by_breaking(body) || leaves_but_by_breaking(continuing),
        _ => false,
    })
}
