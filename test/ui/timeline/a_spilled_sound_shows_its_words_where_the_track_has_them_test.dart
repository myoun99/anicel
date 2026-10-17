import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderClipRect;
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
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart'
    show SeSpanVisual;

import '../../helpers/painted_glyph_boxes.dart';

/// F-358 — 유저 2026-10-14: 「여러 컷에 걸친 se블록이 있을때, 글로벌에선
/// e라는 글자가 보이는 구간인데 로컬에선 T라는게 보인다던가 하는식으로 위치가
/// 서로 어긋남. 위치는 같도록. 글로벌기준으로」.
///
/// The cut a sound spilled into laid that block out AGAIN over the frames it
/// had left: its name chip at the cut's frame 0, its whole line spread over
/// the rest. A cut is a window on the track's block — the same span, laid
/// out from where it starts, seen from the cut's frame 0 on.
void main() {
  const line = 'ABCDEFGH';

  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
    ],
  );

  /// One sound [4, 12) across the cut-1 → cut-2 boundary at 8, and one
  /// inside cut 2 right after it: cut 2 sees the first from 4 frames in.
  Project film() => Project(
    id: const ProjectId('spilled-words'),
    name: 'Spilled words',
    createdAt: DateTime.utc(2026, 10, 18),
    tracks: [
      Track(
        id: const TrackId('spill-track'),
        name: 'Video',
        cuts: [cut('cut-1', 8), cut('cut-2', 6)],
        seLayers: [
          Layer(
            id: const LayerId('se-row-1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(
                id: const FrameId('f-cross'),
                duration: 8,
                name: line,
                seName: 'X',
                strokes: const [],
              ),
              Frame(
                id: const FrameId('f-after'),
                duration: 2,
                name: 'Yo',
                strokes: const [],
              ),
            ],
            timeline: {
              4: const TimelineExposure.drawing(FrameId('f-cross'), length: 8),
              12: const TimelineExposure.drawing(FrameId('f-after'), length: 2),
            },
          ),
        ],
      ),
    ],
  );

  Future<void> pumpFilm(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: film()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  SeSpanVisual spanOf(WidgetTester tester, Finder host) =>
      tester.widget<SeSpanVisual>(
        find.descendant(of: host, matching: find.byType(SeSpanVisual)),
      );

  testWidgets('🚨the cut a sound spilled into lays out the TRACK\'s '
      'block — the span the storyboard draws, from where it starts', (
    tester,
  ) async {
    await pumpFilm(tester);
    await tapKey(tester, 'timeline-mode-storyboard-button');
    final track = spanOf(
      tester,
      find.byKey(const ValueKey<String>('storyboard-se-span-se-row-1-4')),
    );
    expect(
      [track.frames, track.dialogue, track.seName, track.shownFrom],
      [8, line, 'X', 0],
      reason: '⛔전제: the storyboard draws the whole block',
    );

    tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .selectCut(const CutId('cut-2'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'timeline-mode-timeline-button');

    final spilled = find.byKey(
      const ValueKey<String>('timeline-se-label-se-row-1-0'),
    );
    final inCut = spanOf(tester, spilled);
    expect(
      [inCut.frames, inCut.dialogue, inCut.seName],
      [track.frames, track.dialogue, track.seName],
      reason: 'the block the track has, not the four frames the cut holds',
    );
    expect(inCut.shownFrom, 4, reason: 'seen from the cut\'s frame 0 on');

    // Laid from where it really starts: it ends where the next sound
    // begins, eight cells long.
    final after = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-se-label-se-row-1-4')),
    );
    final cell = after.width / 2;
    final rect = tester.getRect(spilled);
    expect(rect.right, moreOrLessEquals(after.left, epsilon: 0.5));
    expect(rect.width, moreOrLessEquals(8 * cell, epsilon: 0.5));
  });

  testWidgets('🚨and the canvas\'s folded row sees it through the same '
      'window', (tester) async {
    await pumpFilm(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectCut(const CutId('cut-2'));
    session.selectLayer(const LayerId('se-row-1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'floating-bottom-collapse');

    final folded = spanOf(
      tester,
      find.descendant(
        of: find.byType(CollapsedRowOverlay),
        matching: find.byKey(
          const ValueKey<String>('timeline-se-label-se-row-1-0'),
        ),
      ),
    );
    expect([folded.frames, folded.shownFrom], [8, 4]);
  });

  /// The boxes the dialogue under [span] paints its glyphs in, and the part
  /// of the span its window shows — both where they stand on screen.
  ({List<Rect> glyphs, Rect shown}) seen(WidgetTester tester, Finder span) {
    final glyphs = find.descendant(
      of: find.descendant(of: span, matching: find.byType(DialogueFitText)),
      matching: find.byType(CustomPaint),
    );
    final canvas = PaintedGlyphBoxes();
    tester
        .widget<CustomPaint>(glyphs)
        .painter!
        .paint(canvas, tester.getSize(glyphs));
    final clip = find.descendant(of: span, matching: find.byType(ClipRect));
    final shown = tester.renderObject<RenderClipRect>(clip);
    return (
      glyphs: [
        for (final box in canvas.boxes) box.shift(tester.getTopLeft(glyphs)),
      ],
      shown: shown.clipper!
          .getClip(shown.size)
          .shift(tester.getTopLeft(clip)),
    );
  }

  for (final axis in Axis.values) {
    testWidgets('🚨a window shows the glyphs whose centre it holds, WHOLE, '
        'and not the name chip at the block\'s head — ${axis.name}', (
      tester,
    ) async {
      // Eight frames of 24, seen from frame 4 on: the window opens at 96.
      const cellExtent = 24.0;
      const across = 30.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: axis == Axis.horizontal ? 8 * cellExtent : across,
                height: axis == Axis.horizontal ? across : 8 * cellExtent,
                child: SeSpanVisual(
                  axis: axis,
                  frames: 8,
                  dialogue: line,
                  seName: 'X',
                  shownFrom: 4,
                ),
              ),
            ),
          ),
        ),
      );
      double along(Offset point) =>
          axis == Axis.horizontal ? point.dx : point.dy;
      ({double start, double end}) extent(Rect box) =>
          axis == Axis.horizontal
          ? (start: box.left, end: box.right)
          : (start: box.top, end: box.bottom);

      final (:glyphs, :shown) = seen(tester, find.byType(SeSpanVisual));
      const window = 4 * cellExtent;
      final opens = extent(shown).start;
      expect(glyphs, hasLength(line.length));
      for (final (index, box) in glyphs.indexed) {
        final inWindow = along(box.center) >= window;
        expect(
          inWindow
              ? extent(box).start >= opens - 1e-6
              : extent(box).end <= opens + 1e-6,
          isTrue,
          reason:
              'glyph $index (centre ${along(box.center)}) is '
              '${inWindow ? 'shown' : 'hidden'} whole — the window opens at '
              '$opens',
        );
      }
      expect(
        [for (final box in glyphs) along(box.center) >= window],
        containsAllInOrder([false, true]),
        reason: '⛔전제: the window cuts the line',
      );
      expect(
        extent(tester.getRect(find.bySemanticsLabel('SE name X'))).end,
        lessThanOrEqualTo(opens + 1e-6),
        reason: 'the chip stands at the head, in the earlier cut',
      );
    });
  }
}
