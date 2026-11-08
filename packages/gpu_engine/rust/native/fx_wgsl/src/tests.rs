use crate::{Cut, Frame, Kernel, PRELUDE, Refusal, open};

const INVERT: &str = include_str!("../fixtures/invert.wgsl");
const ENDLESS: &str = include_str!("../fixtures/endless.wgsl");
const FLOAT: &str = include_str!("../fixtures/float.wgsl");
const BLUR: &str = include_str!("../fixtures/blur.wgsl");
const LAYER: &str = include_str!("../fixtures/layer.wgsl");
const ROW_BLUR: &str = include_str!("../fixtures/row_blur.wgsl");
const HISTOGRAM: &str = include_str!("../fixtures/histogram.wgsl");
const GROUP_SUM: &str = include_str!("../fixtures/group_sum.wgsl");

/// What a reach is asked: the values and the moment, no picture.
fn ask(values: &[[i32; 4]], fuel: u32) -> Frame<'_> {
    Frame {
        out_origin: [0, 0],
        out_size: [0, 0],
        in_origin: [0, 0],
        in_size: [0, 0],
        frame: 0,
        time_q16: 0,
        rate_q16: 24 << 16,
        scale_q16: 1 << 16,
        fuel,
        input: &[],
        rows: &[],
        values,
    }
}

/// A run over `size` at canvas (10, 20), its input `reach` wider.
fn picture<'a>(size: [i32; 2], reach: i32, input: &'a [u32], rows: &'a [u32], values: &'a [[i32; 4]]) -> Frame<'a> {
    Frame {
        out_origin: [10, 20],
        out_size: size,
        in_origin: [10 - reach, 20 - reach],
        in_size: [size[0] + 2 * reach, size[1] + 2 * reach],
        input,
        rows,
        ..ask(values, 1_000_000)
    }
}

fn opened(plugin: &str) -> Kernel {
    open(plugin).unwrap_or_else(|refusal| panic!("refused: {refusal}"))
}

fn refusal(plugin: &str) -> Refusal {
    match open(plugin) {
        Ok(_) => panic!("opened:\n{plugin}"),
        Err(refusal) => refusal,
    }
}

/// A plugin of `render_body` and `reach_body`, with `extra` before them.
fn plugin(extra: &str, render_body: &str, reach_body: &str) -> String {
    format!(
        "{extra}\n@compute @workgroup_size(16, 16)\nfn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {{\n{render_body}\n}}\nfn anicel_reach() -> u32 {{\n{reach_body}\n}}\n"
    )
}

fn pixel(r: u32, g: u32, b: u32, a: u32) -> u32 {
    r | g << 8 | b << 16 | a << 24
}

#[test]
fn the_fixtures_open_but_the_float() {
    let fixtures = [
        ("invert", INVERT),
        ("endless", ENDLESS),
        ("blur", BLUR),
        ("layer", LAYER),
        ("row blur", ROW_BLUR),
        ("histogram", HISTOGRAM),
        ("group sum", GROUP_SUM),
    ];
    for (name, source) in fixtures {
        open(source).unwrap_or_else(|refusal| panic!("{name}: {refusal}"));
    }
    let refused = refusal(FLOAT);
    assert_eq!(refused.line, 5, "at the f32 line: {refused}");
    assert!(refused.why.contains("float"), "{refused}");
}

#[test]
fn invert_inverts_every_pixel_of_the_output_alone() {
    let kernel = opened(INVERT);
    let input: Vec<u32> = (0..6).map(|i| pixel(i * 40, 255 - i * 30, i * 7, 100 + i)).collect();
    let mut output = vec![7u32; 6];
    kernel.render(&picture([3, 2], 0, &input, &[], &[]), &mut output).expect("not cut");
    let inverted: Vec<u32> = (0..6).map(|i| pixel(255 - i * 40, i * 30, 255 - i * 7, 100 + i)).collect();
    assert_eq!(output, inverted);
}

