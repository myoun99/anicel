import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/cel_source_effect_pass.dart'
    show celSourcePlugin;
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'temp_dir.dart';

/// A run of [runner] at [frame], reading [rows].
FxPluginRun fxPluginRunOf(
  FxPluginRunner runner, {
  Map<LayerId, BitmapSurface?> rows = const {},
  int frame = 0,
}) => FxPluginRun(
  runner: runner,
  moment: (frameIndex: frame, time: frame / 24, frameRate: 24, scale: 1),
  rows: rows,
);

/// The stand-in plugin as its file describes it: one with no parameters.
final FxPluginDescription shiftingFxPluginDescription =
    FxPluginDescription.fromJson({
      'spec': 1,
      'id': 'test.shift',
      'name': 'Shift',
      'vendor': 'Test',
      'version': '1',
      'can': ['cpu'],
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
/// the test's own: its build opens as a [ShiftingFxPlugin] by one.
Future<InstalledFxPlugins> installedShiftingFxPlugin(
  WidgetTester tester, {
  FxPluginDescription? as,
}) async {
  final description = as ?? shiftingFxPluginDescription;
  final room = Directory.systemTemp.createTempSync('anicel_fx_shift_');
  addTearDown(() => deleteTempQuietly(room));
  final plugins = InstalledFxPlugins(
    service: FxPluginLibraryService(directoryPath: '${room.path}/fx'),
    // The stand-in's module is its description's text.
    describe: (wasm) => (text: utf8.decode(wasm), refusal: null),
    open: (_, _) => ShiftingFxPlugin(by: 1),
  );
  addTearDown(plugins.dispose);
  await tester.runAsync(() async {
    await plugins.load();
    await plugins.install(
      ZipEncoder().encodeBytes(
        Archive()..add(
          ArchiveFile.bytes(
            'plugin.wasm',
            utf8.encode(jsonEncode(description.toJson())),
          ),
        ),
      ),
      confirm: (_, {required native, required replacing}) async => true,
    );
  });
  return plugins;
}

/// Whether the row the canvas draws on runs a plugin: the device's build
/// bound to its chain ([celSourcePlugin]).
bool theCanvasRowRunsAPlugin(WidgetTester tester) =>
    celSourcePlugin(
      tester
          .widget<MainCanvasBrushHost>(find.byType(MainCanvasBrushHost))
          .activeSourceEffects,
    ) !=
    null;

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
  int? reach(Float64List values, FxPluginMoment moment) =>
      reachFails ? null : by ?? values[0].toInt();

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
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
