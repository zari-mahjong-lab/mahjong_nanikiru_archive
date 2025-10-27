import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class TileMatcher {
  final Map<String, img.Image> _tileTemplates = {};
  bool _isInitialized = false;

  Future<void> _initializeTemplates() async {
    if (_isInitialized) return;

    final tileNames = [
      '1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m',
      '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p',
      '1s', '2s', '3s', '4s', '5s', '6s', '7s', '8s', '9s',
      't', 'n', 's', 'p', 'h', 'r', 'c',
      'r5m', 'r5p', 'r5s',
    ];

    for (final name in tileNames) {
      final bytes = await rootBundle.load('assets/tiles/$name.png');
      final image = img.decodeImage(bytes.buffer.asUint8List());
      if (image != null) {
        _tileTemplates[name] = image;
      }
    }

    _isInitialized = true;
  }

  /// 指定された牌画像を解析し、最も類似した牌ファイル名を返す
  Future<String?> matchTile(img.Image inputTile) async {
    await _initializeTemplates();

    double bestScore = double.infinity;
    String? bestMatch;

    for (final entry in _tileTemplates.entries) {
      final score = _compareImages(entry.value, inputTile);
      if (score < bestScore) {
        bestScore = score;
        bestMatch = entry.key;
      }
    }

    return bestMatch;
  }

  /// 平均二乗誤差（MSE）を使って2つの画像の類似度を比較
  double _compareImages(img.Image a, img.Image b) {
    final resizedA = img.copyResize(a, width: 32, height: 32);
    final resizedB = img.copyResize(b, width: 32, height: 32);

    double error = 0.0;

    for (int y = 0; y < resizedA.height; y++) {
      for (int x = 0; x < resizedA.width; x++) {
        final p1 = resizedA.getPixel(x, y);
        final p2 = resizedB.getPixel(x, y);

        final r1 = p1.r;
        final g1 = p1.g;
        final b1 = p1.b;

        final r2 = p2.r;
        final g2 = p2.g;
        final b2 = p2.b;

        error += ((r1 - r2) * (r1 - r2) +
                  (g1 - g2) * (g1 - g2) +
                  (b1 - b2) * (b1 - b2)).toDouble();
      }
    }

    return error / (resizedA.width * resizedA.height);
  }
}

List<img.Image> extractBottomTiles(img.Image fullImage, {int count = 14}) {
  final tileWidth = (fullImage.width / count).floor();
  final tileHeight = (fullImage.height / 5).floor(); // 最下段想定

  final tiles = <img.Image>[];

  for (int i = 0; i < count; i++) {
    final tile = img.copyCrop(
      fullImage,
      x: i * tileWidth,
      y: fullImage.height - tileHeight,
      width: tileWidth,
      height: tileHeight,
    );
    tiles.add(tile);
  }

  return tiles;
}
