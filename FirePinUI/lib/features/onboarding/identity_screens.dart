import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/camera_service.dart';
import '../../core/services/device_services.dart';
import '../../core/ui/components.dart';
import '../../core/ui/live_camera.dart';
import '../../theme/app_theme.dart';
import 'identity_document_processor.dart';
import 'identity_image_processor.dart';
import 'onboarding_models.dart';

class IdentityCaptureScreen extends StatefulWidget {
  const IdentityCaptureScreen({
    super.key,
    required this.cameraFactory,
    required this.permissions,
    required this.processor,
    required this.onExtracted,
    this.onBack,
  });

  final CameraSourceFactory cameraFactory;
  final DevicePermissions permissions;
  final IdentityDocumentProcessor processor;
  final ValueChanged<IdentityData> onExtracted;
  final VoidCallback? onBack;

  @override
  State<IdentityCaptureScreen> createState() => _IdentityCaptureScreenState();
}

class _IdentityCaptureScreenState extends State<IdentityCaptureScreen> {
  final _camera = GlobalKey<LiveCameraState>();
  final _identityFrame = GlobalKey();
  bool _ready = false;
  bool _processing = false;
  String? _error;

  Future<void> _capture() async {
    if (!_ready || _processing) return;
    final captureRegion = _currentCaptureRegion();
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final image = await _camera.currentState?.capture();
      if (image == null) {
        throw const IdentityScanFailure(
          'تعذّر التقاط الصورة. ثبّت الهاتف وأعد المحاولة.',
        );
      }
      final identity = await widget.processor.extract(
        image,
        region: captureRegion,
      );
      if (mounted) widget.onExtracted(identity);
    } on IdentityScanFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'تعذّرت معالجة الهوية. تأكد من وضوح البطاقة وأعد التصوير.',
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  IdentityCaptureRegion? _currentCaptureRegion() {
    final previewBox = _camera.currentContext?.findRenderObject() as RenderBox?;
    final frameBox =
        _identityFrame.currentContext?.findRenderObject() as RenderBox?;
    if (previewBox == null ||
        frameBox == null ||
        !previewBox.hasSize ||
        !frameBox.hasSize) {
      return null;
    }
    final previewOrigin = previewBox.localToGlobal(Offset.zero);
    final frameOrigin = frameBox.localToGlobal(Offset.zero) - previewOrigin;
    return IdentityCaptureRegion(
      previewSize: previewBox.size,
      guideRect: frameOrigin & frameBox.size,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        LiveCamera(
          key: _camera,
          factory: widget.cameraFactory,
          active: !_processing,
          onReady: (ready) {
            if (mounted && _ready != ready) setState(() => _ready = ready);
          },
          onSettings: () {
            widget.permissions.openAppSettings();
          },
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.20)),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('identity-capture-back'),
                      onPressed: _processing ? null : widget.onBack,
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'تصوير بطاقة الهوية الفلسطينية',
                        textAlign: TextAlign.center,
                        style: AppType.text(
                          18,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: AspectRatio(
                  aspectRatio: 1.58,
                  child: KeyedSubtree(
                    key: const ValueKey('identity-card-frame'),
                    child: Container(
                      key: _identityFrame,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                color: Colors.black.withValues(alpha: 0.72),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ضع الوجه الأمامي للهوية داخل الإطار، وتجنب اللمعان والظلال.',
                      textAlign: TextAlign.center,
                      style: AppType.text(13, color: Colors.white),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        key: const ValueKey('identity-scan-error'),
                        textAlign: TextAlign.center,
                        style: AppType.text(
                          13,
                          weight: FontWeight.w700,
                          color: const Color(0xFFFFB4AB),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    AppButton(
                      _processing ? 'جارٍ قراءة الهوية...' : 'التقاط الهوية',
                      key: const ValueKey('capture-identity'),
                      onPressed: !_ready || _processing ? null : _capture,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class IdentityDetailsScreen extends StatefulWidget {
  const IdentityDetailsScreen({
    super.key,
    required this.onContinue,
    this.initialData,
    this.onBack,
  });

  final ValueChanged<IdentityData> onContinue;
  final IdentityData? initialData;
  final VoidCallback? onBack;

  @override
  State<IdentityDetailsScreen> createState() => _IdentityDetailsScreenState();
}

class _IdentityDetailsScreenState extends State<IdentityDetailsScreen> {
  late final _fullName = TextEditingController(
    text: widget.initialData?.fullName ?? '',
  );
  late final _nationalId = TextEditingController(
    text: widget.initialData?.identityNumber ?? '',
  );
  late final _birthDate = TextEditingController(
    text: widget.initialData?.birthDate ?? '',
  );
  late final _address = TextEditingController(
    text: widget.initialData?.address ?? '',
  );
  String? _error;

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  void _submit() {
    final fullName = _fullName.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final nationalId = normalizeDigits(_nationalId.text).trim();
    final birthDate = normalizeDigits(_birthDate.text).trim();
    if (RegExp(r'[ء-ي]{2,}').allMatches(fullName).length < 2) {
      setState(() => _error = 'أدخل الاسم الكامل كما هو في الهوية.');
      return;
    }
    if (!RegExp(r'^[0-9]{9}$').hasMatch(nationalId)) {
      setState(() => _error = 'رقم الهوية يجب أن يتكوّن من 9 أرقام.');
      return;
    }
    if (!_validBirthDate(birthDate)) {
      setState(() => _error = 'أدخل تاريخ ميلاد صحيحًا بصيغة يوم/شهر/سنة.');
      return;
    }
    FocusScope.of(context).unfocus();
    widget.onContinue(
      IdentityData(
        fullName: fullName,
        identityNumber: nationalId,
        birthDate: birthDate,
        address: _address.text.trim(),
      ),
    );
  }

  bool _validBirthDate(String value) {
    final parts = value.split(RegExp(r'\s*/\s*'));
    if (parts.length != 3) return false;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return false;
    final date = DateTime(year, month, day);
    final today = DateTime.now();
    return date.year == year &&
        date.month == month &&
        date.day == day &&
        year >= today.year - 120 &&
        !date.isAfter(DateTime(today.year, today.month, today.day));
  }

  @override
  void dispose() {
    _fullName.dispose();
    _nationalId.dispose();
    _birthDate.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnboardingPage(
    onBack: widget.onBack,
    children: [
      const SizedBox(height: 32),
      const PageTitle('بيانات الحساب'),
      const SizedBox(height: 8),
      Text(
        'راجع البيانات المستخرجة من الهوية وصححها عند الحاجة.',
        style: AppType.body,
      ),
      const SizedBox(height: 26),
      _Field(
        key: const ValueKey('identity-full-name'),
        controller: _fullName,
        label: 'الاسم الكامل',
        textInputAction: TextInputAction.next,
        onChanged: _clearError,
      ),
      const SizedBox(height: 14),
      _Field(
        key: const ValueKey('identity-national-id'),
        controller: _nationalId,
        label: 'رقم الهوية',
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        maxLength: 9,
        textInputAction: TextInputAction.next,
        onChanged: _clearError,
      ),
      const SizedBox(height: 14),
      _Field(
        key: const ValueKey('identity-birth-date'),
        controller: _birthDate,
        label: 'تاريخ الميلاد',
        hint: '14 / 05 / 1998',
        keyboardType: TextInputType.datetime,
        textDirection: TextDirection.ltr,
        textInputAction: TextInputAction.next,
        onChanged: _clearError,
      ),
      const SizedBox(height: 14),
      _Field(
        key: const ValueKey('identity-address'),
        controller: _address,
        label: 'العنوان (اختياري)',
        textInputAction: TextInputAction.done,
        onChanged: _clearError,
        onSubmitted: _submit,
      ),
      InlineMessage(_error),
      const SizedBox(height: 30),
      AppButton('متابعة', onPressed: _submit),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.textDirection,
    this.maxLength,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final String? hint;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    textDirection: textDirection,
    textInputAction: textInputAction,
    maxLength: maxLength,
    inputFormatters: keyboardType == TextInputType.number
        ? [
            TextInputFormatter.withFunction(
              (oldValue, newValue) =>
                  newValue.copyWith(text: normalizeDigits(newValue.text)),
            ),
            FilteringTextInputFormatter.digitsOnly,
          ]
        : null,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
    ),
    onChanged: (_) => onChanged(),
    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
  );
}
