import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as image;

/// The guide rectangle as drawn over the camera preview.
///
/// [guideRect] is expressed in logical pixels relative to [previewSize]. The
/// captured image is center-cropped in the preview with [BoxFit.cover], so the
/// same transform is reversed before OCR.
class IdentityCaptureRegion {
  const IdentityCaptureRegion({
    required this.previewSize,
    required this.guideRect,
  });

  final Size previewSize;
  final Rect guideRect;
}

class IdentityPixelCrop {
  const IdentityPixelCrop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

class IdentityCropGeometry {
  const IdentityCropGeometry._();

  /// Maps a visible guide through the centered [BoxFit.cover] preview back to
  /// oriented capture pixels. This intentionally derives the crop from the
  /// real UI frame rather than using device-specific percentages.
  static IdentityPixelCrop fromCoverPreview({
    required Size imageSize,
    required Size previewSize,
    required Rect guideRect,
  }) {
    if (!_validSize(imageSize) || !_validSize(previewSize)) {
      throw const FormatException('Invalid image or preview size');
    }
    final previewBounds = Offset.zero & previewSize;
    final visibleGuide = guideRect.intersect(previewBounds);
    if (visibleGuide.isEmpty) {
      throw const FormatException('Identity guide is outside the preview');
    }

    final scale =
        (previewSize.width / imageSize.width) >
            (previewSize.height / imageSize.height)
        ? previewSize.width / imageSize.width
        : previewSize.height / imageSize.height;
    final displayedWidth = imageSize.width * scale;
    final displayedHeight = imageSize.height * scale;
    final offsetX = (previewSize.width - displayedWidth) / 2;
    final offsetY = (previewSize.height - displayedHeight) / 2;

    final left = ((visibleGuide.left - offsetX) / scale).clamp(
      0.0,
      imageSize.width,
    );
    final top = ((visibleGuide.top - offsetY) / scale).clamp(
      0.0,
      imageSize.height,
    );
    final right = ((visibleGuide.right - offsetX) / scale).clamp(
      0.0,
      imageSize.width,
    );
    final bottom = ((visibleGuide.bottom - offsetY) / scale).clamp(
      0.0,
      imageSize.height,
    );

    final x = left.floor();
    final y = top.floor();
    final cropRight = right.ceil().clamp(x + 1, imageSize.width.toInt());
    final cropBottom = bottom.ceil().clamp(y + 1, imageSize.height.toInt());
    return IdentityPixelCrop(
      x: x,
      y: y,
      width: cropRight - x,
      height: cropBottom - y,
    );
  }

  static bool _validSize(Size size) =>
      size.width.isFinite &&
      size.height.isFinite &&
      size.width > 0 &&
      size.height > 0;
}

class ProcessedIdentityImage {
  const ProcessedIdentityImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.wasCropped,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final bool wasCropped;
}

class IdentityCardRegionImages {
  const IdentityCardRegionImages({
    required this.nationalId,
    required this.arabicNames,
    required this.birthDate,
  });

  final Uint8List nationalId;
  final Uint8List arabicNames;
  final Uint8List birthDate;
}

/// Padded fractions of the already cropped card. These areas include the
/// printed Arabic labels, while excluding the portrait and unrelated dates.
class IdentityCardRegions {
  const IdentityCardRegions._();

