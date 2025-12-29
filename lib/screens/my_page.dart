// lib/screens/my_page.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart'; // ← 追加

import '../providers/guest_provider.dart';
import '../providers/premium_provider.dart';
import '../services/purchase_service.dart';
import '../config/build_config.dart'; // ★これを追加

import '../widgets/base_scaffold.dart';
import '../screens/detail_page.dart';
import '../screens/profile_edit_page.dart';
import '../screens/login_selection_page.dart';
import '../screens/title_page.dart';

/// 無アニメーションの共通ルート
Route<T> _noAnimRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_a, _b, _c) => page,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  transitionsBuilder: (_a, _b, _c, child) => child,
);

/// 外部ブラウザでURLを開く共通関数
Future<void> _launchExternalUrl(String url) async {
  final uri = Uri.parse(url);
  // 外部ブラウザで開く（失敗しても致命的ではないので無視でOK）
  await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  // JPYじゃない場合は「円に偽装しない」(設定ミスが分かるようにする)
  // 例: "$2.99" -> "$2.99/月"
  return '$s/月';
}

class MyPage extends StatefulWidget {
  const MyPage({super.key});
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final _parentScroll = ScrollController();
  final AudioPlayer _player = AudioPlayer();

  bool _billingBusy = false; // 課金処理中フラグ

  @override
  void initState() {
    super.initState();
    // 課金SDK 初期化（複数回呼んでも安全）
    unawaited(PurchaseService.I.init());
  }

  Future<void> _playSE(AudioPlayer player) async {
    await player.play(AssetSource('sounds/cyber_click.mp3'));
  }

