import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_services.dart';
import '../../core/services/device_services.dart';
import '../../core/ui/components.dart';
import '../../core/ui/live_camera.dart';
import '../../theme/app_theme.dart';
import '../onboarding/onboarding_models.dart';

/// Figma 77:2. Still photos only: no microphone or photo-library access.
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
  final ValueChanged<Uint8List?> onSubmitted;
  final VoidCallback onClose;
  @override
  State<FireCameraScreen> createState() => _FireCameraScreenState();
}

class _FireCameraScreenState extends State<FireCameraScreen> {
  final _camera = GlobalKey<LiveCameraState>();
  bool _ready = false;
  bool _busy = false;
  bool _permissionGranted = false;
  bool _requestingCamera = true;
  bool _cameraSettings = false;
  Uint8List? _image;
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
    } catch (_) {
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

  Future<void> _submit({required bool withPhoto}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _locationProblem = null;
    });
    try {
      if (withPhoto && _image == null) {
        final photo = await _camera.currentState?.capture();
        if (!mounted) return;
        if (photo == null) {
          setState(
            () => _message =
                'تعذّر التصوير. حاول مجددًا أو أرسل البلاغ بدون صورة.',
          );
          return;
        }
        HapticFeedback.lightImpact();
        setState(() => _image = photo);
      }
      // Refresh GPS at report time; never claim a location was acquired if it wasn't.
      final fix = await widget.services.location.requestCurrentPosition();
      if (!mounted) return;
      widget.session.location = fix;
      await widget.services.reports.submit(
        photo: withPhoto ? _image : null,
        location: fix,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.onSubmitted(withPhoto ? _image : null);
    } on LocationFailure catch (error) {
      if (mounted) {
        setState(() {
          _locationProblem = error.problem;
          _message = locationExplanation(error.problem);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'تعذّر إكمال البلاغ. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'افتح إعدادات الجهاز لتغيير الإذن ثم حاول مجددًا.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
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
                      ExcludeSemantics(
                        excluding: _image != null,
                        child: LiveCamera(
                          key: _camera,
                          factory: widget.services.camera,
                          active: _image == null,
                          onReady: (value) {
                            if (mounted && value != _ready) {
                              setState(() => _ready = value);
                            }
                          },
                          onSettings: _settings,
                        ),
                      )
                    else
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _requestingCamera
                                  ? 'جارٍ طلب إذن الكاميرا'
                                  : 'الكاميرا غير متاحة',
                              style: AppType.text(16, color: Colors.white),
                            ),
                            if (!_requestingCamera)
                              TextButton(
                                onPressed: _cameraSettings
                                    ? _settings
                                    : _requestCamera,
                                child: Text(
                                  _cameraSettings
                                      ? 'فتح إعدادات التطبيق'
                                      : 'السماح بالكاميرا',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (_image != null)
                      Image.memory(_image!, fit: BoxFit.cover),
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
                          Semantics(
                            label: 'إغلاق الكاميرا',
                            button: true,
                            child: Material(
                              color: const Color(0x70091613),
                              shape: CircleBorder(
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _busy ? null : widget.onClose,
                                child: const SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: Center(
                                    child: FigmaIcon('close', size: 20),
                                  ),
                                ),
                              ),
                            ),
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
                        widget.session.location != null
                            ? '✓ تم تحديد موقعك'
                            : 'الموقع مطلوب للبلاغ',
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
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        button: true,
                        label: 'التقاط صورة',
                        enabled: !_busy && (_ready || _image != null),
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            key: const ValueKey('fire-shutter'),
                            customBorder: const CircleBorder(),
                            onTap: !_busy && (_ready || _image != null)
                                ? () => _submit(withPhoto: true)
                                : null,
                            child: Opacity(
                              opacity: !_busy && (_ready || _image != null)
                                  ? 1
                                  : 0.45,
                              child: const FigmaIcon('shutter', size: 92),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        _busy
                            ? 'جارٍ تجهيز البلاغ'
                            : _image == null
                            ? 'التقاط صورة'
                            : 'إعادة إرسال البلاغ',
                        style: AppType.text(
                          14,
                          weight: FontWeight.w500,
                          color: Colors.white,
                          height: 28,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _submit(withPhoto: false),
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
