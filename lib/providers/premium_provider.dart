// lib/providers/premium_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PremiumProvider extends ChangeNotifier {
  bool _serverFlag = false;         // Firestore上の isPremium
  bool _debugOverride = false;      // デバッグ用の手動切替（kDebugMode のみ有効）
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;

  bool get isPremium => _serverFlag || (kDebugMode && _debugOverride);
  bool get serverFlag => _serverFlag;
  bool get debugOverride => _debugOverride;

  Future<void> bindUid(String? uid) async {
    if (_uid == uid) return;
    await _sub?.cancel();
    _uid = uid;
    _serverFlag = false;
    if (uid == null) {
      notifyListeners();
      return;
    }
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    _sub = ref.snapshots().listen((snap) {
      _serverFlag = (snap.data()?['isPremium'] as bool?) ?? false;
      notifyListeners();
    });
  }

  // デバッグ手動切替（リリースでは無視される）
  void setDebugPremium(bool value) {
    _debugOverride = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
