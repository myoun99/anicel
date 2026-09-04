import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/project.dart';

/// [project] with the cut at [cutId] holding [layers] instead of its own.
///
/// ⛔THE WALK IS THE WHOLE PROJECT, ON PURPOSE. A cut is addressed by id,
/// not by track — a caller that knew the track would have to keep knowing
/// it through every undo, and a linked cut's counterpart lives in another
/// one. Two link commands wrote this out identically, which is two places
/// to forget that a cut can be anywhere.
Project projectWithCutLayers(
  Project project,
  CutId cutId,
  List<Layer> layers,
) => project.copyWith(
  tracks: [
    for (final track in project.tracks)
      track.copyWith(
        cuts: [
          for (final cut in track.cuts)
            cut.id == cutId ? cut.copyWith(layers: layers) : cut,
        ],
      ),
  ],
);
