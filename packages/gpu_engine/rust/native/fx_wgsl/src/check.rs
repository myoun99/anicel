//! What a plugin may be (design 2/3 ③): over naga's own parse and the
//! validator wgpu runs, the integer law and the host's shape.
//!
//! - No float anywhere — no float type, and no expression whose type is
//!   one (so a float literal, `f32(x)`, float maths and derivatives are all
//!   caught): the engine's integer law, the same picture on every device.
//! - No texture, sampler or other handle: the pictures come through the
//!   prelude alone.
//! - A group's shared memory, `workgroupBarrier` and atomics (Q6 answer:
//!   「바로 다음 레인에서 … ⓐⓑⓒ 와 함께 연다」), in `anicel_render` alone,
//!   under group.rs: atomics are an add, a min or a max whose result is
//!   not read (ⓑ); no `storageBarrier` or `textureBarrier`.
//! - One entry point, `@compute fn anicel_render`, of at most
//!   [`MOST_INVOCATIONS`] invocations a group and one deep, taking its
//!   `global_invocation_id`; and `fn anicel_reach() -> u32`.
//! - The `anicel_` names are the host's: a plugin declares none but those
//!   two, and names no `anicel_host_` function and none of the prelude's
//!   bindings.
//! - Only what the CPU's run (run.rs) runs: the integer builtins listed in
//!   [`INTEGER_MATHS`], no subgroup operation, no override.

use naga::valid::{FunctionInfo, ModuleInfo};
use naga::{
    AddressSpace, AtomicFunction, Binding, BuiltIn, Expression, Function, FunctionArgument, MathFunction, Module, ScalarKind,
    ShaderStage, Span, Statement, TypeInner,
};

use crate::{MOST_INVOCATIONS, REACH, RENDER, Refusal};

/// The builtins a plugin may call, every one on integers, and every one
/// the CPU's run computes as WGSL defines it.
pub(crate) const INTEGER_MATHS: [MathFunction; 22] = [
    MathFunction::Abs,
    MathFunction::Min,
    MathFunction::Max,
    MathFunction::Clamp,
    MathFunction::Sign,
    MathFunction::Dot,
    MathFunction::CountTrailingZeros,
    MathFunction::CountLeadingZeros,
    MathFunction::CountOneBits,
    MathFunction::ReverseBits,
    MathFunction::ExtractBits,
    MathFunction::InsertBits,
    MathFunction::FirstTrailingBit,
    MathFunction::FirstLeadingBit,
    MathFunction::Pack4xI8,
    MathFunction::Pack4xU8,
    MathFunction::Pack4xI8Clamp,
    MathFunction::Pack4xU8Clamp,
    MathFunction::Unpack4xI8,
    MathFunction::Unpack4xU8,
    MathFunction::Dot4I8Packed,
    MathFunction::Dot4U8Packed,
];

/// The builtins an entry point may take — none a device chooses for itself
/// (a subgroup's size is one, and is refused).
const INVOCATION_BUILTINS: [BuiltIn; 5] = [
    BuiltIn::GlobalInvocationId,
    BuiltIn::LocalInvocationId,
    BuiltIn::LocalInvocationIndex,
    BuiltIn::WorkGroupId,
    BuiltIn::NumWorkGroups,
];

/// Whether `span` lies in the plugin's text (the prelude follows it).
pub(crate) fn is_plugins(span: Span, plugin: &str) -> bool {
    span.to_range().is_some_and(|range| range.start < plugin.len())
}

/// Whether `argument` is the render's `global_invocation_id`.
pub(crate) fn is_invocation(argument: &FunctionArgument) -> bool {
    matches!(argument.binding, Some(Binding::BuiltIn(BuiltIn::GlobalInvocationId)))
}

