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
/// 안겹치고 … 프리미어처럼만 잘 되면됨」): a cut's block is at least 8px so a
/// short cut can be seen, but never past where the next cut starts. At
/// I-22's ten-minute floor the 8px floor was 64 frames, and every shorter
/// cut lay over the next — drawn under it and pressed as itself.
void main() {
  Cut cut(String id, int duration, {int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: const [],
  );

  /// C1 (10 frames), a 30-frame gap, C2 (10), C3 (10) glued on, C4 (20)
  /// last — at [ppf] pixels a frame.
  Future<List<Rect>> blocksAt(WidgetTester tester, double ppf) async {
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
              tracks: [
                Track(
                  id: const TrackId('t'),
                  name: 'V',
                  cuts: [
                    cut('C1', 10),
                    cut('C2', 10, gap: 30),
                    cut('C3', 10),
                    cut('C4', 20),
                  ],
                ),
              ],
            ),
            activeCutId: const CutId('C1'),
            pixelsPerFrame: ppf,
            thumbnails: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return [
      for (final id in ['C1', 'C2', 'C3', 'C4'])
        requireCutBlock(tester, id).rect,
    ];
  }

  testWidgets('at the ten-minute floor a short cut reaches the next cut and '
      'stops there — no two blocks overlap', (tester) async {
    const ppf = 1 / 8;
    final blocks = await blocksAt(tester, ppf);
    for (var i = 0; i + 1 < blocks.length; i += 1) {
      expect(
        blocks[i].right,
        lessThanOrEqualTo(blocks[i + 1].left + 1e-9),
        reason: 'C${i + 1} stops before C${i + 2}',
      );
    }
    // C1 has its own 10 frames and the 30-frame gap before C2: 40 frames,
    // five pixels — short of the 8px floor, so it stops at C2.
    expect(blocks[0].width, closeTo(40 * ppf, 1e-9));
    // C2 and C3 are glued on: their own frames are all the room there is.
    expect(blocks[1].width, closeTo(10 * ppf, 1e-9));
    expect(blocks[2].width, closeTo(10 * ppf, 1e-9));
    // The last cut has no one to stop for: its 2.5px take the floor.
    expect(blocks[3].width, closeTo(StoryboardPanel.cutBlockMinWidth, 1e-9));
  });

  testWidgets('at 100% nothing moved: each block is its frames', (
    tester,
  ) async {
    const ppf = 24.0;
    expect((await blocksAt(tester, ppf)).map((block) => block.width), [
      10 * ppf,
      10 * ppf,
      10 * ppf,
      20 * ppf,
    ]);
  });
}
