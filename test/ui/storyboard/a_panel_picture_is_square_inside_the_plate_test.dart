import 'dart:ui' as ui;

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
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailTier;
import 'package:anicel/src/ui/storyboard_panel.dart';

import '../storyboard_cut_block_probe.dart';

/// 🚨유저 2026-09-26: 「블록이 모서리 둥근건 블록 자체잖아. 근데 … 지금
/// 컷블록이나 콘티블록은 둥근 모서리의 안쪽에 있는것이잖아. 띠가 있으니까.
/// 그래서 모서리가 둥글 이유가 없을거같거든? 관련 로직 삭제. 만약 나중에
/// 띠부분까지 전면 썸네일로 표시한다면 자연스럽게 모서리 잘리도록
/// 낡지않는구조로」.
///
/// Read off the painter's own calls: the rounding a picture meets is the
/// PLATE'S clip and nothing else, so the day a picture reaches the bands it
/// is cut by the plate's corner with no change to the painter.
void main() {
  const ppf = 8.0;

  Cut cut(String id, int duration, {List<int>? panels}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      if (panels != null)
        Layer(
          id: LayerId('$id-sb'),
          name: 'SB',
          kind: LayerKind.storyboard,
          frames: [
            for (var i = 0; i < panels.length; i += 1)
              Frame(id: FrameId('$id-$i'), duration: 1, strokes: const []),
          ],
          timeline: {
            for (var i = 0, start = 0; i < panels.length; start += panels[i], i += 1)
              start: TimelineExposure.drawing(
                FrameId('$id-$i'),
                length: panels[i],
              ),
          },
        ),
    ],
  );

  testWidgets('the plate is the one rounded clip a picture meets — each '
      'picture is clipped SQUARE to its own panel, inside the plate', (
    tester,
  ) async {
    final picture = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 64, 36),
        Paint()..color = const Color(0xFFFF0000),
      );
      return recorder.endRecording().toImage(64, 36);
    }))!;
    await tester.binding.setSurfaceSize(const Size(1200, 400));
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
                    cut('C1', 20, panels: [6, 14]),
                    cut('C2', 12),
                  ],
                ),
              ],
            ),
            activeCutId: const CutId('C1'),
            pixelsPerFrame: ppf,
            thumbnailFor: (cut, frame, {tier = StoryboardThumbnailTier.strip}) =>
                picture,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = cutBlocksPainter(tester);
    final spy = _ClipSpy();
    painter.paint(spy, tester.getSize(cutBlocksFinder()));

    final blocks = painter.blocks();
    final slots = [
      for (final block in blocks)
        for (final cell in block.cells)
          Rect.fromLTRB(
            block.rect.left + cell.startIndex * ppf,
            block.strip.top,
            block.rect.left + cell.endIndexExclusive * ppf,
            block.strip.bottom,
          ),
    ];
    expect(spy.pictures, hasLength(slots.length), reason: 'one per panel');
    for (var i = 0; i < slots.length; i += 1) {
      final draw = spy.pictures[i];
      final rounded = draw.clips.whereType<RRect>().toList();
      expect(rounded, hasLength(1), reason: 'picture $i: only the plate');
      expect(
        rounded.single.tlRadiusX,
        StoryboardCutBlocksPainter.plateCornerRadius,
        reason: 'picture $i: the rounding is the plate\'s corner',
      );
      expect(
        blocks.map((block) => block.rect),
        contains(rounded.single.outerRect),
        reason: 'picture $i: the rounded clip is a whole plate',
      );
      expect(
        draw.clips.whereType<Rect>(),
        [slots[i]],
        reason: 'picture $i: square, and held to its own panel',
      );
    }
    // Nothing else inside the plate wears a corner: every rounded shape
    // drawn is a whole plate.
    for (final shape in spy.roundedShapes) {
      expect(
        blocks.any(
          (block) =>
              shape.outerRect == block.rect ||
              shape.outerRect == block.rect.deflate(0.5),
        ),
        isTrue,
        reason: 'a rounded shape that is not a plate: $shape',
      );
    }
  });
}

/// The picture draws and the clip each one is drawn under — save/restore
/// kept as a stack, the way the canvas itself keeps it.
class _ClipSpy implements Canvas {
  final List<List<Object>> _stack = [[]];
  final pictures = <({Rect dst, List<Object> clips})>[];
  final roundedShapes = <RRect>[];

  List<Object> get _clips => _stack.last;

  @override
  void save() => _stack.add([..._clips]);

  @override
  void restore() {
    if (_stack.length > 1) {
      _stack.removeLast();
    }
  }

  @override
  int getSaveCount() => _stack.length;

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => _clips.add(rect);

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) => _clips.add(rrect);

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      pictures.add((dst: dst, clips: [..._clips]));

  @override
  void drawRRect(RRect rrect, Paint paint) => roundedShapes.add(rrect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