pub(crate) fn check(module: &Module, info: &ModuleInfo, plugin: &str) -> Result<(), Refusal> {
    let refuse = |span: Span, why: String| Err(Refusal::at(plugin, span, why));
    floats_in_text(module, plugin)?;
    names(module, plugin)?;
    for (handle, ty) in module.types.iter() {
        if let Some(why) = refused_type(&ty.inner) {
            return refuse(module.types.get_span(handle), why);
        }
    }
    for (handle, global) in module.global_variables.iter() {
        let span = module.global_variables.get_span(handle);
        if !is_plugins(span, plugin) {
            continue;
        }
        match global.space {
            AddressSpace::Private | AddressSpace::WorkGroup => {}
            _ => return refuse(span, "a plugin binds nothing: the pictures and values are the prelude's".into()),
        }
    }
    if let Some((handle, _)) = module.overrides.iter().next() {
        return refuse(module.overrides.get_span(handle), "the host sets no override".into());
    }
    entry(module, plugin)?;
    reach(module, plugin)?;
    for (handle, function) in module.functions.iter() {
        if is_plugins(module.functions.get_span(handle), plugin) {
            body(&Code { module, info: &info[handle], plugin, render: false }, function)?;
        }
    }
    let (index, render) = module.entry_points.iter().enumerate().find(|(_, entry)| entry.name == RENDER).expect("entry");
    let render_info = info.get_entry_point(index);
    body(&Code { module, info: render_info, plugin, render: true }, &render.function)?;
    crate::group::check(module, render, render_info, plugin)
}

/// The `anicel_` names are the host's.
fn names(module: &Module, plugin: &str) -> Result<(), Refusal> {
    let reserved = |name: &Option<String>| name.as_deref().is_some_and(|name| name.starts_with("anicel_"));
    let refusal = |span: Span, name: &Option<String>| {
        Err(Refusal::at(plugin, span, format!("`{}`: the `anicel_` names are the host's", name.as_deref().unwrap_or(""))))
    };
    for (handle, function) in module.functions.iter() {
        let span = module.functions.get_span(handle);
        if is_plugins(span, plugin) && reserved(&function.name) && function.name.as_deref() != Some(REACH) {
            return refusal(span, &function.name);
        }
    }
    for (handle, global) in module.global_variables.iter() {
        let span = module.global_variables.get_span(handle);
        if is_plugins(span, plugin) && reserved(&global.name) {
            return refusal(span, &global.name);
        }
    }
    for (handle, constant) in module.constants.iter() {
        let span = module.constants.get_span(handle);
        if is_plugins(span, plugin) && reserved(&constant.name) {
            return refusal(span, &constant.name);
        }
    }
    for (handle, ty) in module.types.iter() {
        let span = module.types.get_span(handle);
        if is_plugins(span, plugin) && reserved(&ty.name) {
            return refusal(span, &ty.name);
        }
    }
    Ok(())
}

/// The float names WGSL has for a type — besides `mat…`, every matrix
/// being float.
const FLOAT_TYPES: &[&str] = &["f32", "f16", "vec2f", "vec3f", "vec4f", "vec2h", "vec3h", "vec4h"];

/// The builtins that make or take a float.
const FLOAT_BUILTINS: &[&str] = &[
    "acos", "acosh", "asin", "asinh", "atan", "atanh", "atan2", "ceil", "cos", "cosh", "cross", "degrees",
    "determinant", "distance", "exp", "exp2", "faceForward", "floor", "fma", "fract", "frexp", "inverseSqrt",
    "ldexp", "length", "log", "log2", "mix", "modf", "normalize", "pow", "quantizeToF16", "radians",
    "reflect", "refract", "round", "saturate", "sin", "sinh", "smoothstep", "sqrt", "step", "tan",
    "tanh", "transpose", "trunc", "pack4x8snorm", "pack4x8unorm", "pack2x16snorm", "pack2x16unorm",
    "pack2x16float", "unpack4x8snorm", "unpack4x8unorm", "unpack2x16snorm", "unpack2x16unorm",
    "unpack2x16float", "dpdx", "dpdxCoarse", "dpdxFine", "dpdy", "dpdyCoarse", "dpdyFine", "fwidth",
    "fwidthCoarse", "fwidthFine",
];

