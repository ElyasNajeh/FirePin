import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_services.dart';
import '../../core/ui/components.dart';
import '../../core/ui/live_camera.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import 'onboarding_models.dart';

/// Figma 20:3, using the real camera rather than the design's empty viewport.
class IdentityCaptureScreen extends StatefulWidget {
  const IdentityCaptureScreen({
    super.key,
    required this.services,
    required this.onVerified,
    this.onBack,
  });
  final AppServices services;
  final void Function(Uint8List image, IdentityData identity) onVerified;
  final VoidCallback? onBack;
  @override
  State<IdentityCaptureScreen> createState() => _IdentityCaptureScreenState();
}

class _IdentityCaptureScreenState extends State<IdentityCaptureScreen>
    with SingleTickerProviderStateMixin {
  final _camera = GlobalKey<LiveCameraState>();
  late final _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  Uint8List? _image;
  bool _ready = false;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_busy && _image != null) {
      if (AppMotion.reduced(context)) {
        _scan.stop();
      } else if (!_scan.isAnimating) {
        _scan.repeat();
      }
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await _camera.currentState?.capture();
      if (!mounted) return;
      if (image == null) {
        setState(() => _error = 'تعذّر التقاط الصورة. حاول مرة أخرى.');
        return;
      }
      HapticFeedback.lightImpact();
      setState(() => _image = image);
      if (!AppMotion.reduced(context)) _scan.repeat();
      final result = await widget.services.identity.verify(image);
      if (!mounted) return;
      _scan.stop();
      widget.onVerified(image, result);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذّر فحص الصورة. أعد التصوير وحاول مجددًا.');
      }
    } finally {
      if (mounted) {
        _scan.stop();
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: OnboardingPage(
      onBack: widget.onBack,
      backEnabled: !_busy,
      children: [
        const SizedBox(height: 32),
        Text('صوّر بطاقة الهوية', style: AppType.title),
        const SizedBox(height: 8),
        Text(
          'ضع البطاقة داخل الإطار وتأكد\nأن جميع البيانات واضحة.',
          style: AppType.body,
        ),
        const SizedBox(height: 30),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 430,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(
                  excluding: _image != null,
                  child: LiveCamera(
                    key: _camera,
                    factory: widget.services.camera,
                    active: _image == null,
                    onReady: (ready) {
                      if (mounted && _ready != ready) {
                        setState(() => _ready = ready);
                      }
                    },
                    onSettings: () async {
                      await widget.services.permissions.openAppSettings();
                    },
                  ),
                ),
                if (_image != null)
                  Image.memory(
                    _image!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 196,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(
                                    alpha: _busy ? 0.09 : 0.06,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFDBF2ED,
                                    ).withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              Breathe(
                                enabled: !_busy && _ready,
                                opacity: 0.75,
                                scale: 1,
                                child: const FigmaIcon(
                                  'id_corners',
                                  width: 310,
                                  height: 196,
                                  fit: BoxFit.fill,
                                ),
                              ),
                              if (_busy && _image != null)
                                RepaintBoundary(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: CustomPaint(
                                      painter: _ScanPainter(
                                        _scan,
                                        reduced: AppMotion.reduced(context),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          width: 200,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Breathe(
                                enabled: !_busy && _ready,
                                scale: 1,
                                child: const FigmaIcon('camera_dot', size: 8),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _busy && _image != null
                                      ? 'جارٍ فحص الهوية'
                                      : 'قرّب البطاقة',
                                  style: AppType.text(
                                    16,
                                    color: Colors.white,
                                    weight: FontWeight.w500,
                                    height: 27,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        InlineMessage(_error),
        const SizedBox(height: 26),
        AppButton(
          _busy
              ? 'جارٍ فحص الهوية'
              : _image != null
              ? 'إعادة التصوير'
              : 'التقاط الصورة',
          busy: _busy,
          onPressed: _image != null && !_busy
              ? () => setState(() {
                  _image = null;
                  _error = null;
                })
              : _ready
              ? _capture
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          'التصوير باستخدام الكاميرا مباشرة',
          style: AppType.caption,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.animation, {required this.reduced})
    : super(repaint: animation);
  final Animation<double> animation;
  final bool reduced;
  @override
  void paint(Canvas canvas, Size size) {
    final y = reduced
        ? size.height * 0.5
        : 8 + animation.value * (size.height - 16);
    final trail = Rect.fromLTWH(0, y - 30, size.width, 30);
    canvas.drawRect(
      trail,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x001CBA93), Color(0x551CBA93)],
        ).createShader(trail),
    );
    canvas.drawLine(
      Offset(8, y),
      Offset(size.width - 8, y),
      Paint()
        ..color = const Color(0xFFB6F4D9)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScanPainter oldDelegate) =>
      oldDelegate.reduced != reduced;
}

/// Figma 118:2. The visual communicates a MOCK result, not a local algorithm.
class IdentitySuccessScreen extends StatefulWidget {
  const IdentitySuccessScreen({super.key, required this.onContinue});
  final VoidCallback onContinue;
  @override
  State<IdentitySuccessScreen> createState() => _IdentitySuccessScreenState();
}

class _IdentitySuccessScreenState extends State<IdentitySuccessScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _started = false;
  void _start() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2280), () {
      if (mounted) widget.onContinue();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      HapticFeedback.mediumImpact();
      _start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: OnboardingPage(
      children: [
        const SizedBox(height: 88),
        Center(
          child: Reveal(
            scale: true,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F082E29),
                    blurRadius: 28,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Reveal(
                scale: true,
                delay: const Duration(milliseconds: 70),
                child: Container(
                  width: 154,
                  height: 154,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Reveal(
                    scale: true,
                    delay: Duration(milliseconds: 140),
                    child: FigmaIcon(
                      'identity_success',
                      width: 92,
                      height: 102,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 36),
        Reveal(
          delay: const Duration(milliseconds: 180),
          child: Semantics(
            liveRegion: true,
            child: const PageTitle(
              'تم التحقق من صحة الهوية',
              align: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const CopyBlock(
          'تم التأكد من صلاحية بطاقة الهوية بنجاح.',
          minHeight: 54,
          center: true,
        ),
        const SizedBox(height: 34),
        Reveal(
          delay: const Duration(milliseconds: 240),
          child: Center(
            child: Container(
              width: 214,
              constraints: const BoxConstraints(minHeight: 42),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: AppColors.outline),
              ),
              child: Text(
                '✓ هوية صالحة',
                style: AppType.text(
                  15,
                  color: AppColors.primary,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'سيتم عرض بيانات الهوية الآن',
          textAlign: TextAlign.center,
          style: AppType.caption,
        ),
      ],
    ),
  );
}

/// Figma 109:22 (redesigned review; intentionally no expiry date).
class IdentityReviewScreen extends StatelessWidget {
  const IdentityReviewScreen({
    super.key,
    required this.identity,
    required this.image,
    required this.onContinue,
    this.onBack,
  });
  final IdentityData identity;
  final Uint8List image;
  final VoidCallback onContinue;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => OnboardingPage(
    onBack: onBack,
    children: [
      const SizedBox(height: 32),
      const PageTitle('تم استخراج بيانات الهوية بنجاح', size: 24),
      Text(
        'راجع بياناتك قبل المتابعة',
        style: AppType.text(15, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 20),
      Reveal(
        child: SurfaceCard(
          padding: 15,
          radius: 20,
          shadow: true,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 94,
                  height: 110,
                  // A visual-only crop of the captured photo. NOT face extraction/OCR.
                  child: Image.memory(
                    image,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0.65, 0),
                    errorBuilder: (_, _, _) =>
                        const FigmaIcon('portrait', width: 94, height: 110),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        'الصورة المستخرجة من الهوية',
                        textAlign: TextAlign.center,
                        style: AppType.text(
                          13,
                          color: AppColors.primary,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'تم قص الصورة تلقائيًا من البطاقة المصوّرة.',
                      style: AppType.text(13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'بيانات الهوية',
        style: AppType.text(17, weight: FontWeight.w700, height: 28),
      ),
      const SizedBox(height: 8),
      Reveal(
        delay: const Duration(milliseconds: 50),
        child: _IdentityField('الاسم الكامل', identity.fullName),
      ),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 100),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _IdentityField(
                'رقم الهوية',
                identity.identityNumber,
                latin: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _IdentityField(
                'تاريخ الميلاد',
                identity.birthDate,
                latin: true,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Reveal(
        delay: const Duration(milliseconds: 150),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 116,
              child: _IdentityField('الجنس', identity.gender),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 214,
              child: _IdentityField('العنوان', identity.address),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const FigmaIcon('info', size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'هذه البيانات مستخرجة من صورة الهوية. راجعها قبل المتابعة.',
                style: AppType.text(12, weight: FontWeight.w500, height: 22),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      AppButton('التالي', onPressed: onContinue),
    ],
  );
}

class _IdentityField extends StatelessWidget {
  const _IdentityField(this.label, this.value, {this.latin = false});
  final String label;
  final String value;
  final bool latin;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 70),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppType.text(12, color: AppColors.textSecondary, height: 22),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textDirection: latin ? TextDirection.ltr : TextDirection.rtl,
          textAlign: TextAlign.right,
          style: AppType.text(14, weight: FontWeight.w500, height: 30),
        ),
      ],
    ),
  );
}
