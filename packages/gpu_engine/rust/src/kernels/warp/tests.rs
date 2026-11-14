//! The warp on a real GPU, checked by hand where a map copies whole pixels
//! and against the ledger where it does not — never against a CPU copy of
//! R1 (`kernels/mod.rs` has why). R1 itself is pinned through this pass by
//! shared's tests (`shared::tests::window`).

use std::sync::OnceLock;

use super::{Boxed, Warp, Window};
use crate::device::Engine;
use crate::kernels::composite::tests::mix;
use crate::kernels::mesh::{MeshGrid, MeshOwners, affines};
use crate::kernels::shared::{ResampleMap, ResampleMode, plane, words_buffer};
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    warp: Warp,
    owners: MeshOwners,
}

/// One device and one compile for every test here (blend's tests have
/// why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig { engine, warp: Warp::new(engine), owners: MeshOwners::new(engine) }
    })
}

/// A picture `width` × `height`: a hashed word a pixel, nothing where its
/// alpha would be under 32 (a stored pixel holds no colour without alpha).
fn picture(width: u32, height: u32) -> Vec<u32> {
    (0..width * height)
        .map(|at| mix(at ^ 0x5bd1_e995))
        .map(|word| if word >> 24 < 32 { 0 } else { word })
        .collect()
}

fn words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|four| u32::from_le_bytes([four[0], four[1], four[2], four[3]]))
        .collect()
}

/// `pixels` of a box `size` as a warp reads it.
fn boxed(pixels: &[u32]) -> wgpu::Buffer {
    words_buffer(rig().engine, "warp picture", pixels, wgpu::BufferUsages::STORAGE)
}

/// A mesh dragged from `source` to `destination`.
fn mesh(columns: u32, rows: u32, source: &[[f64; 2]], destination: &[[f64; 2]]) -> MeshGrid {
    MeshGrid {
        columns,
        rows,
        source: source.to_vec(),
        destination: destination.to_vec(),
    }
}

/// `mesh`'s warp of `pixels` — a box `size` whose top-left pixel is at
/// `source_at` on the canvas — into `window`, in `mode`.
fn meshed(
    mesh: &MeshGrid,
    (pixels, size, source_at): (&[u32], (u32, u32), (f64, f64)),
    window: Window,
    mode: ResampleMode,
) -> Option<Vec<u32>> {
    let Rig { engine, warp, owners } = rig();
    let pixels = boxed(pixels);
    let picture = Boxed { pixels: &pixels, size };
    let warped = warp.mesh(engine, (owners, mesh), &picture, source_at, window, 1.0, mode)?;
    Some(words(&read_buffer(engine, &warped)))
}

/// Each pixel's owner in `window`, as the warp reads them.
fn owners(mesh: &MeshGrid, window: Window) -> Vec<u32> {
    let Rig { engine, owners, .. } = rig();
    let owned = owners.owners(engine, mesh, window.at, window.size).expect("owners");
    words(&read_buffer(engine, &owned))
}

/// Pixel (x, y) of the canvas from a box `width` across at its origin, or
/// nothing past it.
fn at(pixels: &[u32], (width, height): (u32, u32), x: i32, y: i32) -> u32 {
    let inside = (0..width as i32).contains(&x) && (0..height as i32).contains(&y);
    if inside { pixels[(y as u32 * width + x as u32) as usize] } else { 0 }
}

const SQUARE: [[f64; 2]; 4] = [[0.0, 0.0], [4.0, 0.0], [0.0, 4.0], [4.0, 4.0]];

/// A mesh at rest copies the picture under it word for word, its maps
/// moving by no pixel, wherever on the canvas the two lie; past the mesh
/// there is nothing.
#[test]
fn a_mesh_at_rest_copies_the_picture_under_it() {
    let pixels = picture(4, 4);
    let square = SQUARE.map(|[x, y]| [x + 10.0, y - 20.0]);
    let rest = mesh(1, 1, &square, &square);
    let window = Window { at: (9, -21), size: (6, 6) };
    let warped = meshed(&rest, (&pixels, (4, 4), (10.0, -20.0)), window, ResampleMode::Blend);
    let wanted: Vec<u32> = (-1..5)
        .flat_map(|y| (-1..5).map(move |x| (x, y)))
        .map(|(x, y)| at(&pixels, (4, 4), x, y))
        .collect();
    assert_eq!(warped.expect("warp"), wanted);
}

/// A pixel takes the map of the triangle that owns it: here the bottom
/// right lands nothing — its corner dragged 30,000 pixels off on the
/// picture, past R1's scale — so its pixels are nothing, and the top left's
/// are the picture's.
#[test]
fn each_pixel_takes_its_owner_s_map_and_nothing_where_it_lands_nothing() {
    let pixels = picture(4, 4);
    let mut source = SQUARE;
    source[3] = [30_000.0, 30_000.0];
    let folded = mesh(1, 1, &source, &SQUARE);
    let maps = affines(&folded, (0.0, 0.0), 1.0, ResampleMode::Blend).expect("maps");
    assert!(maps[0].is_some() && maps[1].is_none(), "the bottom right lands nothing");
    let window = Window { at: (-1, -1), size: (6, 6) };
    let owned = owners(&folded, window);
    assert!(owned.contains(&0) && owned.contains(&1) && owned.contains(&u32::MAX));
    let warped = meshed(&folded, (&pixels, (4, 4), (0.0, 0.0)), window, ResampleMode::Blend);
    let warped = warped.expect("warp");
    let wanted: Vec<u32> = owned
        .iter()
        .enumerate()
        .map(|(index, &owner)| {
            let (x, y) = (index as i32 % 6 - 1, index as i32 / 6 - 1);
            if owner == 0 { at(&pixels, (4, 4), x, y) } else { 0 }
        })
        .collect();
    assert_eq!(warped, wanted);
}

