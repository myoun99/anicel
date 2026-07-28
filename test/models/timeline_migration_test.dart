import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// Legacy-format layers (blank entries, length-less drawing entries, the
/// separate marks map, Frame.duration as hold length) must load into the
/// unified model with their OLD VISUALS preserved.
void main() {
  Map<String, dynamic> layerJson({
    required List<Map<String, dynamic>> frames,
    required List<Map<String, dynamic>> timeline,
    List<Map<String, dynamic>>? marks,
  }) {
    return {
      'id': {'value': 'layer-1'},
      'name': 'A',
      'frames': frames,
      'timeline': timeline,
      'marks': ?marks,
      'isVisible': true,
      'opacity': 1.0,
    };
  }

  Map<String, dynamic> frameJson(String id, {int duration = 1}) => {
    'id': {'value': id},
    'duration': duration,
    'strokes': const <Object>[],
  };

  Map<String, dynamic> legacyDrawing(int index, String frameId) => {
    'index': index,
    'exposure': {
      'type': 'drawing',
      'frameId': {'value': frameId},
    },
  };

  Map<String, dynamic> legacyBlank(int index) => {
    'index': index,
    'exposure': {'type': 'blank'},
  };

  test('interior legacy drawings hold until the next entry', () {
    final layer = Layer.fromJson(
      layerJson(
        frames: [frameJson('f1'), frameJson('f2')],
        timeline: [legacyDrawing(0, 'f1'), legacyDrawing(3, 'f2')],
      ),
    );

    expect(
      layer.timeline[0],
      TimelineExposure.drawing(const FrameId('f1'), length: 3),
    );
    expect(exposedFrameIdAt(layer.timeline, 2), const FrameId('f1'));
  });

  test('a legacy blank cuts the preceding hold and disappears', () {
    final layer = Layer.fromJson(
      layerJson(
        frames: [frameJson('f1')],
        timeline: [legacyDrawing(0, 'f1'), legacyBlank(2)],
      ),
    );

    expect(Map<int, TimelineExposure>.from(layer.timeline), {
      0: TimelineExposure.drawing(const FrameId('f1'), length: 2),
    });
    expect(exposedFrameIdAt(layer.timeline, 2), isNull);
  });

  test('the legacy last block takes its Frame.duration as length', () {
    final layer = Layer.fromJson(
      layerJson(
        frames: [frameJson('f1', duration: 4)],
        timeline: [legacyDrawing(0, 'f1')],
      ),
    );

    expect(
      layer.timeline[0],
      TimelineExposure.drawing(const FrameId('f1'), length: 4),
    );
  });

  test('legacy marks fold into the covering block as breakdown offsets; '
      'ones on drawing starts or uncovered cells drop', () {
    final layer = Layer.fromJson(
      layerJson(
        frames: [frameJson('f1')],
        timeline: [legacyDrawing(0, 'f1'), legacyBlank(3)],
        marks: [
          {
            'index': 0,
            'mark': {'type': 'inbetween'},
          },
          {
            'index': 1,
            'mark': {'type': 'inbetween'},
          },
          {
            'index': 5,
            'mark': {'type': 'inbetween'},
          },
        ],
      ),
    );

    expect(Map<int, TimelineExposure>.from(layer.timeline), {
      0: TimelineExposure.drawing(
        const FrameId('f1'),
        length: 3,
        breakdownOffsets: const [1],
      ),
    });
  });

  test('legacy standalone mark ENTRIES fold into the covering block; free '
      'ones drop (and never terminate a legacy hold)', () {
    Map<String, dynamic> legacyMark(int index) => {
      'index': index,
      'exposure': {'type': 'mark'},
    };

    final layer = Layer.fromJson(
      layerJson(
        frames: [frameJson('f1')],
        timeline: [
          legacyDrawing(0, 'f1'),
          legacyMark(2),
          legacyBlank(3),
          legacyMark(6),
        ],
      ),
    );

    // The mark at 2 never terminated the legacy hold (the blank at 3 does);
    // it folds into the block. The mark at 6 sits on empty space and drops.
    expect(Map<int, TimelineExposure>.from(layer.timeline), {
      0: TimelineExposure.drawing(
        const FrameId('f1'),
        length: 3,
        breakdownOffsets: const [2],
      ),
    });
  });

  test('current-format layers round-trip', () {
    final layer = Layer(
      id: const LayerId('layer-1'),
      name: 'A',
      frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
      timeline: {
        0: TimelineExposure.drawing(
          const FrameId('f1'),
          length: 3,
          breakdownOffsets: const [1, 2],
        ),
      },
    );

    final decoded = Layer.fromJson(layer.toJson());
    expect(decoded, layer);
  });

  test('an overlapping length from a corrupt file is clamped to the next '
      'drawing start', () {
    final layer = Layer.fromJson(
      layerJson(
        frames: [frameJson('f1'), frameJson('f2')],
        timeline: [
          {
            'index': 0,
            'exposure': {
              'type': 'drawing',
              'frameId': {'value': 'f1'},
              'length': 9,
            },
          },
          {
            'index': 2,
            'exposure': {
              'type': 'drawing',
              'frameId': {'value': 'f2'},
              'length': 1,
            },
          },
        ],
      ),
    );

    expect(layer.timeline[0]!.length, 2);
  });
}
