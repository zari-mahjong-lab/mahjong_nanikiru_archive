// lib/screens/my_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../providers/guest_provider.dart';
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

class MyPage extends StatefulWidget {
  const MyPage({super.key});
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final _parentScroll = ScrollController();

  Future<void> _playSE(AudioPlayer player) async {
    await player.play(AssetSource('sounds/cyber_click.mp3'));
  }

  // ★ HomePage と同じテイストの「ページ全体ローディング」
  Widget _buildFullPageLoading() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
            SizedBox(height: 16),
            Text('Now Loading...', style: TextStyle(color: Colors.cyanAccent)),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final isGuest = context.watch<GuestProvider>().isGuest;
    final user = FirebaseAuth.instance.currentUser;
    final player = AudioPlayer();

    // ゲストモード時はこれまでどおり即表示
    if (isGuest || user == null) {
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
        // ★ ここでページ単位ローディングを挟む
        if (snap.connectionState == ConnectionState.waiting) {
          return BaseScaffold(
            title: 'マイページ',
            currentIndex: 2,
            body: _buildFullPageLoading(),
          );
        }
        if (snap.hasError) {
          return BaseScaffold(
            title: 'マイページ',
            currentIndex: 2,
            body: _buildErrorPage('読み込みエラー: ${snap.error}'),
          );
        }

        // ここから先は「ユーザードキュメントが取れてから」だけ実行される
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final nickname =
            (data['nickname'] as String?) ?? (user.displayName ?? 'ユーザー');
        final iconUrl = (data['iconUrl'] as String?) ?? user.photoURL;
        final isPremium = (data['isPremium'] as bool?) ?? false;

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

        // MyPage._MyPageState 内の setPremiumDebug
        Future<void> setPremiumDebug(bool v) async {
          try {
            // ignore: unawaited_futures
            player.play(AssetSource('sounds/cyber_click.mp3'));
          } catch (_) {}

          final doc = FirebaseFirestore.instance.collection('users').doc(uid);

          try {
            if (v) {
              await doc.set({
                'isPremium': true,
                'premiumActivatedAt': FieldValue.serverTimestamp(),
                'premiumDebug': true,
              }, SetOptions(merge: true));
            } else {
              await doc.set({
                'isPremium': false,
                'premiumDebug': true,
              }, SetOptions(merge: true));
              await doc.update({'premiumActivatedAt': FieldValue.delete()});
            }

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(v ? 'プレミアムを有効化（テスト）' : 'プレミアムを無効化（テスト）')),
            );
          } on FirebaseException catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('書き込み失敗: ${e.code}')));
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('書き込み失敗: $e')));
          }
        }

        return BaseScaffold(
          title: 'マイページ',
          currentIndex: 2,
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
                      await _playSE(player);
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

                  // ====== 課金ボタン（エミュ用の疑似動作） ======
                  _PremiumCardDebug(
                    isPremium: isPremium,
                    onActivate: () => setPremiumDebug(true),
                    onDeactivate: () => setPremiumDebug(false),
                  ),

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
                    player: player,
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
                      player: player,
                      parent: _parentScroll,
                    )
                  else
                    const _LockedNotice(title: '投稿履歴（プレミアム限定）'),

                  const SizedBox(height: 32),

                  // ログアウト
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _playSE(player);
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
    super.dispose();
  }
}

// ===== 課金カード（デバッグ用）=====
class _PremiumCardDebug extends StatelessWidget {
  final bool isPremium;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  const _PremiumCardDebug({
    required this.isPremium,
    required this.onActivate,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
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
          const Row(
            children: [
              Icon(Icons.workspace_premium, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text(
                'プレミアム会員（テスト切替）',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPremium
                ? '現在：プレミアムが有効です。全機能をご利用いただけます。'
                : '現在：無料プランです。下記ボタンでテスト的にプレミアムを有効化できます。',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isPremium)
                ElevatedButton.icon(
                  onPressed: onActivate,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('プレミアムを有効化（テスト）'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                ),
              if (isPremium)
                OutlinedButton.icon(
                  onPressed: onDeactivate,
                  icon: const Icon(Icons.lock_reset, color: Colors.cyanAccent),
                  label: const Text('プレミアムを無効化（テスト）'),
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
