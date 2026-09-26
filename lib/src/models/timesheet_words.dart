/// The words the timesheet PRINTS — its header boxes' labels and the sheet
/// vocabulary — handed in already in the NOTATION language (UI-R10 #7:
/// submissions follow the studio's paper convention, not the program's
/// language).
///
/// ⛔A model keeps no words per language: the string tables hold them, and
/// the screen reads the notation language's table into one of these — the
/// conte's words the same way (`ConteWords`).
class TimesheetWords {
  const TimesheetWords({
    required this.episode,
    required this.title,
    required this.scene,
    required this.cut,
    required this.duration,
    required this.name,
    required this.page,
    required this.repeat,
    required this.hold,
  });

  /// The header boxes' labels.
  final String episode;
  final String title;
  final String scene;
  final String cut;
  final String duration;
  final String name;
  final String page;

  /// The word a repeat ghost span prints instead of re-listing its cel
  /// numbers (UI-R10 #6) — display only, the underlying data keeps the
  /// expanded 1,2,3,1,2,3 for XDTS/TDTS export. Printed VERTICALLY, one
  /// character per row (UI-R11 #14).
  final String repeat;

  /// The word a whole-cut hold prints (UI-R11 #15, the sheet's 止め):
  /// shown when the layer displays as ONE cel from row 1 held to the end.
  /// Vertical like [repeat].
  final String hold;

  @override
  bool operator ==(Object other) =>
      other is TimesheetWords &&
      other.episode == episode &&
      other.title == title &&
      other.scene == scene &&
      other.cut == cut &&
      other.duration == duration &&
      other.name == name &&
      other.page == page &&
      other.repeat == repeat &&
      other.hold == hold;

  @override
  int get hashCode => Object.hash(
    episode,
    title,
    scene,
    cut,
    duration,
    name,
    page,
    repeat,
    hold,
  );
}
