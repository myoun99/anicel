import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';

/// 🗣️F-593 (유저 2026-11-15): 「이미지 레이어에도 다른 블록의 그림 복사한거
/// 붙여넣기 가능하게. 어태치 싱크레이어에 붙여넣기 작동시키듯이
/// 그림교체방식으로」 — which rows a paste hangs pictures in rather than
/// laying blocks on, asked of the row alone: the synced attach row and the
/// picture row holding its picture answer it alike, and nothing else does.
void main() {
  const cel = FrameId('cel');

  Layer row(
    LayerKind kind, {
    bool holds = true,
    LayerId? attachedTo,
    AttachedMode mode = AttachedMode.synced,
    MediaReference? reference,
  }) => Layer(
    id: const LayerId('row'),
    name: 'A',
    kind: kind,
    frames: [Frame(id: cel, duration: 1, strokes: const [])],
    timeline: holds
        ? {0: TimelineExposure.drawing(cel, length: 1)}
        : const {},
    attachedToLayerId: attachedTo,
    attachedMode: mode,
    mediaReference: reference,
  );

  final aFile = MediaReference(
    assetPath: 'C:/media/bg.png',
    pose: TransformPose(center: CanvasPoint(x: 0, y: 0)),
    pictureSize: const CanvasSize(width: 640, height: 360),
  );

  test('a picture row holding its picture, and a synced attach row', () {
    expect(pasteHangsPicturesIn(row(LayerKind.image)), isTrue);
    expect(
      pasteHangsPicturesIn(
        row(LayerKind.animation, attachedTo: const LayerId('base')),
      ),
      isTrue,
    );
  });

  test('not a picture row standing empty: a paste lays its one block', () {
    expect(pasteHangsPicturesIn(row(LayerKind.image, holds: false)), isFalse);
  });

  test("not a row whose picture is a file's", () {
    expect(
      pasteHangsPicturesIn(row(LayerKind.image, reference: aFile)),
      isFalse,
    );
  });

  test('not a row a paste lays blocks on — a cel row, a free attach row',
      () {
    expect(pasteHangsPicturesIn(row(LayerKind.animation)), isFalse);
    expect(
      pasteHangsPicturesIn(
        row(
          LayerKind.animation,
          attachedTo: const LayerId('base'),
          mode: AttachedMode.free,
        ),
      ),
      isFalse,
    );
  });
}
