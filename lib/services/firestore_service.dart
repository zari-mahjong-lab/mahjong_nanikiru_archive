import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final CollectionReference posts =
      FirebaseFirestore.instance.collection('posts');

  Future<void> addPost({
    required String selectedTile,
    required String comment,
  }) async {
    await posts.add({
      'selectedTile': selectedTile,
      'comment': comment,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
