import '../core/collection_equality.dart';
import 'camera_instruction.dart';
import 'canvas_size.dart';
import 'export_overrides.dart';
import 'layer.dart';
import 'layer_link_registry.dart';
import 'media_asset.dart';
import 'media_viewer_bookmark.dart';
import 'project_background.dart';
import 'project_frame_rate.dart';
import 'project_id.dart';
import 'timesheet_info.dart';
import 'track.dart';

const defaultProjectCameraSize = CanvasSize(width: 1920, height: 1080);

/// The default BACKDROP: the app's own floor colour — one step darker than
/// chrome, and NOT pure black (유저, R4 #2).
///
/// It is the filmic ground a fade-out lands on (R3b), which is why it was
/// black. Black turned out to cost more than it bought: with the pasteboard
/// held equal to it (below), ink laid down outside the paper was invisible —
/// "완전블랙이면 페이스트보드에 그려도 안보여서". Lifting both to the value
/// the chrome already sits on keeps the two planes one field, keeps them
/// clearly darker than the app around them, and lets a black line show.
///
/// ⚠️This colour REACHES THE EXPORT: `export_frame_renderer` paints it under
/// every non-alpha frame and a fade thins the frame down to it. A project
/// that wants a true-black fade sets its backdrop back to `0xFF000000` with
/// the canvas pill's backdrop swatch (the project background window this
/// used to name is gone, F-114) — the default is the editor's opinion, not a
/// constraint on the film.
///
/// ⚠️Must stay in step with `AppColors.backdrop`, which is the same colour
/// stated in the UI layer (the models layer may not import the theme).
const defaultProjectBackdropArgb = 0xFF141517;

/// The default PASTEBOARD: the same as the backdrop (유저, R3 #4, held).
///
/// It must stay in step with `AppWorkspaceColors.defaultPasteboardArgb` — a
/// project omits this key when it matches the default, so the two constants
/// disagreeing would make a saved project change colour on the way back in.
const defaultProjectPasteboardArgb = 0xFF141517;

/// The default audio rate (EXPORT-AUDIO ③): 48 kHz is the film/video
/// production standard (44.1k is the CD/music one) and what the conform
/// pipeline has targeted since 2B.
const defaultProjectAudioSampleRate = 48000;

class Project {
  Project({
    required this.id,
    required this.name,
    required List<Track> tracks,
    required this.createdAt,
    this.frameRate = ProjectFrameRate.fps24,
    this.cameraSize = defaultProjectCameraSize,
    this.background = ProjectBackground.defaultBackground,
    this.backdropArgb = defaultProjectBackdropArgb,
    this.backdropNone = false,
    this.pasteboardArgb = defaultProjectPasteboardArgb,
    this.pasteboardNone = false,
    this.timesheetInfo = TimesheetInfo.empty,
    CameraInstructionSet? cameraInstructions,
    List<MediaAsset> mediaAssets = const [],
    int trailingFrames = 0,
    LayerLinkRegistry? linkRegistry,
    int audioSampleRate = defaultProjectAudioSampleRate,
    int audioSpeedNumerator = 1,
    int audioSpeedDenominator = 1,
    ExportProjectOverrides? exportOverrides,
    MediaViewerBookmarks mediaViewerBookmarks = const {},
  }) : mediaViewerBookmarks = Map.unmodifiable(mediaViewerBookmarks),
       tracks = List.unmodifiable(tracks),
       exportOverrides = exportOverrides ?? ExportProjectOverrides.empty,
       cameraInstructions = cameraInstructions ?? CameraInstructionSet.standard,
       mediaAssets = immutableMediaAssetList(mediaAssets),
       trailingFrames = trailingFrames < 0 ? 0 : trailingFrames,
       linkRegistry = linkRegistry ?? LayerLinkRegistry.empty,
       audioSampleRate = audioSampleRate < 1
           ? defaultProjectAudioSampleRate
           : audioSampleRate,
       audioSpeedNumerator = audioSpeedNumerator < 1 ? 1 : audioSpeedNumerator,
       audioSpeedDenominator = audioSpeedDenominator < 1
           ? 1
           : audioSpeedDenominator;

  final ProjectId id;
  final String name;
  final List<Track> tracks;
  final DateTime createdAt;

  /// The exact rate, fraction and all (23.976 = 24000/1001).
  final ProjectFrameRate frameRate;

  /// The integer rate the sheet, the grid and every frame index count
  /// with. Timing lives in [frameRate]; counting lives here, and the two
  /// differ only for the NTSC pulldown rates.
  int get fps => frameRate.countingBase;

  final CanvasSize cameraSize;

  /// The movie's TRAILING GAP (UI-R20 #3): extra frames past the last
  /// cut's end — the storyboard end line drags THIS, so the final length
  /// is authored independently of the cuts (gaps are first-class on this
  /// timeline, the tail included). The movie end = the cuts' content end
  /// + this.
  final int trailingFrames;

