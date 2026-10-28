import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../services/camera_lens_blur_passes.dart';
import '../../services/shaded_passes.dart';
import 'loaded_fragment_program.dart';
import 'raster_picture.dart';

/// Where `iris_gather.frag` reads a column of its table from: a whole
/// number over [irisTableScale] past [irisTableOffset] — its `kTable…`.
const int irisTableOffset = 8192;
const int irisTableScale = 16384;

/// The fragment programs a camera lens blur's rasters run — its row sums
/// (`shaders/row_sum.frag`, [RowSumPass]) and its iris gathered out of them
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

  static final _gather = LoadedFragmentProgram(
    'shaders/iris_gather.frag',
    whyAwaited: _whyAwaited,
  );

  /// Whether [rowSumFor] and [gatherFor] can be called
  /// ([LoadedFragmentProgram.isReady]).
  static bool get isReady => _rowSum.isReady && _gather.isReady;

  /// Loads both programs ([LoadedFragmentProgram.load]).
  static Future<void> load() async {
    await _rowSum.load();
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
  }) =>
      _rowSum.shader()
        ..setFloat(0, source.width.toDouble())
        ..setFloat(1, source.height.toDouble())
        ..setFloat(2, pass.stride.toDouble())
        ..setFloat(3, pass.taps.toDouble())
        // On texel centres, as a sum reads whole pixels; ⚠️and a float
        // raster is not linearly filtered on every GPU.
        ..setImageSampler(0, source);

  /// A shader that draws [pass]'s iris over [sums] — the step's [input]
  /// summed along its rows ([RowSumPass]) — for every pixel of a draw
  /// [input]'s size.
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader gatherFor({
    required ui.Image sums,
    required ui.Image input,
    required IrisGatherPass pass,
  }) {
    assert(
      pass.outline.length <= irisRowsAtMost,
      'iris_gather.frag walks $irisRowsAtMost rows at most',
    );
    final table = _tableOf(pass);
    final perLine = _rowsALine(pass.outline.length);
    // The paper's pixels in the raster, first to last; where none is, the
    // first lies past the last and the cut draws nothing.
    final paper =
        pass.paper ??
        ui.Rect.fromLTWH(0, 0, input.width * 1.0, input.height * 1.0);
    final shader = _gather.shader()
      ..setFloat(0, input.width.toDouble())
      ..setFloat(1, input.height.toDouble())
      ..setFloat(2, pass.reach.toDouble())
      ..setFloat(3, table.width.toDouble())
      ..setFloat(4, table.height.toDouble())
      ..setFloat(5, perLine.toDouble())
      ..setFloat(6, pass.fringe)
      ..setFloat(7, pass.weight)
      ..setFloat(8, pass.paper == null ? 0 : 1)
      ..setFloat(9, math.max(paper.left, 0))
      ..setFloat(10, math.max(paper.top, 0))
      ..setFloat(11, math.min(paper.right, input.width.toDouble()) - 1)
      ..setFloat(12, math.min(paper.bottom, input.height.toDouble()) - 1)
      ..setImageSampler(0, sums)
      ..setImageSampler(1, input)
      ..setImageSampler(2, table);
    // ⚠️Safe once bound: the shader holds its own claim on the table.
    table.dispose();
    return shader;
  }

  /// How many of an iris's [rows] a line of its table holds — two texels
  /// each, so a line is never wider than 2048.
  static int _rowsALine(int rows) => math.min(rows, 1024);

  /// [pass]'s rows as a table `iris_gather.frag` reads: the row `reach`
  /// above the pixel first, two texels each — its outline's left and right
  /// column, then its core's, in red and green.
  ///
  /// 🔬Each a whole number over [irisTableScale] past [irisTableOffset], in
  /// floats: a colour drawn into an `rgbaFloat32` raster comes back as the
  /// float it was given — 0 of 18,432 off under Impeller (10-28, a probe of
  /// 2048×3 texels' red, green and blue).
  static ui.Image _tableOf(IrisGatherPass pass) {
    final rows = pass.outline.length;
    final perLine = _rowsALine(rows);
    final lines = (rows / perLine).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    void lay(int row, int k, IrisSpan span) => canvas.drawRect(
      ui.Rect.fromLTWH(
        ((row % perLine) * 2 + k).toDouble(),
        (row ~/ perLine).toDouble(),
        1,
        1,
      ),
      ui.Paint()
        ..isAntiAlias = false
        ..blendMode = ui.BlendMode.src
        ..color = ui.Color.from(
          alpha: 1,
          red: (span.left + irisTableOffset) / irisTableScale,
          green: (span.right + irisTableOffset) / irisTableScale,
          blue: 0,
        ),
    );
    for (var row = 0; row < rows; row += 1) {
      lay(row, 0, pass.outline[row]);
      if (pass.core.isNotEmpty) {
        lay(row, 1, pass.core[row]);
      }
    }
    return rasterPicture(recorder, perLine * 2, lines, inFloats: true);
  }
}
