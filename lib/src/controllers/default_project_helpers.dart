import 'dart:math' show max;

import '../models/app_workspace_colors.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer_id.dart';
import '../models/layer_section_defaults.dart';
import '../models/project.dart';
import '../models/project_frame_rate.dart';
import '../models/project_id.dart';
import '../models/project_timeline.dart';
import '../models/track.dart';
import '../models/track_id.dart';
import '../services/editing/default_cut_helpers.dart';
import '../services/editing/default_layer_helpers.dart';
import '../services/editing/run_id_mint.dart';
import 'timeline_controller.dart' show layerBornWithItsFirstCel;

Project createDefaultProject({DateTime? createdAt}) {
  return Project(
    id: const ProjectId('default-project'),
    name: 'Untitled Project',
    createdAt: createdAt ?? DateTime.now().toUtc(),
    tracks: [createDefaultTrack()],
  );
}

/// A NEW project — the one the app opens with and the one New Project opens
/// in a tab of its own (I-7): the default project under an id no other open
/// project has, its pasteboard seeded from the app-level default (all that
/// remains of the old app-state pasteboard — R3b promotion, R28 #9
/// reversed: the colour is project data now, and this is where「the default
/// for the next project」lands in one).
///
/// 🗣️F-211 (유저 2026-09-28): 「프로젝트 실행 초기값은 초기컷/해당 초기레이어에
/// A라는 레이어 있는상태로 ok. 다만 여기서 **1번인덱스에 프레임도 만들어서
/// 키자마자 그리는게 가능하도록** 하고싶음. 신규유저 배려」. So layer A is
/// born as every animation row Add Layer makes is
/// ([layerBornWithItsFirstCel]).
/// ⛔[createDefaultProject] stays bare: it is the project the tests build on.
///
/// 🗣️new-project-default-fps-23976 (유저 2026-10-06): 「프로젝트 기본 fps
/// 23.976으로하자」. So a new project runs at 24000/1001 and still counts 24:
/// the sheet, the grid and the 6f lines are 24's, and only real time — the
/// sound, the export's length — runs 1000/1001 slower. ⛔It is set HERE, not
/// as the [Project] constructor's default: a file that is read keeps the
/// rate it was saved with, and a project nobody gives a rate — the bare one
/// above, a .tvpp opened as a project — stays at 24 as it was.
Project newUntitledProject() {
  final now = DateTime.now().toUtc();
  return createDefaultProject(createdAt: now).copyWith(
    id: ProjectId('project-${now.microsecondsSinceEpoch}-${_minted++}'),
    pasteboardArgb: AppWorkspaceColors.settings.value.pasteboardArgb,
    frameRate: const ProjectFrameRate.ntsc(24),
    tracks: [_newTrack(createDefaultTrack(), defaultLayerIdForSequence(1))],
  );
}

int _minted = 0;

/// A NEW TIMELINE for [project] (I-150): the track a new project opens with
/// ([newUntitledProject] — 🗣️「새 프로젝트를 만드는것과 동일하게」), under
/// ids [project] holds nowhere — the run's for its track and its cut, and
/// [rowA] for its row — numbered after the last.
///
/// Its cut's canvas is [canvasSize], handed in by whoever stands on a cut:
/// a new cut is the open cut's size (F-537), the default in a gap.
ProjectTimeline newTimelineIn(
  Project project, {
  required LayerId rowA,
  required CanvasSize canvasSize,
}) => ProjectTimeline(
  id: mintTimelineId(),
  number: project.timelines.map((timeline) => timeline.number).reduce(max) + 1,
  tracks: [
    _newTrack(
      createDefaultTrack(
        trackId: mintTrackId(),
        firstCut: _firstCut(
          cutId: mintCutId(),
          rowA: rowA,
          canvasSize: canvasSize,
        ),
      ),
      rowA,
    ),
  ],
);

/// [track] with its row [rowA] born with its first cel (F-211).
Track _newTrack(Track track, LayerId rowA) => track.copyWith(
  cuts: [
    for (final cut in track.cuts)
      cut.copyWith(
        layers: [
          for (final layer in cut.layers)
            if (layer.id == rowA)
              layerBornWithItsFirstCel(layer, mintFrameId(rowA))
            else
              layer,
        ],
      ),
  ],
);

Track createDefaultTrack({
  TrackId trackId = const TrackId('default-track'),
  String name = 'Track 1',
  Cut? firstCut,
}) {
  return Track(
    id: trackId,
    name: name,
    cuts: [firstCut ?? _firstCut()],
    // The timesheet's SE rows are TRACK fixtures (global frame axis).
    seLayers: [
      createTrackSeLayer(trackId: trackId, slot: 1),
      createTrackSeLayer(trackId: trackId, slot: 2),
    ],
  );
}

/// The cut a track opens with: cut 「1」, its row A [rowA].
Cut _firstCut({
  CutId cutId = const CutId('default-cut-1'),
  LayerId? rowA,
  CanvasSize canvasSize = defaultCutCanvasSize,
}) => createDefaultCut(
  cutId: cutId,
  // Bare numbers, the sheet convention (UI-R7 #3): cuts are '1',
  // '2', … — displays add no prefix.
  name: '1',
  layerId: rowA ?? defaultLayerIdForSequence(1),
  canvasSize: canvasSize,
);
