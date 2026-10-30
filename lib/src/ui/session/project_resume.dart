import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/playback_mode.dart';
import '../../services/persistence/anicel_project_archive.dart'
    show anicelObjectMapField;
import '../timeline/lane_graph.dart'
    show LaneGraph, LaneGraphMode, LaneGraphsView;
import 'media_file_views.dart' show MediaFileView;

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
    this.playbackMode,
    this.timelineZoom = const {},
    this.storyboardZoom,
    this.frameAxisOffsets = const {},
    this.layerAxisOffsets = const {},
    this.showSeconds = false,
    this.laneGraphs = LaneGraphsView.none,
    this.mediaFileViews = const {},
  });

  static const ProjectResume none = ProjectResume();

  final CutId? cutId;
  final LayerId? layerId;

  /// The playhead within [cutId], counted from its first frame.
  final int frameIndex;

  /// What the tools were holding, as the tool side wrote it — carried here,
  /// read there.
  final Map<String, Object?> tools;

  /// What a run does at a frame whose picture is not made yet — a project
  /// setting kept here, beside the project and not in it, as the playback
  /// quality whose seat it took was (유저 답 playback-quality-undo-Q1
  /// 「언두 안 됨 — 보기 설정처럼(저장은 됨)」): picking one is no edit, so no
  /// undo step takes it back and nothing marks the film unsaved, and the
  /// file still keeps it. Null when the file says nothing.
  final PlaybackMode? playbackMode;

  /// The timeline zoom each cut was left at (F-253 → F-267, 유저 2026-10-01:
  /// 「프로젝트와 같이 저장되도록」) — a cut nobody zoomed is not here.
  final Map<CutId, double> timelineZoom;

  /// The conte's zoom (F-267) — null when it was left at its default.
  final double? storyboardZoom;

  /// How far each frame panel was scrolled along its frames, by rail, in
  /// pixels at that panel's zoom (F-267) — a rail left at its start is not
  /// here.
  final Map<String, double> frameAxisOffsets;

  /// How far each frame panel was scrolled along its layers — the
  /// timeline's rows, the sheet's columns, the conte's rows — by rail, in
  /// pixels (F-267); a rail left at its start is not here.
  final Map<String, double> layerAxisOffsets;

  /// Whether the frame panels write a frame as seconds+frames (초+코마 표시,
  /// F-354 — `PanelViewMemory.showSeconds`): a view setting kept here as the
  /// zooms are. Turning it is no edit, and the file still keeps it; a file
  /// that says nothing writes frames.
  final bool showSeconds;

  /// The header graphs standing open — how tall, plotting what, enlarged or
  /// not, their pen up or not, their transform box shown or not, their snap
  /// on or not — and the lanes pinned to them (I-89 ③): a
  /// view setting kept here as the zooms are (유저 답 F-360-Q1 「보기 설정처럼
  /// — 저장은 되고 언두는 안 됨」). Turning one is no edit, so no undo step
  /// takes it back and nothing marks the film unsaved, and the file still
  /// keeps it.
  final LaneGraphsView laneGraphs;

  /// The page and the framing each file was left at in the viewers, by the
  /// file's path (F-382, `MediaFileViews`) — a view kept here as the zooms
  /// are: looking at a reference is no edit, and the file still keeps it. A
  /// file nobody turned or framed is not here.
  final Map<String, MediaFileView> mediaFileViews;

  Map<String, Object?> toJson() => {
    if (cutId != null) 'cutId': cutId!.value,
    if (layerId != null) 'layerId': layerId!.value,
    if (frameIndex > 0) 'frameIndex': frameIndex,
    if (tools.isNotEmpty) 'tools': tools,
    if (playbackMode != null) 'playbackMode': playbackMode!.name,
    if (timelineZoom.isNotEmpty)
      'timelineZoom': {
        for (final entry in timelineZoom.entries) entry.key.value: entry.value,
      },
    if (storyboardZoom != null) 'storyboardZoom': storyboardZoom,
    if (frameAxisOffsets.isNotEmpty) 'frameAxisOffsets': frameAxisOffsets,
    if (layerAxisOffsets.isNotEmpty) 'layerAxisOffsets': layerAxisOffsets,
    if (showSeconds) 'showSeconds': true,
    if (laneGraphs.open.isNotEmpty)
      'laneGraphs': {
        for (final MapEntry(:key, value: graph) in laneGraphs.open.entries)
          key: {
            if (graph.extent != null) 'extent': graph.extent,
            if (graph.mode != LaneGraphMode.value) 'mode': graph.mode.name,
            if (graph.enlarged) 'enlarged': true,
            if (graph.pen) 'pen': true,
            if (!graph.transformBox) 'transformBox': false,
            if (graph.snap) 'snap': true,
          },
      },
    if (laneGraphs.pinned.isNotEmpty) 'pinnedLanes': [...laneGraphs.pinned],
    if (mediaFileViews.isNotEmpty)
      'mediaFileViews': {
        for (final MapEntry(key: path, value: view) in mediaFileViews.entries)
          path: view.toJson(),
      },
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
      playbackMode: PlaybackMode.values
          .where((mode) => mode.name == json['playbackMode'])
          .firstOrNull,
      timelineZoom: {
        for (final MapEntry(:key, :value)
            in _positiveByName(json['timelineZoom']).entries)
          CutId(key): value,
      },
      storyboardZoom: _positive(json['storyboardZoom']),
      frameAxisOffsets: _positiveByName(json['frameAxisOffsets']),
      layerAxisOffsets: _positiveByName(json['layerAxisOffsets']),
      showSeconds: json['showSeconds'] == true,
      laneGraphs: LaneGraphsView(
        open: {
          for (final MapEntry(:key, :value)
              in anicelObjectMapField(json['laneGraphs']).entries)
            if (key.isNotEmpty && value is Map)
              key: _laneGraph(anicelObjectMapField(value)),
        },
        pinned: {
          if (json['pinnedLanes'] case final List<Object?> keys)
            for (final key in keys)
              if (key is String && key.isNotEmpty) key,
        },
      ),
      mediaFileViews: {
        for (final MapEntry(:key, :value)
            in anicelObjectMapField(json['mediaFileViews']).entries)
          if (MediaFileView.fromJson(value) case final view?
              when key.isNotEmpty)
            key: view,
      },
    );
  }

  /// The header graph [json] holds — a part it does not hold readably
  /// stands as on a graph nobody has sized, plotted, enlarged, taken the
  /// pen up in, hidden the transform box of or turned the snap on in.
  static LaneGraph _laneGraph(Map<String, Object?> json) => LaneGraph(
    extent: _positive(json['extent']),
    mode:
        LaneGraphMode.values
            .where((mode) => mode.name == json['mode'])
            .firstOrNull ??
        LaneGraphMode.value,
    enlarged: json['enlarged'] == true,
    pen: json['pen'] == true,
    transformBox: json['transformBox'] != false,
    snap: json['snap'] == true,
  );

  /// [value] as a zoom or an offset can be read back: a finite number above
  /// zero — at zero, or anything else, nothing was saved.
  static double? _positive(Object? value) => switch (value) {
    final num number when number.isFinite && number > 0 => number.toDouble(),
    _ => null,
  };

  /// The named [_positive] numbers the map [json] holds.
  static Map<String, double> _positiveByName(Object? json) => {
    for (final MapEntry(:key, :value) in anicelObjectMapField(json).entries)
      if (_positive(value) case final number? when key.isNotEmpty)
        key: number,
  };
}
