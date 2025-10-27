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
      tiles: (json['tiles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[],
      band: json['band'] as Map<String, dynamic>?,
      boxes: json['boxes'] as List<dynamic>?,
    );
  }
}

class ApiClient {
  /// ✅ Base URL を自動切り替え（dart-define で上書きも可）
  static String get _base {
    // 例）flutter run --dart-define=API_BASE=http://192.168.1.10:8080
    const override = String.fromEnvironment('API_BASE');
    if (override.isNotEmpty) return override;

    if (Platform.isAndroid) {
      // Android エミュレータ → ホストPCの localhost は 10.0.2.2
      return 'http://10.0.2.2:8080';
    }
    // iOS/Windows/macOS（開発機の localhost ）
    return 'http://127.0.0.1:8080';
  }

  /// サーバ動作確認
  static Future<String> healthz({Duration timeout = const Duration(seconds: 8)}) async {
    final uri = Uri.parse('$_base/healthz');
    try {
      final res = await http.get(uri).timeout(timeout);
      if (res.statusCode != 200) {
        throw Exception('Health check failed: ${res.statusCode} ${res.body}');
      }
      return res.body;
    } on TimeoutException {
      throw Exception('サーバの応答がタイムアウトしました（/healthz）');
    } on SocketException catch (e) {
      throw Exception('サーバへ接続できませんでした: ${e.message}');
    }
  }

  /// 画像解析
  static Future<AnalysisResult> analyzeImage(
    File image, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('$_base/analyze');

    final contentType = _guessMime(image.path); // image/jpeg or image/png
    final req = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          image.path,
          contentType: contentType,
        ),
      );

    try {
      final streamed = await req.send().timeout(timeout);
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode != 200) {
        throw Exception('APIエラー ${res.statusCode}: ${res.body}');
      }

      final jsonMap = json.decode(res.body) as Map<String, dynamic>;
      return AnalysisResult.fromJson(jsonMap);
    } on TimeoutException {
      throw Exception('解析がタイムアウトしました。ネットワーク状態をご確認ください。');
    } on SocketException catch (e) {
      throw Exception('サーバへ接続できませんでした: ${e.message}');
    } catch (e) {
      throw Exception('解析中にエラーが発生しました: $e');
    }
  }

  // ---- helpers ----
  static MediaType _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    // jpeg / jpg それ以外は jpeg 扱い
    return MediaType('image', 'jpeg');
  }
}
