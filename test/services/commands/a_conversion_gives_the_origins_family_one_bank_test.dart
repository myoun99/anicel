import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// A cut converted to a 겸용 of a cut that has 겸용 already: every row of
/// the origin's family takes the joined bank at once, each keeping a cel it
/// held that the origin's list did not. ↩️The origin's row alone took it,
/// the rest left to gain the joiners on a later bank edit — and a group
/// parted before that copied the pictures each part's rows listed, so a
/// joiner's picture was gone from the part that had not gained it (F-555's
/// linked paste converts, 2026-11-04).
void main() {
  const track = TrackId('t');
  const origin = CutId('origin');
  const sibling = CutId('sibling');
  const target = CutId('target');

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), name: name, duration: 1, strokes: const []);

  Layer rowA(String id, List<Frame> frames) => Layer(
    id: LayerId(id),
    name: 'A',
    frames: frames,
    timeline: {
      for (final (index, drawn) in frames.indexed)
        index * 3: TimelineExposure.drawing(drawn.id, length: 3),
    },
  );

  Cut cut(CutId id, Layer row) => Cut(
    id: id,
    name: id.value,
    layers: [row],
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  final one = frame('f-o1', '1');
  final kept = frame('f-s9', '9');

  /// The origin and its sibling 겸용 on A — the sibling holding [extra]
  /// besides the origin's cels — and a target drawing 1 and 2.
  ProjectRepository family({List<Frame> extra = const []}) =>
      ProjectRepository(
        initialProject: Project(
          id: const ProjectId('p'),
          name: 'P',
          createdAt: DateTime.utc(2026, 11, 4),
          tracks: [
            Track(
              id: track,
              name: 'V',
              cuts: [
                cut(origin, rowA('a-origin', [one])),
                cut(sibling, rowA('a-sibling', [one, ...extra])),
                cut(
                  target,
                  rowA('a-target', [frame('f-t1', '1'), frame('f-t2', '2')]),
                ),
              ],
            ),
          ],
          linkRegistry: LayerLinkRegistry(
            groups: [
              LayerLinkGroup(
                id: 'link-a',
                members: const [
                  LayerLinkMember(
                    trackId: track,
                    cutId: origin,
                    layerId: LayerId('a-origin'),
                  ),
                  LayerLinkMember(
                    trackId: track,
                    cutId: sibling,
                    layerId: LayerId('a-sibling'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  List<String> bankOf(ProjectRepository repository, CutId id) => [
    for (final frame
        in repository
            .requireProject()
            .tracks
            .single
            .cuts
            .firstWhere((cut) => cut.id == id)
            .layers
            .single
            .frames)
      frame.id.value,
  ];

  void convert(ProjectRepository repository, HistoryManager history) =>
      CutCommandCoordinator(
        repository: repository,
        editingSession: EditingSessionState(activeCutId: origin),
        historyManager: history,
        brushFrameStore: BrushFrameStore()
          ..setLinkResolver(
            (key) =>
                repository.currentProject?.linkRegistry.canonicalCelKey(key) ??
                key,
          ),
      ).convertCutToLinked(originCutId: origin, targetCutId: target);

  test('🎯the origin\'s 겸용 sibling holds what the origin holds — the '
      'target\'s joiner too — and the undo takes it back', () {
    final repository = family();
    final history = HistoryManager();

    convert(repository, history);

    expect(bankOf(repository, origin), ['f-o1', 'f-t2']);
    expect(bankOf(repository, sibling), bankOf(repository, origin));
    expect(bankOf(repository, target), bankOf(repository, origin));

    history.undo();
    expect(bankOf(repository, sibling), ['f-o1']);
  });

  test('a cel a sibling held that the origin\'s list did not is kept', () {
    final repository = family(extra: [kept]);

    convert(repository, HistoryManager());

    expect(bankOf(repository, sibling), ['f-o1', 'f-t2', 'f-s9']);
  });
}
