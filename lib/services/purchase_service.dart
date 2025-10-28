// lib/services/purchase_service.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'; // debugPrint, kIsWeb
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    as iap_android;

class PurchaseService {
  PurchaseService._();
  static final PurchaseService I = PurchaseService._();

  /// Play/App Store の製品IDと一致させる
  static const String kPremiumMonthlyId = 'premium_monthly';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  List<ProductDetails> _products = const [];
  bool _available = false;
  bool _initialized = false;

  ProductDetails? get premiumProduct {
    try {
      return _products.firstWhere((p) => p.id == kPremiumMonthlyId);
    } catch (_) {
      return null;
    }
  }

  /// 初期化（複数回呼んでも安全）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Web は in_app_purchase 非対応
    if (kIsWeb) {
      debugPrint('[IAP] Web is not supported');
      _available = false;
      return;
    }

    // ★ enablePendingPurchases は最新版では不要
    _available = await _iap.isAvailable();
    if (!_available) {
      debugPrint('[IAP] Store not available');
      return;
    }

    final resp = await _iap.queryProductDetails({kPremiumMonthlyId});
    if (resp.error != null) {
      debugPrint('[IAP] queryProductDetails error: ${resp.error}');
    }
    _products = resp.productDetails;
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint('[IAP] notFoundIDs: ${resp.notFoundIDs}');
    }

    // 二重購読防止
    _sub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (e, st) => debugPrint('[IAP] stream error: $e'),
      onDone: () {
        _sub?.cancel();
        _sub = null;
      },
    );
  }

  Future<void> _ensureReady() async {
    if (!_initialized || !_available || _products.isEmpty) {
      _initialized = false;
      await init();
    }
  }

  /// サブスク購入開始
  Future<void> buyPremium() async {
    await _ensureReady();

    if (!_available) {
      throw 'ストアが利用できません。Play ストア / App Store の状態を確認してください。';
    }
    final product = premiumProduct;
    if (product == null) {
      throw '商品情報 $kPremiumMonthlyId を取得できませんでした。コンソールのIDと一致しているか確認してください。';
    }

    PurchaseParam purchaseParam;
    if (Platform.isAndroid && product is iap_android.GooglePlayProductDetails) {
      purchaseParam = iap_android.GooglePlayPurchaseParam(
        productDetails: product,
      );
    } else {
      purchaseParam = PurchaseParam(productDetails: product);
    }

    // サブスクは非消費型と同じ buyNonConsumable を使う
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// （主に iOS）購入の復元
  Future<void> restore() async {
    await _ensureReady();
    if (!_available) {
      throw 'ストアが利用できません。';
    }
    await _iap.restorePurchases();
  }

  /// purchaseStream のリスナー
  /// listen のシグネチャに合わせて「戻り値 void」で async にする
  void _onPurchaseUpdated(List<PurchaseDetails> updates) async {
    for (final p in updates) {
      debugPrint('[IAP] update: ${p.productID} / ${p.status}');

      switch (p.status) {
        case PurchaseStatus.pending:
          // 待機中
          continue;

        case PurchaseStatus.error:
          debugPrint('[IAP] error: ${p.error}');
          break;

        case PurchaseStatus.canceled:
          debugPrint('[IAP] canceled');
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.productID == kPremiumMonthlyId) {
            final ok = await _verifyPurchase(p);
            if (ok) {
              await _grantPremiumToUser(p);
            }
          }
          break;
      }

      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  /// NOTE: 本番では Cloud Functions 等でレシート/トークン検証を実装してください。
  Future<bool> _verifyPurchase(PurchaseDetails p) async {
    // TODO: サーバー側検証を入れる場合はここを書き換え
    return true;
  }

  Future<void> _grantPremiumToUser(PurchaseDetails p) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'isPremium': true,
      'premiumActivatedAt': FieldValue.serverTimestamp(),
      'premiumProductId': p.productID,
    }, SetOptions(merge: true));
  }

  /// 価格表示（UIで使用）
  String? formattedPrice() => premiumProduct?.price;

  /// 明示的破棄（必要なら）
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _initialized = false;
    _available = false;
    _products = const [];
  }
}
