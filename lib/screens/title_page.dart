import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_selection_page.dart';
import 'profile_edit_page.dart';
import 'home_page.dart';

class TitlePage extends StatefulWidget {
  const TitlePage({super.key});

  @override
  State<TitlePage> createState() => _TitlePageState();
}

class _TitlePageState extends State<TitlePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _opacityAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _handleStartup() async {
    if (_navigated) return;
    _navigated = true;

    await _audioPlayer.play(AssetSource('sounds/cyber_start.mp3'));

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginSelectionPage()),
      );
      return;
    }

    try {
      await user.reload();
    } catch (e) {
      debugPrint('ユーザーの再読み込み失敗: $e');
    }

    final updatedUser = FirebaseAuth.instance.currentUser;
    final hasProfile = updatedUser?.displayName?.isNotEmpty ?? false;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => hasProfile ? HomePage() : const ProfileEditPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleStartup,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/background.png', fit: BoxFit.cover),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    neonText('  麻雀'),
                    const SizedBox(width: 12),
                    Image.asset(
                      'assets/images/logo.png',
                      height: 54,
                      width: 54,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              neonText('立体何切る'),
              neonText('アーカイブ'),
              const SizedBox(height: 40),
              FadeTransition(
                opacity: _opacityAnimation,
                child: Text(
                  'Tap to Start',
                  style: GoogleFonts.orbitron(
                    fontSize: 20,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                    shadows: const [
                      Shadow(
                        blurRadius: 6,
                        color: Colors.cyanAccent,
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget neonText(String text) {
    return Stack(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.cyan.shade200,
            shadows: const [
              Shadow(blurRadius: 2, color: Colors.cyan, offset: Offset(0, 0)),
            ],
            decoration: TextDecoration.none,
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.cyan[300],
            decoration: TextDecoration.none,
            shadows: const [
              Shadow(blurRadius: 6, color: Colors.cyan, offset: Offset(0, 0)),
              Shadow(
                blurRadius: 10,
                color: Colors.cyanAccent,
                offset: Offset(0, 0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
