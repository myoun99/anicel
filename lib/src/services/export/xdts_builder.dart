import 'dart:convert';

import '../../models/camera_instruction.dart';
import '../../models/cut.dart';
import '../../models/frame.dart';
import '../../models/layer.dart';
import '../../models/sheet_sources.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timesheet_document.dart';
import '../../models/transition_geometry.dart';
import '../../models/xdts_sheet_half.dart';
import '../../models/xdts_viewer_notation.dart';

/// Builds an XDTS (exchange digital time sheet, OpenToonz/Toei) document
/// for one cut, straight from the unified timeline model.
///
/// Format (from OpenToonz `xdtsio`): the file opens with the identifier
/// line, then JSON — `header{cut,scene}`, one timeTable with `duration`,
/// `timeTableHeaders` (layer names per field) and `fields`, where a field
/// is `fieldId` + `tracks` and a track writes a value where one is written
/// — a cel track what the XDTS sheet reads off its column, held on
/// ([_cellTrackFrames]); a dialog's and a camerawork's at their first frame,
/// lasting in `SYMBOL_HYPHEN` ([_trackFrames]); an empty stretch starts with
/// `SYMBOL_NULL_CELL`. Field ids: CELL=0 (cels), DIALOG=3 (the SE/serifu
/// column), CAMERAWORK=5 (camera instructions).
const String xdtsFileIdentifier = 'exchangeDigitalTimeSheet Save Data';

const int xdtsFieldCell = 0;
const int xdtsFieldDialog = 3;
const int xdtsFieldCamerawork = 5;
const int xdtsVersion = 5;
const String xdtsNullCell = 'SYMBOL_NULL_CELL';
const String xdtsHyphen = 'SYMBOL_HYPHEN';
const String xdtsTick1 = 'SYMBOL_TICK_1';
const String xdtsTick2 = 'SYMBOL_TICK_2';

