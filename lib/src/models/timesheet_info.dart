import '../core/collection_equality.dart';
import 'production_staff.dart';

export 'production_staff.dart';

/// The paper form's header boxes, in printing order — the episode number
/// (話数 / Ep.no) leads like the real reference sheets (R7-⑥), then Title,
/// Cut, Duration, Name and Page; SCENE is the user-requested addition
/// slotted after the title. Any box can be hidden per project via
/// [TimesheetInfo.hiddenFields].
enum TimesheetHeaderField { episode, title, scene, cut, time, name, sheet }

/// The sheet-header text the paper timesheet reads: production title
/// (falls back to the project name when empty), episode label (話数),
/// scene label and the artist name (作業者), plus which header boxes the
/// form prints. Project-level — every cut's sheet shares it.
class TimesheetInfo {
  const TimesheetInfo({
    this.title = '',
    this.episode = '',
    this.scene = '',
    this.artist = '',
    this.hiddenFields = const {},
    this.exposureBarThreshold,
    this.seEmptyFill = true,
    this.staff = const {},
    this.logoAssetPath,
  });

  static const TimesheetInfo empty = TimesheetInfo();

  /// The industry-standard hold length the exposure bar option suggests.
  static const int defaultExposureBarThreshold = 3;

  final String title;
  final String episode;
  final String scene;
  final String artist;

  /// Header boxes the form does NOT print; everything else stays visible.
  final Set<TimesheetHeaderField> hiddenFields;

  /// The ACTION columns' hold bar ('1 ─ ─ ─' down held rows): null = never
  /// drawn (the default — most sheets leave holds blank); N = drawn only
  /// for exposures held N+ commas, starting from the (N+1)th comma.
  final int? exposureBarThreshold;

  /// Light-gray fill over SE columns' empty stretches (the "no SE here"
  /// wash) — default on, toggleable per project.
  final bool seEmptyFill;

  /// Who holds each production role, keyed by [ProductionRole] (or any key
  /// a studio's own form binds — the process list differs per production,
  /// so this stays an open map rather than fixed fields).
  ///
  /// Read by every paper surface: the cut envelope's 担当 row, and the
  /// approval boxes a timesheet or conte prints.
  final Map<String, ProductionStaff> staff;

  /// The studio logo, as a [MediaAsset] path of kind `image` — the mark a
  /// form prints in its corner. Null prints nothing.
  final String? logoAssetPath;

  /// The role's assignee, or an empty one when nobody is set — so a form
  /// binding never has to null-check.
  ProductionStaff staffFor(String role) =>
      staff[role] ?? ProductionStaff.empty;

  /// The header boxes the form prints, in printing order.
  List<TimesheetHeaderField> get visibleFields => [
    for (final field in TimesheetHeaderField.values)
      if (!hiddenFields.contains(field)) field,
  ];

  TimesheetInfo copyWith({
    String? title,
    String? episode,
    String? scene,
    String? artist,
    Set<TimesheetHeaderField>? hiddenFields,
    int? Function()? exposureBarThreshold,
    bool? seEmptyFill,
    Map<String, ProductionStaff>? staff,
    String? Function()? logoAssetPath,
  }) {
    return TimesheetInfo(
      title: title ?? this.title,
      episode: episode ?? this.episode,
      scene: scene ?? this.scene,
      artist: artist ?? this.artist,
      hiddenFields: hiddenFields ?? this.hiddenFields,
      exposureBarThreshold: exposureBarThreshold == null
          ? this.exposureBarThreshold
          : exposureBarThreshold(),
      seEmptyFill: seEmptyFill ?? this.seEmptyFill,
      staff: staff ?? this.staff,
      logoAssetPath: logoAssetPath == null
          ? this.logoAssetPath
          : logoAssetPath(),
    );
  }

  /// One role's assignee replaced; an empty one drops the entry so the map
  /// never accumulates blanks.
  TimesheetInfo withStaff(String role, ProductionStaff assignee) {
    final next = {...staff};
    if (assignee.isEmpty) {
      next.remove(role);
    } else {
      next[role] = assignee;
    }
    return copyWith(staff: next);
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'episode': episode,
    'scene': scene,
    'artist': artist,
    'hiddenFields': [for (final field in hiddenFields) field.name],
    if (exposureBarThreshold != null)
      'exposureBarThreshold': exposureBarThreshold,
    if (!seEmptyFill) 'seEmptyFill': false,
    if (staff.isNotEmpty)
      'staff': {
        for (final entry in staff.entries) entry.key: entry.value.toJson(),
      },
    if (logoAssetPath != null) 'logo': logoAssetPath,
  };

  factory TimesheetInfo.fromJson(Map<String, dynamic> json) {
    return TimesheetInfo(
      title: json['title'] as String? ?? '',
      episode: json['episode'] as String? ?? '',
      scene: json['scene'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      hiddenFields: {
        // Unknown names (from newer files) drop silently.
        for (final name in json['hiddenFields'] as List<dynamic>? ?? const [])
          for (final field in TimesheetHeaderField.values)
            if (field.name == name) field,
      },
      exposureBarThreshold: json['exposureBarThreshold'] as int?,
      seEmptyFill: json['seEmptyFill'] as bool? ?? true,
      staff: {
        for (final entry
            in (json['staff'] as Map<String, dynamic>? ?? const {}).entries)
          entry.key: ProductionStaff.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
      logoAssetPath: json['logo'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimesheetInfo &&
          other.title == title &&
          other.episode == episode &&
          other.scene == scene &&
          other.artist == artist &&
          other.exposureBarThreshold == exposureBarThreshold &&
          other.seEmptyFill == seEmptyFill &&
          other.logoAssetPath == logoAssetPath &&
          mapEquals(other.staff, staff) &&
          other.hiddenFields.length == hiddenFields.length &&
          other.hiddenFields.containsAll(hiddenFields);

  @override
  int get hashCode => Object.hash(
    title,
    episode,
    scene,
    artist,
    exposureBarThreshold,
    seEmptyFill,
    logoAssetPath,
    Object.hashAllUnordered(
      staff.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(hiddenFields),
  );

  @override
  String toString() =>
      'TimesheetInfo(title: $title, episode: $episode, scene: $scene, '
      'artist: $artist, hiddenFields: $hiddenFields, '
      'exposureBarThreshold: $exposureBarThreshold, '
      'seEmptyFill: $seEmptyFill)';
}
