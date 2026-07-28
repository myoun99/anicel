import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  group('BrushFrameKey', () {
    test('uses full Project / Track / Cut / Layer / Frame identity', () {
      const key = BrushFrameKey(
        projectId: ProjectId('project-1'),
        trackId: TrackId('track-1'),
        cutId: CutId('cut-1'),
        layerId: LayerId('layer-1'),
        frameId: FrameId('frame-1'),
      );

      expect(key.projectId, const ProjectId('project-1'));
      expect(key.trackId, const TrackId('track-1'));
      expect(key.cutId, const CutId('cut-1'));
      expect(key.layerId, const LayerId('layer-1'));
      expect(key.frameId, const FrameId('frame-1'));
    });

    test('compares every path component', () {
      const key = BrushFrameKey(
        projectId: ProjectId('project-1'),
        trackId: TrackId('track-1'),
        cutId: CutId('cut-1'),
        layerId: LayerId('layer-1'),
        frameId: FrameId('frame-1'),
      );

      expect(key, equals(key));
      expect(
        key,
        equals(
          const BrushFrameKey(
            projectId: ProjectId('project-1'),
            trackId: TrackId('track-1'),
            cutId: CutId('cut-1'),
            layerId: LayerId('layer-1'),
            frameId: FrameId('frame-1'),
          ),
        ),
      );
      expect(
        key,
        isNot(
          equals(
            const BrushFrameKey(
              projectId: ProjectId('project-2'),
              trackId: TrackId('track-1'),
              cutId: CutId('cut-1'),
              layerId: LayerId('layer-1'),
              frameId: FrameId('frame-1'),
            ),
          ),
        ),
      );
    });
  });
}
