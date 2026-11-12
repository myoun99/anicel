import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late List<FxPluginPicture> lastLayers;

  @override
  Future<void>? get toCome => null;

  @override
  int? reach(Float64List values, FxPluginMoment moment) =>
      reachFails ? null : by ?? values[0].toInt();

  @override
  Future<Uint8List?> render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) async {
    renders += 1;
    inputs.add((
      left: input.left,
      top: input.top,
      width: input.width,
      height: input.height,
    ));
    lastInput = input.pixels;
    lastValues = values;
    lastLayers = layers;
    if (fails) {
      return null;
    }
    final shift = by ?? values[0].toInt();
    final out = Uint8List(input.pixels.length);
    for (var y = 0; y < input.height; y += 1) {
      for (var x = shift; x < input.width; x += 1) {
        final to = (y * input.width + x) * 4;
        final from = to - shift * 4;
        out.setRange(to, to + 4, input.pixels, from);
      }
    }
    return out;
  }

  @override
  void close() {}
}
