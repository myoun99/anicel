import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

import '../../helpers/adts_from_m4a.dart';
import '../../helpers/decode_audio_file.dart';
import '../../helpers/encoded_movie.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/pcm_movie.dart';
import '../../helpers/project_scratch_folder.dart';

/// The OS decoder (AAC/m4a), driven for real against the platform codec
/// stack: Media Foundation here on Windows, AudioToolbox when this suite
/// runs on the macOS CI runner. The fixture is a generated 440 Hz sine at
/// -6 dB, 0.5 s, 44.1k stereo — so the assertions are physics, not
/// hand-waving: the rate and channel count must come back exactly, the
/// length within AAC's priming/padding slack, the mid-file peak near the
/// encoded amplitude.
///
/// Beside it, a movie's uncompressed sound, which the engine reads itself on
/// every platform (board mac-reads-no-movie-pcm): where a movie's sound
/// starts is one law whichever of the two read it.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final available = libraryPath != null;
  final skip = available ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaAudioDecoder.debugResetForTests();
    QaVideoEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaAudioDecoder.debugResetForTests();
    QaVideoEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  const fixturePath = 'test/fixtures/tone.m4a';
  Uint8List fixtureBytes() => File(fixturePath).readAsBytesSync();

  test('m4a decodes through the OS codec stack where one exists — and is '
      'honestly undecodable where none does', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull, reason: 'the binary did not bind');
    final decoded = decodeAudioFile(fixturePath);

    if (Platform.isLinux) {
      // Not a shipping platform and no OS codec to lean on: undecodable,
      // which is the definitive answer that leaves the waveform blank.
      expect(decoded, isNull);
      return;
    }

    expect(
      decoded,
      isNotNull,
      reason: 'the OS decoder should have carried this m4a',
    );
    expect(decoded!.format, QaAudioFormat.os);
    expect(decoded.sampleRate, 44100);
    expect(decoded.channels, 2);
    // 0.5 s at 44.1k = 22050 frames; AAC priming/padding moves the edges
    // by up to ~2 frames of 1024 samples either way.
    expect(decoded.length, inInclusiveRange(19000, 25000));

    // The signal itself: a -6 dB sine's peak, measured away from the
    // fade-prone edges. A wrong channel de-interleave or a wrong scale
    // convention fails this immediately.
    var peak = 0.0;
    final start = (decoded.length ~/ 4) * decoded.channels;
    final end = (3 * decoded.length ~/ 4) * decoded.channels;
    for (var index = start; index < end; index += 1) {
      peak = math.max(peak, decoded.samples[index].abs());
    }
    expect(
      peak,
      inInclusiveRange(0.35, 0.65),
      reason: 'expected roughly the encoded -6 dB amplitude, got $peak',
    );
  }, skip: skip);

  test('an m4a conforms END-TO-END: OS decode, resample to the project '
      'rate, peaks — the whole import chain in one call', () {
    final result = runConformHere(
      ConformRequest(
        sourcePath: 'test/fixtures/tone.m4a',
        conformPath: null, // memory-only, like an unsaved project
        libraryPathOverride: libraryPath,
      ),
    );

    if (Platform.isLinux) {
      expect(
        result.outcome,
        ConformOutcome.undecodable,
        reason:
            'no OS codec stack on the Linux runner — the definitive '
            'answer that routes m4a to the fallback there',
      );
      return;
    }

    expect(result.outcome, ConformOutcome.built);
    expect(
      result.sampleRate,
      48000,
      reason: '44.1k source must land at the project rate',
    );
    expect(result.channels, 2);
    // 0.5 s at 48k = 24000 frames, with AAC priming/padding slack.
    expect(result.frames, inInclusiveRange(21000, 27500));
    expect(result.samples, isNotNull);
    expect(result.peaks!.peaks, isNotEmpty);
    // The resampler must carry the -6 dB sine through unchanged.
    var peak = 0.0;
    for (final value in result.peaks!.peaks) {
      peak = math.max(peak, value);
    }
    expect(peak, inInclusiveRange(0.35, 0.65));
  }, skip: skip);

  test('ogg decodes through the BUNDLED stb_vorbis on every platform — '
      'the last format that used to lean on ffmpeg', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final decoded = decodeAudioFile('test/fixtures/tone.ogg');
    expect(
      decoded,
      isNotNull,
      reason: 'stb_vorbis is vendored — no platform stack involved',
    );
    expect(decoded!.format, QaAudioFormat.vorbis);
    expect(decoded.sampleRate, 44100);
    expect(decoded.channels, 2);
    expect(decoded.length, inInclusiveRange(20000, 24500));
    var peak = 0.0;
    final start = (decoded.length ~/ 4) * decoded.channels;
    final end = (3 * decoded.length ~/ 4) * decoded.channels;
    for (var index = start; index < end; index += 1) {
      peak = math.max(peak, decoded.samples[index].abs());
    }
    expect(peak, inInclusiveRange(0.35, 0.65));
  }, skip: skip);

  test('dr_libs formats never route to the OS path (wav stays byte-pinned '
      'on its single decoder)', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    // A tiny valid WAV — a FOREIGN format now, built by the writer the
    // export uses.
    final wav = wav16(
      Float32List.fromList(List.filled(4410 * 2, 0.25)),
      channels: 2,
      rate: 44100,
    );
    final decoded = decodeAudioBytes(wav);
    expect(decoded, isNotNull);
    expect(
      decoded!.format,
      QaAudioFormat.wav,
      reason: 'WAV must stay on dr_wav on every platform',
    );
  }, skip: skip);

  test('a movie\'s uncompressed sound is never dr_mp3\'s — the engine reads '
      'it itself, on every platform', () {
    // 🚨The head decides who may try (user 10-09, board
    // sound-lands-on-its-exact-sample-Q2). This movie's quiet half is what
    // dr_mp3 synced on before it did: 1,920 frames of noise at 44.1 kHz.
    // 🚨And no OS stack is asked (board mac-reads-no-movie-pcm): AudioToolbox
    // read nothing of this movie on the macOS CI runner (10-15), where Media
    // Foundation read it exactly — the C range test pins each way a writer
    // stores such a sound, and the control below what this one holds.
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final decoded = decodeAudioBytes(pcmMovie(_roomToneThenTone()));

    expect(
      decoded?.format,
      isNot(QaAudioFormat.mp3),
      reason: 'a QuickTime head must keep dr_mp3 away from the movie',
    );
    expect(decoded, isNotNull, reason: 'the engine reads it on every platform');
    expect(decoded!.format, QaAudioFormat.moviePcm);
    expect(decoded.sampleRate, 48000);
    expect(decoded.channels, 2);
  }, skip: skip);

  // -------------------------------------------------------------------------
  // 🚨★★★WHERE A SOUND STARTS (user 10-09, board
  // sound-lands-on-its-exact-sample-Q3 · Q4). An encoder puts frames of its
  // own before the sound; the file says how many, and the engine takes
  // exactly those off — whichever decoder read it, an OS stack or the
  // engine's own movie reader. The C range test pins the MP3 half (a LAME
  // tag, and the standard 1,105 without one).

  test('a movie\'s edit list says where its sound starts — taken to the '
      'frame, uncompressed so nothing smears, however the movie is laid '
      'out', () {
    final samples = _roomToneThenTone();
    const plays = (from: 480, keep: 24000);
    for (final (shape, movie) in [
      ('the edit alone', pcmMovie(samples, edits: [plays])),
      (
        // ⚠️Holding the track back places the sound later on the movie's
        // timeline; where the sound STARTS is still the edit that plays.
        'behind an empty edit',
        pcmMovie(samples, edits: [(from: -1, keep: 4800), plays]),
      ),
      (
        'in a long movie\'s shape',
        pcmMovie(samples, edits: [plays], long: true),
      ),
      (
        'after a timecode track with an edit list of its own',
        pcmMovie(samples, edits: [plays], timecodeFirst: true),
      ),
      (
        // Where it starts is the sound's clock, how long it plays the
        // movie's.
        'on QuickTime\'s movie clock of 600',
        pcmMovie(samples, edits: [plays], movieScale: 600),
      ),
    ]) {
      final decoded = decodeAudioBytes(movie);
      expect(decoded, isNotNull, reason: '$shape: the engine reads it');
      expect(decoded!.length, 24000, reason: '$shape: it plays 24,000 frames');
      for (var index = 0; index < 24000 * 2; index += 1) {
        final got = (decoded.samples[index] * 32768).round();
        if (got != samples[480 * 2 + index]) {
          fail('$shape: sample $index is $got, '
              'written ${samples[480 * 2 + index]}');
        }
      }
    }
  }, skip: skip);

  test('an m4a starts on its sound — the sine on frame 0, not 1,024 frames '
      'of its encoder\'s later — and runs as long as its edit list says', () {
    final decoded = decodeAudioFile(fixturePath);
    if (Platform.isLinux) {
      expect(decoded, isNull);
      return;
    }
    expect(decoded, isNotNull);
    expect(
      _sineLag(decoded!),
      0,
      reason: 'the edit list says the sound starts 1,024 frames in',
    );
    expect(decoded.length, 22050, reason: 'and plays half a second');
  }, skip: skip);

  test('a bare .aac has no box to say it in — the standard 1,024 comes off',
      () {
    // The m4a's own frames behind ADTS headers: the same 1,024 frames of
    // its encoder before the sound, and no edit list to say so — bare, and
    // behind the ID3 tag a ripped stream often carries.
    final adts = adtsFromM4a(fixtureBytes());
    final id3 = [0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 20, ...List.filled(20, 0)];
    for (final (shape, bytes) in [
      ('bare', adts),
      ('behind an ID3 tag', Uint8List.fromList([...id3, ...adts])),
    ]) {
      final decoded = decodeAudioBytes(bytes);
      if (Platform.isLinux) {
        expect(decoded, isNull, reason: shape);
        continue;
      }
      expect(decoded, isNotNull, reason: '$shape: the OS stack reads ADTS');
      expect(decoded!.format, QaAudioFormat.os, reason: shape);
      expect(_sineLag(decoded), 0, reason: shape);
    }
  }, skip: skip);

  test('🎯a movie that says nothing takes AAC\'s standard 1,024 off — the m4a '
      'without its edit list starts on the same frame as with it (user '
      '10-09, Q6: 「말하지 않는 MP4 · MOV 도 1,024 를 걷는다」)', () {
    final said = decodeAudioFile(fixturePath);
    final silent = decodeAudioBytes(
      _renamed(fixtureBytes(), ['moov', 'trak', 'edts'], 'free'),
    );
    if (Platform.isLinux) {
      expect((said, silent), (null, null));
      return;
    }
    expect(said, isNotNull);
    expect(silent, isNotNull, reason: 'a skipped box is no reason to refuse');
    for (var index = 0; index < said!.length * said.channels; index += 1) {
      if (silent!.samples[index] != said.samples[index]) {
        fail('sample $index is ${silent.samples[index]} without the edit '
            'list, ${said.samples[index]} with it');
      }
    }
  }, skip: skip);

  test('🎯a movie that says it only in the note iTunes leaves starts where '
      'the note says — Apple\'s 2,112, not the standard, and for as long as '
      'it says (Q3: 「말하면 그 값」)', () {
    // Against the same movie saying nothing, whose sound starts where the
    // edit list says (the test above) and runs to its end.
    final silent = _renamed(fixtureBytes(), ['moov', 'trak', 'edts'], 'free');
    final standard = decodeAudioBytes(silent);
    for (final (shape, bytes, length) in [
      ('in ISO\'s meta', _withITunesNote(silent, _appleNote), 20962),
      (
        'in QuickTime\'s meta',
        _withITunesNote(silent, _appleNote, fullBox: false),
        20962,
      ),
      (
        // A length of 0 says none: it runs to the end too.
        'with no length in it',
        _withITunesNote(
          silent,
          _appleNote.replaceFirst('00000000000051E2', '0' * 16),
        ),
        null,
      ),
    ]) {
      final told = decodeAudioBytes(bytes);
      if (Platform.isLinux) {
        expect((standard, told), (null, null), reason: shape);
        continue;
      }
      expect(standard, isNotNull);
      expect(told, isNotNull, reason: '$shape: a note is no reason to refuse');
      expect(
        told!.length,
        length ?? standard!.length - 1088,
        reason: '$shape: it plays what it says',
      );
      final channels = standard!.channels;
      for (var index = 0; index < told.length * channels; index += 1) {
        if (told.samples[index] != standard.samples[index + 1088 * channels]) {
          fail('$shape: sample $index is not the standard\'s '
              '${index + 1088 * channels}');
        }
      }
    }
  }, skip: skip);

  test('⚠️where the sound track has an edit list, the edit list says it — a '
      'note beside it is not read', () {
    final said = decodeAudioFile(fixturePath);
    final both = decodeAudioBytes(_withITunesNote(fixtureBytes(), _appleNote));
    if (Platform.isLinux) {
      expect((said, both), (null, null));
      return;
    }
    expect(said, isNotNull);
    expect(both, isNotNull);
    expect(both!.length, said!.length);
    for (var index = 0; index < said.length * said.channels; index += 1) {
      if (both.samples[index] != said.samples[index]) {
        fail('sample $index is not the edit list\'s');
      }
    }
  }, skip: skip);

  test('🎯unless Media Foundation wrote it: the mark its writer leaves keeps '
      'the standard off — the same movie without the mark starts one AAC '
      'frame later (user 10-09, Q7: 「윈도 기록기의 표지가 있으면 걷지 '
      '않는다」)', () {
    final bytes = File('test/fixtures/tone_with_video.mp4').readAsBytesSync();
    final marked = decodeAudioBytes(bytes);
    final unmarked = decodeAudioBytes(_renamed(bytes, ['uuid'], 'free'));
    if (Platform.isLinux) {
      expect((marked, unmarked), (null, null));
      return;
    }
    expect(marked, isNotNull);
    expect(unmarked, isNotNull);
    expect(unmarked!.length, marked!.length - 1024);
    final channels = marked.channels;
    for (var index = 0; index < unmarked.length * channels; index += 1) {
      if (unmarked.samples[index] != marked.samples[index + 1024 * channels]) {
        fail('sample $index without the mark is not the marked one\'s '
            '${index + 1024 * channels}');
      }
    }
  }, skip: skip);

  test('⛔CONTROL: a movie of uncompressed sound that says nothing loses '
      'nothing — its format has no delay to take', () {
    final samples = _roomToneThenTone();
    final decoded = decodeAudioBytes(pcmMovie(samples));
    expect(decoded!.length, samples.length ~/ 2, reason: 'not a frame more');
    // Every sample is the one written, so the first lands on frame 0 and the
    // tone on its own frame.
    for (var index = 0; index < samples.length; index += 1) {
      final got = (decoded.samples[index] * 32768).round();
      if (got != samples[index]) {
        fail('sample $index is $got, written ${samples[index]}');
      }
    }
  }, skip: skip);

  test('🔬AAC in a QuickTime movie decodes as the m4a does — or says this '
      'stack does not read a QuickTime movie\'s AAC either (board '
      'mac-reads-no-movie-pcm: whether a Mac refuses a movie\'s PCM for the '
      'sound or for the movie)', () {
    final m4a = decodeAudioFile(fixturePath);
    final movie = decodeAudioBytes(_quickTimeBranded(fixtureBytes()));
    if (Platform.isLinux) {
      expect((m4a, movie), (null, null));
      return;
    }
    expect(m4a, isNotNull);
    if (movie == null && !Platform.isWindows) {
      markTestSkipped('this OS stack does not read a QuickTime movie\'s AAC');
      return;
    }
    expect(movie, isNotNull, reason: 'Media Foundation reads a QuickTime one');
    expect(movie!.length, m4a!.length);
    for (var index = 0; index < m4a.length * m4a.channels; index += 1) {
      if (movie.samples[index] != m4a.samples[index]) {
        fail('sample $index is not the m4a\'s');
      }
    }
  }, skip: skip);

  test('a movie this app exported comes back with its sound where it was '
      'written — whichever OS wrote it', () {
    // Media Foundation's encoder writes no edit list, and its sound is
    // already in place (measured 10-09) — its mark keeps the standard delay
    // off (Q7). Wherever else this runs (the Mac's AVAssetWriter in CI), the
    // export must say where its sound starts some way the decode reads, or
    // the standard comes off a sound that had none: this is the pin that
    // asks.
    final directory = Directory.systemTemp.createTempSync('qa_export_click');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}click.mp4';
    const rate = 48000;
    const clickAt = rate ~/ 4;
    if (!writeEncodedMovie(
      path,
      frames: 24,
      sampleRate: rate,
      sound: (sample) {
        final index = sample - clickAt;
        // A decaying click, so the codec keeps it.
        return index < 0 || index >= 48
            ? 0
            : ((index.isEven ? 1 : -1) * 30000 * (1 - index / 48)).round();
      },
    )) {
      return;
    }

    final decoded = decodeAudioFile(path);
    expect(decoded, isNotNull);
    var peakAt = -1;
    var peak = 0.0;
    for (var index = 0; index < decoded!.length; index += 1) {
      final value = decoded.samples[index * decoded.channels].abs();
      if (value > peak) {
        peak = value;
        peakAt = index;
      }
    }
    expect(
      peakAt,
      inInclusiveRange(clickAt - 2, clickAt + 2),
      reason: 'the click came back at $peakAt, written at $clickAt',
    );
  }, skip: skip);

  test('a window of a sound is the whole decode\'s own frames, and only '
      'those are held — a movie\'s PCM, an m4a, an ogg', () {
    // 🚨Q5 (user 10-09): a piece cut from a long reel holds the piece. Every
    // decoder decodes from the start and keeps the window, so a window must
    // be the whole decode's frames exactly — through the edit list's lead,
    // the m4a's 1,024, whichever stack decoded it.
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final directory = Directory.systemTemp.createTempSync('qa_window');
    deleteAfterSessionEnds(directory);
    final movie = pcmMovie(
      _roomToneThenTone(),
      edits: [(from: 480, keep: 24000)],
    );
    for (final (what, bytes) in [
      ('a movie\'s PCM', movie),
      ('an m4a', fixtureBytes()),
      ('an ogg', File('test/fixtures/tone.ogg').readAsBytesSync()),
    ]) {
      final path = '${directory.path}${Platform.pathSeparator}sound';
      File(path).writeAsBytesSync(bytes);
      QaDecodedAudio? decode([({int start, int count})? window]) =>
          decoder!.decodeSpan(
            (path: path, offset: 0, length: bytes.length, framed: false),
            window: window,
          );
      final whole = decode();
      if (whole == null) {
        expect(Platform.isLinux, isTrue, reason: '$what: nothing decoded it');
        continue;
      }
      final channels = whole.channels;

      final probe = decode((start: 0, count: 0));
      expect(probe, isNotNull, reason: '$what: the probe answers');
      expect(probe!.length, 0, reason: '$what: and holds nothing');
      expect(probe.sampleRate, whole.sampleRate, reason: what);
      expect(probe.channels, channels, reason: what);
      expect(probe.format, whole.format, reason: what);

      final inside = decode((start: 1000, count: 5000))!;
      expect(inside.length, 5000, reason: '$what: the window, no more');
      expect(
        inside.samples,
        orderedEquals(whole.samples.sublist(1000 * channels, 6000 * channels)),
        reason: '$what: the whole decode\'s own frames',
      );

      final past = decode((start: whole.length + 10, count: 100));
      expect(past, isNotNull, reason: '$what: past the end is silence');
      expect(past!.length, 0, reason: what);
    }
  }, skip: skip);

  // -------------------------------------------------------------------------
  // A container that is a RANGE of a file.
  //
  // 🚨★★★What the C test next door CANNOT reach: it builds a WAV, so it never
  // gets past dr_wav and the OS stack's own range plumbing — an
  // `IMFByteStream` on Windows, resource-loader callbacks on Apple — is never
  // asked anything. These fixtures are real encoded files, so they are.

  /// Writes [bytes] into a file with junk on both sides, and says where they
  /// landed. The junk is the point: an offset that is ignored reads it.
  ({String path, int offset, int length}) buried(
    Uint8List bytes,
    String name,
  ) {
    const prefix = 4096;
    final directory = Directory.systemTemp.createTempSync('qa_range');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}$name';
    final sink = File(path).openSync(mode: FileMode.write);
    sink.writeFromSync(
      Uint8List.fromList(List.generate(prefix, (i) => (i * 13 + 7) & 0xFF)),
    );
    sink.writeFromSync(bytes);
    sink.writeFromSync(
      Uint8List.fromList(List.generate(512, (i) => (i * 29 + 3) & 0xFF)),
    );
    sink.closeSync();
    return (path: path, offset: prefix, length: bytes.length);
  }

  test('an ogg inside a bigger file decodes from its RANGE, identically to '
      'the same file read whole', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final bytes = File('test/fixtures/tone.ogg').readAsBytesSync();
    final at = buried(bytes, 'carried.ogg');

    final ranged = decoder!.decodeSpan((
      path: at.path,
      offset: at.offset,
      length: at.length,
      framed: false,
    ));
    expect(
      ranged,
      isNotNull,
      reason: 'stb_vorbis reads a FILE section — no platform stack involved, '
          'so this must hold on every runner including Linux',
    );
    expect(ranged!.format, QaAudioFormat.vorbis);

    // Byte-for-byte the same answer as the whole file. ⛔If these ever
    // differ, the range path has quietly become a second decoder.
    final assembled = decodeAudioFile('test/fixtures/tone.ogg')!;
    expect(ranged.channels, assembled.channels);
    expect(ranged.sampleRate, assembled.sampleRate);
    expect(ranged.samples.length, assembled.samples.length);
    expect(ranged.samples, orderedEquals(assembled.samples));
  }, skip: skip);

  test('an m4a inside a bigger file decodes from its RANGE through the OS '
      'codec stack', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final at = buried(fixtureBytes(), 'carried.m4a');
    final ranged = decoder!.decodeSpan((
      path: at.path,
      offset: at.offset,
      length: at.length,
      framed: false,
    ));

    if (Platform.isLinux) {
      // No OS codec to lean on — undecodable, the same honest answer the
      // whole file gives there.
      expect(ranged, isNull);
      return;
    }

    expect(
      ranged,
      isNotNull,
      reason: 'the OS decoder must reach a container that starts at an '
          'offset — this is the whole carried-media case',
    );
    expect(ranged!.format, QaAudioFormat.os);
    expect(ranged.sampleRate, 44100);
    expect(ranged.channels, 2);
    expect(ranged.length, inInclusiveRange(19000, 25000));
    var peak = 0.0;
    final start = (ranged.length ~/ 4) * ranged.channels;
    final end = (3 * ranged.length ~/ 4) * ranged.channels;
    for (var index = start; index < end; index += 1) {
      peak = math.max(peak, ranged.samples[index].abs());
    }
    expect(
      peak,
      inInclusiveRange(0.35, 0.65),
      reason: 'the range must carry the same sine, not the junk around it',
    );
  }, skip: skip);

  test('a sound INSIDE the project file conforms end to end — source range, '
      'streamed fingerprint, decode in place', () {
    // 🚨★★★THE WHOLE CHAIN THIS ROUND EXISTS FOR, in one call: the source
    // says where its bytes are, the identity check streams them, and the
    // decoder is pointed at the span rather than handed a copy. A movie's
    // soundtrack is this same case with a bigger container.
    final at = buried(fixtureBytes(), 'carried.m4a');
    final result = runConformHere(
      ConformRequest(
        sourcePath: 'carried.m4a',
        conformPath: null, // memory-only, like an unsaved project
        source: MediaArchiveBytes(
          archivePath: at.path,
          dataOffset: at.offset,
          length: at.length,
        ),
        libraryPathOverride: libraryPath,
      ),
    );

    if (Platform.isLinux) {
      expect(result.outcome, ConformOutcome.undecodable);
      return;
    }

    expect(
      result.outcome,
      ConformOutcome.built,
      reason: 'reason: ${result.error}',
    );
    expect(result.sampleRate, 48000, reason: 'lands at the project rate');
    expect(result.channels, 2);
    expect(result.frames, inInclusiveRange(21000, 27500));
    var peak = 0.0;
    for (final value in result.peaks!.peaks) {
      peak = math.max(peak, value);
    }
    expect(
      peak,
      inInclusiveRange(0.35, 0.65),
      reason: 'the -6 dB sine has to survive being read out of the middle '
          'of a bigger file',
    );
  }, skip: skip);

  test('a movie WITH A VIDEO TRACK gives up its soundtrack — whole file and '
      'from a range', () {
    // 🚨★★★**THE ONE THING THE m4a FIXTURE COULD NOT PROVE.** Every other
    // test here uses audio-only containers, so 「the OS reader picks the
    // AUDIO stream out of a file that also has video」 was standard
    // behaviour this repo had never run — and it is the entire point of
    // letting the conform see a movie. `tone_with_video.mp4` is 0.5 s of
    // 64x48 H.264 with the same 440 Hz sine at -6 dB, written by this app's
    // OWN encoder so the fixture needs no outside tool to regenerate.
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final bytes = File('test/fixtures/tone_with_video.mp4').readAsBytesSync();
    final at = buried(bytes, 'carried.mp4');

    final whole = decodeAudioFile('test/fixtures/tone_with_video.mp4');
    final ranged = decoder!.decodeSpan((
      path: at.path,
      offset: at.offset,
      length: at.length,
      framed: false,
    ));

    if (Platform.isLinux) {
      // No OS codec stack — the same honest answer as every other AAC here.
      expect(whole, isNull);
      expect(ranged, isNull);
      return;
    }

    for (final (what, decoded) in [
      ('the whole file', whole),
      ('a range inside a bigger file', ranged),
    ]) {
      expect(decoded, isNotNull, reason: '$what: nothing came back');
      expect(decoded!.format, QaAudioFormat.os, reason: what);
      expect(decoded.sampleRate, 44100, reason: what);
      expect(decoded.channels, 2, reason: what);
      expect(decoded.length, inInclusiveRange(19000, 25000), reason: what);
      var peak = 0.0;
      final start = (decoded.length ~/ 4) * decoded.channels;
      final end = (3 * decoded.length ~/ 4) * decoded.channels;
      for (var index = start; index < end; index += 1) {
        peak = math.max(peak, decoded.samples[index].abs());
      }
      expect(
        peak,
        inInclusiveRange(0.35, 0.65),
        reason: '$what: expected the -6 dB sine, got $peak — a reader that '
            'handed back the VIDEO stream, or silence, fails here',
      );
    }
  }, skip: skip);

  test('a movie conforms like any other sound — the round\'s whole claim, '
      'end to end', () {
    final at = buried(
      File('test/fixtures/tone_with_video.mp4').readAsBytesSync(),
      'carried.mp4',
    );
    final result = runConformHere(
      ConformRequest(
        sourcePath: 'reference.mp4',
        conformPath: null,
        source: MediaArchiveBytes(
          archivePath: at.path,
          dataOffset: at.offset,
          length: at.length,
        ),
        libraryPathOverride: libraryPath,
      ),
    );

    if (Platform.isLinux) {
      expect(result.outcome, ConformOutcome.undecodable);
      return;
    }

    expect(
      result.outcome,
      ConformOutcome.built,
      reason: 'reason: ${result.error}',
    );
    expect(result.sampleRate, 48000);
    expect(result.channels, 2);
    var peak = 0.0;
    for (final value in result.peaks!.peaks) {
      peak = math.max(peak, value);
    }
    expect(peak, inInclusiveRange(0.35, 0.65));
  }, skip: skip);

  test('a range that is not inside the file is refused, and the junk around '
      'a container is not audio', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final bytes = File('test/fixtures/tone.ogg').readAsBytesSync();
    final at = buried(bytes, 'carried.ogg');

    expect(
      decoder!.decodeSpan((
        path: at.path,
        offset: at.offset,
        length: at.length + 4096,
        framed: false,
      )),
      isNull,
      reason: 'a container cut short decodes as corrupt — refusing says what '
          'actually went wrong',
    );
    // ⛔The assertion the offset dies on: reading from the start of the file
    // finds the junk, not the ogg.
    expect(
      decoder.decodeSpan(
        (path: at.path, offset: 0, length: at.length, framed: false),
      ),
      isNull,
    );
  }, skip: skip);

  // -------------------------------------------------------------------------
  // A container kept FRAMED — compressed in blocks, the shape a carried
  // movie takes when it shrinks (board `carried-movie-compressed`).
  //
  // 🚨★★★The OS stack is fed the blocks DECODED, through the engine's span
  // reader: an `IMFByteStream` on Windows, the resource loader on Apple. The
  // fixture is a real movie, so that plumbing is asked everything a real
  // movie asks of it.

  /// The real movie at [fixture] with a `free` box of zeros after it — so it
  /// shrinks, and the writer that ships keeps it FRAMED — written where a
  /// staged copy would be. A `free` box is part of the format: every reader
  /// skips one, so the movie in front of it is untouched.
  String framedMovie(String fixture) {
    const padding = 1024 * 1024;
    final box = ByteData(8)
      ..setUint32(0, 8 + padding)
      ..setUint8(4, 0x66) // f
      ..setUint8(5, 0x72) // r
      ..setUint8(6, 0x65) // e
      ..setUint8(7, 0x65); // e
    final bytes = (BytesBuilder(copy: false)
          ..add(File(fixture).readAsBytesSync())
          ..add(box.buffer.asUint8List())
          ..add(Uint8List(padding)))
        .takeBytes();
    final directory = Directory.systemTemp.createTempSync('qa_framed');
    deleteAfterSessionEnds(directory);
    final written = writeMediaBlob(
      basePath: '${directory.path}${Platform.pathSeparator}carried.mp4',
      length: bytes.length,
      readInto: mediaBytesReader(bytes),
    );
    expect(written.framed, isTrue, reason: 'fixture: the free box shrinks');
    return written.path;
  }

  test('🚨a movie kept FRAMED gives up its soundtrack through the OS stack — '
      'the carried movie that shrank', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final path = framedMovie('test/fixtures/tone_with_video.mp4');

    final decoded = decoder!.decodeSpan((
      path: path,
      offset: 0,
      length: File(path).lengthSync(),
      framed: true,
    ));

    if (Platform.isLinux) {
      expect(decoded, isNull);
      return;
    }
    expect(
      decoded,
      isNotNull,
      reason: 'the OS reader must be fed the blocks decoded, not the blocks',
    );
    expect(decoded!.format, QaAudioFormat.os);
    expect(decoded.sampleRate, 44100);
    expect(decoded.channels, 2);
    expect(decoded.length, inInclusiveRange(19000, 25000));
    var peak = 0.0;
    final start = (decoded.length ~/ 4) * decoded.channels;
    final end = (3 * decoded.length ~/ 4) * decoded.channels;
    for (var index = start; index < end; index += 1) {
      peak = math.max(peak, decoded.samples[index].abs());
    }
    expect(peak, inInclusiveRange(0.35, 0.65));
  }, skip: skip);

  test('and it conforms end to end from where the project keeps it', () {
    final result = runConformHere(
      ConformRequest(
        sourcePath: 'reference.mp4',
        conformPath: null,
        source: mediaAppFileSource(
          framedMovie('test/fixtures/tone_with_video.mp4'),
        ),
        libraryPathOverride: libraryPath,
      ),
    );

    if (Platform.isLinux) {
      expect(result.outcome, ConformOutcome.undecodable);
      return;
    }
    expect(
      result.outcome,
      ConformOutcome.built,
      reason: 'reason: ${result.error}',
    );
    expect(result.sampleRate, 48000);
    expect(result.channels, 2);
    var peak = 0.0;
    for (final value in result.peaks!.peaks) {
      peak = math.max(peak, value);
    }
    expect(peak, inInclusiveRange(0.35, 0.65));
  }, skip: skip);

  test('🎯a sound opened as a stream and read a piece at a time is the whole '
      'decode — a movie\'s PCM through its edit list, an m4a through the OS '
      'stack, an ogg, a movie kept framed', () {
    // A conform is made from the stream (user 10-10, board
    // long-sound-conform-memory-Q1), so its pieces — of any size, across the
    // decoders' own blocks — must be the whole decode's frames exactly, the
    // lead the file says counted once.
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final directory = Directory.systemTemp.createTempSync('qa_stream');
    deleteAfterSessionEnds(directory);
    MediaSpan written(String name, Uint8List bytes) {
      final path = '${directory.path}${Platform.pathSeparator}$name';
      File(path).writeAsBytesSync(bytes);
      return (path: path, offset: 0, length: bytes.length, framed: false);
    }

    final movie = pcmMovie(
      _roomToneThenTone(),
      edits: [(from: 480, keep: 24000)],
    );
    final framed = framedMovie('test/fixtures/tone_with_video.mp4');
    for (final (what, span) in [
      ('a movie\'s PCM', written('pcm.mov', movie)),
      ('an m4a', written('tone.m4a', fixtureBytes())),
      (
        'an ogg',
        written('tone.ogg', File('test/fixtures/tone.ogg').readAsBytesSync()),
      ),
      (
        'a movie kept framed',
        (
          path: framed,
          offset: 0,
          length: File(framed).lengthSync(),
          framed: true,
        ),
      ),
    ]) {
      final whole = decoder!.decodeSpan(span);
      final stream = decoder.openSpan(span);
      if (whole == null) {
        expect(Platform.isLinux, isTrue, reason: '$what: nothing decoded it');
        expect(stream, isNull, reason: '$what: nor opened it');
        continue;
      }
      expect(
        (stream!.format, stream.channels, stream.sampleRate),
        (whole.format, whole.channels, whole.sampleRate),
        reason: what,
      );
      final read = <double>[];
      const pieces = [1, 7, 333, 4096, 5000, 2];
      for (var turn = 0; ; turn += 1) {
        final piece = stream.read(pieces[turn % pieces.length]);
        if (piece.isEmpty) {
          break;
        }
        read.addAll(piece);
      }
      expect(stream.read(16), isEmpty, reason: '$what: nothing past the end');
      stream.close();
      expect(
        read,
        orderedEquals(whole.samples),
        reason: '$what: the whole decode\'s own frames',
      );
    }
  }, skip: skip);
}

