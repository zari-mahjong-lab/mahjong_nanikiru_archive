import 'package:flutter/material.dart';

/// 牌画像を横一列に表示するウィジェット。
/// [tiles] は '1m','2m','3m','4p','r5p','c','n','h' などのアセットID（拡張子なし）想定。
class HandImageWidget extends StatelessWidget {
  final List<String> tiles;

  /// 各牌の左右間隔（デフォルト0で隙間なし）
  final double itemSpacing;

  /// 全体の最大高さ（null の場合はレイアウト幅から自動算出）
  final double? maxHeight;

  const HandImageWidget({
    Key? key,
    required this.tiles,
    this.itemSpacing = 0,
    this.maxHeight,
  }) : super(key: key);

  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        final count = tiles.length.clamp(1, 14);
        final totalSpacing = itemSpacing * (count - 1);
        final tileW = (c.maxWidth - totalSpacing) / count;
        final tileH = tileW * 3 / 2;

        // clamp は num を返すため、toDouble() で明示変換する
        final double height =
            ((maxHeight ?? tileH).clamp(0.0, tileH)).toDouble();

        return SizedBox(
          width: c.maxWidth,
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(count, (i) {
              final id = tiles[i];
              return SizedBox(
                width: tileW,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Image.asset(
                    _asset(id),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        id,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
