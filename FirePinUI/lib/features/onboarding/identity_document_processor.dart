import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

import 'identity_image_processor.dart';
import 'onboarding_models.dart';

abstract interface class IdentityDocumentProcessor {
  Future<IdentityData> extract(
    Uint8List imageBytes, {
    IdentityCaptureRegion? region,
  });
}

enum IdentityScanFailureType {
  imageInvalid,
  tessdataAssetFailure,
  ocrInitializationFailure,
  ocrExecutionFailure,
  parserFailure,
  ambiguousIdentityData,
}

class IdentityScanFailure implements Exception {
  const IdentityScanFailure(
    this.message, {
    this.type = IdentityScanFailureType.parserFailure,
    this.technicalCode,
  });

  final String message;
  final IdentityScanFailureType type;
  final String? technicalCode;

  @override
  String toString() => 'IdentityScanFailure($type, $technicalCode)';
}

abstract interface class IdentityOcrEngine {
  Future<String> recognize({
    required String imagePath,
    required String tessdataPath,
    required String language,
  });
}

/// Uses FirePin's checked Android channel. Other platforms retain the package
/// implementation so this Android reliability fix does not regress iOS.
class PlatformIdentityOcrEngine implements IdentityOcrEngine {
  const PlatformIdentityOcrEngine();

  static const _androidChannel = MethodChannel('firepin/identity_ocr');

  @override
  Future<String> recognize({
    required String imagePath,
    required String tessdataPath,
    required String language,
  }) async {
    if (Platform.isAndroid) {
      final result = await _androidChannel.invokeMethod<String>('recognize', {
        'imagePath': imagePath,
        'tessdataPath': tessdataPath,
        'language': language,
      });
      if (result == null) {
        throw PlatformException(
          code: 'OCR_EMPTY_RESULT',
          message: 'Native OCR returned no result',
        );
      }
      return result;
    }
    return TesseractOcr.extractText(
      imagePath,
      config: OCRConfig(language: language, engine: OCREngine.tesseract),
    );
  }
}

abstract interface class IdentityTessdataProvider {
  Future<String> prepare();
}

class TessdataAssetException implements Exception {
  const TessdataAssetException(this.code, [this.cause]);
  final String code;
  final Object? cause;
}

/// Copies known-good bundled language data atomically and repairs stale or
/// truncated files left by interrupted installs/older plugin versions.
class BundledIdentityTessdataProvider implements IdentityTessdataProvider {
  const BundledIdentityTessdataProvider();

  static const _assets = {
    'ara.traineddata':
        'e3206d3dc87fd50c24a0fb9f01838615911d25168f4e64415244b67d2bb3e729',
    'eng.traineddata':
        '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
  };

  @override
  Future<String> prepare() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory(
        '${support.path}${Platform.pathSeparator}firepin_identity_ocr',
      );
      final tessdata = Directory(
        '${root.path}${Platform.pathSeparator}tessdata',
      );
      await tessdata.create(recursive: true);
      for (final entry in _assets.entries) {
        await _installVerifiedAsset(tessdata, entry.key, entry.value);
      }
      _identityOcrLog('tessdata', 'status=ready languages=ara+eng');
      return root.path;
    } on TessdataAssetException {
      rethrow;
    } on Object catch (error) {
      throw TessdataAssetException('setup_failed', error);
    }
  }

  Future<void> _installVerifiedAsset(
    Directory directory,
    String fileName,
    String expectedHash,
  ) async {
    final assetData = await rootBundle.load('assets/tessdata/$fileName');
    final assetBytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );
    if (sha256.convert(assetBytes).toString() != expectedHash) {
      throw TessdataAssetException('bundled_hash_mismatch_$fileName');
    }

    final destination = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    if (await destination.exists()) {
      final installedBytes = await destination.readAsBytes();
      if (installedBytes.length == assetBytes.length &&
          sha256.convert(installedBytes).toString() == expectedHash) {
        _identityOcrLog(
          'tessdata',
          'file=$fileName status=verified bytes=${installedBytes.length}',
        );
        return;
      }
    }

    final temporary = File('${destination.path}.installing');
    try {
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsBytes(assetBytes, flush: true);
      final writtenBytes = await temporary.readAsBytes();
      if (sha256.convert(writtenBytes).toString() != expectedHash) {
        throw TessdataAssetException('written_hash_mismatch_$fileName');
      }
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      _identityOcrLog(
        'tessdata',
        'file=$fileName status=installed bytes=${assetBytes.length}',
      );
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Object catch (error) {
        _identityOcrLog(
          'tessdata_cleanup',
          'status=failed type=${error.runtimeType}',
        );
      }
    }
  }
}

