//! The letters' C ABI on a real GPU: faces handed over as files and a
//! picture built call by call set the very picture the same faces and
//! passes built in Rust do, and what is refused says why.

use super::*;
use crate::kernels::composite::TILE_BYTES;
use crate::kernels::composite::tests::rig;
use crate::kernels::letters::glyphs_tests::{faces, file, here, run};
use crate::testing::{last_error, read_buffer};

const WORDS: [f32; 6] = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
/// Turned a little, scaled and moved off the grid's pixels: a stand.
const STAND: [f32; 6] = [1.4, 0.3, -0.3, 1.4, 20.25, 7.5];

/// The app's faces — BIZ UDPGothic, 나눔고딕, Noto Sans SC, each family's
/// files together — through the ABI.
fn handed() -> *mut Faces {
    let files = [
        (file("BIZUDPGothic-Regular.ttf"), 0),
        (file("BIZUDPGothic-Bold.ttf"), 0),
        (file("NanumGothic-Regular.ttf"), 1),
        (file("NanumGothic-Bold.ttf"), 1),
        (file("NotoSansSC-Variable.ttf"), 2),
    ];
    faces_of(&files)
}

fn faces_of(files: &[(Vec<u8>, u32)]) -> *mut Faces {
    let at: Vec<*const u8> = files.iter().map(|(bytes, _)| bytes.as_ptr()).collect();
    let lengths: Vec<usize> = files.iter().map(|(bytes, _)| bytes.len()).collect();
    let families: Vec<u32> = files.iter().map(|&(_, family)| family).collect();
    // SAFETY: the three hold one each of `files`, alive for the call.
    unsafe { gpu_engine_faces_new(at.as_ptr(), lengths.as_ptr(), families.as_ptr(), files.len()) }
}

/// `text` — one cluster a letter, Latin, Hangul and a simplified
/// character, so each family draws one — as the ABI is handed a run.
fn run_of(letters: *mut Lettering, text: &str, at: [f32; 6]) -> bool {
    let set = run(text, 30 * 64, (5 * 64, 40 * 64), 31 * 64);
    let mut ends = Vec::new();
    let mut origins = Vec::new();
    let mut end = 0;
    for cluster in &set.clusters {
        end += cluster.text.len() as u32;
        ends.push(end);
        origins.extend(cluster.origin);
    }
    // SAFETY: each buffer holds what it is said to.
    unsafe {
        gpu_engine_letters_run(
            letters,
            at.as_ptr(),
            set.size,
            400,
            false,
            text.as_ptr(),
            text.len(),
            ends.as_ptr(),
            origins.as_ptr(),
            ends.len(),
        )
    }
}

/// The straight RGBA8 tiles `lettered` holds, and where.
fn read(engine: &Engine, lettered: *mut Lettered, rect: [i32; 4]) -> ([i32; 4], Vec<u8>) {
    let mut bytes = vec![0; rect[2] as usize * rect[3] as usize * TILE_BYTES as usize];
    // SAFETY: `bytes` holds every tile of `rect`.
    let read = unsafe { gpu_engine_lettered_read(engine, lettered, bytes.as_mut_ptr(), bytes.len()) };
    assert!(read, "{}", last_error());
    // SAFETY: made by `gpu_engine_letters_set`.
    unsafe { gpu_engine_lettered_free(lettered) };
    (rect, bytes)
}

#[test]
fn a_picture_built_call_by_call_is_the_one_built_in_rust() {
    let rig = rig();
    let handed_faces = handed();
    assert!(!handed_faces.is_null(), "{}", last_error());
    let letters = gpu_engine_letters_new();
    // SAFETY: `letters` is live.
    unsafe {
        assert!(gpu_engine_letters_pass(letters, 0xFF20_2020, false, 3 * 64));
        assert!(run_of(letters, "A셀业", WORDS));
        assert!(gpu_engine_letters_pass(letters, 0xC0FF_FFFF, false, 0));
        assert!(run_of(letters, "A셀业", WORDS));
        assert!(gpu_engine_letters_rect(letters, WORDS.as_ptr(), [0, 44 * 64, 100 * 64, 46 * 64].as_ptr()));
    }
    let mut rect = [0; 4];
    // SAFETY: every pointer is live.
    let lettered = unsafe {
        gpu_engine_letters_set(letters, rig.engine, &rig.composite, handed_faces, STAND.as_ptr(), rect.as_mut_ptr())
    };
    assert!(!lettered.is_null(), "{}", last_error());
    let handed = read(rig.engine, lettered, rect);

    let [a, b, c, d, e, f] = STAND;
    let built = set(
        rig.engine,
        &rig.composite,
        faces(),
        Affine { a, b, c, d, e, f },
        &[
            Pass {
                colour: 0xFF20_2020,
                hard: false,
                paint: Paint::Stroke { width: 3 * 64 },
                shapes: here(vec![Shape::Letters(run("A셀业", 30 * 64, (5 * 64, 40 * 64), 31 * 64))]),
            },
            Pass {
                colour: 0xC0FF_FFFF,
                hard: false,
                paint: Paint::Fill,
                shapes: here(vec![
                    Shape::Letters(run("A셀业", 30 * 64, (5 * 64, 40 * 64), 31 * 64)),
                    Shape::Rect([0, 44 * 64, 100 * 64, 46 * 64]),
                ]),
            },
        ],
    )
    .flatten()
    .expect("set");
    let at = built.rect;
    let built = ([at.x0, at.y0, at.columns as i32, at.rows as i32], read_buffer(rig.engine, &built.tiles));
    assert_eq!(handed.0, built.0, "the rectangle");
    assert!(handed.1 == built.1, "the pixels");
    assert!(handed.1.chunks_exact(4).any(|pixel| pixel[3] != 0), "LIVENESS: letters were laid");
    // SAFETY: each came from its `_new`.
    unsafe {
        gpu_engine_letters_free(letters);
        gpu_engine_faces_free(handed_faces);
    }
}

