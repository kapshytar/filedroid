import 'dart:async';
import 'dart:io';

/// A lightweight HTTP server that serves a single remote Android file
/// with HTTP Range support, reading bytes on demand via adb exec-out.
///
/// Each (deviceId, remotePath) pair gets its own server bound to a
/// random loopback port.  Servers are kept alive for the lifetime of the app
/// (no explicit teardown needed for the streaming use-case).
class StreamServer {
  StreamServer._();

  // Registry: key = "$deviceId|$remotePath" → bound Uri
  static final Map<String, Uri> _registry = {};

  /// Shell-quote a remote path for the *device* shell
  /// (same logic as AdbService._shellQuote).
  static String _shellQuote(String path) =>
      "'${path.replaceAll("'", "'\\''")}'";

  /// Start (or reuse) an HTTP server that streams [remotePath] from [deviceId]
  /// via [adbPath].  Returns the base Uri (e.g. http://127.0.0.1:54321/).
  static Future<Uri> start({
    required String adbPath,
    required String deviceId,
    required String remotePath,
  }) async {
    final key = '$deviceId|$remotePath';
    if (_registry.containsKey(key)) {
      return _registry[key]!;
    }

    // Get file size once up front.
    final sizeResult = await Process.run(adbPath, [
      '-s',
      deviceId,
      'shell',
      'stat',
      '-c',
      '%s',
      _shellQuote(remotePath),
    ]);
    final totalSize =
        int.tryParse((sizeResult.stdout as String).trim()) ?? 0;

    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/',
    );
    _registry[key] = uri;

    _serveRequests(server, adbPath, deviceId, remotePath, totalSize);

    return uri;
  }

  static void _serveRequests(
    HttpServer server,
    String adbPath,
    String deviceId,
    String remotePath,
    int totalSize,
  ) {
    server.listen((HttpRequest request) async {
      final response = request.response;

      // Content-Type heuristic based on extension.
      final ext = remotePath.toLowerCase().split('.').last;
      final contentType = _contentTypeForExtension(ext);

      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.set('Content-Type', contentType);

      // HEAD — headers only.
      if (request.method == 'HEAD') {
        if (totalSize > 0) {
          response.headers.set('Content-Length', '$totalSize');
        }
        await response.close();
        return;
      }

      final rangeHeader = request.headers.value('range');

      int start = 0;
      int end = totalSize > 0 ? totalSize - 1 : 0;

      if (rangeHeader != null && totalSize > 0) {
        // Parse "bytes=start-end" or "bytes=-suffix" or "bytes=start-"
        final match =
            RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
        if (match != null) {
          final startStr = match.group(1)!;
          final endStr = match.group(2)!;
          if (startStr.isEmpty && endStr.isNotEmpty) {
            // Suffix form: bytes=-N
            final suffix = int.parse(endStr);
            start = totalSize - suffix;
            end = totalSize - 1;
          } else if (startStr.isNotEmpty) {
            start = int.parse(startStr);
            end = endStr.isNotEmpty ? int.parse(endStr) : totalSize - 1;
          }
          // Clamp
          if (start < 0) start = 0;
          if (end >= totalSize) end = totalSize - 1;
        }
      }

      final len = (totalSize > 0) ? end - start + 1 : 0;

      if (rangeHeader != null && totalSize > 0) {
        response.statusCode = HttpStatus.partialContent;
        response.headers
            .set('Content-Range', 'bytes $start-$end/$totalSize');
        response.headers.set('Content-Length', '$len');
      } else {
        response.statusCode = HttpStatus.ok;
        if (totalSize > 0) {
          response.headers.set('Content-Length', '$totalSize');
        }
      }

      // Build the adb command to read the byte range.
      final quoted = _shellQuote(remotePath);
      List<String> adbArgs;
      if (totalSize > 0) {
        final offset = start + 1; // tail -c uses 1-based offset
        adbArgs = [
          '-s',
          deviceId,
          'exec-out',
          "tail -c +$offset $quoted | head -c $len",
        ];
      } else {
        // Unknown size: stream the whole file.
        adbArgs = ['-s', deviceId, 'exec-out', 'cat $quoted'];
      }

      Process? adbProcess;
      try {
        adbProcess = await Process.start(adbPath, adbArgs);

        // Pipe stdout → HTTP response; ignore stderr.
        final pipeDone = Completer<void>();

        adbProcess.stdout.listen(
          (List<int> data) {
            try {
              response.add(data);
            } catch (_) {
              // Client disconnected mid-stream; kill adb.
              adbProcess?.kill();
            }
          },
          onDone: () {
            if (!pipeDone.isCompleted) pipeDone.complete();
          },
          onError: (_) {
            if (!pipeDone.isCompleted) pipeDone.complete();
          },
          cancelOnError: true,
        );

        await pipeDone.future;
        await adbProcess.exitCode;
      } catch (_) {
        adbProcess?.kill();
      } finally {
        try {
          await response.close();
        } catch (_) {}
      }
    });
  }

  static String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }
}
