import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/text/word_bake.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/line_on_screen.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/room_for_the_pills.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/timeline_host.dart';
import 'tile_store_idle.dart';

/// 🔬I-22-rest (11-01, S5_BA 컷352, 디버그): a click on a rail row built the
/// whole timeline host, 195 widgets and 9ms, for a colour on two rows and
/// the cursor's wash. A stand is no news to the host now: what shows it hears
/// it itself.
///
/// 🚨The proof is the screen. A stand that left something behind shows
/// something a build would change, so every case here is read twice: as the
/// stand left it, and after the host is made to build. Equal pixels are what
/// says no reader of the stand was left out; a list of readers could not.
void main() {
  /// The screen once the cell tiles and the narrowed words have landed and
  /// been painted.
  ///
  /// 🚨A TILE THAT LANDS BETWEEN THE TWO READS CHANGES THE SCREEN WHATEVER
  /// THE STAND DID. 🔬At 512 px spans the X-sheet's tiles were still landing
  /// at both reads (11-07): four lines of a cell row moved by a few
  /// levels, with or without the build, and the case went red in a run of
  /// the file and green alone. ↩️It read the screen at once.
  ///
  /// And so does a word: 🔬the X-sheet's rail narrows a row's name, whose
  /// bake the GPU engine lands in real time (grid-on-the-engine ③) — one
  /// word was waited for at the first read, and 2098 bytes of the plate had
  /// moved by the second (11-08). ↩️It waited for the tiles alone.
  Future<ByteData> landedPixels(WidgetTester tester) async {
    final store = TimelineGridTileStore.instance;
    final words = BakedWords.instance;
    for (var round = 0; round < 20; round += 1) {
      await tileStoreIdle(store, tester: tester);
      await settleAsync(tester, () => words.debugWaitingWords == 0);
      await tester.pump();
      if (!store.debugBusy && words.debugWaitingWords == 0) {
        return screenPixels(tester);
      }
    }
    fail('a pump kept asking the tile store or the word bakes for more');
  }

  Future<void> expectBuildChangesNothing(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    final stood = await landedPixels(tester);
    final panel = tester.widget(find.byType(TimelinePanel));
    session.notifyChanged();
    await tester.pump();
    expect(
      identical(tester.widget(find.byType(TimelinePanel)), panel),
      isFalse,
      reason: 'LIVENESS: the host was made to build',
    );
    final built = await landedPixels(tester);
    var differing = 0;
    for (var byte = 0; byte < built.lengthInBytes; byte += 1) {
      if (built.getUint8(byte) != stood.getUint8(byte)) {
        differing += 1;
      }
    }
    expect(built.lengthInBytes, stood.lengthInBytes);
    expect(differing, 0, reason: 'a build changed what the stand left');
  }

  for (final (orientation, prefix) in const [
    (TimelineOrientation.horizontal, 'timeline'),
    (TimelineOrientation.vertical, 'xsheet'),
  ]) {
    Future<EditorSessionManager> open(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return pumpTimelineHost(
        tester,
        createDefaultProject(),
        surface: const Size(1400, 1000),
        orientation: orientation,
        pixelsPerFrame: 24,
      );
    }

    LayerId stoodOnRow(WidgetTester tester) => tester
        .widget<TimelineLayerControlsRow>(
          find.ancestor(
            of: find.named('$prefix-selected-layer'),
            matching: find.byType(TimelineLayerControlsRow),
          ),
        )
        .layer
        .id;

    testWidgets('$prefix: a click stands on a row and builds no panel', (
      tester,
    ) async {
      final session = await open(tester);
      final from = session.activeLayerId!;
      final next = session.layers.firstWhere((row) => row.id != from).id;
      final panel = tester.widget(find.byType(TimelinePanel));

      await tester.tapAt(
        tester.getCenter(find.named('$prefix-layer-name-${next.value}')),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(session.activeLayerId, next, reason: 'LIVENESS: it stood');
      expect(stoodOnRow(tester), next);
      expect(
        identical(tester.widget(find.byType(TimelinePanel)), panel),
        isTrue,
      );
      await expectBuildChangesNothing(tester, session);
    });

    testWidgets('$prefix: a stand on a lane shows what a build shows', (
      tester,
    ) async {
      final session = await open(tester);
      final layer = session.activeLayerId!;
      session.layerSwitches.toggleLayerLanes(layer);
      await tester.pumpAndSettle();
      final other = session.layers.firstWhere((row) => row.id != layer).id;
      session.standOnRow(LayerRowAddress(other));
      await tester.pump();

      session.standOnRow(LaneRowAddress(layer, 'position'));
      await tester.pump();

      expect(session.activeLayerId, layer, reason: 'LIVENESS: it stood');
      await expectBuildChangesNothing(tester, session);
    });

    testWidgets('$prefix: a stand under a filter brings the row it spares', (
      tester,
    ) async {
      final session = await open(tester);
      final from = session.activeLayerId!;
      final next = session.layers.firstWhere((row) => row.id != from).id;
      session.railView.rowFilter.value = const TimelineRowFilter(
        kinds: {LayerKind.folder},
      );
      await tester.pump();
      final hidden = find.named('$prefix-layer-name-${next.value}');
      expect(hidden, findsNothing, reason: '⛔전제');

      session.selectLayer(next);
      await tester.pump();

      expect(hidden, findsOneWidget);
      expect(find.named('$prefix-layer-name-${from.value}'), findsNothing);
      await expectBuildChangesNothing(tester, session);
    });

    testWidgets('$prefix: a stand under a solo moves the eyes', (tester) async {
      final session = await open(tester);
      final from = session.activeLayerId!;
      final next = session.layers.firstWhere((row) => row.id != from).id;
      session.visibilitySolo.toggleLayerVisibilitySolo();
      await tester.pump();
      expect(
        session.layerSwitches.isLayerEyeOn(next),
        isFalse,
        reason: '⛔전제',
      );

      session.selectLayer(next);
      await tester.pump();

      expect(session.layerSwitches.isLayerEyeOn(next), isTrue);
      await expectBuildChangesNothing(tester, session);
    });
  }

  testWidgets('the tab in the app hears the session through that door', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(appWindowWithRoomForItsPills);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AnicelApp());
    await tester.pump();
    final session = timelineSessionOf(tester);
    final from = session.activeLayerId;
    final next = session.layers.firstWhere((row) => row.id != from).id;
    final panel = tester.widget(find.byType(TimelinePanel));

    session.selectLayer(next);
    await tester.pump();
    expect(session.activeLayerId, next, reason: 'LIVENESS: it stood');
    expect(
      identical(tester.widget(find.byType(TimelinePanel)), panel),
      isTrue,
      reason: 'a stand builds no panel',
    );

    session.notifyChanged();
    await tester.pump();
    expect(
      identical(tester.widget(find.byType(TimelinePanel)), panel),
      isFalse,
      reason: 'any other news does',
    );
  });

  group('what a stand announces', () {
    EditorSessionManager open() {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      return session;
    }

    LayerId anotherThan(EditorSessionManager session) => session.layers
        .firstWhere((row) => row.id != session.activeLayerId)
        .id;

    test('every listener hears it, and the news does not move', () {
      final session = open();
      final news = session.newsRevision;
      var heard = 0;
      session.addListener(() => heard += 1);

      session.selectLayer(anotherThan(session));

      expect(heard, 1);
      expect(session.newsRevision, news);
    });

    test('any other announcement moves the news', () {
      final session = open();
      final news = session.newsRevision;

      session.notifyChanged();

      expect(session.newsRevision, news + 1);
    });

    test('standing where it stands announces nothing', () {
      final session = open();
      var heard = 0;
      session.addListener(() => heard += 1);

      session.selectLayer(session.activeLayerId!);

      expect(heard, 0);
    });

    test('a stand that clears a range is news', () {
      final session = open();
      final next = anotherThan(session);
      session.updateFrameRangeSelectionDrag(
        layerId: session.activeLayerId!,
        anchorIndex: 0,
        headIndex: 1,
      );
      expect(session.frameRangeSelection.value, isNotNull, reason: '⛔전제');
      final news = session.newsRevision;

      session.selectLayer(next);

      expect(session.frameRangeSelection.value, isNull);
      expect(session.newsRevision, greaterThan(news));
    });

    test('a stand under a filter is news', () {
      final session = open();
      session.railView.rowFilter.value = const TimelineRowFilter(
        kinds: {LayerKind.folder},
      );
      final news = session.newsRevision;

      session.selectLayer(anotherThan(session));

      expect(session.newsRevision, greaterThan(news));
    });

    test('a stand under a solo is news', () {
      final session = open();
      session.visibilitySolo.toggleLayerVisibilitySolo();
      final news = session.newsRevision;

      session.selectLayer(anotherThan(session));

      expect(session.newsRevision, greaterThan(news));
    });

    test('the active layer is told when it moves, through any door', () {
      final session = open();
      final told = session.standing.activeLayerListenable;
      var heard = 0;
      void hear() => heard += 1;
      told.addListener(hear);
      addTearDown(() => told.removeListener(hear));
      expect(told.value, session.activeLayerId);

      final next = anotherThan(session);
      session.selectLayer(next);
      expect((heard, told.value), (1, next));

      session.selectLayer(next);
      expect(heard, 1, reason: 'it did not move');

      session.layerStack.addLayer();
      expect(session.activeLayerId, isNot(next), reason: '⛔전제');
      expect((heard, told.value), (2, session.activeLayerId));
    });
  });

  group('with nothing above built again', () {
    Layer row(String id) => Layer(
      id: LayerId(id),
      name: id,
      frames: [Frame(id: const FrameId('cel'), duration: 1, strokes: const [])],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('cel'), length: 1),
      },
    );

    final layers = [row('a'), row('b'), row('c')];

    TimelineGridHooks hooks(
      ValueListenable<LayerId?> activeLayer,
      ValueListenable<int> cursor,
    ) => TimelineGridHooks(
      activeLayer: activeLayer,
      frameCursor: cursor,
      playbackFrameCount: 24,
      exposureStateForLayer: exposureOf,
      onSelectLayer: (_) {},
      onSelectFrame: (_) {},
      onToggleLayerVisibility: (_) {},
      onLayerOpacityChanged: (_, _) {},
      onToggleLayerTimesheet: (_) {},
      onLayerMarkSelected: (_, _) {},
    );

    for (final (prefix, grid) in <(String, Widget Function(TimelineGridHooks))>[
      (
        'timeline',
        (hooks) => LayerTimelineGrid(hooks: hooks, layers: layers),
      ),
      (
        'xsheet',
        (hooks) => XSheetTimelineGrid(hooks: hooks, layers: layers),
      ),
    ]) {
      testWidgets('$prefix: the plate, the sheet and the wash hear a stand', (
        tester,
      ) async {
        final active = ValueNotifier<LayerId?>(const LayerId('a'));
        final cursor = ValueNotifier(0);
        addTearDown(active.dispose);
        addTearDown(cursor.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: grid(hooks(active, cursor))),
          ),
        );

        LayerId plate() => tester
            .widget<TimelineLayerControlsRow>(
              find.ancestor(
                of: find.named('$prefix-selected-layer'),
                matching: find.byType(TimelineLayerControlsRow),
              ),
            )
            .layer
            .id;
        List<Color> sheet() => [
          for (final row
              in tester
                  .widget<TimelineGridSheet>(
                    find.descendant(
                      of: find.byKey(ValueKey<String>('$prefix-grid-sheet')),
                      matching: find.byType(TimelineGridSheet),
                    ),
                  )
                  .rows
                  .rows)
            row.ground,
        ];
        Rect wash() =>
            tester.getRect(find.byKey(const ValueKey('timeline-standing-wash')));

        final sheetBefore = sheet();
        final washBefore = wash();
        expect(plate(), const LayerId('a'));

        active.value = const LayerId('b');
        await tester.pump();

        expect(plate(), const LayerId('b'));
        expect(sheet(), isNot(sheetBefore));
        expect(wash(), isNot(washBefore));
      });
    }
  });
}