class TesseractIdentityDocumentProcessor implements IdentityDocumentProcessor {
  const TesseractIdentityDocumentProcessor({
    this.preprocessor = const ConservativeIdentityImagePreprocessor(),
    this.ocrEngine = const PlatformIdentityOcrEngine(),
    this.tessdataProvider = const BundledIdentityTessdataProvider(),
  });

  final IdentityImagePreprocessor preprocessor;
  final IdentityOcrEngine ocrEngine;
  final IdentityTessdataProvider tessdataProvider;

  @override
  Future<IdentityData> extract(
    Uint8List imageBytes, {
    IdentityCaptureRegion? region,
  }) async {
    _identityOcrLog(
      'capture',
      'bytes=${imageBytes.length} guide=${region == null ? 'missing' : 'present'}',
    );
    late final ProcessedIdentityImage processed;
    try {
      processed = await preprocessor.process(imageBytes, region: region);
    } on IdentityImageProcessingException catch (error) {
      _identityOcrLog('preprocess', 'status=failed reason=${error.reason}');
      throw const IdentityScanFailure(
        'الصورة غير صالحة أو دقتها منخفضة. أعد تصوير بطاقة الهوية بوضوح.',
        type: IdentityScanFailureType.imageInvalid,
        technicalCode: 'preprocess_failed',
      );
    } on Object catch (error) {
      _identityOcrLog('preprocess', 'status=failed type=${error.runtimeType}');
      throw const IdentityScanFailure(
        'الصورة غير صالحة أو غير قابلة للقراءة. أعد تصوير بطاقة الهوية.',
        type: IdentityScanFailureType.imageInvalid,
        technicalCode: 'image_invalid',
      );
    }
    _identityOcrLog(
      'preprocess',
      'status=ready dimensions=${processed.width}x${processed.height} '
          'bytes=${processed.bytes.length} cropped=${processed.wasCropped}',
    );

    late final String tessdataPath;
    try {
      tessdataPath = await tessdataProvider.prepare();
    } on TessdataAssetException catch (error) {
      _identityOcrLog(
        'tessdata',
        'status=failed code=${error.code} type=${error.cause.runtimeType}',
      );
      throw IdentityScanFailure(
        'تعذّر تجهيز قارئ الهوية. أغلق التطبيق وافتحه ثم حاول مجددًا.',
        type: IdentityScanFailureType.tessdataAssetFailure,
        technicalCode: error.code,
      );
    } on Object catch (error) {
      _identityOcrLog('tessdata', 'status=failed type=${error.runtimeType}');
      throw const IdentityScanFailure(
        'تعذّر تجهيز قارئ الهوية. أغلق التطبيق وافتحه ثم حاول مجددًا.',
        type: IdentityScanFailureType.tessdataAssetFailure,
        technicalCode: 'tessdata_unknown',
      );
    }

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'firepin-id-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    try {
      await file.writeAsBytes(processed.bytes, flush: true);
      _identityOcrLog('recognize', 'status=starting language=ara+eng');
      final text = await ocrEngine
          .recognize(
            imagePath: file.path,
            tessdataPath: tessdataPath,
            language: 'ara+eng',
          )
          .timeout(const Duration(seconds: 60));
      _identityOcrLog('recognize', 'status=complete characters=${text.length}');
      try {
        final identity = IdentityTextParser.parse(text);
        _identityOcrLog('parse', 'status=complete');
        return identity;
      } on IdentityScanFailure catch (error) {
        _identityOcrLog(
          'parse',
          'status=failed type=${error.type} code=${error.technicalCode}',
        );
        rethrow;
      }
    } on IdentityScanFailure {
      rethrow;
    } on TimeoutException {
      _identityOcrLog('recognize', 'status=failed code=timeout');
      throw const IdentityScanFailure(
        'استغرقت قراءة الهوية وقتًا طويلًا. أعد التصوير وحاول مجددًا.',
        type: IdentityScanFailureType.ocrExecutionFailure,
        technicalCode: 'timeout',
      );
    } on PlatformException catch (error) {
      _identityOcrLog(
        'recognize',
        'status=failed code=${error.code} message=${error.message}',
      );
      throw classifyOcrError(error);
    } on MissingPluginException catch (error) {
      _identityOcrLog(
        'recognize',
        'status=failed code=missing_plugin message=$error',
      );
      throw const IdentityScanFailure(
        'تعذّر تشغيل قارئ الهوية على هذا الجهاز. أعد فتح التطبيق وحاول مجددًا.',
        type: IdentityScanFailureType.ocrInitializationFailure,
        technicalCode: 'missing_plugin',
      );
    } on Object catch (error) {
      _identityOcrLog('recognize', 'status=failed type=${error.runtimeType}');
      throw IdentityScanFailure(
        'تعذّرت قراءة صورة الهوية. تأكد من الإضاءة والوضوح ثم أعد التصوير.',
        type: IdentityScanFailureType.ocrExecutionFailure,
        technicalCode: error.runtimeType.toString(),
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on Object catch (error) {
        _identityOcrLog(
          'image_cleanup',
          'status=failed type=${error.runtimeType}',
        );
      }
    }
  }

