import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/ruler_marker.dart';
import 'package:anicel/src/models/timeline_id.dart';
import 'package:anicel/src/services/commands/update_ruler_markers_command.dart';
import 'package:anicel/src/services/editing/cut_duplicate_helpers.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-169-Q2 (유저 2026-11-13): 「애초에 컷(로컬)이랑 콘티(글로벌)이랑 마커
/// 독립적으로 하고싶음. 즉 로컬에서 보이는거랑 글로벌에서 보이는거랑 다름.
/// 따로따로 설정한단느낌. 뭐 움직인다고 동기화되서 같이움직이지도않음」.
void main() {
  RulerMarkers set(int start, String text) =>
      RulerMarkers.settled([RulerMarker(start: start, text: text)]);

  ({ProjectRepository repository, HistoryManager history, Project before})
  open() {
    final project = createDefaultProject();
    return (
      repository: ProjectRepository(initialProject: project),
      history: HistoryManager(),
      before: project,
    );
  }

  test('🚨a cut\'s markers and the timeline\'s are two sets: writing one '
      'leaves the other, and each undo puts its own back', () {
    final (:repository, :history, :before) = open();
    final cut = before.tracks.first.cuts.first;
    final ofCut = RulerMarkerHolder.cut(cut.id);
    const ofTimeline = RulerMarkerHolder.timeline();
    Project now() => repository.requireProject();

    history.execute(
      UpdateRulerMarkersCommand(
        repository: repository,
        holder: ofCut,
        markers: set(3, 'cut'),
      ),
    );
    expect(rulerMarkersOf(now(), ofCut), set(3, 'cut'));
    expect(rulerMarkersOf(now(), ofTimeline).isEmpty, isTrue);
    expect(
      now().tracks.first.cuts.first.metadata,
      cut.metadata.copyWith(rulerMarkers: set(3, 'cut')),
      reason: 'the markers alone — the rest of the cut\'s as it stood',
    );

    history.execute(
      UpdateRulerMarkersCommand(
        repository: repository,
        holder: ofTimeline,
        markers: set(40, 'movie'),
      ),
    );
    expect(rulerMarkersOf(now(), ofTimeline), set(40, 'movie'));
    expect(now().currentTimeline.rulerMarkers, set(40, 'movie'));
    expect(rulerMarkersOf(now(), ofCut), set(3, 'cut'));

    history.undo();
    expect(rulerMarkersOf(now(), ofTimeline).isEmpty, isTrue);
    expect(rulerMarkersOf(now(), ofCut), set(3, 'cut'));
    history.undo();
    expect(now(), before);
    history.redo();
    expect(rulerMarkersOf(now(), ofCut), set(3, 'cut'));
  });

  test('the timeline\'s are the OPEN timeline\'s — another keeps its own, '
      'and a copy of one carries them', () {
    final project = createDefaultProject();
    final other = ProjectTimeline(
      id: const TimelineId('other'),
      number: 2,
      tracks: const [],
      rulerMarkers: set(7, 'other'),
    );
    final repository = ProjectRepository(
      initialProject: project.copyWith(
        timelines: [...project.timelines, other],
      ),
    );
    UpdateRulerMarkersCommand(
      repository: repository,
      holder: const RulerMarkerHolder.timeline(),
      markers: set(40, 'movie'),
    ).execute();
    final timelines = repository.requireProject().timelines;
    expect(timelines.first.rulerMarkers, set(40, 'movie'));
    expect(timelines.last.rulerMarkers, set(7, 'other'));

    final copy = duplicateTimelineAsIndependentCopy(
      source: other,
      ids: TimelineCopyIds(
        timelineId: const TimelineId('copy'),
        tracks: const {},
        cuts: const {},
        rows: const {},
        cels: const {},
        links: const {},
      ),
      number: 3,
      name: null,
    );
    expect(copy.rulerMarkers, set(7, 'other'));
  });
}
