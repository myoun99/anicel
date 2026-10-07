// THE BOARD'S DOOR — where the server listens, whom it lets in, and how a
// tool on another machine reaches it.
//
// 유저 2026-10-07 (card the-board-is-one-server-for-both-machines; 답 「집
// 네트워크에서 보드 서버를 연다」, 「서피스는 집에서만 쓸거야. 컴은 랜선
// 서피스들은 같은 모뎀?에서 흘러오는 와이파이」): a second machine does the
// work on another account, so no session message reaches it, and it holds no
// copy of the records. The board stays ONE file on ONE machine, and the
// server is the way in — for reading it, and for writing to it.
//
// ⛔OPEN AND UNLOCKED IS NOT A STATE THIS FILE CAN SPELL. Until this change
// the server had no authentication at all, which was sound only because it
// listened on loopback. A door to the network exists as a value only together
// with its secret ([LanDoor]), and [doorAsked] makes one only from a secret
// long enough to be one — so there is no order of flags, edits or restarts
// in which the board listens beyond this machine without asking who is
// there.
//
// ⚠️Imports nothing of ours: `board_up.sh` and `sourcesOfEntry` follow an
// entry's imports ONE level, so a file an entry imports must not hide a
// second level behind it.
import 'dart:convert';
import 'dart:io';

/// Where the board listens.
sealed class BoardDoor {
  const BoardDoor();
}

/// This machine only — how the board was served from its first day.
final class LoopbackDoor extends BoardDoor {
  const LoopbackDoor();
}

/// The home network. Whoever is not this machine shows [secret] with every
/// request.
final class LanDoor extends BoardDoor {
  const LanDoor(this.secret);

  final String secret;
}

/// A secret shorter than this is a word, not a secret: 32 hex digits are 128
/// bits, past guessing on a network that lets four machines in.
const kDoorSecretLength = 32;

/// The cookie a browser keeps the secret in once it has shown it.
const kDoorCookie = 'board';

/// The door a launch asked for.
///
/// ⚠️A launch that asks for the network and cannot be given it gets the
/// LOOPBACK door and a [complaint] — never no board. The machine the board
/// lives on goes on working, and what stays shut is the part that needed the
/// secret: failing closed for the network and open for this machine.
({BoardDoor door, String? complaint}) doorAsked(
  String? openTo,
  String? secretFile, {
  String? Function(String path)? read,
}) {
  if (openTo == null) return (door: const LoopbackDoor(), complaint: null);
  if (openTo != 'lan') {
    return (
      door: const LoopbackDoor(),
      complaint: '--open-to 는 lan 하나만 압니다(받은 것: $openTo) — '
          '이 기계에서만 엽니다.',
    );
  }
  final readFile = read ??
      (path) {
        final file = File(path);
        return file.existsSync() ? file.readAsStringSync() : null;
      };
  final secret = secretFile == null ? null : readFile(secretFile)?.trim();
  if (secret == null || secret.length < kDoorSecretLength) {
    return (
      door: const LoopbackDoor(),
      complaint: '--open-to lan 은 --token-file 의 비밀값이 있어야 합니다'
          '($kDoorSecretLength자 이상 — ${secretFile ?? '경로 없음'}) — '
          '이 기계에서만 엽니다.',
    );
  }
  return (door: LanDoor(secret), complaint: null);
}

/// The address a server behind [door] listens on: every interface of this
/// machine for the network door, loopback alone for the other.
InternetAddress doorListensOn(BoardDoor door) => switch (door) {
  LoopbackDoor() => InternetAddress.loopbackIPv4,
  LanDoor() => InternetAddress.anyIPv4,
};

/// Whether a request may come in.
///
/// This machine always may — it is the one the records file is on, and a
/// process here can read that file without asking anyone. Everybody else
/// comes through a [LanDoor], showing its secret.
bool doorAdmits(
  BoardDoor door, {
  required bool fromThisMachine,
  required String? shown,
}) {
  if (fromThisMachine) return true;
  return switch (door) {
    LoopbackDoor() => false,
    LanDoor(:final secret) => shown != null && sameSecret(shown, secret),
  };
}

