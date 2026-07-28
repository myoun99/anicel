import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

void main() {
  group('TimelineExposure', () {
    test('drawing exposure requires a positive length', () {
      expect(
        () => TimelineExposure.drawing(const FrameId('frame-a'), length: 0),
        throwsAssertionError,
      );
    });

    test('round-trips drawing JSON', () {
      final exposure = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 3,
      );

      expect(TimelineExposure.fromJson(exposure.toJson()), exposure);
    });

    test('round-trips breakdown offsets through JSON', () {
      final exposure = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 4,
        breakdownOffsets: const [1, 3],
      );

      expect(exposure.toJson()['breakdown'], const [1, 3]);
      expect(TimelineExposure.fromJson(exposure.toJson()), exposure);
    });

    test('omits the breakdown JSON key when there are no dots', () {
      final exposure = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 3,
      );

      expect(exposure.toJson().containsKey('breakdown'), isFalse);
    });

    test('standalone mark JSON is rejected at the entry level (legacy is '
        'migrated in Layer.fromJson)', () {
      expect(
        () => TimelineExposure.fromJson({'type': 'mark'}),
        throwsFormatException,
      );
    });

    test('drawing JSON without a length is rejected (legacy entries are '
        'migrated at the Layer level)', () {
      expect(
        () => TimelineExposure.fromJson({
          'type': 'drawing',
          'frameId': {'value': 'frame-a'},
        }),
        throwsFormatException,
      );
    });

    test('fromJson normalizes breakdown offsets: sorts, dedupes, clamps', () {
      final exposure = TimelineExposure.fromJson({
        'type': 'drawing',
        'frameId': {'value': 'frame-a'},
        'length': 4,
        'breakdown': [3, 1, 3, 0, 4, 9],
      });

      expect(exposure.breakdownOffsets, const [1, 3]);
    });

    test('copyWith relinks and resizes drawings', () {
      final drawing = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 2,
      );

      expect(
        drawing.copyWith(frameId: const FrameId('frame-b')),
        TimelineExposure.drawing(const FrameId('frame-b'), length: 2),
      );
      expect(
        drawing.copyWith(length: 5),
        TimelineExposure.drawing(const FrameId('frame-a'), length: 5),
      );
    });

    test('copyWith length shrink drops the offsets it cut off', () {
      final drawing = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 6,
        breakdownOffsets: const [1, 3, 5],
      );

      expect(drawing.copyWith(length: 4).breakdownOffsets, const [1, 3]);
      expect(drawing.copyWith(length: 1).breakdownOffsets, isEmpty);
      // Growth keeps everything.
      expect(drawing.copyWith(length: 9).breakdownOffsets, const [1, 3, 5]);
    });

    test('hasBreakdownAt reads the offsets', () {
      final drawing = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 4,
        breakdownOffsets: const [2],
      );

      expect(drawing.hasBreakdownAt(2), isTrue);
      expect(drawing.hasBreakdownAt(1), isFalse);
      expect(drawing.hasBreakdownAt(0), isFalse);
    });

    test('implements equality and hashCode', () {
      final a = TimelineExposure.drawing(const FrameId('frame-a'), length: 1);
      final b = TimelineExposure.drawing(const FrameId('frame-a'), length: 1);
      final c = TimelineExposure.drawing(const FrameId('frame-b'), length: 1);
      final d = TimelineExposure.drawing(const FrameId('frame-a'), length: 2);
      final e = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 2,
        breakdownOffsets: const [1],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(d, isNot(e));
      expect(
        e,
        TimelineExposure.drawing(
          const FrameId('frame-a'),
          length: 2,
          breakdownOffsets: const [1],
        ),
      );
    });
  });
}
