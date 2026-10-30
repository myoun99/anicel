import '../core/collection_equality.dart';
import '../core/copy_with_sentinel.dart';
import 'conte/conte_camera_room.dart';
import 'layer_mark.dart';
import 'layer_process.dart';
import 'timesheet_sheet_kind.dart';

class CutMetadata {
  const CutMetadata({
    this.pageNotes = const [],
    this.mark = LayerMark.none,
    this.staff = const {},
    this.sheetKind = TimesheetSheetKind.sixSeconds,
    this.scene = '',
    this.openStaffFolds = staffFoldsOpenAtFirst,
    this.conteCameraRoom,
  });

  const CutMetadata.empty()
    : pageNotes = const [],
      mark = LayerMark.none,
      staff = const {},
      sheetKind = TimesheetSheetKind.sixSeconds,
      scene = '',
      openStaffFolds = staffFoldsOpenAtFirst,
      conteCameraRoom = null;

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

  /// The scene this cut is in, as the timesheet's SCENE box prints it —
  /// empty where none is written.
  ///
  /// 🗣️유저 2026-10-28 (F-291): 「타임시트용지패널에서 신 눌러서
  /// 편집할수있게하고, 기억되는 위치는 컷 대상으로 한 이름편집에서 신이란
  /// 항목을 위에 둬서 거기서도 편집가능. 즉 컷마다 개별적임 … 신은 그리고
  /// 이름 비울수있음」. ↩️The box was written by hand on the printed paper
  /// alone (09-25: 「씬은 작품설정에선 필요없어」).
  final String scene;

  /// The stages whose folds 컷 설정 opens on for this cut — as it was last
  /// saved with them.
  ///
  /// 🗣️유저 2026-10-28 (F-291): 「이런 접힘/펼침상태는 컷별로 기억」 · F-291-Q4
  /// 「파일에, 저장 버튼을 누를 때만」 — the window's 저장 writes them with
  /// the names, ONE undo step; a cancelled window keeps what was saved.
  final Set<LayerProcess> openStaffFolds;

  /// How much of the conte sheet this cut's cells take where its camera
  /// moves — null where the cut takes the format window's
  /// (`TimesheetInfo.conteCameraRoom`): I-82-Q1 (유저 2026-10-30) 「서식
  /// 전체 + 컷마다 덮어쓰기」.
  final ConteCameraRoom? conteCameraRoom;

  /// [mark]'s name on this cut, or empty when nobody is set.
  String staffNameFor(LayerMark mark) => staff[mark.keySlug] ?? '';

  /// [mark]'s name on this cut replaced ([staffWithName]).
  CutMetadata withStaffName(LayerMark mark, String name) =>
      copyWith(staff: staffWithName(staff, mark, name));

  CutMetadata copyWith({
    List<String>? pageNotes,
    LayerMark? mark,
    Map<String, String>? staff,
    TimesheetSheetKind? sheetKind,
    String? scene,
    Set<LayerProcess>? openStaffFolds,
    Object? conteCameraRoom = copyWithSentinel,
  }) {
    return CutMetadata(
      pageNotes: pageNotes ?? this.pageNotes,
      mark: mark ?? this.mark,
      staff: staff ?? this.staff,
      sheetKind: sheetKind ?? this.sheetKind,
      scene: scene ?? this.scene,
      openStaffFolds: openStaffFolds ?? this.openStaffFolds,
      conteCameraRoom: identical(conteCameraRoom, copyWithSentinel)
          ? this.conteCameraRoom
          : conteCameraRoom as ConteCameraRoom?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (pageNotes.isNotEmpty) 'pageNotes': [...pageNotes],
    if (!mark.isNone) 'mark': mark.toJson(),
    if (staff.isNotEmpty) 'staff': {...staff},
    if (sheetKind != TimesheetSheetKind.sixSeconds)
      'sheetKind': sheetKind.jsonValue,
    if (scene.isNotEmpty) 'scene': scene,
    if (!setEquals(openStaffFolds, staffFoldsOpenAtFirst))
      'openStaffFolds': [
        for (final process in LayerProcess.values)
          if (openStaffFolds.contains(process)) process.jsonValue,
      ],
    if (conteCameraRoom case final room?) 'conteCameraRoom': room.name,
    // The per-cut fade TARGET (FO/WO) is gone (R3b) — legacy 'fadeTarget'
    // keys are ignored on read. ↩️F-192: the black or white a fade clears
    // from or closes to is the TERM's (F.x black, W.x white —
    // `transitionScreenColorOf`), not the cut's and not the backdrop's.
    // ⛔The thumbnail frame pin is gone too — 🗣️F-379 (유저 2026-10-17):
    // 「컷 버튼의 썸네일 프레임 고정 삭제. 기능 싹 잔재 삭제」. A block shows
    // its first frame; a legacy 'thumbnailFrame' key is ignored on read.
  };

  factory CutMetadata.fromJson(Map<String, dynamic> json) {
    return CutMetadata(
      pageNotes: List.unmodifiable([
        for (final note in json['pageNotes'] as List? ?? const []) '$note',
      ]),
      mark: LayerMark.fromJson(json['mark']),
      staff: staffFromJson(json['staff']),
      sheetKind: TimesheetSheetKind.fromJson(json['sheetKind']),
      scene: '${json['scene'] ?? ''}',
      openStaffFolds: switch (json['openStaffFolds']) {
        final List<dynamic> open => Set.unmodifiable({
          for (final value in open) ?LayerProcess.fromJson(value),
        }),
        _ => staffFoldsOpenAtFirst,
      },
      conteCameraRoom: ConteCameraRoom.named(json['conteCameraRoom']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutMetadata &&
          listEquals(other.pageNotes, pageNotes) &&
          other.mark == mark &&
          mapEquals(other.staff, staff) &&
          other.sheetKind == sheetKind &&
          other.scene == scene &&
          setEquals(other.openStaffFolds, openStaffFolds) &&
          other.conteCameraRoom == conteCameraRoom;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(pageNotes),
    mark,
    Object.hashAllUnordered(
      staff.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    sheetKind,
    scene,
    Object.hashAllUnordered(openStaffFolds),
    conteCameraRoom,
  );

  @override
  String toString() =>
      'CutMetadata(pageNotes: $pageNotes, '
      'mark: $mark, staff: $staff, sheetKind: $sheetKind, scene: $scene, '
      'openStaffFolds: $openStaffFolds, '
      'conteCameraRoom: $conteCameraRoom)';
}
