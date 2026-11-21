import 'dart:ffi';
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/services/cel_shells.dart';

/// A keeper whose shells hold no bytes here: each tile of one reads what the
/// engine holds of it while [slots] says it does, else its cel's kept bytes
/// again — and says whether the engine holds a whole shell by [whole]. It
/// makes none of a cel while [holds] says the engine holds no tile of it,
/// but of one laid there ([lay]) while [takes] says it has room.
final class ShellsWithNoBytes implements CelShells {
  final made = <BitmapSurface>[];
  bool whole = true;
  bool slots = true;
  bool holds = true;
  int readsOfASlot = 0;
  int readsOfTheKept = 0;

  int get reads => readsOfASlot + readsOfTheKept;

  /// What was laid on the engine, each with the cel it was laid as.
  final laid = <({BitmapSurface surface, Object cel})>[];

  /// Whether the engine has room for what is laid on it.
  bool takes = true;

  /// How many times a rest was asked for.
  int restsAsked = 0;

  final _taken = Set<BitmapSurface>.identity();

  @override
  void lay(BitmapSurface surface, {required Object cel}) {
    laid.add((surface: surface, cel: cel));
    if (takes) {
      _taken.add(surface);
    }
  }

  @override
  void restBeforeLong() => restsAsked += 1;

  @override
  BitmapSurface? shellOf(
    BitmapSurface surface, {
    required BitmapSurface Function() readAgain,
  }) {
    if (!holds && !_taken.contains(surface)) {
      return null;
    }
    // As the ledger says it (`EngineTileLedger.shellOf`): a tile that is
    // the engine's already stays as it is — a shell's reads what it was
    // made to read — and a cel of such tiles alone is its own shell.
    if (surface.tiles.values.every((tile) => tile.isOnEngine)) {
      return surface.tiles.isEmpty ? null : surface;
    }
    final shell = surface.copyWith(
      tiles: {
        for (final MapEntry(key: at, value: tile) in surface.tiles.entries)
          at: tile.isOnEngine
              ? tile
              : BitmapTile.onEngine(
                  size: tile.size,
                  on: _Held(this, tile.pixels, () => readAgain().tiles[at]!),
                  hasInk: tile.hasInk,
                ),
      },
    );
    made.add(shell);
    return shell;
  }

  // As the ledger says it: a tile whose bytes are here was never the
  // engine's to let go of.
  @override
  bool isWhole(BitmapSurface shell) =>
      whole || shell.tiles.values.every((tile) => !tile.isOnEngine);
}

/// What reads a tile of [ShellsWithNoBytes]'s shells.
final class _Held implements TilePixelsKeptBesides {
  _Held(this._engine, this._onTheEngine, this._kept);

  final ShellsWithNoBytes _engine;
  final Uint8List _onTheEngine;
  final BitmapTile Function() _kept;

  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {
    final bytes = into.asTypedList(_onTheEngine.length);
    if (_engine.slots) {
      _engine.readsOfASlot += 1;
      bytes.setAll(0, _onTheEngine);
    } else {
      _engine.readsOfTheKept += 1;
      _kept().readPixels((_, view) => bytes.setAll(0, view));
    }
  }
}