/// A real 16-bit PCM WAV — a FOREIGN format to this app now.
///
/// ⚠️This used to be `encodeConformWav`, which worked only while a conform
/// happened to be a WAV. It stopped being one on 2026-08-30, so the fixture
/// says what it means: build the thing the decoder is supposed to read.
Uint8List wav16(Float32List samples, {int channels = 1, int rate = 48000}) {
  final pcm = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(pcm);
  for (var i = 0; i < samples.length; i += 1) {
    var v = samples[i];
    if (v > 1.0) v = 1.0;
    if (v < -1.0) v = -1.0;
    var s = (v * 32768.0).round();
    if (s > 32767) s = 32767;
    view.setInt16(i * 2, s, Endian.little);
  }
  return Uint8List.fromList([
    ...wav16HeaderBytes(
      dataBytes: pcm.length,
      sampleRate: rate,
      channels: channels,
    ),
    ...pcm,
  ]);
}

/// One second of 48 kHz stereo: half a second of room tone — the few steps
/// either side of zero a quiet stretch of a recording has — then a 440 Hz
/// tone at -6 dB.
Int16List _roomToneThenTone() {
  const frames = 48000;
  final dither = math.Random(1);
  final samples = Int16List(frames * 2);
  for (var frame = 0; frame < frames; frame += 1) {
    for (var channel = 0; channel < 2; channel += 1) {
      samples[frame * 2 + channel] = frame < frames ~/ 2
          ? dither.nextInt(6) - 3
          : (math.sin(2 * math.pi * 440 * (frame - frames ~/ 2) / 48000) *
                  0.5 *
                  32767)
              .round();
    }
  }
  return samples;
}

