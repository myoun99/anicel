import 'dart:io';

/// Ends the process [pid] and every process under it: `flutter test` runs
/// its testers two and three processes down, and ending the shell alone
/// leaves them holding the machine. ⚠️Off Windows only the shell's own
/// children go with it.
void cutTree(int pid) {
  if (Platform.isWindows) {
    Process.runSync('taskkill', ['/PID', '$pid', '/T', '/F']);
  } else {
    Process.runSync('pkill', ['-KILL', '-P', '$pid']);
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}
