import '../../models/project.dart';
import '../../models/ruler_marker.dart';
import '../project_lookup.dart';
import 'mirrored_field_command.dart';

/// The markers on [holder]'s ruler in [project] (I-169).
RulerMarkers rulerMarkersOf(Project project, RulerMarkerHolder holder) =>
    switch (holder.cutId) {
      null => project.rulerMarkers,
      final cutId => requireCut(project, cutId).metadata.rulerMarkers,
    };

/// Writes the markers on ONE ruler — a cut's own or the open timeline's
/// ([RulerMarkerHolder]) — as one undo step: a marker made, edited, dragged
/// or deleted is the whole set written again, and the undo puts the set
/// back as it stood.
///
/// The holder's alone. A 겸용 sibling keeps its own markers, as it keeps
/// its own timing; nothing carries a cut's into the timeline's or back
/// (I-169-Q2: 「움직인다고 동기화되서 같이움직이지도않음」).
class UpdateRulerMarkersCommand
    extends MirroredFieldCommand<RulerMarkerHolder, RulerMarkers> {
  UpdateRulerMarkersCommand({
    required super.repository,
    required this.holder,
    required RulerMarkers markers,
  }) : super(value: markers);

  final RulerMarkerHolder holder;

  @override
  String get description => 'Set the markers on $holder';

  @override
  List<RulerMarkerHolder> membersOf(Project project) => [holder];

  @override
  RulerMarkers valueOf(Project project, RulerMarkerHolder member) =>
      rulerMarkersOf(project, member);

  // The markers alone, into the metadata the cut has NOW — an undo gives
  // them back and leaves the rest as it stands.
  @override
  void writeTo(RulerMarkerHolder member, RulerMarkers value) =>
      switch (member.cutId) {
        null => repository.updateTimelineRulerMarkers(value),
        final cutId => repository.updateCutMetadata(
          cutId: cutId,
          metadata: requireCut(
            repository.requireProject(),
            cutId,
          ).metadata.copyWith(rulerMarkers: value),
        ),
      };
}
