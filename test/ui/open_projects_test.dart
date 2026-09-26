import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_workspace_colors.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/open_projects.dart';

import '../helpers/fake_playback_transport.dart';

/// I-7 (유저 2026-09-26): 「여러 프로젝트 열수있게할거야 … 상단띠에 프로젝트
/// 리스트있고 닫기버튼있고」 — the projects open in the window, a session per
/// tab, and the rules of the row: where a tab opens, which one is shown after
/// a close, what the last close leaves, what an untitled tab is called, and
/// how much each tab may cache.
void main() {
  late List<EditorSessionManager> letGo;

  OpenProjects make({Project? first}) {
    letGo = [];
    final projects = OpenProjects(
      first: first ?? createDefaultProject(),
      openSession: (project) => EditorSessionManager(initialProject: project),
      letGo: (session) {
        letGo.add(session);
        session.dispose();
      },
    );
    addTearDown(projects.dispose);
    return projects;
  }

  /// Binds [session] to [path] the way a save does — the record only.
  void bind(EditorSessionManager session, String path) =>
      session.projectFile.bindToSavedFile(path, mediaInFile: {}, cleanAsOf: 0);

  test('opening adds a tab AFTER the others and shows it — the tab that '
      'was shown stays open behind it', () {
    final projects = make();
    final first = projects.active;
    final second = projects.open(createDefaultProject());
    final third = projects.open(createDefaultProject());
    expect(projects.sessions, [first, second, third]);
    expect(identical(projects.active, third), isTrue);
    expect(letGo, isEmpty, reason: 'opening closes nothing');
  });

  test('activating shows that tab; the shown one or a stranger is a no-op',
      () {
    final projects = make();
    final first = projects.active;
    projects.open(createDefaultProject());
    var notified = 0;
    projects.addListener(() => notified += 1);
    projects.activate(first);
    expect(identical(projects.active, first), isTrue);
    expect(notified, 1);
    projects.activate(first);
    final stranger = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(stranger.dispose);
    projects.activate(stranger);
    expect(notified, 1, reason: 'nothing changed, nothing said');
    expect(identical(projects.active, first), isTrue);
  });

  test('closing the SHOWN tab shows the one that took its place — or, at '
      'the end of the row, the one before it', () {
    final projects = make();
    final a = projects.active;
    final b = projects.open(createDefaultProject());
    final c = projects.open(createDefaultProject());
    projects.activate(b);
    projects.close(b, fresh: createDefaultProject);
    expect(projects.sessions, [a, c]);
    expect(identical(projects.active, c), isTrue, reason: 'took its place');
    projects.close(c, fresh: createDefaultProject);
    expect(identical(projects.active, a), isTrue, reason: 'end of the row');
    expect(letGo, [b, c], reason: 'each closed session is let go');
  });

  test('closing a tab BEHIND keeps the shown one shown', () {
    final projects = make();
    final a = projects.active;
    final b = projects.open(createDefaultProject());
    projects.close(a, fresh: createDefaultProject);
    expect(projects.sessions, [b]);
    expect(identical(projects.active, b), isTrue);
  });

  test('🗣️I-7-Q1: closing the LAST tab leaves an untitled project — there '
      'is always a project on screen', () {
    final projects = make();
    final only = projects.active;
    var made = 0;
    projects.close(
      only,
      fresh: () {
        made += 1;
        return createDefaultProject();
      },
    );
    expect(made, 1);
    expect(projects.sessions, hasLength(1));
    expect(identical(projects.active, only), isFalse);
    expect(letGo, [only]);
    expect(projects.untitledNumberOf(projects.active), 2);
  });

  test('a PREPARED session is in no tab until adopted, and a discarded one '
      'is let go without ever being shown', () {
    final projects = make();
    final first = projects.active;
    final read = projects.prepare(createDefaultProject());
    expect(projects.sessions, [first]);
    expect(identical(projects.active, first), isTrue);
    projects.adopt(read);
    expect(projects.sessions, [first, read]);
    expect(identical(projects.active, read), isTrue);

    final failed = projects.prepare(createDefaultProject());
    projects.discard(failed);
    expect(projects.sessions, [first, read]);
    expect(letGo, [failed]);
  });

  test('an untitled tab is numbered in the order it opened, and keeps its '
      'number — a project from a file takes none', () {
    final projects = make();
    final one = projects.active;
    final fromFile = projects.prepare(createDefaultProject());
    bind(fromFile, 'C:/work/Scene 3.anicel');
    projects.adopt(fromFile);
    final two = projects.open(createDefaultProject());
    expect(projects.untitledNumberOf(one), 1);
    expect(projects.untitledNumberOf(fromFile), isNull);
    expect(projects.untitledNumberOf(two), 2);
    projects.close(one, fresh: createDefaultProject);
    final three = projects.open(createDefaultProject());
    expect(projects.untitledNumberOf(two), 2, reason: 'kept after a close');
    expect(projects.untitledNumberOf(three), 3, reason: 'never reused');
  });

  test('boundTo finds the tab bound to the same file, however the path is '
      'spelled', () {
    final projects = make();
    final open = projects.open(createDefaultProject());
    bind(open, 'C:/work/Scene 3.anicel');
    expect(
      identical(projects.boundTo(r'C:\work\Scene 3.anicel'), open),
      isTrue,
    );
    expect(projects.boundTo('C:/work/Scene 4.anicel'), isNull);
  });

  test('the tab on screen takes the whole cache allowance; the ones behind '
      'share a quarter between them', () {
    final projects = make();
    final a = projects.active;
    expect(a.cacheShare, 1);
    final b = projects.open(createDefaultProject());
    final c = projects.open(createDefaultProject());
    expect(c.cacheShare, 1);
    expect(a.cacheShare, OpenProjects.backgroundCacheShare / 2);
    expect(b.cacheShare, OpenProjects.backgroundCacheShare / 2);
    projects.activate(a);
    expect(a.cacheShare, 1);
    expect(c.cacheShare, OpenProjects.backgroundCacheShare / 2);
    projects.close(b, fresh: createDefaultProject);
    expect(c.cacheShare, OpenProjects.backgroundCacheShare);
  });

  test('a tab behind the one on screen caches with its SHARE: its own '
      'caches\' budgets shrink with it, and come back when it is shown', () {
    final projects = make();
    final a = projects.active;
    int playback() => a.playbackRig.playbackCache.playbackCacheByteBudget;
    final whole = playback();
    projects.open(createDefaultProject());
    expect(playback(), lessThan(whole), reason: 'behind: a share');
    projects.activate(a);
    expect(playback(), whole, reason: 'on screen: the whole allowance');
  });

  test('a tab going behind stops every transport it has — and one closed '
      'while shown stops too', () {
    final projects = make();
    final a = projects.active;
    final playing = FakePlaybackTransport()..play();
    a.playbackRig.transports.add(playing);
    projects.open(createDefaultProject());
    expect(playing.isPlaying, isFalse, reason: 'it went behind');

    projects.activate(a);
    final again = FakePlaybackTransport()..play();
    a.playbackRig.transports.add(again);
    final other = projects.sessions.last;
    final behind = FakePlaybackTransport()..play();
    other.playbackRig.transports.add(behind);
    projects.close(a, fresh: createDefaultProject);
    expect(again.isPlaying, isFalse, reason: 'closed while on screen');
    projects.activate(other);
    expect(behind.isPlaying, isTrue, reason: 'coming forward starts nothing');
  });

  test('disposing lets every open session go — the window is closing', () {
    final projects = OpenProjects(
      first: createDefaultProject(),
      openSession: (project) => EditorSessionManager(initialProject: project),
      letGo: (session) {
        letGo.add(session);
        session.dispose();
      },
    );
    letGo = [];
    final a = projects.active;
    final b = projects.open(createDefaultProject());
    projects.dispose();
    expect(letGo, [a, b]);
  });

  test('a NEW project is new: an id no other open project has, and the '
      'pasteboard the app keeps for the next project', () {
    final kept = AppWorkspaceColors.settings.value;
    addTearDown(() => AppWorkspaceColors.settings.value = kept);
    AppWorkspaceColors.settings.value = const AppWorkspaceColors(
      pasteboardArgb: 0xFF123456,
    );
    final a = newUntitledProject();
    final b = newUntitledProject();
    expect(a.id, isNot(b.id));
    expect(a.pasteboardArgb, 0xFF123456);
    expect(b.pasteboardArgb, 0xFF123456);
  });
}
