import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_counts.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../../models/project.dart';
import '../../services/commands/link_mirror.dart';

export '../../models/envelope/cut_envelope_paper.dart'
    show CutEnvelopePaperMode, cutEnvelopePaperSize;

/// Builds the envelope's read-only description from the project — the
/// conte sheet builder's job, said of envelopes.
///
/// One envelope covers one CUT, and a 겸용 cut brings its siblings onto the
/// same sheet: the folder they share in the studio is one envelope, so the
/// form prints a CUT line per sibling (the WIT sheet has four). Cel rows
/// come from the ACTIVE cut — the siblings share its drawings by
/// definition, which is what makes them one envelope in the first place.
CutEnvelopeSource buildCutEnvelopeSource({
  required Project project,
  required Cut cut,
}) {
  final info = project.timesheetInfo;
  return CutEnvelopeSource(
    title: info.title.isEmpty ? project.name : info.title,
    episode: info.episode,
    // The timesheet's first page's memo — F-301-Q1 (유저 2026-10-08):
    // 「봉투와 「컷 메모」 창은 1쪽 메모」.
    note: cut.metadata.noteOf(0),
    cuts: [
      for (final line in _cutLines(project, cut))
        CutEnvelopeCutLine(
          name: line.name,
          durationFrames: line.duration,
          fps: project.fps,
        ),
    ],
    cels: cutEnvelopeCelCounts(cut),
    staff: cut.metadata.staff,
    logoAssetPath: info.logoAssetPath,
    canvasWidth: cut.canvasSize.width,
    canvasHeight: cut.canvasSize.height,
    cameraWidth: project.cameraSize.width,
    cameraHeight: project.cameraSize.height,
  );
}

/// The cut and its 겸용 siblings, in TRACK order.
///
/// Track order rather than "active first": the envelope is a document
/// about a set of cuts, and reading it should not depend on which one
/// happens to be open.
List<({String name, int duration})> _cutLines(Project project, Cut cut) {
  final lines = [
    for (final sibling in linkedCutGroupInTrackOrder(project, cutId: cut.id))
      (name: sibling.name, duration: sibling.duration),
  ];
  // A cut that somehow escaped the walk (an id with no cut) still prints
  // its own line rather than an empty envelope.
  if (lines.isEmpty) {
    lines.add((name: cut.name, duration: cut.duration));
  }
  return lines;
}

/// The cut whose id OWNS this envelope's ink.
///
/// A 겸용 envelope is one sheet for several cuts, so its annotations must
/// be one set too. The representative is the first sibling in track order
/// — the same order [buildCutEnvelopeSource] prints the CUT lines in, so
/// opening any sibling reaches the same sheet and the same handwriting.
CutId cutEnvelopeInkOwner(Project project, CutId cutId) =>
    linkedCutGroupInTrackOrder(project, cutId: cutId).firstOrNull?.id ?? cutId;
