import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/plan_plugins.dart' show EngineFxPluginInput;
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show gpuTileSide;

import 'a_canvas_standing_on_a_frame.dart' show theFramesPicture;
import 'fx_plugin_file.dart';
import 'panel_finders.dart' show mainCanvasPanel;
import 'project_scratch_folder.dart';

/// A run of [runner] at [frame], reading [rows], telling [told] how it
/// went.
FxPluginRun fxPluginRunOf(
  FxPluginRunner runner, {
  Map<LayerId, BitmapSurface?> rows = const {},
  int frame = 0,
  void Function({required bool failed})? told,
}) => FxPluginRun(
  runner: runner,
  moment: (frameIndex: frame, time: frame / 24, frameRate: 24, scale: 1),
  rows: rows,
  told: told,
);

/// The stand-in plugin as its file describes it: one with no parameters.
final FxPluginDescription shiftingFxPluginDescription =
    FxPluginDescription.fromJson({
      'spec': 2,
      'id': 'test.shift',
      'name': 'Shift',
      'vendor': 'Test',
      'version': '1',
      'can': ['gpu'],
      'params': <Object?>[],
    })!;

/// The stand-in moving every pixel [by] to the right — across a tile's
/// edge, so no tile of what it makes is a tile's own — as a row's chain
/// runs it.
ResolvedLayerEffect shiftingFxPluginEffect({int by = 1}) => ResolvedLayerEffect(
  kind: EffectKind.plugin,
  plugin: shiftingFxPluginDescription,
  values: const [],
  run: fxPluginRunOf(ShiftingFxPlugin(by: by)),
);

/// The stand-in as a project keeps it on a row.
LayerEffect shiftingFxPluginLayerEffect() => LayerEffect.defaults(
  id: const EffectId('shift'),
  kind: EffectKind.plugin,
  plugin: shiftingFxPluginDescription,
);

/// This device's plugins with the stand-in installed — described [as] says,
/// the stand-in's own description where it says nothing — on a directory of
/// the test's own: its build opens as a [ShiftingFxPlugin] by [by], or as
/// [runner] where told one — or not at all, [opens] false.
Future<InstalledFxPlugins> installedShiftingFxPlugin(
  WidgetTester tester, {
  FxPluginDescription? as,
  int by = 1,
  bool opens = true,
  FxPluginRunner? runner,
}) async {
  final description = as ?? shiftingFxPluginDescription;
  final room = Directory.systemTemp.createTempSync('anicel_fx_shift_');
  deleteAfterSessionEnds(room);
  final plugins = InstalledFxPlugins(
    service: FxPluginLibraryService(directoryPath: '${room.path}/fx'),
    // The stand-in is no WGSL a device would open: no device is asked.
    check: (_) async => (opened: null, refusal: null),
    open: (_, _) => opens ? runner ?? ShiftingFxPlugin(by: by) : null,
  );
  addTearDown(plugins.dispose);
  await tester.runAsync(() async {
    await plugins.load();
    await plugins.install(
      fxPluginFileOf(description),
      confirm: (_, {required replacing}) async => true,
    );
  });
  return plugins;
}

/// Whether the row the canvas draws on runs a plugin: the device's build
/// bound to its chain ([ResolvedLayerEffect.run]), as the canvas's stack
/// hands the row on.
bool theCanvasRowRunsAPlugin(WidgetTester tester) {
  var runs = false;
  mapCompositeLeaves<CanvasStackRow, CanvasStackRow>(
    tester
        .widget<FramePictureView>(theFramesPicture(within: mainCanvasPanel()))
        .nodes,
    (row) {
      if (row case CanvasActiveLayerRow(:final effects)) {
        runs = effects.any(
          (effect) => effect.kind == EffectKind.plugin && effect.run != null,
        );
      }
      return row;
    },
  );
  return runs;
}

/// What a stand-in plug-in reads of [input] — its picture's pixels, or the
/// pixels of its row in slot [row] there — straight RGBA row after row, as
/// the chain kept them on the engine; null where it kept none (no plan ran
/// through it, or no such row). ⚠️Waits for the GPU: the app's own run
/// reads the tiles where they lie.
Uint8List? fxPluginInputPixels(FxPluginInput input, {int? row}) {
  final (:left, :top, :width, :height) = input.picture;
  final (dx, dy) = input.paperOnTheGrid;
  return (input as EngineFxPluginInput).read.reader.pixels((
    left + dx,
    top + dy,
    left + dx + width,
    top + dy + height,
  ), row: row);
}