/// Where the box at [path] starts in [bytes] — each the first box of that
/// type inside the one before it, from the file's top level.
int _boxAt(Uint8List bytes, List<String> path) {
  final data = ByteData.sublistView(bytes);
  var start = 0;
  var end = bytes.length;
  var at = -1;
  for (final type in path) {
    at = -1;
    for (var box = start; box + 8 <= end;) {
      if (String.fromCharCodes(bytes, box + 4, box + 8) == type) {
        at = box;
        break;
      }
      final size = data.getUint32(box);
      if (size < 8) {
        break;
      }
      box += size;
    }
    expect(at, isNot(-1), reason: 'no $type on the way to ${path.join('/')}');
    start = at + 8;
    end = at + data.getUint32(at);
  }
  return at;
}

/// [bytes] with the box at [path] ([_boxAt]) renamed [to], its size kept: a
/// `free` box, which every reader skips, takes what it said away and moves
/// no other byte.
Uint8List _renamed(Uint8List bytes, List<String> path, String to) {
  final at = _boxAt(bytes, path);
  return Uint8List.fromList(bytes)..setRange(at + 4, at + 8, to.codeUnits);
}

/// The m4a [bytes] as a QuickTime movie — every brand of its `ftyp`
/// QuickTime's (`qt  `), as an iPhone's or QuickTime's movie says — with its
/// user data set aside (`free`), whose `meta` is ISO's shape. Every other
/// byte is the m4a's: the boxes its sound is read by are the same in both.
Uint8List _quickTimeBranded(Uint8List bytes) {
  final ftyp = _boxAt(bytes, ['ftyp']);
  final end = ftyp + ByteData.sublistView(bytes).getUint32(ftyp);
  final branded = _renamed(bytes, ['moov', 'udta'], 'free');
  // The major brand, then the compatible ones after the minor version.
  for (final at in [ftyp + 8, for (var at = ftyp + 16; at < end; at += 4) at]) {
    branded.setRange(at, at + 4, 'qt  '.codeUnits);
  }
  return branded;
}

