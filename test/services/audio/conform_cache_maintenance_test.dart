import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../../helpers/conform_file_path.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_cache_maintenance.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

/// The conform cache's lifetime, and what it is allowed to touch.
///
/// Nothing ever collected it. A conform is about twelve times its source,
/// so a working month of dialogue quietly became gigabytes — and inside an
/// iPad's app container that is a pile the user can neither see nor empty,
/// growing until the device is full with no explanation attached.
///
/// The root is a SETTING with a Browse button, so the collector runs in a
/// folder somebody chose. Every deletion here is therefore a question
/// about ownership before it is a question about size.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('qa_conform_cache_');
    AppSave.settings.value = AppSaveSettings(
      conformDirectory: GrantedDirectory(path: root.path.replaceAll('\\', '/')),
    );
  });

  tearDown(() {
    AppSave.settings.value = const AppSaveSettings();
    try {
      root.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  var nextKey = 0;

  /// A file at [name] holding exactly [bytes].
  String writeRaw(String name, List<int> bytes, {int agoMinutes = 0}) {
    final file = File('${root.path}/$name')..writeAsBytesSync(bytes);
    file.setLastModifiedSync(
      DateTime.now().subtract(Duration(minutes: agoMinutes)),
    );
    return file.path.replaceAll('\\', '/');
  }

  /// 🚨**「ours」 is now the MAGIC, not a provenance chunk.**
  ///
  /// This used to build a WAV either way and hang the difference on our
  /// `qacf` chunk being present — because a conform WAS a WAV, so「not
  /// ours」 could be spelled as「the same file, minus our chunk」. It is not
  /// a WAV any more (see [ConformHeader]), so a file we did not write has
  /// to actually be one: a real 16-bit WAV, built by the writer the audio
  /// export uses.
  ///
  /// ⛔The old spelling would now pass: a conform written with no
  /// fingerprint still carries the magic, and it IS ours — we wrote it.
  Uint8List conformBytes({required bool ours, int frames = 64}) {
    if (ours) {
      return encodeConform(
        samples: Float32List(frames),
        channels: 1,
        sampleRate: 48000,
        fingerprint: ConformSourceFingerprint(
          sourceLength: frames,
          sourceCrc32: 7,
        ),
      );
    }
    return Uint8List.fromList([
      ...wav16HeaderBytes(
        dataBytes: frames * 2,
        sampleRate: 48000,
        channels: 1,
      ),
      ...Uint8List(frames * 2),
    ]);
  }

  /// A REAL cache entry: the name the layout gives one, and — the part
  /// that decides everything here — the bytes, provenance chunk and all.
  ///
  /// The collector identifies its own files by READING them, so a fixture
  /// of zeroes with the right name would exercise a path production never
  /// takes and pass while the guard did nothing.
  String writeEntry(String sourceName, {int frames = 64, int agoMinutes = 0}) {
    nextKey += 1;
    final key = nextKey.toRadixString(16).padLeft(8, '0');
    return writeRaw(
      '$sourceName.$key.wav',
      conformBytes(ours: true, frames: frames),
      agoMinutes: agoMinutes,
    );
  }

  int sizeOf(String path) => File(path).lengthSync();

  test('🚨a conform from BEFORE the header is still collected', () {
    // ⛔The gap that would have been silent. Conforms were WAVs until
    // 2026-08-30, and every machine that ran a previous build has a cache
    // full of them. No reader accepts one any more — it fails the magic
    // and is rebuilt, which is right — but a file the COLLECTOR cannot
    // recognise is a file it never deletes and never counts.
    //
    // ⇒ Those would have sat there for ever, invisible, which is the exact
    // unbounded pile this whole file exists to prevent. The legacy tag
    // check in `_isOurConform` is what stops that, and this is the only
    // thing that would go red if somebody removed it as dead code.
    final legacy = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF ....
      0x57, 0x41, 0x56, 0x45, // WAVE
      0x66, 0x6d, 0x74, 0x20, 16, 0, 0, 0, // 'fmt ' + size
      ...List<int>.filled(16, 0), // fmt body
      0x71, 0x61, 0x63, 0x66, 4, 0, 0, 0, // 'qacf' at offset 36
      1, 2, 3, 4,
      ...List<int>.filled(64, 0),
    ]);
    final path = writeRaw('옛대사.m4a.0badf00d.wav', legacy);

    expect(
      conformCacheEntries().map((entry) => entry.path),
      [path],
      reason: 'unrecognised means undeletable, and it never stops growing',
    );
    expect(clearConformCache(), legacy.length);
    expect(File(path).existsSync(), isFalse);
  });

  test('🚨 what the LAYOUT writes is what the COLLECTOR recognises', () {
    // The seam nobody was standing on. The layout names a conform and the
    // collector decides what is a conform, and if those two ever drift the
    // failure is silent in the worst direction: the cache stops being
    // collectable and grows without bound — which is the entire thing 4b
    // exists to prevent. Neither side's own tests can see it.
    final path = ConformCacheLayout.forAudio(
      sampleRate: 48000,
      speedNumerator: 1,
      speedDenominator: 1,
    ).conformPathFor('/somewhere/대사.m4a');
    File(path).writeAsBytesSync(conformBytes(ours: true));

    expect(
      conformCacheEntries().map((entry) => entry.path),
      [path.replaceAll('\\', '/')],
      reason:
          'a file written at the layout\'s own address, with the '
          'bytes the pipeline writes, has to be collectable',
    );
  });

  test('🚨 …INCLUDING when the pipeline compressed it', () {
    final compressor = QaCelCompressor.instance;
    if (compressor == null || !compressor.isSupported) {
      markTestSkipped('no engine on this run');
      return;
    }
    // The same seam as above, driven end to end. A conform is written
    // FRAMED when that is worth it, and the collector identifies its own
    // files by reading the conform MAGIC out of them — so a framed one
    // looks like a block index where the guard wanted that magic.
    //
    // ⛔The failure that would cause is silent in the worst direction: the
    // cache stops being collectable AND stops being counted, so the app
    // container grows without bound while the settings panel reports it as
    // empty. Neither the pipeline's tests nor the collector's own can see
    // that, which is exactly why it is tested here.
    final sourcePath = '${root.path}/원본.wav';
    File(sourcePath).writeAsBytesSync(
      encodeConform(
        // Long enough to cross a block boundary, and compressible — a
        // conform is PCM, and PCM is what the 38% measurement was taken on.
        samples: Float32List.fromList([
          for (var index = 0; index < 400000; index += 1)
            (index % 4096) / 4096.0 - 0.5,
        ]),
        channels: 1,
        sampleRate: 48000,
      ),
    );
    final layout = ConformCacheLayout.forAudio(
      sampleRate: 48000,
      speedNumerator: 1,
      speedDenominator: 1,
    );
    final result =
        AudioConformPipeline(
          decode: (source) {
            final bytes = source.readSync();
            final audio = decodeConform(bytes);
            return (
              samples: audio.samples,
              channels: audio.channels,
              sampleRate: audio.sampleRate,
            );
          },
          resample:
              ({
                required samples,
                required channels,
                required inputRate,
                required outputRate,
              }) => samples,
        ).ensureConform(
          sourcePath: sourcePath,
          conformPath: layout.conformPathFor(sourcePath),
        );

    expect(result.outcome, ConformOutcome.built);
    expect(
      conformFilePathOrNull(result.conformBytes),
      endsWith(mediaFramedEntrySuffix),
      reason: 'fixture: this audio compresses, so the write framed it',
    );
    final entries = conformCacheEntries();
    expect(
      entries.map((entry) => entry.path),
      contains(conformFilePathOrNull(result.conformBytes)),
      reason: 'the collector has to recognise what the pipeline wrote',
    );
    expect(
      conformCacheBytes(),
      greaterThan(0),
      reason:
          'and count it, or the panel shows an empty container that '
          'is not empty',
    );
    expect(clearConformCache(), greaterThan(0));
    expect(
      File(conformFilePathOrNull(result.conformBytes)!).existsSync(),
      isFalse,
    );
  });

  test('the SHIPPED budget is 2GB', () {
    // Every prune in this file injects its budget, so only this line reads
    // what production actually enforces — without it, a fat-fingered
    // constant (2MB, 2TB) keeps every suite green.
    expect(conformCacheBudgetBytes, 2 * 1024 * 1024 * 1024);
  });

  test('an absent cache measures zero rather than throwing', () {
    // The first run of a fresh install, and every run before any audio is
    // imported. Preferences asks for this number on open.
    root.deleteSync(recursive: true);
    expect(conformCacheEntries(), isEmpty);
    expect(conformCacheBytes(), 0);
    expect(pruneConformCache(), 0);
  });

  test('the size is the sum of what is there', () {
    final a = writeEntry('대사.m4a');
    final b = writeEntry('발소리.wav', frames: 256);
    expect(conformCacheBytes(), sizeOf(a) + sizeOf(b));
  });

  test('a cache inside the budget is left alone', () {
    final kept = writeEntry('대사.m4a');
    expect(pruneConformCache(budgetBytes: 5 * 1024 * 1024), 0);
    expect(File(kept).existsSync(), isTrue);
  });

  test('🚨 a WAV this app did not write is never counted and never '
      'collected, however it is named', () {
    // 🔑 The guard that was here first asked the NAME: `<x>.<8 hex>.wav`.
    // Hex digits include decimal ones, so a render called
    // `믹스.20260813.wav` matched — it was summed into the size shown in
    // Preferences and deleted by the button under it. A pattern that is
    // usually right is the worst kind of guard, because the case it gets
    // wrong is somebody's work.
    //
    // So ownership is read out of the file: our conforms carry a `qacf`
    // chunk, and nothing else writes one.
    final render = writeRaw('믹스.20260813.wav', conformBytes(ours: false));
    final notes = writeRaw('notes.txt', const [1, 2, 3]);
    final ours = writeEntry('대사.m4a', agoMinutes: 900);
    final ourBytes = sizeOf(ours);

    expect(
      conformCacheBytes(),
      ourBytes,
      reason:
          'a size counting their files promises to reclaim what it '
          'must never touch',
    );

    expect(clearConformCache(), ourBytes);
    expect(File(render).existsSync(), isTrue);
    expect(File(notes).existsSync(), isTrue);
    expect(File(ours).existsSync(), isFalse);
  });

  test('🚨 a dated folder of renders is not mistaken for a legacy cache '
      'folder', () {
    // The same hole one level up, and worse: the sweep deletes folders.
    // `믹스.20260813/` ends in a dot and eight hex-looking digits, so the
    // first guard matched it.
    //
    // ⚠️ The fixture holds nothing but WAVs on purpose. A dated folder of
    // renders is the realistic case AND the only one that reaches the
    // name test — a folder with a `.psd` in it is saved by the contents
    // check further down, which would mask a broken pattern here and let
    // a mutation of it survive. (Both layers have to be defeated for a
    // test to be measuring the one it names.)
    final dated = Directory('${root.path}/믹스.20260813')..createSync();
    File('${dated.path}/믹스_v3.wav').writeAsBytesSync(conformBytes(ours: false));

    pruneConformCache();

    expect(dated.existsSync(), isTrue);
    expect(File('${dated.path}/믹스_v3.wav').existsSync(), isTrue);
  });

  test('🚨 a folder named like ours but holding anything else stays whole', () {
    // The folder name is a strong hint and not proof — a directory cannot
    // be asked what wrote it. So the contents have to agree: an old cache
    // folder holds conforms and nothing else.
    final imposter = Directory('${root.path}/scene.anicel.0badf00d')
      ..createSync();
    File(
      '${imposter.path}/대사.m4a.wav',
    ).writeAsBytesSync(conformBytes(ours: true));
    File('${imposter.path}/작업.psd').writeAsBytesSync(const [8, 8, 8]);

    pruneConformCache();

    expect(imposter.existsSync(), isTrue);
    expect(
      File('${imposter.path}/대사.m4a.wav').existsSync(),
      isTrue,
      reason:
          'not even the part that does look like ours — the folder is '
          'evidently somebody else\'s',
    );
  });

  test('a plain folder is left alone', () {
    final theirs = Directory('${root.path}/작업중')..createSync();
    File('${theirs.path}/scene.anicel').writeAsBytesSync(const [1, 2, 3]);

    pruneConformCache();

    expect(theirs.existsSync(), isTrue);
    expect(File('${theirs.path}/scene.anicel').existsSync(), isTrue);
  });

  test('eviction takes the COLDEST first, not the oldest built', () {
    // The distinction is the whole reason reuse touches the file. A sound
    // used in every cut was built once, long ago; dropping it for that
    // would rebuild the entry that earns its keep the most and spare the
    // one imported by mistake and never played.
    final stale = writeEntry('한번쓴것.wav', agoMinutes: 600);
    final middling = writeEntry('가끔.wav', agoMinutes: 60);
    final hot = writeEntry('매컷에쓰는것.wav', agoMinutes: 1);
    final each = sizeOf(hot);

    expect(pruneConformCache(budgetBytes: each * 2), each);

    expect(File(stale).existsSync(), isFalse);
    expect(File(middling).existsSync(), isTrue);
    expect(File(hot).existsSync(), isTrue);
  });

  test('it keeps evicting until it actually fits', () {
    writeEntry('a.wav', agoMinutes: 300);
    writeEntry('b.wav', agoMinutes: 200);
    final hot = writeEntry('c.wav', agoMinutes: 1);
    final each = sizeOf(hot);

    expect(pruneConformCache(budgetBytes: each), each * 2);
    expect(conformCacheBytes(), each);
    expect(File(hot).existsSync(), isTrue);
  });

  test('the per-project folders an older build wrote are collected', () {
    // They are unreachable now — the cache is keyed by source, so nothing
    // will ever look inside one again. Leaving them would mean the pile
    // this exists to bound is partly made of entries it cannot see.
    final legacy = Directory('${root.path}/scene.anicel.0badf00d')
      ..createSync(recursive: true);
    final inside = File('${legacy.path}/대사.m4a.wav')
      ..writeAsBytesSync(conformBytes(ours: true));
    final insideBytes = inside.lengthSync();
    final current = writeEntry('대사.m4a');

    expect(pruneConformCache(), insideBytes);

    expect(legacy.existsSync(), isFalse);
    expect(
      File(current).existsSync(),
      isTrue,
      reason: 'the new flat entries are not what is being collected',
    );
  });

  test('emptying it removes everything of ours', () {
    final a = writeEntry('a.wav');
    final b = writeEntry('b.wav', frames: 128);
    final total = sizeOf(a) + sizeOf(b);

    expect(clearConformCache(), total);
    expect(conformCacheBytes(), 0);
  });

  test('a subdirectory is never counted as an entry', () {
    // conformCacheEntries feeds both the size shown in Preferences and the
    // eviction order; a directory in either would be a size nobody can
    // explain and a delete that fails every pass.
    Directory('${root.path}/scene.anicel.0badf00d').createSync();
    final ours = writeEntry('대사.m4a');
    expect(conformCacheEntries().map((entry) => entry.bytes), [sizeOf(ours)]);
  });
}