  @visibleForTesting
  static IdentityScanFailure classifyOcrError(PlatformException error) {
    final code = error.code.toUpperCase();
    if (code.contains('TESSDATA') || code.contains('ASSET')) {
      return IdentityScanFailure(
        'تعذّر تجهيز قارئ الهوية. أغلق التطبيق وافتحه ثم حاول مجددًا.',
        type: IdentityScanFailureType.tessdataAssetFailure,
        technicalCode: error.code,
      );
    }
    if (code.contains('INIT') || code == 'INVALID_ARGUMENT') {
      return IdentityScanFailure(
        'تعذّر تشغيل قارئ الهوية على هذا الجهاز. أعد فتح التطبيق وحاول مجددًا.',
        type: IdentityScanFailureType.ocrInitializationFailure,
        technicalCode: error.code,
      );
    }
    return IdentityScanFailure(
      'تعذّرت قراءة صورة الهوية. تأكد من الإضاءة والوضوح ثم أعد التصوير.',
      type: IdentityScanFailureType.ocrExecutionFailure,
      technicalCode: error.code,
    );
  }
}

void _identityOcrLog(String stage, String details) {
  debugPrint('[FirePinIdentityOCR] stage=$stage $details');
}

class IdentityTextParser {
  const IdentityTextParser._();

  static IdentityData parse(String rawText) {
    final normalized = normalizeDigits(
      rawText,
    ).replaceAll('\r', '\n').replaceAll(RegExp(r'\n+'), '\n').trim();
    if (normalized.length < 12) {
      throw const IdentityScanFailure(
        'لم تظهر بيانات كافية في الصورة. أعد تصوير الوجه الأمامي للهوية.',
        type: IdentityScanFailureType.parserFailure,
        technicalCode: 'insufficient_text',
      );
    }
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final nationalId = _nationalId(lines);
    final birthDate = _birthDate(lines);
    final fullName = _arabicName(lines);
    return IdentityData(
      fullName: fullName,
      identityNumber: nationalId,
      birthDate: birthDate,
      address: '',
    );
  }

  static String _nationalId(List<String> lines) {
    final all = _idCandidates(lines.join('\n'));
    if (all.length == 1) return all.single;
    if (all.length > 1) {
      throw const IdentityScanFailure(
        'ظهرت عدة أرقام محتملة للهوية. أعد التصوير بحيث تظهر بطاقة واحدة فقط.',
        type: IdentityScanFailureType.ambiguousIdentityData,
        technicalCode: 'multiple_national_ids',
      );
    }
    throw const IdentityScanFailure(
      'لم نتمكن من تحديد رقم هوية واحد من 9 أرقام. أعد التصوير بوضوح.',
      type: IdentityScanFailureType.parserFailure,
      technicalCode: 'national_id_missing',
    );
  }

  static Set<String> _idCandidates(String text) {
    final matches = RegExp(
      r'(?<![0-9])(?:[0-9][\s-]*){9}(?![0-9])',
    ).allMatches(text);
    return {
      for (final match in matches)
        match.group(0)!.replaceAll(RegExp(r'[^0-9]'), ''),
    };
  }

