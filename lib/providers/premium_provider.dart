// lib/providers/premium_provider.dart
import 'dart:async';
import '../config/build_config.dart';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore の users/{uid}.isPremium を監視して
/// アプリ全体の「課金状態」を提供する Provider。
///
/// デバッグ用に override を持たせて、
/// - null  : サーバー値そのまま
/// - true  : 強制プレミアム
/// - false : 強制非プレミアム
/// という 3 状態にしています。
class PremiumProvider extends ChangeNotifier {
  bool _serverPremium = false;      // Firestore 上の isPremium
  bool? _debugOverride;            // null: 未指定, true: 強制ON, false: 強制OFF

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  PremiumProvider() {
    // ログイン状態の変化を監視
    _authSub =
        FirebaseAuth.instance.authStateChanges().listen(_handleAuthChanged);
  }

  /// 画面側が参照する最終的な isPremium
  ///
  /// 優先順位:
  ///   1. デバッグ用 override（Debug ビルドでの強制 ON/OFF）
  ///   2. クローズドテスト用フラグ（FREE_PREMIUM=true ビルド時は常に true）
  ///   3. Firestore 上の isPremium
  bool get isPremium {
    // ① デバッグ用の強制 ON / OFF があればそれを最優先
    if (_debugOverride != null) {
      return _debugOverride!;
    }

    // ② クローズドテスト用ビルドなら全ユーザー強制プレミアム
    if (kFreePremiumForClosedTest) {
      return true;
    }

    // ③ それ以外はサーバー値
    return _serverPremium;
  }

  /// サーバー上の素の値（デバッグ表示用）
  bool get serverIsPremium => _serverPremium;

  /// デバッグ override 状態（null / true / false）
  bool? get debugOverride => _debugOverride;

  void _handleAuthChanged(User? user) {
    _userSub?.cancel();
    _userSub = null;
    _serverPremium = false;

    if (user == null) {
      // ログアウト時は false に戻す
      notifyListeners();
      return;
    }

    final uid = user.uid;
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      final fromServer = (data?['isPremium'] ?? false) as bool;
      if (fromServer != _serverPremium) {
        _serverPremium = fromServer;
        notifyListeners();
      }
    });
  }

  /// （必要なら）サーバー側の値を直接上書きしたいとき用
  void setServerPremium(bool value) {
    if (value == _serverPremium) return;
    _serverPremium = value;
    notifyListeners();
  }

  /// デバッグ用:
  ///   null  → サーバー値に戻す
  ///   true  → 強制プレミアム
  ///   false → 強制非プレミアム
  void setDebugPremium(bool? v) {
    if (v == _debugOverride) return;
    _debugOverride = v;
    notifyListeners();
  }

  void clearDebugOverride() => setDebugPremium(null);

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }
}
