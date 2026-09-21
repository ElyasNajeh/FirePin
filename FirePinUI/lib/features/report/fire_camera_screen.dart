import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_services.dart';
import '../../core/network/api_client.dart';
import '../../core/services/device_services.dart';
import '../../core/ui/components.dart';
import '../../core/ui/digit_input.dart';
import '../../core/ui/live_camera.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import '../auth/auth_models.dart';
import '../onboarding/onboarding_models.dart';
import 'fire_report_repository.dart';

/// Still-photo reporting using only a new camera capture. Gallery access is
/// intentionally not offered.
class FireCameraScreen extends StatefulWidget {
  const FireCameraScreen({
    super.key,
    required this.services,
    required this.session,
    required this.onSubmitted,
    required this.onClose,
  });

  final AppServices services;
  final OnboardingSession session;
  final FutureOr<void> Function(FireReport report) onSubmitted;
  final VoidCallback onClose;

  @override
  State<FireCameraScreen> createState() => _FireCameraScreenState();
}

class _FireCameraScreenState extends State<FireCameraScreen> {
  static const _maximumImages = 5;

  final _camera = GlobalKey<LiveCameraState>();
  final List<Uint8List> _images = [];
  bool _ready = false;
  bool _busy = false;
  bool _permissionGranted = false;
  bool _requestingCamera = true;
  bool _cameraSettings = false;
  String? _message;
  LocationProblem? _locationProblem;

  @override
  void initState() {
    super.initState();
    _requestCamera();
  }

  Future<void> _requestCamera() async {
    setState(() {
      _requestingCamera = true;
      _message = null;
    });
    try {
      final permission = await widget.services.permissions.requestCamera();
      if (!mounted) return;
      setState(() {
        _permissionGranted = permission == DevicePermission.granted;
        _cameraSettings = permission == DevicePermission.permanentlyDenied;
        if (!_permissionGranted) {
          _message = 'لم يتم السماح بالكاميرا. يمكنك إرسال البلاغ بدون صورة.';
        }
      });
    } on Object {
      if (mounted) {
        setState(
          () =>
              _message = 'تعذّر تشغيل الكاميرا. يمكنك إرسال البلاغ بدون صورة.',
        );
      }
    } finally {
      if (mounted) setState(() => _requestingCamera = false);
    }
  }

