import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/playback_quality.dart';
import '../../services/persistence/anicel_project_archive.dart'
    show anicelObjectMapField;

/// Where the work stood when the project was saved — the cut, the row and
/// the frame in front of the person, and what their tools were holding —
/// so opening the project picks it up there (F-123).
///
/// 유저 2026-09-13: 「저장시 마지막으로 고른 툴 상태(무슨 브러시인지, 무슨
/// 지우개인지, 채우기툴에서 뭐 골라져있는지 등)와 액티브컷,액티브레이어,인덱스
/// 를 저장해서 열 때 반영되도록. 존재안하는게 있으면 해당 분야만 초기값으로」.
///
/// ⛔Kept BESIDE the project, never in it: moving the playhead or picking a
/// tool is not an edit, and a field in the project would mark the film
/// unsaved for it — the reason the media grants and fingerprints live beside
/// it too.
///
/// 🚨EVERY PART ANSWERS FOR ITSELF. A file from before this existed, a cut
/// deleted since, a value nobody can read — each part that cannot be read
/// comes back as "nothing saved here", and only that part falls back.
/// What reads the tools part of a [ProjectResume] at each save and puts it
/// back on open — installed on the door by the workspace, which holds the
/// tools and the preset library the door cannot reach (F-123).
typedef ToolChoiceBridge = ({
  Map<String, Object?> Function() read,
  void Function(Map<String, Object?> saved) resume,
});

class ProjectResume {
  const ProjectResume({
    this.cutId,
    this.layerId,
    this.frameIndex = 0,
    this.tools = const {},
    this.playbackQuality,
  });

  static const ProjectResume none = ProjectResume();

  final CutId? cutId;
  final LayerId? layerId;

  /// The playhead within [cutId], counted from its first frame.
  final int frameIndex;

  /// What the tools were holding, as the tool side wrote it — carried here,
  /// read there.
  final Map<String, Object?> tools;

  /// The resolution playback previewed at — a project setting kept here,
  /// beside the project and not in it (유저 답 playback-quality-undo-Q1
  /// 「언두 안 됨 — 보기 설정처럼(저장은 됨)」): picking one is no edit, so
  /// no undo step takes it back and nothing marks the film unsaved, and the
  /// file still keeps it. Null when the file says nothing.
  final PlaybackQuality? playbackQuality;

  Map<String, Object?> toJson() => {
    if (cutId != null) 'cutId': cutId!.value,
    if (layerId != null) 'layerId': layerId!.value,
    if (frameIndex > 0) 'frameIndex': frameIndex,
    if (tools.isNotEmpty) 'tools': tools,
    if (playbackQuality != null) 'playbackQuality': playbackQuality!.name,
  };

  /// The resume point [json] holds; any part it does not hold readably is
  /// left at its "nothing saved" value.
  static ProjectResume fromJson(Map<String, Object?> json) {
    final cutId = json['cutId'];
    final layerId = json['layerId'];
    final frameIndex = json['frameIndex'];
    return ProjectResume(
      cutId: cutId is String && cutId.isNotEmpty ? CutId(cutId) : null,
      layerId: layerId is String && layerId.isNotEmpty
          ? LayerId(layerId)
          : null,
      frameIndex: frameIndex is int && frameIndex > 0 ? frameIndex : 0,
      tools: anicelObjectMapField(json['tools']),
      playbackQuality: PlaybackQuality.values
          .where((quality) => quality.name == json['playbackQuality'])
          .firstOrNull,
    );
  }
}
