/// A KIND of thing the Cels tab writes — the tab's FIRST filter.
///
/// 🗣️F-289 (유저 2026-10-06): 「셀/콘티/미술/디렉션/타임시트/컷봉투 이렇게
/// 두자. 미술 라벨이 아닌 일반적으로 셀로 들어가는 것들도 여기 넣어서, 셀
/// 체크 해제하면 출력될거에서 셀 빠진다거나 … 이렇게 정해진 내보낼 타입이
/// 제일 첫번째 필터? 그래서 여기서 사라진것들은 오른쪽 행 리스트에서
/// 안보이도록 … 필터는 정해진 행중에서 필터로 뭔가를 바꾸는거고, 그래서
/// 필터로 off되도 사라진다거나 하지않음」 — and its name: 「타입이 아니라
/// 내보낼 종류로」. So a kind that is off is not in the window's list at all,
/// where a row a FILTER turns off stays in it, off.
///
/// Which kind a row is: `exportCelKindOf`. The last three are no row's: they
/// are the cut's own documents, written beside its cels (유저 2026-10-05:
/// 「타임시트 탭을 그냥 셀 탭의 내부로 편입. 컷봉투탭도 셀 내부로 편입」), the
/// film among them since I-151.
///
/// ↩️Art and direction were two switches that ADDED rows on top of the
/// label's pick (`addArt` · `addDirection`), and a conte row went out only
/// under the conte label.
enum ExportCelKind {
  /// The rows that go out as ordinary cels — every drawing row that is not
  /// one of the kinds below.
  cel(defaultPrefix: ''),

  /// The conte row's drawings, written as cels are (유저: 「진짜 그냥 셀
  /// 출력하듯이 캔버스에 콘티그림있는채로 일반 셀이랑 똑같이」).
  conte(defaultPrefix: ''),

  /// The image rows, by their layer kind — 🗣️F-578-Q4 (유저 2026-11-10):
  /// 「이미지」 for 「미술」. ↩️The rows labelled 미술, the kind named 미술.
  image(defaultPrefix: '_'),

  /// The direction rows.
  direction(defaultPrefix: '_'),

  /// The cut's timesheet — its pages, or its digital sheet file.
  timesheet(defaultPrefix: '_'),

  /// The cut envelope (컷 봉투).
  envelope(defaultPrefix: '_'),

  /// The cut's film — a movie a cut, under the project scope too (I-151,
  /// 유저 2026-11-03: 「범위 대상은 프로젝트로 하더라도 셀은 컷마다 출력이니까
  /// 컷마다 영상 출력하는것임」). Its prefix is the documents' — my call, not
  /// the user's.
  video(defaultPrefix: '_');

  /// Whether this kind's rows pass the colour label filter by their own
  /// mark — the cels and the images (🗣️F-578, 유저 2026-11-10: 「해당
  /// 공정에서 발생한걸 내보낸다」); the others go out while their kind is on.
  /// ↩️The cels alone (F-289).
  bool get wearsTheLabel =>
      this == ExportCelKind.cel || this == ExportCelKind.image;

  /// Whether this kind is a document of the cut rather than a kind of its
  /// rows.
  bool get isDocument =>
      this == ExportCelKind.timesheet ||
      this == ExportCelKind.envelope ||
      this == ExportCelKind.video;

  const ExportCelKind({required this.defaultPrefix});

  /// What a file of this kind starts with until the user says otherwise
  /// (`ExportCelNaming.prefixOf`) — 유저 2026-10-06: 「기본값은 셀:없음,
  /// 미술:_, 디렉션:_, 시트:_, 컷봉투:_」, and for the conte: 「콘티레이어는
  /// 다만 기본값 없음으로」.
  final String defaultPrefix;

  String get jsonValue => name;

  static ExportCelKind? fromJson(Object? json) {
    for (final kind in values) {
      if (kind.jsonValue == json) {
        return kind;
      }
    }
    return null;
  }
}