#[test]
fn a_pixel_past_the_output_is_written_by_no_invocation() {
    // Seventeen wide: the second group's fifteen spare columns run too, and
    // write nothing — the output is exactly the plane.
    let kernel = opened(INVERT);
    let input = vec![pixel(1, 2, 3, 4); 17];
    let mut output = vec![0u32; 17];
    kernel.render(&picture([17, 1], 0, &input, &[], &[]), &mut output).expect("not cut");
    assert_eq!(output, vec![pixel(254, 253, 252, 4); 17]);
}

#[test]
fn the_blur_answers_its_reach_from_its_value() {
    let kernel = opened(BLUR);
    assert_eq!(kernel.reach(&ask(&[[3 << 16, 0, 0, 0]], 1_000_000)), Ok(3));
    assert_eq!(kernel.reach(&ask(&[[100 << 16, 0, 0, 0]], 1_000_000)), Ok(64), "clamped");
    assert_eq!(kernel.reach(&ask(&[], 1_000_000)), Ok(0), "a value past the declared ones is 0");
}

#[test]
fn the_blur_averages_what_its_reach_brings_in() {
    let kernel = opened(BLUR);
    let (size, reach) = ([4, 3], 1);
    let (width, height) = (size[0] + 2 * reach, size[1] + 2 * reach);
    let input: Vec<u32> = (0..width * height).map(|i| pixel((i * 37 % 256) as u32, (i * 11 % 256) as u32, 9, 255)).collect();
    let mut output = vec![0u32; (size[0] * size[1]) as usize];
    let values = [[1 << 16, 0, 0, 0]];
    kernel.render(&picture(size, reach, &input, &[], &values), &mut output).expect("not cut");
    for y in 0..size[1] {
        for x in 0..size[0] {
            let mut sum = [0u32; 4];
            for dy in 0..3 {
                for dx in 0..3 {
                    let word = input[((y + dy) * width + x + dx) as usize];
                    for (channel, total) in sum.iter_mut().enumerate() {
                        *total += (word >> (8 * channel)) & 0xff;
                    }
                }
            }
            let mean = sum.map(|total| (total + 4) / 9);
            assert_eq!(output[(y * size[0] + x) as usize], pixel(mean[0], mean[1], mean[2], mean[3]), "({x}, {y})");
        }
    }
}

#[test]
fn the_layer_reader_reads_the_slot_its_value_names() {
    let kernel = opened(LAYER);
    let input = [pixel(9, 9, 9, 255), 0];
    let rows = [pixel(1, 1, 1, 1), pixel(2, 2, 2, 2), pixel(3, 3, 3, 3), pixel(4, 4, 4, 4)];
    let mut output = [0u32; 2];
    kernel.render(&picture([2, 1], 0, &input, &rows, &[[1, 0, 0, 0]]), &mut output).expect("not cut");
    assert_eq!(output, [pixel(9, 9, 9, 255), pixel(4, 4, 4, 4)], "slot 1's second pixel behind the hole");
    kernel.render(&picture([2, 1], 0, &input, &rows, &[[-1, 0, 0, 0]]), &mut output).expect("not cut");
    assert_eq!(output, [pixel(9, 9, 9, 255), 0], "slot -1 names no layer: transparent");
}

#[test]
fn the_endless_plugin_is_cut_in_its_reach_and_its_render() {
    let kernel = opened(ENDLESS);
    assert_eq!(kernel.reach(&ask(&[], 10_000)), Err(Cut));
    let input = [0u32; 4];
    let mut output = [0u32; 4];
    let frame = Frame { fuel: 10_000, ..picture([2, 2], 0, &input, &[], &[]) };
    assert_eq!(kernel.render(&frame, &mut output), Err(Cut));
}

/// The cost one turn of the counted text's first charge names.
fn first_turn(kernel: &Kernel) -> u32 {
    let source = kernel.source();
    let at = source.find("anicel_host_spend(").expect("a charge") + "anicel_host_spend(".len();
    source[at..].split('u').next().expect("a number").parse().expect("the turn's cost")
}

