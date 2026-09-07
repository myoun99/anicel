import 'dart:convert';

import '../../models/camera_instruction.dart';
import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../models/sheet_sources.dart';
import '../../models/timeline_coverage.dart';

/// Builds an XDTS (exchange digital time sheet, OpenToonz/Toei) document
/// for one cut, straight from the unified timeline model.
///
/// Format (from OpenToonz `xdtsio`): the file opens with the identifier
/// line, then JSON — `header{cut,scene}`, one timeTable with `duration`,
/// `timeTableHeaders` (layer names per field) and `fields`, where a field
/// is `fieldId` + `tracks` and a track writes only the frames whose value
/// CHANGES (readers hold values forward); an empty stretch starts with
/// `SYMBOL_NULL_CELL`. Field ids: CELL=0 (cels), DIALOG=3 (the SE/serifu
/// column), CAMERAWORK=5 (camera instructions).
const String xdtsFileIdentifier = 'exchangeDigitalTimeSheet Save Data';

const int xdtsFieldCell = 0;
const int xdtsFieldDialog = 3;
const int xdtsFieldCamerawork = 5;
const int xdtsVersion = 5;
const String xdtsNullCell = 'SYMBOL_NULL_CELL';

String buildXdtsContent({
  required Cut cut,
  /// The cut NUMBER as the sheet writes it — which is the cut's NAME, a
  /// free string the user owns ('39', '39A', '39B/40'). It used to be the
  /// cut's 1-based position, so reordering cuts silently renumbered every
  /// sheet that had already been exported.
  required String cutLabel,
  String scene = '1',
  CameraInstructionDef? Function(String instructionId)? instructionDefById,

  /// The owning track's SE lanes (GLOBAL frame axis) and this cut's start
  /// on that axis. SE rows are track-owned now, so a sheet built from
  /// [cut.layers] alone writes an empty DIALOG column — the sounds live
  /// one level up and reach the sheet the print timesheet's way: windowed
  /// to the cut, spill-in synthesized, starts past the cut end clipped.
  List<Layer> trackSeLayers = const [],
  int cutStartFrame = 0,
}) {
  // The SAME projection the print timesheet reads (the comment below the
  // parameter list has promised this all along).
  final sources = SheetSources.of(
    cut: cut,
    trackSeLayers: trackSeLayers,
    cutStartFrame: cutStartFrame,
  );
  final duration = sources.playbackFrameCount;
  final celLayers = sources.celLayers;
  final seLayers = [for (final slot in sources.seLayers) slot.layer];
  final instructionLayers = sources.instructionLayers;

  final timeTableHeaders = <Map<String, dynamic>>[
    if (celLayers.isNotEmpty)
      {
        'fieldId': xdtsFieldCell,
        'names': [for (final layer in celLayers) layer.name],
      },
    if (seLayers.isNotEmpty)
      {
        'fieldId': xdtsFieldDialog,
        'names': [for (final layer in seLayers) layer.name],
      },
    if (instructionLayers.isNotEmpty)
      {
        'fieldId': xdtsFieldCamerawork,
        'names': [for (final layer in instructionLayers) layer.name],
      },
  ];

  final fields = <Map<String, dynamic>>[
    if (celLayers.isNotEmpty)
      {
        'fieldId': xdtsFieldCell,
        'tracks': [
          for (var track = 0; track < celLayers.length; track += 1)
            {
              'trackNo': track,
              'frames': _drawingTrackFrames(celLayers[track], duration),
            },
        ],
      },
    if (seLayers.isNotEmpty)
      {
        'fieldId': xdtsFieldDialog,
        'tracks': [
          for (var track = 0; track < seLayers.length; track += 1)
            {
              'trackNo': track,
              'frames': _drawingTrackFrames(seLayers[track], duration),
            },
        ],
      },
    if (instructionLayers.isNotEmpty)
      {
        'fieldId': xdtsFieldCamerawork,
        'tracks': [
          for (var track = 0; track < instructionLayers.length; track += 1)
            {
              'trackNo': track,
              'frames': _instructionTrackFrames(
                instructionLayers[track],
                duration,
                instructionDefById,
              ),
            },
        ],
      },
  ];

  final json = <String, dynamic>{
    'header': {'cut': cutLabel, 'scene': scene},
    'timeTables': [
      {
        'duration': duration,
        'name': cut.name,
        'timeTableHeaders': timeTableHeaders,
        'fields': fields,
      },
    ],
    'version': xdtsVersion,
  };

  return '$xdtsFileIdentifier\n'
      '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

Map<String, dynamic> _frameEntry(int frame, String value) => {
  'frame': frame,
  'data': [
    {
      'id': 0,
      'values': [value],
    },
  ],
};

/// The XDTS change-only track rule, once: a track writes only the frames
/// whose value CHANGES (readers hold values forward), so each span in
/// [spans] emits its label at its start, a `SYMBOL_NULL_CELL` opens any gap
/// before it, spans starting at or past [duration] are dropped, and the
/// tail past the last span (or a track with no spans at all) closes with a
/// null cell clamped inside the sheet.
///
/// [spans] must arrive in start order and is walked LAZILY: the `break`
/// stops the producer as well, so a label nobody writes is never derived.
List<Map<String, dynamic>> _changeTrackFrames(
  Iterable<({int start, int endExclusive, String label})> spans,
  int duration,
) {
  final frames = <Map<String, dynamic>>[];
  var nextUncovered = 0;
  for (final span in spans) {
    if (span.start >= duration) {
      break;
    }
    if (span.start > nextUncovered) {
      frames.add(_frameEntry(nextUncovered, xdtsNullCell));
    }
    frames.add(_frameEntry(span.start, span.label));
    nextUncovered = span.endExclusive;
  }
  if (nextUncovered < duration || frames.isEmpty) {
    frames.add(_frameEntry(nextUncovered.clamp(0, duration - 1), xdtsNullCell));
  }
  return frames;
}

/// Value-change frames for a cel/SE layer: the sheet label at each drawing
/// start (Frame.name, 1-based position fallback — the timesheet's naming
/// rule) and SYMBOL_NULL_CELL where coverage ends or is missing.
List<Map<String, dynamic>> _drawingTrackFrames(Layer layer, int duration) {
  final labelsByFrameId = {
    for (var index = 0; index < layer.frames.length; index += 1)
      layer.frames[index].id: layer.frames[index].name ?? '${index + 1}',
  };

  return _changeTrackFrames(
    drawingBlocks(layer.timeline).map(
      (block) => (
        start: block.startIndex,
        endExclusive: block.endIndexExclusive,
        label: labelsByFrameId[block.frameId] ?? '?',
      ),
    ),
    duration,
  );
}

/// Value-change frames for an instruction row: the event's writing (free
/// text, vocabulary-name fallback; A→B appended when present) at each span
/// start, SYMBOL_NULL_CELL where a span ends into empty space.
List<Map<String, dynamic>> _instructionTrackFrames(
  Layer layer,
  int duration,
  CameraInstructionDef? Function(String instructionId)? defById,
) => _changeTrackFrames(
  layer.instructions.entries.map(
    (entry) => (
      start: entry.key,
      endExclusive: entry.key + entry.value.length,
      label: _instructionLabel(entry.value, defById),
    ),
  ),
  duration,
);

/// An instruction event's writing: free text, vocabulary-name fallback,
/// with `(A→B)` appended when either value is present.
String _instructionLabel(
  InstructionEvent event,
  CameraInstructionDef? Function(String instructionId)? defById,
) {
  final label = event.displayLabel(defById?.call(event.instructionId));
  final valueA = event.valueA;
  final valueB = event.valueB;
  if (valueA == null && valueB == null) {
    return label;
  }
  return '$label (${valueA ?? ''}→${valueB ?? ''})';
}
