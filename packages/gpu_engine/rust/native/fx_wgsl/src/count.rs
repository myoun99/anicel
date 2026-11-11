//! The charges (design 2/3 ②, 🗣️Q1 「명령 수 — 정한 수만큼 실행하면
//! 끊는다」 · Q19 「화소 하나의 몫」): the top of every loop of the plugin's
//! spends what one turn costs from the invocation's share, and breaks when
//! the share cannot pay — `anicel_host_spend` in the prelude. A loop of the
//! render that waits at a barrier is charged with
//! `anicel_host_spend_together` instead: each invocation pays from its own
//! share, and the group breaks when any of it could not (Q6 ⓐ), so none is
//! left waiting at a barrier the others no longer reach.
//!
//! A turn's cost is the loop's size in IR, read from the plugin's own
//! module: one for every statement and every expression its body and
//! continuing emit, and for every call the straight size of what it calls
//! (a callee's loops pay for themselves), never less than one. The source
//! fixes it, so a plugin is cut at the same turn on every device and on the
//! CPU, which runs this same counted text (run.rs).
//!
//! The charge goes in as text, just inside the loop's `{`, and the counted
//! text is read again (lib.rs `open`): what the device compiles is WGSL the
//! parser and validator saw, not IR this crate assembled.
//!
//! 🔧Each `pack4xU8` and `pack4xU8Clamp` of the plugin's is called through
//! the prelude's `anicel_host_` function of that name: naga 30.0.1's HLSL
//! writer (back/hlsl/writer.rs, `Function::Pack4xU8`) writes an unsigned
//! pack as `(v[0] & 0xFF) | ((v[1] & 0xFF) << 8) | …` with no parentheses
//! around it — only the signed packs are wrapped, in `uint(…)` — so on D3D12
//! `x ^ pack4xU8Clamp(v)` came out `(x ^ v[0]) | …` (kernels/plugin's
//! parity test, 2026-11-08). A call's result is a value of its own in every
//! backend. ⚠️AT EVERY NAGA UPGRADE: when its HLSL writer parenthesizes the
//! unsigned packs, delete this and the prelude's two functions.

use std::collections::HashMap;
use std::ops::Range;

use naga::{
    BinaryOperator, Binding, Block, BuiltIn, EntryPoint, Expression, Function, Handle, MathFunction, Module, Statement,
};

use crate::{RENDER, scan};

/// The plugin's source with its charges, its unsigned packs called through
/// the prelude, its shifts' amounts held under 32, and `anicel_host_enter`
/// first in its render — and what a turn of each of its loops costs, in
/// the order they are written.
pub(crate) fn count(module: &Module, plugin: &str) -> (String, Vec<u64>) {
    let mut sizes = Sizes { module, straight: HashMap::new(), turns: Vec::new() };
    let words = scan::words(plugin);
    let mut charges = Vec::new();
    let mut edits = Vec::new();
    for (handle, function) in module.functions.iter() {
        if crate::check::is_plugins(module.functions.get_span(handle), plugin) {
            sizes.charge(&function.body, plugin, false, &mut charges);
            unsigned_packs(function, &mut charges);
            masked_shifts(function, &words, &mut edits);
        }
    }
    let render = module.entry_points.iter().find(|entry| entry.name == RENDER).expect("the check found it");
    sizes.charge(&render.function.body, plugin, true, &mut charges);
    unsigned_packs(&render.function, &mut charges);
    masked_shifts(&render.function, &words, &mut edits);
    let (renamed, taken) = chunked_ids(render, plugin);
    edits.extend(renamed);
    let enter = format!(" anicel_host_enter({});", invocation_name(&render.function));
    charges.push((render_open(plugin), format!("{taken}{enter}")));
    edits.extend(charges.into_iter().map(|(at, text)| (at, (2, 0), text)));
    edits.sort_by_key(|&(at, order, _)| (at, order));
    let mut counted = String::with_capacity(plugin.len() + edits.len() * 48);
    let mut written = 0;
    for (at, _, text) in edits {
        counted.push_str(&plugin[written..at]);
        counted.push_str(&text);
        written = at;
    }
    counted.push_str(&plugin[written..]);
    sizes.turns.sort_unstable();
    (counted, sizes.turns.into_iter().map(|(_, turn)| turn).collect())
}