/// The gapless note Apple's encoder would leave on the fixture's sound: 2,112
/// frames before it (0x840) and 20,962 of it (0x51E2) — the fixture's own
/// sound from its 1,088th frame on, since its encoder put 1,024 there.
const _appleNote = ' 00000000 00000840 000001DE 00000000000051E2 00000000 '
    '00000000 00000000 00000000 00000000 00000000 00000000 00000000';

/// The loudness note iTunes leaves ahead of the gapless one — words of
/// hexadecimal too: a reading that took it for the gapless note would start
/// the sound 331 frames in (0x14B).
const _appleLoudness = ' 0000014B 0000014B 00000C26 00000C26 00000000 '
    '00000000 00007F2F 00007F2F 00000000 00000000';

/// [bytes] — a movie whose movie box comes last, so that growing it moves no
/// sample — with its user data set aside (`free`) and new user data at the
/// movie box's end: a metadata list holding iTunes' loudness note and then
/// its gapless note, [text], as iTunes writes them. Its `meta` is ISO's,
/// with four bytes of version and flags, or QuickTime's, without
/// ([fullBox]).
Uint8List _withITunesNote(Uint8List bytes, String text, {bool fullBox = true}) {
  final moov = _boxAt(bytes, ['moov']);
  final moovEnd = moov + ByteData.sublistView(bytes).getUint32(moov);
  expect(moovEnd, bytes.length, reason: 'fixture: the movie box is last');
  List<int> box(String type, List<int> body) => [
    ...(ByteData(4)..setUint32(0, 8 + body.length)).buffer.asUint8List(),
    ...type.codeUnits,
    ...body,
  ];
  const flags = [0, 0, 0, 0];
  List<int> note(String name, String says) => box('----', [
    ...box('mean', [...flags, ...'com.apple.iTunes'.codeUnits]),
    ...box('name', [...flags, ...name.codeUnits]),
    ...box('data', [0, 0, 0, 1, ...flags, ...says.codeUnits]),
  ]);
  final udta = box('udta', [
    ...box('meta', [
      if (fullBox) ...flags,
      ...box('hdlr', [
        ...flags,
        ...flags,
        ...'mdirappl'.codeUnits,
        ...List.filled(9, 0),
      ]),
      ...box('ilst', [
        ...note('iTunNORM', _appleLoudness),
        ...note('iTunSMPB', text),
      ]),
    ]),
  ]);
  final grown = Uint8List.fromList([
    ..._renamed(bytes, ['moov', 'udta'], 'free'),
    ...udta,
  ]);
  ByteData.sublistView(grown).setUint32(moov, moovEnd - moov + udta.length);
  return grown;
}

/// The lag, within [range] frames either way, at which [decoded]'s first
/// channel best matches the fixtures' 440 Hz sine at -6 dB from frame 0 —
/// measured on its middle half. ⚠️Kept inside half a period (100 frames at
/// 44.1 kHz): a whole period further looks the same.
int _sineLag(QaDecodedAudio decoded, {int range = 48}) {
  var best = 0;
  var bestError = double.infinity;
  for (var lag = -range; lag <= range; lag += 1) {
    var error = 0.0;
    for (var frame = decoded.length ~/ 4;
        frame < decoded.length * 3 ~/ 4;
        frame += 3) {
      final want =
          0.5 * math.sin(2 * math.pi * 440 * frame / decoded.sampleRate);
      final got = decoded.samples[(frame + lag) * decoded.channels];
      error += (got - want) * (got - want);
    }
    if (error < bestError) {
      bestError = error;
      best = lag;
    }
  }
  return best;
}
