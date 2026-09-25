import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart' show requireCut;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// 🚨A CONTE BLOCK'S ACTION IS ITS OWN.
///
/// 유저 2026-09-25: 「데이터는 알겟지만 해당 콘티블록에 저장. 다만 아까
/// 잉크와 마찬가지로 독립적임. 같은 이름의 콘티블록이랑 링크된다고 해도
/// 내용물은 독립」. The words live on the exposure that opens the cell, and a
/// link shares a layer's drawing, never its timeline's entries — so two
/// cuts whose conte rows are LINKED and whose blocks are the SAME NAME still
/// each keep the words written on them.
void main() {
  const track = TrackId('track');
  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 6,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: [
      Layer(
        id: LayerId('$id-sb'),
        name: 'SB',
        kind: LayerKind.storyboard,
        // The SAME name on both blocks.
        frames: [
          Frame(
            id: FrameId('$id-f'),
            duration: 1,
            name: 'A',
            strokes: const [],
          ),
        ],
        timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 6)},
      ),
    ],
  );

  test('writing one block\'s ACTION leaves a linked, same-named block\'s '
      'words where they were', () {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('action-own'),
        name: 'Conte',
        createdAt: DateTime.utc(2026, 9, 25),
        tracks: [
          Track(id: track, name: 'Video', cuts: [cut('1'), cut('2')]),
        ],
        linkRegistry: LayerLinkRegistry(
          groups: [
            LayerLinkGroup(
              id: 'sb-link',
              members: const [
                LayerLinkMember(
                  trackId: track,
                  cutId: CutId('1'),
                  layerId: LayerId('1-sb'),
                ),
                LayerLinkMember(
                  trackId: track,
                  cutId: CutId('2'),
                  layerId: LayerId('2-sb'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    addTearDown(session.dispose);

    session.storyboardCursor.setStoryboardCellAction(
      cutId: const CutId('1'),
      cellIndex: 0,
      action: 'ハヤト走る',
    );

    Layer conteRow(String id) => storyboardLayerForCut(
      requireCut(session.repository.requireProject(), CutId(id)),
    )!;
    expect(conteRow('1').timeline[0]!.memo?.actionMemo, 'ハヤト走る');
    expect(
      conteRow('2').timeline[0]!.memo,
      isNull,
      reason: 'linked and same-named, and still its own words',
    );
  });
}
