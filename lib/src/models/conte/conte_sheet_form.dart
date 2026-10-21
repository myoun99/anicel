/// The forms a conte sheet is printed in (🗣️유저 2026-10-21, I-118: 「콘티용지의
/// 새로운 서식. 지금은 아날로그식? … 그리고 디지털식? 요즘에 맞게 컷번호
/// 항목도 본문인 화면쪽이랑 붙어있고, 컷 마다 가로로 선 그어서 칸 제대로
/// 나누는방식」) — chosen in the sheet's format window and kept with the work
/// (`TimesheetInfo.conteForm`), as the envelope's form is.
enum ConteSheetForm {
  /// The reference sheet's (유저 2026-09-25): the cut box stands apart from
  /// the table, and nothing rules the body across — a cell's words run until
  /// the next cell's start.
  analog,

  /// Today's: the cut column stands against the picture's, and a rule across
  /// the table ends every cut — a cut's words stop on it.
  digital;

  /// The form [name] names in a file, or [analog] for a name this build
  /// does not know.
  static ConteSheetForm named(Object? name) {
    for (final form in values) {
      if (form.name == name) {
        return form;
      }
    }
    return analog;
  }
}
