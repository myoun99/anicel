import '../core/collection_equality.dart';
import 'envelope/cut_envelope_presets.dart';
import 'layer_mark.dart';

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
    this.coverImagePath,
    this.envelopeFormId = CutEnvelopePresets.analogId,
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

  /// Who does each colour label's work — the name a paper form prints for
  /// a stage, or for a stage's correction — keyed by the label's
  /// [LayerMark.keySlug]: 원화 is `key`, 원화 작화감독 is
  /// `key-animation-director`.
  ///
  /// 🚨★★★ONE VOCABULARY, THE COLOUR LABELS. 유저 09-25: 「이런 스태프는
  /// 색라벨에 자세하게 나와있으니 그거 기반으로」, grouped 「공정별 묶음 —
  /// 작업자 + 그 공정의 수정 담당」 (답 staff-roles-from-labels). ↩️The
  /// window wrote the process keys while the envelope read a vocabulary of
  /// its own (`genga` · `director` …) — the two sets never met, and no name
  /// ever reached an envelope.
  ///
  /// ⛔NAMES ONLY. A 도장 or a check is made per cut on the envelope itself
  /// (유저 09-25: 「도장이나 체크나 이런거는 그냥 전처럼 컷봉투 내에서
  /// 조작」), so the work's staff carries no stamp.
  final Map<String, String> staff;

  /// The studio logo, as a [MediaAsset] path of kind `image` — the mark a
  /// form prints in its corner. Null prints nothing.
  final String? logoAssetPath;

  /// The conte cover's own picture, a [MediaAsset] path of kind `image`
  /// (유저 답 conte-cover-image: 「표지 그림 칸을 따로」). Null leaves its
  /// place empty.
  final String? coverImagePath;

  /// Which bundled 봉투 form the cut envelope prints — chosen in its panel
  /// and kept with the work (유저 답 sheet-form-choice-home: 「해당 패널에
  /// 지금처럼 두고싶고, 그 상태에서 작품에 저장되도록」). ↩️It was a
  /// workspace value that did not outlive the session.
  final String envelopeFormId;

  /// The name for [mark]'s work, or empty when nobody is set — so a form
  /// binding never has to null-check.
  String staffNameFor(LayerMark mark) => staff[mark.keySlug] ?? '';

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
    Map<String, String>? staff,
    String? Function()? logoAssetPath,
    String? Function()? coverImagePath,
    String? envelopeFormId,
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
      coverImagePath: coverImagePath == null
          ? this.coverImagePath
          : coverImagePath(),
      envelopeFormId: envelopeFormId ?? this.envelopeFormId,
    );
  }

  /// [mark]'s name replaced; an empty one drops the entry so the map never
  /// accumulates blanks.
  TimesheetInfo withStaffName(LayerMark mark, String name) {
    final next = {...staff};
    if (name.isEmpty) {
      next.remove(mark.keySlug);
    } else {
      next[mark.keySlug] = name;
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
    if (staff.isNotEmpty) 'staff': {...staff},
    if (logoAssetPath != null) 'logo': logoAssetPath,
    if (coverImagePath != null) 'cover': coverImagePath,
    if (envelopeFormId != CutEnvelopePresets.analogId)
      'envelopeForm': envelopeFormId,
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
        // A value that is not a name (a file from before the labels
        // vocabulary kept a name-and-stamp object) drops silently.
        for (final entry
            in (json['staff'] as Map<String, dynamic>? ?? const {}).entries)
          if (entry.value case final String name) entry.key: name,
      },
      logoAssetPath: json['logo'] as String?,
      coverImagePath: json['cover'] as String?,
      envelopeFormId:
          json['envelopeForm'] as String? ?? CutEnvelopePresets.analogId,
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
          other.coverImagePath == coverImagePath &&
          other.envelopeFormId == envelopeFormId &&
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
    coverImagePath,
    envelopeFormId,
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
