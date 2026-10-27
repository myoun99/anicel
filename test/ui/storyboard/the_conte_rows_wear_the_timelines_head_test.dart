import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart'
    show FlipHudAxis;
import 'package:anicel/src/ui/storyboard/storyboard_rows_channel.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerAttachArrowCell;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// 🗣️I-73 (유저 2026-10-08): 「콘티행도 동일하게 하고싶으니까 어태치
/// 접기펼치기버튼등 동일하게 할수있는거 다 넣는거 잊지말고」 · 「콘티레이어
/// 권고한대로 머리만 한벌 ok. 맘에드는생각이야. 겸용컷이랑 같은 느낌이네」 ·
/// 「이거만 눈이랑 불투명도조차 링크하도록. 그거마저 머리로서 하나로되도록
/// 통일」.
///
/// The storyboard's rail draws a track's conte — and every attach row
/// riding it — as rows of its own, and each row's HEAD is the timeline's
/// row: the same widget, on the first cut's layer at that seat, whose every
/// control writes the row at that seat of every cut.
void main() {
  const trackId = TrackId('t1');
  const conteMark = LayerMark(process: LayerProcess.conte);
  const layoutMark = LayerMark(process: LayerProcess.layout);

  Layer conte(String cut, {LayerMark mark = LayerMark.none}) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    mark: mark,
    frames: [Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
  );

  /// An attach row riding [cut]'s conte — free, with one block of its own.
  Layer rider(
    String cut,
    String suffix, {
    required AttachedPlacement placement,
  }) => Layer(
    id: LayerId('$cut-$suffix'),
    name: placement == AttachedPlacement.above ? 'Conte+1' : 'Conte-1',
    kind: LayerKind.storyboard,
    attachedToLayerId: LayerId('$cut-conte'),
    attachedPlacement: placement,
    attachedMode: AttachedMode.free,
    frames: [
      Frame(id: FrameId('$cut-$suffix-1'), duration: 6, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-$suffix-1'), length: 6),
    },
  );

  Layer cel(String cut) => Layer(
    id: LayerId('$cut-cel'),
    name: 'A',
    frames: const [],
    timeline: const {},
  );

  Cut cutOf(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: layers,
  );

  /// Cuts `a` and `b` with a conte, `c` with none.
  Project film({bool withRiders = false, LayerMark aMark = LayerMark.none}) =>
      Project(
        id: const ProjectId('conte-head'),
        name: 'Conte head',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [
          Track(
            id: trackId,
            name: 'V1',
            // An S row: the rail's other row with an fx, an eye and an
            // opacity to stand in column with.
            seLayers: [
              Layer(
                id: const LayerId('t1-s1'),
                name: 'S1',
                kind: LayerKind.se,
                frames: const [],
                timeline: const {},
              ),
            ],
            cuts: [
              cutOf('a', [
                cel('a'),
                if (withRiders)
                  rider('a', 'under', placement: AttachedPlacement.below),
                conte('a', mark: aMark),
                if (withRiders)
                  rider('a', 'over', placement: AttachedPlacement.above),
              ]),
              cutOf('b', [
                cel('b'),
                if (withRiders)
                  rider('b', 'under', placement: AttachedPlacement.below),
                conte('b'),
                if (withRiders)
                  rider('b', 'over', placement: AttachedPlacement.above),
              ]),
              cutOf('c', [cel('c')]),
            ],
          ),
        ],
      );

  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester,
    Project project, {
    TimelineRowFilter rowFilter = TimelineRowFilter.none,
    StoryboardRowsChannel? rowsChannel,
  }) async {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    // The filter as set — the session's, without the chip's own hand-off.
    session.railView.rowFilter.value = rowFilter;
    await pumpStoryboardHostOn(
      tester,
      session,
      surface: const Size(1400, 760),
      pixelsPerFrame: 12,
      rowsChannel: rowsChannel,
    );
    return session;
  }

  Layer row(EditorSessionManager session, String id) {
    for (final track in session.repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        for (final layer in cut.layers) {
          if (layer.id == LayerId(id)) {
            return layer;
          }
        }
      }
    }
    throw StateError('no row $id');
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));
  Finder named(String value) => find.named(value);

  /// The conte row's label at a seat — `conte`, `conte+1`, `conte-1`.
  Finder label(String word) => key('storyboard-$word-label-t1');

  TimelineLayerControlsRow headOf(WidgetTester tester, String word) =>
      tester.widget<TimelineLayerControlsRow>(
        find.descendant(
          of: label(word),
          matching: find.byType(TimelineLayerControlsRow),
        ),
      );

  group('the conte row\'s head', () {
    testWidgets('is the timeline\'s own row, on the first cut\'s conte — '
        'with the cells the proposal names and none of the others', (
      tester,
    ) async {
      await pumpPanel(tester, film());

      expect(label('conte'), findsOneWidget);
      expect(headOf(tester, 'conte').layer.id, const LayerId('a-conte'));
      expect(headOf(tester, 'conte').keyPrefix, 'storyboard');

      // The sheet switch and the onion are the head's, one for every cut
      // (I-89-Q22, 유저 2026-10-19).
      for (final cell in const [
        'mark',
        'fx',
        'visibility',
        'opacity',
        'timesheet',
        'onion',
      ]) {
        expect(
          named('storyboard-layer-$cell-a-conte'),
          findsOneWidget,
          reason: 'the head carries its $cell',
        );
      }
      expect(named('storyboard-layer-blend-a-conte'), findsOneWidget);
      for (final cell in const ['clip', 'link-badge']) {
        expect(
          named('storyboard-layer-$cell-a-conte'),
          findsNothing,
          reason: 'the head mounts no $cell',
        );
      }
      expect(
        named('storyboard-attach-twirl-a-conte'),
        findsNothing,
        reason: 'no attach row rides the conte: nothing to fold',
      );
      // ONE head for the film: cut b's conte draws no row of its own.
      expect(named('storyboard-layer-fx-b-conte'), findsNothing);
    });

    testWidgets('🚨every control writes the conte of every cut', (
      tester,
    ) async {
      final session = await pumpPanel(tester, film());
      List<T> both<T>(T Function(Layer row) read) => [
        read(row(session, 'a-conte')),
        read(row(session, 'b-conte')),
      ];

      await tester.tap(named('storyboard-layer-visibility-a-conte'));
      await tester.pumpAndSettle();
      expect(both((row) => row.isVisible), [false, false], reason: 'eye');

      await tester.tap(named('storyboard-layer-fx-a-conte'));
      await tester.pumpAndSettle();
      expect(
        both((row) => row.transformEnabled),
        [false, false],
        reason: 'fx switch',
      );
      expect(
        headOf(tester, 'conte').fxState,
        isNot(LayerFxState.on),
        reason: 'and the button shows what it wrote',
      );

      await tester.tap(named('storyboard-layer-blend-a-conte'));
      await tester.pumpAndSettle();
      await tester.tap(
        key('storyboard-layer-blend-option-${LayerBlendMode.multiply.name}'),
      );
      await tester.pumpAndSettle();
      expect(
        both((row) => row.blendMode),
        [LayerBlendMode.multiply, LayerBlendMode.multiply],
        reason: 'blend',
      );

      final bar = tester.getRect(named('storyboard-layer-opacity-a-conte'));
      await tester.dragFrom(
        bar.centerRight - const Offset(2, 0),
        Offset(-bar.width / 2, 0),
      );
      await tester.pumpAndSettle();
      final opacities = both((row) => row.opacity);
      expect(opacities.first, lessThan(1), reason: 'LIVENESS: the bar moved');
      expect(opacities.last, opacities.first, reason: 'opacity');
    });

    testWidgets('a press on it picks the ROW — the address every cut '
        'answers to — not the first cut\'s layer', (tester) async {
      final session = await pumpPanel(tester, film());

      await tester.tap(named('storyboard-layer-name-a-conte'));
      await tester.pumpAndSettle();

      expect(
        session.selectedRow,
        LayerRowAddress(trackConteRowId(trackId)),
      );
      expect(headOf(tester, 'conte').active, isTrue);
    });

    testWidgets('stands in the rail\'s own columns: its fx, its eye and its '
        'opacity under an S row\'s, and the blend in the slot every row '
        'keeps', (tester) async {
      await pumpPanel(tester, film());
      const se = 't1-s1';

      for (final cell in const ['fx', 'visibility', 'opacity']) {
        expect(
          tester.getRect(named('storyboard-layer-$cell-a-conte')).left,
          tester.getRect(named('storyboard-layer-$cell-$se')).left,
          reason: 'the $cell column is one column down the rail',
        );
      }
      // The blend is the last column, past the opacity's — on a rail whose
      // other rows have none to show.
      expect(
        tester.getRect(named('storyboard-layer-blend-a-conte')).left,
        greaterThanOrEqualTo(
          tester.getRect(named('storyboard-layer-opacity-a-conte')).right,
        ),
      );
      expect(named('storyboard-layer-blend-$se'), findsNothing);
      expect(
        tester.getRect(label('conte')).width,
        tester
            .getRect(key('storyboard-se-label-t1-1'))
            .width,
        reason: 'and the row is as wide as the rail\'s other rows',
      );
    });

    testWidgets('a sweep down the eye column paints it with the rows above '
        'it', (tester) async {
      final session = await pumpPanel(tester, film());
      const se = 't1-s1';
      final from = tester.getCenter(named('storyboard-layer-visibility-$se'));
      final to = tester.getCenter(named('storyboard-layer-visibility-a-conte'));
      expect(to.dy, greaterThan(from.dy), reason: 'fixture: conte is below');

      final gesture = await tester.startGesture(from);
      for (var step = 1; step <= 6; step += 1) {
        await gesture.moveTo(
          Offset(from.dx, from.dy + (to.dy - from.dy) * step / 6),
        );
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(row(session, 'a-conte').isVisible, isFalse);
      expect(row(session, 'b-conte').isVisible, isFalse);
    });

    testWidgets('the legend\'s filter judges the row on its head — a label '
        'chip the head does not wear hides it, strip and all', (tester) async {
      var filter = TimelineRowFilter.none;
      await pumpPanel(
        tester,
        film(aMark: conteMark),
        rowFilter: filter,
      );
      expect(label('conte'), findsOneWidget);
      expect(key('storyboard-conte-row-t1'), findsOneWidget);

      filter = TimelineRowFilter.none.toggledMark(layoutMark);
      await tester.pumpWidget(const SizedBox());
      await pumpPanel(
        tester,
        film(aMark: conteMark),
        rowFilter: filter,
      );
      expect(label('conte'), findsNothing);
      expect(key('storyboard-conte-row-t1'), findsNothing);

      filter = TimelineRowFilter.none.toggledMark(conteMark);
      await tester.pumpWidget(const SizedBox());
      await pumpPanel(
        tester,
        film(aMark: conteMark),
        rowFilter: filter,
      );
      expect(label('conte'), findsOneWidget, reason: 'LIVENESS: its own chip');
    });

    testWidgets('while no cut has a conte there is no head to wear: the row '
        'keeps its slots, empty', (tester) async {
      await pumpPanel(
        tester,
        Project(
          id: const ProjectId('bare'),
          name: 'Bare',
          createdAt: DateTime.utc(2026, 10, 8),
          tracks: [
            Track(
              id: trackId,
              name: 'V1',
              cuts: [cutOf('a', [cel('a')])],
            ),
          ],
        ),
      );

      expect(label('conte'), findsOneWidget);
      expect(
        find.descendant(
          of: label('conte'),
          matching: find.byType(TimelineLayerControlsRow),
        ),
        findsNothing,
      );
    });
  });

  group('the attach rows riding the conte', () {
    testWidgets('are rows of the rail at their seats — above the conte and '
        'below it — each with the timeline\'s head for an attach row', (
      tester,
    ) async {
      await pumpPanel(tester, film(withRiders: true));

      final over = tester.getRect(label('conte+1'));
      final base = tester.getRect(label('conte'));
      final under = tester.getRect(label('conte-1'));
      expect(over.bottom, base.top, reason: '+1 stands on the conte');
      expect(base.bottom, under.top, reason: 'and -1 hangs under it');

      expect(headOf(tester, 'conte+1').layer.id, const LayerId('a-over'));
      expect(headOf(tester, 'conte-1').layer.id, const LayerId('a-under'));
      // An attach row says which side it rides, and wears its base's fx.
      expect(
        find.descendant(
          of: label('conte+1'),
          matching: find.byType(LayerAttachArrowCell),
        ),
        findsOneWidget,
      );
      expect(named('storyboard-layer-fx-a-over'), findsNothing);
      for (final cell in const ['visibility', 'opacity', 'blend']) {
        expect(
          named('storyboard-layer-$cell-a-over'),
          findsOneWidget,
          reason: 'an attach row keeps its own $cell',
        );
      }
      // A strip a seat.
      expect(key('storyboard-conte-row-t1'), findsOneWidget);
      expect(key('storyboard-conte-row-t1-conte+1'), findsOneWidget);
      expect(key('storyboard-conte-row-t1-conte-1'), findsOneWidget);
      // The twirl is the base's: a row that rides folds nothing.
      expect(named('storyboard-attach-twirl-a-conte'), findsOneWidget);
      expect(named('storyboard-attach-twirl-a-over'), findsNothing);
      expect(named('storyboard-attach-twirl-a-under'), findsNothing);
      // And the button that makes a cut's conte — cut c has none — is the
      // conte row's alone.
      expect(key('storyboard-conte-create-t1'), findsOneWidget);
      expect(key('storyboard-conte-create-t1-conte+1'), findsNothing);
      expect(key('storyboard-conte-create-t1-conte-1'), findsNothing);
    });

    testWidgets('a press on a row that rides, over a cut with no conte, '
        'makes none — the + is the conte row\'s', (tester) async {
      final session = await pumpPanel(tester, film(withRiders: true));
      Layer? conteOfC() => storyboardLayerForCut(
        session.repository.requireProject().tracks.single.cuts.last,
      );
      // Frame 26 is cut c's third frame (12 px a frame).
      Offset overC(String row) {
        final strip = tester.getRect(key(row));
        return strip.topLeft + Offset(26 * 12 + 6, strip.height / 2);
      }

      await tester.tapAt(overC('storyboard-conte-row-t1-conte+1'));
      await tester.pumpAndSettle();
      expect(conteOfC(), isNull);

      await tester.tapAt(overC('storyboard-conte-row-t1'));
      await tester.pumpAndSettle();
      expect(conteOfC(), isNotNull, reason: 'LIVENESS: the conte row\'s +');
    });

    testWidgets('🚨the filter judges each seat on ITS head: a label chip the '
        'conte wears and its rows do not shows the conte alone', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        film(withRiders: true, aMark: conteMark),
        rowFilter: TimelineRowFilter.none.toggledMark(conteMark),
      );

      expect(label('conte'), findsOneWidget);
      expect(label('conte+1'), findsNothing);
      expect(label('conte-1'), findsNothing);
      expect(key('storyboard-conte-row-t1'), findsOneWidget);
      expect(key('storyboard-conte-row-t1-conte+1'), findsNothing);
    });

    testWidgets('🚨a sweep down a column reaches each seat\'s OWN row: the '
        'eye paints all three, and the fx and the sheet switch the '
        'conte\'s alone', (tester) async {
      final session = await pumpPanel(tester, film(withRiders: true));
      const se = 't1-s1';
      const group = ['a-over', 'a-conte', 'a-under'];
      Future<void> sweepDown(String cell) async {
        final from = tester.getCenter(named('storyboard-layer-$cell-$se'));
        final to = tester.getRect(label('conte-1')).center.dy;
        expect(to, greaterThan(from.dy), reason: 'fixture: the group is below');
        final gesture = await tester.startGesture(from);
        for (var step = 1; step <= 8; step += 1) {
          await gesture.moveTo(
            Offset(from.dx, from.dy + (to - from.dy) * step / 8),
          );
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await sweepDown('visibility');
      expect(
        [for (final id in group) row(session, id).isVisible],
        [false, false, false],
        reason: 'the eye: every seat has its own',
      );

      await sweepDown('fx');
      expect(
        [for (final id in group) row(session, id).transformEnabled],
        [true, false, true],
        reason: 'the fx: a row that rides wears its base\'s, and has none',
      );

      final sheetWas = [for (final id in group) row(session, id).onTimesheet];
      bool seOnSheet() => session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .single
          .onTimesheet;
      final seWas = seOnSheet();
      expect(
        sheetWas[1],
        seWas,
        reason: '⛔전제: the conte stands as the S row does, so a sweep that '
            'reaches it moves it',
      );
      await sweepDown('timesheet');
      expect(
        seOnSheet(),
        isNot(seWas),
        reason: 'LIVENESS: the sweep toggled the row it started on',
      );
      expect(
        [for (final id in group) row(session, id).onTimesheet],
        [sheetWas.first, seOnSheet(), sheetWas.last],
        reason: 'the head\'s switch takes the swept value (I-89-Q22); a row '
            'that rides wears none',
      );
    });

    testWidgets('🚨the flip window reads each seat as the row it is — its '
        'name, and its own blocks', (tester) async {
      final channel = StoryboardRowsChannel();
      await pumpPanel(
        tester,
        film(withRiders: true),
        rowsChannel: channel,
      );
      final seats = [
        for (final seat in const [1, 0, -1])
          LayerRowAddress(trackConteRowId(trackId, seat: seat)),
      ];
      final at = [for (final seat in seats) channel.rows.indexOf(seat)];
      expect(at, everyElement(isNonNegative), reason: 'fixture: three rows');
      expect([at[1] - at[0], at[2] - at[1]], [1, 1], reason: 'top row first');

      final hud = channel.snapshotFor(FlipHudAxis.row)!.rows;
      expect(
        [for (final index in at) hud[index].name],
        ['Conte+1', 'Conte', 'Conte-1'],
      );
      // A rider holds six frames a cut, the conte its cut's twelve.
      expect(
        [
          for (final index in at)
            [for (final run in hud[index].runs) run.length],
        ],
        [
          [6, 6],
          [12, 12],
          [6, 6],
        ],
      );
    });

    testWidgets('🚨the conte\'s twirl folds them — on this rail, and in '
        'every cut\'s timeline: the head is one', (tester) async {
      final session = await pumpPanel(tester, film(withRiders: true));
      final twirl = named('storyboard-attach-twirl-a-conte');
      expect(twirl, findsOneWidget);
      expect(headOf(tester, 'conte').groupFoldExpanded, isTrue);

      await tester.tap(twirl);
      await tester.pumpAndSettle();
      expect(headOf(tester, 'conte').groupFoldExpanded, isFalse);

      expect(label('conte+1'), findsNothing);
      expect(label('conte-1'), findsNothing);
      expect(key('storyboard-conte-row-t1-conte+1'), findsNothing);
      expect(label('conte'), findsOneWidget, reason: 'the conte stays');
      expect(
        session.railView.collapsedAttachBaseIds.value,
        containsAll(const [LayerId('a-conte'), LayerId('b-conte')]),
        reason: 'cut b\'s group folds with cut a\'s',
      );

      await tester.tap(twirl);
      await tester.pumpAndSettle();
      expect(label('conte+1'), findsOneWidget, reason: 'and opens again');
      expect(session.railView.collapsedAttachBaseIds.value, isEmpty);
    });

    testWidgets('an attach row\'s eye writes the row at its seat of every '
        'cut', (tester) async {
      final session = await pumpPanel(tester, film(withRiders: true));

      await tester.tap(named('storyboard-layer-visibility-a-over'));
      await tester.pumpAndSettle();

      expect(row(session, 'a-over').isVisible, isFalse);
      expect(row(session, 'b-over').isVisible, isFalse);
      expect(row(session, 'a-under').isVisible, isTrue, reason: 'its seat');
      expect(row(session, 'a-conte').isVisible, isTrue);
    });

    testWidgets('standing on one seats the timeline on the cut\'s own row '
        'at that seat', (tester) async {
      final session = await pumpPanel(tester, film(withRiders: true));
      final strip = tester.getRect(key('storyboard-conte-row-t1-conte+1'));

      // Frame 14 is cut b's third frame (12 px a frame).
      await tester.tapAt(strip.topLeft + Offset(14 * 12 + 6, strip.height / 2));
      await tester.pumpAndSettle();

      expect(
        session.selectedRow,
        LayerRowAddress(trackConteRowId(trackId, seat: 1)),
      );
      expect(session.activeCutId, const CutId('b'));
      expect(session.activeLayerId, const LayerId('b-over'));
      // …and the wash is laid on THAT row's block: cut b's row holds
      // [12, 18) there, where the conte under it holds the cut's twelve.
      final wash = tester.getRect(key('storyboard-standing-wash'));
      expect(wash.top, closeTo(strip.top, 1));
      expect(wash.left, closeTo(strip.left + 12 * 12, 1));
      expect(wash.width, closeTo(6 * 12, 1));
    });

    testWidgets('each seat\'s strip wears its own head\'s colour label', (
      tester,
    ) async {
      await pumpPanel(tester, film(withRiders: true, aMark: conteMark));
      LayerMark shownMark(String row) => (tester
              .widget<CustomPaint>(key('storyboard-conte-cells-$row'))
              .painter!
          as TimelineRowCellsPainter)
          .layer
          .mark;

      expect(shownMark('t1'), conteMark);
      expect(shownMark('t1-conte+1'), LayerMark.none);
      expect(shownMark('t1-conte-1'), LayerMark.none);
    });

    // 🗣️F-489 — the conte's strips are the timeline's rows, so their
    // unnamed heads wear the mark picked in Preferences as well.
    testWidgets('each seat\'s strip wears the unnamed mark picked', (
      tester,
    ) async {
      addTearDown(
        () => AppFrameGridSettings.settings.value =
            const AppFrameGridSettings(),
      );
      await pumpPanel(tester, film(withRiders: true));
      InbetweenMark shownMark(String row) => (tester
              .widget<CustomPaint>(key('storyboard-conte-cells-$row'))
              .painter!
          as TimelineRowCellsPainter)
          .unnamedMark;
      const seats = ['t1', 't1-conte+1', 't1-conte-1'];
      expect([for (final row in seats) shownMark(row)], [
        for (final _ in seats) InbetweenMark.two,
      ]);

      AppFrameGridSettings.settings.value = const AppFrameGridSettings(
        unnamedMark: InbetweenMark.one,
      );
      await tester.pump();
      expect([for (final row in seats) shownMark(row)], [
        for (final _ in seats) InbetweenMark.one,
      ]);
    });
  });
}
