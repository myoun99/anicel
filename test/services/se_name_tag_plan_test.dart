import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/se_name_tag_plan.dart';

/// The on-canvas SE name tag resolution (R5b, §6-z15): which rows show
/// what over the picture at a given cut frame — pure, so the editing
/// canvas, playback and export can't disagree.
///
/// The canvas and the camera frame are DELIBERATELY different sizes here
/// (the shipped defaults are 2340×1654 paper against a 1920×1080 camera):
/// a canvas-relative default sits perfectly visible while editing and is
/// clipped away in every framed surface, which is exactly the defect an
/// equal-size fixture cannot see.
void main() {
  const canvas = CanvasSize(width: 2340, height: 1654);
  const camera = CanvasSize(width: 1920, height: 1080);

  Layer seRow({
    required String id,
    required String name,
    String? seName,
    String? dialogue,
    int startFrame = 0,
    int length = 12,
    bool isVisible = true,
    SeNameTag? tag,
  }) {
    final frameId = FrameId('$id-cel');
    return Layer(
      id: LayerId(id),
      name: name,
      kind: LayerKind.se,
      isVisible: isVisible,
      seNameTag: tag,
      frames: [
        Frame(
          id: frameId,
          duration: length,
          strokes: const [],
          name: dialogue,
          seName: seName,
        ),
      ],
      timeline: {startFrame: TimelineExposure.drawing(frameId, length: length)},
    );
  }

  List<ResolvedSeNameTag> resolve(
    List<Layer> rows, {
    int cutStartFrame = 0,
    int localFrameIndex = 0,
    int rowOffset = 0,
  }) => resolveSeNameTagsAt(
    trackSeLayers: rows,
    cutStartFrame: cutStartFrame,
    localFrameIndex: localFrameIndex,
    canvas: canvas,
    cameraFrame: camera,
    rowOffset: rowOffset,
  );

  test('a covered row shows [name] dialogue, and the stacked default lands '
      'INSIDE THE SHOT — the canvas is bigger than the frame, so a '
      'canvas-relative default would never reach the video', () {
    final tags = resolve([
      seRow(id: 's1', name: 'S1', seName: 'タモツ', dialogue: 'おはよう'),
      seRow(id: 's2', name: 'S2', seName: 'ユキ', dialogue: 'うん'),
    ], localFrameIndex: 3);

    expect(tags.map((tag) => tag.content.text), ['[タモツ] おはよう', '[ユキ] うん']);
    expect(tags.first.layerId, 's1');

    // The camera's rect on the canvas at the resting pose.
    final shot = shotRectIn(canvas: canvas, cameraFrame: camera);
    for (final tag in tags) {
      final position = tag.content.position!;
      expect(
        position.dx,
        inInclusiveRange(shot.left, shot.left + shot.width),
        reason: 'inside the shot horizontally',
      );
      expect(
        position.dy,
        inInclusiveRange(shot.top, shot.top + shot.height),
        reason:
            'inside the shot vertically — the defect that shipped tags '
            'to an editing canvas and an empty MP4',
      );
    }

    final first = tags[0].content.position!;
    final second = tags[1].content.position!;
    expect(first.dx, second.dx, reason: 'one left margin for every row');
    expect(
      second.dy,
      lessThan(first.dy),
      reason: 'later rows stack UPWARD from the bottom',
    );
    // The pitch must clear the painted red box (line height + both pads),
    // or consecutive boxes fuse into one stepped blob.
    final boxHeight = SeNameTag.defaultStyle.fontSize * (1.25 + 0.25 * 2);
    expect(first.dy - second.dy, greaterThan(boxHeight));
    expect(tags.first.content.style, SeNameTag.defaultStyle);
    expect(
      tags.first.content.style.backgroundColor,
      0xFFC95C5C,
      reason: 'the アフレコ red box',
    );
    expect(
      tags.first.widthBudget,
      lessThanOrEqualTo(shot.width),
      reason: 'a long line shrinks to the shot, never runs off it',
    );
  });

  test('rowOffset stacks the tracks BELOW this one, so a multitrack frame '
      'never piles two tracks on one spot', () {
    final base = resolve([seRow(id: 's1', name: 'S1', seName: 'A')]);
    final upper = resolve([
      seRow(id: 't1', name: 'S1', seName: 'B'),
    ], rowOffset: 2);
    expect(
      upper.single.content.position!.dy,
      lessThan(base.single.content.position!.dy),
    );
  });

  test('a lone speaker needs no brackets and a lone line needs no box '
      'label; a block with no writing at all shows nothing', () {
    expect(
      seNameTagText(seName: 'タモツ', dialogue: null),
      'タモツ',
      reason: 'the box already frames the name',
    );
    expect(seNameTagText(seName: '  ', dialogue: 'おはよう'), 'おはよう');
    expect(seNameTagText(seName: null, dialogue: '  '), isEmpty);

    expect(
      resolve([seRow(id: 's1', name: 'S1')]),
      isEmpty,
      reason: 'an empty red box says less than nothing',
    );
  });

  test('the row EYE is the display switch (muted stays the sound gate)', () {
    expect(
      resolve([seRow(id: 's1', name: 'S1', seName: 'タモツ', isVisible: false)]),
      isEmpty,
    );
    expect(resolve([seRow(id: 's1', name: 'S1', seName: 'タモツ')]), hasLength(1));
  });

  test('SE rows key on the TRACK-GLOBAL axis: the cut start converts, and '
      'a block that spills in from an earlier cut still shows', () {
    final rows = [
      // Global frames 20..32 — the cut starts at 24, so the block spills
      // in and covers this cut's frames 0..8.
      seRow(id: 's1', name: 'S1', seName: 'タモツ', startFrame: 20, length: 12),
    ];
    expect(
      resolve(rows, cutStartFrame: 24, localFrameIndex: 0),
      hasLength(1),
      reason: 'covered from before the cut',
    );
    expect(
      resolve(rows, cutStartFrame: 24, localFrameIndex: 10),
      isEmpty,
      reason: 'global frame 34 is past the block',
    );
  });

  test('a configured tag overrides position AND style; a STYLE-ONLY tag '
      'keeps riding the per-cut default (the position stays null)', () {
    const configured = SeNameTag(
      position: Offset(400, 900),
      style: TextCelStyle(fontSize: 64, color: 0xFF202020),
    );
    final placed = resolve([
      seRow(id: 's1', name: 'S1', seName: 'タモツ', tag: configured),
    ]);
    expect(placed.single.content.position, const Offset(400, 900));
    expect(placed.single.content.style.fontSize, 64);
    expect(SeNameTag.fromJson(configured.toJson()), configured);

    const styleOnly = SeNameTag(style: TextCelStyle(fontSize: 20));
    final styled = resolve([
      seRow(id: 's1', name: 'S1', seName: 'タモツ', tag: styleOnly),
    ]);
    expect(styled.single.content.style.fontSize, 20);
    expect(
      styled.single.content.position,
      defaultSeNameTagPosition(
        canvas: canvas,
        cameraFrame: camera,
        rowIndex: 0,
      ),
      reason: 'a colour edit must not pin this cut\'s default in pixels',
    );
    expect(SeNameTag.fromJson(styleOnly.toJson()).position, isNull);
  });
}
