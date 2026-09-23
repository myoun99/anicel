import 'dart:typed_data';

import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';

/// Every change a save made to the project file, in order — heard through
/// [anicelDebugWriteWatcher] while the save ran for real.
///
/// 🧪What a crash leaves is a PREFIX of this laid over the file as it was:
/// writes land in order and a cut is all or nothing. So one real run gives
/// every state a process that died partway through that save can leave,
/// one byte at a time, without running the save again for each — a sweep
/// that re-ran it per byte took minutes on this machine's file system.
class SaveRecording implements AnicelWriteWatcher {
  final List<(int, List<int>?)> _steps = [];

  @override
  void wrote(int at, List<int> bytes) => _steps.add((at, bytes));

  @override
  void cut(int length) => _steps.add((length, null));

  /// [before] with each prefix of the recording laid over it: the file
  /// before the save first, then one state per byte written and per cut.
  Iterable<Uint8List> statesFrom(Uint8List before) sync* {
    final file = <int>[...before];
    yield Uint8List.fromList(file);
    for (final (at, bytes) in _steps) {
      if (bytes == null) {
        file.length = at;
        yield Uint8List.fromList(file);
        continue;
      }
      if (at > file.length) {
        throw StateError('a write at $at past the end (${file.length})');
      }
      for (var i = 0; i < bytes.length; i += 1) {
        if (at + i == file.length) {
          file.add(bytes[i]);
        } else {
          file[at + i] = bytes[i];
        }
        yield Uint8List.fromList(file);
      }
    }
  }
}

/// What the app reads out of [file]: the directory the strict reader
/// finds, or — when there is none — what recovery rebuilds. Each name maps
/// to the bytes of the entry the app would use (the first one named).
Map<String, List<int>> openedAsTheAppWould(Uint8List file) {
  AnicelZipLayout layout;
  try {
    layout = parseAnicelZipLayout(file);
  } on FormatException {
    layout = recoverAnicelZipLayout(file);
  }
  final opened = <String, List<int>>{};
  for (final entry in layout.entries) {
    final used = layout.entryNamed(entry.name)!;
    opened[entry.name] = file.sublist(
      used.dataOffset,
      used.dataOffset + used.length,
    );
  }
  return opened;
}

/// Whether [a] and [b] hold the same names with the same bytes.
bool sameContents(Map<String, List<int>> a, Map<String, List<int>> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry(:key, :value) in a.entries) {
    final other = b[key];
    if (other == null || other.length != value.length) {
      return false;
    }
    for (var i = 0; i < value.length; i += 1) {
      if (other[i] != value[i]) {
        return false;
      }
    }
  }
  return true;
}