#[test]
fn a_plugin_is_cut_at_the_one_turn_its_share_runs_out_at() {
    // Ten turns cost ten charges: a share of exactly that ends the loop
    // whole, one less cuts it — the same place on every device, since the
    // cost is read from the source.
    let kernel = opened(&plugin("", "", "var n = 0u;\nfor (var i = 0u; i < 10u; i++) { n += 1u; }\nreturn n;"));
    let turn = first_turn(&kernel);
    assert!(turn > 1, "a turn costs its size, not one: {turn}");
    assert_eq!(kernel.reach(&ask(&[], 10 * turn)), Ok(10));
    assert_eq!(kernel.reach(&ask(&[], 10 * turn - 1)), Err(Cut));
}

#[test]
fn every_loop_of_the_plugins_pays_and_the_render_enters_first() {
    let kernel = opened(BLUR);
    let source = kernel.source();
    let plugin_part = &source[..source.len() - PRELUDE.len()];
    assert_eq!(plugin_part.matches("anicel_host_spend(").count(), 2, "the blur's two loops:\n{plugin_part}");
    assert!(plugin_part.contains("fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) { anicel_host_enter(at);"));
}

#[test]
fn a_call_in_a_loop_costs_what_it_calls() {
    // The same loop, calling a helper of one statement or of ten: only the
    // callee's straight size tells the two turns apart.
    let turn_with = |helper_body: &str| {
        first_turn(&opened(&plugin(
            &format!("fn helper(x: u32) -> u32 {{ {helper_body} }}"),
            "",
            "var n = 0u;\nloop { n += helper(n) & 1u; n += 1u; if n > 3u { break; } }\nreturn n;",
        )))
    };
    let small = turn_with("return x;");
    let big = turn_with("let a = x * 3u; let b = a + 7u; let c = b ^ a; let d = c * c; return d + b;");
    assert!(big >= small + 8, "the callee's straight size is in the turn: {small} -> {big}");
}

#[test]
fn braces_in_comments_do_not_move_a_charge() {
    let kernel = opened(&plugin(
        "",
        "",
        "var n = 0u;\nfor (var i = 0u; i < 3u; i++) /* { */ // {\n{ n += 1u; }\nreturn n;",
    ));
    assert_eq!(kernel.reach(&ask(&[], 1_000_000)), Ok(3));
    assert!(kernel.source().contains("// {\n{ if anicel_host_spend("), "{}", kernel.source());
}

#[test]
fn the_integers_are_wgsls() {
    // value 0's words are 0, -1, i32::MIN, 33 — known only at run time.
    let kernel = opened(&plugin(
        "",
        "",
        "let zero = anicel_value(0, 0);\nlet minus = anicel_value(0, 1);\nlet low = anicel_value(0, 2);\nlet far = u32(anicel_value(0, 3));\n\
         var table = array<u32, 3>(5u, 6u, 7u);\n\
         let a = (7 / zero == 7) && (7 % zero == 0) && (low / minus == low) && (low % minus == 0);\n\
         let b = (1u << far) == 2u && (-8 >> far) == -4;\n\
         let c = table[u32(minus)] == 7u && table[far] == 7u;\n\
         let d = (low + minus) == 2147483647 && abs(low) == low;\n\
         return u32(a) | u32(b) << 1u | u32(c) << 2u | u32(d) << 3u;",
    ));
    let values = [[0, -1, i32::MIN, 33]];
    assert_eq!(kernel.reach(&ask(&values, 1_000_000)), Ok(0b1111));
}

#[test]
fn the_frame_crosses_member_by_member() {
    // run.rs's `frame_val` lays the prelude's AnicelFrame out by place.
    let module = naga::front::wgsl::parse_str(PRELUDE).expect("the prelude parses alone");
    let frame = module.types.iter().find(|(_, ty)| ty.name.as_deref() == Some("AnicelFrame")).expect("the struct");
    let naga::TypeInner::Struct { ref members, .. } = frame.1.inner else { panic!("a struct") };
    let names: Vec<_> = members.iter().map(|m| m.name.as_deref().unwrap_or("")).collect();
    assert_eq!(
        names,
        ["out_origin", "out_size", "in_origin", "in_size", "rows", "values", "frame", "time_q16", "rate_q16", "scale_q16", "fuel", "spare"]
    );
}