  // ★ エラー時もページ全体で表示
  Widget _buildErrorPage(String message) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withOpacity(0.15),
            Colors.black.withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }

  Future<void> _showLoginDialog(
    BuildContext context,
    AudioPlayer player,
  ) async {
    await _playSE(player);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('ログインしますか？', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'キャンセル',
              style: TextStyle(color: Colors.cyanAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ログイン',
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      context.read<GuestProvider>().setGuest(false);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        _noAnimRoute(const LoginSelectionPage()),
        (_) => false,
      );
    }
  }

  // ====== 課金処理（本番用） ======
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
      ).showSnackBar(SnackBar(content: Text('購入に失敗しました: $e')));
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
      ).showSnackBar(SnackBar(content: Text('復元に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _deleteAccountAndData() async {
    await _playSE(_player);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 確認ダイアログ
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'アカウントを削除しますか？',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'このアカウントとユーザーデータ（usersドキュメント）を削除します。\n'
          '一度削除すると元に戻すことはできません。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'キャンセル',
              style: TextStyle(color: Colors.cyanAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '削除する',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final uid = user.uid;
    final db = FirebaseFirestore.instance;

    try {
      // ① Firestore の users ドキュメント削除
      await db.collection('users').doc(uid).delete().catchError((_) {});

      // ② Firebase Authentication のユーザー削除
      await user.delete();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('アカウントを削除しました')));

      // ③ ルートに戻す
      context.read<GuestProvider>().setGuest(false);
      Navigator.pushAndRemoveUntil(
        context,
        _noAnimRoute(const TitlePage()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg;
      if (e.code == 'requires-recent-login') {
        msg =
            'アカウント削除には再ログインが必要です。\n'
            '一度ログアウトしてから、再度ログインし直してください。';
      } else {
        msg = 'アカウント削除に失敗しました (${e.code})';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('アカウント削除に失敗しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = context.watch<GuestProvider>().isGuest;
    final premiumProvider = context.watch<PremiumProvider>();
    final isPremium = premiumProvider.isPremium;
    final serverIsPremium = premiumProvider.serverIsPremium; // ★追加
    final debugOverride = premiumProvider.debugOverride; // ★追加

    final user = FirebaseAuth.instance.currentUser;

    // ゲストモード時はこれまでどおり即表示
    if (isGuest || user == null) {
      final player = _player;
      return BaseScaffold(
        title: 'マイページ',
        currentIndex: 2,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 48,
                backgroundColor: Colors.cyanAccent,
                child: Icon(Icons.person, size: 48, color: Colors.black),
              ),
              const SizedBox(height: 12),
              const Text(
                'ゲストユーザー',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showLoginDialog(context, player),
                icon: const Icon(Icons.login),
                label: const Text('ログイン'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final uid = user.uid;
    final docStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docStream,
      builder: (context, snap) {
        // ★ BaseScaffold の showLoading で画面全体オーバーレイ
        final bool isLoading = snap.connectionState == ConnectionState.waiting;

        if (snap.hasError) {
          return BaseScaffold(
            title: 'マイページ',
            currentIndex: 2,
            showLoading: false,
            body: _buildErrorPage('読み込みエラー: ${snap.error}'),
          );
        }

        // ユーザードキュメント（ローディング中は空マップ）
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final nickname =
            (data['nickname'] as String?) ?? (user.displayName ?? 'ユーザー');
        final iconUrl = (data['iconUrl'] as String?) ?? user.photoURL;
        final isPremium = premiumProvider.isPremium;

        final affiliationsRaw = (data['affiliations'] as List?) ?? const [];
        final affiliations = affiliationsRaw
            .whereType<Map>()
            .map(
              (m) => {
                'affiliation': (m['affiliation'] ?? '未選択').toString(),
                'rank': (m['rank'] ?? '未選択').toString(),
              },
            )
            .toList();

        return BaseScaffold(
          title: 'マイページ',
          currentIndex: 2,
          showLoading: isLoading, // ★ここでローディングオーバーレイON/OFF
          body: Center(
            child: SingleChildScrollView(
              controller: _parentScroll,
              primary: false,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // アイコン・名前・プレミアムバッジ
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.cyanAccent,
                    backgroundImage: iconUrl != null
                        ? NetworkImage(iconUrl)
                        : null,
                    child: iconUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 48,
                            color: Colors.black,
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nickname,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isPremium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.cyanAccent),
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.workspace_premium,
                                size: 16,
                                color: Colors.cyanAccent,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'PREMIUM',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),
                  if (affiliations.isNotEmpty)
                    _AffiliationsBox(affiliations: affiliations),

                  const SizedBox(height: 16),

                  // アカウント編集
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _playSE(_player);
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        _noAnimRoute(const ProfileEditPage()),
                      );
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('アカウントを編集'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ====== 課金カード（本番用） ======
                  _PremiumCard(
                    isPremium: isPremium,
                    busy: _billingBusy,
                    priceText: PurchaseService.I.formattedPrice(),
                    onBuy: _buyPremium,
                    onRestore: _restore,
                  ),

                  // ====== デバッグ用プレミアム切替（リリースビルドでは非表示） ======
                  if (kDebugMode) ...[
                    const SizedBox(height: 12),
                    _PremiumDebugCard(
                      isPremium: isPremium,
                      serverIsPremium: serverIsPremium,
                      debugOverride: debugOverride,
                      onForceOn: () =>
                          context.read<PremiumProvider>().setDebugPremium(true),
                      onForceOff: () => context
                          .read<PremiumProvider>()
                          .setDebugPremium(false),
                      onClear: () =>
                          context.read<PremiumProvider>().setDebugPremium(null),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ====== （非課金時は非表示）投稿お気に入り数 / 回答いいね数 ======
                  if (isPremium)
                    _LikesStatsRow(uid: uid)
                  else
                    const _LockedNotice(title: '投稿お気に入り数・回答いいね数（プレミアム限定）'),

                  const SizedBox(height: 32),

                  // お気に入り問題
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'お気に入り問題',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.cyan, blurRadius: 6)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FavoritePostsList(
                    uid: uid,
                    player: _player,
                    parent: _parentScroll,
                  ),

                  const SizedBox(height: 32),

                  // 投稿履歴
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '投稿履歴',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.cyan, blurRadius: 6)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isPremium)
                    _MyPostHistoryList(
                      uid: uid,
                      player: _player,
                      parent: _parentScroll,
                    )
                  else
                    const _LockedNotice(title: '投稿履歴（プレミアム限定）'),

                  const SizedBox(height: 32),

                  // ログアウト
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _playSE(_player);
                      await FirebaseAuth.instance.signOut();
                      if (!mounted) return;
                      context.read<GuestProvider>().setGuest(false);
                      if (!mounted) return;
                      Navigator.pushAndRemoveUntil(
                        context,
                        _noAnimRoute(const TitlePage()),
                        (_) => false,
                      );
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('ログアウト'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  // アカウント削除（ログイン時のみ表示される領域）
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _deleteAccountAndData,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('アカウントとユーザーデータを削除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(
                        color: Colors.redAccent,
                        width: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _parentScroll.dispose();
    _player.dispose();
    super.dispose();
  }
}

// ===== 課金カード（本番用）=====
class _PremiumCard extends StatefulWidget {
  final bool isPremium;
  final bool busy;
  final String? priceText;
  final VoidCallback onBuy;
  final VoidCallback onRestore;

  const _PremiumCard({
    required this.isPremium,
    required this.busy,
    required this.priceText,
    required this.onBuy,
    required this.onRestore,
  });

  @override
  State<_PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<_PremiumCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final priceLabel = _toYenPerMonth(widget.priceText);
    final isFreeTest = kFreePremiumForClosedTest; // ★クローズドテスト用フラグ

    // Apple への説明用に、サブスクの内容をより詳しく
    final description = isFreeTest
        ? 'クローズドテスト中につき、すべてのユーザーでプレミアム機能を無料開放しています。'
        : (widget.isPremium
              ? 'プレミアムが有効です。全ての機能をご利用いただけます。'
              : 'プレミアム会員になると、以下の機能が開放されます：\n'
                    '・アプリ内広告の非表示\n'
                    '・画像解析を利用した何切る問題の投稿\n'
                    '・何切る問題への回答および回答結果の詳細表示\n'
                    '・マイページでの投稿履歴・お気に入り数・いいね数の表示');

    // 利用規約 / プライバシーポリシーのURL
    final termsUrl = Platform.isIOS
        ? 'https://www.apple.com/legal/internet-services/itunes/appstore/dev/stdeula/'
        : 'https://play.google.com/intl/ja_jp/about/play-terms/';

    const privacyUrl = 'https://sites.google.com/view/nanikiru-archive-privacy';

    // 折りたたみ時に右側へ出すステータス（お好みで調整OK）
    final rightLabel = isFreeTest
        ? '無料開放中'
        : (widget.isPremium ? '有効' : priceLabel);

    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(16),
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
          // ===== タイトル行（ここだけ常に表示）=====
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium, color: Colors.cyanAccent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'プレミアム会員プラン',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.cyanAccent),
                      color: Colors.cyanAccent.withValues(alpha: 0.12),
                    ),
                    child: Text(
                      rightLabel,
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0, // 180°
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),

          // ===== 展開時だけ全内容を表示（プライバシーポリシー含む）=====
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  (widget.isPremium ||
                                      widget.busy ||
                                      isFreeTest)
                                  ? null
                                  : widget.onBuy,
                              icon: const Icon(Icons.lock_open),
                              label: Text(
                                isFreeTest
                                    ? 'クローズドテスト中（自動開放）'
                                    : (widget.isPremium
                                          ? '購入済み'
                                          : '購入する ($priceLabel)'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyanAccent,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (!isFreeTest)
                            OutlinedButton.icon(
                              onPressed: widget.busy ? null : widget.onRestore,
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.cyanAccent,
                              ),
                              label: const Text('復元'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.cyanAccent,
                                side: const BorderSide(
                                  color: Colors.cyanAccent,
                                  width: 1.4,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(color: Colors.cyanAccent, height: 20),

                      // サブスク必須説明
                      _SubscriptionNoteSection(priceLabel: priceLabel),

                      const SizedBox(height: 8),

                      // 利用規約 / プライバシーポリシー
                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          children: [
                            TextButton(
                              onPressed: () => _launchExternalUrl(termsUrl),
                              child: Text(
                                Platform.isIOS
                                    ? '利用規約（EULA）'
                                    : 'Google Play 利用規約',
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
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// サブスクリプションに関する必須説明文
class _SubscriptionNoteSection extends StatelessWidget {
  final String priceLabel;
  const _SubscriptionNoteSection({required this.priceLabel});

  @override
  Widget build(BuildContext context) {
    final text = Platform.isIOS
        ? '・サブスクリプション期間：1か月（自動更新）\n'
              '・料金：$priceLabel（地域により異なる場合があります）\n'
              '・期間終了の24時間前までに解約しない限り、自動的に更新されます。\n'
              '・購入後は、端末の「設定」アプリ > Apple ID > サブスクリプション から自動更新を停止・解約できます。'
        : '・サブスクリプション期間：1か月（自動更新）\n'
              '・料金：$priceLabel（地域により異なる場合があります）\n'
              '・期間終了の24時間前までに解約しない限り、自動的に更新されます。\n'
              '・購入後は、Google Play ストアアプリ > 右上のプロフィールアイコン > '
              '「お支払いと定期購入」から自動更新を停止・解約できます。';

    return Text(
      text,
      style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
    );
  }
}

// ===== 課金カード（デバッグ用：kDebugMode のときだけ表示）=====
class _PremiumDebugCard extends StatelessWidget {
  final bool isPremium;
  final bool serverIsPremium;
  final bool? debugOverride;
  final VoidCallback onForceOn;
  final VoidCallback onForceOff;
  final VoidCallback onClear;

  const _PremiumDebugCard({
    required this.isPremium,
    required this.serverIsPremium,
    required this.debugOverride,
    required this.onForceOn,
    required this.onForceOff,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    String overrideLabel;
    if (debugOverride == null) {
      overrideLabel = '未指定（サーバー値を使用）';
    } else if (debugOverride == true) {
      overrideLabel = '強制ON';
    } else {
      overrideLabel = '強制OFF';
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        border: Border.all(color: Colors.greenAccent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bug_report, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text(
                'デバッグ用プレミアム切替',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'serverPremium = $serverIsPremium / override = $overrideLabel\n'
            '⇒ 最終 isPremium = $isPremium',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onForceOn,
                icon: const Icon(Icons.lock_open, color: Colors.greenAccent),
                label: const Text(
                  '強制ON',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onForceOff,
                icon: const Icon(Icons.lock_reset, color: Colors.redAccent),
                label: const Text(
                  '強制OFF',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              OutlinedButton(
                onPressed: onClear,
                child: const Text(
                  '解除（サーバー値）',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '※ デバッグビルドのみ。Firestore の isPremium は変更しません。',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ===== ロック表示（非課金時に見せる置き換えUI）=====
class _LockedNotice extends StatelessWidget {
  final String title;
  const _LockedNotice({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        border: Border.all(color: Colors.cyanAccent, width: 1.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Colors.cyanAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('Premium', style: TextStyle(color: Colors.cyanAccent)),
        ],
      ),
    );
  }
}

// ===== 所属ボックス =====
class _AffiliationsBox extends StatelessWidget {
  final List<Map<String, String>> affiliations;
  const _AffiliationsBox({required this.affiliations});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '所属：',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.cyan, blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: affiliations
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${e['affiliation']}  ${e['rank']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.cyan, blurRadius: 6)],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ===== お気に入り一覧 =====
class _FavoritePostsList extends StatelessWidget {
  final String uid;
  final AudioPlayer player;
  final ScrollController parent;
  const _FavoritePostsList({
    required this.uid,
    required this.player,
    required this.parent,
  });

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final favMap =
            (snap.data?.data()?['favoritePosts'] as Map?)
                ?.cast<String, dynamic>() ??
            const {};
        final postIds = favMap.entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toList();

        if (postIds.isEmpty) {
          return const Text(
            'お気に入りはまだありません',
            style: TextStyle(color: Colors.white70),
          );
        }

        Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        fetchPosts() async {
          final db = FirebaseFirestore.instance;
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> all = [];
          for (var i = 0; i < postIds.length; i += 10) {
            final chunk = postIds.sublist(i, (i + 10).clamp(0, postIds.length));
            final qs = await db
                .collection('posts')
                .where(FieldPath.documentId, whereIn: chunk)
                .get();
            all.addAll(qs.docs);
          }
          all.sort((a, b) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];
            final va = (ta is Timestamp) ? ta.millisecondsSinceEpoch : 0;
            final vb = (tb is Timestamp) ? tb.millisecondsSinceEpoch : 0;
            return vb.compareTo(va);
          });
          return all;
        }

        return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: fetchPosts(),
          builder: (context, postSnap) {
            if (!postSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = postSnap.data!;
            // navIds（お気に入り一覧の並び順）
            final navIds = posts.map((d) => d.id).toList();

            return Container(
              height: 360,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.30),
                border: Border.all(color: Colors.cyanAccent, width: 1.5),
                borderRadius: BorderRadius.zero,
              ),
              child: NotificationListener<OverscrollIndicatorNotification>(
                onNotification: (n) {
                  n.disallowIndicator();
                  return true;
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is OverscrollNotification) {
                      if (parent.hasClients) {
                        final pos = parent.position;
                        final target = (pos.pixels + n.overscroll).clamp(
                          0.0,
                          pos.maxScrollExtent,
                        );
                        pos.jumpTo(target);
                        return true;
                      }
                    }
                    return false;
                  },
                  child: ListView.separated(
                    primary: false,
                    physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.zero,
                    itemCount: posts.length,
                    separatorBuilder: (_a, _b) => const Divider(
                      color: Colors.cyanAccent,
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, i) {
                      final p = posts[i].data();
                      final tiles = ((p['tiles'] ?? []) as List).cast<String>();
                      final ruleType = (p['ruleType'] ?? '') as String;
                      final postType = (p['postType'] ?? '') as String;
                      final postUserId = (p['userId'] ?? '') as String;

                      final meldDisplayGroups = _readMeldDisplayGroups(p);

                      return InkWell(
                        onTap: () {
                          player.play(AssetSource('sounds/cyber_click.mp3'));
                          Navigator.push(
                            context,
                            _noAnimRoute(
                              DetailPage(
                                postId: posts[i].id,
                                source: 'mypage',
                                currentIndex: 2, // BottomNav: MyPage
                                navIds: navIds,
                                navIndex: i,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TileStrip(
                                tiles: tiles,
                                meldGroups: meldDisplayGroups,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$ruleType / $postType',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                future: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(postUserId)
                                    .get(),
                                builder: (context, s) {
                                  if (!s.hasData) {
                                    return const Text(
                                      '読み込み中…',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    );
                                  }
                                  final u = s.data?.data() ?? {};
                                  final nickname = (u['nickname'] ?? '匿名')
                                      .toString();
                                  final affs =
                                      (u['affiliations'] as List? ?? const [])
                                          .whereType<Map>()
                                          .map((m) {
                                            final a = (m['affiliation'] ?? '')
                                                .toString();
                                            final r = (m['rank'] ?? '')
                                                .toString();
                                            return a.isEmpty
                                                ? ''
                                                : (r.isEmpty ? a : '$a($r)');
                                          })
                                          .where((e) => e.isNotEmpty)
                                          .join('・');
                                  final line2 = affs.isEmpty
                                      ? nickname
                                      : '$nickname / $affs';
                                  return Text(
                                    line2,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Firestoreの meldGroups から「表示用の牌配列(List<List<String>>）」だけ取り出す
List<List<String>> _readMeldDisplayGroups(Map<String, dynamic> data) {
  final out = <List<String>>[];
  final mg = data['meldGroups'];
  if (mg is List) {
    for (final g in mg) {
      if (g is Map) {
        final disp =
            (g['displayTiles'] as List? ?? g['tiles'] as List? ?? const [])
                .map((e) => e?.toString() ?? '')
                .where((e) => e.isNotEmpty)
                .cast<String>()
                .toList();
        if (disp.isNotEmpty) out.add(disp);
      }
    }
  }
  return out;
}

/// 手牌＋副露を同じ行に並べる行ウィジェット
class _TileStrip extends StatelessWidget {
  final List<String> tiles; // 手牌
  final List<List<String>>? meldGroups; // 副露（オプション）

  const _TileStrip({required this.tiles, this.meldGroups});

  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    final allGroups = meldGroups ?? [];

    return LayoutBuilder(
      builder: (context, c) {
        final totalTiles =
            tiles.length +
            allGroups.fold<int>(0, (acc, g) => acc + g.length) +
            (allGroups.isEmpty ? 0 : allGroups.length - 1);

        final tileW = c.maxWidth / totalTiles;
        final tileH = tileW * 1.5;

        return SizedBox(
          width: c.maxWidth,
          height: tileH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ...tiles.map((id) => _buildTile(id, tileW, tileH)),
              ...allGroups.asMap().entries.expand((entry) {
                final gi = entry.key;
                final g = entry.value;
                final list = <Widget>[];
                if (gi > 0 || tiles.isNotEmpty) {
                  list.add(SizedBox(width: tileW * 0.3));
                }
                list.addAll(
                  g.map((id) => _buildTile(id, tileW * 0.9, tileH * 0.9)),
                );
                return list;
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTile(String id, double w, double h) {
    final assetId = (id == '0') ? '0' : id;
    return SizedBox(
      width: w,
      height: h,
      child: Image.asset(
        _asset(assetId),
        fit: BoxFit.contain,
        errorBuilder: (_c, _d, _e) => Center(
          child: Text(assetId, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

// ====== 既存の Likes 集計を流用 ======
Stream<int> _postLikesTotal(String uid) {
  return FirebaseFirestore.instance
      .collection('posts')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map(
        (qs) => qs.docs.fold<int>(0, (s, d) => s + ((d['likes'] ?? 0) as int)),
      );
}

Stream<int> _answerLikesTotal(String uid) {
  return FirebaseFirestore.instance
      .collectionGroup('answers')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map(
        (qs) => qs.docs.fold<int>(0, (s, d) => s + ((d['likes'] ?? 0) as int)),
      );
}

class _LikesStatsRow extends StatelessWidget {
  final String uid;
  const _LikesStatsRow({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<int>(
          stream: _postLikesTotal(uid),
          builder: (context, snap) {
            return _StatBlock(
              value: '${snap.data ?? 0}',
              label: '投稿お気に入り数',
              icon: const Icon(Icons.star, color: Colors.yellow, size: 20),
            );
          },
        ),
        StreamBuilder<int>(
          stream: _answerLikesTotal(uid),
          builder: (context, snap) {
            return _StatBlock(
              value: '${snap.data ?? 0}',
              label: '回答いいね数',
              icon: const Icon(
                Icons.favorite,
                color: Colors.pinkAccent,
                size: 20,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;
  final Widget? icon;
  const _StatBlock({required this.value, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 4)],
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.cyan, blurRadius: 6)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

// ===== 自分の投稿履歴（myPosts配列を参照） =====
class _MyPostHistoryList extends StatelessWidget {
  final String uid;
  final AudioPlayer player;
  final ScrollController parent;
  const _MyPostHistoryList({
    required this.uid,
    required this.player,
    required this.parent,
  });

  Future<void> _confirmAndDelete(BuildContext context, String postId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('削除しますか？', style: TextStyle(color: Colors.white)),
        content: const Text(
          'この投稿（回答含む）を削除します。元に戻せません。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'キャンセル',
              style: TextStyle(color: Colors.cyanAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final db = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;
    final postRef = db.collection('posts').doc(postId);
    final userRef = db.collection('users').doc(uid);

    try {
      final snap = await postRef.get();
      final data = snap.data();
      final String? imagePath = (data?['imagePath'] as String?);
      final String? imageUrl = (data?['imageUrl'] as String?);

      QuerySnapshot<Map<String, dynamic>> ans;
      do {
        ans = await postRef.collection('answers').limit(400).get();
        if (ans.docs.isEmpty) break;
        final batch = db.batch();
        for (final d in ans.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      } while (ans.docs.isNotEmpty);

      try {
        if (imagePath != null && imagePath.isNotEmpty) {
          await storage.ref(imagePath).delete();
        } else if (imageUrl != null && imageUrl.isNotEmpty) {
          await storage.refFromURL(imageUrl).delete();
        }
      } catch (_) {}

      final batch = db.batch();
      batch.delete(postRef);
      batch.set(userRef, {
        'myPosts': FieldValue.arrayRemove([postId]),
      }, SetOptions(merge: true));
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('投稿を削除しました')));
      }
    } catch (e) {
      final msg = e is FirebaseException ? e.code : e.toString();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました ($msg)')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final myPosts =
            (snap.data?.data()?['myPosts'] as List?)?.cast<String>() ??
            const [];

        if (myPosts.isEmpty) {
          return const Text(
            'まだ投稿がありません',
            style: TextStyle(color: Colors.white70),
          );
        }

        Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        fetchPosts() async {
          final db = FirebaseFirestore.instance;
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> all = [];
          for (var i = 0; i < myPosts.length; i += 10) {
            final chunk = myPosts.sublist(i, (i + 10).clamp(0, myPosts.length));
            final qs = await db
                .collection('posts')
                .where(FieldPath.documentId, whereIn: chunk)
                .get();
            all.addAll(qs.docs);
          }
          all.sort((a, b) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];
            final va = (ta is Timestamp) ? ta.millisecondsSinceEpoch : 0;
            final vb = (tb is Timestamp) ? tb.millisecondsSinceEpoch : 0;
            return vb.compareTo(va);
          });
          return all;
        }

        return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: fetchPosts(),
          builder: (context, postSnap) {
            if (!postSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = postSnap.data!;
            // 自分の投稿履歴の navIds
            final navIds = posts.map((d) => d.id).toList();

            return Container(
              height: 360,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.30),
                border: Border.all(color: Colors.cyanAccent, width: 1.5),
                borderRadius: BorderRadius.zero,
              ),
              child: NotificationListener<OverscrollIndicatorNotification>(
                onNotification: (n) {
                  n.disallowIndicator();
                  return true;
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is OverscrollNotification) {
                      if (parent.hasClients) {
                        final pos = parent.position;
                        final target = (pos.pixels + n.overscroll).clamp(
                          0.0,
                          pos.maxScrollExtent,
                        );
                        pos.jumpTo(target);
                        return true;
                      }
                    }
                    return false;
                  },
                  child: ListView.separated(
                    primary: false,
                    physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.zero,
                    itemCount: posts.length,
                    separatorBuilder: (_a, _b) => const Divider(
                      color: Colors.cyanAccent,
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, i) {
                      final p = posts[i].data();
                      final tiles = ((p['tiles'] ?? []) as List).cast<String>();
                      final ruleType = (p['ruleType'] ?? '') as String;
                      final postType = (p['postType'] ?? '') as String;
                      final postId = posts[i].id;

                      final meldDisplayGroups = _readMeldDisplayGroups(p);

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: LayoutBuilder(
                          builder: (context, bc) {
                            const reservedForIcon = 32.0;
                            final tilesCount = tiles.length.clamp(1, 14);
                            final tileW =
                                (bc.maxWidth - reservedForIcon) / tilesCount;
                            final tileH = tileW * 1.5;

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      player.play(
                                        AssetSource('sounds/cyber_click.mp3'),
                                      );
                                      Navigator.push(
                                        context,
                                        _noAnimRoute(
                                          DetailPage(
                                            postId: postId,
                                            source: 'mypage',
                                            currentIndex: 2,
                                            navIds: navIds,
                                            navIndex: i,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _TileStrip(
                                          tiles: tiles,
                                          meldGroups: meldDisplayGroups,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '$ruleType / $postType',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: reservedForIcon,
                                  height: tileH,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 36,
                                        maxWidth: 36,
                                        maxHeight: 36,
                                      ),
                                      iconSize: 26,
                                      splashRadius: 22,
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () =>
                                          _confirmAndDelete(context, postId),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