/// The pixels of each row [input] keeps, by slot ([fxPluginInputPixels]).
List<Uint8List> fxPluginInputRows(FxPluginInput input) {
  final rows = <Uint8List>[];
  while (true) {
    final row = fxPluginInputPixels(input, row: rows.length);
    if (row == null) {
      return rows;
    }
    rows.add(row);
  }
}

/// [straight] — pixels over [input]'s picture, row after row — as tiles of
/// the canvas's grid where it lies, clear past it: what a stand-in plug-in
/// hands back, as the device's run lands its own.
FxPluginTiles fxPluginTilesOf(FxPluginInput input, Uint8List straight) {
  final side = gpuTileSide;
  final buffers = <TileCoord, Uint8List>{};
  _eachSpan(input, (coord, inTile, inPicture, span) {
    buffers
        .putIfAbsent(coord, () => Uint8List(BitmapTile.bytesFor(side)))
        .setRange(inTile, inTile + span * 4, straight, inPicture);
  });
  return {
    for (final MapEntry(key: coord, value: pixels) in buffers.entries)
      coord: BitmapTile(size: side, pixels: pixels),
  };
}

/// [tiles]' pixels over [input]'s picture, straight RGBA row after row —
/// clear where they hold none: what a plug-in's run made, read back.
/// ⚠️Waits for the GPU for a tile the engine alone holds.
Uint8List fxPluginTilesPixels(FxPluginInput input, FxPluginTiles tiles) {
  final (left: _, top: _, :width, :height) = input.picture;
  final out = Uint8List(width * height * 4);
  final read = <TileCoord, Uint8List?>{};
  _eachSpan(input, (coord, inTile, inPicture, span) {
    final pixels = read.putIfAbsent(
      coord,
      () => tiles[coord]?.readPixels((_, view) => Uint8List.fromList(view)),
    );
    if (pixels != null) {
      out.setRange(inPicture, inPicture + span * 4, pixels, inTile);
    }
  });
  return out;
}

/// Each run of [input]'s picture's pixels along a row that lies in one
/// tile of the canvas's grid: that tile, the run's first byte in it and in
/// the picture, and how many pixels it is.
void _eachSpan(
  FxPluginInput input,
  void Function(TileCoord coord, int inTile, int inPicture, int span) span,
) {
  final (:left, :top, :width, :height) = input.picture;
  final (dx, dy) = input.paperOnTheGrid;
  final side = gpuTileSide;
  for (var y = 0; y < height; y += 1) {
    final down = top + dy + y;
    final row = (down / side).floor();
    for (var x = 0; x < width;) {
      final across = left + dx + x;
      final column = (across / side).floor();
      final run = math.min(width - x, (column + 1) * side - across);
      span(
        TileCoord(x: column, y: row),
        ((down - row * side) * side + across - column * side) * 4,
        (y * width + x) * 4,
        run,
      );
      x += run;
    }
  }
}

/// Moves every pixel right by its first value — reaching that far — or by
/// [by] where it is told one.
final class ShiftingFxPlugin implements FxPluginRunner {
  ShiftingFxPlugin({this.by, this.fails = false, this.reachFails = false});

  final int? by;
  final bool fails;
  final bool reachFails;
  int renders = 0;
  final List<({int left, int top, int width, int height})> inputs = [];
  late Uint8List lastInput;
  late Float64List lastValues;

  /// Each row its last run read, by slot: its pixels over the picture.
  late List<Uint8List> lastLayers;
  late FxPluginMoment lastMoment;

  @override
  Future<void>? get toCome => null;

  @override
  int? reach(Float64List values, FxPluginMoment moment) =>
      reachFails ? null : by ?? values[0].toInt();

  @override
  Future<FxPluginTiles?> render({
    required FxPluginInput input,
    required Float64List values,
    required FxPluginMoment moment,
  }) async {
    renders += 1;
    final (left: _, top: _, :width, :height) = input.picture;
    inputs.add(input.picture);
    final pixels = fxPluginInputPixels(input);
    if (pixels == null) {
      return null;
    }
    lastInput = pixels;
    lastValues = values;
    lastLayers = fxPluginInputRows(input);
    lastMoment = moment;
    if (fails) {
      return null;
    }
    final shift = by ?? values[0].toInt();
    final out = Uint8List(pixels.length);
    for (var y = 0; y < height; y += 1) {
      for (var x = shift; x < width; x += 1) {
        final to = (y * width + x) * 4;
        final from = to - shift * 4;
        out.setRange(to, to + 4, pixels, from);
      }
    }
    return fxPluginTilesOf(input, out);
  }

  @override
  void close() => closed = true;

  @override
  bool closed = false;
}
