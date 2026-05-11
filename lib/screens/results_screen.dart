import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/detected_symbol.dart';
import '../models/omr_result.dart';
import '../providers/omr_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/sheet_overlay_painter.dart';

const _descriptions = <String, String>{
  'accidentalFlat':    'Flat (♭) — lowers the note by one semitone. Applies for the rest of the measure.',
  'accidentalNatural': 'Natural (♮) — cancels a previous sharp or flat, returning the note to its original pitch.',
  'accidentalSharp':   'Sharp (♯) — raises the note by one semitone. Applies for the rest of the measure.',
};

class ResultsScreen extends StatefulWidget {
  final String      imagePath;
  final OmrNotifier notifier;

  const ResultsScreen({super.key, required this.imagePath, required this.notifier});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> with TickerProviderStateMixin {
  late final AnimationController _overlayCtrl;
  late final AnimationController _flyCtrl;
  late final CurvedAnimation     _flyCurve;

  final _transformCtrl = TransformationController();
  Matrix4? _flyBegin, _flyEnd;

  ui.Image?          _uiImage;
  Map<String, Color> _colorMap  = {};
  DetectedSymbol?    _selected;
  Size               _canvasSize = Size.zero;

  final _expanded = <String, bool>{};

  @override
  void initState() {
    super.initState();

    _overlayCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _flyCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _flyCurve    = CurvedAnimation(parent: _flyCtrl, curve: Curves.easeInOutCubic);
    _flyCtrl.addListener(_onFlyTick);

    widget.notifier.addListener(_onNotifierChanged);
    _loadImage();
    widget.notifier.analyze(widget.imagePath);
  }

  @override
  void dispose() {
    _overlayCtrl.dispose();
    _flyCtrl.dispose();
    _flyCurve.dispose();
    _transformCtrl.dispose();
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _uiImage = frame.image);
  }

  void _onNotifierChanged() {
    if (widget.notifier.status == OmrStatus.success) {
      final labels = widget.notifier.result!.symbols.map((s) => s.label).toSet().toList();
      _colorMap = {
        for (var i = 0; i < labels.length; i++)
          labels[i]: AppColors.symbolPalette[i % AppColors.symbolPalette.length],
      };
      for (final l in labels) {
        _expanded[l] ??= true;
      }
      _overlayCtrl.forward();
    }
    if (mounted) setState(() {});
  }

  void _onFlyTick() {
    if (_flyBegin == null || _flyEnd == null) return;
    _transformCtrl.value = _lerpMatrix4(_flyBegin!, _flyEnd!, _flyCurve.value);
  }

  void _flyToSymbol(DetectedSymbol sym) {
    if (_uiImage == null || _canvasSize == Size.zero) return;

    final imageSize = Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble());
    final fitted    = applyBoxFit(BoxFit.contain, imageSize, _canvasSize);
    final destRect  = Alignment.topCenter.inscribe(fitted.destination, Offset.zero & _canvasSize);

    final symCX = destRect.left + (sym.normX + sym.normWidth  / 2) * destRect.width;
    final symCY = destRect.top  + (sym.normY + sym.normHeight / 2) * destRect.height;

