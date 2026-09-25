import 'dart:io';

/// Whether [a] and [b] name the same file — the one answer to 「is this the
/// project file」, whoever asks: the held handle (`OpenProjectFile`), a
/// save's refs and its readers, a Save As telling itself from a save, the
/// swap that repoints refs.
///
/// 🚨★★★**FIVE SPELLINGS OF ONE QUESTION, AND THEY DISAGREED ABOUT CASE**
/// (audit 09-25): the handle compared the strings whole, three compared
/// them with the separators made one, and the save's own test folded case
/// too. The same file picked in another case for a Save As let the readers
/// go and kept the session's own handle, and the rename stayed refused.
///
/// A backslash is a separator where the platform says so — Windows — and a
/// letter of the name everywhere else, so there a name spelled with one is
/// another file. 🪦「The separators never matter」 was the first line here,
/// and on Linux CI a save onto the bound file spelled with backslashes was
/// judged a save of that file while it wrote another one (d607dba65 pinned
/// the test to Windows; this is the product half). [backslashSeparates] is
/// the platform's answer, passed only by a test asking the other one.
///
/// Letters that differ only in case name one file where the volume folds
/// case (Windows, most Macs) and two where it does not (Android, iOS,
/// Linux) — so for those the file system answers
/// ([FileSystemEntity.identicalSync]), and a name that is not there is not
/// the same file.
bool namesTheSameFile(String a, String b, {bool? backslashSeparates}) {
  // Every cel read asks this of the held file — the same string, nearly
  // always: answered before anything is built.
  if (a == b) {
    return true;
  }
  final separates = backslashSeparates ?? Platform.isWindows;
  final left = separates ? a.replaceAll(r'\', '/') : a;
  final right = separates ? b.replaceAll(r'\', '/') : b;
  if (left == right) {
    return true;
  }
  if (left.toLowerCase() != right.toLowerCase()) {
    return false;
  }
  try {
    return FileSystemEntity.identicalSync(a, b);
  } on FileSystemException {
    return false;
  }
}
