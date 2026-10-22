import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/bitmap_surface.dart';
import '../../services/playback/let_go_wanted_latest.dart';
import '../camera/camera_frame_render_service.dart' show RowPictures;
import '../canvas/image_pieces.dart';
import '../canvas/tiled_surface_compose.dart' show PositionedSurfaceImage;

/// When a run next shows a row: how many frames on from the frame
/// being drawn the first frame that shows [address] is, counting from
/// [from] frames on (0 — the frame being drawn); null when no frame from
/// there shows it.
typedef RowNextShown = int? Function(Object address, int from);

/// The row pictures of an export run — each held from the frame that composes
/// it to the last frame ahead that shows it, as far as the room lent to
/// them reaches.
///
/// 🗣️유저 2026-10-07 (F-289-Q21): 「붙든다 — 재생 줄의 허용치 안에서」. A
/// frame on which a cut's picture changes composited every row of the cut
/// again where two of five or six had changed — 56% of a run of the user's
/// film (card `video-export-holds-unchanged-rows`).
///
/// A row is the picture its CEL composes to and nothing more — its pose,
/// opacity and effects are laid on at the draw — so it is held under the
/// cel's address ([addressOf]: which cel, at which revision), and a cel read
/// again is the row held for it. And at the level the render reduces it to
/// (`displayLevelOf`): a camera that zooms across a halving asks for the
/// cel at another, which is another picture; both are wanted for as long
/// as a frame ahead shows the cel.
///
/// ↩️It was held under the surface OBJECT, for as long as a held picture was
/// made of it (10-07). 🔬Measured 2026-10-13 on the user's film (Surface Pro
/// 11, profile build, card `video-export-speed`): of 1,594 row rasters, 958
/// were of cels composed before — a drawing that leaves the frame for two
/// frames and comes back, as each drawing of a cycle does, is read again,
/// and a surface read again is another object. Each was a canvas-size
/// raster with every tile uploaded again.
///
/// ⛔THE ROOM IS LENT, NOT A BUDGET OF ITS OWN — the user chose that the
/// memory allowance gets no export line. Playback rests while a run goes,
/// so its line lends the run what its caches will give back ([room]), and
/// hears every change in what is held ([onHeld]) so that they give way.
/// Where the room is short the rows let go in the order playback's caches
/// do ([letGoWantedLatest]: the one shown latest first), and a row shown
/// later than every held one is composed for its render and let go after
/// it.
class HeldRows {
  HeldRows({
    required int Function() room,
    required void Function(int bytes) onHeld,
    required Object Function(BitmapSurface surface) addressOf,
    required RowNextShown nextShown,
    required bool Function() laidTexelForTexel,
  }) : _room = room,
       _onHeld = onHeld,
       _addressOf = addressOf,
       _nextShown = nextShown,
       _laidTexelForTexel = laidTexelForTexel;

  final int Function() _room;
  final void Function(int bytes) _onHeld;
  final Object Function(BitmapSurface surface) _addressOf;
  final RowNextShown _nextShown;

  /// The run's word that every picture it makes lays its rows down texel
  /// for texel ([RowPictures.laidTexelForTexel]).
  final bool Function() _laidTexelForTexel;

  final _rows = <_RowAt, _Row>{};

  var _bytes = 0;
  var _said = 0;

  /// One tick per picture made — the recency that orders rows shown at
  /// the same frame.
  var _clock = 0;

  /// How many row pictures have been composed — a row held already is not.
  int get made => _made;
  var _made = 0;

  /// How many rows every holder is holding right now (test hook) — a run
  /// that is over holds none.
  @visibleForTesting
  static int debugHeld = 0;

  /// [render]'s result, made with the rows held here — and each row it
  /// composes held from then on, if a frame ahead shows it and the room has
  /// it.
  Future<T> during<T>(Future<T> Function(RowPictures rows) render) async {
    final rows = _RowsOfOnePicture(this, _clock += 1);
    try {
      return await render(rows);
    } finally {
      for (final passing in rows._passing.values) {
        passing.pieces.disposeAll();
      }
      _tell();
    }
  }

