import '../core/collection_equality.dart';
import 'timeline_row_address.dart';
import 'track_id.dart';

/// A selected frame RANGE on a TRACK's GLOBAL frame axis — the storyboard's
/// rows: the cut row, whose blocks are cuts, and the track-owned SE rows,
/// whose sounds cross cut boundaries freely.
///
/// It is the same object [TimelineFrameRangeSelection] is, stated in the
/// other axis. The two exist because a CUT owns its own axis: the timeline
/// shows one cut at a time and its selection dies with the cut switch,
/// while a track row spans the whole movie and a cut-local index cannot
/// name a frame BEFORE the active cut — the local axis has no negatives,
/// so an earlier cut's sound has no local address (the display window is
/// open-ended on the right now, but the left wall stands).
///
/// The two are mutually exclusive on screen: starting one clears the other,
/// so there is never a question of which axis the highlight is in.
///
/// View state — never persisted.
class TrackFrameRangeSelection {
  const TrackFrameRangeSelection({
    required this.trackId,
    required this.anchorRow,
    required this.startFrame,
    required this.endFrameExclusive,
    this.rows = const [],
  }) : assert(endFrameExclusive > startFrame, 'Range must cover frames.');

  /// The track whose global axis these frames are stated in.
  final TrackId trackId;

  /// The row the drag STARTED on — single-row flows read this alone.
  final TimelineRowAddress anchorRow;

  /// The rows the selection covers, anchor to head. Empty = the anchor
  /// alone.
  final List<TimelineRowAddress> rows;

  final int startFrame;
  final int endFrameExclusive;

  /// The rows this selection covers, anchor-only selections included.
  List<TimelineRowAddress> get spanRows => rows.isEmpty ? [anchorRow] : rows;

  bool coversRow(TimelineRowAddress row) =>
      rows.isEmpty ? row == anchorRow : rows.contains(row);

  int get lengthFrames => endFrameExclusive - startFrame;

  bool contains(int globalFrame) =>
      globalFrame >= startFrame && globalFrame < endFrameExclusive;

  /// Whether the selection touches the half-open span [start, end).
  bool overlaps(int start, int endExclusive) =>
      start < endFrameExclusive && endExclusive > startFrame;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackFrameRangeSelection &&
          other.trackId == trackId &&
          other.anchorRow == anchorRow &&
          other.startFrame == startFrame &&
          other.endFrameExclusive == endFrameExclusive &&
          listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(
    trackId,
    anchorRow,
    startFrame,
    endFrameExclusive,
    Object.hashAll(rows),
  );

  @override
  String toString() =>
      'TrackFrameRangeSelection($trackId, $anchorRow, '
      '[$startFrame, $endFrameExclusive), rows: $spanRows)';
}
