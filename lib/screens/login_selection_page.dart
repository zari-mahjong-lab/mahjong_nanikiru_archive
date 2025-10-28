// lib/screens/login_selection_page.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart'; // ★ 追加

import '../providers/guest_provider.dart';
import 'my_page.dart';
import 'email_login_page.dart';

class LoginSelectionPage extends StatefulWidget {
  const LoginSelectionPage({super.key});

  @override
  State<LoginSelectionPage> createState() => _LoginSelectionPageState();
}

class _LoginSelectionPageState extends State<LoginSelectionPage> {
  final AudioPlayer _player = AudioPlayer();
  bool _busy = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _afterLogin(UserCredential cred) async {
    if (!mounted) return;
    context.read<GuestProvider>().setGuest(false);
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MyPage(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _showError(Object e) {
    final msg =
        (e is FirebaseAuthException) ? '${e.code}: ${e.message}' : e.toString();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ログインに失敗しました: $msg')),
    );
  }

  // ---------------- Google（Androidはネイティブ経路・ブラウザ非経由） ----------------
  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await _player.play(AssetSource('sounds/cyber_click.mp3'));

      if (Platform.isAndroid) {
        // ✅ Androidは GoogleSignIn (GMS) を使い、ブラウザのリダイレクトを避ける
        final gSignIn = GoogleSignIn(
          scopes: const ['email', 'profile'],
        );

        // 毎回アカウント選択を出したい場合は silent → signOut
        await gSignIn.signOut();

        final gUser = await gSignIn.signIn(); // キャンセル時は null
        if (gUser == null) return;

        final gAuth = await gUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: gAuth.idToken,
          accessToken: gAuth.accessToken,
        );

        final cred =
            await FirebaseAuth.instance.signInWithCredential(credential);
        await _afterLogin(cred);
        return;
      }

      // ✅ iOS / macOS / それ以外は Firebase Auth のプロバイダAPIを使用
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile')
        ..setCustomParameters({'prompt': 'select_account'});

      final cred = await FirebaseAuth.instance.signInWithProvider(provider);
      await _afterLogin(cred);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Apple ----------------
  Future<void> _signInWithApple() async {
    if (_busy) return;

    if (!(Platform.isIOS || Platform.isMacOS)) {
      _showError('Appleでログインは iOS / macOS でのみ利用できます。');
      return;
    }

    setState(() => _busy = true);

    try {
      await _player.play(AssetSource('sounds/cyber_click.mp3'));

      final appleIdCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauth = OAuthProvider('apple.com').credential(
        idToken: appleIdCredential.identityToken,
        accessToken: appleIdCredential.authorizationCode,
      );

      final cred = await FirebaseAuth.instance.signInWithCredential(oauth);

      // 初回の氏名があれば displayName に反映
      final user = cred.user;
      if (user != null &&
          (user.displayName == null || user.displayName!.isEmpty)) {
        final given = appleIdCredential.givenName ?? '';
        final family = appleIdCredential.familyName ?? '';
        final name = ('$family $given').trim();
        if (name.isNotEmpty) {
          await user.updateDisplayName(name);
        }
      }

      await _afterLogin(cred);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Guest ----------------
  Future<void> _signInAsGuest(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await _player.play(AssetSource('sounds/cyber_click.mp3'));
      context.read<GuestProvider>().setGuest(true);

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MyPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showApple = Platform.isIOS || Platform.isMacOS;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'ログイン',
          style: TextStyle(
            letterSpacing: 1.2,
            shadows: [
              Shadow(
                blurRadius: 12,
                color: Colors.cyanAccent,
                offset: Offset(0, 0),
              )
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF001018), Color(0xFF00232E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: SizedBox(
            height: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.cyanAccent, Colors.transparent],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _StaticCyberBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'ログイン方法を選択してください',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  blurRadius: 8,
                                  color: Colors.cyan,
                                  offset: Offset(0, 0),
                                )
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          NeonButton(
                            icon: Icons.account_circle,
                            label: 'Googleでログイン',
                            onPressed: _busy ? null : _signInWithGoogle,
                          ),
                          const SizedBox(height: 12),

                          if (showApple) ...[
                            NeonButton(
                              icon: Icons.apple,
                              label: 'Appleでログイン',
                              onPressed: _busy ? null : _signInWithApple,
                            ),
                            const SizedBox(height: 12),
                          ],

                          NeonButton(
                            icon: Icons.mail_outline,
                            label: 'メールアドレスでログイン',
                            onPressed: _busy
                                ? null
                                : () async {
                                    await _player.play(
                                        AssetSource('sounds/cyber_click.mp3'));
                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (_, __, ___) =>
                                            const EmailLoginPage(),
                                        transitionDuration: Duration.zero,
                                        reverseTransitionDuration:
                                            Duration.zero,
                                      ),
                                    );
                                  },
                          ),

                          const SizedBox(height: 20),

                          NeonOutlineButton(
                            icon: Icons.person_outline,
                            label: 'ゲストとして使う',
                            onPressed:
                                _busy ? null : () => _signInAsGuest(context),
                          ),

                          if (_busy) ...[
                            const SizedBox(height: 20),
                            const CircularProgressIndicator(
                              color: Colors.cyanAccent,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ======== 背景・見た目用ウィジェット ========

class _StaticCyberBackground extends StatelessWidget {
  const _StaticCyberBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _GridPainter(opacity: 0.16),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF020B0E),
              Color(0xFF01080A),
              Color(0xFF000507),
            ],
          ),
        ),
        foregroundDecoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white12,
              Colors.transparent,
              Colors.white12,
            ],
            stops: const [0.25, 0.5, 0.75],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double opacity;
  const _GridPainter({this.opacity = 0.16});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent.withOpacity(opacity)
      ..strokeWidth = 0.6;

    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC0B1114),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.6),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8020FFFF),
            blurRadius: 24,
            spreadRadius: 1,
          )
        ],
      ),
      child: child,
    );
  }
}

class NeonButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const NeonButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: enabled
                ? const [Color(0xFF00FFF0), Color(0xFF00B7FF)]
                : [
                    Colors.cyanAccent.withOpacity(0.4),
                    Colors.blue.withOpacity(0.4)
                  ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x8020FFFF),
                    blurRadius: 20,
                    spreadRadius: 1,
                  )
                ]
              : const [],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

class NeonOutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const NeonOutlineButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final border = BorderSide(
      color: enabled ? Colors.cyanAccent : Colors.cyanAccent.withOpacity(0.5),
      width: 1.4,
    );
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x8020FFFF),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  )
                ]
              : const [],
        ),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.login, color: Colors.cyanAccent),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.cyanAccent,
            side: border,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