#[test]
fn faces_handed_over_in_no_family_order_are_refused() {
    let biz = file("BIZUDPGothic-Regular.ttf");
    assert!(faces_of(&[(biz.clone(), 1)]).is_null());
    assert!(last_error().contains("family 1"), "{}", last_error());
    assert!(faces_of(&[(biz.clone(), 0), (biz.clone(), 2)]).is_null());
    assert!(last_error().contains("family 2"), "{}", last_error());
    assert!(faces_of(&[(biz, 0), (b"no face".to_vec(), 1)]).is_null());
    assert!(last_error().contains("family 1 holds no face"), "{}", last_error());
    assert!(faces_of(&[]).is_null());
    assert!(last_error().contains("none was given"), "{}", last_error());
}

#[test]
fn a_shape_with_no_pass_to_go_to_is_refused() {
    let letters = gpu_engine_letters_new();
    assert!(!run_of(letters, "A", WORDS));
    assert!(last_error().contains("none was begun"), "{}", last_error());
    // SAFETY: `letters` is live; the rect holds four words.
    unsafe {
        assert!(!gpu_engine_letters_rect(letters, WORDS.as_ptr(), [0, 0, 64, 64].as_ptr()));
        assert!(!gpu_engine_letters_pass(letters, 0xFF00_0000, false, -64));
        assert!(last_error().contains("an outline -64 wide"), "{}", last_error());
        gpu_engine_letters_free(letters);
    }
}

#[test]
fn clusters_that_do_not_cut_the_letters_whole_are_refused() {
    let letters = gpu_engine_letters_new();
    let text = "A셀";
    let ask = |ends: &[u32]| {
        let origins = vec![0; 2 * ends.len()];
        // SAFETY: each buffer holds what it is said to.
        unsafe {
            gpu_engine_letters_run(
                letters,
                WORDS.as_ptr(),
                64,
                400,
                false,
                text.as_ptr(),
                text.len(),
                ends.as_ptr(),
                origins.as_ptr(),
                ends.len(),
            )
        }
    };
    // SAFETY: `letters` is live.
    assert!(unsafe { gpu_engine_letters_pass(letters, 0xFF00_0000, false, 0) });
    assert!(ask(&[1, 4]), "{}", last_error());
    assert!(!ask(&[1]), "short of the letters");
    assert!(last_error().contains("the letters at 4"), "{}", last_error());
    assert!(!ask(&[2, 4]), "inside 셀");
    assert!(!ask(&[1, 1, 4]), "an empty cluster");
    assert!(!ask(&[1, 9]), "past the letters");
    // A run wrong twice over says the first: its weight.
    let origins = [0; 2];
    // SAFETY: each buffer holds what it is said to.
    let twice = unsafe {
        gpu_engine_letters_run(
            letters,
            WORDS.as_ptr(),
            64,
            0,
            false,
            text.as_ptr(),
            text.len(),
            [1].as_ptr(),
            origins.as_ptr(),
            1,
        )
    };
    assert!(!twice);
    assert!(last_error().contains("a weight of 0"), "{}", last_error());
    // SAFETY: made by `gpu_engine_letters_new`.
    unsafe { gpu_engine_letters_free(letters) };
}

#[test]
fn letters_that_cover_nothing_are_no_picture_and_no_failure() {
    let rig = rig();
    let faces = handed();
    let letters = gpu_engine_letters_new();
    // SAFETY: `letters` is live.
    unsafe {
        assert!(gpu_engine_letters_pass(letters, 0xFF00_0000, false, 0));
        assert!(run_of(letters, " ", WORDS));
    }
    let set_in = |to_grid: *const f32| {
        let mut rect = [-1; 4];
        // SAFETY: every pointer is live or null where the ABI says so.
        let lettered =
            unsafe { gpu_engine_letters_set(letters, rig.engine, &rig.composite, faces, to_grid, rect.as_mut_ptr()) };
        (lettered.is_null(), rect)
    };
    assert_eq!(set_in(WORDS.as_ptr()), (true, [0; 4]), "a space: no picture, its rectangle none");
    assert_eq!(set_in(std::ptr::null()), (true, [-1; 4]), "a failure: its rectangle as it was");
    assert!(last_error().contains("no placement was given"), "{}", last_error());
    // SAFETY: each came from its `_new`.
    unsafe {
        gpu_engine_letters_free(letters);
        gpu_engine_faces_free(faces);
    }
}
