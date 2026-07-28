import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/home_page.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';

/// The ruler's scrub follows the POINTER, not a transform captured when the
/// drag began (feedback #13: "드래그중 커서 밖으로 나갔다 들어오면 커서랑
/// 위치가 어긋남 … 타임라인패널이랑 통일해줘").
///
/// The trap is specific: a gesture's `localPosition` rides the transform
/// captured at pointer-DOWN, and the ruler strip is translated by the
/// scroll. The moment an edge auto-pan moves it, every later move reports a
/// frame that has drifted by however far the axis panned — which is exactly
/// what leaving the viewport and coming back does.
const _trackId = TrackId('scrub-track');

/// Long enough that the axis can actually scroll under the drag.
Project _project() => Project(
  id: const ProjectId('scrub-project'),
  name: 'Scrub',
  createdAt: DateTime.utc(2026, 7, 28),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        for (var i = 0; i < 8; i += 1)
          Cut(
            id: CutId('cut-$i'),
            name: 'cut-$i',
            duration: 48,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: LayerId('cut-$i-cel'),
                name: 'A',
                frames: const [],
                timeline: const {},
              ),
            ],
          ),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
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

Finder get _ruler => find.byKey(const ValueKey<String>('storyboard-ruler'));

double _pixelsPerFrame(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)).pixelsPerFrame;

/// The frame the panel's playhead currently sits on.
int? _playheadFrame(WidgetTester tester) {
  final finder = find.byKey(const ValueKey<String>('storyboard-playhead'));
  if (finder.evaluate().isEmpty) {
    return null;
  }
  final left = tester.widget<Positioned>(finder).left;
  if (left == null) {
    return null;
  }
  return (left / _pixelsPerFrame(tester)).round();
}

void main() {
  testWidgets('the frame under the pointer is the frame it seeks, even after '
      'the drag has pushed the axis past the viewport edge', (tester) async {
    await _openStoryboard(tester);

    final perFrame = _pixelsPerFrame(tester);
    final y = tester.getRect(_ruler).center.dy;
    // The strip is translated by the scroll, so its LEFT edge is the
    // content origin in global coordinates — read live, never cached.
    double stripLeft() => tester.getRect(_ruler).left;
    final initialLeft = stripLeft();
    // The PANEL's right edge — the ruler viewport ends there, and the edge
    // auto-pan only arms within 24px of it.
    final viewportRight =
        tester.getRect(find.byType(StoryboardPanel)).right - 6;

    // MOUSE: a touch drag here belongs to the panel's scroll view (the
    // edit-pan device policy), so the ruler would never claim the arena.
    final gesture = await tester.startGesture(
      Offset(initialLeft + 120, y),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    // Drag into the right edge so the auto-pan scrolls the axis under the
    // pointer — the state a captured transform goes stale in. Each step
    // must MOVE, or no pointer event is dispatched to pan on.
    for (var i = 0; i < 8; i += 1) {
      await gesture.moveTo(Offset(viewportRight - (i.isEven ? 0 : 1), y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      stripLeft(),
      lessThan(initialLeft),
      reason: 'the axis really did pan under the drag',
    );

    // Come back to a settled position well inside the viewport.
    final settled = Offset(viewportRight - 260, y);
    await gesture.moveTo(settled);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Whatever the axis did in between, the committed frame is the one the
    // POINTER is over — measured against where the content actually sits.
    final expected = ((settled.dx - stripLeft()) / perFrame).floor();
    expect(_playheadFrame(tester), expected);
  });

  testWidgets('a plain press with no panning still lands under the pointer', (
    tester,
  ) async {
    await _openStoryboard(tester);

    final rulerRect = tester.getRect(_ruler);
    final perFrame = _pixelsPerFrame(tester);
    final at = Offset(rulerRect.left + 8 * perFrame + 2, rulerRect.center.dy);

    await tester.tapAt(at);
    await tester.pumpAndSettle();

    expect(_playheadFrame(tester), 8);
  });
}
