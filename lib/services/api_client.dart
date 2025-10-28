// lib/services/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class AnalysisResult {
  final List<String> tiles;
  final Map<String, dynamic>? band;
  final List<dynamic>? boxes;

  AnalysisResult({
    required this.tiles,
    this.band,
    this.boxes,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      tiles: (json['tiles'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
      band: json['band'] as Map<String, dynamic>?,
      boxes: json['boxes'] as List<dynamic>?,
    );
  }
}

class ApiClient {
  /// ベースURL（--dart-define=API_BASE=... で上書き）
  static String get _base {
    const override = String.fromEnvironment('API_BASE');
    if (override.isNotEmpty) return override;
    if (Platform.isAndroid) return 'http://10.0.2.2:8080';
    return 'http://127.0.0.1:8080';
  }

  /// APIキー（ANALYZER_API_KEY でも API_KEY でも可）
  static String get _apiKey {
    const k1 = String.fromEnvironment('API_KEY');
    if (k1.isNotEmpty) return k1;
    const k2 = String.fromEnvironment('ANALYZER_API_KEY');
    if (k2.isNotEmpty) return k2;
    return '';
  }

  static Map<String, String> _headers() {
    final h = <String, String>{'Accept': 'application/json'};
    if (_apiKey.isNotEmpty) h['x-api-key'] = _apiKey;
    return h;
  }

  /// ---- ping ----
  /// Cloud Run は `/healthz/` が 200、`/healthz` が 404 の構成があるため両方試す
  static Future<bool> healthz({Duration timeout = const Duration(seconds: 8)}) async {
    final candidates = <String>[
      '$_base/healthz/',
      '$_base/healthz',
    ];

    try {
      for (final url in candidates) {
        final res = await http.get(Uri.parse(url), headers: _headers()).timeout(timeout);
        if (res.statusCode == 200) return true;
        if (res.statusCode != 404) {
          throw Exception('Health check failed: ${res.statusCode} ${res.body}');
        }
      }
      return false;
    } on TimeoutException {
      throw Exception('サーバの応答がタイムアウトしました（/healthz）');
    } on SocketException catch (e) {
      throw Exception('サーバへ接続できませんでした: ${e.message}');
    }
  }

  /// ---- 画像解析 ----
  static Future<AnalysisResult> analyzeImage(
    File image, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final uri = Uri.parse('$_base/analyze');

    final bytes = await image.readAsBytes();
    final filename = image.path.split(Platform.pathSeparator).last;

    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers())
      ..files.add(http.MultipartFile.fromBytes(
        'file', // FastAPI 側の期待名
        bytes,
        filename: filename,
        contentType: _guessMime(image.path),
      ));

    try {
      final streamed = await req.send().timeout(timeout);
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode != 200) {
        // 認証系はヒント付きで返す
        if (res.statusCode == 401 || res.statusCode == 403) {
          final hint = _apiKey.isEmpty
              ? '（アプリに API_KEY/ANALYZER_API_KEY が未設定）'
              : '（送信したキーがサーバの SERVER_API_KEY と一致していません）';
          throw Exception('認証エラー ${res.statusCode}: ${res.body} $hint');
        }
        throw Exception('APIエラー ${res.statusCode}: ${res.body}');
      }

      final jsonMap = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return AnalysisResult.fromJson(jsonMap);
    } on TimeoutException {
      throw Exception('解析がタイムアウトしました。ネットワーク状態をご確認ください。');
    } on SocketException catch (e) {
      throw Exception('サーバへ接続できませんでした: ${e.message}');
    } catch (e) {
      throw Exception('解析中にエラーが発生しました: $e');
    }
  }

  static MediaType _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    return MediaType('image', 'jpeg');
  }
}