    const scale = 4.0;
    final target = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, _canvasSize.width  / 2 - scale * symCX)
      ..setEntry(1, 3, _canvasSize.height / 2 - scale * symCY);

    _flyBegin = _transformCtrl.value.clone();
    _flyEnd   = target;
    _flyCtrl.forward(from: 0);
  }

  void _resetZoom() {
    _flyBegin = _transformCtrl.value.clone();
    _flyEnd   = Matrix4.identity();
    _flyCtrl.forward(from: 0);
  }

  static Matrix4 _lerpMatrix4(Matrix4 a, Matrix4 b, double t) {
    final s = a.storage, e = b.storage;
    return Matrix4(
      s[0]  + (e[0]  - s[0])  * t,  s[1]  + (e[1]  - s[1])  * t,
      s[2]  + (e[2]  - s[2])  * t,  s[3]  + (e[3]  - s[3])  * t,
      s[4]  + (e[4]  - s[4])  * t,  s[5]  + (e[5]  - s[5])  * t,
      s[6]  + (e[6]  - s[6])  * t,  s[7]  + (e[7]  - s[7])  * t,
      s[8]  + (e[8]  - s[8])  * t,  s[9]  + (e[9]  - s[9])  * t,
      s[10] + (e[10] - s[10]) * t,  s[11] + (e[11] - s[11]) * t,
      s[12] + (e[12] - s[12]) * t,  s[13] + (e[13] - s[13]) * t,
      s[14] + (e[14] - s[14]) * t,  s[15] + (e[15] - s[15]) * t,
    );
  }

  void _onCanvasTap(Offset localPos, OmrResult result) {
    if (_uiImage == null) return;

    final imageSize = Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble());
    final fitted    = applyBoxFit(BoxFit.contain, imageSize, _canvasSize);
    final destRect  = Alignment.topCenter.inscribe(fitted.destination, Offset.zero & _canvasSize);

    DetectedSymbol? hit;
    double hitArea = double.infinity;

    for (final sym in result.symbols) {
      final rect = Rect.fromLTWH(
        destRect.left + sym.normX     * destRect.width,
        destRect.top  + sym.normY     * destRect.height,
        sym.normWidth  * destRect.width,
        sym.normHeight * destRect.height,
      );
      final area = rect.width * rect.height;
      if (rect.inflate(6).contains(localPos) && area < hitArea) {
        hit     = sym;
        hitArea = area;
      }
    }

    if (hit != null) {
      setState(() => _selected = hit);
      _showDescriptionSheet(hit);
    } else {
      setState(() => _selected = null);
    }
  }

  void _showDescriptionSheet(DetectedSymbol sym) {
    final color = _colorMap[sym.label] ?? AppColors.accentBlue;
    final desc  = _descriptions[sym.label] ?? 'Detected symbol: ${sym.label}.';

    showModalBottomSheet<void>(
      context:         context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color:        AppColors.textTertiary.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(sym.label, style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color:        color.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: color.withAlpha(70), width: 0.5),
                  ),
                  child: Text('${(sym.confidence * 100).round()}%',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(desc, style: const TextStyle(
              fontSize: 14, height: 1.6, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:        AppColors.backgroundPrimary,
      extendBodyBehindAppBar: true,
      appBar:                 _buildAppBar(),
      body: widget.notifier.status == OmrStatus.error
          ? _buildErrorView()
          : _buildMainView(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isDone = widget.notifier.status == OmrStatus.success;
    return AppBar(
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:  AppColors.backgroundSecondary.withAlpha(230),
            shape:  BoxShape.circle,
            border: Border.all(color: AppColors.separator, width: 0.5),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
        ),
      ),
      title: const Text('Analysis'),
      actions: [
        if (isDone)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _StatusBadge(count: widget.notifier.result!.symbols.length),
          ),
      ],
    );
  }

  Widget _buildMainView() {
    final result = widget.notifier.result;
    return Stack(
      children: [
        Positioned.fill(
          bottom: result != null ? 220 : 0,
          child: _buildCanvas(result),
        ),
        if (result != null)
          DraggableScrollableSheet(
            initialChildSize: 0.30,
            minChildSize:     0.12,
            maxChildSize:     0.72,
            snap:             true,
            snapSizes:        const [0.12, 0.30, 0.72],
            builder:          (_, ctrl) => _buildBottomPanel(result, ctrl),
          ),
        if (widget.notifier.status == OmrStatus.loading)
          _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildCanvas(OmrResult? result) {
    if (_uiImage == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentGold, strokeWidth: 1.5),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = constraints.biggest;
        return InteractiveViewer(
          transformationController: _transformCtrl,
          minScale:       0.8,
          maxScale:       8.0,
          boundaryMargin: const EdgeInsets.all(100),
          child: GestureDetector(
            onTapUp:    result == null ? null : (d) => _onCanvasTap(d.localPosition, result),
            onDoubleTap: _resetZoom,
            child: AnimatedBuilder(
              animation: Listenable.merge([_overlayCtrl, _transformCtrl]),
              builder: (_, _) => CustomPaint(
                painter: SheetOverlayPainter(
                  image:         _uiImage!,
                  symbols:       result?.symbols ?? [],
                  colorMap:      _colorMap,
                  progress:      _overlayCtrl.value,
                  selectedSymbol: _selected,
                  viewScale:     _transformCtrl.value.storage[0],
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.backgroundPrimary.withAlpha(230),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36, height: 36,
              child: CircularProgressIndicator(color: AppColors.accentGold, strokeWidth: 2),
            ),
            SizedBox(height: 18),
            Text('Analyzing sheet music…', style: TextStyle(
              color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
            SizedBox(height: 5),
            Text('Running on Neural Engine', style: TextStyle(
              color: AppColors.textTertiary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel(OmrResult result, ScrollController ctrl) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color:        AppColors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border:       Border(top: BorderSide(color: AppColors.separator, width: 0.5)),
      ),
      child: CustomScrollView(
        controller: ctrl,
        slivers: [
          SliverToBoxAdapter(child: _dragHandle()),
          SliverToBoxAdapter(child: _summaryRow(result)),
          SliverToBoxAdapter(child: _sectionLabel('DETECTIONS')),
          ..._groupedSlivers(result),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  Widget _dragHandle() => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(
            color:        AppColors.textTertiary.withAlpha(80),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _summaryRow(OmrResult result) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Row(
          children: [
            Expanded(child: _StatChip(value: '${result.symbols.length}', label: 'Symbols', color: AppColors.accentBlue)),
            const SizedBox(width: 10),
            Expanded(child: _StatChip(value: '${result.groupedByLabel.length}', label: 'Types', color: AppColors.accentGold)),
          ],
        ),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, AppSpacing.sm),
        child: Text(text, style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          letterSpacing: 1.5, color: AppColors.textTertiary)),
      );

  List<Widget> _groupedSlivers(OmrResult result) {
    final entries = result.groupedByLabel.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return entries.expand<Widget>((entry) {
      final label  = entry.key;
      final syms   = entry.value;
      final color  = _colorMap[label] ?? AppColors.accentBlue;
      final isOpen = _expanded[label] ?? true;

      return [
        SliverToBoxAdapter(
          child: _GroupHeader(
            label:    label,
            count:    syms.length,
            color:    color,
            isOpen:   isOpen,
            onToggle: () => setState(() => _expanded[label] = !isOpen),
          ),
        ),
        if (isOpen)
          SliverList.separated(
            itemCount:        syms.length,
            separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.separator, indent: 42),
            itemBuilder: (_, i) => _SymbolRow(
              symbol:     syms[i],
              color:      color,
              index:      i + 1,
              isSelected: _selected == syms[i],
              onTap: () {
                setState(() {
                  _selected        = syms[i];
                  _expanded[label] = true;
                });
                _flyToSymbol(syms[i]);
              },
            ),
          ),
      ];
    }).toList();
  }

  Widget _buildErrorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.accentRed, size: 52),
              const SizedBox(height: 18),
              const Text('Analysis Failed', style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(widget.notifier.error, style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 28),
              _RetryButton(onTap: () => widget.notifier.analyze(widget.imagePath)),
            ],
          ),
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:        AppColors.accentGreen.withAlpha(40),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border:       Border.all(color: AppColors.accentGreen.withAlpha(80), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text('$count found', style: const TextStyle(
              fontSize: 12, color: AppColors.accentGreen, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        decoration: BoxDecoration(
          color:        color.withAlpha(25),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border:       Border.all(color: color.withAlpha(60), width: 0.5),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(
              fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.color,
    required this.isOpen,
    required this.onToggle,
  });

  final String     label;
  final int        count;
  final Color      color;
  final bool       isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        color.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$count', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ),
              const SizedBox(width: 6),
              Icon(
                isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: AppColors.textTertiary, size: 20,
              ),
            ],
          ),
        ),
      );
}

class _SymbolRow extends StatelessWidget {
  const _SymbolRow({
    required this.symbol,
    required this.color,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  final DetectedSymbol symbol;
  final Color          color;
  final int            index;
  final bool           isSelected;
  final VoidCallback   onTap;

  @override
  Widget build(BuildContext context) {
    final pct = (symbol.confidence * 100).round();
    return InkWell(
      onTap: onTap,
      child: Container(
        color:   isSelected ? color.withAlpha(22) : null,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text('$index', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500,
                color: isSelected ? color : AppColors.textTertiary)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'x ${(symbol.normX * 100).round()}%  y ${(symbol.normY * 100).round()}%',
                style: TextStyle(fontSize: 13, color: isSelected ? color : AppColors.textSecondary),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$pct%', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                const SizedBox(height: 4),
                SizedBox(
                  width: 60,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value:           symbol.confidence,
                      backgroundColor: color.withAlpha(35),
                      valueColor:      AlwaysStoppedAnimation(color),
                      minHeight:       3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.my_location_rounded,
              size:  15,
              color: isSelected ? color : AppColors.textTertiary.withAlpha(100),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
          decoration: BoxDecoration(
            color:        AppColors.accentBlue,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Text('Retry', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      );
}
