import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/session/layer_id_mint.dart';
import 'package:anicel/src/ui/session/session_roles.dart';

/// WHERE A NEW ROW'S ID COMES FROM — pinned (2026-09-08; nothing named
/// `session/layer_id_mint.dart` before this).
///
/// 🚨THE COUNTER ALONE IS NOT ENOUGH, and that is the whole file. The
/// counter is SESSION state while the project can arrive from DISK: open a
/// file that already holds `default-layer-2` and a bare counter mints
/// straight on top of an existing row. Two layers, one id — which surfaced
/// as a red screen from the rail (`multiple children with key
/// …default-layer-2-row`), because a duplicate key is what a duplicate id
/// looks like downstream.
void main() {
  ProjectRepository repositoryHolding(List<LayerId> ids) => ProjectRepository(
    initialProject: Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 9, 8),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'T',
          cuts: [
            Cut(
              id: const CutId('c'),
              name: '1',
              duration: 4,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                for (final id in ids)
                  Layer(
                    id: id,
                    name: id.value,
                    frames: const [],
                    timeline: const {},
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  LayerIdMint mintOver(ProjectRepository repository) =>
      LayerIdMint(project: _ProjectOnly(repository));

  test('every mint is a NEW id — the counter never hands the same one twice',
      () {
    final mint = mintOver(repositoryHolding(const []));
    final minted = [for (var i = 0; i < 5; i += 1) mint.mint().value];
    expect(minted.toSet(), hasLength(5));
    for (final id in minted) {
      expect(id, startsWith('default-layer-'));
    }
  });

  test('🚨the PROJECT has the last word: an id a loaded file already holds '
      'is never minted onto', () {
    // The counter is at its opening value, so without the scan the very
    // next mint is the id this project already carries.
    final naive = mintOver(repositoryHolding(const [])).mint();
    final mint = mintOver(repositoryHolding([naive]));

    expect(
      mint.mint().value,
      isNot(naive.value),
      reason: 'a session counter cannot know what came off disk — this is '
          'the duplicate-row-key red screen, one step upstream',
    );
  });

  test('it walks PAST a whole run the project already holds, not just one',
      () {
    final free = mintOver(repositoryHolding(const []));
    final taken = [for (var i = 0; i < 3; i += 1) free.mint()];
    final mint = mintOver(repositoryHolding(taken));

    final fresh = mint.mint();
    expect(taken.map((id) => id.value), isNot(contains(fresh.value)));
  });

  group('🚨the scan is the WHOLE project — track rows hold ids too (F-131)', () {
    // A track SE row and the transition row take their ids from the same
    // `default-layer-N` counter as a cut layer, and the counter restarts
    // every session. The scan used to walk cut layers only, so a reopened
    // file could mint a new row the id of S3 — and the lookup, which checks
    // track rows first, then wrote that row's frames and attach arrow onto
    // the SE row (「가끔 … S3 에도 프레임이 생기고 어태치 아이콘」).
    ProjectRepository holdingTrackRows({
      List<LayerId> seIds = const [],
      LayerId? transitionId,
    }) => ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 9, 15),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [
              Cut(
                id: const CutId('c'),
                name: '1',
                duration: 4,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: const [],
              ),
            ],
            seLayers: [
              for (final id in seIds)
                Layer(
                  id: id,
                  name: id.value,
                  frames: const [],
                  timeline: const {},
                ),
            ],
            transitionLayer: transitionId == null
                ? null
                : Layer(
                    id: transitionId,
                    name: 'O',
                    frames: const [],
                    timeline: const {},
                  ),
          ),
        ],
      ),
    );

    test('an id a track SE row holds is never minted onto', () {
      final naive = mintOver(repositoryHolding(const [])).mint();
      final mint = mintOver(holdingTrackRows(seIds: [naive]));
      expect(
        mint.mint().value,
        isNot(naive.value),
        reason: 'the SE row is a layer of this project — two rows, one id',
      );
    });

    test('an id the transition row holds is never minted onto', () {
      final naive = mintOver(repositoryHolding(const [])).mint();
      final mint = mintOver(holdingTrackRows(transitionId: naive));
      expect(mint.mint().value, isNot(naive.value));
    });
  });

  test('🚨usedIds REPLACES the scan, so a batch pays for it once', () {
    // No project at all: `requireProject` throws. The mint still answers,
    // which is the proof that the caller's set was used INSTEAD of a
    // walk — an import minting 200 ids must not walk the project 200
    // times.
    final mint = LayerIdMint(project: _ProjectOnly(ProjectRepository()));
    final first = mint.mint(usedIds: const <String>{}).value;

    final second = LayerIdMint(
      project: _ProjectOnly(ProjectRepository()),
    ).mint(usedIds: {first}).value;
    expect(
      second,
      isNot(first),
      reason: 'the handed-in set is honoured exactly as the scan would be',
    );
  });
}

/// A [ProjectAccess] that answers ONE question. Every other role member
/// throws rather than returning a null the mint would silently mint over.
class _ProjectOnly implements ProjectAccess {
  _ProjectOnly(this.repository);

  @override
  final ProjectRepository repository;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
