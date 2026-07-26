import 'dart:convert';
import 'dart:io';

/// Результат выполнения скрипта монтирования.
class MountResult {
  final bool success;
  final String output;

  const MountResult({required this.success, required this.output});
}

/// Сервис монтирования телефона как диска через готовые shell-скрипты.
class MountService {
  static const String _mountScript =
      '/Users/v/PhoneAsExtStorage/adbfs-rootless/mount-phone.sh';
  static const String _unmountScript =
      '/Users/v/PhoneAsExtStorage/adbfs-rootless/unmount-phone.sh';

  /// Монтирует внутреннюю память телефона (→ ~/Phone).
  /// Скрипт сам открывает Finder.
  Future<MountResult> mountPhone() => _run([_mountScript]);

  /// Монтирует системный раздел (→ ~/Phone-System).
  Future<MountResult> mountSystem() => _run([_mountScript, 'system']);

  /// Размонтирует все разделы телефона.
  Future<MountResult> unmountPhone() => _run([_unmountScript]);

  Future<MountResult> _run(List<String> args) async {
    try {
      final result = await Process.run(
        '/bin/bash',
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final combined =
          [result.stdout as String, result.stderr as String]
              .where((s) => s.trim().isNotEmpty)
              .join('\n')
              .trim();
      return MountResult(
        success: result.exitCode == 0,
        output: combined.isEmpty ? '(нет вывода)' : combined,
      );
    } catch (e) {
      return MountResult(success: false, output: e.toString());
    }
  }
}
