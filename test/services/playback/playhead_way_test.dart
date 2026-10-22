import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/playhead_way.dart';

/// [playheadWay]: where a run's playhead goes when its clock says a frame —
/// for the canvas's run and the media viewer's alike. 유저 2026-10-15,
/// F-365-Q1 「직전 프레임에 서서 기다린다(뷰어와 같은 법)」: before a frame
/// whose picture is not there, on the last one on the way that is.
void main() {
  /// The way from [from] to [to] in a run of [total] frames, where the
  /// frames in [missing] wait for their pictures — and the frames asked.
  ({({int stands, int passed, int? waitsFor}) way, List<int> asked}) walk({
    required int from,
    required int to,
    int total = 10,
    Set<int> missing = const {},
    bool everyPicture = false,
  }) {
    final asked = <int>[];
    final way = playheadWay(
      from: from,
      to: to,
      total: total,
      waitsOn: (frame) {
        asked.add(frame);
        return missing.contains(frame);
      },
      everyPicture: everyPicture,
    );
    return (way: way, asked: asked);
  }

  test('nothing on the way waits: the run stands where its clock says, and '
      'the frames between are passed', () {
    final (:way, :asked) = walk(from: 2, to: 5);
    expect(way, (stands: 5, passed: 2, waitsFor: null));
    expect(asked, [3, 4, 5]);
  });

  test('🚨a frame on the way waits: the run stands on the frame BEFORE it — '
      'the last it has — and waits for that one', () {
    final (:way, :asked) = walk(from: 2, to: 7, missing: {5});
    expect(way, (stands: 4, passed: 1, waitsFor: 5));
    expect(asked, [3, 4, 5], reason: 'nothing past the frame it waits for');
  });

  test('the very next frame waits: the run stays where it stood, and has '
      'passed nothing', () {
    final (:way, asked: _) = walk(from: 2, to: 6, missing: {3, 5});
    expect(way, (stands: 2, passed: 0, waitsFor: 3));
  });

  test('round the end of a lap: the run waits on the lap\'s last frame for '
      'the first', () {
    final (:way, asked: _) = walk(from: 8, to: 1, missing: {0});
    expect(way, (stands: 9, passed: 0, waitsFor: 0));
  });

  test('a clock that says where the run stands moves it nowhere, and asks '
      'about nothing', () {
    final (:way, :asked) = walk(from: 4, to: 4, missing: {4, 5});
    expect(way, (stands: 4, passed: 0, waitsFor: null));
    expect(asked, isEmpty);
  });

  test('🚨COUNTED: a reading outside the run is folded into it, not walked '
      'towards for good', () {
    final (:way, asked: _) = walk(from: 1, to: 23);
    expect(way, (stands: 3, passed: 1, waitsFor: null));
  });

  group('showing every picture (유저 2026-10-15, F-364-Q1 b)', () {
    test('🚨a run behind its clock goes on ONE frame and drops none — it '
        'stands short of its clock', () {
      final (:way, :asked) = walk(from: 2, to: 6, everyPicture: true);
      expect(way, (stands: 3, passed: 0, waitsFor: null));
      expect(asked, [3]);
    });

    test('the next frame not there yet is waited for as ever', () {
      final (:way, asked: _) = walk(
        from: 2,
        to: 6,
        missing: {3},
        everyPicture: true,
      );
      expect(way, (stands: 2, passed: 0, waitsFor: 3));
    });

    test('round the end of a lap the next frame is the first — and a clock '
        'on time, or where the run stands, moves it as ever', () {
      expect(
        walk(from: 9, to: 2, everyPicture: true).way,
        (stands: 0, passed: 0, waitsFor: null),
      );
      expect(
        walk(from: 2, to: 3, everyPicture: true).way,
        (stands: 3, passed: 0, waitsFor: null),
      );
      expect(
        walk(from: 4, to: 4, everyPicture: true).way,
        (stands: 4, passed: 0, waitsFor: null),
      );
    });
  });
}
