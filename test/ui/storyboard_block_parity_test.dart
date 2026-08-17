import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/dialogs/instruction_event_dialog.dart'
    show InstructionEventDialog;
import 'package:anicel/src/ui/dialogs/se_instance_dialog.dart'
    show SeInstanceDialog;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_double_tap.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart'
    show BlockEdgeGripBarPainter, BlockEdgeGripInk, blockEdgeGripHitExtent;

/// B5/B6 (2026-08-17): the storyboard's TRANSITION and SE blocks behave
/// like FRAME BLOCKS — the same double-tap gate (same cell twice, or it is
/// two seeks), the same edge zones (the dense rows' grip-width law), and
/// the same arbitration (edges above the range gesture). Every gesture in
/// here is REAL input ([[parity-tests-must-drive-real-input]]): taps at
/// pixel positions, mouse hovers, mouse drags — never a callback call.
const _trackId = TrackId('parity-track');
const _seLayerId = LayerId('parity-se-row');

/// The storyboard's resting zoom — 8px a frame, the value the panel really
/// draws at ([_storyboardPixelsPerFrame]'s default), which is exactly the
/// zoom where the old cell-only grip width collapsed to ~2.7px.
const double _ppf = 8;

Cut _cut(String id, int duration) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    Layer(
      id: LayerId('$id-cel'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
  ],
);

/// One track: a transition span over global frames 2..6 (a 1..5-shaped
/// block, the user's own repro) and one SE block over global frames 1..5.
Project _project() => Project(
  id: const ProjectId('parity-project'),
  name: 'Block Parity',
  createdAt: DateTime.utc(2026, 8, 17),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 10), _cut('cut-2', 6)],
      transitionLayer: createTrackTransitionLayer(_trackId).copyWith(
        instructions: {
          2: const InstructionEvent(instructionId: 'ol', length: 5),
        },
      ),
      seLayers: [
        Layer(
          id: _seLayerId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('parity-sound'),
              duration: 5,
              name: 'Bang!',
              strokes: const [],
            ),
          ],
          timeline: {
            1: const TimelineExposure.drawing(
              FrameId('parity-sound'),
              length: 5,
            ),
          },
        ),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
}

StoryboardPanel _panel(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));

Track _track(WidgetTester tester) => _panel(tester).project.tracks.single;

/// A point over [globalFrame]'s CENTER on the row widget found by [rowKey].
Offset _rowPoint(WidgetTester tester, String rowKey, double dx) {
  final row = find.byKey(ValueKey<String>(rowKey));
  final topLeft = tester.getTopLeft(row);
  return Offset(topLeft.dx + dx, topLeft.dy + tester.getSize(row).height / 2);
}

String get _transitionRowKey => 'storyboard-transition-row-${_trackId.value}';

const String _seRowKey = 'storyboard-se-row-0-1';

