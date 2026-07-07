import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Información de una versión disponible en GitHub Releases.
class UpdateInfo {
  final String version; // versión limpia, ej: "1.0.1"
  final String tagName; // tag original, ej: "v1.0.1"
  final String apkUrl; // URL de descarga directa del APK
  final String releaseNotes;
  final String htmlUrl; // página del release en GitHub

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.releaseNotes,
    required this.htmlUrl,
  });
}

/// Comprueba GitHub Releases y gestiona la descarga/instalación de un APK nuevo.
///
/// Solo aplica en Android: iOS no permite instalar apps fuera de la App Store.
class UpdateService {
  static const String _owner = 'Jhongdlp';
  static const String _repo = 'DailyAPP';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Devuelve [UpdateInfo] si hay una versión más nueva publicada, o `null` si
  /// ya está al día, la plataforma no es Android, o algo falla.
  static Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;

    try {
      final res = await http
          .get(
            Uri.parse(_latestReleaseUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String?;
      if (tagName == null) return null;

      final latest = _parseVersion(tagName);
      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);

      if (_compareVersions(latest, current) <= 0) {
        return null; // Ya estamos al día
      }

      // Buscar el asset APK del release
      final assets = (data['assets'] as List?) ?? const [];
      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
            orElse: () => <String, dynamic>{},
          );
      final apkUrl = apkAsset['browser_download_url'] as String?;
      if (apkUrl == null) return null;

      return UpdateInfo(
        version: _cleanVersion(tagName),
        tagName: tagName,
        apkUrl: apkUrl,
        releaseNotes: (data['body'] as String?)?.trim() ?? '',
        htmlUrl: data['html_url'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('UpdateService.checkForUpdate falló: $e');
      return null;
    }
  }

  /// Descarga el APK reportando progreso (0.0–1.0) y lanza el instalador.
  /// Devuelve `true` si el instalador se abrió correctamente.
  static Future<bool> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.apkUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Descarga falló: HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/SistemDaily-${info.version}.apk');

      final sink = file.openWrite();
      int received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();

      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('UpdateService.downloadAndInstall falló: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  // ---- Utilidades de versión (semver simple: major.minor.patch) ----

  static String _cleanVersion(String raw) {
    // "v1.0.1" -> "1.0.1"; descarta cualquier "+build"
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus != -1) v = v.substring(0, plus);
    return v;
  }

  static List<int> _parseVersion(String raw) {
    final parts = _cleanVersion(raw).split('.');
    return List.generate(3, (i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    });
  }

  static int _compareVersions(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return 0;
  }
}
