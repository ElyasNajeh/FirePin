import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import '../../theme/app_theme.dart';

/// Serializes lifecycle changes with capture and initialization so a pause,
/// permission dialog or route disposal cannot race a camera operation.
class LiveCamera extends StatefulWidget {
  const LiveCamera({
    super.key,
    required this.factory,
    this.active = true,
    this.onReady,
    this.onSettings,
  });
  final CameraSourceFactory factory;
  final bool active;
  final ValueChanged<bool>? onReady;
  final VoidCallback? onSettings;
  @override
  State<LiveCamera> createState() => LiveCameraState();
}

class LiveCameraState extends State<LiveCamera> with WidgetsBindingObserver {
  CameraSource? _source;
  Future<void> _queue = Future<void>.value();
  bool _foreground = true;
  bool _ready = false;
  bool _error = false;
  bool _takingPicture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _synchronize();
  }

  @override
  void didUpdateWidget(LiveCamera oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _synchronize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _synchronize();
  }

  void _synchronize() {
    _queue = _queue
        .then((_) async {
          if (!mounted || !widget.active || !_foreground) {
            final source = _source;
            _source = null;
            await source?.close();
            if (mounted) _update(ready: false);
            return;
          }
          if (_source != null && _ready) return;
          await _source?.close();
          _source = null;
          _update(ready: false);
          final source = widget.factory();
          _source = source;
          try {
            await source.initialize();
            if (!mounted || !widget.active || !_foreground) {
              await source.close();
              _source = null;
              return;
            }
            _update(ready: true);
          } catch (_) {
            await source.close();
            _source = null;
            if (mounted) _update(ready: false, error: true);
          }
        })
        .catchError((Object _) {
          if (mounted) _update(ready: false, error: true);
        });
  }

  void _update({required bool ready, bool error = false}) {
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _error = error;
    });
    // Avoid changing an ancestor while it is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call(_ready);
    });
  }

  Future<Uint8List?> capture({Offset? focusPoint}) async {
    if (!_ready || _takingPicture || _source == null) return null;
    _takingPicture = true;
    final result = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      try {
        if (!mounted || !_foreground || _source == null) {
          result.complete(null);
        } else {
          result.complete(await _source!.capture(focusPoint: focusPoint));
        }
      } catch (_) {
        if (mounted) _update(ready: false, error: true);
        result.complete(null);
      } finally {
        _takingPicture = false;
      }
    });
    return result.future;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _queue
          .then((_) async {
            final source = _source;
            _source = null;
            await source?.close();
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.textPrimary,
    child: _ready && _source != null
        ? RepaintBoundary(child: _source!.buildPreview())
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error ? 'تعذّر تشغيل الكاميرا' : 'جارٍ تجهيز الكاميرا',
                    textAlign: TextAlign.center,
                    style: AppType.text(16, color: Colors.white),
                  ),
                  if (_error) ...[
                    TextButton(
                      onPressed: _synchronize,
                      child: const Text(
                        'إعادة المحاولة',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    if (widget.onSettings != null)
                      TextButton(
                        onPressed: widget.onSettings,
                        child: const Text(
                          'إعدادات الكاميرا',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
  );
}
