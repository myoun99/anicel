import 'dart:convert';
import 'dart:io';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/layer_controls_row_facts.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerRailOptionalColumns, noOptionalRailColumns;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_current_row.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneControlsRow;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🚨Card a-rail-lane-row-is-drawn-again-on-every-host-pass (2026-11-07):
/// A KEPT LANE ROW SEES EVERY FACT IT SHOWS.
///
/// Every host keeps a lane's controls row while the row's facts
/// (`TimelineLaneControlsRow.facts`) answer the same — both grids with the
/// preview their drag gate follows ([laneControlsRowKeptBy]), and the
/// conte's rail — and the lane is one of those facts by identity — so
/// the host hands a layer's lanes back as the same objects while all they
/// are read from holds ([KeptTimelineLanes]). A read left out of either is
/// a row kept across a change of it. This changes one at a time, as the
/// layer row's test does (`a_kept_controls_row_sees_every_fact_it_shows`).
void main() {
  group('a layer\'s lanes, as the host keeps them', () {
    const cutId = CutId('a');
    const celId = LayerId('cel');
    const otherId = LayerId('other');
    const cameraId = LayerId('cam');
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

    late Directory room;
    late InstalledFxPlugins plugins;
    late EditorSessionManager session;
    EditorSessionManager sessionOf() => EditorSessionManager(
      fxPlugins: plugins,
      initialProject: Project(
        id: const ProjectId('kept-lanes'),
        name: 'kept lanes',
        createdAt: DateTime.utc(2026, 11, 7),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [
              Cut(
                id: cutId,
                name: 'a',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: cameraId,
                    name: 'Camera',
                    kind: LayerKind.camera,
                    frames: const [],
                  ),
                  Layer(
                    id: celId,
                    name: 'cel',
                    frames: const [],
                    effects: [
                      LayerEffect.defaults(
                        id: const EffectId('fx-glow'),
                        kind: EffectKind.plugin,
                        plugin: glow,
                      ),
                    ],
                  ),
                  Layer(id: otherId, name: 'other', frames: const []),
                ],
              ),
            ],
          ),
        ],
      ),
    )..selectCut(cutId);

    setUp(() {
      room = Directory.systemTemp.createTempSync('anicel_kept_lanes_');
      plugins = InstalledFxPlugins(
        service: FxPluginLibraryService(directoryPath: '${room.path}/fx'),
        describe: (wasm) => (text: utf8.decode(wasm), refusal: null),
      );
      session = sessionOf();
    });
    tearDown(() {
      session.dispose();
      plugins.dispose();
      deleteTempQuietly(room);
    });

    Layer rowOf(LayerId id) =>
        session.layers.singleWhere((layer) => layer.id == id);
    const open = <String>{};

    test('asked again while nothing changed, the same lanes — the same '
        'objects', () {
      final kept = KeptTimelineLanes();
      for (final id in [cameraId, celId, otherId]) {
        final first = kept.of(
          rowOf(id),
          session: session,
          expandedGroupKeys: open,
        );
        expect(first, isNotEmpty, reason: '⛔premise: $id has lanes');
        expect(
          identical(
            kept.of(rowOf(id), session: session, expandedGroupKeys: open),
            first,
          ),
          isTrue,
          reason: '$id read anew for a pass that changed nothing',
        );
      }
    });

    Future<void> readAgainFor(
      String what,
      LayerId id,
      Future<
        ({Layer layer, EditorSessionManager session, Set<String> open})
      >
      Function()
      change,
    ) async {
      final kept = KeptTimelineLanes();
      final before = kept.of(
        rowOf(id),
        session: session,
        expandedGroupKeys: open,
      );
      final after = await change();
      expect(
        identical(
          kept.of(
            after.layer,
            session: after.session,
            expandedGroupKeys: after.open,
          ),
          before,
        ),
        isFalse,
        reason: 'the lanes are read off $what; kept across its change, '
            'they show it stale',
      );
    }

    // A drag's preview hands the lanes the layer as it would be, with
    // nothing committed.
    test('the layer', () async {
      await readAgainFor('the layer', otherId, () async {
        final previewed = rowOf(otherId).copyWith(name: 'renamed');
        return (layer: previewed, session: session, open: open);
      });
    });

    test('the groups twirled open', () async {
      await readAgainFor('the groups open', otherId, () async {
        final twirled = {laneGroupKey(otherId, transformGroupHeaderLane.laneId)};
        return (layer: rowOf(otherId), session: session, open: twirled);
      });
    });

    test('the rows of the cut', () async {
      final layer = rowOf(otherId);
      await readAgainFor('the rows', otherId, () async {
        session.layerVerbs.renameLayer(celId, 'renamed');
        return (layer: layer, session: session, open: open);
      });
    });

    test('the session', () async {
      final other = sessionOf();
      addTearDown(other.dispose);
      await readAgainFor('the session', otherId, () async {
        return (
          layer: other.layers.singleWhere((layer) => layer.id == otherId),
          session: other,
          open: open,
        );
      });
    });

    test('the plugins this device has', () async {
      final layer = rowOf(celId);
      await readAgainFor('the device\'s plugins', celId, () async {
        await plugins.install(
          ZipEncoder().encodeBytes(
            Archive()..add(
              ArchiveFile.bytes(
                'plugin.wasm',
                utf8.encode(jsonEncode(glowJson)),
              ),
            ),
          ),
          confirm: (_, {required native, required replacing}) async => true,
        );
        return (layer: layer, session: session, open: open);
      });
    });

    test('the camera track a camera drag previews', () async {
      final layer = rowOf(cameraId);
      await readAgainFor('the camera track', cameraId, () async {
        session.dragPreview.value = LaneEditPreview.camera(
          cameraCutId: cutId,
          cameraTrack: TransformTrack.empty().copyWith(
            rotation: PropertyTrack<double>().withKey(0, 45),
          ),
        );
        return (layer: layer, session: session, open: open);
      });
    });

    test('the language', () async {
      final layer = rowOf(otherId);
      final settings = AppText.settings.value;
      addTearDown(() => AppText.settings.value = settings);
      await readAgainFor('the language', otherId, () async {
        AppText.settings.value = settings.copyWith(
          programLanguage: settings.programLanguage == AppLanguage.ja
              ? AppLanguage.en
              : AppLanguage.ja,
        );
        return (layer: layer, session: session, open: open);
      });
    });
  });

  group('a lane\'s controls row', () {
    final layer = Layer(
      id: const LayerId('row'),
      name: 'Row',
      frames: const [],
    );
    const lane = PropertyLaneRow(
      laneId: 'rotation',
      label: 'Rotation',
      keyMarks: {},
    );
    final cursorA = ValueNotifier<int>(0);
    final cursorB = ValueNotifier<int>(0);
    final previewA = ValueNotifier<TimelineDragPreview?>(null);
    final previewB = ValueNotifier<TimelineDragPreview?>(null);
    final standingA = ValueNotifier<TimelineRowAddress?>(null);
    final standingB = ValueNotifier<TimelineRowAddress?>(null);
    const seat = TimelineGraphSeat(
      groupKey: 'row|transform-group',
      graph: LaneGraph(),
      lanes: ['rotation'],
      picked: [],
      pinned: [],
    );

    // What every host keeps a lane's row by: the row's own facts, as the
    // grids hand it with the preview its drag gate follows
    // ([laneControlsRowKeptBy]) and the conte's rail keeps it. Every verb is
    // a fresh closure at every ask, as at every build of a host; [without]
    // names the verbs left off.
    Object? facts({
      Layer? of,
      PropertyLaneRow shows = lane,
      TimelineGraphSeat? graph,
      bool folded = false,
      TimelineGridMetrics metrics = TimelineGridMetrics.defaults,
      Axis axis = Axis.horizontal,
      String keyPrefix = 'timeline',
      double? width,
      double? height,
      double leadingInset = 0,
      LayerRailOptionalColumns optionalColumns = noOptionalRailColumns,
      LaneGraphsView laneGraphs = LaneGraphsView.none,
      ValueListenable<int>? cursor,
      ValueListenable<TimelineDragPreview?>? dragPreview,
      ValueListenable<TimelineRowAddress?>? standing,
      bool linked = false,
      Set<String> without = const {},
    }) {
      bool has(String verb) => !without.contains(verb);
      return laneControlsRowKeptBy(
        TimelineLaneControlsRow(
          layer: of ?? layer,
          lane: shows,
          metrics: metrics,
          frameCursor: cursor ?? cursorA,
          onSelectFrame: has('onSelectFrame') ? (_) {} : null,
          laneEdit: has('laneEdit')
              ? PropertyLaneEditCallbacks(
                  onToggleKeyAt: (_, _, _) {},
                  valueLink: linked
                      ? (
                          changes: ValueNotifier(0),
                          isOn: () => false,
                          toggle: () {},
                        )
                      : null,
                )
              : null,
          onToggleLaneGroup: has('onToggleLaneGroup') ? (_, _) {} : null,
          onToggleLaneGroupEnabled: has('onToggleLaneGroupEnabled')
              ? (_, _) {}
              : null,
          onSetLaneGroupBasis: has('onSetLaneGroupBasis')
              ? (_, _, _) {}
              : null,
          onRasterizeLaneGroup: has('onRasterizeLaneGroup')
              ? (_, _) => null
              : null,
          onResetLaneGroup: has('onResetLaneGroup') ? (_, _) {} : null,
          axis: axis,
          keyPrefix: keyPrefix,
          width: width,
          height: height,
          leadingInset: leadingInset,
          currentRowHooks: TimelineCurrentRowHooks(
            currentRow: standing ?? standingA,
            onStandOnLane: has('onStandOnLane') ? (_, _) {} : null,
            onSettledPress: has('onSettledPress') ? () {} : null,
          ),
          optionalColumns: optionalColumns,
          laneGraphs: laneGraphs,
          laneGraphVerbs: has('laneGraphVerbs')
              ? (
                  toggle: (_) {},
                  togglePin: (_) {},
                  plot: (_, _) {},
                  resize: (_, _) {},
                  enlarge: (_) {},
                  pen: (_) {},
                  transformBox: (_) {},
                  snap: (_) {},
                )
              : null,
          seat: graph,
          folded: folded,
        ),
        dragPreview ?? previewA,
      );
    }

    test('the same facts, asked again, are the same facts — and a verb is '
        'not one', () {
      expect(
        facts(),
        facts(),
        reason: 'fresh verbs at every build would miss the memo at every '
            'build',
      );
    });

    const verbs = {
      'onSelectFrame',
      'laneEdit',
      'onToggleLaneGroup',
      'onToggleLaneGroupEnabled',
      'onSetLaneGroupBasis',
      'onRasterizeLaneGroup',
      'onResetLaneGroup',
      'laneGraphVerbs',
      'onStandOnLane',
      'onSettledPress',
    };
    final changes = <String, Object? Function()>{
      'layer': () => facts(of: layer.copyWith(name: 'Row')),
      // The same lane read again: a new object, its value read anew.
      'lane': () => facts(
        shows: PropertyLaneRow(
          laneId: 'rotation',
          label: 'Rotation',
          keyMarks: const {},
          valueLabel: (_) => '0',
        ),
      ),
      'seat': () => facts(graph: seat),
      'folded': () => facts(folded: true),
      'layerRowHeight': () => facts(
        metrics: TimelineGridMetrics.defaults.copyWith(layerRowHeight: 40),
      ),
      'layerControlsWidth': () => facts(
        metrics: TimelineGridMetrics.defaults.copyWith(
          layerControlsWidth: 500,
        ),
      ),
      'sectionLabelGutterWidth': () => facts(
        metrics: const TimelineGridMetrics(sectionLabelGutterWidth: 30),
      ),
      'railColumns': () => facts(
        metrics: TimelineGridMetrics.defaults.copyWith(
          railColumns: (
            opacity: TimelineGridMetrics.defaults.railColumns.opacity,
            blend: TimelineGridMetrics.defaults.railColumns.blend,
            laneValue: TimelineGridMetrics.defaults.railColumns.laneValue + 10,
          ),
        ),
      ),
      'axis': () => facts(axis: Axis.vertical),
      'keyPrefix': () => facts(keyPrefix: 'xsheet'),
      'width': () => facts(width: 180),
      'height': () => facts(height: 30),
      'leadingInset': () => facts(leadingInset: 12),
      'optionalColumns': () =>
          facts(optionalColumns: (onion: true, blend: false)),
      'laneGraphs': () => facts(
        laneGraphs: const LaneGraphsView(pinned: {'row|rotation'}),
      ),
      'frameCursor': () => facts(cursor: cursorB),
      'dragPreview': () => facts(dragPreview: previewB),
      'currentRow': () => facts(standing: standingB),
      'laneEdit.valueLink': () => facts(linked: true),
      for (final verb in verbs) 'whether there is $verb': () =>
          facts(without: {verb}),
    };
    for (final change in changes.entries) {
      test('${change.key} is a fact the row shows — it must change the '
          'facts', () {
        expect(
          facts() == change.value(),
          isFalse,
          reason: 'the row is given ${change.key}; a kept row that survives '
              'its change shows it stale',
        );
      });
    }
  });
}
