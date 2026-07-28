import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  group('typed IDs', () {
    test('IDs with the same value are equal', () {
      expect(
        const ProjectId('project-1'),
        equals(const ProjectId('project-1')),
      );
      expect(const TrackId('track-1'), equals(const TrackId('track-1')));
      expect(const CutId('cut-1'), equals(const CutId('cut-1')));
      expect(const LayerId('layer-1'), equals(const LayerId('layer-1')));
      expect(const FrameId('frame-1'), equals(const FrameId('frame-1')));
      expect(const StrokeId('stroke-1'), equals(const StrokeId('stroke-1')));
    });

    test('IDs with different values are not equal', () {
      expect(
        const ProjectId('project-1'),
        isNot(equals(const ProjectId('project-2'))),
      );
      expect(const TrackId('track-1'), isNot(equals(const TrackId('track-2'))));
      expect(const CutId('cut-1'), isNot(equals(const CutId('cut-2'))));
      expect(const LayerId('layer-1'), isNot(equals(const LayerId('layer-2'))));
      expect(const FrameId('frame-1'), isNot(equals(const FrameId('frame-2'))));
      expect(
        const StrokeId('stroke-1'),
        isNot(equals(const StrokeId('stroke-2'))),
      );
    });

    test('toJson and fromJson preserve values', () {
      expect(
        ProjectId.fromJson(const ProjectId('project-1').toJson()),
        const ProjectId('project-1'),
      );
      expect(
        TrackId.fromJson(const TrackId('track-1').toJson()),
        const TrackId('track-1'),
      );
      expect(
        CutId.fromJson(const CutId('cut-1').toJson()),
        const CutId('cut-1'),
      );
      expect(
        LayerId.fromJson(const LayerId('layer-1').toJson()),
        const LayerId('layer-1'),
      );
      expect(
        FrameId.fromJson(const FrameId('frame-1').toJson()),
        const FrameId('frame-1'),
      );
      expect(
        StrokeId.fromJson(const StrokeId('stroke-1').toJson()),
        const StrokeId('stroke-1'),
      );
    });
  });
}
