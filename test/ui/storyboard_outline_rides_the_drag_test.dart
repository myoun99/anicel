import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

/// 🚨H12 (유저 2026-08-22) — **THE OUTLINE RIDES THE DRAG.**
///
/// > 「스토리보드패널, **이 패널만** 선택범위로 선택하고 드래그시, 선택범위의
/// > **ui 실루엣이 원래 블록 자리에 남음.** 드래그 끝나야 사라짐.
/// > **타임라인패널이랑 다르니까 통일**」
///
/// The band was never the culprit — it is drawn from the selection's own
/// frame numbers and `CutMoveDrag` republishes those every step. What stayed
/// behind was the STANDING BLOCK OUTLINE, which read its rect off the
/// COMMITTED project and subscribed to the standing row and the playhead
/// alone. The blocks moved; the accent rectangle held the vacated seat.
///
/// ⚠️Everything here is asserted MID-DRAG, before the pointer goes up —
/// which is the only place the bug lived. A test that releases first sees
/// the committed layout and passes either way.
const _trackId = TrackId('outline-track');

Cut _cut(String id) => Cut(
  id: CutId(id),
  name: id,
  duration: 10,
  canvasSize: const CanvasSize(width: 320, height: 180),
  layers: [
    Layer(id: LayerId('$id-cel'), name: 'A', frames: const [], timeline: {}),
    Layer(
      id: LayerId('$id-sb'),
      name: 'SB',
      kind: LayerKind.storyboard,
      frames: [
        Frame(id: FrameId('$id-0'), duration: 1, strokes: const []),
      ],
      timeline: {0: TimelineExposure.drawing(FrameId('$id-0'), length: 10)},
    ),
  ],
);

/// Three packed 10-frame cuts: [0,10) [10,20) [20,30).
Project _project() => Project(
  id: const ProjectId('outline-project'),
  name: 'Outline',
  createdAt: DateTime.utc(2026, 8, 22),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1'), _cut('cut-2'), _cut('cut-3')],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1500, 800));
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

double _pixelsPerFrame(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)).pixelsPerFrame;

Rect _cutRowRect(WidgetTester tester) {
  final row = find.byKey(
    ValueKey<String>('storyboard-track-timeline-area-${_trackId.value}'),
  );
  return tester.getTopLeft(row) & tester.getSize(row);
}

/// A point on the cut's own TOP band over [globalFrame] — the cut's handle.
Offset _bandPoint(WidgetTester tester, int globalFrame) {
  final rect = _cutRowRect(tester);
  return Offset(
    rect.left + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    rect.top + StoryboardCutBlocksPainter.bandHeight / 2,
  );
}

Rect? _outlineRect(WidgetTester tester) {
  final finder = find.byKey(
    const ValueKey<String>('storyboard-standing-block'),
  );
  return finder.evaluate().isEmpty ? null : tester.getRect(finder);
}

void main() {
  testWidgets('the standing outline follows a cut move while the hand still '
      'holds it', (tester) async {
    await _openStoryboard(tester);
    final ppf = _pixelsPerFrame(tester);

    // Stand on the cut row and take cut-1 as a run — the cut's own handle.
    final gesture = await tester.startGesture(
      _bandPoint(tester, 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(_bandPoint(tester, 7));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final before = _outlineRect(tester);
    expect(
      before,
      isNotNull,
      reason: 'the premise: standing on the cut row draws the outline',
    );

    // Now DRAG that run one whole cut to the right, and look before letting
    // go. Cut-1's seat past cut-2 is frame 10 — cut-2's length of travel.
    final move = await tester.startGesture(
      _bandPoint(tester, 5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await move.moveTo(_bandPoint(tester, 15));
    await tester.pump();

    // Read BEFORE letting go, assert AFTER — a gesture left in flight
    // outlives the widget tree and the drag's notifier is disposed under it.
    final during = _outlineRect(tester);
    await move.up();
    await tester.pumpAndSettle();

    expect(during, isNotNull, reason: 'the outline is still on screen');
    expect(
      during!.left - before!.left,
      moreOrLessEquals(10 * ppf, epsilon: ppf),
      reason: '「실루엣이 원래 블록 자리에 남음」 — it must not. WHICH cut you '
          'stand on is committed, WHERE it is is previewed; asking both of '
          'one film leaves the rectangle exactly where it was',
    );
  });

  testWidgets('and it holds still when the drag moves nothing', (tester) async {
    await _openStoryboard(tester);

    final gesture = await tester.startGesture(
      _bandPoint(tester, 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(_bandPoint(tester, 7));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final before = _outlineRect(tester);
    expect(before, isNotNull);

    // A press with no travel: the preview says nothing changed, so neither
    // does the outline. This is the half a preview-aware read could break.
    final move = await tester.startGesture(
      _bandPoint(tester, 5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await move.moveTo(_bandPoint(tester, 5));
    await tester.pump();

    final during = _outlineRect(tester);
    await move.up();
    await tester.pumpAndSettle();

    expect(during, before);
  });
}
