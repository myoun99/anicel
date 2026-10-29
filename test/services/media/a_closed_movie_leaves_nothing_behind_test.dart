import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';

import '../../helpers/mpeg4_visual_movie.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/os_video_codec.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★**A MOVIE OPENED AND CLOSED LEAVES NOTHING BEHIND.**
///
/// 관제 2026-10-23 (movie-23976-mpeg4-part2-asks-no-speed, then
/// a-closed-movie-leaves-nothing-behind): the two releases the Windows open
/// gained that day — of the stored type the rate is read off
/// (`qa_win_ask_for_the_stored_rate`) and of the samples the end is read off
/// (`qa_win_video_end_100ns`) — each survived its mutant, because nothing
/// asked what an open leaves behind. Without them every open of this movie
/// kept about 1.4KB and about 280KB; with them two hundred more opens kept
/// at most 6KB (measured that day, Windows 11 26200). The open's older
/// releases are counted the same way — the reader's, its attributes', the
/// current type's and the requested type's, the smallest at some 270B an
/// open.
///
/// ⚠️THE HEAPS — NOT THE HANDLES, NOT THE FOOTPRINT. Neither release holds a
/// handle or the file, so both counted the same with and without, and the
/// private working set the memory panel reads moves by whole pages: it
/// wandered half a megabyte over a thousand opens that leaked nothing. What
/// the heaps have handed out and not taken back does not move.
/// ⚠️THE FLOOR AND THE CEILING OF A RUN, BOTH: Media Foundation takes a
/// block of some 300KB and gives it back every twenty opens or so, so one
/// reading falls either side of it — and a whole run can miss a side: the
/// highest of one run of two hundred came back 261KB under the run before.
/// What is kept raises the lowest and the highest alike, the block only one
/// of them, so the smaller rise is what is counted. Over runs of two
/// hundred, an open that leaks nothing rose at most 6KB that way and the
/// smallest leak counted (the requested type) 38KB; the bound sits between.
///
/// ⛔WINDOWS ONLY (저장 2026-10-23): the releases this counts are that
/// backend's, and the heaps are read with its `HeapSummary`. The Apple
/// backend frees its own and nothing counts them yet — its reader would be
/// `malloc_zone_statistics`, and a bound set where it never ran is a guess.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = !Platform.isWindows
      ? 'the heaps are read with HeapSummary — Windows only'
      : libraryPath != null
      ? false
      : nativeEngineMissingSkipReason;

  setUp(() {
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaVideoDecoder.instance?.close();
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  test('🚨two hundred more opens of the same movie leave the heaps where two '
      'hundred left them', () {
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null) {
      return;
    }
    final directory = Directory.systemTemp.createTempSync('qa_closed_movie');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}movie.mov';
    // Two seconds of pictures: every sample is one the end is read off.
    File(path).writeAsBytesSync(mpeg4VisualMovie(frames: 48));
    final heaps = _Heaps();
    addTearDown(heaps.free);

    ({int lowest, int highest}) heapsOver(int opens) {
      int? lowest;
      int? highest;
      for (var open = 0; open < opens; open += 1) {
        final document = decoder.openDocument(path);
        if (document == null) {
          fail('open $open: ${decoder.lastError}');
        }
        decoder.closeDocument(document);
        final live = heaps.liveBytes();
        lowest = min(lowest ?? live, live);
        highest = max(highest ?? live, live);
      }
      return (lowest: lowest!, highest: highest!);
    }

    // The first opens fill Media Foundation's own pools.
    heapsOver(30);
    final before = heapsOver(200);
    final after = heapsOver(200);
    final kept = min(
      after.lowest - before.lowest,
      after.highest - before.highest,
    );
    expect(
      kept,
      lessThan(16 * 1024),
      reason: 'two hundred opens kept ${kept ~/ 1024}KB — measured in two '
          'hundred, the requested type unreleased keeps some 40 to 55KB, '
          'the stored type some 100 to 280KB, the end\'s samples some 55MB, '
          'and an open that leaks nothing at most 6KB',
    );
  }, skip: skip);
}

/// Every heap of this process, asked what it has handed out and not taken
/// back. What it asks with is taken once, so the asking adds nothing.
final class _Heaps {
  static const _most = 256;

  final _handles = calloc<IntPtr>(_most);
  final _summary = calloc<_HeapSummary>();

  int liveBytes() {
    final count = min(_processHeaps(_most, _handles), _most);
    var bytes = 0;
    for (var at = 0; at < count; at += 1) {
      _summary.ref.cb = sizeOf<_HeapSummary>();
      if (_heapSummary(_handles[at], 0, _summary) != 0) {
        bytes += _summary.ref.allocated;
      }
    }
    return bytes;
  }

  void free() {
    calloc.free(_handles);
    calloc.free(_summary);
  }
}

/// `HEAP_SUMMARY` (heapapi.h).
final class _HeapSummary extends Struct {
  @Uint32()
  external int cb;
  @UintPtr()
  external int allocated;
  @UintPtr()
  external int committed;
  @UintPtr()
  external int reserved;
  @UintPtr()
  external int maxReserve;
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _processHeaps = _kernel32.lookupFunction<
  Uint32 Function(Uint32, Pointer<IntPtr>),
  int Function(int, Pointer<IntPtr>)
>('GetProcessHeaps');

final _heapSummary = _kernel32.lookupFunction<
  Int32 Function(IntPtr, Uint32, Pointer<_HeapSummary>),
  int Function(int, int, Pointer<_HeapSummary>)
>('HeapSummary');
