import '../core/collection_equality.dart';
import 'layer_mark.dart';
import 'timesheet_sheet_kind.dart';

class CutMetadata {
  const CutMetadata({
    this.pageNotes = const [],
    this.thumbnailFrameIndex,
    this.mark = LayerMark.none,
    this.staff = const {},
    this.sheetKind = TimesheetSheetKind.sixSeconds,
  });

  const CutMetadata.empty()
    : pageNotes = const [],
      thumbnailFrameIndex = null,
      mark = LayerMark.none,
      staff = const {},
      sheetKind = TimesheetSheetKind.sixSeconds;

  /// The memo written on each page of the cut's timesheet, by page —
  /// trailing blanks left off ([withPageNote]).
  ///
  /// 🗣️F-301 (유저 2026-10-05): 「타임시트의 메모란은 페이지별로 다름 …
  /// 페이지별로 독립」. ↩️It was one note per cut, printed on every page and
  /// written by any of them. A page the cut no longer prints keeps its memo
  /// and shows it again when it prints again — the sheet's ink's law
  /// (F-252).
  final List<String> pageNotes;

  /// The memo on page [page] (0-based), empty where none is written.
  String noteOf(int page) =>
      page >= 0 && page < pageNotes.length ? pageNotes[page] : '';

  /// [text] as page [page]'s memo, the others as they are.
  CutMetadata withPageNote(int page, String text) {
    final notes = [
      for (var at = 0; at < pageNotes.length || at <= page; at += 1)
        if (at == page) text else noteOf(at),
    ];
    while (notes.isNotEmpty && notes.last.isEmpty) {
      notes.removeLast();
    }
    return copyWith(pageNotes: List.unmodifiable(notes));
  }

  /// The cut-local frame the storyboard block's thumbnail shows; null means
  /// the first frame. Clamped to the playback range at render time, so a
  /// later trim never breaks it.
  final int? thumbnailFrameIndex;

  /// The cut's 색 라벨 — the SAME label a layer carries, palette and all.
  ///
  /// 🗣️유저 2026-09-26: 「애초에 컷별로 우리가 정한 색라벨 적용할수있게할거거든?
  /// 정한거 그대로 사용. 겸용컷은 물론 한 컷 취급이니까 같이바뀌고 … 색라벨
  /// 정하는건 블록마다 다른거니까 컷버튼안에 있다던가. 선택범위 한상태로
  /// 조작가능한거 물론이고」 — one [LayerMark], not a cut palette of its own,
  /// so a palette change repaints cuts and layers alike. 겸용 cuts carry one
  /// label ([UpdateCutMarkCommand] writes every sibling).
  final LayerMark mark;

  /// Who does each stage's work on THIS cut — every stage but the conte's,
  /// which is the work's ([StaffHolder.cut]) — by the label's
  /// [LayerMark.keySlug], as the work's staff is (`TimesheetInfo.staff`).
  /// ↩️A stage with no name here took the work's (유저 09-25: 작품 설정에는
  /// 기본값, 컷 설정에는 컷별 이름) until the work kept the conte's alone
  /// (F-291-Q1, 2026-10-08).
  final Map<String, String> staff;

  /// The paper this cut's timesheet prints on — the cut's own
  /// (timesheet-sheet-kind-scope-Q1: 「컷마다 따로」). A cut with more cel
  /// layers than the 6-second sheet holds prints on the 3-second one
  /// whatever this says ([sheetKindFor]).
  final TimesheetSheetKind sheetKind;

  /// [mark]'s name on this cut, or empty when nobody is set.
  String staffNameFor(LayerMark mark) => staff[mark.keySlug] ?? '';

  /// [mark]'s name on this cut replaced ([staffWithName]).
  CutMetadata withStaffName(LayerMark mark, String name) =>
      copyWith(staff: staffWithName(staff, mark, name));

  /// [thumbnailFrameIndex] passes as a closure so callers can CLEAR the pin
  /// (`() => null`) — the plain-nullable convention cannot express that.
  CutMetadata copyWith({
    List<String>? pageNotes,
    int? Function()? thumbnailFrameIndex,
    LayerMark? mark,
    Map<String, String>? staff,
    TimesheetSheetKind? sheetKind,
  }) {
    return CutMetadata(
      pageNotes: pageNotes ?? this.pageNotes,
      thumbnailFrameIndex: thumbnailFrameIndex == null
          ? this.thumbnailFrameIndex
          : thumbnailFrameIndex(),
      mark: mark ?? this.mark,
      staff: staff ?? this.staff,
      sheetKind: sheetKind ?? this.sheetKind,
    );
  }

  Map<String, dynamic> toJson() => {
    if (pageNotes.isNotEmpty) 'pageNotes': [...pageNotes],
    if (thumbnailFrameIndex != null) 'thumbnailFrame': thumbnailFrameIndex,
    if (!mark.isNone) 'mark': mark.toJson(),
    if (staff.isNotEmpty) 'staff': {...staff},
    if (sheetKind != TimesheetSheetKind.sixSeconds)
      'sheetKind': sheetKind.jsonValue,
    // The per-cut fade TARGET (FO/WO) is gone (R3b) — legacy 'fadeTarget'
    // keys are ignored on read. ↩️F-192: the black or white a fade clears
    // from or closes to is the TERM's (F.x black, W.x white —
    // `transitionScreenColorOf`), not the cut's and not the backdrop's.
  };

  factory CutMetadata.fromJson(Map<String, dynamic> json) {
    return CutMetadata(
      pageNotes: List.unmodifiable([
        for (final note in json['pageNotes'] as List? ?? const []) '$note',
      ]),
      thumbnailFrameIndex: json['thumbnailFrame'] as int?,
      mark: LayerMark.fromJson(json['mark']),
      staff: staffFromJson(json['staff'], holder: StaffHolder.cut),
      sheetKind: TimesheetSheetKind.fromJson(json['sheetKind']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutMetadata &&
          listEquals(other.pageNotes, pageNotes) &&
          other.thumbnailFrameIndex == thumbnailFrameIndex &&
          other.mark == mark &&
          mapEquals(other.staff, staff) &&
          other.sheetKind == sheetKind;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(pageNotes),
    thumbnailFrameIndex,
    mark,
    Object.hashAllUnordered(
      staff.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    sheetKind,
  );

  @override
  String toString() =>
      'CutMetadata(pageNotes: $pageNotes, '
      'thumbnailFrame: $thumbnailFrameIndex, '
      'mark: $mark, staff: $staff, sheetKind: $sheetKind)';
}