/// The render's ids as one dispatch of the whole run would hand them, in a
/// run dispatched in chunks (an-endless-plugin-stalls-the-app 11-10 16:44
/// ②: the plugin sees what it would see undivided): its
/// `global_invocation_id`, `workgroup_id` and `num_workgroups` arguments
/// renamed `anicel_host_raw_…`, and each taken again under its own name
/// just inside the body — the chunk's own and where the chunk starts
/// (`anicel_host_frame.chunk`), or the run's groups from its output's
/// size. The renames, and the text that takes them again.
fn chunked_ids(render: &EntryPoint, plugin: &str) -> (Vec<(usize, (u8, usize), String)>, String) {
    let [across, down, _] = render.workgroup_size;
    let signature = scan::function_at(plugin, RENDER).expect("the check found it");
    let words: Vec<_> =
        scan::words(&plugin[..render_open(plugin)]).into_iter().filter(|&(at, _)| at >= signature).collect();
    let (mut renamed, mut taken) = (Vec::new(), String::new());
    for argument in &render.function.arguments {
        let (Some(Binding::BuiltIn(builtin)), Some(name)) = (argument.binding.as_ref(), argument.name.as_deref())
        else {
            continue;
        };
        let raw = format!("anicel_host_raw_{name}");
        let (written, again) = match builtin {
            BuiltIn::GlobalInvocationId => (
                "global_invocation_id",
                format!("{raw} + vec3<u32>(anicel_host_frame.chunk * vec2<u32>({across}u, {down}u), 0u)"),
            ),
            BuiltIn::WorkGroupId => ("workgroup_id", format!("{raw} + vec3<u32>(anicel_host_frame.chunk, 0u)")),
            BuiltIn::NumWorkGroups => (
                "num_workgroups",
                format!(
                    "vec3<u32>((vec2<u32>(anicel_host_frame.out_size) + vec2<u32>({}u, {}u)) \
                     / vec2<u32>({across}u, {down}u), 1u)",
                    across - 1,
                    down - 1,
                ),
            ),
            _ => continue,
        };
        let at = words
            .windows(3)
            .find(|word| word[0].1 == "builtin" && word[1].1 == written && word[2].1 == name)
            .map(|word| word[2].0)
            .expect("the parser read the argument as it is written");
        renamed.push((at, (2, 0), "anicel_host_raw_".to_string()));
        taken.push_str(&format!(" let {name} = {again};"));
    }
    (renamed, taken)
}

/// Each shift's amount `function` writes, wrapped as `((amount) % 32u)`:
/// the amount WGSL shifts by — taken mod the word's 32 bits — held there
/// on every device. 🔧naga 30's SPIR-V and MSL writers hand the amount on
/// as it is, and a shift by 32 or more is undefined in both
/// (an-endless-plugin-stalls-the-app 11-10 16:44 「앞서 받은 것」). `%`, not
/// `& 31u`: a vector's amount takes a scalar `%`, not a scalar `&`.
///
/// Where a closing and an opening land on one place, the closings go
/// first, the innermost of them first; the openings then, the outermost
/// first — so wrapped amounts nest as the shifts do.
fn masked_shifts(function: &Function, words: &[(usize, &str)], edits: &mut Vec<(usize, (u8, usize), String)>) {
    for (handle, expression) in function.expressions.iter() {
        if let Expression::Binary { op: BinaryOperator::ShiftLeft | BinaryOperator::ShiftRight, right, .. } = *expression
            && let Some(shift) = function.expressions.get_span(handle).to_range()
        {
            let amount = amount_written(function.expressions.get_span(right).to_range(), &shift, words);
            edits.push((amount.start, (1, usize::MAX - amount.end), "((".to_string()));
            edits.push((amount.end, (0, usize::MAX - amount.start), ") % 32u)".to_string()));
        }
    }
}

