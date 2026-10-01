import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

import '../storyboard_cut_block_probe.dart';

/// 🗣️유저 2026-09-26 (zoom-floor-fixed-marks-Q1, 「다음 컷 앞에서 멈춘다 …
/// 안겹치고 … 프리미어처럼만 잘 되면됨」): a cut's block never reaches past
/// where the next cut starts. At I-22's ten-minute floor the 8px floor was
/// 64 frames, and every shorter cut lay over the next — drawn under it and
/// pressed as itself.
///
/// 🗣️유저 2026-09-27: 「타임라인줌 최대한 줄이면 컷블록이 엔드라인 넘거나
/// 해서 원래 있어야할 크기보다 블럭이 커지는데 최대한 원래 공간만
/// 차지하도록」. The 8px floor still grew a short cut before a gap into the
/// gap and the film's last cut past its end line. A block is its frames; the
/// floor is one pixel, which only keeps a cut too short to cover one from
/// vanishing — and even that pixel stops at the next cut.
void main() {
  Cut cut(String id, int duration, {int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: const [],
  );

  /// The blocks of [cuts] at [ppf] pixels a frame, in track order.
  Future<List<Rect>> blocksAt(
    WidgetTester tester,
    double ppf,
    List<Cut> cuts,
  ) async {
    await tester.binding.setSurfaceSize(const Size(2600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: Project(
              id: const ProjectId('p'),
              name: 'P',
              createdAt: DateTime.utc(2026, 9, 26),
              tracks: [Track(id: const TrackId('t'), name: 'V', cuts: cuts)],
            ),
            activeCutId: cuts.first.id,
            pixelsPerFrame: ppf,
            thumbnails: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return [for (final c in cuts) requireCutBlock(tester, c.id.value).rect];
  }

  /// C1 (10 frames), a 30-frame gap, C2 (10), C3 (10) glued on, C4 (20)
  /// last.
  List<Cut> film() => [
    cut('C1', 10),
    cut('C2', 10, gap: 30),
    cut('C3', 10),
    cut('C4', 20),
  ];

  testWidgets('at the ten-minute floor a block is its frames — not into the '
      'gap after it, not past the film\'s end', (tester) async {
    const ppf = 1 / 8;
    final blocks = await blocksAt(tester, ppf, film());
    for (var i = 0; i + 1 < blocks.length; i += 1) {
      expect(
        blocks[i].right,
        lessThanOrEqualTo(blocks[i + 1].left + 1e-9),
        reason: 'C${i + 1} stops before C${i + 2}',
      );
    }
    expect(blocks.map((block) => block.width), [
      closeTo(10 * ppf, 1e-9),
      closeTo(10 * ppf, 1e-9),
      closeTo(10 * ppf, 1e-9),
      closeTo(20 * ppf, 1e-9),
    ], reason: '🚨유저: 「원래 있어야할 크기보다 블럭이 커지는데」 — C1 grew into '
        'the gap after it, C4 past the end');
  });

  testWidgets('a cut too short to cover a pixel is drawn as one pixel, and '
      'still stops at the next cut', (tester) async {
    // At 1/8px a frame, 4 frames are half a pixel.
    const ppf = 1 / 8;
    final blocks = await blocksAt(tester, ppf, [
      cut('C1', 4),
      cut('C2', 4, gap: 20),
      cut('C3', 10),
      cut('C4', 4),
    ]);
    expect(
      blocks[0].width,
      closeTo(StoryboardPanel.cutBlockMinWidth, 1e-9),
      reason: 'C1 has room before C2, so it takes the one pixel',
    );
    expect(
      blocks[1].width,
      closeTo(4 * ppf, 1e-9),
      reason: 'C2 has C3 glued on: its own half pixel is all the room',
    );
    expect(
      blocks[3].width,
      closeTo(StoryboardPanel.cutBlockMinWidth, 1e-9),
      reason: 'the last cut takes the one pixel, and no more',
    );
  });

  testWidgets('at 100% nothing moved: each block is its frames', (
    tester,
  ) async {
    const ppf = 24.0;
    expect((await blocksAt(tester, ppf, film())).map((block) => block.width), [
      10 * ppf,
      10 * ppf,
      10 * ppf,
      20 * ppf,
    ]);
  });
}