/// One map takes every pixel of a window anywhere in its output: a move by
/// (3, −2) reads the picture there, nothing past it — and with no map,
/// nothing at all. The buffer holds a row past the box, which the window
/// reaches and no pixel reads.
#[test]
fn one_map_takes_every_pixel_of_the_window() {
    let Rig { engine, warp, .. } = rig();
    let pixels = picture(4, 5);
    assert!(pixels[16..].iter().any(|&word| word != 0));
    let buffer = boxed(&pixels);
    let source = Boxed { pixels: &buffer, size: (4, 4) };
    let window = Window { at: (2, -3), size: (6, 7) };
    let moved = ResampleMap::moved(3, -2);
    let warped = warp.one(engine, &source, Some(&moved), window).expect("warp");
    let wanted: Vec<u32> = (-3..4)
        .flat_map(|y| (2..8).map(move |x| (x, y)))
        .map(|(x, y)| at(&pixels, (4, 4), x - 3, y + 2))
        .collect();
    assert_eq!(words(&read_buffer(engine, &warped)), wanted);
    let none = warp.one(engine, &source, None, window).expect("warp");
    assert_eq!(words(&read_buffer(engine, &none)), [0; 42]);
}

/// A mirror at full size — C6's flip, which the app makes as a reorder of
/// rows and columns (`CutPiece.flippedImage`) before any scale — puts every
/// word as it is in every mode, though R1 takes a mirror through the mode's
/// own path and not as its copy; past the box there is nothing.
#[test]
fn a_mirror_at_full_size_puts_every_word_as_it_is() {
    let Rig { engine, warp, .. } = rig();
    let (width, height) = (7, 5);
    let pixels = picture(width, height);
    let buffer = boxed(&pixels);
    let source = Boxed { pixels: &buffer, size: (width, height) };
    let window = Window { at: (-1, -1), size: (width + 2, height + 2) };
    let flip = |on: bool, side: u32| if on { (-1.0, f64::from(side)) } else { (1.0, 0.0) };
    let back = |on: bool, side: u32, at: i32| if on { side as i32 - 1 - at } else { at };
    for (across, down) in [(true, false), (false, true), (true, true)] {
        let ((a, c), (e, f)) = (flip(across, width), flip(down, height));
        let inverse = [a, 0.0, c, 0.0, e, f, 0.0, 0.0, 1.0];
        let wanted: Vec<u32> = (-1..height as i32 + 1)
            .flat_map(|y| (-1..width as i32 + 1).map(move |x| (x, y)))
            .map(|(x, y)| (back(across, width, x), back(down, height, y)))
            .map(|(x, y)| at(&pixels, (width, height), x, y))
            .collect();
        for mode in [ResampleMode::Blend, ResampleMode::Pick, ResampleMode::Nearest] {
            let map = ResampleMap::new(inverse, 1.0, mode, width, height).expect("a mirror lands");
            assert!(!map.is_copy(), "a mirror is not R1's copy");
            let warped = warp.one(engine, &source, Some(&map), window).expect("warp");
            let warped = words(&read_buffer(engine, &warped));
            assert_eq!(warped, wanted, "{mode:?}, across {across}, down {down}");
        }
    }
}

/// A warp refuses a picture its buffer does not hold, a window of no
/// pixels and owners short of the window.
#[test]
fn a_warp_refuses_what_is_not_there() {
    let Rig { engine, warp, .. } = rig();
    let buffer = boxed(&picture(4, 4));
    let moved = ResampleMap::moved(0, 0);
    let window = Window { at: (0, 0), size: (4, 4) };
    let past = Boxed { pixels: &buffer, size: (4, 5) };
    assert!(warp.one(engine, &past, Some(&moved), window).is_none());
    let source = Boxed { pixels: &buffer, size: (4, 4) };
    for size in [(0, 4), (4, 0)] {
        assert!(warp.one(engine, &source, Some(&moved), Window { at: (0, 0), size }).is_none());
    }
    let short = plane(engine, "short owners", 15 * 4);
    assert!(warp.run(engine, &source, &[Some(moved)], Some(&short), window).is_none());
}

/// A 2 × 2 mesh over a 32 × 32 picture, its middle dragged up and right
/// and a corner pulled in, through Blend and Pick: the ledger's. The top
/// left cell's first triangle stays at rest, so its pixels are the
/// picture's word for word in either mode.
#[test]
fn every_device_warps_the_pinned_mesh() {
    let pixels = picture(32, 32);
    let rest: Vec<[f64; 2]> = (0..3)
        .flat_map(|row| (0..3).map(move |column| [16.0 * column as f64, 16.0 * row as f64]))
        .collect();
    let mut dragged = rest.clone();
    dragged[4] = [21.25, 11.5];
    dragged[8] = [28.75, 30.0];
    let warp = mesh(2, 2, &rest, &dragged);
    let window = Window { at: (-2, -2), size: (36, 36) };
    let mut bytes = Vec::new();
    for mode in [ResampleMode::Blend, ResampleMode::Pick] {
        let warped = meshed(&warp, (&pixels, (32, 32), (0.0, 0.0)), window, mode).expect("warp");
        for (x, y) in [(0, 0), (2, 3), (9, 1), (1, 9)] {
            let index = ((y + 2) * 36 + x + 2) as usize;
            assert_eq!(warped[index], at(&pixels, (32, 32), x, y), "{mode:?} at ({x}, {y})");
        }
        bytes.extend(warped.iter().flat_map(|word| word.to_le_bytes()));
    }
    assert_pinned("warp/mesh", &bytes);
}
