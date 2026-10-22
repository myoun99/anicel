import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/storyboard_coverage.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';

/// A storyboard panel's picture is the cut at the panel's own division.
///
/// 🗣️F-379 (유저 2026-10-17): 「컷 버튼의 썸네일 프레임 고정 삭제. 기능 싹
/// 잔재 삭제」 — ↩️a cut could pin its thumbnail to a frame of its own, and
/// the panel covering that frame showed it instead.
ui.Size _original() => const ui.Size(1920, 1080);

void main() {
  test('a cut written with a thumbnail pin reads as one without — the key '
      'is left behind', () {
    final read = CutMetadata.fromJson({
      'pageNotes': ['memo'],
      'thumbnailFrame': 7,
    });

    expect(read, const CutMetadata(pageNotes: ['memo']));
    expect(read.toJson().containsKey('thumbnailFrame'), isFalse);
  });

  test('every panel shows its own division, in the cut\'s frames', () {
    const first = StoryboardCoverageCell(
      startIndex: 0,
      endIndexExclusive: 10,
      frameId: FrameId('a'),
    );
    const second = StoryboardCoverageCell(
      startIndex: 10,
      endIndexExclusive: 20,
      frameId: FrameId('b'),
    );

    expect(storyboardCellPictureFrame(first, conteStart: 0), 0);
    expect(storyboardCellPictureFrame(second, conteStart: 0), 10);
    // F-227: a cut an O.L arrives into counts the conte 6 frames in — the
    // picture is the CUT's frame.
    expect(storyboardCellPictureFrame(second, conteStart: 6), 16);
  });

  Future<ui.Image> tinyImage() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(2, 2);
    } finally {
      picture.dispose();
    }
  }

  final cut = Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: 24,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
        ],
      ),
    ],
  );

  testWidgets('the store renders once per (cut, FRAME) — the frame the '
      'panel asks for', (tester) async {
    var renderCount = 0;
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, _, _) {
        renderCount += 1;
        return tinyImage();
      },
    );
    addTearDown(store.dispose);

    await tester.runAsync(() async {
      store.thumbnailFor(cut, 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // A different frame is a different picture.
      store.thumbnailFor(cut, 12, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // The same one again is not.
      store.thumbnailFor(cut, 12, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(renderCount, 2);
  });
}
