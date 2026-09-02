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
      const exposure = TimelineExposure.drawing(
        FrameId('frame-a'),
        length: 3,
      );

      expect(TimelineExposure.fromJson(exposure.toJson()), exposure);
    });

    test('round-trips breakdown offsets through JSON', () {
      const exposure = TimelineExposure.drawing(
        FrameId('frame-a'),
        length: 4,
        breakdownOffsets: [1, 3],
      );

      expect(exposure.toJson()['breakdown'], const [1, 3]);
      expect(TimelineExposure.fromJson(exposure.toJson()), exposure);
    });

    test('omits the breakdown JSON key when there are no dots', () {
      const exposure = TimelineExposure.drawing(
        FrameId('frame-a'),
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
      const drawing = TimelineExposure.drawing(
        FrameId('frame-a'),
        length: 2,
      );

      expect(
        drawing.copyWith(frameId: const FrameId('frame-b')),
        const TimelineExposure.drawing(FrameId('frame-b'), length: 2),
      );
      expect(
        drawing.copyWith(length: 5),
        const TimelineExposure.drawing(FrameId('frame-a'), length: 5),
      );
    });

    test('copyWith length shrink drops the offsets it cut off', () {
      const drawing = TimelineExposure.drawing(
        FrameId('frame-a'),
        length: 6,
        breakdownOffsets: [1, 3, 5],
      );

      expect(drawing.copyWith(length: 4).breakdownOffsets, const [1, 3]);
      expect(drawing.copyWith(length: 1).breakdownOffsets, isEmpty);
      // Growth keeps everything.
      expect(drawing.copyWith(length: 9).breakdownOffsets, const [1, 3, 5]);
    });

    test('hasBreakdownAt reads the offsets', () {
      const drawing = TimelineExposure.drawing(
        FrameId('frame-a'),
        length: 4,
        breakdownOffsets: [2],
      );

      expect(drawing.hasBreakdownAt(2), isTrue);
      expect(drawing.hasBreakdownAt(1), isFalse);
      expect(drawing.hasBreakdownAt(0), isFalse);
    });

    test('implements equality and hashCode', () {
      const a = TimelineExposure.drawing(FrameId('frame-a'), length: 1);
      const b = TimelineExposure.drawing(FrameId('frame-a'), length: 1);
      const c = TimelineExposure.drawing(FrameId('frame-b'), length: 1);
      const d = TimelineExposure.drawing(FrameId('frame-a'), length: 2);
      const e = TimelineExposure.drawing(
        FrameId('frame-a'),
        length: 2,
        breakdownOffsets: [1],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(d, isNot(e));
      expect(
        e,
        const TimelineExposure.drawing(
          FrameId('frame-a'),
          length: 2,
          breakdownOffsets: [1],
        ),
      );
    });
  });
}