/// No float in the text either: naga folds a constant expression when it
/// parses — `u32(sqrt(4.0))` reaches the IR as `2u` — and folds a float
/// with the host's own maths, whose last place differs from OS to OS
/// (`sin` · `pow` are the device's library, as native/audio's pins found;
/// one_maths.rs). A float literal, type or builtin call is refused where it
/// is written, so no float is ever made, folded or not. A builtin's name
/// alone is not: WGSL lets a plugin name a value `round` or its own
/// function `length`, and those make no float.
fn floats_in_text(module: &Module, plugin: &str) -> Result<(), Refusal> {
    let at = |offset: usize| naga::Span::new(offset as u32, offset as u32 + 1);
    let why = "no float: a plugin is integers alone, so every device draws the same picture";
    if let Some(offset) = crate::scan::first_float_literal(plugin) {
        return Err(Refusal::at(plugin, at(offset), why));
    }
    let plugins_function = |word: &str| {
        module.functions.iter().any(|(handle, function)| {
            function.name.as_deref() == Some(word) && is_plugins(module.functions.get_span(handle), plugin)
        })
    };
    let called = |offset: usize, word: &str| crate::scan::next_byte(plugin, offset + word.len()) == Some(b'(');
    let float_word = |offset: usize, word: &str| {
        FLOAT_TYPES.contains(&word)
            || (word.starts_with("mat") && word.as_bytes().get(3).is_some_and(u8::is_ascii_digit))
            || (FLOAT_BUILTINS.contains(&word) && called(offset, word) && !plugins_function(word))
    };
    match crate::scan::words(plugin).into_iter().find(|&(offset, word)| float_word(offset, word)) {
        Some((offset, word)) => Err(Refusal::at(plugin, at(offset), format!("`{word}` — {why}"))),
        None => Ok(()),
    }
}

/// Why a type cannot be a plugin's, if it cannot.
fn refused_type(inner: &TypeInner) -> Option<String> {
    let float = |kind: ScalarKind| matches!(kind, ScalarKind::Float | ScalarKind::AbstractFloat);
    match *inner {
        TypeInner::Scalar(scalar) | TypeInner::Vector { scalar, .. } | TypeInner::ValuePointer { scalar, .. }
            if float(scalar.kind) =>
        {
            Some("no float: a plugin is integers alone, so every device draws the same picture".into())
        }
        TypeInner::Matrix { .. } | TypeInner::CooperativeMatrix { .. } => {
            Some("no float: a plugin is integers alone, so every device draws the same picture".into())
        }
        TypeInner::Atomic(scalar) if float(scalar.kind) => Some("no float atomic".into()),
        TypeInner::Image { .. }
        | TypeInner::Sampler { .. }
        | TypeInner::AccelerationStructure { .. }
        | TypeInner::RayQuery { .. }
        | TypeInner::BindingArray { .. } => {
            Some("no texture or sampler: a plugin reads its pictures through the prelude".into())
        }
        _ => None,
    }
}

