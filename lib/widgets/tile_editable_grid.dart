import 'package:flutter/material.dart';

class TileEditableGrid extends StatelessWidget {
  final List<String> tileIds;
  final void Function(List<String>) onChanged;
  final int maxTiles;
  final List<String> allTileOptions;

  const TileEditableGrid({
    Key? key,
    required this.tileIds,
    required this.onChanged,
    required this.allTileOptions,
    this.maxTiles = 14,
  }) : super(key: key);

  void _showReplaceDialog(BuildContext context, int index) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text('牌を選択', style: TextStyle(color: Colors.cyanAccent)),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: allTileOptions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (context, i) {
                final tile = allTileOptions[i];
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(tile),
                  child: Image.asset('assets/tiles/$tile.png'),
                );
              },
            ),
          ),
        );
      },
    );

    if (selected != null) {
      final newList = List<String>.from(tileIds);
      newList[index] = selected;
      onChanged(newList);
    }
  }

  void _showAddDialog(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text('牌を追加', style: TextStyle(color: Colors.cyanAccent)),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: allTileOptions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (context, i) {
                final tile = allTileOptions[i];
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(tile),
                  child: Image.asset('assets/tiles/$tile.png'),
                );
              },
            ),
          ),
        );
      },
    );

    if (selected != null) {
      final newList = List<String>.from(tileIds)..add(selected);
      onChanged(newList);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = [];

    for (int i = 0; i < tileIds.length; i++) {
      tiles.add(Stack(
        children: [
          GestureDetector(
            onTap: () => _showReplaceDialog(context, i),
            child: Image.asset(
              'assets/tiles/${tileIds[i]}.png',
              width: 40,
              height: 56,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () {
                final newList = List<String>.from(tileIds)..removeAt(i);
                onChanged(newList);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, color: Colors.redAccent, size: 16),
              ),
            ),
          ),
        ],
      ));
    }

    if (tileIds.length < maxTiles) {
      tiles.add(GestureDetector(
        onTap: () => _showAddDialog(context),
        child: Container(
          width: 40,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.black87,
            border: Border.all(color: Colors.cyanAccent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Center(
            child: Icon(Icons.add, color: Colors.cyanAccent),
          ),
        ),
      ));
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tiles,
    );
  }
}
