import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/reference_swap.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:flutter_test/flutter_test.dart';

/// I-47: which reference rows take which files in place of the one they
/// show — a movie row a movie, an image row's still a still, and nothing
/// else (유저 2026-09-25 「이미지 레이어의 프레임영역에 떨구면 참조변경」 ·
/// Q1 「참조로 둔 이미지(또는 동영상) 레이어」).
void main() {
  Layer row(LayerKind kind, String? shows) => Layer(
    id: const LayerId('row'),
    name: 'row',
    kind: kind,
    frames: [Frame(id: const FrameId('cel'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('cel'), length: 4)},
    mediaReference: shows == null ? null : MediaReference(assetPath: shows),
  );

  test('🎯an image row showing a still takes another still — as a still', () {
    final bg = row(LayerKind.image, '/work/bg_v1.png');
    expect(referenceSwapFor(bg, '/work/bg_v2.jpg'), ReferenceSwap.still);
    expect(referenceSwapFor(bg, '/work/layout.psd'), ReferenceSwap.still);
  });

  test('🎯a movie row takes another movie — as a movie', () {
    final take = row(LayerKind.animation, '/work/take1.mp4');
    expect(referenceSwapFor(take, '/work/take2.mov'), ReferenceSwap.movie);
  });

  test('a file of the other kind does not stand where the picture stands',
      () {
    expect(
      referenceSwapFor(row(LayerKind.image, '/work/bg.png'), '/work/a.mp4'),
      isNull,
    );
    expect(
      referenceSwapFor(row(LayerKind.animation, '/work/a.mp4'), '/work/b.png'),
      isNull,
    );
    expect(
      referenceSwapFor(row(LayerKind.image, '/work/bg.png'), '/work/a.wav'),
      isNull,
    );
  });

  test('the file the row already shows changes nothing — in either '
      'spelling of its path', () {
    final bg = row(LayerKind.image, 'C:/work/bg.png');
    expect(referenceSwapFor(bg, 'C:/work/bg.png'), isNull);
    expect(referenceSwapFor(bg, r'C:\work\bg.png'), isNull);
  });

  test('⚠️a row of any other shape is not one this answers — a sequence or '
      'GIF on an animation row, a PDF page, a row with no file', () {
    expect(
      referenceSwapFor(row(LayerKind.animation, '/work/A_0001.png'), '/b.png'),
      isNull,
      reason: 'each cel is one picture of the file in order',
    );
    expect(
      referenceSwapFor(row(LayerKind.image, '/work/conte.pdf'), '/b.png'),
      isNull,
    );
    expect(referenceSwapFor(row(LayerKind.image, null), '/b.png'), isNull);
  });
}