  static Future<IdentityCardRegionImages> extract(Uint8List cardBytes) =>
      Isolate.run(() {
        final card = image.decodeImage(cardBytes);
        if (card == null) {
          throw const IdentityImageProcessingException('region decode failed');
        }
        Uint8List crop(double left, double top, double right, double bottom) {
          final x = (left * card.width).floor();
          final y = (top * card.height).floor();
          var piece = image.copyCrop(
            card,
            x: x,
            y: y,
            width: (right * card.width).ceil() - x,
            height: (bottom * card.height).ceil() - y,
          );
          if (piece.width < 1400) {
            piece = image.copyResize(
              piece,
              width: 1400,
              interpolation: image.Interpolation.cubic,
            );
          }
          return Uint8List.fromList(image.encodeJpg(piece, quality: 94));
        }

        return IdentityCardRegionImages(
          nationalId: crop(.34, .24, .95, .36),
          arabicNames: crop(.67, .35, .97, .67),
          birthDate: crop(.58, .63, .97, .73),
        );
      });
}

class IdentityImageProcessingException implements Exception {
  const IdentityImageProcessingException(this.reason);
  final String reason;
}

abstract interface class IdentityImagePreprocessor {
  Future<ProcessedIdentityImage> process(
    Uint8List bytes, {
    IdentityCaptureRegion? region,
  });
}

class ConservativeIdentityImagePreprocessor
    implements IdentityImagePreprocessor {
  const ConservativeIdentityImagePreprocessor();

  static const _maximumWidth = 2400;
  static const _minimumUncroppedWidth = 640;
  static const _minimumUncroppedHeight = 360;
  static const _minimumCroppedWidth = 400;
  static const _minimumCroppedHeight = 250;
  static const _preferredCroppedWidth = 1280;

  @override
  Future<ProcessedIdentityImage> process(
    Uint8List bytes, {
    IdentityCaptureRegion? region,
  }) {
    final request = _PreprocessRequest.from(bytes, region);
    return Isolate.run(() => _process(request));
  }

  static ProcessedIdentityImage _process(_PreprocessRequest request) {
    if (request.bytes.isEmpty) {
      throw const IdentityImageProcessingException('empty image');
    }
    final decoded = image.decodeImage(request.bytes);
    if (decoded == null) {
      throw const IdentityImageProcessingException('image decode failed');
    }

    // Camera JPEGs commonly store rotation in EXIF. Baking it makes native
    // Tesseract see exactly the same upright image the user saw in preview.
    var prepared = image.bakeOrientation(decoded);
    var wasCropped = false;
    if (request.hasRegion) {
      final crop = IdentityCropGeometry.fromCoverPreview(
        imageSize: Size(prepared.width.toDouble(), prepared.height.toDouble()),
        previewSize: Size(request.previewWidth!, request.previewHeight!),
        guideRect: Rect.fromLTWH(
          request.guideLeft!,
          request.guideTop!,
          request.guideWidth!,
          request.guideHeight!,
        ),
      );
      prepared = image.copyCrop(
        prepared,
        x: crop.x,
        y: crop.y,
        width: crop.width,
        height: crop.height,
      );
      wasCropped = true;
    }

    final minimumWidth = wasCropped
        ? _minimumCroppedWidth
        : _minimumUncroppedWidth;
    final minimumHeight = wasCropped
        ? _minimumCroppedHeight
        : _minimumUncroppedHeight;
    if (prepared.width < minimumWidth || prepared.height < minimumHeight) {
      throw IdentityImageProcessingException(
        'image resolution ${prepared.width}x${prepared.height} is too low',
      );
    }

    if (wasCropped && prepared.width < _preferredCroppedWidth) {
      // A usable guide crop can be smaller than the full camera capture.
      // Enlarge it before OCR while retaining its card aspect ratio.
      prepared = image.copyResize(
        prepared,
        width: _preferredCroppedWidth,
        interpolation: image.Interpolation.cubic,
      );
    } else if (prepared.width > _maximumWidth) {
      prepared = image.copyResize(
        prepared,
        width: _maximumWidth,
        interpolation: image.Interpolation.linear,
      );
    }

    // Tesseract performs its own binarization. A mild grayscale/contrast pass
    // reduces color noise without hard-thresholding faint Arabic glyphs.
    image.grayscale(prepared);
    image.contrast(prepared, contrast: 108);
    final encoded = image.encodeJpg(prepared, quality: 92);
    return ProcessedIdentityImage(
      bytes: encoded,
      width: prepared.width,
      height: prepared.height,
      wasCropped: wasCropped,
    );
  }
}

class _PreprocessRequest {
  const _PreprocessRequest({
    required this.bytes,
    this.previewWidth,
    this.previewHeight,
    this.guideLeft,
    this.guideTop,
    this.guideWidth,
    this.guideHeight,
  });

  factory _PreprocessRequest.from(
    Uint8List bytes,
    IdentityCaptureRegion? region,
  ) => _PreprocessRequest(
    bytes: bytes,
    previewWidth: region?.previewSize.width,
    previewHeight: region?.previewSize.height,
    guideLeft: region?.guideRect.left,
    guideTop: region?.guideRect.top,
    guideWidth: region?.guideRect.width,
    guideHeight: region?.guideRect.height,
  );

  final Uint8List bytes;
  final double? previewWidth;
  final double? previewHeight;
  final double? guideLeft;
  final double? guideTop;
  final double? guideWidth;
  final double? guideHeight;

  bool get hasRegion => previewWidth != null;
}
