import '../../core/collection_equality.dart';
import '../canvas_size.dart';
import '../media_asset.dart';

/// THE PICTURES A PICKED ONE COMES IN WITH — its NUMBERED RUN, one layer's
/// frames (I-76 → F-392).
///
/// 🗣️F-392 (유저 2026-10-17): 「1.jpg 2.jpg는 연속으로 안불러와지고 A1.jpg
/// A2.jpg여야 연속되는데, 그냥 A면 이라는거 없이 숫자면 연속되도록.
/// A1s.jpg일때 이런건 기존처럼 다르게 두되 … 숫자뒤 s가 붙은거끼리
/// 이어져야함. 그런식으로 규칙단순화하고 통일」 · 「숫자 연속된거라도 중간에
/// 해상도 다른거만나면 항목으로서 독립시키도록」.
///
/// ONE RULE: pictures whose names are the same but for the LAST number in
/// them run together, in that number's order — `1` · `2` · `3`, `A1` · `A2`,
/// and `A1s` · `A2s`, which is not `A1`'s run: what follows the number is
/// part of the name, and so is the extension. A run holds ONE size: where a
/// picture of another size stands in it, the run stops there
/// ([sameSizeRunOf]).
///
/// ↩️It was read with the cut folder's grammar (I-76): a layer symbol and a
/// cel number, so `1.jpg` was no cel, `A1s` was an insertion in `A1`'s run
/// and `A2_` folded into `A2` as its revision. The FOLDER import still reads
/// a cut folder that way (rule B · C · F) — a folder of cels is layers ×
/// cels, where a picked picture's run is one layer's frames.
///
/// ⛔A `_` name runs with nothing (rule E, the folders the user measured):
/// `_BOOK2` and `_BOOK3` are two books, and a timesheet's pages are no
/// frames.
class PictureRun {
  const PictureRun({required this.name, required this.pictures});

  /// What its layer is called: its pictures' name around the number — `A`
  /// of `A1`, `As` of `A1s`, `shot` of `shot_0001` — or, where nothing
  /// stands around it (`1` · `2`), the folder's.
  final String name;

  /// In the order of their numbers.
  final List<RunPicture> pictures;

  @override
  bool operator ==(Object other) =>
      other is PictureRun &&
      other.name == name &&
      listEquals(other.pictures, pictures);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(pictures));
}

/// One picture of a [PictureRun].
class RunPicture {
  const RunPicture({required this.file, required this.number});

  /// The file's name in its folder.
  final String file;

  /// The number as the name spells it — what the picture's frame is called.
  final String number;

  /// The name it is shown by: the file's, without its extension.
  String get shown => mediaFileNameParts(file).name;

  @override
  bool operator ==(Object other) =>
      other is RunPicture && other.file == file && other.number == number;

  @override
  int get hashCode => Object.hash(file, number);
}

/// The run [picked] is part of among [names] — the file names of the folder
/// it lives in, called [folderName] — or null when no other picture runs
/// with it.
PictureRun? pictureRunOf(
  String picked,
  Iterable<String> names, {
  required String? folderName,
}) {
  final key = _runKeyOf(picked);
  if (key == null) {
    return null;
  }
  final pictures = [
    for (final name in names)
      if (_runKeyOf(name) case final other? when other.sameRunAs(key))
        (picture: RunPicture(file: name, number: other.digits), key: other),
  ]..sort((a, b) => a.key.compareTo(b.key, a.picture.file, b.picture.file));
  if (pictures.length < 2) {
    return null;
  }
  final around = _trimmed('${key.before}${key.after}');
  return PictureRun(
    name: around.isNotEmpty
        ? around
        : (folderName ?? mediaFileNameParts(picked).name),
    pictures: [for (final entry in pictures) entry.picture],
  );
}

/// [run] as far as [picked]'s size holds on either side of it — [sizeOf]
/// each picture's size, null for one that cannot be read, which holds no
/// size — or null when that leaves [picked] alone.
PictureRun? sameSizeRunOf(
  PictureRun run,
  String picked,
  CanvasSize? Function(String file) sizeOf,
) {
  final at = run.pictures.indexWhere((picture) => picture.file == picked);
  final size = at < 0 ? null : sizeOf(picked);
  if (size == null) {
    return null;
  }
  bool holds(int index) => sizeOf(run.pictures[index].file) == size;
  var first = at;
  while (first > 0 && holds(first - 1)) {
    first -= 1;
  }
  var last = at;
  while (last < run.pictures.length - 1 && holds(last + 1)) {
    last += 1;
  }
  return last == first
      ? null
      : PictureRun(
          name: run.name,
          pictures: run.pictures.sublist(first, last + 1),
        );
}

/// [name] read as a picture of a run: what stands before its last number,
/// the number, and what stands after — the extension apart — or null for a
/// name with no number, or a `_` name.
_RunKey? _runKeyOf(String name) {
  if (name.startsWith('_')) {
    return null;
  }
  final (name: stem, :extension) = mediaFileNameParts(name);
  final match = _lastNumber.firstMatch(stem);
  if (match == null) {
    return null;
  }
  return _RunKey(
    before: match.group(1)!,
    digits: match.group(2)!,
    after: match.group(3)!,
    extension: extension.toLowerCase(),
  );
}

/// A name's LAST number, and what stands either side of it.
final RegExp _lastNumber = RegExp(r'^(.*?)(\d+)(\D*)$');

/// [text] without the separators that only stood between it and a number.
String _trimmed(String text) =>
    text.replaceAll(RegExp(r'^[\s._-]+|[\s._-]+$'), '');

class _RunKey {
  const _RunKey({
    required this.before,
    required this.digits,
    required this.after,
    required this.extension,
  });

  final String before;
  final String digits;
  final String after;
  final String extension;

  bool sameRunAs(_RunKey other) =>
      other.before == before &&
      other.after == after &&
      other.extension == extension;

  /// By the number's value — `2` before `10` — then by how it is spelled,
  /// then by [file] against [otherFile].
  int compareTo(_RunKey other, String file, String otherFile) {
    final value = _byValue(digits, other.digits);
    if (value != 0) {
      return value;
    }
    final spelled = digits.compareTo(other.digits);
    return spelled != 0 ? spelled : file.compareTo(otherFile);
  }

  static int _byValue(String a, String b) {
    final x = a.replaceFirst(RegExp('^0+'), '');
    final y = b.replaceFirst(RegExp('^0+'), '');
    return x.length != y.length ? x.length - y.length : x.compareTo(y);
  }
}
