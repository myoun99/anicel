import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/lru.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/camera_lens_blur_passes.dart';
import '../../services/shaded_passes.dart';
import 'loaded_fragment_program.dart';
import 'raster_picture.dart';

/// The fragment programs a camera lens blur's rasters run — its row sums
/// (`shaders/row_sum.frag`, [RowSumPass]), the table of its iris's rows
/// (`shaders/iris_table.frag`) and its iris gathered out of the sums by it
/// (`shaders/iris_gather.frag`, [IrisGatherPass]) — each a raster of its
/// own at the identity, as a directional blur's are ([applyEffectSteps],
/// `ShadedEffect`).
class IrisBlurShader {
  IrisBlurShader._();

  static const String _whyAwaited =
      'A composite that reached a camera lens blur with no program would '
      'have to drop the effect, so the load is a prerequisite of offering '
      'it at all.';

  static final _rowSum = LoadedFragmentProgram(
    'shaders/row_sum.frag',
    whyAwaited: _whyAwaited,
  );

  static final _table = LoadedFragmentProgram(
    'shaders/iris_table.frag',
    whyAwaited: _whyAwaited,
  );

  static final _gather = LoadedFragmentProgram(
    'shaders/iris_gather.frag',
    whyAwaited: _whyAwaited,
  );

  /// 🚨THE TABLE LAST LAID, KEPT FOR THE NEXT GATHER OF THE SAME ROWS: a
  /// table is its [IrisRows] alone, and every gather laid its own — a
  /// stroke's every patch, a playback's every frame, over an iris that had
  /// not changed. 🔬Surface Pro 11 (2026-10-31, release,
  /// `tool/probe/iris_table_probe_main.dart`): a table took 0.05–0.4ms at a
  /// radius of 8–40, 1.2ms at 150, 4–5ms at 500 and 11–14ms at 1500, beside
  /// a gather of 3–64ms over 512² to 1920×1080.
  ///
  /// ⚖️ONE: a miss lays it as before, and what is held between gathers is
  /// the one table a gather held while it drew. ⛔Not one for each iris a
  /// cut draws: two lens blurs that differ still lay theirs at each draw —
  /// keeping more is holding past what a draw holds, which the old-device
  /// memory policy leaves to the user, not to this cache.
  ///
  /// ⚠️Let go of while a recorded picture's shader still reads it: safe —
  /// a shader holds its own claim on what it was bound.
  static final Lru<IrisRows, ui.Image> _kept = Lru(
    entryCap: () => 1,
    costOf: _bytesOf,
    letGo: (_, table) => table.dispose(),
  );

  /// What the table kept weighs — the memory census's `lensBlurTables`.
  static int get tableBytes => _kept.held;

  /// The table kept, or null.
  @visibleForTesting
  static ui.Image? get debugKeptTable =>
      _kept.isEmpty ? null : _kept.values.last;

  /// A float a channel: four times a picture of bytes.
  static int _bytesOf(ui.Image table) =>
      4 * estimatedImageBytes(table.width, table.height);

  /// Whether [rowSumFor], [tableFor] and [gatherFor] can be called
  /// ([LoadedFragmentProgram.isReady]).
  static bool get isReady =>
      _rowSum.isReady && _table.isReady && _gather.isReady;

  /// Loads the three programs ([LoadedFragmentProgram.load]).
  static Future<void> load() async {
    await _rowSum.load();
    await _table.load();
    await _gather.load();
  }

  /// A shader that draws [pass] over [source] for every pixel of a draw
  /// [source]'s size — into floats ([RowSumPass]).
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader rowSumFor({
    required ui.Image source,
    required RowSumPass pass,
  }) {
    final shader = _rowSum.shader()
      ..setFloat(0, source.width.toDouble())
      ..setFloat(1, source.height.toDouble())
      ..setFloat(2, pass.stride.toDouble())
      ..setFloat(3, pass.taps.toDouble())
      // On texel centres, as a sum reads whole pixels; ⚠️and a float
      // raster is not linearly filtered on every GPU.
      ..setImageSampler(0, source);
    _setLight(shader, 4, pass.light);
    return shader;
  }

