/// A byte count as a person reads it: `340 MB`, `1.2 GB`.
///
/// Shared because two places now put a size in front of a decision — the
/// import window asking whether a file should go inside the project, and
/// Preferences saying what the conform cache is holding — and a number
/// that means the same thing should not be rounded two different ways
/// depending on which screen you are looking at.
///
/// Megabytes are whole (a decimal on 340 MB is noise) and gigabytes carry
/// one place (the difference between 1.2 and 1.8 is the decision).
String byteSizeLabel(int bytes) {
  const megabyte = 1024 * 1024;
  if (bytes >= 1024 * megabyte) {
    return '${(bytes / (1024 * megabyte)).toStringAsFixed(1)} GB';
  }
  if (bytes >= megabyte) {
    return '${(bytes / megabyte).round()} MB';
  }
  return '${(bytes / 1024).round()} KB';
}
