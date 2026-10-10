import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/reference_swap.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/reference_to.dart';

/// I-47: which reference rows take which files in place of the one they
/// show — a movie row a movie, an image row's still a still, and nothing
/// else (유저 2026-09-25 「이미지 레이어의 프레임영역에 떨구면 참조변경」 ·
/// Q1 「참조로 둔 이미지(또는 동영상) 레이어」).
void main() {
  Layer row(LayerKind kind, String? shows) => Layer(
    id: const LayerId('row'),
    name: 'row',
    kind: kind,
    frames: [
      Frame(
        id: const FrameId('cel'),
        duration: 1,
        strokes: const [],
        filePicture: shows == null ? null : 0,
      ),
    ],
    timeline: {0: const TimelineExposure.drawing(FrameId('cel'), length: 4)},
    mediaReference: shows == null ? null : referenceTo(shows),
  );

  test('🎯an image row showing a still takes another still — as a still', () {
    final bg = row(LayerKind.image, '/work/bg_v1.png');
    expect(referenceSwapFor(bg, '/work/bg_v2.jpg'), ReferenceSwap.pictures);
    expect(referenceSwapFor(bg, '/work/layout.psd'), ReferenceSwap.pictures);
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

  // I-68 (유저 2026-10-10 「가」): every row that shows a file is laid again
  // by one law — each cel its own picture of the file.
  group('drawn again from the file', () {
    Layer cels(String shows, List<int?> pictures) => Layer(
      id: const LayerId('seq'),
      name: 'seq',
      frames: [
        for (final (index, picture) in pictures.indexed)
          Frame(
            id: FrameId('c$index'),
            duration: 1,
            strokes: const [],
            filePicture: picture,
          ),
      ],
      timeline: {
        for (var index = 0; index < pictures.length; index += 1)
          index: TimelineExposure.drawing(FrameId('c$index'), length: 1),
      },
      mediaReference: referenceTo(shows),
    );

    test('🎯a GIF\'s frames and a PDF\'s pages are, when each cel says which '
        'picture of the file it is', () {
      expect(
        referenceRedrawFor(cels('/work/a.gif', [3, 4, 6])),
        ReferenceSwap.pictures,
      );
      expect(
        referenceRedrawFor(cels('/work/conte.pdf', [12, 13])),
        ReferenceSwap.pictures,
      );
      expect(
        referenceRedrawFor(row(LayerKind.image, '/work/bg.png')),
        ReferenceSwap.pictures,
        reason: 'a still is the one-cel case of the same law',
      );
      expect(
        referenceRedrawFor(row(LayerKind.animation, '/work/take.mp4')),
        ReferenceSwap.movie,
      );
    });

    test('a row with a cel that does not say is not — that one could not be '
        'made again — nor is a row with no file', () {
      expect(referenceRedrawFor(cels('/work/a.gif', [3, null])), isNull);
      expect(referenceRedrawFor(cels('/work/a.gif', [])), isNull);
      expect(referenceRedrawFor(row(LayerKind.image, null)), isNull);
    });
  });
}
