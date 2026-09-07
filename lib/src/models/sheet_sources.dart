import 'cut.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'track_se_window.dart';

/// The rows one cut hands a SHEET, and how long the sheet runs.
///
/// The printed timesheet and the XDTS export are two renderings of ONE
/// projection, and both already carried comments promising as much. They
/// derived it separately until this class existed, which is how the
/// instruction row's sheet toggle came to be honoured on paper and ignored
/// in the export.
class SheetSources {
  SheetSources._({
    required this.playbackFrameCount,
    required this.celLayers,
    required this.seLayers,
    required this.instructionLayers,
  });

  factory SheetSources.of({
    required Cut cut,
    List<Layer> trackSeLayers = const [],
    int cutStartFrame = 0,
  }) {
    final playbackFrameCount = cut.duration < 1 ? 1 : cut.duration;
    // SE rows are track-owned: window their global timelines to this cut
    // (spill-in synthesizes a display block). Cut-owned SE layers remain
    // for legacy fixtures.
    final seWindow = TrackSeWindow(
      cutStartFrame: cutStartFrame,
      cutDurationFrames: cut.duration,
    );
    return SheetSources._(
      playbackFrameCount: playbackFrameCount,
      // ACTION-block cel columns: ONE gate shared with the envelope and
      // the XDTS export ([layerTakesSheetCelColumn], D24) — image rows
      // answer false, a nameless held picture prints nothing.
      celLayers: [
        for (final layer in cut.layers)
          if (layerTakesSheetCelColumn(layer)) layer,
      ],
      seLayers: [
        for (final layer in cut.layers)
          if (layer.kind == LayerKind.se && layer.onTimesheet)
            (layer: layer, crosses: crossesCutEnd(layer, playbackFrameCount),
             spills: false),
        for (final layer in trackSeLayers)
          if (layer.onTimesheet)
            () {
              // The display window is open-ended on the right now (SE
              // globalization — the timeline's runway shows the
              // neighbours' sounds), but a printed page is no runway:
              // entries starting at or past the cut end stay off the
              // sheet, crossing blocks keep their true length and the
              // sheet marks them with the timeline's `~`. One clip for
              // every cut-scoped export ([clipLayerStartsBefore] — the
              // XDTS sheet reads the same projection).
              final clone = clipLayerStartsBefore(
                seWindow.displayLayer(layer),
                playbackFrameCount,
              );
              return (
                layer: clone,
                crosses: crossesCutEnd(clone, playbackFrameCount),
                spills: seWindow.spillInBlock(layer) != null,
              );
            }(),
      ],
      instructionLayers: [
        for (final layer in cut.layers)
          if (layer.kind == LayerKind.instruction && layer.onTimesheet) layer,
      ],
    );
  }

  /// The cut's length in rows the sheet must show, never less than 1.
  final int playbackFrameCount;

  /// The rows that take an ACTION-block cel column.
  final List<Layer> celLayers;

  /// The SE rows, already windowed and clipped to this cut, each with the
  /// two facts the printed sheet marks: whether the row's block runs past
  /// the cut end, and whether it spilled in from an earlier cut.
  final List<({Layer layer, bool crosses, bool spills})> seLayers;

  /// The instruction rows the sheet prints.
  final List<Layer> instructionLayers;
}

/// Whether any authored block of [clone] starts inside the cut and runs
/// past [playbackFrameCount] — the `~` the sheet marks a crossing with.
bool crossesCutEnd(Layer clone, int playbackFrameCount) {
  for (final entry in clone.timeline.entries) {
    if (entry.value.isDrawing &&
        !entry.value.ghost &&
        entry.key < playbackFrameCount &&
        entry.key + (entry.value.length ?? 1) > playbackFrameCount) {
      return true;
    }
  }
  return false;
}
