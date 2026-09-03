import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';

class CutListEntry {
  const CutListEntry({
    required this.trackId,
    required this.trackName,
    required this.trackIndex,
    required this.trackType,
    required this.cutId,
    required this.cutName,
    required this.cutIndex,
    required this.isActive,
  });

  final TrackId trackId;
  final String trackName;
  final int trackIndex;
  final TrackType trackType;
  final CutId cutId;
  final String cutName;
  final int cutIndex;
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutListEntry &&
          other.trackId == trackId &&
          other.trackName == trackName &&
          other.trackIndex == trackIndex &&
          other.trackType == trackType &&
          other.cutId == cutId &&
          other.cutName == cutName &&
          other.cutIndex == cutIndex &&
          other.isActive == isActive;

  @override
  int get hashCode => Object.hash(
    trackId,
    trackName,
    trackIndex,
    trackType,
    cutId,
    cutName,
    cutIndex,
    isActive,
  );

  @override
  String toString() {
    return 'CutListEntry('
        'trackId: $trackId, '
        'trackName: $trackName, '
        'trackIndex: $trackIndex, '
        'trackType: $trackType, '
        'cutId: $cutId, '
        'cutName: $cutName, '
        'cutIndex: $cutIndex, '
        'isActive: $isActive)';
  }
}

List<CutListEntry> cutListEntriesFor(Project project, {CutId? activeCutId}) {
  final entries = <CutListEntry>[];

  for (final trackEntry in project.tracks.asMap().entries) {
    final trackIndex = trackEntry.key;
    final track = trackEntry.value;

    for (final cutEntry in track.cuts.asMap().entries) {
      final cutIndex = cutEntry.key;
      final cut = cutEntry.value;
      entries.add(
        CutListEntry(
          trackId: track.id,
          trackName: track.name,
          trackIndex: trackIndex,
          trackType: track.type,
          cutId: cut.id,
          cutName: cut.name,
          cutIndex: cutIndex,
          isActive: cut.id == activeCutId,
        ),
      );
    }
  }

  return entries;
}
