import 'dart:math' as math;
import 'dart:typed_data';

import 'progress_share.dart';

/// A read of a known length of bytes a piece at a time, told as it goes —
/// the one walk every read the bar follows takes.
///
/// 🗣️F-608-Q2 (유저 2026-11-17: 「내려받는중에 퍼센테이지가 조금이라도
/// 안느는게 문제 … 통일하면서」): a file in the cloud comes down INSIDE the
/// read that asks for it, so the percent can only move if the read is
/// told piece by piece — [onRead] hears how much is in, as 0–1, before the
/// first piece and after each one.
///
/// The piece itself is its reader's — a picked file's under its wait, a
/// .clip's on a worker, a medium's through its window — so a reader walks
/// it: [from] … [to] asked of the file, what came handed to [took].
///
/// 🚨ONE WALK (F-608-Q2, 2026-11-17). ↩️Till then the opened file's read
/// (`FolderPicker._readInPieces`) and the .clip's (`readClipPlace`) each
/// wrote this walk; a medium's whole read was to be the third.
final class PieceRead {
  /// A read of [length] bytes, [onRead] told none of them is in yet.
  PieceRead(int length, {void Function(double fraction)? onRead})
    : bytes = Uint8List(length),
      _onRead = onRead {
    onRead?.call(doneShare(0, length));
  }

  /// How much one piece asks for — the size of one arrival.
  static const int pieceBytes = 4 << 20;

  /// Where the pieces land, whole once [done].
  final Uint8List bytes;

  final void Function(double fraction)? _onRead;
  int _at = 0;

  /// Whether every byte is in.
  bool get done => _at >= bytes.length;

  /// Where the next piece starts.
  int get from => _at;

  /// Where the next piece ends, exclusive.
  int get to => math.min(_at + pieceBytes, bytes.length);

  /// [got] more bytes in, from [from] — false when none came: the file
  /// ended before its length, which only its reader can name.
  bool took(int got) {
    if (got <= 0) {
      return false;
    }
    _at += got;
    _onRead?.call(doneShare(_at, bytes.length));
    return true;
  }
}
