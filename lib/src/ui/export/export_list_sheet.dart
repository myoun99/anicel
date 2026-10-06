import '../../models/cut_id.dart';

/// Why a file the Cels list shows is not written as things stand — what its
/// block says when it is pressed (F-289, 유저 2026-10-06: 「나갈 수 없는
/// 그림은 작동하려하면 이유 띄우자」).
enum ExportCelRefusal {
  /// Its row is off, and so is everything riding it.
  rowOff,

  /// The rows of its cel that are on hold no picture for it (「그림이
  /// 존재하는 영역만 출력」).
  noPicture,

  /// No cut places it on the timeline (「애초에 타임라인에 안놓은 셀은 출력에
  /// 포함하지않음」).
  notPlaced,

  /// A row of the same name files its unnamed picture first (「순서상 첫
  /// 블록만」).
  sameName,

  /// It rides its base's cels: a free attach row that is not the bundle's
  /// only picture.
  ridesBase,
}

/// ONE FILE the Cels tab could write, as its list shows it — a BLOCK: a
/// cel, a page of the cut's timesheet, the cut envelope.
///
/// The list draws these and nothing else, so a cel and a document are
/// turned off, stood on and told apart by ONE law — the timesheet and the
/// envelope came into the tab as kinds of what it writes (유저 2026-10-05:
/// 「타임시트 탭을 그냥 셀 탭의 내부로 편입. 컷봉투탭도 셀 내부로 편입」).
abstract class ExportListSheet {
  const ExportListSheet();

  /// Names it among its row's blocks: its widget key, and where the list
  /// stands.
  String get idValue;

  /// The cut whose delta holds what the hand did to it.
  CutId get deltaCut;

  /// What its block reads.
  String get word;

  /// Its whole name, for where there is the room to say it.
  String get fullName;

  /// The file it is written as — empty while it is [refused].
  String get fileName;

  /// The user turned it off. Kept while it is [refused] too: a row turned
  /// back on lights the ones that were left on, and no others.
  bool get skipped;

  /// Why it is no file as things stand, or null for a PLANNED one.
  ExportCelRefusal? get refused;

  /// Whether a direction is laid over it.
  bool get laid;

  bool get planned => refused == null;

  /// Whether a file is written for it.
  bool get written => planned && !skipped;
}