  /// The PAPER (R10-⑥ / R3b): the sheet under the artwork, alpha-capable
  /// — one plane of the four-plane stage this project displays and
  /// prints with (backdrop → pasteboard → paper → pictures).
  final ProjectBackground background;

  /// The BACKDROP: the panel-wide floor behind everything — what a fade
  /// reveals, and what an opaque export bakes where nothing covers.
  ///
  /// 🚨It was opaque by contract (it is the stage's final answer; an alpha
  /// here would only re-ask the question — user 2026-07-29), the constructor
  /// forcing the alpha byte. F-114 (유저 2026-09-15) gave it the opacity the
  /// paper and the pasteboard have: 「페이스트보드, 백그라운드 설정에도
  /// 동일적용」. The byte is kept as written.
  final int backdropArgb;

  /// Whether the backdrop is ABSENT (F-114) — a checkerboard where it would
  /// be, nothing painted for it — rather than thinned. [backdropArgb] stays
  /// kept for the next pick. The paper's own is [ProjectBackground.none].
  final bool backdropNone;

  /// The PASTEBOARD: the apron around the paper, RGBA — thinning it
  /// reveals the backdrop. PROJECT data now, not app state: a camera
  /// reaching past the paper prints it, and what prints travels with the
  /// project (R28 #9 reversed by the user, 2026-07-29 — the app-level
  /// value demoted to a new-project default).
  final int pasteboardArgb;

  /// Whether the pasteboard is ABSENT (F-114), as [backdropNone] is for the
  /// backdrop.
  final bool pasteboardNone;

  /// Sheet-header text (title/episode/artist) the timesheet document reads.
  final TimesheetInfo timesheetInfo;

  /// The instruction vocabulary instruction rows pick from; seeds with the
  /// standard 撮影 terms and is user-editable.
  final CameraInstructionSet cameraInstructions;

  /// The media pool the browser panel lists, keyed by absolute path.
  /// Loading reconciles it against every clip reference, so legacy projects
  /// (and hand-edited files) always open with a complete pool.
  final List<MediaAsset> mediaAssets;

  /// The film's layer link table ("이름이 같으면 같은 그림"): groups of
  /// layers sharing one cel bank. Empty on projects that never link.
  final LayerLinkRegistry linkRegistry;

  /// The project's audio rate: what every sound conforms to at import and
  /// what the mixer runs at (EXPORT-AUDIO ③). PROJECT state — unlike the
  /// A/V offset (a property of one machine's output path), the rate is a
  /// property of the film.
  final int audioSampleRate;

  /// The project's audio speed as an exact rational (EXPORT-AUDIO ④):
  /// 1001/1000 after choosing the "0.1% pull" on a 23.976→24 change, so
  /// every sound keeps its exact frame span. Unity everywhere else.
  /// Applied at conform time; accumulates (and cancels) across repeated
  /// rate changes.
  final int audioSpeedNumerator;
  final int audioSpeedDenominator;

  /// The pull as ONE value. Four places paired these two fields into
  /// exactly this record by hand — the conform store, the import window's
  /// preview, the movie hydrator and the door that places a movie — and a
  /// pair carried by hand is a pair that can be carried inverted.
  ({int numerator, int denominator}) get audioSpeed =>
      (numerator: audioSpeedNumerator, denominator: audioSpeedDenominator);

  /// PROJECT-side export state (출력 UI): the cut checks the Cels/Timesheet
  /// project scope excludes and each cut's Cels manual delta. Travels with
  /// the film; written through the repository with no history entry.
  final ExportProjectOverrides exportOverrides;

  /// What each viewer was looking at, keyed by its panel id (유저 확정 ⑤
  /// ㉑) — see [MediaViewerBookmark] for why it lives here and why
  /// writing it is not a document edit.
  final MediaViewerBookmarks mediaViewerBookmarks;

  /// The pool's entry for [path], in whichever spelling it is asked
  /// ([normalizedMediaPath]).
  MediaAsset? mediaAssetByPath(String path) {
    final key = normalizedMediaPath(path);
    for (final asset in mediaAssets) {
      if (asset.path == key) {
        return asset;
      }
    }
    return null;
  }

  /// The fit a placed file's picture sits with: the pool entry's own, and
  /// [MediaFitMode.contain] for a path no entry names.
  ///
  /// ⚠️ONE ANSWER, because two places must agree about it: a movie kept as a
  /// reference has each decoded frame fitted to the canvas with this, and
  /// RASTERIZING that movie bakes the same frames as cels with it. Were they
  /// to drift, baking would move the picture.
  MediaFitMode mediaFitModeFor(String path) =>
      mediaAssetByPath(path)?.fitMode ?? MediaFitMode.contain;