  /// A shader that draws [pass]'s iris over [sums] — the step's [input]
  /// summed along its rows ([RowSumPass]) — for every pixel of a draw
  /// [input]'s size; each pixel's level read off [map] where the pass
  /// reads one ([IrisGatherPass.map]), a raster on [input]'s grid.
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader gatherFor({
    required ui.Image sums,
    required ui.Image input,
    required IrisGatherPass pass,
    ui.Image? map,
  }) {
    assert(
      2 * pass.reach + 1 <= irisRowsAtMost,
      'iris_gather.frag walks $irisRowsAtMost rows at most',
    );
    assert(
      (map == null) == (pass.map == null),
      'a pass that reads a blur map is drawn with one, and only it',
    );
    final rows = pass.rows;
    final layout = _layoutOf(rows);
    final table = _kept.resolve(rows, () => tableFor(rows));
    // The paper's pixels in the raster, first to last; where none is, the
    // first lies past the last and the cut draws nothing.
    final paper =
        pass.paper ??
        ui.Rect.fromLTWH(0, 0, input.width * 1.0, input.height * 1.0);
    final channel = pass.map?.channel;
    final shader = _gather.shader()
      ..setFloat(0, input.width.toDouble())
      ..setFloat(1, input.height.toDouble())
      ..setFloat(2, pass.reach.toDouble())
      ..setFloat(3, table.width.toDouble())
      ..setFloat(4, table.height.toDouble())
      ..setFloat(5, layout.rowsALine.toDouble())
      ..setFloat(6, layout.linesALevel.toDouble())
      ..setFloat(7, pass.iris.fringe / 500)
      ..setFloat(8, pass.paper == null ? 0 : 1)
      ..setFloat(9, math.max(paper.left, 0))
      ..setFloat(10, math.max(paper.top, 0))
      ..setFloat(11, math.min(paper.right, input.width.toDouble()) - 1)
      ..setFloat(12, math.min(paper.bottom, input.height.toDouble()) - 1)
      ..setImageSampler(0, sums)
      ..setImageSampler(1, input)
      ..setImageSampler(2, table)
      // Read for nothing where there is no map: every sampler is bound.
      ..setImageSampler(3, map ?? input);
    _setLight(shader, 13, pass.light);
    shader
      ..setFloat(18, channel == null ? 0 : 1)
      ..setFloat(19, channel?.r ?? 0)
      ..setFloat(20, channel?.g ?? 0)
      ..setFloat(21, channel?.b ?? 0)
      ..setFloat(22, channel?.a ?? 0)
      ..setFloat(23, layout.heads.toDouble());
    return shader;
  }

  /// [rows] as `iris_gather.frag` reads them, laid by `iris_table.frag` in
  /// floats: each of its levels — one, or a blur map's 256 — [_layoutOf]'s
  /// lines, two texels a row, each a span's left and right column in red
  /// and green; then from line `heads` a texel a level, its reach and the
  /// centres its outline and its core cover.
  ///
  /// ⚠️The caller owns the returned image.
  static ui.Image tableFor(IrisRows rows) {
    final layout = _layoutOf(rows);
    final levels = rows.levels;
    final width = layout.rowsALine * 2;
    final height = layout.heads + layout.headLines;
    final halfSide = math.pi / rows.sides;
    final shader = _table.shader()
      ..setFloat(0, width.toDouble())
      ..setFloat(1, height.toDouble())
      ..setFloat(2, layout.rowsALine.toDouble())
      ..setFloat(3, layout.linesALevel.toDouble())
      ..setFloat(4, layout.reach.toDouble())
      ..setFloat(5, rows.radius)
      ..setFloat(6, layout.levels.toDouble())
      ..setFloat(7, levels?.focal ?? 0)
      ..setFloat(8, (levels?.inverts ?? false) ? 1 : 0)
      ..setFloat(9, rows.sides.toDouble())
      ..setFloat(10, rows.roundness)
      ..setFloat(11, rows.aspect)
      // ⚠️Turned here, in doubles: a GPU's sin and cos miss by too much
      // (the shader's uniforms say how much).
      ..setFloat(12, math.cos(rows.rotation))
      ..setFloat(13, math.sin(rows.rotation))
      ..setFloat(14, math.cos(halfSide))
      ..setFloat(15, math.sin(halfSide))
      ..setFloat(16, math.cos(2 * halfSide))
      ..setFloat(17, math.sin(2 * halfSide));
    try {
      // What the shader gives, as it gives it — a column past 1.
      return shadedRaster(shader, width, height, inFloats: true);
    } finally {
      shader.dispose();
    }
  }

  /// How [rows]' table is laid: its rows [reach] either way of a pixel, its
  /// levels, each [linesALevel] lines of [rowsALine] rows — two texels a
  /// row, so a line is never wider than 2048 — and from line [heads] on
  /// their heads, [headLines] of them.
  static ({
    int reach,
    int levels,
    int rowsALine,
    int linesALevel,
    int heads,
    int headLines,
  })
  _layoutOf(IrisRows rows) {
    final reach = rows.radius.floor();
    final count = 2 * reach + 1;
    final rowsALine = math.min(count, 1024);
    final levels = rows.levels == null ? 1 : 256;
    final linesALevel = (count / rowsALine).ceil();
    return (
      reach: reach,
      levels: levels,
      rowsALine: rowsALine,
      linesALevel: linesALevel,
      heads: levels * linesALevel,
      headLines: (levels / (rowsALine * 2)).ceil(),
    );
  }

  /// [light] on [shader] from its float [at] on, as `lens_light.glsl` takes
  /// it: whether there is one, then its gain, threshold, saturation and
  /// whether it reads in linear light.
  static void _setLight(ui.FragmentShader shader, int at, LensLight? light) {
    shader
      ..setFloat(at, light == null ? 0 : 1)
      ..setFloat(at + 1, light?.gain ?? 0)
      ..setFloat(at + 2, light?.threshold ?? 0)
      ..setFloat(at + 3, light?.saturation ?? 0)
      ..setFloat(at + 4, (light?.linear ?? false) ? 1 : 0);
  }
}