#[test]
fn what_the_check_refuses_and_why() {
    let render = "anicel_out(0u);";
    let reach = "return 0u;";
    let with_render_argument = |argument: &str| {
        plugin("", render, reach).replace("at: vec3<u32>) {", &format!("at: vec3<u32>, {argument}) {{"))
    };
    let cases: [(&str, String, &str); 22] = [
        ("a float literal", plugin("", "let x = 1.5;", reach), "no float"),
        ("a float conversion", plugin("", "let x = u32(f32(at.x));", reach), "no float"),
        ("a texture", plugin("@group(1) @binding(0) var picture: texture_2d<u32>;", render, reach), "no texture"),
        ("its own binding", plugin("@group(1) @binding(0) var<storage> extra: array<u32>;", render, reach), "binds nothing"),
        ("another's cell written", plugin("var<workgroup> tile: array<u32, 256>;", "tile[0] = 1u;", reach), "own cell"),
        ("a barrier in a helper", plugin("fn wait() { workgroupBarrier(); }", "wait();", reach), "anicel_render's own"),
        ("an anicel_ name", plugin("fn anicel_mine() -> u32 { return 1u; }", render, reach), "names are the host's"),
        ("the host's spend", plugin("", "let paid = anicel_host_spend(1u);", reach), "`anicel_host_spend` is the host's"),
        ("the host's fuel", plugin("", "anicel_host_fuel = 99u;", reach), "`anicel_host_fuel` is the host's"),
        ("the host's output", plugin("", "anicel_host_output[0] = 1u;", reach), "`anicel_host_output` is the host's"),
        ("an override", plugin("override strength: u32 = 1u;", render, reach), "override"),
        ("a big workgroup", plugin("", render, reach).replace("(16, 16)", "(32, 32)"), "at most 256"),
        (
            "no invocation",
            plugin("", render, reach).replace("@builtin(global_invocation_id) at: vec3<u32>", ""),
            "global_invocation_id",
        ),
        // The validator refuses it first (no subgroup capability is granted).
        ("a subgroup size", with_render_argument("@builtin(subgroup_size) s: u32"), "invalid"),
        (
            "builtins in a struct",
            plugin("struct Ids { @builtin(global_invocation_id) at: vec3<u32>, @builtin(local_invocation_index) i: u32 }", render, reach)
                .replace("@builtin(global_invocation_id) at: vec3<u32>) {", "ids: Ids) {"),
            "each its own argument",
        ),
        (
            "no reach",
            format!("@compute @workgroup_size(16, 16)\nfn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {{ {render} }}"),
            "answers its reach",
        ),
        (
            "a reach of i32",
            plugin("", render, "return 0;").replace("fn anicel_reach() -> u32", "fn anicel_reach() -> i32"),
            "answers its reach",
        ),
        ("a float the parser folds", plugin("", "let x = countOneBits(u32(sqrt(4.0)));", reach), "no float"),
        ("a float builtin on an integer", plugin("", "let x = u32(sqrt(4));", reach), "`sqrt`"),
        ("a float builtin past a comment", plugin("", "let x = u32(sqrt /* ( */ (4));", reach), "`sqrt`"),
        ("an exponent", plugin("", "let x = u32(1e3);", reach), "no float"),
        ("a matrix", plugin("const m = mat2x2(1, 0, 0, 1);", render, reach), "`mat2x2`"),
    ];
    for (what, source, why) in cases {
        let refused = refusal(&source);
        assert!(refused.why.contains(why), "{what}: refused for another reason — {refused}\n{source}");
    }
}

#[test]
fn a_refusal_names_the_plugins_line() {
    let refused = refusal(&plugin("", "let x = 1.5;", "return 0u;"));
    assert_eq!((refused.line, refused.why.contains("float")), (4, true), "{refused}");
}

#[test]
fn a_float_in_a_comment_and_a_hex_integer_open() {
    let kernel = opened(&plugin(
        "// halves it: 0.5, 1e3 /* 2.0f */",
        "anicel_out(0xffu); /* 0x1p4 */",
        "return u32(0x1e) + 1u; // 3.5",
    ));
    assert_eq!(kernel.reach(&ask(&[], 1_000)), Ok(31));
}