  Project copyWith({
    ProjectId? id,
    String? name,
    List<Track>? tracks,
    DateTime? createdAt,
    ProjectFrameRate? frameRate,
    CanvasSize? cameraSize,
    ProjectBackground? background,
    int? backdropArgb,
    bool? backdropNone,
    int? pasteboardArgb,
    bool? pasteboardNone,
    TimesheetInfo? timesheetInfo,
    CameraInstructionSet? cameraInstructions,
    List<MediaAsset>? mediaAssets,
    MediaViewerBookmarks? mediaViewerBookmarks,
    int? trailingFrames,
    LayerLinkRegistry? linkRegistry,
    int? audioSampleRate,
    int? audioSpeedNumerator,
    int? audioSpeedDenominator,
    ExportProjectOverrides? exportOverrides,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt ?? this.createdAt,
      frameRate: frameRate ?? this.frameRate,
      cameraSize: cameraSize ?? this.cameraSize,
      background: background ?? this.background,
      backdropArgb: backdropArgb ?? this.backdropArgb,
      backdropNone: backdropNone ?? this.backdropNone,
      pasteboardArgb: pasteboardArgb ?? this.pasteboardArgb,
      pasteboardNone: pasteboardNone ?? this.pasteboardNone,
      timesheetInfo: timesheetInfo ?? this.timesheetInfo,
      cameraInstructions: cameraInstructions ?? this.cameraInstructions,
      mediaAssets: mediaAssets ?? this.mediaAssets,
      trailingFrames: trailingFrames ?? this.trailingFrames,
      linkRegistry: linkRegistry ?? this.linkRegistry,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioSpeedNumerator: audioSpeedNumerator ?? this.audioSpeedNumerator,
      audioSpeedDenominator:
          audioSpeedDenominator ?? this.audioSpeedDenominator,
      exportOverrides: exportOverrides ?? this.exportOverrides,
      mediaViewerBookmarks:
          mediaViewerBookmarks ?? this.mediaViewerBookmarks,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    'tracks': tracks.map((track) => track.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    // `fps` stays the counting base so a file written today still opens
    // in a build that predates the fraction; `frameRate` carries the
    // exact rate and wins on read.
    'fps': fps,
    'frameRate': frameRate.toJson(),
    'cameraSize': cameraSize.toJson(),
    if (background != ProjectBackground.defaultBackground)
      'background': background.toJson(),
    // Omitted at the defaults: pre-stage projects keep their exact JSON.
    if (backdropArgb != defaultProjectBackdropArgb)
      'backdropArgb': backdropArgb,
    if (backdropNone) 'backdropNone': true,
    if (pasteboardArgb != defaultProjectPasteboardArgb)
      'pasteboardArgb': pasteboardArgb,
    if (pasteboardNone) 'pasteboardNone': true,
    'timesheetInfo': timesheetInfo.toJson(),
    'cameraInstructions': cameraInstructions.toJson(),
    'mediaAssets': mediaAssets.map((asset) => asset.toJson()).toList(),
    if (trailingFrames != 0) 'trailingFrames': trailingFrames,
    // Omitted when empty: unlinked projects keep their exact legacy JSON.
    if (linkRegistry.isNotEmpty) 'linkRegistry': linkRegistry.toJson(),
    // Omitted at the default: 48k projects keep their exact legacy JSON.
    if (audioSampleRate != defaultProjectAudioSampleRate)
      'audioSampleRate': audioSampleRate,
    if (audioSpeedNumerator != audioSpeedDenominator) ...{
      'audioSpeedNumerator': audioSpeedNumerator,
      'audioSpeedDenominator': audioSpeedDenominator,
    },
    // Omitted when empty: projects that never touched the export scope
    // keep their exact legacy JSON.
    if (exportOverrides.isNotEmpty) 'exportOverrides': exportOverrides.toJson(),
    // Omitted when empty: a project nobody opened a reference in keeps
    // its exact legacy JSON.
    if (mediaViewerBookmarks.isNotEmpty)
      'mediaViewerBookmarks': {
        for (final entry in mediaViewerBookmarks.entries)
          entry.key: entry.value.toJson(),
      },
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    final tracks = (json['tracks'] as List<dynamic>)
        .map((track) => Track.fromJson(track as Map<String, dynamic>))
        .toList();
    final storedAssets = json['mediaAssets'] == null
        ? const <MediaAsset>[]
        : (json['mediaAssets'] as List<dynamic>)
              .map(
                (asset) => MediaAsset.fromJson(asset as Map<String, dynamic>),
              )
              .toList();
    return Project(
      id: ProjectId.fromJson(json['id'] as Map<String, dynamic>),
      name: json['name'] as String,
      tracks: tracks,
      createdAt: DateTime.parse(json['createdAt'] as String),
      frameRate: json['frameRate'] == null
          ? ProjectFrameRate.integer(json['fps'] as int)
          : ProjectFrameRate.fromJson(
              json['frameRate'] as Map<String, dynamic>,
            ),
      cameraSize: json['cameraSize'] == null
          ? defaultProjectCameraSize
          : CanvasSize.fromJson(json['cameraSize'] as Map<String, dynamic>),
      background: json['background'] == null
          ? ProjectBackground.defaultBackground
          : ProjectBackground.fromJson(
              json['background'] as Map<String, dynamic>,
            ),
      backdropArgb:
          (json['backdropArgb'] as int?) ?? defaultProjectBackdropArgb,
      backdropNone: json['backdropNone'] == true,
      pasteboardArgb:
          (json['pasteboardArgb'] as int?) ?? defaultProjectPasteboardArgb,
      pasteboardNone: json['pasteboardNone'] == true,
      timesheetInfo: json['timesheetInfo'] == null
          ? TimesheetInfo.empty
          : TimesheetInfo.fromJson(
              json['timesheetInfo'] as Map<String, dynamic>,
            ),
      cameraInstructions: json['cameraInstructions'] == null
          ? null
          : CameraInstructionSet.fromJson(
              json['cameraInstructions'] as Map<String, dynamic>,
            ),
      mediaAssets: reconciledMediaAssets(storedAssets, tracks),
      trailingFrames: (json['trailingFrames'] as int?) ?? 0,
      linkRegistry: json['linkRegistry'] == null
          ? null
          : LayerLinkRegistry.fromJson(
              json['linkRegistry'] as Map<String, dynamic>,
            ),
      audioSampleRate:
          (json['audioSampleRate'] as int?) ?? defaultProjectAudioSampleRate,
      audioSpeedNumerator: (json['audioSpeedNumerator'] as int?) ?? 1,
      audioSpeedDenominator: (json['audioSpeedDenominator'] as int?) ?? 1,
      exportOverrides: json['exportOverrides'] == null
          ? null
          : ExportProjectOverrides.fromJson(
              json['exportOverrides'] as Map<String, dynamic>,
            ),
      mediaViewerBookmarks: mediaViewerBookmarksFromJson(
        json['mediaViewerBookmarks'],
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project &&
          other.id == id &&
          other.name == name &&
          listEquals(other.tracks, tracks) &&
          other.createdAt == createdAt &&
          other.frameRate == frameRate &&
          other.cameraSize == cameraSize &&
          other.background == background &&
          other.timesheetInfo == timesheetInfo &&
          other.cameraInstructions == cameraInstructions &&
          listEquals(other.mediaAssets, mediaAssets) &&
          other.trailingFrames == trailingFrames &&
          other.linkRegistry == linkRegistry &&
          other.audioSampleRate == audioSampleRate &&
          other.audioSpeedNumerator == audioSpeedNumerator &&
          other.audioSpeedDenominator == audioSpeedDenominator &&
          other.exportOverrides == exportOverrides &&
          mapEquals(other.mediaViewerBookmarks, mediaViewerBookmarks);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(tracks),
    createdAt,
    frameRate,
    cameraSize,
    background,
    timesheetInfo,
    cameraInstructions,
    Object.hashAll(mediaAssets),
    trailingFrames,
    linkRegistry,
    audioSampleRate,
    audioSpeedNumerator,
    audioSpeedDenominator,
    exportOverrides,
    Object.hashAll([
      for (final entry in mediaViewerBookmarks.entries) (entry.key, entry.value),
    ]),
  );

  @override
  String toString() =>
      'Project(id: $id, name: $name, tracks: $tracks, '
      'createdAt: $createdAt, frameRate: $frameRate, '
      'cameraSize: $cameraSize)';
}

/// [stored] plus a synthesized entry (file-name display name) for every
/// clip-referenced path the pool does not know yet, in first-reference
/// order. Legacy projects predate the pool entirely; newer files can also
/// arrive with pool/clips out of sync (hand edits, merges) — loading always
/// reconciles rather than trusting the stored list.
List<MediaAsset> reconciledMediaAssets(
  List<MediaAsset> stored,
  List<Track> tracks,
) {
  final known = {for (final asset in stored) asset.path};
  final synthesized = <MediaAsset>[];
  void addFromLayer(Layer layer) {
    for (final clip in layer.audioClips) {
      if (known.add(clip.filePath)) {
        synthesized.add(
          MediaAsset(
            path: clip.filePath,
            name: mediaAssetDefaultName(clip.filePath),
          ),
        );
      }
    }
  }

  for (final track in tracks) {
    for (final layer in track.seLayers) {
      addFromLayer(layer);
    }
    for (final cut in track.cuts) {
      for (final layer in cut.layers) {
        addFromLayer(layer);
      }
    }
  }
  return synthesized.isEmpty ? stored : [...stored, ...synthesized];
}
