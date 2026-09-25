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
/// The separators never matter. Letters that differ only in case name one
/// file where the volume folds case (Windows, most Macs) and two where it
/// does not (Android, iOS, Linux) — so for those the file system answers
/// ([FileSystemEntity.identicalSync]), and a name that is not there is not
/// the same file.
bool namesTheSameFile(String a, String b) {
  // Every cel read asks this of the held file — the same string, nearly
  // always: answered before anything is built.
  if (a == b) {
    return true;
  }
  final left = a.replaceAll(r'\', '/');
  final right = b.replaceAll(r'\', '/');
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