#[test]
fn a_float_builtins_name_on_a_value_or_an_own_function_opens() {
    // WGSL lets a plugin take the names: `round` here is a number, and
    // `length` the plugin's own, on integers — no float is made.
    let kernel = opened(&plugin(
        "fn length(v: vec2<i32>) -> u32 { return u32(abs(v.x) + abs(v.y)); }",
        "anicel_out(0u);",
        "let round = 2u;\nreturn round + length(vec2<i32>(-3, 4));",
    ));
    assert_eq!(kernel.reach(&ask(&[], 1_000)), Ok(9));
}

#[test]
fn a_read_past_the_input_is_transparent() {
    // Five to the left of a reach of none is off the input: spec 1's
    // `Picture::at` answered None there, and the prelude answers 0.
    let kernel = opened(&plugin(
        "",
        "let here = anicel_here();\nanicel_out(anicel_in(here.x - 5, here.y) | anicel_in(here.x, here.y) << 1u);",
        "return 0u;",
    ));
    let input = [3u32, 5];
    let mut output = [9u32; 2];
    kernel.render(&picture([2, 1], 0, &input, &[], &[]), &mut output).expect("not cut");
    assert_eq!(output, [6, 10]);
}

/// `plugin`'s render, also taking its `local_invocation_index` as `i`.
fn indexed(extra: &str, render_body: &str) -> String {
    plugin(extra, render_body, "return 0u;")
        .replace("at: vec3<u32>) {", "at: vec3<u32>, @builtin(local_invocation_index) i: u32) {")
}

/// A canvas of `size` pixels, pixel `i` the word `word(i)`.
fn canvas(size: [i32; 2], word: impl Fn(u32) -> u32) -> Vec<u32> {
    (0..(size[0] * size[1]) as u32).map(word).collect()
}

#[test]
fn the_row_blur_reads_its_neighbours_after_the_barrier() {
    let kernel = opened(ROW_BLUR);
    let size = [32, 2];
    let input = canvas(size, |i| pixel(i * 7 % 256, i * 13 % 256, 255 - i, 255));
    let mut output = vec![0u32; input.len()];
    kernel.render(&picture(size, 0, &input, &[], &[]), &mut output).expect("not cut");
    for (at, word) in output.iter().enumerate() {
        let (start, i) = (at - at % 16, at % 16);
        let around = [start + i.max(1) - 1, at, start + (i + 1).min(15)];
        let channel = |c: u32| (around.iter().map(|&n| (input[n] >> (8 * c)) & 0xff).sum::<u32>() + 1) / 3;
        assert_eq!(*word, pixel(channel(0), channel(1), channel(2), channel(3)), "pixel {at}");
    }
}

#[test]
fn the_histogram_counts_each_group_from_zero() {
    // Two groups side by side: the second's counts start from zero again
    // (Q6 ⓒ), not from where the first's ended.
    let kernel = opened(HISTOGRAM);
    let size = [16, 8];
    let input = canvas(size, |i| pixel(0, 0, 0, i * 37 % 256));
    let mut output = vec![0u32; input.len()];
    kernel.render(&picture(size, 0, &input, &[], &[]), &mut output).expect("not cut");
    let group = |at: usize| (at % 16) / 8;
    for (at, word) in output.iter().enumerate() {
        let quarter = input[at] >> 30;
        let alike = (0..input.len()).filter(|&n| group(n) == group(at) && input[n] >> 30 == quarter).count();
        assert_eq!(*word, alike as u32, "pixel {at}");
    }
}

#[test]
fn the_group_sum_adds_in_two_steps_a_round() {
    let kernel = opened(GROUP_SUM);
    let size = [8, 16];
    let input = canvas(size, |i| pixel(i * 29 % 256, 1, 2, 3));
    let mut output = vec![0u32; input.len()];
    kernel.render(&picture(size, 0, &input, &[], &[]), &mut output).expect("not cut");
    let sum = |group: usize| input[group * 64..(group + 1) * 64].iter().map(|word| word & 0xff).sum::<u32>();
    assert_eq!(output, (0..input.len()).map(|at| sum(at / 64)).collect::<Vec<_>>());
    assert!(kernel.source().contains("anicel_host_spend_together("), "the round waits at barriers:\n{}", kernel.source());
}

