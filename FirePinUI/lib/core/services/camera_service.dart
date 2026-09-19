import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The UI can inject a fake camera without opening any platform channels.
abstract interface class CameraSource {
  Future<void> initialize();
  Widget buildPreview();
  Future<Uint8List> capture();
  Future<void> close();
}

typedef CameraSourceFactory = CameraSource Function();

class NativeCameraSource implements CameraSource {
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
      ResolutionPreset.high,
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
  Future<Uint8List> capture() async {
    final image = await _controller!.takePicture();
    try {
      return await image.readAsBytes();
    } finally {
      // The camera plugin creates a cache file. Keep only session memory.
      final file = File(image.path);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