/// [a] == [b], taking as long for a near miss as for a far one.
bool sameSecret(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var differs = x.length ^ y.length;
  for (var i = 0; i < y.length; i++) {
    differs |= (i < x.length ? x[i] : 0) ^ y[i];
  }
  return differs == 0;
}

/// The secret a request shows: a tool sends it as a bearer, a browser as the
/// cookie the server gave it.
String? secretShown(HttpRequest request) {
  final bearer = request.headers.value(HttpHeaders.authorizationHeader);
  if (bearer != null && bearer.startsWith('Bearer ')) {
    return bearer.substring('Bearer '.length).trim();
  }
  for (final cookie in request.cookies) {
    if (cookie.name == kDoorCookie) return cookie.value;
  }
  return null;
}

/// The cookie that lets a browser back in for a year without typing again.
Cookie doorCookie(String secret) => Cookie(kDoorCookie, secret)
  ..httpOnly = true
  ..path = '/'
  ..sameSite = SameSite.strict
  ..maxAge = 60 * 60 * 24 * 365;

// ─────────────────────────────────────────── the other side of the door

/// What a tool was pointed at: this machine's records file, or the server of
/// the machine that holds it.
sealed class BoardPlace {
  const BoardPlace();
}

final class BoardFile extends BoardPlace {
  const BoardFile(this.path);

  final String path;
}

final class BoardServer extends BoardPlace {
  const BoardServer(this.base, {this.secret});

  final Uri base;

  /// Null when the tool was given none — which is right on the machine the
  /// server runs on, and a 401 anywhere else.
  final String? secret;
}

/// The variable that names the file a tool reads the door's secret from.
///
/// ⚠️The FILE's name, not the secret: an environment is printed, logged and
/// inherited, and a command line is written into a transcript.
const kDoorSecretFileVariable = 'ANICEL_BOARD_TOKEN_FILE';

/// [said] as a place: an address is a server, anything else a records file.
BoardPlace boardPlaceOf(
  String said, {
  Map<String, String>? environment,
  String? Function(String path)? read,
}) {
  if (!said.startsWith('http://') && !said.startsWith('https://')) {
    return BoardFile(said);
  }
  final readFile = read ??
      (path) {
        final file = File(path);
        return file.existsSync() ? file.readAsStringSync() : null;
      };
  final named = (environment ?? Platform.environment)[kDoorSecretFileVariable];
  final secret = named == null ? null : readFile(named)?.trim();
  return BoardServer(
    Uri.parse(said),
    secret: secret == null || secret.isEmpty ? null : secret,
  );
}

/// What the server answered. [status] 0 is 「nobody answered」 and [body]
/// then says why.
typedef BoardAnswer = ({int status, String body});

/// One request to the board's server, answered whole.
Future<BoardAnswer> askBoard(
  BoardServer server,
  String method,
  String pathAndQuery, {
  String? body,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.openUrl(
      method,
      server.base.resolve(pathAndQuery),
    );
    final secret = server.secret;
    if (secret != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    }
    if (body != null) {
      request.headers.contentType = ContentType(
        'text',
        'plain',
        charset: 'utf-8',
      );
      request.add(utf8.encode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (status: response.statusCode, body: text);
  } on Object catch (e) {
    return (status: 0, body: '보드 서버에 닿지 못했습니다(${server.base}) — $e');
  } finally {
    client.close(force: true);
  }
}

/// What to tell the person when the server would not let a tool in.
String turnedAwayAdvice(BoardServer server) => server.secret == null
    ? '이 기계가 아닌 곳에서는 비밀값이 있어야 합니다 — '
          '$kDoorSecretFileVariable 가 비밀값 파일을 가리키게 하세요.'
    : '서버가 이 비밀값을 받지 않았습니다 — 본진의 값이 바뀌었는지 보세요.';
