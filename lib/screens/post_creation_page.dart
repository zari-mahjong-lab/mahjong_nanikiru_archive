// lib/screens/post_creation_page.dart
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // PlatformException 用
import 'package:url_launcher/url_launcher.dart'; // ★追加

import '../providers/premium_provider.dart';
import '../services/api_client.dart';
import '../services/purchase_service.dart';
import '../widgets/base_scaffold.dart';
import 'login_selection_page.dart';
import 'post_edit_page.dart';

class PostCreationPage extends StatefulWidget {
  const PostCreationPage({super.key});

  @override
  State<PostCreationPage> createState() => _PostCreationPageState();
}

/// 外部ブラウザでURLを開く共通関数
Future<void> _launchExternalUrl(String url) async {
  final uri = Uri.parse(url);
  try {
    await launchUrl(uri);
  } catch (_) {
    // 失敗時はとりあえず無視（必要なら SnackBar などを出してもOK）
  }
}

String _toYenPerMonth(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '---円/月';
  final s = raw.trim();

  // すでに「/月」等が付いているならそのまま
  if (RegExp(r'(/月|/month)', caseSensitive: false).hasMatch(s)) return s;

  // JPYっぽい表記のときだけ「◯◯円/月」に寄せる
  final hasYen = RegExp(r'[¥￥]|JP¥|円').hasMatch(s);
  if (hasYen) {
    // 例: "¥300" "JP¥300" "300円" "¥300.00" -> "300円/月"
    final m = RegExp(r'(\d[\d,]*)').firstMatch(s);
    if (m != null) {
      final num = m.group(1)!.replaceAll(',', '');
      return '${num}円/月';
    }
    return '$s/月';
  }
  // JPYじゃない場合は「円に偽装しない」
  return '$s/月';
}

class _PostCreationPageState extends State<PostCreationPage> {
  File? selectedImage;
  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _player = AudioPlayer();

  bool _loading = false; // 解析中スピナー
  bool _billingBusy = false; // 購入処理中スピナー

  // ★ 共通ローディング画面（メッセージ差し替え可）
  Widget _buildFullPageLoading({String message = 'Now Loading...'}) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 購入ストリーム購読の初期化（複数回呼んでも安全）
    PurchaseService.I.init();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // ====== 効果音 ======
  Future<void> _playSE() async {
    try {
      await _player.play(AssetSource('sounds/cyber_click.mp3'));
    } catch (_) {}
  }

  // ====== 画像選択関連 ======
  Future<void> _showPickSheet() async {
    await _playSE();
    if (!mounted) return;

    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('ギャラリーから選択'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;
    await _pickImage(source);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;

      setState(() {
        selectedImage = File(picked.path);
      });
    } on PlatformException catch (e) {
      // カメラ権限拒否 / Simulator でカメラなし など
      _showError('カメラにアクセスできませんでした: ${e.message ?? e.code}');
    } catch (e) {
      _showError('画像の取得に失敗しました: $e');
    }
  }