String buildXdtsContent({
  required Cut cut,

  /// Which of the cut's two files ([XdtsSheetHalf]).
  required XdtsSheetHalf half,
  /// The cut NUMBER as the sheet writes it — which is the cut's NAME, a
  /// free string the user owns ('39', '39A', '39B/40'). It used to be the
  /// cut's 1-based position, so reordering cuts silently renumbered every
  /// sheet that had already been exported.
  required String cutLabel,

  /// The mark a drawing with no cel number wears — the pick its host heard
  /// (`AppFrameGridSettings.unnamedMark`), as the printed sheet is handed it.
  required InbetweenMark unnamedMark,
  CameraInstructionDef? Function(String instructionId)? instructionDefById,

  /// The owning track's SE lanes (GLOBAL frame axis) and this cut's start
  /// on that axis. SE rows are track-owned now, so a sheet built from
  /// [cut.layers] alone writes an empty DIALOG column — the sounds live
  /// one level up and reach the sheet the print timesheet's way: windowed
  /// to the cut, spill-in synthesized, starts past the cut end clipped.
  List<Layer> trackSeLayers = const [],
  int cutStartFrame = 0,

  /// The track's transition spans (GLOBAL axis): the のりしろ an O.L
  /// arriving into the cut asks puts its own frame 0 — the cel tracks'
  /// first — that much before [cutStartFrame], and the DIALOG tracks count
  /// from there too (I-73-ol-sheet-columns).
  List<TransitionSpan> transitionSpans = const [],
}) {
  // The SAME projection the print timesheet reads (the comment below the
  // parameter list has promised this all along).
  final sources = SheetSources.of(
    cut: cut,
    trackSeLayers: trackSeLayers,
    cutStartFrame: cutStartFrame,
    transitionSpans: transitionSpans,
  );
  // The rows the printed sheet DRAWS: its conte 尺 and the のりしろ an O.L
  // asks of either side (I-73-ol-xdts-duration — 저장 2026-10-20, by the
  // sheet's 「컷 엔드라인(OL여백이든 뭐든 총합적인 엔드라인)」). The XDTS
  // has no column to say O.L in, so it is handed every row drawn rather
  // than lose what is on the のりしろ. ↩️It ran the conte 尺, and a cut an
  // O.L arrives into — its own frame 0 that much before its conte — lost
  // its last のりしろ rows, the pictures and the sounds on them.
  final duration = sources.drawnFrameCount;
  final celLayers = xdtsCelLayersOf(half, sources);
  final seLayers = [for (final slot in sources.seLayers) slot.layer];
  final instructionLayers = sources.instructionLayers;

  // 🚨THE CEL FIELD IS WRITTEN WITH NO ROW TO HOLD as well (I-161 ④,
  // 서피스 검증 2026-11-07): XDTS Viewer v1.3.0 finds it by its id and has
  // no sheet without it — a 動画 file of a cut with no CELL rows closed the
  // viewer as it opened, and so did its 原画 file, which opens its pair
  // (`getCellField` indexes `m_fields[-1]`, xdts_viewer mywindow.cpp). An
  // empty one draws the sheet's length with nothing in it. ↩️A field with
  // no row was left out (07-08), when one file held every row.
  final timeTableHeaders = <Map<String, dynamic>>[
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
    {
      'fieldId': xdtsFieldCell,
      'tracks': [
        for (var track = 0; track < celLayers.length; track += 1)
          {
            'trackNo': track,
            'frames': _cellTrackFrames(
              celLayers[track],
              duration: duration,
              playbackFrameCount: sources.playbackFrameCount,
              unnamedMark: unnamedMark,
            ),
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
              'frames': _dialogTrackFrames(
                seLayers[track],
                duration,
                unnamedMark,
              ),
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
    // The cut's scene, as its timesheet prints it — 🗣️F-291-Q7 (유저
    // 2026-10-28): 「컷의 신을 쓴다」, empty where none is written.
    // ↩️It was always '1', a default nobody asked for (07-08).
    'header': {'cut': cutLabel, 'scene': cut.metadata.scene},
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

/// The rows of [sources] [half]'s cel field holds: the ACTION block's for
/// the 原画 file, the CELL block's for the 動画 file.
List<Layer> xdtsCelLayersOf(XdtsSheetHalf half, SheetSources sources) =>
    switch (half) {
      XdtsSheetHalf.genga => sources.actionLayers,
      XdtsSheetHalf.douga => sources.cellLayers,
    };

Map<String, dynamic> _frameEntry(int frame, List<String> values) => {
  'frame': frame,
  'data': [
    {'id': 0, 'values': values},
  ],
};

/// One instruction a track writes: where it starts, where it ends, and the
/// values its first frame carries.
typedef _Span = ({int start, int endExclusive, List<String> values});

/// The track rule of the dialog and camerawork fields: each span in [spans]
/// writes its values at its start and `SYMBOL_HYPHEN` on every frame after
/// it, to its end inside the sheet; a `SYMBOL_NULL_CELL` opens any gap
/// before it, spans starting at or past [duration] are dropped, and the
/// tail past the last span (or a track with no spans at all) closes with a
/// null cell clamped inside the sheet.
///
/// 🗣️I-161-Q3 (유저 2026-11-05): 「일단 데이터로서 내보낼수있는건 다
/// 내보내고싶음」 — so the dialog and camerawork fields take the shape
/// `xdtsio`'s spec gives them: 「When the line lasts for multiple frames,
/// specify the character string "SYMBOL_HYPHEN" up to the end frame」.
/// ↩️Their value was written at the start alone. What closes them the spec
/// does not say; a null cell does, as it does a cel's, so a reader that
/// holds values forward stops where the sheet does.
///
/// [spans] must arrive in start order and is walked LAZILY: the `break`
/// stops the producer as well, so a label nobody writes is never derived.
List<Map<String, dynamic>> _trackFrames(
  Iterable<_Span> spans,
  int duration,
) {
  final frames = <Map<String, dynamic>>[];
  var nextUncovered = 0;
  for (final span in spans) {
    if (span.start >= duration) {
      break;
    }
    if (span.start > nextUncovered) {
      frames.add(_frameEntry(nextUncovered, const [xdtsNullCell]));
    }
    frames.add(_frameEntry(span.start, span.values));
    final end = span.endExclusive < duration ? span.endExclusive : duration;
    for (var frame = span.start + 1; frame < end; frame += 1) {
      frames.add(_frameEntry(frame, const [xdtsHyphen]));
    }
    nextUncovered = span.endExclusive;
  }
  if (nextUncovered < duration || frames.isEmpty) {
    frames.add(
      _frameEntry(nextUncovered.clamp(0, duration - 1), const [xdtsNullCell]),
    );
  }
  return frames;
}

/// A cel layer's track: the values the XDTS Viewer reads off its column,
/// each on the frame it is written on — a drawing's number or mark where it
/// starts, a breakdown mark where its block wears one, the null cell where
/// a run of nothing starts — held on between them (readers hold values
/// forward).
///
/// ⛔Read by the function the XDTS sheet draws the column by
/// ([xdtsViewerFramesOf]), off the cells it draws ([timesheetLayerCells],
/// the DATA cells the sheet's blocks print on an XDTS sheet —
/// `TimesheetDocument.fromCut`), so the file is what the sheet shows (유저
/// I-162 메모: 「보이는그대로 출력이 목표」). ↩️The file walked the drawing
/// blocks on its own and wrote each one's head alone: the breakdown marks
/// the sheet draws inside a block never reached it — a viewer drew the
/// block's line on through them (타임라인/콘티, I-162 2026-11-05) — and a
/// held cel's ghosts wrote its number again, one cel read as two (R26 #26).
List<Map<String, dynamic>> _cellTrackFrames(
  Layer layer, {
  required int duration,
  required int playbackFrameCount,
  required InbetweenMark unnamedMark,
}) {
  final frames = xdtsViewerFramesOf(
    timesheetLayerCells(
      layer: layer,
      rowCount: duration,
      playbackFrameCount: playbackFrameCount,
      unnamedMark: unnamedMark,
      dataSheet: true,
    ),
    duration: duration,
  );
  return [
    for (var frame = 0; frame < frames.length; frame += 1)
      if (frames[frame] case final value?)
        _frameEntry(frame, [_xdtsValue(value)]),
  ];
}

/// An SE layer's dialog track: each block's speaker — the name its accent
/// box shows ([Frame.seName]), empty where it has none — and its line
/// ([_drawingSpans]), the two values `xdtsio`'s spec gives a dialog's first
/// frame (「enter the speaker name in the first element, and the dialog's
/// string in the second element」).
List<Map<String, dynamic>> _dialogTrackFrames(
  Layer layer,
  int duration,
  InbetweenMark unnamedMark,
) => _trackFrames(
  _drawingSpans(
    layer,
    unnamedMark,
    (frame, head) => [frame.seName ?? '', head],
  ),
  duration,
);

/// An SE layer's drawing blocks as spans: each drawing's head where its
/// block starts — what the printed sheet writes there ([drawingHeadOf]), as
/// an XDTS value ([_xdtsHead]) — laid into the field's values by
/// [valuesOf]; `?` for a drawing the layer does not hold.
///
/// ↩️It wrote `name ?? '${index + 1}'` (I-161, 2026-11-05): a number the
/// sheet never prints (R5-④ 「never an invented number」), a name of spaces
/// as spaces, a written name as its hidden text — the one head the sheet
/// and the cel export already asked here, spelled again.
Iterable<_Span> _drawingSpans(
  Layer layer,
  InbetweenMark unnamedMark,
  List<String> Function(Frame frame, String head) valuesOf,
) {
  final framesById = {for (final frame in layer.frames) frame.id: frame};
  return drawingBlocks(layer.timeline).map((block) {
    final frame = framesById[block.frameId];
    return (
      start: block.startIndex,
      endExclusive: block.endIndexExclusive,
      values: frame == null
          ? const ['?']
          : valuesOf(
              frame,
              _xdtsHead(
                drawingHeadOf(
                  frame.name,
                  kind: layer.kind,
                  unnamedMark: unnamedMark,
                ),
              ),
            ),
    );
  });
}

/// A drawing's [head] as an XDTS cell value ([_xdtsValue]).
String _xdtsHead(DrawingHead head) => _xdtsValue(head.mark ?? head.word);

/// A value the viewer reads ([xdtsViewerFramesOf]) as an XDTS cell value:
/// a cel number as it is, the null cell as `SYMBOL_NULL_CELL`, and a mark
/// as the tick the format has for it. Mark 1 (○) is SYMBOL_TICK_1 and mark
/// 2 (●) SYMBOL_TICK_2 — the order `xdtsio`'s spec names them in (中割り記号
/// ○, 逆シート記号 ●) and the one the user checked against Toei's digital
/// sheet and Clip Studio (I-130, 2026-10-25). The XDTS viewer draws
/// TICK_1 as a small dot, not a ○; the file still writes each mark by its
/// shape — 🗣️I-161-Q9 (유저 2026-11-05): 「모양대로」 — and our sheet keeps
/// its own ○ ● (I-161-Q6).
String _xdtsValue(Object value) => switch (value) {
  final String number => number,
  InbetweenMark.one => xdtsTick1,
  InbetweenMark.two => xdtsTick2,
  _ => xdtsNullCell,
};

/// An instruction row's camerawork track: the event's writing (free text,
/// vocabulary-name fallback; A→B appended when present) at each span's
/// start, lasting on in hyphens, SYMBOL_NULL_CELL where a span ends into
/// empty space — and where a span that writes nothing stands, the empty
/// cell it shows (「(없음)」).
List<Map<String, dynamic>> _instructionTrackFrames(
  Layer layer,
  int duration,
  CameraInstructionDef? Function(String instructionId)? defById,
) => _trackFrames(
  layer.instructions.entries
      .map(
        (entry) => (
          start: entry.key,
          endExclusive: entry.key + entry.value.length,
          values: [_instructionLabel(entry.value, defById)],
        ),
      )
      .where((span) => span.values.single.isNotEmpty),
  duration,
);

/// An instruction event's writing: free text, vocabulary-name fallback,
/// with `(A→B)` appended when either value is present.
String _instructionLabel(
  InstructionEvent event,
  CameraInstructionDef? Function(String instructionId)? defById,
) {
  final label = event.displayLabel(event.defIn(defById));
  final valueA = event.valueA;
  final valueB = event.valueB;
  if (valueA == null && valueB == null) {
    return label;
  }
  final ends = '(${valueA ?? ''}→${valueB ?? ''})';
  return label.isEmpty ? ends : '$label $ends';
}