/// `plugin`'s render, also taking its `local_invocation_id` as `lid`.
fn by_axes(extra: &str, render_body: &str) -> String {
    plugin(extra, render_body, "return 0u;")
        .replace("at: vec3<u32>) {", "at: vec3<u32>, @builtin(local_invocation_id) lid: vec3<u32>) {")
}

#[test]
fn a_tile_kept_by_its_axes_flips_each_group() {
    // The own cell by the invocation's place in the group, an axis a level.
    let kernel = opened(&by_axes(
        "var<workgroup> tile: array<array<u32, 16>, 16>;",
        "let here = anicel_here();\ntile[lid.y][lid.x] = anicel_in(here.x, here.y);\nworkgroupBarrier();\n\
         anicel_out(tile[15u - lid.y][lid.x]);",
    ));
    let size = [16, 32];
    let input = canvas(size, |i| i.wrapping_mul(2654435761));
    let mut output = vec![0u32; input.len()];
    kernel.render(&picture(size, 0, &input, &[], &[]), &mut output).expect("not cut");
    for (at, word) in output.iter().enumerate() {
        let (x, y) = (at % 16, at / 16);
        let flipped = (y / 16 * 16 + 15 - y % 16) * 16 + x;
        assert_eq!(*word, input[flipped], "pixel ({x}, {y})");
    }
}

#[test]
fn a_cut_in_a_barriers_loop_takes_the_whole_group_out() {
    // The first loop runs `i` turns, so the later invocations spend their
    // share there; the second waits at a barrier each round, and the whole
    // group leaves it on its first turn once any of it was cut — each pixel
    // says how many rounds it ran. The CPU's run stops, rather than waits,
    // if any invocation meets a barrier the others do not.
    let kernel = opened(&indexed(
        "var<workgroup> cells: array<u32, 256>;",
        "var spent = 0u;\nfor (var k = 0u; k < i; k++) { spent += 1u; }\n\
         var rounds = 0u;\n\
         for (var round = 0u; round < 8u; round++) {\ncells[i] = spent + round;\nworkgroupBarrier();\nrounds += 1u;\n}\n\
         anicel_out(spent << 4u | rounds);",
    ));
    let input = [0u32; 256];
    let mut output = [0u32; 256];
    let frame = picture([16, 16], 0, &input, &[], &[]);
    kernel.render(&frame, &mut output).expect("enough to spend");
    assert_eq!(output.to_vec(), (0..256).map(|i| i << 4 | 8).collect::<Vec<u32>>());
    let short = Frame { fuel: 100 * first_turn(&kernel), ..frame };
    assert_eq!(kernel.render(&short, &mut output), Err(Cut));
    assert!(output.iter().all(|word| word & 15 == 0), "no invocation ran a round: {output:?}");
}

#[test]
fn an_endless_barriers_loop_is_cut_with_its_whole_group() {
    // A group of four, so the many rounds before the cut meet quickly.
    let kernel = opened(&plugin("", "loop {\nworkgroupBarrier();\n}", "return 0u;").replace("(16, 16)", "(2, 2)"));
    let input = [0u32; 4];
    let mut output = [0u32; 4];
    let frame = Frame { fuel: 10_000, ..picture([2, 2], 0, &input, &[], &[]) };
    assert_eq!(kernel.render(&frame, &mut output), Err(Cut));
}

