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
void main() {
  const canvas = CanvasSize(width: 1920, height: 1080);

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

  test('a covered row shows [name] dialogue at its stacked default spot; '
      'rows stack upward so two speakers never pile on one line', () {
    final tags = resolveSeNameTagsAt(
      trackSeLayers: [
        seRow(id: 's1', name: 'S1', seName: 'タモツ', dialogue: 'おはよう'),
        seRow(id: 's2', name: 'S2', seName: 'ユキ', dialogue: 'うん'),
      ],
      cutStartFrame: 0,
      localFrameIndex: 3,
      canvas: canvas,
    );

    expect(tags.map((tag) => tag.content.text), ['[タモツ] おはよう', '[ユキ] うん']);
    expect(tags.first.layerId, 's1');
    final first = tags[0].content.position!;
    final second = tags[1].content.position!;
    expect(first.dx, second.dx, reason: 'one left margin for every row');
    expect(
      second.dy,
      lessThan(first.dy),
      reason: 'later rows stack UPWARD from the bottom',
    );
    expect(tags.first.content.style, SeNameTag.defaultStyle);
    expect(
      tags.first.content.style.backgroundColor,
      0xFFC95C5C,
      reason: 'the アフレコ red box',
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

    final tags = resolveSeNameTagsAt(
      trackSeLayers: [seRow(id: 's1', name: 'S1')],
      cutStartFrame: 0,
      localFrameIndex: 0,
      canvas: canvas,
    );
    expect(tags, isEmpty, reason: 'an empty red box says less than nothing');
  });

  test('the row EYE is the display switch (muted stays the sound gate)', () {
    final rows = [seRow(id: 's1', name: 'S1', seName: 'タモツ', isVisible: false)];
    expect(
      resolveSeNameTagsAt(
        trackSeLayers: rows,
        cutStartFrame: 0,
        localFrameIndex: 0,
        canvas: canvas,
      ),
      isEmpty,
    );

    final visible = [seRow(id: 's1', name: 'S1', seName: 'タモツ')];
    expect(
      resolveSeNameTagsAt(
        trackSeLayers: visible,
        cutStartFrame: 0,
        localFrameIndex: 0,
        canvas: canvas,
      ),
      hasLength(1),
    );
  });

  test('SE rows key on the TRACK-GLOBAL axis: the cut start converts, and '
      'a block that spills in from an earlier cut still shows', () {
    final rows = [
      seRow(
        id: 's1',
        name: 'S1',
        seName: 'タモツ',
        // Global frames 20..32 — the cut starts at 24, so the block
        // spills in and covers this cut's frames 0..8.
        startFrame: 20,
        length: 12,
      ),
    ];
    expect(
      resolveSeNameTagsAt(
        trackSeLayers: rows,
        cutStartFrame: 24,
        localFrameIndex: 0,
        canvas: canvas,
      ),
      hasLength(1),
      reason: 'covered from before the cut',
    );
    expect(
      resolveSeNameTagsAt(
        trackSeLayers: rows,
        cutStartFrame: 24,
        localFrameIndex: 10,
        canvas: canvas,
      ),
      isEmpty,
      reason: 'global frame 34 is past the block',
    );
  });

  test('a configured tag overrides position AND style; the model round-'
      'trips through JSON', () {
    const configured = SeNameTag(
      position: Offset(120, 900),
      style: TextCelStyle(fontSize: 64, color: 0xFF202020),
    );
    final tags = resolveSeNameTagsAt(
      trackSeLayers: [
        seRow(id: 's1', name: 'S1', seName: 'タモツ', tag: configured),
      ],
      cutStartFrame: 0,
      localFrameIndex: 0,
      canvas: canvas,
    );
    expect(tags.single.content.position, const Offset(120, 900));
    expect(tags.single.content.style.fontSize, 64);

    expect(SeNameTag.fromJson(configured.toJson()), configured);
  });
}
