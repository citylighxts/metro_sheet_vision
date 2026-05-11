import 'detected_symbol.dart';

class OmrResult {
  final String imagePath;
  final List<DetectedSymbol> symbols;

  const OmrResult({required this.imagePath, required this.symbols});

  Map<String, List<DetectedSymbol>> get groupedByLabel {
    final map = <String, List<DetectedSymbol>>{};
    for (final sym in symbols) {
      (map[sym.label] ??= []).add(sym);
    }
    return map;
  }
}
