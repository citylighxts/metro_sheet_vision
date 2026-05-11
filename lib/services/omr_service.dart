import 'package:flutter/services.dart';
import '../models/detected_symbol.dart';

abstract interface class OmrServiceInterface {
  Future<List<DetectedSymbol>> analyzeSheet(String imagePath);
  Future<String?> scanDocument();
}

final class OmrService implements OmrServiceInterface {
  const OmrService();

  static const _channel = MethodChannel('com.hana.metro_sheet_vision/omr');

  @override
  Future<List<DetectedSymbol>> analyzeSheet(String imagePath) async {
    final json = await _channel.invokeMethod<String>(
          'analyzeSheet',
          {'imagePath': imagePath},
        ) ??
        '[]';
    return DetectedSymbol.fromJsonString(json)
        .where((s) => s.label != 'noteheadFull' && s.label != 'noteheadHalf')
        .toList();
  }

  @override
  Future<String?> scanDocument() =>
      _channel.invokeMethod<String>('scanDocument');
}