/// One `@compute fn anicel_render` taking its `global_invocation_id`.
fn entry(module: &Module, plugin: &str) -> Result<(), Refusal> {
    let nowhere = |why: &str| Err(Refusal::nowhere(why));
    let [render] = module.entry_points.as_slice() else {
        return nowhere("a plugin has one entry point, `@compute fn anicel_render`");
    };
    if render.name != RENDER || render.stage != ShaderStage::Compute {
        return nowhere("a plugin has one entry point, `@compute fn anicel_render`");
    }
    let invocations: u64 = render.workgroup_size.iter().map(|&size| u64::from(size)).product();
    if render.workgroup_size_overrides.is_some() || invocations > u64::from(MOST_INVOCATIONS) {
        return nowhere("`anicel_render`'s workgroup is at most 256 invocations, set by numbers");
    }
    // Q4's one invocation a pixel: a group deeper than one would have its
    // invocations at one place across and down write that pixel each.
    if render.workgroup_size[2] != 1 {
        return nowhere("`anicel_render`'s workgroup is one deep: one invocation writes each pixel");
    }
    if render.function.result.is_some() {
        return nowhere("`anicel_render` returns nothing: it writes its pixel with `anicel_out`");
    }
    for argument in &render.function.arguments {
        let allowed = match argument.binding {
            Some(Binding::BuiltIn(builtin)) => INVOCATION_BUILTINS.contains(&builtin),
            _ => false,
        };
        if !allowed {
            return nowhere(
                "`anicel_render` takes builtins alone, each its own argument: global_invocation_id, \
                 local_invocation_id, local_invocation_index, workgroup_id, num_workgroups",
            );
        }
    }
    if render.function.arguments.iter().filter(|argument| is_invocation(argument)).count() != 1 {
        return nowhere("`anicel_render` takes its `@builtin(global_invocation_id)`");
    }
    if crate::scan::function_at(plugin, RENDER).and_then(|at| crate::scan::body_open(plugin, at)).is_none() {
        return nowhere("`anicel_render`'s body was not found");
    }
    Ok(())
}

/// `fn anicel_reach() -> u32`, the plugin's own.
fn reach(module: &Module, plugin: &str) -> Result<(), Refusal> {
    let found = module.functions.iter().find(|(handle, function)| {
        function.name.as_deref() == Some(REACH) && is_plugins(module.functions.get_span(*handle), plugin)
    });
    let shaped = found.is_some_and(|(_, function)| {
        function.arguments.is_empty()
            && function.result.as_ref().is_some_and(|result| {
                result.binding.is_none()
                    && matches!(module.types[result.ty].inner, TypeInner::Scalar(scalar) if scalar.kind == ScalarKind::Uint && scalar.width == 4)
            })
    });
    if shaped { Ok(()) } else { Err(Refusal::nowhere("a plugin answers its reach: `fn anicel_reach() -> u32`")) }
}

/// Where a function's code is read: the module and the function's info,
/// the plugin's text, and whether the function is `anicel_render` — the one
/// a group's shared memory, barriers and atomics belong to (group.rs).
struct Code<'a> {
    module: &'a Module,
    info: &'a FunctionInfo,
    plugin: &'a str,
    render: bool,
}

/// The plugin's code in one function: what it may run and name.
fn body(code: &Code<'_>, function: &Function) -> Result<(), Refusal> {
    let module = code.module;
    for (handle, expression) in function.expressions.iter() {
        let span = function.expressions.get_span(handle);
        let refuse = |why: String| Err(Refusal::at(code.plugin, span, why));
        if let Some(why) = refused_type(code.info[handle].ty.inner_with(&module.types)) {
            return refuse(why);
        }
        match *expression {
            Expression::Literal(_)
            | Expression::Constant(_)
            | Expression::ZeroValue(_)
            | Expression::Compose { .. }
            | Expression::Access { .. }
            | Expression::AccessIndex { .. }
            | Expression::Splat { .. }
            | Expression::Swizzle { .. }
            | Expression::FunctionArgument(_)
            | Expression::LocalVariable(_)
            | Expression::Load { .. }
            | Expression::Unary { .. }
            | Expression::Binary { .. }
            | Expression::Select { .. }
            | Expression::As { .. }
            | Expression::CallResult(_)
            | Expression::AtomicResult { .. }
            | Expression::WorkGroupUniformLoadResult { .. } => {}
            Expression::Relational { fun, .. } => {
                if !matches!(fun, naga::RelationalFunction::All | naga::RelationalFunction::Any) {
                    return refuse(format!("`{fun:?}` is a float test"));
                }
            }
            Expression::Math { fun, .. } => {
                if !INTEGER_MATHS.contains(&fun) {
                    return refuse(format!("`{fun:?}` is not an integer builtin the host runs"));
                }
            }
            Expression::GlobalVariable(global) => {
                let declared = &module.global_variables[global];
                if !is_plugins(module.global_variables.get_span(global), code.plugin) {
                    let name = declared.name.as_deref().unwrap_or("");
                    return refuse(format!("`{name}` is the host's: a plugin reaches it through the `anicel_` functions"));
                }
                if declared.space == AddressSpace::WorkGroup && !code.render {
                    return refuse(SHARED_IN_RENDER.into());
                }
            }
            ref other => return refuse(format!("a plugin cannot use {}", kind_of(other))),
        }
    }
    statements(code, &function.body)
}

