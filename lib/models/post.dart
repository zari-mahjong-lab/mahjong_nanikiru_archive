import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  // 画像
  final String imageUrl;

  /// Storage 上のパス（例: post_images/xxx.jpg）※任意
  final String? imagePath;

  // 問題の補足
  final String description;

  // 問題タイプ（牌効率/押し引き/リーチ判断/副露判断/アシスト/その他）
  final String postType;

  // 牌姿（手牌）
  final List<String> tiles;

  // 作成日時
  final Timestamp createdAt;

  // 投稿者情報
  final String userId;
  final String userName;

  // いいね/コメント数（将来用）
  final int likes;
  final int commentsCount;

  /// 麻雀のルール（例：四麻・半荘 / 四麻・東風 / 三麻）
  final String ruleType;

  /// 投稿者自身が選んだ「切る牌」
  /// - 通常: ここに切る牌
  /// - リーチ判断: ここに切る牌（別途 [reach] でリーチ/非リーチを保持）
  /// - 副露判断: 鳴く場合は「鳴いた後に切る牌」を入れてもOK（下の [callDiscard] と重複可）
  final String? answerTile;

  /// 投稿者のコメント（理由など）
  final String? answerComment;

  // ---------- 判断の構造化保存 ----------
  /// リーチ判断の結果（true: リーチする / false: リーチしない / null: 該当なし）
  final bool? reach;

  /// 副露判断の「鳴く/スルー」（true: 鳴く / false: スルー / null: 該当なし）
  final bool? call;

  /// 副露判断で「鳴く」場合に使う2枚（順不同で2枚想定）
  final List<String>? callTiles; // 例: ['3p','4p']

  /// 副露判断で「鳴く」場合に、鳴いた後に切る牌
  final String? callDiscard;

  const Post({
    required this.imageUrl,
    this.imagePath,
    required this.description,
    required this.postType,
    required this.tiles,
    required this.createdAt,
    required this.userId,
    required this.userName,
    this.likes = 0,
    this.commentsCount = 0,
    required this.ruleType,
    this.answerTile,
    this.answerComment,
    this.reach,
    this.call,
    this.callTiles,
    this.callDiscard,
  });

  /// Firestore へ保存する Map。
  /// ルールに合わせて **null / 空** はキーごと省略します。
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'imageUrl': imageUrl,
      'description': description,
      'postType': postType,
      'tiles': tiles,
      'createdAt': createdAt,
      'userId': userId,
      'userName': userName,
      'likes': likes,
      'commentsCount': commentsCount,
      'ruleType': ruleType,
    };

    // 任意フィールドは "存在すれば" の型チェックに通すため null は入れない
    if (imagePath != null && imagePath!.isNotEmpty) {
      map['imagePath'] = imagePath;
    }
    if (answerTile != null && answerTile!.isNotEmpty) {
      map['answerTile'] = answerTile;
    }
    if (answerComment != null && answerComment!.isNotEmpty) {
      map['answerComment'] = answerComment;
    }
    if (reach != null) map['reach'] = reach;
    if (call != null) map['call'] = call;
    if (callTiles != null && callTiles!.isNotEmpty) {
      map['callTiles'] = callTiles;
    }
    if (callDiscard != null && callDiscard!.isNotEmpty) {
      map['callDiscard'] = callDiscard;
    }
    return map;
  }

  factory Post.fromMap(Map<String, dynamic> map, String documentId) {
    return Post(
      imageUrl: map['imageUrl'] as String,
      imagePath: map['imagePath'] as String?,
      description: map['description'] as String,
      postType: map['postType'] as String,
      tiles: List<String>.from(map['tiles'] ?? const <String>[]),
      createdAt: map['createdAt'] as Timestamp,
      userId: map['userId'] as String,
      userName: map['userName'] as String,
      likes: (map['likes'] ?? 0) as int,
      commentsCount: (map['commentsCount'] ?? 0) as int,
      ruleType: (map['ruleType'] ?? '四麻・半荘') as String,
      answerTile: map['answerTile'] as String?,
      answerComment: map['answerComment'] as String?,
      reach: map['reach'] as bool?,
      call: map['call'] as bool?,
      callTiles: map['callTiles'] != null
          ? List<String>.from(map['callTiles'] as List)
          : null,
      callDiscard: map['callDiscard'] as String?,
    );
  }
}