#[test]
fn a_barrier_under_a_uniform_load_opens() {
    // The group's most alpha by a max, and its least, negated, by a min.
    let kernel = opened(&plugin(
        "var<workgroup> most: atomic<u32>;\nvar<workgroup> least: atomic<i32>;",
        "let here = anicel_here();\nlet alpha = anicel_in(here.x, here.y) >> 24u;\n\
         atomicMax(&most, alpha);\natomicMin(&least, -i32(alpha));\nworkgroupBarrier();\n\
         let top = workgroupUniformLoad(&most);\nif (top > 128u) {\nworkgroupBarrier();\n}\n\
         anicel_out(top | u32(-atomicLoad(&least)) << 8u);",
        "return 0u;",
    ));
    let input = canvas([16, 16], |i| pixel(0, 0, 0, i * 3 % 211));
    let mut output = vec![0u32; 256];
    kernel.render(&picture([16, 16], 0, &input, &[], &[]), &mut output).expect("not cut");
    assert_eq!(output, vec![210 | 210 << 8; 256]);
}

#[test]
fn an_own_cell_by_any_mix_of_the_invocations_numbers_opens() {
    // Q9 asks that the index be the invocation's own number alone; how its
    // levels mix the whole index and the axes is the plugin's.
    for (extra, body) in [
        ("var<workgroup> grid: array<array<u32, 8>, 64>;", "grid[i][lid.x] = 1u;"),
        ("var<workgroup> grid: array<array<u32, 8>, 8>;", "grid[lid.x][lid.y] = 1u;"),
    ] {
        let source = by_axes(extra, body).replace("(16, 16)", "(8, 8)");
        opened(&source.replace("at: vec3<u32>,", "at: vec3<u32>, @builtin(local_invocation_index) i: u32,"));
    }
}

