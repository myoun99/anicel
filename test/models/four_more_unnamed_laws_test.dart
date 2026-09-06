import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_stroke_commit_outcome.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/tvpp_key_value_lines.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/string_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';

/// Four more laws the audit left unnamed by any test.
void main() {
  group('a typed id is its TYPE plus its value', () {
    test('🚨two ids of different types never match, however equal their '
        'strings — a LayerId is not a FrameId that happens to read the '
        'same', () {
      expect(const FrameId('a') == const LayerId('a'), isFalse);
      expect(const FrameId('a'), const FrameId('a'));
      expect(const FrameId('a'), isNot(const FrameId('b')));
    });

    test('it is a StringId, and prints as its bare value', () {
      expect(const FrameId('a'), isA<StringId>());
      expect(const FrameId('a').toString(), 'a');
      expect('${const LayerId('l1')}', 'l1');
    });

    test('the JSON is the value under one key, both ways', () {
      expect(const FrameId('a').toJson(), {'value': 'a'});
      expect(FrameId.fromJson(const {'value': 'a'}), const FrameId('a'));
    });

    test('⚠️the hash is the VALUE\'s — different types collide in a bucket '
        'and are separated by ==, which is what a Map needs', () {
      expect(const FrameId('a').hashCode, const LayerId('a').hashCode);
      expect(
        {const FrameId('a'): 1, const LayerId('a'): 2},
        hasLength(2),
        reason: 'a map holding both keeps them apart',
      );
    });
  });

  group('the clip-config key=value lines ([cameradata], [audio+N])', () {
    test('an [audio+N] section reads through the same law — the header '
        'line drops out, a path keeps its own =', () {
      expect(tvppKeyValueLines('[audio+0]\nfilepath=G:/a=b.mp4\nmute=1'), {
        'filepath': 'G:/a=b.mp4',
        'mute': '1',
      });
    });

    test('key=value lines become a map, trimmed', () {
      expect(tvppKeyValueLines('a=1\n  b  =  two  \nc=3'), {
        'a': '1',
        'b': 'two',
        'c': '3',
      });
    });

    test('🚨everything after the FIRST = is the value — a value may '
        'contain one', () {
      expect(tvppKeyValueLines('mpoint=0.5=1.0'), {'mpoint': '0.5=1.0'});
    });

    test('⛔an = at index 0 is not a key', () {
      expect(tvppKeyValueLines('=orphan'), isEmpty);
    });

    test('lines with no = are skipped, not stored empty', () {
      expect(tvppKeyValueLines('[cameradata]\na=1\n\n'), {'a': '1'});
    });

    test('a later line WINS — the block is read top to bottom', () {
      expect(tvppKeyValueLines('a=1\na=2'), {'a': '2'});
    });
  });

  group('the app-support path', () {
    test('is <base>/anicel/<file>, with the app folder always in it', () {
      final path = appSupportFilePath('export.json');
      expect(path, endsWith('/anicel/export.json'));
    });

    test('is stable across calls — "where app state lives" is one fact', () {
      expect(appSupportFilePath('a.json'), appSupportFilePath('a.json'));
    });

    test('🚨the separators are FORWARD, even on Windows, so a path built '
        'here compares equal to one read back', () {
      expect(appSupportFilePath('brush_tips/tip.png'), isNot(contains(r'\')));
    });

    test('a subfolder rides through', () {
      expect(
        appSupportFilePath('Recovery/snap.anicel'),
        endsWith('/anicel/Recovery/snap.anicel'),
      );
    });
  });

  group('a committed stroke bills only what it changed', () {
    BitmapSurface surface({int tileSize = 8}) => BitmapSurface(
      canvasSize: const CanvasSize(width: 32, height: 32),
      tileSize: tileSize,
      tiles: const {},
    );

    test('the retained bytes are the DIRTY tiles, not the whole surface — '
        'the rest is shared with the neighbouring undo entry', () {
      final outcome = BrushStrokeCommitOutcome(
        preSurface: surface(),
        postSurface: surface(),
        dirtyTiles: DirtyTileSet([
          TileCoord(x: 0, y: 0),
          TileCoord(x: 1, y: 0),
        ]),
      );

      expect(outcome.estimatedRetainedBytes, 2 * 8 * 8 * 4);
    });

    test('a stroke that changed nothing retains nothing', () {
      final outcome = BrushStrokeCommitOutcome(
        preSurface: surface(),
        postSurface: surface(),
        dirtyTiles: DirtyTileSet(),
      );

      expect(outcome.estimatedRetainedBytes, 0);
    });

    test('the bill follows the PRE surface\'s tile size — those are the '
        'bytes actually being held', () {
      final outcome = BrushStrokeCommitOutcome(
        preSurface: surface(tileSize: 16),
        postSurface: surface(),
        dirtyTiles: DirtyTileSet([TileCoord(x: 0, y: 0)]),
      );

      expect(outcome.estimatedRetainedBytes, 16 * 16 * 4);
    });
  });
}