/// Two REAL taps [firstDx] then [secondDx] from the row's left edge,
/// inside the double-tap window — the gesture the recognizer fuses into
/// one double tap whatever cells they hit (its ~100px slop).
Future<void> _doubleTapAt(
  WidgetTester tester,
  String rowKey, {
  required double firstDx,
  required double secondDx,
}) async {
  await tester.tapAt(_rowPoint(tester, rowKey, firstDx));
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(_rowPoint(tester, rowKey, secondDx));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

void main() {
  setUp(TimelineCellDoubleTapGate.reset);

  group('B5① the transition blocks take the frame blocks\' double-tap law', () {
    testWidgets('two taps on DIFFERENT cells of one span never open the '
        'editor — they are two seeks', (tester) async {
      await _openStoryboard(tester);

      // Frames 3 and 5 of the 2..6 span — both covered, 16px apart, well
      // inside the recognizer's slop. The old span-covering gate opened
      // the term dialog here.
      await _doubleTapAt(
        tester,
        _transitionRowKey,
        firstDx: 3.5 * _ppf,
        secondDx: 5.5 * _ppf,
      );

      expect(find.byType(InstructionEventDialog), findsNothing);
      // The taps still seeked — the second tap's frame is where we parked.
      expect(_panel(tester).playheadFrame?.value, 5);
    });

    testWidgets('two taps on the SAME cell open the span editor', (
      tester,
    ) async {
      await _openStoryboard(tester);

      await _doubleTapAt(
        tester,
        _transitionRowKey,
        firstDx: 4.5 * _ppf,
        secondDx: 4.5 * _ppf,
      );

      expect(find.byType(InstructionEventDialog), findsOneWidget);
    });

    testWidgets('two taps on the same EMPTY cell stay quiet — creation is '
        'the Edit Instance verb\'s, not a brush-past\'s', (tester) async {
      await _openStoryboard(tester);

      await _doubleTapAt(
        tester,
        _transitionRowKey,
        firstDx: 8.5 * _ppf,
        secondDx: 8.5 * _ppf,
      );

      expect(find.byType(InstructionEventDialog), findsNothing);
      expect(_track(tester).transitionLayer.instructions.keys, [2]);
    });
  });

  group('B5② the transition edges are the frame blocks\' edges', () {
    testWidgets('a REAL mouse drag on the span\'s end grip adjusts its '
        'comma — and the range selection does not swallow it', (tester) async {
      await _openStoryboard(tester);
      expect(_track(tester).transitionLayer.instructions[2]!.length, 5);

      // The end grip: 6px inward of the span's trailing edge (frame 7's
      // leading edge, 56px) — the dense rows' floored width at 8px cells.
      final grip = _rowPoint(tester, _transitionRowKey, 7 * _ppf - 3);
      final gesture = await tester.startGesture(
        grip,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(9, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        _track(tester).transitionLayer.instructions[2]!.length,
        7,
        reason: 'a 17px pull at 8px a frame is two frames of comma',
      );
      expect(
        _panel(tester).seSelect?.selectedRange.value,
        isNull,
        reason: 'the edge drag must never read as a range select',
      );
    });

    testWidgets('a REAL mouse drag on the span\'s BODY still range-selects '
        '— the edges took their zones, not the row', (tester) async {
      await _openStoryboard(tester);

      final start = _rowPoint(tester, _transitionRowKey, 3.5 * _ppf);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final selection = _panel(tester).seSelect?.selectedRange.value;
      expect(selection, isNotNull, reason: 'drag-select must keep working');
      // The dragged frames are covered; the ends may snap outward to the
      // whole block — the frame blocks' own selection law.
      expect(selection!.startFrame, lessThanOrEqualTo(3));
      expect(selection.endFrameExclusive, greaterThan(4));
      expect(
        _track(tester).transitionLayer.instructions[2]!.length,
        5,
        reason: 'a body drag selects; it never edits the comma',
      );
    });
  });

  group('B6 the SE blocks: edges at the true edges, double-tap opens', () {
    testWidgets('the grips sit AT the block edges with the dense rows\' '
        'width — not as slivers the visible bar overhangs', (tester) async {
      await _openStoryboard(tester);

      final row = find.byKey(const ValueKey<String>(_seRowKey));
      final rowLeft = tester.getTopLeft(row).dx;

      final startGrip = find.byKey(
        ValueKey<String>('storyboard-se-grip-$_seLayerId-0-start'),
      );
      final endGrip = find.byKey(
        ValueKey<String>('storyboard-se-grip-$_seLayerId-0-end'),
      );
      // The dense rows' law: max(cell/3, min(6, block/3)) capped at 12 —
      // at 8px cells and a 5-frame block that is 6px, where the cell-only
      // form gave 2.67px and parked the visible bar outside its own hit
      // strip.
      final lawWidth = blockEdgeGripHitExtent(_ppf, blockExtent: 5 * _ppf);
      expect(lawWidth, 6);
      expect(tester.getSize(startGrip).width, lawWidth);
      expect(tester.getSize(endGrip).width, lawWidth);
      // Anchored ON the edges: the start grip's leading edge is the
      // block's (frame 1, 8px), the end grip's trailing edge is the
      // block's (frame 6's leading edge, 48px).
      expect(tester.getTopLeft(startGrip).dx - rowLeft, 1 * _ppf);
      expect(tester.getTopRight(endGrip).dx - rowLeft, 6 * _ppf);
    });

    testWidgets('a REAL mouse hover on the end edge engages the grip — and '
        'leaving it lets go', (tester) async {
      await _openStoryboard(tester);

      final endGrip = find.byKey(
        ValueKey<String>('storyboard-se-grip-$_seLayerId-0-end'),
      );
      BlockEdgeGripInk ink() {
        final paint = find.descendant(
          of: endGrip,
          matching: find.byType(CustomPaint),
        );
        return (tester.widget<CustomPaint>(paint.first).painter!
                as BlockEdgeGripBarPainter)
            .ink;
      }

      final hover = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 7,
      );
      addTearDown(hover.removePointer);
      await hover.addPointer(location: Offset.zero);
      await tester.pump();
      expect(ink(), BlockEdgeGripInk.rest);

      await hover.moveTo(tester.getCenter(endGrip));
      await tester.pump();
      expect(ink(), BlockEdgeGripInk.hovered);

      await hover.moveTo(Offset.zero);
      await tester.pump();
      expect(ink(), BlockEdgeGripInk.rest);
    });

    testWidgets('double-tapping the SAME cell of a sound block opens the SE '
        'instance dialog — the timeline cells\' entrance', (tester) async {
      await _openStoryboard(tester);

      await _doubleTapAt(
        tester,
        _seRowKey,
        firstDx: 3.5 * _ppf,
        secondDx: 3.5 * _ppf,
      );

      expect(find.byType(SeInstanceDialog), findsOneWidget);
      expect(find.text('Bang!'), findsWidgets);
    });

    testWidgets('two taps on DIFFERENT cells of the block do NOT open it', (
      tester,
    ) async {
      await _openStoryboard(tester);

      await _doubleTapAt(
        tester,
        _seRowKey,
        firstDx: 2.5 * _ppf,
        secondDx: 4.5 * _ppf,
      );

      expect(find.byType(SeInstanceDialog), findsNothing);
    });

    testWidgets('the dialog COMMITS through the row-addressed verb: editing '
        'the dialogue lands on the track fixture', (tester) async {
      await _openStoryboard(tester);

      await _doubleTapAt(
        tester,
        _seRowKey,
        firstDx: 3.5 * _ppf,
        secondDx: 3.5 * _ppf,
      );
      expect(find.byType(SeInstanceDialog), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('se-dialogue-field')),
        'Crash!',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
      );
      await tester.pumpAndSettle();

      expect(_track(tester).seLayers.single.frames.single.name, 'Crash!');
    });
  });

  group('B5③ the storyboard rail rows wear the timeline rows\' chrome', () {
    testWidgets('the S row carries the sheet toggle, and a REAL tap flips '
        'the layer\'s flag', (tester) async {
      await _openStoryboard(tester);

      final toggle = find.byKey(
        ValueKey<String>('storyboard-layer-timesheet-$_seLayerId'),
      );
      expect(toggle, findsOneWidget);
      expect(_track(tester).seLayers.single.onTimesheet, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(_track(tester).seLayers.single.onTimesheet, isFalse);
    });

    testWidgets('the transition row carries sheet, mark and eye — the three '
        'the timeline row already had', (tester) async {
      await _openStoryboard(tester);
      final transitionId = _track(tester).transitionLayer.id;

      expect(
        find.byKey(
          ValueKey<String>('storyboard-layer-timesheet-$transitionId'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('storyboard-layer-mark-$transitionId')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('storyboard-layer-visibility-$transitionId'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the transition eye is COMPOSITE inclusion: a REAL tap '
        'hides the layer and its fades stop contributing', (tester) async {
      await _openStoryboard(tester);
      final transitionId = _track(tester).transitionLayer.id;

      await tester.tap(
        find.byKey(
          ValueKey<String>('storyboard-layer-visibility-$transitionId'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_track(tester).transitionLayer.isVisible, isFalse);
      expect(
        _track(tester).transitionLayer.instructions,
        isNotEmpty,
        reason: 'the eye hides the contribution, never the data',
      );
    });
  });

  group('the row-addressed session verbs (the storyboard\'s door)', () {
    test('a hidden transition layer contributes NO spans to playback', () {
      final session = EditorSessionManager(initialProject: _project());
      addTearDown(session.dispose);

      expect(session.transitionSpansOfTrack(_trackId), hasLength(1));

      session.toggleLayerVisibility(session.activeTrack.transitionLayer.id);

      expect(session.transitionSpansOfTrack(_trackId), isEmpty);
    });

    test('the sheet toggle works from a GAP — the row is track-owned, so '
        'no active cut is required', () {
      final session = EditorSessionManager(initialProject: _project());
      addTearDown(session.dispose);

      // Park in the gap past both cuts: no active cut.
      seekStoryboardGlobalFrame(session, 20);
      expect(session.activeCutId, isNull);

      session.toggleLayerTimesheet(_seLayerId);

      expect(
        session.repository
            .requireProject()
            .tracks
            .single
            .seLayers
            .single
            .onTimesheet,
        isFalse,
      );
    });
  });
}