#[test]
fn what_the_group_check_refuses_and_why() {
    let tile = "var<workgroup> tile: array<u32, 256>;";
    let count = "var<workgroup> count: atomic<u32>;";
    let cases: [(&str, String, &str); 28] = [
        (
            "an in-place tree sum (Q10)",
            indexed(tile, "tile[i] = 1u;\nworkgroupBarrier();\ntile[i] = tile[i] + tile[min(i + 1u, 255u)];"),
            "not both",
        ),
        ("an exchange (b)", indexed(count, "atomicExchange(&count, 1u);"), "an add, a min or a max"),
        ("an atomic's answer read (b)", indexed(count, "anicel_out(atomicAdd(&count, 1u));"), "is not read"),
        ("an atomic stored (b)", indexed(count, "atomicStore(&count, 1u);"), "alone (Q6"),
        (
            "an atomic read before a barrier (Q8)",
            indexed(count, "atomicAdd(&count, 1u);\nanicel_out(atomicLoad(&count));"),
            "only after a barrier has followed its last write",
        ),
        (
            "an atomic written once read (Q8)",
            indexed(count, "atomicAdd(&count, 1u);\nworkgroupBarrier();\nanicel_out(atomicLoad(&count));\natomicAdd(&count, 1u);"),
            "not written again",
        ),
        ("another's cell written (Q9)", indexed(tile, "tile[255u - i] = 1u;"), "own cell"),
        ("a cell chosen by data (Q9)", indexed(tile, "tile[anicel_in(0, 0) & 255u] = 1u;"), "own cell"),
        ("too few cells for the group", indexed("var<workgroup> tile: array<u32, 16>;", "tile[i] = 1u;"), "own cell"),
        (
            "too few cells for an axis",
            by_axes("var<workgroup> tile: array<array<u32, 16>, 8>;", "tile[lid.y][lid.x] = 1u;"),
            "own cell",
        ),
        ("an axis the group spans left out", by_axes("var<workgroup> tile: array<u32, 16>;", "tile[lid.x] = 1u;"), "own cell"),
        (
            "a neighbour read before the barrier",
            indexed(tile, "tile[i] = 1u;\nanicel_out(tile[min(i + 1u, 255u)]);"),
            "only after a barrier has followed the writes",
        ),
        (
            "a write a break carries out, read past (Q9, Q10)",
            indexed(tile, "loop {\ntile[i] = 1u;\nif (anicel_frame() == 0) { break; }\nworkgroupBarrier();\n}\nanicel_out(tile[min(i + 1u, 255u)]);"),
            "only after a barrier has followed the writes",
        ),
        (
            "a write a continue carries round (Q9, Q10)",
            indexed(
                tile,
                "for (var k = 0u; k < 4u; k++) {\nlet other = tile[min(i + 1u, 255u)];\nworkgroupBarrier();\n\
                 tile[i] = other + k;\nif (k == 2u) { continue; }\nworkgroupBarrier();\n}",
            ),
            "only after a barrier has followed the writes",
        ),
        (
            "a write a switch's break carries out (Q9, Q10)",
            indexed(
                tile,
                "switch (anicel_frame()) {\ncase 0: {\ntile[i] = 1u;\nif (anicel_time() == 0) { break; }\n\
                 workgroupBarrier();\n}\ndefault: {}\n}\nanicel_out(tile[min(i + 1u, 255u)]);",
            ),
            "only after a barrier has followed the writes",
        ),
        (
            "a write a continue in a switch carries round (Q9, Q10)",
            indexed(
                tile,
                "for (var k = 0u; k < 4u; k++) {\nlet other = tile[min(i + 1u, 255u)];\nworkgroupBarrier();\n\
                 tile[i] = other + k;\nswitch (k) {\ncase 2u: { continue; }\ndefault: {}\n}\nworkgroupBarrier();\n}",
            ),
            "only after a barrier has followed the writes",
        ),
        (
            "a barrier's loop left apart (a)",
            indexed("", "for (var k = 0u; k < i; k++) { workgroupBarrier(); }"),
            "left by the whole group at once",
        ),
        (
            "a barrier's loop some continue apart (a)",
            indexed("", "loop {\nif (i == 0u) { continue; }\nworkgroupBarrier();\nbreak;\n}"),
            "left by the whole group at once",
        ),
        (
            "a barrier's loop some return from (a)",
            indexed("", "loop {\nif (i == 0u) { return; }\nworkgroupBarrier();\n}"),
            "left by the whole group at once",
        ),
        (
            "a barrier's loop its break if leaves apart (a)",
            indexed("", "var k = 0u;\nloop {\nworkgroupBarrier();\ncontinuing {\nk += 1u;\nbreak if k > i;\n}\n}"),
            "left by the whole group at once",
        ),
        (
            "a barrier's loop bound by a local holding the index (a)",
            indexed("", "var n = 0u;\nn = i;\nfor (var k = 0u; k < n; k++) { workgroupBarrier(); }"),
            "left by the whole group at once",
        ),
        (
            "a barrier's loop bound by a local a helper wrote (a)",
            indexed(
                "fn write_x(p: ptr<function, u32>) { *p = u32(anicel_here().x); }",
                "var n = 0u;\nwrite_x(&n);\nfor (var k = 0u; k < n; k++) { workgroupBarrier(); }",
            ),
            "left by the whole group at once",
        ),
        (
            "a barrier passed by after a return (a)",
            indexed("", "loop { if (i == 0u) { return; } break; }\nworkgroupBarrier();"),
            "met by the whole group",
        ),
        (
            "shared memory in a helper",
            plugin(&format!("{tile}\nfn put() {{ tile[0] = 1u; }}"), "put();", "return 0u;"),
            "anicel_render's own",
        ),
        (
            "shared memory handed to a helper (naga refuses the pointer)",
            plugin(&format!("{tile}\nfn put(p: ptr<workgroup, array<u32, 256>>) {{ (*p)[0] = 1u; }}"), "put(&tile);", "return 0u;"),
            "'put' is invalid",
        ),
        ("a storage barrier", plugin("", "storageBarrier();", "return 0u;"), "the one barrier"),
        ("too much shared memory", indexed("var<workgroup> big: array<u32, 4096>;", "big[i] = 1u;"), "at most 16368 bytes"),
        (
            // 16356 and 4 bytes fit only unrounded: each rounds up to 16.
            "shared memory rounded up a variable",
            indexed("var<workgroup> big: array<u32, 4089>;\nvar<workgroup> count: atomic<u32>;", "atomicAdd(&count, 1u);"),
            "at most 16368 bytes",
        ),
    ];
    for (what, source, why) in cases {
        let refused = refusal(&source);
        assert!(refused.why.contains(why), "{what}: refused for another reason — {refused}\n{source}");
    }
}
