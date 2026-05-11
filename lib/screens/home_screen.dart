import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/omr_notifier.dart';
import '../services/omr_service.dart';
import '../theme/app_theme.dart';
import 'results_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _fadeIn;
  late final Animation<double>   _slideIn;
  late final Animation<double>   _pulse;

  final _picker  = ImagePicker();
  final _service = const OmrService();

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fadeIn  = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _slideIn = Tween<double>(begin: 28, end: 0).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.035).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanDocument() async {
    final path = await _service.scanDocument();
    if (path == null || !mounted) return;
    _goToResults(path);
  }

  Future<void> _pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null || !mounted) return;
    _goToResults(file.path);
  }

  void _goToResults(String path) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        imagePath: path,
        notifier: OmrNotifier(const OmrService()),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 360;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _entranceCtrl,
          builder: (_, child) => Opacity(
            opacity: _fadeIn.value,
            child: Transform.translate(
              offset: Offset(0, _slideIn.value),
              child: child,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: isCompact ? AppSpacing.lg : AppSpacing.xl),
                      _buildHeader(isCompact),
                      SizedBox(height: isCompact ? AppSpacing.md : AppSpacing.lg),
                      _buildStaffCard(),
                      SizedBox(height: isCompact ? AppSpacing.md : AppSpacing.lg),
                      _buildFeatureList(isCompact),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
              ),
              _buildActions(),
              SizedBox(height: isCompact ? AppSpacing.md : AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    final titleSize = isCompact ? 34.0 : 42.0;
    final letterSpacing = isCompact ? -1.2 : -1.8;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.md),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Metro Sheet\n',
                  style: TextStyle(
                    fontSize:      titleSize,
                    fontWeight:    FontWeight.w700,
                    height:        1.05,
                    letterSpacing: letterSpacing,
                    color:         AppColors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: 'Vision',
                  style: TextStyle(
                    fontSize:      titleSize,
                    fontWeight:    FontWeight.w700,
                    height:        1.05,
                    letterSpacing: letterSpacing,
                    color:         AppColors.accentGold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isCompact ? 6 : AppSpacing.sm),
          Text(
            'On-device Optical Music Recognition for piano learners to detect accidentals in sheet music. Accidentals change a note by a semitone (sharp raises, flat lowers, natural cancels).',
            style: TextStyle(
              fontSize: isCompact ? 14 : 15,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.accentGold.withAlpha(18), AppColors.backgroundSecondary],
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.accentGold.withAlpha(45), width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: CustomPaint(
            painter: _StaffPainter(),
            size: const Size(double.infinity, 100),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureList(bool isCompact) {
    const features = [
      (symbol: '♮', label: 'Natural', detail: 'Cancel accidental'),
      (symbol: '♯', label: 'Sharp',   detail: 'Raise by semitone'),
      (symbol: '♭', label: 'Flat',    detail: 'Lower by semitone'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CAPABILITIES',
            style: TextStyle(
              fontSize:      11,
              fontWeight:    FontWeight.w600,
              letterSpacing: 1.5,
              color:         AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _CapabilityChip(
                  symbol: features[0].symbol,
                  label: features[0].label,
                  detail: features[0].detail,
                  compact: isCompact,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CapabilityChip(
                  symbol: features[1].symbol,
                  label: features[1].label,
                  detail: features[1].detail,
                  compact: isCompact,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CapabilityChip(
                  symbol: features[2].symbol,
                  label: features[2].label,
                  detail: features[2].detail,
                  compact: isCompact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulse,
            child: _PrimaryButton(
              label: 'Scan Sheet Music',
              icon:  Icons.document_scanner_rounded,
              onTap: _scanDocument,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SecondaryButton(
            label: 'Choose from Library',
            icon:  Icons.photo_library_outlined,
            onTap: _pickFromGallery,
          ),
        ],
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({
    required this.symbol,
    required this.label,
    required this.detail,
    required this.compact,
  });

  final String symbol;
  final String label;
  final String detail;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 12 : 14,
        ),
        decoration: BoxDecoration(
          color:        AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border:       Border.all(color: AppColors.separator, width: 0.8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(symbol, style: TextStyle(fontSize: compact ? 22 : 24)),
            SizedBox(height: compact ? 4 : 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: compact ? 3 : 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                height: 1.25,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.icon, required this.onTap});

  final String     label;
  final IconData   icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFC8952E), Color(0xFFE8C06E)],
              begin: Alignment.centerLeft,
              end:   Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color:      AppColors.accentGold.withAlpha(90),
                blurRadius: 22,
                offset:     const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black, size: 22),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(
                fontSize:      17,
                fontWeight:    FontWeight.w700,
                color:         Colors.black,
                letterSpacing: -0.3,
              )),
            ],
          ),
        ),
      );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.icon, required this.onTap});

  final String     label;
  final IconData   icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color:        AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border:       Border.all(color: AppColors.separator),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}

class _StaffPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color       = AppColors.accentGold.withAlpha(50)
      ..strokeWidth = 0.75;

    const lineCount = 5;
    final staffH   = size.height * 0.50;
    final staffTop = (size.height - staffH) / 2;
    final gap      = staffH / (lineCount - 1);

    for (var i = 0; i < lineCount; i++) {
      final y = staffTop + i * gap;
      canvas.drawLine(Offset(size.width * 0.06, y), Offset(size.width * 0.94, y), linePaint);
    }

    final barPaint = Paint()
      ..color       = AppColors.accentGold.withAlpha(35)
      ..strokeWidth = 0.8;
    for (final xFrac in [0.36, 0.65]) {
      canvas.drawLine(
        Offset(size.width * xFrac, staffTop),
        Offset(size.width * xFrac, staffTop + staffH),
        barPaint,
      );
    }

    final glyphs = <(double, double, double, Color, String)>[
      (0.10, staffTop - gap * 0.5, 30, AppColors.accentGold.withAlpha(180),   '𝄞'),
      (0.40, staffTop + gap * 0.5, 18, AppColors.accentBlue.withAlpha(160),   '♩'),
      (0.50, staffTop + gap * 1.5, 16, AppColors.accentGold.withAlpha(130),   '♪'),
      (0.58, staffTop + gap,       18, AppColors.accentGreen.withAlpha(130),  '♩'),
      (0.70, staffTop + gap * 0.5, 16, AppColors.accentOrange.withAlpha(120), '♪'),
      (0.80, staffTop + gap,       16, AppColors.accentBlue.withAlpha(110),   '♫'),
    ];

    for (final (xFrac, y, fontSize, color, char) in glyphs) {
      final tp = TextPainter(
        text: TextSpan(text: char, style: TextStyle(fontSize: fontSize, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width * xFrac - tp.width / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_StaffPainter _) => false;
}
