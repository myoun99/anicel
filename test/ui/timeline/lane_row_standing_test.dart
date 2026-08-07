import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart'
    show VerticalWritingText;
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show railSelectedRowColor;

/// R10 #19's RAIL half: the row you are standing on is drawn, and a
/// property lane's LABEL is a place you can stand.
///
/// Standing itself shipped in R10 R2 — the address type, the verb routing,
/// the ↑/↓ nav — but only through the frame side: you could press a lane's
/// BAND and nothing else, and nothing on screen said which row had it. The
/// two halves pinned here are what make it a thing you can see and aim,
/// and what the row-order drag will grab next.

/// The widget keys spell the id out, so the tests need it as a STRING too
/// (a `LayerId` cannot be interpolated into a const key).
const _cameraId = 'lane-cam-layer';
const _cameraLayerId = LayerId(_cameraId);
const _drawLayerId = LayerId('lane-draw-layer');

Project _project() {
  return Project(
    id: const ProjectId('standing-project'),
    name: 'Standing Project',
    createdAt: DateTime.utc(2026, 8, 7),
    tracks: [
      Track(
        id: const TrackId('standing-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('standing-cut'),
            name: 'Standing Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              Layer(id: _drawLayerId, name: 'Drawing', frames: const []),
              Layer(
                id: _cameraLayerId,
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
}

Future<void> _openLanes(
  WidgetTester tester, {
  String keyPrefix = 'timeline',
}) async {
  await tester.tap(
    find.byKey(ValueKey<String>('$keyPrefix-lane-toggle-$_cameraId')),
  );
  await tester.pumpAndSettle();
  final groupToggle = find.byKey(
    ValueKey<String>('$keyPrefix-lane-group-toggle-$_cameraId-transform-group'),
  );
  await tester.ensureVisible(groupToggle);
  await tester.pumpAndSettle();
  await tester.tap(groupToggle);
  await tester.pumpAndSettle();
}

Finder _laneLabel(String laneId, {String keyPrefix = 'timeline'}) =>
    find.byKey(ValueKey<String>('$keyPrefix-lane-label-$_cameraId-$laneId'));

/// The label's PLATE — what says "you are standing here".
Color _plateOf(WidgetTester tester, Finder label) {
  final container = tester.widget<Container>(label);
  return (container.decoration! as BoxDecoration).color!;
}

/// Presses the lane's NAME, which is the part of the label that belongs to
/// no control: tapping the cell's centre would be a coin flip between the
/// value readout and empty space.
Future<void> _pressLaneName(
  WidgetTester tester,
  String laneId,
  String name, {
  String keyPrefix = 'timeline',
}) async {
  final label = _laneLabel(laneId, keyPrefix: keyPrefix);
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  // The sheet stands its names up, so the name is a VerticalWritingText
  // there and a plain Text on the rail — one finder covers both.
  final laneName = find.descendant(
    of: label,
    matching: find.byWidgetPredicate(
      (widget) =>
          (widget is Text && widget.data == name) ||
          (widget is VerticalWritingText && widget.text == name),
    ),
  );
  await tester.tap(laneName, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  group('standing on a property lane from its label', () {
    testWidgets('pressing the name takes the lane as the current row, and '
        'leaves the playhead where it was', (tester) async {
      await _pump(tester);
      await _openLanes(tester);
      final session = _sessionOf(tester);
      session.selectFrameIndex(5);
      await tester.pumpAndSettle();
      expect(session.currentRow, isA<LayerRowAddress>());

      await _pressLaneName(tester, 'position', 'Position');

      expect(
        session.currentRow,
        const LaneRowAddress(_cameraLayerId, 'position'),
      );
      // Standing is not seeking: a label names a ROW.
      expect(session.currentFrameIndex, 5);
    });

    testWidgets('exactly the current row wears the wash', (tester) async {
      await _pump(tester);
      await _openLanes(tester);
      final washed = railSelectedRowColor(
        Theme.of(tester.element(find.byType(EditorWorkspace))).colorScheme,
      );

      // Nothing stood on yet: every lane is an ordinary plate.
      expect(_plateOf(tester, _laneLabel('position')), AppColors.washDown);
      expect(_plateOf(tester, _laneLabel('scale')), AppColors.washDown);

      await _pressLaneName(tester, 'position', 'Position');

      expect(_plateOf(tester, _laneLabel('position')), washed);
      expect(_plateOf(tester, _laneLabel('scale')), AppColors.washDown);

      // And it MOVES — the row that lost it repaints too.
      await _pressLaneName(tester, 'scale', 'Scale');

      expect(_plateOf(tester, _laneLabel('position')), AppColors.washDown);
      expect(_plateOf(tester, _laneLabel('scale')), washed);
    });

    testWidgets('the group header lights while you stand INSIDE it', (
      tester,
    ) async {
      await _pump(tester);
      await _openLanes(tester);
      final washed = railSelectedRowColor(
        Theme.of(tester.element(find.byType(EditorWorkspace))).colorScheme,
      );
      expect(
        _plateOf(tester, _laneLabel('transform-group')),
        AppColors.washDown,
      );

      await _pressLaneName(tester, 'position', 'Position');

      // The chain reads as a chain: the property AND the group that holds
      // it, in the same wash — which of them you are on is answered on the
      // frame side (user, 2026-08-07: "심플하게 가고싶어").
      expect(_plateOf(tester, _laneLabel('position')), washed);
      expect(_plateOf(tester, _laneLabel('transform-group')), washed);

      // A lane of the SAME group lights its header too; leaving for the
      // header itself keeps it lit and drops the member.
      await _pressLaneName(tester, 'transform-group', 'Transform');
      expect(_plateOf(tester, _laneLabel('transform-group')), washed);
      expect(_plateOf(tester, _laneLabel('position')), AppColors.washDown);
    });

    testWidgets('the frame side marks the LANE, and the layer row gives its '
        'ring up — there is one standing place', (tester) async {
      await _pump(tester);
      await _openLanes(tester);
      const cellRing = ValueKey<String>('timeline-selected-cell');
      const laneMark = ValueKey<String>('timeline-lane-standing-cell');

      // Standing on the layer row: the ring is on the cells.
      expect(find.byKey(cellRing), findsOneWidget);
      expect(find.byKey(laneMark), findsNothing);

      await _pressLaneName(tester, 'position', 'Position');

      // It MOVED — it did not multiply. The layer is still what you draw
      // on; it is no longer where you are standing.
      expect(find.byKey(laneMark), findsOneWidget);
      expect(find.byKey(cellRing), findsNothing);

      // And back: pressing the layer's own row takes it home.
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-layer-row-$_cameraId')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(cellRing), findsOneWidget);
      expect(find.byKey(laneMark), findsNothing);
    });

    testWidgets('a group header stands without twirling; the chevron is what '
        'twirls', (tester) async {
      await _pump(tester);
      await _openLanes(tester);
      final session = _sessionOf(tester);
      expect(
        _laneLabel('position'),
        findsOneWidget,
        reason: 'the group opened, so its members are on screen',
      );

      // The NAME stands on the header and leaves the group open — a header
      // is a row you pick (and, next round, grab), not a switch.
      await _pressLaneName(tester, 'transform-group', 'Transform');

      expect(
        session.currentRow,
        const LaneRowAddress(_cameraLayerId, 'transform-group'),
      );
      expect(_laneLabel('position'), findsOneWidget);

      // The chevron still owns the twirl.
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-group-toggle-$_cameraId-transform-group',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_laneLabel('position'), findsNothing);
    });

    testWidgets('the X-sheet answers the same press the same way', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-orientation-toggle-button'),
        ),
      );
      await tester.pumpAndSettle();
      await _openLanes(tester, keyPrefix: 'xsheet');
      final session = _sessionOf(tester);

      await _pressLaneName(tester, 'position', 'Position', keyPrefix: 'xsheet');

      expect(
        session.currentRow,
        const LaneRowAddress(_cameraLayerId, 'position'),
      );
      expect(
        _plateOf(tester, _laneLabel('position', keyPrefix: 'xsheet')),
        railSelectedRowColor(
          Theme.of(tester.element(find.byType(EditorWorkspace))).colorScheme,
        ),
      );
    });
  });

  group('the current row publishes itself', () {
    test('it fires when the answer moves and stays quiet when it does not', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final layerId = session.layers.first.id;

      var notifications = 0;
      session.currentRowListenable.addListener(() => notifications += 1);

      session.selectLayer(layerId);
      final afterLayer = notifications;
      expect(
        session.currentRowListenable.value,
        LayerRowAddress(layerId),
        reason: 'the row you draw on is the row you stand on by default',
      );

      // Standing on a property inside it MOVES the answer.
      session.selectRow(LaneRowAddress(layerId, 'position'));
      expect(
        session.currentRowListenable.value,
        LaneRowAddress(layerId, 'position'),
      );
      expect(notifications, greaterThan(afterLayer));

      // Pressing the same lane again is free — the claim on pointer-down
      // fires inside gestures whose contract is silence until release, so
      // "no change" must cost nothing.
      final settled = notifications;
      session.selectRow(LaneRowAddress(layerId, 'position'));
      session.claimTimelineRow();
      expect(notifications, settled);

      // Leaving the lane for its own layer row moves it back, even though
      // the active layer never changed (the notify-free path).
      session.selectLayer(layerId);
      expect(session.currentRowListenable.value, LayerRowAddress(layerId));
      expect(notifications, greaterThan(settled));
    });
  });
}
