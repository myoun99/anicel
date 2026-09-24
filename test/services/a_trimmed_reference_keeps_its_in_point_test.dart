import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/clipboard/layer_copy_payload.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart';
import 'package:anicel/src/services/commands/relink_media_asset_command.dart';
import 'package:anicel/src/services/editing/cut_duplicate_helpers.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🚨A TRIMMED REFERENCE KEEPS ITS IN POINT WHEREVER THE ROW GOES (미디어
/// 배치 라운드 ⑤, 자른 참조 허용).
///
/// [MediaReference.frameOffset] is how many source frames are skipped before
/// the row's first frame — the answer 「앞을 자르면 파일 안의 시작점이
/// 움직인다」 wrote, and the one every later read of that file depends on.
/// A path that carries the row but drops the offset moves the picture: the
/// same block would show the file from the top again.
///
/// ⚠️**THIS FILE EXISTS BECAUSE THE CODE WAS RIGHT AND UNWATCHED.** Reading
/// the three commands below showed each already carrying the reference whole
/// — and not one assertion anywhere named `frameOffset` while they did it.
/// 「맞다」와 「맞는지 재고 있다」는 다른 말이고, 남는 것은 후자뿐이다.
///
/// ⛔The two paths NOT here, and why:
/// * the DECODE and the EXPORT read the id the one shared visit makes
///   (`resolveExposedFrameAt` → `movieCelFrameId`), and the head trim's own
///   test already pins that that id moves by the offset — asserting it again
///   here would be a second copy of that measurement, not a second path;
/// * 「원본이 오프셋보다 짧을 때」 is not pinned at all, on purpose: what
///   should happen is a decision the board holds ([video-place-Q3]), and a
///   test written before it would freeze whichever answer I guessed.
void main() {
  const oldPath = '/old/take3.mov';
  const newPath = '/new/take3.mov';
  const inPoint = 7;

  Layer movieRow(String id, String path, {int offset = inPoint}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: LayerKind.animation,
    mediaReference: MediaReference(assetPath: path, frameOffset: offset),
  );

  Cut cutWith(List<Layer> layers) => Cut(
    id: const CutId('c'),
    name: 'c',
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Project projectWith(List<Layer> layers) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 12),
    mediaAssets: [MediaAsset(path: oldPath, name: 'take3')],
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [cutWith(layers)],
      ),
    ],
  );

  test('a RELINK moves the path and leaves the in point alone', () {
    final repository = ProjectRepository(
      initialProject: projectWith([movieRow('row', oldPath)]),
    );

    RelinkMediaAssetCommand(
      repository: repository,
      oldPath: oldPath,
      newPath: newPath,
    ).execute();

    final reference = repository
        .requireProject()
        .tracks
        .single
        .cuts
        .single
        .layers
        .single
        .mediaReference!;
    expect(reference.assetPath, newPath, reason: 'the premise: it relinked');
    expect(
      reference.frameOffset,
      inPoint,
      reason: 'a file that MOVED is the same film — the trim is about the '
          'row, not about where the bytes live',
    );
  });

  test('a DUPLICATED row starts where the original started', () {
    final source = movieRow('row', oldPath);

    final copy = duplicateLayerAsIndependentCopy(
      source: source,
      newLayerId: const LayerId('row-copy'),
      newName: 'row copy',
      frameIdMap: <FrameId, FrameId>{},
    );

    expect(copy.mediaReference!.assetPath, oldPath);
    expect(
      copy.mediaReference!.frameOffset,
      inPoint,
      reason: 'the copy shows the same span of the same file — an offset '
          'reset to 0 would run the film from the top on one of them',
    );
  });

  test('a COPIED row pasted elsewhere starts where it started', () {
    final source = movieRow('row', oldPath);
    final target = cutWith([movieRow('other', oldPath, offset: 0)]);

    final plan = planPasteLayerCommandInput(
      project: projectWith([source]),
      targetCut: target,
      payload: copyLayerToPayload(source),
      insertionIndex: 0,
    );

    expect(plan.layer.mediaReference!.assetPath, oldPath);
    expect(
      plan.layer.mediaReference!.frameOffset,
      inPoint,
      reason: 'the payload carries the reference whole, and the paste puts '
          'it back whole — 잘라 둔 구간이 붙여넣기로 풀리지 않는다',
    );
  });

  test('a row with NO reference pastes none — the offset is not a default '
      'somebody inherits', () {
    final plain = Layer(
      id: const LayerId('plain'),
      name: 'plain',
      frames: const [],
      timeline: const {},
    );

    final plan = planPasteLayerCommandInput(
      project: projectWith([plain]),
      targetCut: cutWith(const []),
      payload: copyLayerToPayload(plain),
      insertionIndex: 0,
    );

    expect(plan.layer.mediaReference, isNull);
  });
}
