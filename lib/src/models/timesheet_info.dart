import '../core/collection_equality.dart';
import 'envelope/cut_envelope_presets.dart';
import 'layer_mark.dart';

/// The paper form's header boxes, in printing order — the episode number
/// (話数 / Ep.no) leads like the real reference sheets (R7-⑥), then Title,
/// Cut, Duration, Name and Page; SCENE is the user-requested addition
/// slotted after the title. Any box can be hidden per project via
/// [TimesheetInfo.hiddenFields].
enum TimesheetHeaderField { episode, title, scene, cut, time, name, sheet }

/// The work's words every paper form prints — its title (the project's
/// name while it has none), its episode (話数), who does each stage's work
/// — plus how the timesheet prints its header. Project-level: every cut's
/// sheets share it.
///
/// ⛔No scene: 유저 09-25 「씬은 작품설정에선 필요없어. 1500컷을 작업한다치면
/// 콘티패널 내에서 컷들을 하나로 묶어서 씬/파트 이렇게 묶게할예정」 — a scene
/// belongs to a group of cuts, not to the work.
/// ⛔No artist of its own: a sheet's 作業者 is the 원화 worker in [staff]
/// (유저 09-25 「작품설정 작업자랑 원화랑 겹치니까 타임시트든 뭐든 스태프의
/// 원화 이름 인식하게하고」).
class TimesheetInfo {
  const TimesheetInfo({
    this.title = '',
    this.episode = '',
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
      'TimesheetInfo(title: $title, episode: $episode, staff: $staff, '
      'hiddenFields: $hiddenFields, '
      'exposureBarThreshold: $exposureBarThreshold, '
      'seEmptyFill: $seEmptyFill)';
}
