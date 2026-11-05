/// The two files a cut's XDTS is written as, by the blocks of its sheet:
/// the 原画 file holds the ACTION block's cel rows, the 動画 file the CELL
/// block's (`xdtsCelLayersOf`). Each is otherwise the cut's whole sheet —
/// its dialog and its camerawork as well — my call, not the user's: a
/// reader that opens one of the two still reads every value the cut has.
///
/// 🗣️I-162-Q6 (유저 2026-11-05): 「나누고, 내보내기도 원화 · 동화 두 파일로」.
/// The XDTS Viewer tells the two apart by [nameMark] in the file's name,
/// opens the other from the same folder and draws them into its ACTION and
/// CELL blocks (타임라인/콘티's reading of its `MyParams::setCurrentXdtsPath`,
/// I-162 11-05). ↩️One file a cut, which the viewer laid all in CELL.
enum XdtsSheetHalf {
  genga('_genga_ts'),
  douga('_douga_ts');

  const XdtsSheetHalf(this.nameMark);

  /// What the file's name carries for the viewer.
  final String nameMark;

  String get jsonValue => name;

  static XdtsSheetHalf? fromJson(Object? json) {
    for (final half in values) {
      if (half.jsonValue == json) {
        return half;
      }
    }
    return null;
  }
}
