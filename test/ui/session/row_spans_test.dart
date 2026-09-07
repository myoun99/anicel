import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// WHAT A ROW SPANS — the four reads every snap, gate and D40 verb asks of
/// a row before it selects anything: the folder band's aggregate runs, the
/// track row's authored span, the cut row's whole span, and the snap lane
/// each row kind offers.
///
/// They answered from the session itself until round 8's G3 cut, and
/// nothing named them directly — every pin was three layers up, through a
/// drag. These are the characterisation tests written BEFORE the move, so
/// the move has something to be judged against.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  test('R9 #1: a FOLDER row aggregates its members exposures; a row that '
      'owns its own blocks aggregates nothing', () {
    final s = session();
    s.createDrawingAtCurrentFrame();
    final memberId = s.activeLayer!.id;
    s.folders.groupActiveLayerIntoFolder();
    final folder = s.layers.firstWhere(
      (layer) => layer.kind == LayerKind.folder,
    );

    expect(
      s.rowSpans.aggregateRunsForRow(folder),
      isNotEmpty,
      reason: 'the band draws its members runs, so the snap reads them',
    );
    expect(
      s.rowSpans.aggregateRunsForRow(s.layers.firstWhere((l) => l.id == memberId)),
      isEmpty,
      reason: 'const [] for every row that owns its own blocks',
    );
  });

  test('a SINGLE-CEL (image) row is named as one; a drawing row is not', () {
    final s = session();
    s.layerStack.addLayerOfKind(LayerKind.image);
    final image = s.layers.firstWhere((layer) => layer.kind == LayerKind.image);
    final drawing = s.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );

    expect(s.rowSpans.isSingleCelLayerId(image.id), isTrue);
    expect(s.rowSpans.isSingleCelLayerId(drawing.id), isFalse);
  });

  test('D40: the cut row spans the first cut start through the last cut end',
      () {
    final s = session();
    final span = s.rowSpans.trackCutSpan(s.selectedTrackId);

    expect(span, isNotNull);
    expect(span!.startFrame, 0);
    expect(span.endFrameExclusive, s.requireActiveCut.duration);

    s.createCut();
    expect(
      s.rowSpans.trackCutSpan(s.selectedTrackId)!.endFrameExclusive,
      greaterThan(span.endFrameExclusive),
      reason: 'a second cut lengthens the span; the start is still the first',
    );
  });

  test('D40: an EMPTY track row has no authored span, and a cut-owned row '
      'is no track row at all', () {
    final s = session();
    final emptySe = s.activeTrack.seLayers.first;

    expect(s.rowSpans.trackRowAuthoredSpan(emptySe.id), isNull);
    expect(s.rowSpans.trackRowAuthoredSpan(s.activeLayerId!), isNull);
  });

  test('the snap lane a row offers: the cut row snaps to cut blocks, and a '
      'LANE row to nothing — lane keys are POINTS, not blocks', () {
    final s = session();
    final axis = s.trackFrameAxis();

    expect(
      s.rowSpans.trackRowSnapLane(TrackRowAddress(s.selectedTrackId), axis),
      isNotNull,
    );
    expect(
      s.rowSpans.trackRowSnapLane(LaneRowAddress(s.activeLayerId!, 'position'), axis),
      isNull,
    );
  });

  test('D40: the standing row selects its WHOLE authored span, and the gate '
      'answers true exactly where that would select something', () {
    final s = session();
    s.createDrawingAtCurrentFrame();
    final rowId = s.activeLayerId!;

    expect(s.rangeSelections.canSelectRowSpanForCurrentRow, isTrue);
    s.rangeSelections.selectRowSpanForCurrentRow();

    final selection = s.frameRangeSelection.value;
    expect(selection, isNotNull);
    expect(selection!.layerId, rowId);
    expect(selection.startIndex, 0);
    expect(selection.lengthFrames, greaterThan(0));
  });
}
