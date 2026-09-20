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

  Offset get normalizedGuideCenter => Offset(
    (guideRect.center.dx / previewSize.width).clamp(0.0, 1.0),
    (guideRect.center.dy / previewSize.height).clamp(0.0, 1.0),
  );
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
    double paddingFraction = 0.045,
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

    final mappedLeft = (visibleGuide.left - offsetX) / scale;
    final mappedTop = (visibleGuide.top - offsetY) / scale;
    final mappedRight = (visibleGuide.right - offsetX) / scale;
    final mappedBottom = (visibleGuide.bottom - offsetY) / scale;
    final horizontalPadding =
        (mappedRight - mappedLeft) * paddingFraction.clamp(0.0, 0.15);
    final verticalPadding =
        (mappedBottom - mappedTop) * paddingFraction.clamp(0.0, 0.15);
    final left = (mappedLeft - horizontalPadding).clamp(0.0, imageSize.width);
    final top = (mappedTop - verticalPadding).clamp(0.0, imageSize.height);
    final right = (mappedRight + horizontalPadding).clamp(0.0, imageSize.width);
    final bottom = (mappedBottom + verticalPadding).clamp(
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
    required this.enhancedBytes,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cropWidth,
    required this.cropHeight,
    required this.wasCropped,
  });

  final Uint8List bytes;
  final Uint8List enhancedBytes;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
  final int cropWidth;
  final int cropHeight;
  final bool wasCropped;
}

class IdentityCardRegionImages {
  const IdentityCardRegionImages({
    this.nationalId,
    this.arabicNames,
    this.birthDate,
  });

  final Uint8List? nationalId;
  final Uint8List? arabicNames;
  final Uint8List? birthDate;
}

/// Padded fractions of the already cropped card. These areas include the
/// printed Arabic labels, while excluding the portrait and unrelated dates.
class IdentityCardRegions {
  const IdentityCardRegions._();

  static Future<IdentityCardRegionImages> extract(
    Uint8List cardBytes, {
    required bool nationalId,
    required bool arabicNames,
    required bool birthDate,
  }) => Isolate.run(() {
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
      image.convolution(
        piece,
        filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
        amount: 0.28,
      );
      return Uint8List.fromList(image.encodeJpg(piece, quality: 94));
    }

    return IdentityCardRegionImages(
      nationalId: nationalId ? crop(.24, .17, .98, .41) : null,
      arabicNames: arabicNames ? crop(.40, .27, .99, .73) : null,
      birthDate: birthDate ? crop(.40, .57, .99, .81) : null,
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
    final sourceWidth = prepared.width;
    final sourceHeight = prepared.height;
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

    final cropWidth = prepared.width;
    final cropHeight = prepared.height;

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

    // Tesseract performs its own binarization. Keep a mild grayscale/contrast
    // full-card image, plus one stronger-contrast variant for targeted
    // recovery. Requested targeted crops are sharpened after cropping, which
    // avoids filtering millions of unused pixels. Neither path applies a
    // destructive hard threshold to Arabic glyphs.
    final conservative = image.Image.from(prepared);
    image.grayscale(conservative);
    image.contrast(conservative, contrast: 108);
    final enhanced = image.Image.from(conservative);
    image.contrast(enhanced, contrast: 114);
    final encoded = image.encodeJpg(conservative, quality: 94);
    final enhancedEncoded = image.encodeJpg(enhanced, quality: 94);
    return ProcessedIdentityImage(
      bytes: encoded,
      enhancedBytes: enhancedEncoded,
      width: conservative.width,
      height: conservative.height,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
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
