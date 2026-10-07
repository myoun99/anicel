import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/pin_counts.dart';
import '../../models/bitmap_surface.dart';
import '../../models/rgba_image_bytes.dart';
import '../camera/camera_frame_render_service.dart' show RowPictures;
import '../canvas/tiled_surface_compose.dart' show PositionedSurfaceImage;

/// The row pictures a video run's held cut pictures are made of — each held
/// for as long as a picture made of it is held, as far as the room lent to
/// them reaches.
///
/// 🗣️유저 2026-10-07 (F-289-Q21): 「붙든다 — 재생 줄의 허용치 안에서」. A
/// frame on which a cut's picture changes composited every row of the cut
/// again where two of five or six had changed — 56% of a run of the user's
/// film (card `video-export-holds-unchanged-rows`). A row that shows what
/// the picture before it showed is that picture's row, handed again.
///
/// A row is the picture its SURFACE composes to and nothing more — its
/// pose, opacity and effects are laid on at the draw — so it is held under
/// that surface: the object itself, which the run holds while it shows (the
/// renderer's cels). A drawing read again is another object, and composes
/// again.
///
/// ⛔THE ROOM IS LENT, NOT A BUDGET OF ITS OWN — the user chose that the
/// memory allowance gets no export line. Playback rests while a run goes,
/// so its line lends the run what its caches will give back ([room]), and
/// hears every change in what is held ([onHeld]) so that they give way. A
/// row that does not fit is composed for its render and let go after it,
/// as every row was before.
class HeldRows {
  HeldRows({
    required int Function() room,
    required void Function(int bytes) onHeld,
  }) : _room = room,
       _onHeld = onHeld;

  final int Function() _room;
  final void Function(int bytes) _onHeld;

  final _rows = HashMap<BitmapSurface, _Row>.identity();

  /// The rows each held picture is made of, under that picture's key.
  final _byPicture = <Object, List<_Row>>{};

  /// How many held pictures are made of each row.
  final _holds = PinCounts<_Row>();

  var _bytes = 0;
  var _said = 0;

  /// How many row pictures have been composed — a row a held picture
  /// already holds is not.
  int get made => _made;
  var _made = 0;

  /// How many rows every holder is holding right now (test hook) — a run
  /// that is over holds none.
  @visibleForTesting
  static int debugHeld = 0;

  /// [render]'s result, made with the rows held here — and the rows it was
  /// made of held from then on under [picture], the key its own holder
  /// knows it by, until that key is let go ([letGoOf]).
  ///
  /// A render that fails holds nothing new.
  Future<T> during<T>(
    Object picture,
    Future<T> Function(RowPictures rows) render,
  ) async {
    final rows = _RowsOfOnePicture(this);
    try {
      final made = await render(rows);
      // A picture made again under a key lets go of what the one before
      // held — after this one has taken what it shares with it.
      _byPicture.update(picture, (before) {
        before.forEach(_release);
        return rows._held;
      }, ifAbsent: () => rows._held);
      return made;
    } on Object {
      rows._held.forEach(_release);
      rethrow;
    } finally {
      for (final image in rows._passing) {
        image.dispose();
      }
      _tell();
    }
  }

  /// Lets go of the rows held under [picture] — the ones no other held
  /// picture is made of. A row is held under nothing but a picture, so
  /// once every picture is let go, every row is.
  void letGoOf(Object picture) {
    _byPicture.remove(picture)?.forEach(_release);
    _tell();
  }

  /// [composed], held under [surface] — or null when it does not fit in
  /// the room.
  _Row? _keep(BitmapSurface surface, PositionedSurfaceImage composed) {
    final bytes = estimatedImageBytes(
      composed.image.width,
      composed.image.height,
    );
    if (_bytes + bytes > _room()) {
      return null;
    }
    final row = _Row(surface, composed, bytes);
    _rows[surface] = row;
    _bytes += bytes;
    debugHeld += 1;
    _tell();
    return row;
  }

  void _release(_Row row) {
    _holds.release(row);
    if (_holds.isPinned(row)) {
      return;
    }
    _rows.remove(row.surface);
    row.picture.image.dispose();
    _bytes -= row.bytes;
    debugHeld -= 1;
  }

  /// Says what is held now, when that has changed since it was last said.
  void _tell() {
    if (_said == _bytes) {
      return;
    }
    _said = _bytes;
    _onHeld(_bytes);
  }
}

/// One row picture held.
final class _Row {
  _Row(this.surface, this.picture, this.bytes);

  final BitmapSurface surface;
  final PositionedSurfaceImage picture;
  final int bytes;
}

/// The rows of the one picture being made — what it asks for, from what is
/// held or composed now.
final class _RowsOfOnePicture implements RowPictures {
  _RowsOfOnePicture(this._keeper);

  final HeldRows _keeper;

  /// The held rows this picture is made of, each once.
  final _held = <_Row>[];

  /// The rows composed for this picture alone (no room for them), let go
  /// when it is made.
  final _passing = <ui.Image>[];

  @override
  Future<PositionedSurfaceImage> of(
    BitmapSurface surface,
    Future<PositionedSurfaceImage> Function() compose,
  ) async {
    final held = _keeper._rows[surface];
    if (held != null) {
      _hold(held);
      return held.picture;
    }
    final composed = await compose();
    _keeper._made += 1;
    final row = _keeper._keep(surface, composed);
    if (row == null) {
      _passing.add(composed.image);
    } else {
      _hold(row);
    }
    return composed;
  }

  void _hold(_Row row) {
    if (_held.any((held) => identical(held, row))) {
      return;
    }
    _keeper._holds.retain(row);
    _held.add(row);
  }
}
