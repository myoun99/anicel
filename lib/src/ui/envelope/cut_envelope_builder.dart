import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_counts.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../../models/project.dart';
import '../../services/commands/link_mirror.dart';

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
    note: cut.metadata.note,
    cuts: [
      for (final line in _cutLines(project, cut))
        CutEnvelopeCutLine(
          name: line.name,
          durationFrames: line.duration,
          fps: project.fps,
        ),
    ],
    cels: cutEnvelopeCelCounts(cut),
    staff: info.staff,
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
  final siblings = <CutId>{
    cut.id,
    ...linkedCutSiblings(project, cutId: cut.id),
  };
  final lines = <({String name, int duration})>[];
  for (final track in project.tracks) {
    for (final candidate in track.cuts) {
      if (siblings.contains(candidate.id)) {
        lines.add((name: candidate.name, duration: candidate.duration));
      }
    }
  }
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
CutId cutEnvelopeInkOwner(Project project, CutId cutId) {
  final siblings = <CutId>{cutId, ...linkedCutSiblings(project, cutId: cutId)};
  if (siblings.length == 1) {
    return cutId;
  }
  for (final track in project.tracks) {
    for (final candidate in track.cuts) {
      if (siblings.contains(candidate.id)) {
        return candidate.id;
      }
    }
  }
  return cutId;
}

/// The envelope for a cut id, or null when the cut is gone.
CutEnvelopeSource? buildCutEnvelopeSourceById(Project project, CutId cutId) {
  for (final track in project.tracks) {
    for (final cut in track.cuts) {
      if (cut.id == cutId) {
        return buildCutEnvelopeSource(project: project, cut: cut);
      }
    }
  }
  return null;
}

/// The paper an envelope prints on.
enum CutEnvelopePaperMode {
  /// The real 봉투: the form's own size at the export resolution.
  sheet,

  /// The cut's canvas, so the exported image drops into a working file as
  /// a layer and lines up with the artwork.
  cut;

  String toJson() => name;

  static CutEnvelopePaperMode fromJson(Object? json) =>
      values.asNameMap()[json] ?? CutEnvelopePaperMode.sheet;
}

/// The paper size for [mode], in pixels.
///
/// [sheetWidth] is what the real-envelope mode prints at; the cut mode
/// takes the canvas verbatim so the result is drop-in.
({int width, int height}) cutEnvelopePaperSize({
  required CutEnvelopePaperMode mode,
  required Cut cut,
  required double formAspectRatio,
  int sheetWidth = 2480,
}) {
  switch (mode) {
    case CutEnvelopePaperMode.sheet:
      final width = sheetWidth < 1 ? 1 : sheetWidth;
      return (width: width, height: (width / formAspectRatio).round());
    case CutEnvelopePaperMode.cut:
      return (width: cut.canvasSize.width, height: cut.canvasSize.height);
  }
}
