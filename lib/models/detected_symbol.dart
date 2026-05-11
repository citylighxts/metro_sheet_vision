import 'dart:convert';

class DetectedSymbol {
  final String label;
  final double confidence;
  final double normX;
  final double normY;
  final double normWidth;
  final double normHeight;

  const DetectedSymbol({
    required this.label,
    required this.confidence,
    required this.normX,
    required this.normY,
    required this.normWidth,
    required this.normHeight,
  });

  factory DetectedSymbol.fromJson(Map<String, dynamic> json) => DetectedSymbol(
        label:      json['label']      as String,
        confidence: (json['confidence'] as num).toDouble(),
        normX:      (json['normX']      as num).toDouble(),
        normY:      (json['normY']      as num).toDouble(),
        normWidth:  (json['normWidth']  as num).toDouble(),
        normHeight: (json['normHeight'] as num).toDouble(),
      );

  static List<DetectedSymbol> fromJsonString(String json) =>
      (jsonDecode(json) as List)
          .map((e) => DetectedSymbol.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  String toString() => 'DetectedSymbol($label, ${(confidence * 100).round()}%)';
}