  Future<void> _capture() async {
    if (_busy || !_ready || _images.length >= _maximumImages) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final image = await _camera.currentState?.capture();
      if (!mounted) return;
      if (image == null) {
        setState(() => _message = 'تعذّر التقاط الصورة. حاول مرة أخرى.');
        return;
      }
      HapticFeedback.lightImpact();
      setState(() => _images.add(image));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit({required List<Uint8List> images, String? pin}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _locationProblem = null;
    });
    try {
      // Reacquire GPS at submission time; the map location is never replaced
      // with a fixed coordinate or a stale fallback.
      final fix = await widget.services.location.requestCurrentPosition();
      if (!mounted) return;
      widget.session.location = fix;
      final report = await widget.services.reportRepository.submit(
        images: images,
        pin: pin,
        location: fix,
      );
      if (!mounted) return;
      await widget.onSubmitted(report);
      if (mounted) HapticFeedback.mediumImpact();
    } on LocationFailure catch (error) {
      if (mounted) {
        setState(() {
          _locationProblem = error.problem;
          _message = locationExplanation(error.problem);
        });
      }
    } on DioException catch (error) {
      if (!mounted) return;
      final validationMessage = _reportValidationMessage(error);
      if (validationMessage != null) {
        setState(() => _message = validationMessage);
        return;
      }
      final detail = _apiDetail(error);
      setState(() {
        _message =
            error.response?.statusCode == 422 &&
                detail == 'PIN verification failed'
            ? 'رمز الدخول غير صحيح. لم يتم إرسال البلاغ.'
            : detail == 'A fire report can contain at most 5 images'
            ? 'يمكن إرفاق خمس صور كحد أقصى.'
            : 'تعذّر إكمال البلاغ. حاول مرة أخرى.';
      });
    } on AuthenticationException {
      if (mounted) {
        setState(() => _message = 'انتهت الجلسة. سجّل الدخول مجددًا.');
      }
    } on Object {
      if (mounted) {
        setState(() => _message = 'تعذّر إكمال البلاغ. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndSubmitWithoutPhoto() async {
    if (_busy) return;
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ReportPinDialog(),
    );
    if (pin != null && mounted) {
      await _submit(images: const [], pin: pin);
    }
  }

  Future<void> _settings() async {
    try {
      if (_locationProblem != null) {
        await widget.services.location.openSettings(
          locationService: _locationProblem == LocationProblem.serviceDisabled,
        );
      } else {
        await widget.services.permissions.openAppSettings();
      }
    } on Object {
      if (mounted) {
        showFeedback(
          context,
          'افتح إعدادات الجهاز لتغيير الإذن ثم حاول مجددًا.',
        );
      }
    }
  }

  void _removeImage(int index) {
    if (_busy) return;
    setState(() => _images.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final canCapture = !_busy && _ready && _images.length < _maximumImages;
    return PopScope(
      canPop: !_busy,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.textPrimary,
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_permissionGranted)
                      LiveCamera(
                        key: _camera,
                        factory: widget.services.camera,
                        active: _images.length < _maximumImages,
                        onReady: (value) {
                          if (mounted && value != _ready) {
                            setState(() => _ready = value);
                          }
                        },
                        onSettings: _settings,
                      )
                    else
                      _CameraUnavailable(
                        requesting: _requestingCamera,
                        openSettings: _cameraSettings,
                        onAction: _cameraSettings ? _settings : _requestCamera,
                      ),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 190,
                      child: IgnorePointer(
                        child: FigmaIcon(
                          'camera_top_gradient',
                          width: 390,
                          height: 190,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 132,
                      child: IgnorePointer(
                        child: FigmaIcon(
                          'camera_bottom_gradient',
                          width: 390,
                          height: 132,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                    Positioned(
                      top: padding.top > 36 ? padding.top + 8 : 48,
                      left: 20,
                      right: 20,
                      child: Row(
                        textDirection: TextDirection.ltr,
                        children: [
                          _CloseCameraButton(
                            onPressed: _busy ? null : widget.onClose,
                          ),
                          Expanded(
                            child: Text(
                              'إبلاغ عن حريق',
                              textAlign: TextAlign.center,
                              style: AppType.text(
                                20,
                                weight: FontWeight.w700,
                                color: Colors.white,
                                height: 40,
                              ),
                            ),
                          ),
                          const SizedBox(width: 42),
                        ],
                      ),
                    ),
                    Positioned(
                      top: padding.top > 36 ? padding.top + 65 : 105,
                      right: 20,
                      child: _CameraPill(
                        widget.session.location == null
                            ? 'الموقع مطلوب للبلاغ'
                            : '✓ تم تحديد موقعك على الخريطة',
                      ),
                    ),
                    if (_images.isNotEmpty)
                      Positioned(
                        top: padding.top > 36 ? padding.top + 108 : 148,
                        left: 16,
                        right: 16,
                        height: 68,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _images[index],
                                  key: ValueKey('captured-fire-image-$index'),
                                  width: 68,
                                  height: 68,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: InkWell(
                                  key: ValueKey('remove-fire-image-$index'),
                                  onTap: _busy
                                      ? null
                                      : () => _removeImage(index),
                                  child: const CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Color(0xB0000000),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 22,
                      left: 24,
                      right: 24,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_message != null) ...[
                            _CameraPill(_message!),
                            if (_locationProblem ==
                                    LocationProblem.permanentlyDenied ||
                                _locationProblem ==
                                    LocationProblem.serviceDisabled)
                              TextButton(
                                onPressed: _settings,
                                child: const Text(
                                  'فتح إعدادات الموقع',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          const _CameraPill(
                            'صوّر الحريق فقط إذا كان ذلك آمنًا',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        button: true,
                        label: 'التقاط صورة',
                        enabled: canCapture,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            key: const ValueKey('fire-shutter'),
                            customBorder: const CircleBorder(),
                            onTap: canCapture ? _capture : null,
                            child: Opacity(
                              opacity: canCapture ? 1 : 0.45,
                              child: const FigmaIcon('shutter', size: 76),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        _busy
                            ? 'جارٍ تجهيز البلاغ'
                            : 'الصور ${_images.length}/$_maximumImages',
                        key: const ValueKey('fire-image-count'),
                        style: AppType.text(
                          14,
                          weight: FontWeight.w500,
                          color: Colors.white,
                          height: 24,
                        ),
                      ),
                      if (_images.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        AppButton(
                          'إرسال البلاغ بالصور',
                          key: const ValueKey('submit-fire-images'),
                          busy: _busy,
                          onPressed: _busy
                              ? null
                              : () =>
                                    _submit(images: List.unmodifiable(_images)),
                        ),
                      ],
                      TextButton(
                        onPressed: _busy ? null : _confirmAndSubmitWithoutPhoto,
                        child: Text(
                          'إرسال البلاغ بدون صورة',
                          style:
                              AppType.text(
                                16,
                                weight: FontWeight.w500,
                                color: Colors.white,
                              ).copyWith(
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                              ),
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
    );
  }
}

class _ReportPinDialog extends StatefulWidget {
  const _ReportPinDialog();

  @override
  State<_ReportPinDialog> createState() => _ReportPinDialogState();
}

class _ReportPinDialogState extends State<_ReportPinDialog> {
  final _pin = TextEditingController();
  String? _error;
  int _shake = 0;

  void _confirm() {
    if (!isValidLoginPin(_pin.text)) {
      setState(() {
        _error = 'أدخل رمز دخول مكوّنًا من 4 أرقام.';
        _shake++;
      });
      return;
    }
    final pin = normalizeDigits(_pin.text).trim();
    _pin.clear();
    Navigator.of(context).pop(pin);
  }

  @override
  void dispose() {
    _pin.clear();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('تأكيد رمز الدخول', style: AppType.section),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'أدخل رمز حسابك المكوّن من 4 أرقام لإرسال البلاغ بدون صورة.',
          style: AppType.text(14, color: AppColors.textSecondary, height: 25),
        ),
        const SizedBox(height: 18),
        Shake(
          trigger: _shake,
          child: DigitInput(
            controller: _pin,
            label: 'رمز تأكيد البلاغ',
            length: 4,
            obscure: true,
          ),
        ),
        InlineMessage(_error),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const ValueKey('confirm-no-photo-report'),
        onPressed: _confirm,
        child: const Text('تأكيد الإرسال'),
      ),
    ],
  );
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({
    required this.requesting,
    required this.openSettings,
    required this.onAction,
  });

  final bool requesting;
  final bool openSettings;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          requesting ? 'جارٍ طلب إذن الكاميرا' : 'الكاميرا غير متاحة',
          style: AppType.text(16, color: Colors.white),
        ),
        if (!requesting)
          TextButton(
            onPressed: onAction,
            child: Text(
              openSettings ? 'فتح إعدادات التطبيق' : 'السماح بالكاميرا',
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
    ),
  );
}

class _CloseCameraButton extends StatelessWidget {
  const _CloseCameraButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'إغلاق الكاميرا',
    button: true,
    child: Material(
      color: const Color(0x70091613),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Center(child: FigmaIcon('close', size: 20)),
        ),
      ),
    ),
  );
}

class _CameraPill extends StatelessWidget {
  const _CameraPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xA0091613),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: AppType.text(
        13,
        weight: FontWeight.w500,
        color: Colors.white,
        height: 26,
      ),
    ),
  );
}

String? _apiDetail(DioException error) {
  final data = error.response?.data;
  return data is Map<String, dynamic> && data['detail'] is String
      ? data['detail'] as String
      : null;
}

String? _reportValidationMessage(DioException error) {
  final status = error.response?.statusCode;
  final data = error.response?.data;
  final detail = data is Map ? data['detail'] : null;
  if (status == 422) {
    if (detail == 'PIN verification failed') {
      return 'رمز الدخول غير صحيح. لم يتم إرسال البلاغ.';
    }
    if (detail == 'PIN is required when no images are provided') {
      return 'أدخل رمز الدخول لإرسال البلاغ بدون صور.';
    }
    if (detail == 'A fire report can contain at most 5 images') {
      return 'يمكن إرفاق خمس صور كحد أقصى.';
    }
    if (detail == 'Uploaded file is not a valid supported image') {
      return 'إحدى الصور غير صالحة أو غير مدعومة. أزلها والتقط صورة جديدة.';
    }
    if (detail is List) {
      final fields = detail
          .whereType<Map>()
          .expand((issue) => issue['loc'] is List ? issue['loc'] as List : const [])
          .map((part) => part.toString())
          .toSet();
      if (fields.contains('latitude') || fields.contains('longitude')) {
        return 'إحداثيات الموقع غير مقبولة. أعد تحديد موقعك وحاول مجددًا.';
      }
      if (fields.contains('images')) {
        return 'تعذّر قبول الصور. أزلها والتقط صورًا جديدة.';
      }
    }
    return 'بيانات البلاغ غير مقبولة (422). تحقّق من الموقع والصور وحاول مجددًا.';
  }
  if (status == 503 && detail == 'No active municipalities are available') {
    return 'لا توجد بلدية نشطة لاستقبال البلاغ حاليًا.';
  }
  if (status == 413) {
    return 'الصور كبيرة جدًا لإرسالها. التقط صورًا أقل وحاول مجددًا.';
  }
  if (error.response == null) {
    return 'تعذّر الاتصال بالخادم. تحقّق من الإنترنت ثم حاول مجددًا.';
  }
  return null;
}
