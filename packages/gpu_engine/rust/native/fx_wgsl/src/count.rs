//! The charges (design 2/3 ②, 🗣️Q1 「명령 수 — 정한 수만큼 실행하면
//! 끊는다」 · Q5 「화소마다 몫」): the top of every loop of the plugin's
//! spends what one turn costs from the invocation's share, and breaks when
//! the share cannot pay — `anicel_host_spend` in the prelude.
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

use std::collections::HashMap;

use naga::{Block, Function, Handle, Module, Statement};

use crate::{RENDER, scan};

/// The plugin's source with its charges, and `anicel_host_enter` first in
/// its render.
pub(crate) fn count(module: &Module, plugin: &str) -> String {
    let mut sizes = Sizes { module, straight: HashMap::new() };
    let mut charges = Vec::new();
    for (handle, function) in module.functions.iter() {
        if crate::check::is_plugins(module.functions.get_span(handle), plugin) {
            sizes.charge(&function.body, plugin, &mut charges);
        }
    }
    let render = module.entry_points.iter().find(|entry| entry.name == RENDER).expect("the check found it");
    sizes.charge(&render.function.body, plugin, &mut charges);
    charges.push((render_open(plugin), format!(" anicel_host_enter({});", invocation_name(&render.function))));
    charges.sort_by_key(|(at, _)| *at);
    let mut counted = String::with_capacity(plugin.len() + charges.len() * 48);
    let mut written = 0;
    for (at, text) in charges {
        counted.push_str(&plugin[written..at]);
        counted.push_str(&text);
        written = at;
    }
    counted.push_str(&plugin[written..]);
    counted
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
/// once it is known.
struct Sizes<'m> {
    module: &'m Module,
    straight: HashMap<Handle<Function>, u64>,
}

impl Sizes<'_> {
    /// Records a charge at the top of every loop in `block`, nested ones
    /// included.
    fn charge(&mut self, block: &Block, plugin: &str, charges: &mut Vec<(usize, String)>) {
        for (statement, span) in block.span_iter() {
            match statement {
                Statement::Loop { body, continuing, break_if } => {
                    let turn = (self.size(body) + self.size(continuing) + u64::from(break_if.is_some())).max(1);
                    let start = span.to_range().expect("a loop the parser read has a place").start;
                    let open = scan::body_open(plugin, start).expect("a loop has a body");
                    charges.push((open, format!(" if anicel_host_spend({turn}u) {{ break; }}")));
                    self.charge(body, plugin, charges);
                    self.charge(continuing, plugin, charges);
                }
                Statement::Block(inner) => self.charge(inner, plugin, charges),
                Statement::If { accept, reject, .. } => {
                    self.charge(accept, plugin, charges);
                    self.charge(reject, plugin, charges);
                }
                Statement::Switch { cases, .. } => {
                    for case in cases {
                        self.charge(&case.body, plugin, charges);
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
