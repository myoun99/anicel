import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/canvas_point_gizmo.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

const _gizmoKey = ValueKey<String>('layer-position-gizmo');
const _anchorKey = ValueKey<String>('layer-anchor-gizmo');

/// The two glyphs are one drawing with two sets of radii, so the radii are
/// what a test has to hold — a test on the painter's fields would pass
/// while the drawing moved (the C9 characterisation's rule).
class _CanvasSpy implements Canvas {
  final circles = <({Offset center, double radius})>[];
  final lines = <({Offset from, Offset to})>[];

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((center: c, radius: radius));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((from: p1, to: p2));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

_CanvasSpy _spyOnGlyph(WidgetTester tester, Key handleKey) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(of: find.byKey(handleKey), matching: find.byType(CustomPaint))
        .first,
  );
  final spy = _CanvasSpy();
  paint.painter!.paint(spy, tester.getSize(find.byKey(handleKey)));
  return spy;
}

/// Stands on the Transform GROUP header — the row that declares every
/// manipulator its members do (R5 #10).
///
/// The NAME, not the cell: the chevron twirls and the value cell edits, so
/// the label's text is the part of the row that only ever means "stand
/// here".
Future<void> _standOnTransformHeader(WidgetTester tester) async {
  final label = find.byKey(
    const ValueKey<String>(
      'timeline-lane-label-gizmo-draw-transform-group',
    ),
  );
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: label, matching: find.text('Transform')),
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('transformTrackWithPositionDragged', () {
    test('keys the dragged position at the playhead, preserving an '
        'existing key\'s interpolation', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 1, y: 1),
          interpolation: PropertyKeyInterpolation.hold,
        ),
      );

      final dragged = transformTrackWithPositionDragged(
        track,
        frameIndex: 0,
        position: CanvasPoint(x: 9, y: 3),
      );
      expect(dragged.position.keyAt(0)!.value, CanvasPoint(x: 9, y: 3));
      expect(
        dragged.position.keyAt(0)!.interpolation,
        PropertyKeyInterpolation.hold,
      );

      final keyedFresh = transformTrackWithPositionDragged(
        TransformTrack.empty(),
        frameIndex: 4,
        position: CanvasPoint(x: 2, y: 2),
      );
      expect(keyedFresh.position.keyAt(4)!.value, CanvasPoint(x: 2, y: 2));
      expect(
        keyedFresh.position.keyAt(4)!.interpolation,
        PropertyKeyInterpolation.linear,
      );
    });
  });

  group('CanvasPointGizmo', () {
    testWidgets('dragging the handle commits ONE position in canvas '
        'coordinates (screen delta ÷ viewport zoom)', (tester) async {
      final committed = <CanvasPoint>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasPointGizmo(
              glyph: HandleGlyph.crosshair,
              point: CanvasPoint(x: 100, y: 80),
              viewport: CanvasViewport(zoom: 2),
              onCommitted: committed.add,
            ),
          ),
        ),
      );

      await tester.drag(find.byKey(_gizmoKey), const Offset(48, -20));
      await tester.pumpAndSettle();

      expect(committed, hasLength(1));
      expect(committed.single.x, closeTo(100 + 48 / 2, 0.001));
      expect(committed.single.y, closeTo(80 - 20 / 2, 0.001));
    });

    testWidgets('a drag that lands back where it started commits NOTHING — '
        'one undo entry per real move, none for a handle that did not move', (
      tester,
    ) async {
      final committed = <CanvasPoint>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasPointGizmo(
              glyph: HandleGlyph.crosshair,
              point: CanvasPoint(x: 100, y: 80),
              viewport: CanvasViewport(),
              onCommitted: committed.add,
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_gizmoKey)),
      );
      await gesture.moveBy(const Offset(24, 16));
      await tester.pump();
      await gesture.moveBy(const Offset(-24, -16));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(committed, isEmpty);
    });

    testWidgets('the crosshair glyph: one circle and four ticks OUTSIDE it '
        '(AE-style move handle)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasPointGizmo(
              glyph: HandleGlyph.crosshair,
              point: CanvasPoint(x: 100, y: 80),
              viewport: CanvasViewport(),
              onCommitted: (_) {},
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byKey(_gizmoKey)), const Size(22, 22));
      final spy = _spyOnGlyph(tester, _gizmoKey);
      expect(spy.circles, hasLength(1));
      expect(spy.circles.single.center, const Offset(11, 11));
      expect(spy.circles.single.radius, 9);
      expect(spy.lines, hasLength(4));
      expect(
        spy.lines.map((l) => (l.from, l.to)).toSet(),
        {
          (const Offset(16, 11), const Offset(21, 11)),
          (const Offset(6, 11), const Offset(1, 11)),
          (const Offset(11, 16), const Offset(11, 21)),
          (const Offset(11, 6), const Offset(11, 1)),
        },
      );
    });

    testWidgets('the anchor glyph: a smaller circle with the four ticks '
        'reaching THROUGH it — a pivot, not a move handle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasPointGizmo(
              glyph: HandleGlyph.anchor,
              point: CanvasPoint(x: 60, y: 40),
              viewport: CanvasViewport(),
              onCommitted: (_) {},
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byKey(_anchorKey)), const Size(24, 24));
      final spy = _spyOnGlyph(tester, _anchorKey);
      expect(spy.circles, hasLength(1));
      expect(spy.circles.single.center, const Offset(12, 12));
      expect(spy.circles.single.radius, 6);
      expect(spy.lines, hasLength(4));
      expect(
        spy.lines.map((l) => (l.from, l.to)).toSet(),
        {
          (const Offset(18, 12), const Offset(23, 12)),
          (const Offset(6, 12), const Offset(1, 12)),
          (const Offset(12, 18), const Offset(12, 23)),
          (const Offset(12, 6), const Offset(12, 1)),
        },
      );
    });

    // TS9's law reaches the layer chrome too (유저: 드로잉모드가 아닌이상은
    // 툴이 작동하면 안되지). This one is a GestureDetector rather than a
    // Listener, so it declines by staying OUT OF THE ARENA — an early return
    // in `onPanStart` would come after the recognizer had already won, and
    // then neither the gizmo nor the flip would happen.
    testWidgets('a finger moves nothing while the one-finger slot flips', (
      tester,
    ) async {
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
      addTearDown(() {
        AppInput.settings.value = AppInputSettings.testCorpusBaseline;
      });
      final committed = <CanvasPoint>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasPointGizmo(
              glyph: HandleGlyph.crosshair,
              point: CanvasPoint(x: 100, y: 80),
              viewport: CanvasViewport(),
              onCommitted: committed.add,
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(_gizmoKey),
        const Offset(48, -20),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(committed, isEmpty);

      await tester.drag(
        find.byKey(_gizmoKey),
        const Offset(48, -20),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pumpAndSettle();
      expect(committed, hasLength(1), reason: 'the pen is never in doubt');
    });

    testWidgets('R5 #10: the ANCHOR gizmo keys anchor-point alone — the '
        'member you touch is the member that keys', (tester) async {
      final committed = <CanvasPoint>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasPointGizmo(
              glyph: HandleGlyph.anchor,
              point: CanvasPoint(x: 60, y: 40),
              viewport: CanvasViewport(zoom: 2),
              onCommitted: committed.add,
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(_anchorKey),
        const Offset(30, 10),
      );
      await tester.pumpAndSettle();

      expect(committed, hasLength(1));
      expect(committed.single.x, closeTo(60 + 30 / 2, 0.001));
      expect(committed.single.y, closeTo(40 + 10 / 2, 0.001));

      // Position is NOT compensated: the track helper touches one lane.
      final dragged = transformTrackWithAnchorDragged(
        TransformTrack.empty(),
        frameIndex: 3,
        anchorPoint: committed.single,
      );
      expect(dragged.anchorPoint.keyAt(3)!.value, committed.single);
      expect(
        dragged.position.isEmpty,
        isTrue,
        reason: 'compensating would key Position, which the user\'s rule for '
            '#10 forbids',
      );
    });

    testWidgets('R5 #10: shows only while a lane that DECLARES it is the '
        'standing row — twirling alone is not intent', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialProject: Project(
              id: const ProjectId('gizmo-project'),
              name: 'Gizmo Project',
              createdAt: DateTime.utc(2026, 7, 10),
              tracks: [
                Track(
                  id: const TrackId('gizmo-track'),
                  name: 'Video Track',
                  cuts: [
                    Cut(
                      id: const CutId('gizmo-cut'),
                      name: 'Gizmo Cut',
                      duration: 12,
                      canvasSize: const CanvasSize(width: 1280, height: 720),
                      layers: [
                        Layer(
                          id: const LayerId('gizmo-draw'),
                          name: 'Drawing',
                          frames: const [],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_gizmoKey), findsNothing);

      // Opening the lanes shows the Transform header. It does NOT put a
      // handle on the artwork: reading a row's properties is not asking to
      // pose it, which is the whole of R5 #10.
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-lane-toggle-gizmo-draw')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_gizmoKey), findsNothing);

      // Standing on the Transform group declares everything its members do
      // — the box AND the anchor, together, which is the one row where both
      // are on screen at once.
      await _standOnTransformHeader(tester);
      expect(find.byKey(_gizmoKey), findsOneWidget);
      expect(
        find.byKey(_anchorKey),
        findsOneWidget,
      );

      // Stepping back onto the LAYER row takes it away — the layer is what
      // you draw on, and nothing there declares a manipulator.
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-layer-name-gizmo-draw')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_gizmoKey), findsNothing);
      expect(
        find.byKey(_anchorKey),
        findsNothing,
      );
    });

    testWidgets('the TRANSFORM group\'s own bypass hides it — the row MASTER '
        'cannot answer this, since a row with one effect off is `mixed` '
        '(R8)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialProject: Project(
              id: const ProjectId('gizmo-fx-project'),
              name: 'Gizmo FX Project',
              createdAt: DateTime.utc(2026, 7, 30),
              tracks: [
                Track(
                  id: const TrackId('gizmo-track'),
                  name: 'Video Track',
                  cuts: [
                    Cut(
                      id: const CutId('gizmo-cut'),
                      name: 'Gizmo Cut',
                      duration: 12,
                      canvasSize: const CanvasSize(width: 1280, height: 720),
                      layers: [
                        Layer(
                          id: const LayerId('gizmo-draw'),
                          name: 'Drawing',
                          frames: const [],
                          // An effect that stays ON: with the transform
                          // bypassed the row reads `mixed`, which is the
                          // ONE state that tells the two gates apart.
                          effects: [
                            LayerEffect(
                              id: const EffectId('gizmo-fx'),
                              kind: EffectKind.brightnessContrast,
                              parameters: {
                                'brightness': EffectParameter(value: 20),
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Twirl the row's lanes open and stand on the Transform group.
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-lane-toggle-gizmo-draw')),
      );
      await tester.pumpAndSettle();
      await _standOnTransformHeader(tester);
      expect(find.byKey(_gizmoKey), findsOneWidget);

      final headerSwitch = find.byKey(
        const ValueKey<String>(
          'timeline-lane-group-fx-gizmo-draw-transform-group',
        ),
      );
      await tester.ensureVisible(headerSwitch);
      await tester.pumpAndSettle();

      await tester.tap(headerSwitch);
      await tester.pumpAndSettle();
      expect(
        find.byKey(_gizmoKey),
        findsNothing,
        reason: 'the pose it would drag is bypassed',
      );

      await tester.tap(headerSwitch);
      await tester.pumpAndSettle();
      expect(find.byKey(_gizmoKey), findsOneWidget);
    });
  });
}
