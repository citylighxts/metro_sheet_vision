import 'package:flutter/foundation.dart';
import '../models/omr_result.dart';
import '../services/omr_service.dart';

enum OmrStatus { idle, loading, success, error }

class OmrNotifier extends ChangeNotifier {
  OmrNotifier(this._service);

  final OmrServiceInterface _service;

  OmrStatus  _status = OmrStatus.idle;
  OmrResult? _result;
  String     _error  = '';

  OmrStatus  get status => _status;
  OmrResult? get result => _result;
  String     get error  => _error;

  Future<void> analyze(String imagePath) async {
    _status = OmrStatus.loading;
    _error  = '';
    notifyListeners();

    try {
      final symbols = await _service.analyzeSheet(imagePath);
      _result = OmrResult(imagePath: imagePath, symbols: symbols);
      _status = OmrStatus.success;
    } catch (e) {
      _error  = e.toString();
      _status = OmrStatus.error;
    }
    notifyListeners();
  }

  void reset() {
    _status = OmrStatus.idle;
    _result = null;
    _error  = '';
    notifyListeners();
  }
}
