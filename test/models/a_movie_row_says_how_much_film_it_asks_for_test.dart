import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// 🚨HOW FAR INTO ITS MOVIE A ROW REACHES — the one law three readers share
/// (미디어 배치 라운드; 유저 2026-09-12 `video-place` Q3).
///
/// `movieElapsedAt` is what the composite visit, the bake and the
/// source-length check all count with. It was written twice before this
/// round and about to be written a third time; these are the assertions that
/// keep the single copy honest, because 「같은 값을 세 곳이 따로 세고 있었다」
/// is invisible to every behaviour test that only ever exercises one of them.
void main() {
  Layer movieRow({
    Map<int, TimelineExposure> timeline = const {},
    int offset = 0,
  }) => Layer(
    id: const LayerId('a'),
    name: 'a',
    frames: const [],
    timeline: timeline,
    kind: LayerKind.animation,
    mediaReference: MediaReference(
      assetPath: '/takes/pan.mov',
      frameOffset: offset,
    ),
  );

  Map<int, TimelineExposure> blocksOf(Map<int, int> startToLength) => {
    for (final entry in startToLength.entries)
      entry.key: TimelineExposure.drawing(
        FrameId('f${entry.key}'),
        length: entry.value,
      ),
  };

  group('한 위치가 영상의 어디인가', () {
    final cut = MediaReference(assetPath: '/takes/pan.mov', frameOffset: 7);
    final whole = MediaReference(assetPath: '/takes/pan.mov');

    test('머리를 자른 만큼 안쪽에서 시작한다', () {
      expect(movieElapsedAt(cut, 0), 7);
      expect(movieElapsedAt(cut, 3), 10);
    });

    test('자르지 않은 참조에서는 위치가 곧 그 답이다', () {
      expect(movieElapsedAt(whole, 0), 0);
      expect(movieElapsedAt(whole, 12), 12);
    });
  });

  group('행이 파일에 요구하는 길이', () {
    test('블록 하나면 그 블록의 끝까지다', () {
      expect(movieProjectFramesAskedOf(movieRow(timeline: blocksOf({0: 5}))), 5);
    });

    test('🚨머리를 자르면 요구가 그만큼 깊어진다 — 같은 5칸이 파일 안에서는 '
        '7부터 11까지다', () {
      final row = movieRow(timeline: blocksOf({0: 5}), offset: 7);
      expect(movieProjectFramesAskedOf(row), 12);
    });

    test('🚨블록마다 영상은 처음부터 다시 흐르므로, 답은 가장 긴 블록이지 '
        '마지막 블록의 끝도 마지막 블록의 길이도 아니다', () {
      // `resolveExposedFrameAt` counts from the block's OWN start, so the
      // second block shows the same opening frames again — a row of two
      // blocks 10 apart asks for as much film as its LONGEST one, not for
      // everything up to frame 12.
      //
      // ⚠️THE LONG BLOCK IS FIRST ON PURPOSE. With it last, 「the largest」
      // and 「the one the loop ended on」 are the same number, and this
      // assertion would pass on a version that simply kept the last.
      final row = movieRow(timeline: blocksOf({0: 5, 10: 2}));
      expect(movieProjectFramesAskedOf(row), 5);
    });

    test('⛔빈 타임라인은 아무것도 요구하지 않는다', () {
      expect(movieProjectFramesAskedOf(movieRow()), 0);
    });

    test('⛔파일을 가리키지 않는 행도 0이다 — 물을 원본이 없다', () {
      final plain = Layer(
        id: const LayerId('b'),
        name: 'b',
        frames: const [],
        kind: LayerKind.animation,
      );
      expect(movieProjectFramesAskedOf(plain), 0);
    });
  });
}
