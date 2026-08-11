class BarcodeService {
  String? _lastCode;
  DateTime? _lastScan;

  bool shouldHandle(
    String code, {
    Duration cooldown = const Duration(seconds: 2),
  }) {
    final now = DateTime.now();
    if (_lastCode == code &&
        _lastScan != null &&
        now.difference(_lastScan!) < cooldown) {
      return false;
    }
    _lastCode = code;
    _lastScan = now;
    return true;
  }
}
