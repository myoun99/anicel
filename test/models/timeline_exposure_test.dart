import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/frame.dart' show InbetweenMark;

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
        breakdownMarks: {1: InbetweenMark.two, 3: InbetweenMark.two},
      );

      expect(exposure.toJson()['breakdown'], const [1, 3]);
      expect(TimelineExposure.fromJson(exposure.toJson()), exposure);
    });

    test('🗣️I-130: each mark round-trips under its own key, and a file '
        'written with the one ● still reads as the ● — mark 2', () {
      const exposure = TimelineExposure.drawing(
        FrameId('frame-a'),
        length: 5,
        breakdownMarks: {1: InbetweenMark.one, 3: InbetweenMark.two},
      );
      final json = exposure.toJson();

      expect(json['breakdown1'], const [1]);
      expect(json['breakdown'], const [3]);
      expect(TimelineExposure.fromJson(json), exposure);
      expect(
        TimelineExposure.fromJson({
          'type': 'drawing',
          'frameId': {'value': 'frame-a'},
          'length': 4,
          'breakdown': [2],
        }).breakdownMarks,
        {2: InbetweenMark.two},
      );
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
        breakdownMarks: {
          1: InbetweenMark.two,
          3: InbetweenMark.two,
          5: InbetweenMark.two,
        },
      );

      expect(drawing.copyWith(length: 4).breakdownOffsets, const [1, 3]);
      expect(drawing.copyWith(length: 1).breakdownOffsets, isEmpty);
      // Growth keeps everything.
      expect(drawing.copyWith(length: 9).breakdownOffsets, const [1, 3, 5]);
    });

    test('a block that starts a cut in keeps the dots past it, moved back '
        'and each wearing its own mark', () {
      const marks = {
        1: InbetweenMark.one,
        2: InbetweenMark.two,
        4: InbetweenMark.one,
        5: InbetweenMark.two,
      };

      expect(TimelineExposure.marksPastCut(marks, 2), {
        2: InbetweenMark.one,
        3: InbetweenMark.two,
      }, reason: 'the dot ON the cut is the new head, the drawing itself');
      expect(TimelineExposure.marksPastCut(marks, 0), marks);
    });

    test('implements equality and hashCode', () {
      const a = TimelineExposure.drawing(FrameId('frame-a'), length: 1);
      const b = TimelineExposure.drawing(FrameId('frame-a'), length: 1);
      const c = TimelineExposure.drawing(FrameId('frame-b'), length: 1);
      const d = TimelineExposure.drawing(FrameId('frame-a'), length: 2);
      const e = TimelineExposure.drawing(
        FrameId('frame-a'),
        length: 2,
        breakdownMarks: {1: InbetweenMark.two},
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(d, isNot(e));
      expect(
        e,
        isNot(
          const TimelineExposure.drawing(
            FrameId('frame-a'),
            length: 2,
            breakdownMarks: {1: InbetweenMark.one},
          ),
        ),
        reason: 'the same cell wearing the other mark is another entry',
      );
      expect(
        e,
        const TimelineExposure.drawing(
          FrameId('frame-a'),
          length: 2,
          breakdownMarks: {1: InbetweenMark.two},
        ),
      );
    });
  });
}
