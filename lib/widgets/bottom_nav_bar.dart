import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';

import '../screens/home_page.dart';
import '../screens/post_creation_page.dart';
import '../screens/my_page.dart';

class BottomNavBar extends StatefulWidget {
  final int currentIndex;

  const BottomNavBar({
    Key? key,
    required this.currentIndex,
  }) : super(key: key);

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  static bool _isOpen = false;

  Future<void> _playClickSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/cyber_click.mp3'));
  }

  void _navigate(BuildContext context, int index, Widget page) async {
    if (index == widget.currentIndex) return;
    await _playClickSound();
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    if (!isLandscape) {
      return BottomNavigationBar(
        backgroundColor: Colors.black.withOpacity(0.6),
        elevation: 0,
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.white70,
        currentIndex: widget.currentIndex,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        onTap: (index) {
          switch (index) {
            case 0:
              _navigate(context, index, HomePage());
              break;
            case 1:
              _navigate(context, index, const PostCreationPage());
              break;
            case 2:
              _navigate(context, index, MyPage()); // ✅ 修正：isGuestの引数削除
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: '投稿'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'マイページ'),
        ],
      );
    }

    return Positioned(
      bottom: 16,
      left: 16,
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              await _playClickSound();
              setState(() => _isOpen = !_isOpen);
            },
            child: Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                border: Border.all(color: Colors.cyanAccent, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _isOpen ? Icons.close : Icons.menu,
                color: Colors.cyanAccent,
                size: 28,
              ),
            ),
          ),
          if (_isOpen)
            Container(
              height: 56,
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.cyanAccent.withOpacity(0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIcon(context, 0, Icons.home, HomePage()),
                  _buildIcon(context, 1, Icons.add_box, const PostCreationPage()),
                  _buildIcon(context, 2, Icons.person, MyPage()), // ✅ 修正
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIcon(BuildContext context, int index, IconData icon, Widget page) {
    final isSelected = widget.currentIndex == index;
    return IconButton(
      icon: Icon(icon, color: isSelected ? Colors.cyanAccent : Colors.white70),
      onPressed: () => _navigate(context, index, page),
    );
  }
}
