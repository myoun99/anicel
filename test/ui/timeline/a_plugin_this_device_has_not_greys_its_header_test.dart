import 'dart:convert';
import 'dart:io';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🗣️I-132-Q28 a 「Fx 목록에 그 fx 가 회색으로 남고 값 · 키도 그대로 … 설치하면
/// 그대로 다시 걸린다」: an effect of a plugin this device has not keeps its
/// header and its lanes, the header greyed — and the device's one list
/// answers it, so an install ungreys it in every open project.
void main() {
  late Directory room;
  setUp(() => room = Directory.systemTemp.createTempSync('anicel_fx_grey_'));
  tearDown(() => deleteTempQuietly(room));

  final glowJson = {
    'spec': 1,
    'id': 'com.example.glow',
    'name': 'Glow',
    'vendor': 'Example',
    'version': '1',
    'can': ['cpu'],
    'params': [
      {
        'id': 'amount',
        'kind': 'number',
        'label': 'Amount',
        'default': 5,
        'min': 0,
        'max': 10,
      },
    ],
  };
  final glow = FxPluginDescription.fromJson(glowJson)!;
  const id = EffectId('fx-glow');
  final effect = LayerEffect.defaults(
    id: id,
    kind: EffectKind.plugin,
    plugin: glow,
  );

  test('the header of one the device has not greys, its lanes kept — one '
      'it has, an app kind\'s and a rail not told the device\'s do not', () {
    final asked = <FxPluginDescription>[];
    final rows = effectPropertyLanes(
      [
        effect,
        LayerEffect.defaults(id: const EffectId('fx-b'), kind: EffectKind.blur),
      ],
      isExpanded: (_) => true,
      hasPlugin: (plugin) {
        asked.add(plugin);
        return false;
      },
    );

    expect(asked, [glow]);
    expect(
      [
        for (final row in rows)
          if (row.isGroupHeader) row.pluginNotOnDevice,
      ],
      [true, false],
    );
    expect(rows[1].laneId, effectLaneId(id, 'amount'));
    expect(
      effectPropertyLanes(
        [effect],
        isExpanded: (_) => false,
        hasPlugin: (_) => true,
      ).single.pluginNotOnDevice,
      isFalse,
    );
    expect(
      effectPropertyLanes(
        [effect],
        isExpanded: (_) => false,
      ).single.pluginNotOnDevice,
      isFalse,
    );
  });

  test('a cut\'s rail asks the device\'s list, and an install ungreys it — '
      'heard by the project until it is closed', () async {
    final plugins = InstalledFxPlugins(
      service: FxPluginLibraryService(directoryPath: '${room.path}/fx'),
      describe: (wasm) => (text: utf8.decode(wasm), refusal: null),
    );
    addTearDown(plugins.dispose);
    final session = EditorSessionManager(
      fxPlugins: plugins,
      initialProject: Project(
        id: const ProjectId('grey'),
        name: 'grey',
        createdAt: DateTime.utc(2026, 10, 30),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [
              Cut(
                id: const CutId('a'),
                name: 'a',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: const LayerId('cel'),
                    name: 'cel',
                    frames: const [],
                    effects: [effect],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    )..selectCut(const CutId('a'));
    bool greyed() {
      final lanes = timelineLanesForLayer(
        layer: session.layers.singleWhere(
          (row) => row.id == const LayerId('cel'),
        ),
        session: session,
        expandedGroupKeys: const {},
      );
      return lanes
          .singleWhere((lane) => lane.laneId == effectGroupLaneId(id))
          .pluginNotOnDevice;
    }
    var heard = 0;
    session.addListener(() => heard += 1);

    expect(greyed(), isTrue);
    await plugins.install(
      ZipEncoder().encodeBytes(
        Archive()..add(
          ArchiveFile.bytes('plugin.wasm', utf8.encode(jsonEncode(glowJson))),
        ),
      ),
      confirm: (_, {required native, required replacing}) async => true,
    );
    expect(heard, 1);
    expect(greyed(), isFalse);

    session.dispose();
    // A project closed is off the list: one that still heard it would be
    // told after it is gone, and the list would report what that threw.
    final reported = <FlutterErrorDetails>[];
    final reportsBefore = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = reportsBefore);
    await plugins.uninstall(glow.id);
    FlutterError.onError = reportsBefore;
    expect(reported, isEmpty);
  });

  testWidgets('the header greys as the rail\'s off glyphs do', (tester) async {
    Future<Color?> labelColour({required bool notOnDevice}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 40,
              child: TimelineLaneControlsRow(
                layer: Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  frames: const [],
                ),
                lane: PropertyLaneRow(
                  laneId: effectGroupLaneId(id),
                  label: 'Glow',
                  keyMarks: const {},
                  isGroupHeader: true,
                  groupEnabled: true,
                  pluginNotOnDevice: notOnDevice,
                ),
                metrics: TimelineGridMetrics.defaults,
              ),
            ),
          ),
        ),
      );
      return tester.widget<Text>(find.text('Glow')).style?.color;
    }

    final onSurface = ThemeData().colorScheme.onSurface;
    expect(await labelColour(notOnDevice: false), onSurface);
    expect(
      await labelColour(notOnDevice: true),
      onSurface.withValues(alpha: 0.35),
    );
  });
}