  static String _birthDate(List<String> lines) {
    final labeledText = _labeledText(
      lines,
      (line) => RegExp(
        r'(تاريخ\s*(الميلاد|الولادة)|ميلاد|birth|dob)',
        caseSensitive: false,
      ).hasMatch(line),
    );
    final labeled = _validDates(labeledText);
    final dates = labeled.isNotEmpty ? labeled : _validDates(lines.join('\n'));
    if (dates.isEmpty) {
      throw const IdentityScanFailure(
        'لم نتمكن من قراءة تاريخ ميلاد صحيح. أعد تصوير الهوية بوضوح.',
        type: IdentityScanFailureType.parserFailure,
        technicalCode: 'birth_date_missing_or_invalid',
      );
    }
    if (dates.length > 1) {
      throw const IdentityScanFailure(
        'ظهرت عدة تواريخ ميلاد محتملة. أعد تصوير الهوية بوضوح.',
        type: IdentityScanFailureType.ambiguousIdentityData,
        technicalCode: 'multiple_birth_dates',
      );
    }
    dates.sort();
    final date = dates.first;
    return '${date.day.toString().padLeft(2, '0')} / '
        '${date.month.toString().padLeft(2, '0')} / ${date.year}';
  }

  static List<DateTime> _validDates(String text) {
    final result = <DateTime>{};
    final pattern = RegExp(
      r'(?<![0-9])([0-9]{1,4})\s*[/.-]\s*([0-9]{1,2})\s*[/.-]\s*([0-9]{1,4})(?![0-9])',
    );
    for (final match in pattern.allMatches(text)) {
      final first = match.group(1)!;
      final middle = match.group(2)!;
      final last = match.group(3)!;
      final yearFirst = first.length == 4;
      final year = int.parse(yearFirst ? first : last);
      final month = int.parse(middle);
      final day = int.parse(yearFirst ? last : first);
      final date = DateTime(year, month, day);
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      if (year >= today.year - 120 &&
          year <= today.year &&
          date.year == year &&
          date.month == month &&
          date.day == day &&
          !date.isAfter(todayDate)) {
        result.add(date);
      }
    }
    return result.toList();
  }

  static String _arabicName(List<String> lines) {
    final label = RegExp(r'(الاسم\s*(الكامل|الرباعي)?|اسم\s*العائلة)');
    final labeled = <String>[];
    for (var index = 0; index < lines.length; index++) {
      if (!label.hasMatch(lines[index])) continue;
      labeled.add(lines[index].replaceAll(label, ' '));
      if (index + 1 < lines.length) labeled.add(lines[index + 1]);
    }
    final fromLabel = _bestName(labeled, minimumWords: 2);
    if (fromLabel != null) return fromLabel;
    // When OCR loses the label entirely, accept only a stronger three-word
    // Arabic candidate. This keeps the fallback useful without treating an
    // address or government header as a person's name.
    final fromDocument = _bestName(lines, minimumWords: 3);
    if (fromDocument != null) return fromDocument;
    throw const IdentityScanFailure(
      'لم نتمكن من قراءة الاسم العربي الكامل. أعد تصوير الهوية بوضوح.',
      type: IdentityScanFailureType.parserFailure,
      technicalCode: 'arabic_name_missing',
    );
  }

  static String? _bestName(
    Iterable<String> lines, {
    required int minimumWords,
  }) {
    const excluded = {
      'السلطة',
      'الوطنية',
      'الفلسطينية',
      'دولة',
      'فلسطين',
      'وزارة',
      'الداخلية',
      'بطاقة',
      'هوية',
      'الهوية',
      'تاريخ',
      'الميلاد',
      'الجنس',
      'ذكر',
      'أنثى',
      'مكان',
      'الإقامة',
      'انتهاء',
      'الاسم',
      'الكامل',
      'الرباعي',
      'العائلة',
      'السكن',
      'العنوان',
    };
    String? best;
    var bestWords = 0;
    for (final line in lines) {
      final words = RegExp(
        r'[ء-ي]{2,}',
      ).allMatches(line).map((match) => match.group(0)!);
      final candidateWords = words
          .where((word) => !excluded.contains(word))
          .toList();
      if (candidateWords.length >= minimumWords &&
          candidateWords.length > bestWords) {
        best = candidateWords.join(' ');
        bestWords = candidateWords.length;
      }
    }
    return best;
  }

  static String _labeledText(
    List<String> lines,
    bool Function(String line) isLabel,
  ) {
    final selected = <String>[];
    for (var index = 0; index < lines.length; index++) {
      if (!isLabel(lines[index])) continue;
      selected.add(lines[index]);
      if (index + 1 < lines.length) selected.add(lines[index + 1]);
    }
    return selected.join('\n');
  }
}
