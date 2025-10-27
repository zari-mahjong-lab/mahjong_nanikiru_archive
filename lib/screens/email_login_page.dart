import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';
import 'my_page.dart';

enum AuthMode { login, signup }

class EmailLoginPage extends StatefulWidget {
  const EmailLoginPage({super.key});

  @override
  State<EmailLoginPage> createState() => _EmailLoginPageState();
}

class _EmailLoginPageState extends State<EmailLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pw = TextEditingController();

  AuthMode _mode = AuthMode.login;
  bool _busy = false;
  bool _pwObscure = true;
  final AudioPlayer _player = AudioPlayer();

  // ===== util =====
  Future<void> _switchTo(AuthMode m) async {
    if (_mode == m) return;
    await _player.play(AssetSource('sounds/cyber_click.mp3'));
    if (!mounted) return;
    setState(() => _mode = m);
  }

  String _mapError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'メールアドレスの形式が正しくありません。';
      case 'user-not-found':
        return '該当するユーザーが見つかりません。新規登録をお試しください。';
      case 'wrong-password':
        return 'パスワードが違います。';
      case 'email-already-in-use':
        return 'このメールアドレスは既に登録されています。ログインしてください。';
      case 'weak-password':
        return 'パスワードが弱すぎます。（6文字以上を推奨）';
      case 'network-request-failed':
        return 'ネットワークに接続できません。通信環境を確認してください。';
      case 'too-many-requests':
        return '短時間にリクエストが多すぎます。しばらく待ってから再度お試しください。';
      case 'operation-not-allowed':
        return 'この認証方法は無効化されています（ConsoleのAuthentication設定を確認）。';
      default:
        return '認証エラー: ${e.message ?? e.code}';
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    await _player.play(AssetSource('sounds/cyber_click.mp3'));

    // 入力チェック
    if (!_formKey.currentState!.validate()) return;

    final email = _email.text.trim();
    final password = _pw.text;

    setState(() => _busy = true);
    try {
      if (_mode == AuthMode.signup) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyPage()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_mapError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    await _player.play(AssetSource('sounds/cyber_click.mp3'));
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('パスワード再設定にはメールアドレスを入力してください。')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('再設定メールを $email に送信しました。')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_mapError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // === 見た目のトーン ===
  List<Color> get _bgGrad => _mode == AuthMode.login
      ? const [Color(0xFF001018), Color(0xFF00232E)]
      : const [Color(0xFF061A10), Color(0xFF013226)];
  List<Color> get _primaryGrad => _mode == AuthMode.login
      ? const [Color(0xFF00D4FF), Color(0xFF008CFF)]
      : const [Color(0xFF00FFA3), Color(0xFF00E1C7)];
  Color get _badgeBorder =>
      _mode == AuthMode.login ? const Color(0xFF20D4FF) : const Color(0xFF00FFC2);
  Color get _badgeFill =>
      _mode == AuthMode.login ? const Color(0x3320D4FF) : const Color(0x3300FFC2);
  IconData get _modeIcon =>
      _mode == AuthMode.login ? Icons.login_rounded : Icons.person_add_alt_1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          _mode == AuthMode.login ? 'ログイン' : '新規登録',
          style: const TextStyle(
            letterSpacing: 1.2,
            shadows: [Shadow(blurRadius: 12, color: Colors.cyanAccent)],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _bgGrad,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.cyanAccent, Colors.transparent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _StaticCyberBackground(accent: _badgeBorder)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: _GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // タブ
                            _ModeTabs(
                              mode: _mode,
                              onTapLogin: () => _switchTo(AuthMode.login),
                              onTapSignup: () => _switchTo(AuthMode.signup),
                            ),
                            const SizedBox(height: 18),

                            // ヘッダー
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _badgeBorder, width: 1.2),
                                    color: _badgeFill,
                                    boxShadow: const [
                                      BoxShadow(color: Color(0x4020FFFF), blurRadius: 10),
                                    ],
                                  ),
                                  child: Icon(_modeIcon, color: Colors.cyanAccent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _mode == AuthMode.login ? 'メールでログイン' : '新規登録で始める',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _mode == AuthMode.login
                                            ? '既存アカウントでアプリに入ります'
                                            : '初めての方は無料でアカウントを作成',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // ====== フォーム ======
                            Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  _NeonTextField(
                                    controller: _email,
                                    label: 'メールアドレス',
                                    keyboardType: TextInputType.emailAddress,
                                    prefixIcon: Icons.alternate_email,
                                    textInputAction: TextInputAction.next,
                                    validator: (v) {
                                      final s = (v ?? '').trim();
                                      if (s.isEmpty) return 'メールアドレスを入力してください。';
                                      // ざっくり形式チェック
                                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(s)) {
                                        return 'メールアドレスの形式が正しくありません。';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  _NeonTextField(
                                    controller: _pw,
                                    label: 'パスワード',
                                    obscureText: _pwObscure,
                                    prefixIcon: Icons.lock_outline,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _submit(),
                                    suffix: IconButton(
                                      icon: Icon(
                                        _pwObscure ? Icons.visibility : Icons.visibility_off,
                                        color: Colors.cyanAccent,
                                      ),
                                      onPressed: () =>
                                          setState(() => _pwObscure = !_pwObscure),
                                    ),
                                    validator: (v) {
                                      final s = v ?? '';
                                      if (s.isEmpty) return 'パスワードを入力してください。';
                                      if (s.length < 6) return '6文字以上のパスワードを入力してください。';
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // 補助行
                            const SizedBox(height: 8),
                            if (_mode == AuthMode.login)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy ? null : _resetPassword,
                                  child: const Text(
                                    'パスワードを忘れた？',
                                    style: TextStyle(color: Colors.cyanAccent),
                                  ),
                                ),
                              )
                            else
                              const Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'パスワードは6文字以上推奨（英数字混在だとより安全）',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ),

                            const SizedBox(height: 12),

                            // 送信ボタン
                            NeonButton(
                              icon: _mode == AuthMode.signup ? Icons.person_add : Icons.login,
                              label: _mode == AuthMode.signup ? '新規登録' : 'ログイン',
                              onPressed: _busy ? null : _submit,
                              colors: _primaryGrad,
                              foregroundColor: Colors.black,
                            ),
                            const SizedBox(height: 10),

                            // 切替
                            Text(
                              _mode == AuthMode.signup
                                  ? 'すでにアカウントをお持ちの方はこちら'
                                  : 'はじめての方はこちら',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 8),

                            NeonOutlineButton(
                              icon: Icons.swap_horiz,
                              label: _mode == AuthMode.signup ? '代わりにログイン' : '代わりに新規登録',
                              onPressed: _busy
                                  ? null
                                  : () => _switchTo(
                                        _mode == AuthMode.signup ? AuthMode.login : AuthMode.signup,
                                      ),
                            ),

                            if (_busy) ...[
                              const SizedBox(height: 16),
                              const Center(
                                child: CircularProgressIndicator(color: Colors.cyanAccent),
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
          ),
        ],
      ),
    );
  }
}