  /// The next frame starts: the rows no frame from it on shows are let go —
  /// the room they took goes back to playback — and then the rows shown
  /// latest, until what is held fits the room.
  ///
  /// The room can shrink while a run goes: an OS memory warning halves
  /// playback's line, and rows held before it would stand over the lowered
  /// line for as long as frames ahead show them (the storage session's
  /// review, 2026-10-08). A row let go only waits to be asked for again, and
  /// is composed again when it is.
  void nextFrame() {
    for (final row in [..._rows.values]) {
      if (_nextShown(row.at.address, 0) == null) {
        _letGo(row);
      }
    }
    _letGoShownLatest(maxBytes: _room());
    _tell();
  }

  /// Lets go of every row held — the run is over.
  void dispose() {
    for (final row in [..._rows.values]) {
      _letGo(row);
    }
    _tell();
  }

  /// Lets go of the rows [among] shown latest until what is held is
  /// [maxBytes] or under, never one shown [laterThan] frames on or sooner;
  /// answers whether it got there.
  bool _letGoShownLatest({
    required int maxBytes,
    Iterable<_Row>? among,
    int? laterThan,
  }) => letGoWantedLatest(
    entries: [...(among ?? _rows.values)],
    heldBytes: _bytes,
    maxBytes: maxBytes,
    wantedAt: (row) => _nextShown(row.at.address, 0),
    lastUsed: (row) => row.lastUsed,
    bytesOf: (row) => row.bytes,
    letGo: _letGo,
    laterThan: laterThan,
  );

  /// [composed], held [at] its cel and level by the picture stamped
  /// [stamp] — or null when no frame after this one shows it, or room
  /// cannot be made for it but by letting go of a row shown sooner. The
  /// rows [inUse] are the picture's own, still to be drawn, and stay.
  _Row? _keep(
    _RowAt at,
    PositionedSurfaceImage composed, {
    required int stamp,
    required Set<_Row> inUse,
  }) {
    final next = _nextShown(at.address, 1);
    if (next == null) {
      return null;
    }
    final bytes = composed.pieces.estimatedBytes;
    final fits = _letGoShownLatest(
      maxBytes: _room() - bytes,
      among: [
        for (final row in _rows.values)
          if (!inUse.contains(row)) row,
      ],
      laterThan: next,
    );
    if (!fits) {
      return null;
    }
    final row = _Row(at, composed, bytes)..lastUsed = stamp;
    _rows[at] = row;
    _bytes += bytes;
    debugHeld += 1;
    return row;
  }

  void _letGo(_Row row) {
    _rows.remove(row.at);
    row.picture.pieces.disposeAll();
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

/// Which cel's row, at which level.
typedef _RowAt = ({Object address, int level});

/// One row picture held.
final class _Row {
  _Row(this.at, this.picture, this.bytes);

  final _RowAt at;
  final PositionedSurfaceImage picture;
  final int bytes;

  /// The stamp of the last picture made with it.
  int lastUsed = 0;
}

/// The rows of the one picture being made — what it asks for, from what is
/// held or composed now.
final class _RowsOfOnePicture implements RowPictures {
  _RowsOfOnePicture(this._keeper, this._stamp);

  final HeldRows _keeper;
  final int _stamp;

  /// The held rows this picture is made of.
  final _inUse = <_Row>{};

  /// The rows composed for this picture alone, under their cels and levels
  /// — let go when it is made.
  final _passing = <_RowAt, PositionedSurfaceImage>{};

  @override
  bool get laidTexelForTexel => _keeper._laidTexelForTexel();

  @override
  Future<PositionedSurfaceImage> of(
    BitmapSurface surface,
    int level,
    Future<PositionedSurfaceImage> Function() compose,
  ) async {
    final at = (address: _keeper._addressOf(surface), level: level);
    final held = _keeper._rows[at];
    if (held != null) {
      held.lastUsed = _stamp;
      _inUse.add(held);
      return held.picture;
    }
    final passing = _passing[at];
    if (passing != null) {
      return passing;
    }
    final composed = await compose();
    _keeper._made += 1;
    final row = _keeper._keep(
      at,
      composed,
      stamp: _stamp,
      inUse: _inUse,
    );
    if (row == null) {
      _passing[at] = composed;
    } else {
      _inUse.add(row);
    }
    return composed;
  }
}
