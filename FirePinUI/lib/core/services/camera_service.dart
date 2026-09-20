import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The UI can inject a fake camera without opening any platform channels.
abstract interface class CameraSource {
  Future<void> initialize();
  Widget buildPreview();
  Future<Uint8List> capture({Offset? focusPoint});
  Future<void> close();
}

typedef CameraSourceFactory = CameraSource Function();

class NativeCameraSource implements CameraSource {
  @visibleForTesting
  static const captureResolutionPreset = ResolutionPreset.max;

  CameraController? _controller;
  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('noCamera', 'No camera available');
    }
    final rear = cameras.where(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    final controller = CameraController(
      rear.isNotEmpty ? rear.first : cameras.first,
      captureResolutionPreset,
      enableAudio: false,
    );
    _controller = controller;
    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
  }

  @override
  Widget buildPreview() {
    final controller = _controller!;
    return LayoutBuilder(
      builder: (_, constraints) {
        // The sensor is landscape; the locked mobile preview is portrait.
        final size = controller.value.previewSize!;
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.height,
              height: size.width,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  @override
  Future<Uint8List> capture({Offset? focusPoint}) async {
    final controller = _controller!;
    final point = focusPoint ?? const Offset(0.5, 0.5);
    await _prepareAutoCapture(controller, point);
    final image = await controller.takePicture();
    try {
      final bytes = await image.readAsBytes();
      debugPrint('[FirePinCamera] stage=capture bytes=${bytes.length}');
      return bytes;
    } finally {
      // The camera plugin creates a cache file. Keep only session memory.
      final file = File(image.path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _prepareAutoCapture(
    CameraController controller,
    Offset point,
  ) async {
    final safePoint = Offset(
      point.dx.clamp(0.0, 1.0),
      point.dy.clamp(0.0, 1.0),
    );
    var adjusted = false;
    for (final operation in <Future<void> Function()>[
      () => controller.setFocusMode(FocusMode.auto),
      () => controller.setExposureMode(ExposureMode.auto),
      () => controller.setFocusPoint(safePoint),
      () => controller.setExposurePoint(safePoint),
    ]) {
      try {
        await operation();
        adjusted = true;
      } on CameraException catch (error) {
        debugPrint(
          '[FirePinCamera] stage=metering status=unsupported code=${error.code}',
        );
      }
    }
    if (adjusted) await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