/// Where `shift`'s amount is written: the amount's own place where that
/// lies in the shift, and otherwise the name the shift ends with. 🔧naga
/// 30 hands a name's value the place it was declared at — a `let`'s its
/// initializer's, an argument's its signature's — or none, a `var`'s load
/// (front/wgsl/lower `LocalVariable(var), Span::UNDEFINED`); wrapping
/// that place changed the `let` for every other use of it (the integers
/// test, 2026-11-11). A shift's operands are unary expressions, so an
/// amount written by name is that name, in parentheses or not.
fn amount_written(own: Option<Range<usize>>, shift: &Range<usize>, words: &[(usize, &str)]) -> Range<usize> {
    match own {
        Some(own) if shift.start <= own.start && own.end <= shift.end => own,
        _ => {
            let &(at, name) = words
                .iter()
                .rev()
                .find(|&&(at, _)| shift.start <= at && at < shift.end)
                .expect("a shift ends with its amount");
            at..at + name.len()
        }
    }
}

/// The prelude's name before each unsigned pack `function` calls — where
/// its call starts, the builtin's name.
fn unsigned_packs(function: &Function, edits: &mut Vec<(usize, String)>) {
    for (handle, expression) in function.expressions.iter() {
        if let Expression::Math { fun: MathFunction::Pack4xU8 | MathFunction::Pack4xU8Clamp, .. } = expression {
            let call = function.expressions.get_span(handle).to_range().expect("a call the parser read has a place");
            edits.push((call.start, "anicel_host_".to_string()));
        }
    }
}

/// Just inside the render's body.
fn render_open(plugin: &str) -> usize {
    scan::function_at(plugin, RENDER)
        .and_then(|declared| scan::body_open(plugin, declared))
        .expect("the check found the render's body")
}

/// The name the render gives its `global_invocation_id`.
fn invocation_name(render: &Function) -> &str {
    render
        .arguments
        .iter()
        .find(|argument| crate::check::is_invocation(argument))
        .and_then(|argument| argument.name.as_deref())
        .expect("the check found it")
}

/// What a turn costs: the sizes, with each function's straight size kept
/// once it is known, and each loop's turn where its charge goes.
struct Sizes<'m> {
    module: &'m Module,
    straight: HashMap<Handle<Function>, u64>,
    turns: Vec<(usize, u64)>,
}

impl Sizes<'_> {
    /// Records a charge at the top of every loop in `block`, nested ones
    /// included.
    fn charge(&mut self, block: &Block, plugin: &str, render: bool, charges: &mut Vec<(usize, String)>) {
        for (statement, span) in block.span_iter() {
            match statement {
                Statement::Loop { body, continuing, break_if } => {
                    let turn = (self.size(body) + self.size(continuing) + u64::from(break_if.is_some())).max(1);
                    let start = span.to_range().expect("a loop the parser read has a place").start;
                    let open = scan::body_open(plugin, start).expect("a loop has a body");
                    let together = render && (crate::group::holds_barrier(body) || crate::group::holds_barrier(continuing));
                    let spend = if together { "anicel_host_spend_together" } else { "anicel_host_spend" };
                    charges.push((open, format!(" if {spend}({turn}u) {{ break; }}")));
                    self.turns.push((open, turn));
                    self.charge(body, plugin, render, charges);
                    self.charge(continuing, plugin, render, charges);
                }
                Statement::Block(inner) => self.charge(inner, plugin, render, charges),
                Statement::If { accept, reject, .. } => {
                    self.charge(accept, plugin, render, charges);
                    self.charge(reject, plugin, render, charges);
                }
                Statement::Switch { cases, .. } => {
                    for case in cases {
                        self.charge(&case.body, plugin, render, charges);
                    }
                }
                _ => {}
            }
        }
    }

    /// The straight size of `block`: its statements and emitted
    /// expressions, what its calls call, and a nested loop as one.
    fn size(&mut self, block: &Block) -> u64 {
        block
            .iter()
            .map(|statement| {
                1 + match statement {
                    Statement::Emit(range) => range.clone().count() as u64,
                    Statement::Block(inner) => self.size(inner),
                    Statement::If { accept, reject, .. } => self.size(accept) + self.size(reject),
                    Statement::Switch { cases, .. } => cases.iter().map(|case| self.size(&case.body)).sum(),
                    Statement::Call { function, .. } => self.called(*function),
                    _ => 0,
                }
            })
            .sum()
    }

    fn called(&mut self, function: Handle<Function>) -> u64 {
        if let Some(&known) = self.straight.get(&function) {
            return known;
        }
        let module = self.module;
        let size = self.size(&module.functions[function].body);
        self.straight.insert(function, size);
        size
    }
}
