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
/// name while it has none), its episode (話数), who does the conte — plus
/// how the timesheet prints its header. Project-level: every cut's sheets
/// share it.
///
/// ⛔No scene: 유저 09-25 「씬은 작품설정에선 필요없어. 1500컷을 작업한다치면
/// 콘티패널 내에서 컷들을 하나로 묶어서 씬/파트 이렇게 묶게할예정」 — a scene
/// belongs to a group of cuts, not to the work.
/// ⛔No artist of its own: a sheet's 作業者 is a stage's worker on the CUT
/// (`sheetArtistMark`). ↩️It was the 원화 worker in the work's [staff]
/// (유저 09-25 「작품설정 작업자랑 원화랑 겹치니까 타임시트든 뭐든 스태프의
/// 원화 이름 인식하게하고」) until the stages other than the conte became
/// each cut's (F-291-Q1, 2026-10-08).
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
    this.conteCover = true,
    this.conteBlankPage = true,
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

  /// Who does the conte's work — its worker and its corrections, the stages
  /// the work keeps ([StaffHolder.work]; every other stage is the cut's,
  /// `CutMetadata.staff`) — keyed by the label's [LayerMark.keySlug]: the
  /// conte is `conte`, its 감독 `conte-director`.
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

  /// Whether the conte book opens with its COVER, and whether the cover's
  /// BLANK back follows it (유저 2026-09-25: 「보통 1페이지는 표지,
  /// 2페이지는 인쇄할때 생각해서 빈용지, 3페이지부터 콘티 본 페이지」) —
  /// each put in or taken out in the conte panel's settings and kept with
  /// the work, and an export prints the book the panel shows (유저
  /// 2026-10-02, I-59: 「1페이지 헤더 넣기/빼기, 2페이지 빈용지 넣기빼기.
  /// 위치는 콘티 용지패널의 설정버튼안에. 이게 내보내기시에도 연동」).
  final bool conteCover;
  final bool conteBlankPage;

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
    bool? conteCover,
    bool? conteBlankPage,
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
      conteCover: conteCover ?? this.conteCover,
      conteBlankPage: conteBlankPage ?? this.conteBlankPage,
    );
  }

  /// [mark]'s name replaced ([staffWithName]).
  TimesheetInfo withStaffName(LayerMark mark, String name) =>
      copyWith(staff: staffWithName(staff, mark, name));

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
    if (!conteCover) 'conteCover': false,
    if (!conteBlankPage) 'conteBlankPage': false,
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
      staff: staffFromJson(json['staff']),
      logoAssetPath: json['logo'] as String?,
      coverImagePath: json['cover'] as String?,
      envelopeFormId:
          json['envelopeForm'] as String? ?? CutEnvelopePresets.analogId,
      conteCover: json['conteCover'] as bool? ?? true,
      conteBlankPage: json['conteBlankPage'] as bool? ?? true,
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
          other.conteCover == conteCover &&
          other.conteBlankPage == conteBlankPage &&
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
    conteCover,
    conteBlankPage,
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

/// A picture of the work its sheets print, taken from its media pool: the
/// company logo and the conte cover's picture — which field keeps it. ONE
/// vocabulary for the window that picks them (작품 설정), the walk that moves
/// them with their file (`projectWithMediaMoved`) and the pool that lists
/// them among a file's uses.
enum WorkPicture {
  logo,
  cover;

  /// The pool path [info] keeps for this picture, or null.
  String? pathIn(TimesheetInfo info) => switch (this) {
    logo => info.logoAssetPath,
    cover => info.coverImagePath,
  };

  /// [info] keeping [path] for this picture — null takes it away.
  TimesheetInfo withPath(TimesheetInfo info, String? path) => switch (this) {
    logo => info.copyWith(logoAssetPath: () => path),
    cover => info.copyWith(coverImagePath: () => path),
  };
}
