import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/services/camera_projection_matrix.dart';
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

  /// The shot of a camera at rest over [canvas] — centred, zoom 1.
  final atRest = shotPlacement(
    CameraPose(
      center: CanvasPoint(x: canvas.width / 2, y: canvas.height / 2),
    ),
    camera,
  );

  List<ResolvedSeNameTag> resolve(List<Layer> rows, {int globalFrame = 0}) =>
      resolveSeNameTagsAt(
        trackSeLayers: rows,
        globalFrame: globalFrame,
        cameraFrame: camera,
        shot: atRest,
      );

  test('a covered row shows the name and the dialogue as SEPARATE runs, and '
      'the stacked default lands INSIDE THE SHOT — the canvas is bigger '
      'than the frame, so a canvas-relative default would never reach the '
      'video', () {
    final tags = resolve([
      seRow(id: 's1', name: 'S1', seName: 'タモツ', dialogue: 'おはよう'),
      seRow(id: 's2', name: 'S2', seName: 'ユキ', dialogue: 'うん'),
    ], globalFrame: 3);

    // R5 #7: two runs, not one `[name] line` string — the name lives in
    // the box and the dialogue hangs beside it with its own ink.
    expect(tags.map((tag) => tag.content.text), ['タモツ', 'ユキ']);
    expect(tags.map((tag) => tag.line?.text), ['おはよう', 'うん']);
    expect(tags.first.layerId, 's1');

    // A tag's position is the shot's own (I-67-Q1): inside the frame by
    // what it is, wherever the shot lies on the canvas.
    for (final tag in tags) {
      final position = tag.content.position!;
      expect(
        position.dx,
        inInclusiveRange(0, camera.width),
        reason: 'inside the shot horizontally',
      );
      expect(
        position.dy,
        inInclusiveRange(0, camera.height),
        reason:
            'inside the shot vertically — the defect that shipped tags '
            'to an editing canvas and an empty MP4',
      );
    }

    expect(tags.first.content.style, SeNameTag.defaultStyle);
    expect(
      tags.first.content.style.backgroundColor,
      0xFFC95C5C,
      reason: 'the アフレコ red box',
    );
    expect(
      tags.first.widthBudget,
      lessThanOrEqualTo(camera.width),
      reason: 'a long line shrinks to the shot, never runs off it',
    );
  });

  // The `rowOffset` stacking test went with the stacked default: nothing
  // shifts per row or per track any more, so there is no offset to pin —
  // and the parameter went after it (2026-10-01), still passed and read by
  // nobody.

  test('a block with no writing at all shows nothing', () {
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

  // ↩️This passed a cut's start and a frame of the cut, which the function
  // added: where a cut's frames stand on the track is the caller's to say
  // (I-73-ol-index-space).
  test('SE rows key on the TRACK-GLOBAL axis: a block shows over the '
      'frames of the track it covers, and nowhere else', () {
    final rows = [
      // Global frames 20..32.
      seRow(id: 's1', name: 'S1', seName: 'タモツ', startFrame: 20, length: 12),
    ];
    expect(resolve(rows, globalFrame: 24), hasLength(1));
    expect(resolve(rows, globalFrame: 20), hasLength(1));
    expect(resolve(rows, globalFrame: 19), isEmpty, reason: 'before it');
    expect(resolve(rows, globalFrame: 32), isEmpty, reason: 'past it');
    expect(resolve(rows, globalFrame: -1), isEmpty);
  });

  // R5 #7 (user, 2026-08-09): the tag has no position of its own, and rows
  // get no per-row default. Every tag starts at the centre and the SE
  // row's TRANSFORM moves it — one rule, no exception per row. I-67-Q1
  // (user, 2026-10-10): the SHOT's centre — the transform is the shot's.
  test('an untouched row puts its tag at the SHOT\'S CENTRE, and so does '
      'every other row — a camera at rest lays it on the canvas centre', () {
    final tags = resolve([
      seRow(id: 's1', name: 'S1', seName: 'タモツ'),
      seRow(id: 's2', name: 'S2', seName: 'ユキ'),
    ]);
    final centre = Offset(camera.width / 2, camera.height / 2);
    expect(tags.map((tag) => tag.content.position), [centre, centre]);
    expect(
      atRest.apply(CanvasPoint(x: centre.dx, y: centre.dy)),
      CanvasPoint(x: canvas.width / 2, y: canvas.height / 2),
    );
  });

  test('every tag carries the shot it stands in', () {
    final tags = resolve([
      seRow(id: 's1', name: 'S1', seName: 'タモツ'),
      seRow(id: 's2', name: 'S2', seName: 'ユキ'),
    ]);
    expect(tags.map((tag) => tag.shot), [atRest, atRest]);
  });

  test('the row\'s TRANSFORM is what moves it', () {
    final moved = seRow(id: 's1', name: 'S1', seName: 'タモツ').copyWith(
      transformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 400, y: 900),
        ),
      ),
    );
    expect(resolve([moved]).single.content.position, const Offset(400, 900));
  });

  test('a style-only tag round-trips and never places', () {
    const styleOnly = SeNameTag(style: TextCelStyle(fontSize: 20));
    final styled = resolve([
      seRow(id: 's1', name: 'S1', seName: 'タモツ', tag: styleOnly),
    ]);
    expect(styled.single.content.style.fontSize, 20);
    expect(SeNameTag.fromJson(styleOnly.toJson()), styleOnly);
    expect(
      styled.single.content.position,
      Offset(camera.width / 2, camera.height / 2),
    );
  });
}
