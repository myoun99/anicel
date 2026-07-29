import 'dart:convert';

import '../../models/camera_instruction.dart';
import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart';
import '../../models/track_se_window.dart';

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
  final duration = cut.duration < 1 ? 1 : cut.duration;
  final celLayers = [
    for (final layer in cut.layers)
      if (layer.kind == LayerKind.animation && layer.onTimesheet) layer,
  ];
  final seWindow = TrackSeWindow(
    cutStartFrame: cutStartFrame,
    cutDurationFrames: cut.duration,
  );
  final seLayers = [
    // Cut-owned SE layers remain for legacy fixtures (the print sheet
    // keeps the same pair of sources).
    for (final layer in cut.layers)
      if (layer.kind == LayerKind.se && layer.onTimesheet) layer,
    for (final layer in trackSeLayers)
      if (layer.onTimesheet)
        clipLayerStartsBefore(seWindow.displayLayer(layer), duration),
  ];
  final instructionLayers = [
    for (final layer in cut.layers)
      if (layer.kind == LayerKind.instruction) layer,
  ];

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

/// Value-change frames for a cel/SE layer: the sheet label at each drawing
/// start (Frame.name, 1-based position fallback — the timesheet's naming
/// rule) and SYMBOL_NULL_CELL where coverage ends or is missing.
List<Map<String, dynamic>> _drawingTrackFrames(Layer layer, int duration) {
  final labelsByFrameId = {
    for (var index = 0; index < layer.frames.length; index += 1)
      layer.frames[index].id: layer.frames[index].name ?? '${index + 1}',
  };

  final frames = <Map<String, dynamic>>[];
  var nextUncovered = 0;
  for (final block in drawingBlocks(layer.timeline)) {
    if (block.startIndex >= duration) {
      break;
    }
    if (block.startIndex > nextUncovered) {
      frames.add(_frameEntry(nextUncovered, xdtsNullCell));
    }
    frames.add(
      _frameEntry(block.startIndex, labelsByFrameId[block.frameId] ?? '?'),
    );
    nextUncovered = block.endIndexExclusive;
  }
  if (nextUncovered < duration || frames.isEmpty) {
    frames.add(_frameEntry(nextUncovered.clamp(0, duration - 1), xdtsNullCell));
  }
  return frames;
}

/// Value-change frames for an instruction row: the event's writing (free
/// text, vocabulary-name fallback; A→B appended when present) at each span
/// start, SYMBOL_NULL_CELL where a span ends into empty space.
List<Map<String, dynamic>> _instructionTrackFrames(
  Layer layer,
  int duration,
  CameraInstructionDef? Function(String instructionId)? defById,
) {
  final frames = <Map<String, dynamic>>[];
  var nextUncovered = 0;
  for (final entry in layer.instructions.entries) {
    final start = entry.key;
    if (start >= duration) {
      break;
    }
    final event = entry.value;
    if (start > nextUncovered) {
      frames.add(_frameEntry(nextUncovered, xdtsNullCell));
    }
    var value = event.displayLabel(defById?.call(event.instructionId));
    final valueA = event.valueA;
    final valueB = event.valueB;
    if (valueA != null || valueB != null) {
      value = '$value (${valueA ?? ''}→${valueB ?? ''})';
    }
    frames.add(_frameEntry(start, value));
    nextUncovered = start + event.length;
  }
  if (nextUncovered < duration || frames.isEmpty) {
    frames.add(_frameEntry(nextUncovered.clamp(0, duration - 1), xdtsNullCell));
  }
  return frames;
}
