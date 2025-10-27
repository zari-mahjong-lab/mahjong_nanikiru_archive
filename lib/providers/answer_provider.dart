import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ← Firestore用

class AnswerProvider with ChangeNotifier {
  Future<void> submitAnswer({
    required String selectedTile,
    required String comment,
  }) async {
    try {
      // Firestoreの「answers」コレクションに新しいドキュメントを追加する
      await FirebaseFirestore.instance.collection('answers').add({
        'selectedTile': selectedTile,
        'comment': comment,
        'timestamp': FieldValue.serverTimestamp(), // サーバーの時刻を自動で記録
      });
    } catch (e) {
      print('Firestoreへの書き込みに失敗しました: $e');
    }
  }
}