/// Why shared memory, a barrier or an atomic outside `anicel_render` is
/// refused: the proof of group.rs does not follow calls. A helper reaches
/// shared memory only by naming it — naga refuses a `ptr<workgroup, …>`
/// parameter (no `unrestricted_pointer_parameters`; tests.rs pins that).
const SHARED_IN_RENDER: &str = "shared memory, barriers and atomics are anicel_render's own: the host's proof \
                                that the group meets them alike does not follow calls";

fn statements(code: &Code<'_>, block: &naga::Block) -> Result<(), Refusal> {
    let module = code.module;
    for (statement, span) in block.span_iter() {
        let refuse = |why: String| Err(Refusal::at(code.plugin, *span, why));
        match statement {
            Statement::Emit(_) | Statement::Break | Statement::Continue | Statement::Return { .. } | Statement::Store { .. } => {}
            Statement::Block(inner) => statements(code, inner)?,
            Statement::If { accept, reject, .. } => {
                statements(code, accept)?;
                statements(code, reject)?;
            }
            Statement::Switch { cases, .. } => {
                for case in cases {
                    statements(code, &case.body)?;
                }
            }
            Statement::Loop { body, continuing, .. } => {
                statements(code, body)?;
                statements(code, continuing)?;
            }
            Statement::Call { function, .. } => {
                let name = module.functions[*function].name.as_deref().unwrap_or("");
                if name.starts_with("anicel_host_") {
                    return refuse(format!("`{name}` is the host's"));
                }
            }
            Statement::ControlBarrier(_) | Statement::WorkGroupUniformLoad { .. } if !code.render => {
                return refuse(SHARED_IN_RENDER.into());
            }
            Statement::ControlBarrier(barrier) if *barrier != naga::Barrier::WORK_GROUP => {
                return refuse("the one barrier a plugin has is `workgroupBarrier`: it owns no storage, texture or subgroup".into());
            }
            Statement::ControlBarrier(_) | Statement::WorkGroupUniformLoad { .. } => {}
            // A helper has nothing to aim one at: an atomic lives in shared
            // memory, which it cannot name, or in storage, of which a plugin
            // has none.
            Statement::Atomic { fun, result, .. } => {
                if !matches!(fun, AtomicFunction::Add | AtomicFunction::Min | AtomicFunction::Max) {
                    return refuse("an atomic is an add, a min or a max — its last value is then the same in any order (Q6 ⓑ)".into());
                }
                if result.is_some_and(|result| code.info[result].ref_count > 0) {
                    return refuse("what an atomic gives back is not read — the order it came in is the device's (Q6 ⓑ)".into());
                }
            }
            other => return refuse(format!("a plugin cannot use {}", kind_of(other))),
        }
    }
    Ok(())
}

/// The variant's name of an IR node, for a refusal.
fn kind_of(node: &impl std::fmt::Debug) -> String {
    let debug = format!("{node:?}");
    debug.split(|c: char| !c.is_alphanumeric()).next().unwrap_or("this").to_string()
}
