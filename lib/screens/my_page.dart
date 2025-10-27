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

class MyPage extends StatefulWidget {
  const MyPage({Key? key}) : super(key: key);
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final _parentScroll = ScrollController();

  Future<void> _playSE(AudioPlayer player) async {
    await player.play(AssetSource('sounds/cyber_click.mp3'));
  }

  void _navigateToDetail(
    BuildContext context,
    String postId,
    AudioPlayer player,
  ) async {
    await _playSE(player);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            DetailPage(postId: postId, source: 'mypage', currentIndex: 2),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _showLoginDialog(
    BuildContext context,
    AudioPlayer player,
  ) async {
    await _playSE(player);
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
      context.read<GuestProvider>().setGuest(false);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginSelectionPage()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = context.watch<GuestProvider>().isGuest;
    final user = FirebaseAuth.instance.currentUser;
    final player = AudioPlayer();

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
        final nickname =
            (snap.data?.data()?['nickname'] as String?) ??
            (user.displayName ?? 'ユーザー');
        final iconUrl =
            (snap.data?.data()?['iconUrl'] as String?) ?? user.photoURL;

        final affiliationsRaw =
            (snap.data?.data()?['affiliations'] as List?) ?? const [];
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
          body: Center(
            child: SingleChildScrollView(
              controller: _parentScroll, // ★ 追加
              primary: false, // ★ 変更
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
                  Text(
                    nickname,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (affiliations.isNotEmpty) _affiliationsBox(affiliations),
                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    onPressed: () async {
                      await _playSE(player);
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const ProfileEditPage(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
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

                  // 投稿お気に入り数/回答いいね数（前に作った _LikesStatsRow を再利用）
                  _LikesStatsRow(uid: uid),

                  const SizedBox(height: 32),

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

                  // お気に入り
                  _FavoritePostsList(
                    uid: uid,
                    player: player,
                    parent: _parentScroll,
                  ),

                  const SizedBox(height: 32),

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
                  _MyPostHistoryList(
                    uid: uid,
                    player: player,
                    parent: _parentScroll,
                  ),

                  const SizedBox(height: 32),

                  ElevatedButton.icon(
                    onPressed: () async {
                      await _playSE(player);
                      await FirebaseAuth.instance.signOut();
                      context.read<GuestProvider>().setGuest(false);
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const TitlePage()),
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

// ===== お気に入り一覧 =====
class _FavoritePostsList extends StatelessWidget {
  final String uid;
  final AudioPlayer player;
  final ScrollController parent; // ★ 追加
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

        // Firestore の whereIn は 10 件まで → 10件ずつ分割取得
        Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        _fetchPosts() async {
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
          // createdAt 降順
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
          future: _fetchPosts(),
          builder: (context, postSnap) {
            if (!postSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = postSnap.data!;

            return Container(
              height: 360, // 固定
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.30),
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
                    separatorBuilder: (_, __) => const Divider(
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

                      // 🔹 追加：表示用の副露配列
                      final meldDisplayGroups = _readMeldDisplayGroups(p);

                      return InkWell(
                        onTap: () async {
                          await player.play(
                            AssetSource('sounds/cyber_click.mp3'),
                          );
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) => DetailPage(
                                postId: posts[i].id,
                                source: 'mypage',
                                currentIndex: 2,
                              ),
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
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
                              // 手牌（横幅いっぱい）
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
                .toList()
                .cast<String>();
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

    // 1つのRowに「手牌」＋「副露」を連結して表示
    return LayoutBuilder(
      builder: (context, c) {
        final totalTiles =
            tiles.length +
            allGroups.fold<int>(0, (sum, g) => sum + g.length) +
            (allGroups.isEmpty ? 0 : allGroups.length - 1); // 副露間のスペース考慮

        final tileW = c.maxWidth / totalTiles;
        final tileH = tileW * 1.5;

        return SizedBox(
          width: c.maxWidth,
          height: tileH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 🔹 手牌
              ...tiles.map((id) => _buildTile(id, tileW, tileH)).toList(),

              // 🔹 副露（間にちょっとスペース）
              ...allGroups.asMap().entries.expand((entry) {
                final gi = entry.key;
                final g = entry.value;
                final list = <Widget>[];

                // 副露の前に少し間隔を空ける
                if (gi > 0 || tiles.isNotEmpty) {
                  list.add(SizedBox(width: tileW * 0.3));
                }

                // グループ内の各牌
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

  /// 個々の牌Widget生成（0.pngも通常牌と同じ扱い）
  Widget _buildTile(String id, double w, double h) {
    final assetId = (id == '0') ? '0' : id; // 0 は assets/tiles/0.png を使う
    return SizedBox(
      width: w,
      height: h,
      child: Image.asset(
        _asset(assetId),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(
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

Widget _affiliationsBox(List<Map<String, String>> affiliations) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.3),
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

// ===== 自分の投稿履歴（myPosts配列を参照） =====
class _MyPostHistoryList extends StatelessWidget {
  final String uid;
  final AudioPlayer player;
  final ScrollController parent; // ★ 追加
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
      // まず投稿ドキュメントを取得（画像のURL/Path を読むため）
      final snap = await postRef.get();
      final data = snap.data();
      final String? imagePath = (data?['imagePath'] as String?);
      final String? imageUrl = (data?['imageUrl'] as String?);

      // answers サブコレ削除（バッチ分割）
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

      // Storage の画像を削除（imagePath 優先。なければ imageUrl から ref を復元）
      try {
        if (imagePath != null && imagePath.isNotEmpty) {
          await storage.ref(imagePath).delete();
        } else if (imageUrl != null && imageUrl.isNotEmpty) {
          await storage.refFromURL(imageUrl).delete();
        }
      } catch (_) {
        // 画像が既に無い等は無視（投稿本体の削除は続行）
      }

      // 本体削除 + myPosts から除外
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

        // Firestore whereIn は 10 件まで → チャンクして取得
        Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        _fetchPosts() async {
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
          // createdAt 降順
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
          future: _fetchPosts(),
          builder: (context, postSnap) {
            if (!postSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = postSnap.data!;

            return Container(
              height: 360, // 固定
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.30),
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
                    separatorBuilder: (_, __) => const Divider(
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

                      // 🔹 追加：表示用の副露配列
                      final meldDisplayGroups = _readMeldDisplayGroups(p);

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: LayoutBuilder(
                          builder: (context, bc) {
                            // 🔽 ここだけ差し替え
                            const reservedForIcon = 32.0; // アイコン用の固定幅
                            final tilesCount = tiles.length.clamp(1, 14);
                            final tileW =
                                (bc.maxWidth - reservedForIcon) / tilesCount;
                            final tileH = tileW * 1.5;

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 左：牌画像（手牌＋副露）
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      await player.play(
                                        AssetSource('sounds/cyber_click.mp3'),
                                      );
                                      Navigator.push(
                                        context,
                                        PageRouteBuilder(
                                          pageBuilder: (_, __, ___) =>
                                              DetailPage(
                                                postId: postId,
                                                source: 'mypage',
                                                currentIndex: 2,
                                              ),
                                          transitionDuration: Duration.zero,
                                          reverseTransitionDuration:
                                              Duration.zero,
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

                                // 右：削除ボタン（少し大きく・上寄せ・左余白なし）
                                SizedBox(
                                  width: reservedForIcon,
                                  height: tileH, // 行の高さに合わせる
                                  child: Align(
                                    alignment: Alignment.topCenter, // 🔹 上寄せ
                                    child: IconButton(
                                      padding: EdgeInsets.zero, // 🔹 左余白なし
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 36,
                                        maxWidth: 36,
                                        maxHeight: 36,
                                      ),
                                      iconSize: 26, // 🔹 少し大きく
                                      splashRadius: 22, // 🔹 タップ領域も少し拡大
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
