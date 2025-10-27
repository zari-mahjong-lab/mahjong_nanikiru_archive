// guest_provider.dart
import 'package:flutter/material.dart';

class GuestProvider with ChangeNotifier {
  bool _isGuest = false;

  bool get isGuest => _isGuest;

  void setGuest(bool value) {
    _isGuest = value;
    notifyListeners();
  }
}