  Future<void> _goToEditPage() async {
    if (selectedImage == null || _loading) return;

    setState(() => _loading = true);
    try {
      // ApiClient 側で: multipart/form-data + 'file' フィールド + x-api-key を付与
      final result = await ApiClient.analyzeImage(selectedImage!);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostEditPage(
            imageFile: selectedImage!,
            tiles: result.tiles,
            // band / boxes を渡す場合は以下を有効化
            // band: result.band,
            // boxes: result.boxes,
          ),
        ),
      );
    } on TimeoutException catch (_) {
      _showError('解析がタイムアウトしました。ネットワーク状況をご確認ください。');
    } on SocketException catch (_) {
      _showError(
        'サーバーに接続できませんでした。Cloud Run の稼働/ネットワーク、'
        'あるいは --dart-define=API_BASE=... の設定をご確認ください。',
      );
    } catch (e) {
      _showError('解析エラー: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ====== ストア購入/復元 ======
  Future<void> _buyPremium() async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      await PurchaseService.I.buyPremium();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('購入処理を開始しました。')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('購入に失敗: $e')));
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _restore() async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      await PurchaseService.I.restore();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('購入情報を復元しました。')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('復元に失敗: $e')));
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final premiumProvider = context.watch<PremiumProvider>();

    // 未ログイン：ログイン誘導
    if (user == null) {
      return BaseScaffold(
        title: '投稿作成',
        currentIndex: 1,
        body: Center(
          child: _LoginCallout(
            onTapLogin: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginSelectionPage()),
            ),
          ),
        ),
      );
    }

    final isPremium = premiumProvider.isPremium;

    // ====== 非課金：ペイウォールを表示 ======
    if (!isPremium) {
      return BaseScaffold(
        title: '投稿作成',
        currentIndex: 1,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: _Paywall(
              busy: _billingBusy,
              priceText: PurchaseService.I.formattedPrice(),
              onBuy: _buyPremium,
              onRestore: _restore,
              // デバッグビルドのときだけ強制ON/OFFを有効化
              onDebugOn: kDebugMode
                  ? () => premiumProvider.setDebugPremium(true)
                  : null,
              onDebugOff: kDebugMode
                  ? () => premiumProvider.setDebugPremium(false)
                  : null,
            ),
          ),
        ),
      );
    }

    // ====== プレミアム：本来の投稿作成画面 ======
    final contentPadding = const EdgeInsets.all(24.0);
    return BaseScaffold(
      title: '投稿作成',
      currentIndex: 1,
      // ★ ここで画面全体ローディングを BaseScaffold に任せる
      showLoading: _loading,
      loadingChild: _buildFullPageLoading(message: '画像を解析中...'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: contentPadding,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.cyan.withValues(alpha: 0.10),
                    // ignore: deprecated_member_use_from_same_package
                    Colors.black.withValues(alpha: 0.50),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.cyanAccent, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.50),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(3, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.60),
                    blurRadius: 6,
                    offset: const Offset(-3, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  selectedImage != null
                      ? Image.file(selectedImage!)
                      : const Text(
                          '画像が未選択です',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            shadows: [
                              Shadow(color: Colors.cyan, blurRadius: 4),
                            ],
                          ),
                        ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showPickSheet,
                    icon: const Icon(Icons.image),
                    label: const Text('画像を選択'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: (selectedImage == null || _loading)
                        ? null
                        : _goToEditPage,
                    icon: const Icon(Icons.edit),
                    label: const Text('編集へ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------- 以下、補助ウィジェット -------

class _LoginCallout extends StatelessWidget {
  final VoidCallback onTapLogin;
  const _LoginCallout({required this.onTapLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, color: Colors.cyanAccent, size: 40),
          const SizedBox(height: 12),
          const Text(
            '投稿作成はログインとプレミアム登録が必要です',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'ログインとプレミアム登録をすると、画像解析から何切る問題の手牌を作成し、投稿できるようになります。',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onTapLogin,
            icon: const Icon(Icons.login),
            label: const Text('ログイン / 新規登録へ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _Paywall extends StatelessWidget {
  final bool busy;
  final String? priceText;
  final VoidCallback onBuy;
  final VoidCallback onRestore;
  final VoidCallback? onDebugOn;
  final VoidCallback? onDebugOff;

  const _Paywall({
    required this.busy,
    required this.priceText,
    required this.onBuy,
    required this.onRestore,
    this.onDebugOn,
    this.onDebugOff,
  });

  @override
  Widget build(BuildContext context) {
    final priceLabel = _toYenPerMonth(priceText);
    final showDebug = onDebugOn != null && onDebugOff != null;

    // ★ プラットフォームごとに説明文を切り替え
    final descriptionText = Platform.isIOS
        ? '・サブスクリプション期間：1か月（自動更新）\n'
              '・料金：$priceLabel（地域により異なる場合があります）\n'
              '・期間終了の24時間前までに解約しない限り、自動的に更新されます。\n'
              '・購入後は、端末の「設定」アプリ > Apple ID > サブスクリプション から自動更新を停止・解約できます。'
        : '・サブスクリプション期間：1か月（自動更新）\n'
              '・料金：$priceLabel（地域により異なる場合があります）\n'
              '・期間終了の24時間前までに解約しない限り、自動的に更新されます。\n'
              '・購入後は、Google Play ストアアプリ > 右上のプロフィールアイコン > '
              '「お支払いと定期購入」から自動更新を停止・解約できます。';

    // 利用規約 / プライバシーポリシーのURL
    final termsUrl = Platform.isIOS
        ? 'https://www.apple.com/legal/internet-services/itunes/appstore/dev/stdeula/'
        : 'https://play.google.com/intl/ja_jp/about/play-terms/'; // Google Play 利用規約

    const privacyUrl = 'https://sites.google.com/view/nanikiru-archive-privacy';

    return Container(
      constraints: const BoxConstraints(maxWidth: 640),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8020FFFF),
            blurRadius: 14,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.workspace_premium, color: Colors.cyanAccent, size: 28),
              SizedBox(width: 8),
              Text(
                'プレミアムで投稿作成を解放',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '・広告表示のOFF\n'
            '・画像から牌を自動解析して何切る問題の手牌を作成（手動で修正も可能）\n'
            '・何切る問題の補足情報、投稿者の選択とコメントの記載も可能',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),

          // 購入/復元 ボタン（ここは priceLabel をそのまま使う）
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onBuy,
                  icon: const Icon(Icons.lock_open),
                  label: Text('購入する ($priceLabel)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : onRestore,
                icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
                label: const Text('復元'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent, width: 1.4),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          if (busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: CircularProgressIndicator(),
              ),
            ),

          if (showDebug) ...[
            // （デバッグ部分は既存のまま）
          ],

          const SizedBox(height: 16),
          const Divider(height: 20, color: Colors.cyanAccent),

          // ★ プラットフォーム別の説明文
          Text(
            descriptionText,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 8),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              children: [
                TextButton(
                  onPressed: () => _launchExternalUrl(termsUrl),
                  child: Text(
                    Platform.isIOS ? '利用規約（EULA）' : 'Google Play 利用規約',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),

                TextButton(
                  onPressed: () => _launchExternalUrl(privacyUrl),
                  child: const Text(
                    'プライバシーポリシー',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