/// ====== タブ ======
class _ModeTabs extends StatelessWidget {
  final AuthMode mode;
  final VoidCallback onTapLogin;
  final VoidCallback onTapSignup;

  const _ModeTabs({
    required this.mode,
    required this.onTapLogin,
    required this.onTapSignup,
  });

  @override
  Widget build(BuildContext context) {
    Widget tab(String text, bool active, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? Colors.cyanAccent : Colors.cyanAccent.withOpacity(0.35),
                width: 1.2,
              ),
              color: active ? const Color(0x2220FFFF) : const Color(0x1100FFFF),
              boxShadow: active
                  ? const [BoxShadow(color: Color(0x6020FFFF), blurRadius: 14, spreadRadius: 1)]
                  : const [],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('ログイン', mode == AuthMode.login, onTapLogin),
        const SizedBox(width: 10),
        tab('新規登録', mode == AuthMode.signup, onTapSignup),
      ],
    );
  }
}

/// ====== 見た目だけのウィジェット ======
class _StaticCyberBackground extends StatelessWidget {
  final Color accent;
  const _StaticCyberBackground({required this.accent});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(opacity: 0.16, lineColor: accent),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF020B0E), Color(0xFF01080A), Color(0xFF000507)],
          ),
        ),
        foregroundDecoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white54.withOpacity(0.03),
              Colors.transparent,
              Colors.white54.withOpacity(0.03),
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
  final Color lineColor;
  const _GridPainter({this.opacity = 0.16, this.lineColor = Colors.cyanAccent});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor.withOpacity(opacity)
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
      oldDelegate.opacity != opacity || oldDelegate.lineColor != lineColor;
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
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x8020FFFF), blurRadius: 24, spreadRadius: 1),
        ],
      ),
      child: child,
    );
  }
}

class _NeonTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;

  // 追加: validator / onSubmitted / suffix / action
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final Widget? suffix;
  final TextInputAction? textInputAction;

  const _NeonTextField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.validator,
    this.onSubmitted,
    this.suffix,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    const fill = Color(0x2200FFFF);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.5), width: 1),
    );
    final focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.6),
    );

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.cyanAccent,
      autofillHints: keyboardType == TextInputType.emailAddress
          ? const [AutofillHints.username, AutofillHints.email]
          : const [AutofillHints.password],
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration: InputDecoration(
        filled: true,
        fillColor: fill,
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Colors.cyanAccent) : null,
        suffixIcon: suffix,
        enabledBorder: border,
        focusedBorder: focused,
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }
}

/// ボタン
class NeonButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final List<Color>? colors;
  final Color? foregroundColor;

  const NeonButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.colors,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final grad = colors ??
        (enabled
            ? const [Color(0xFF00FFF0), Color(0xFF00B7FF)]
            : [Colors.cyan.withOpacity(0.4), Colors.blue.withOpacity(0.4)]);
    final fg = foregroundColor ?? Colors.black;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: grad),
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? const [BoxShadow(color: Color(0x8020FFFF), blurRadius: 20, spreadRadius: 1)]
              : const [],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: fg,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              ? const [BoxShadow(color: Color(0x8020FFFF), blurRadius: 14, spreadRadius: 0.5)]
              : const [],
        ),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.cyanAccent),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.cyanAccent,
            side: border,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
