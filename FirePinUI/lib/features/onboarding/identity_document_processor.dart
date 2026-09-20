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
    IdentityOcrMode mode = IdentityOcrMode.fullCard,
  });
}

enum IdentityOcrMode { fullCard, arabicNames, nationalId, birthDate }

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
    IdentityOcrMode mode = IdentityOcrMode.fullCard,
  }) async {
    if (Platform.isAndroid) {
      final result = await _androidChannel.invokeMethod<String>('recognize', {
        'imagePath': imagePath,
        'tessdataPath': tessdataPath,
        'language': language,
        'mode': mode.name,
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
      'status=ready source=${processed.sourceWidth}x${processed.sourceHeight} '
          'crop=${processed.cropWidth}x${processed.cropHeight} '
          'output=${processed.width}x${processed.height} '
          'cropped=${processed.wasCropped}',
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

    final files = <File>[];
    try {
      Future<String> recognize(
        List<int> bytes,
        String language,
        IdentityOcrMode mode,
      ) async {
        final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'firepin-id-${DateTime.now().microsecondsSinceEpoch}-${mode.name}.jpg',
        );
        files.add(file);
        await file.writeAsBytes(bytes, flush: true);
        _identityOcrLog(
          'recognize',
          'status=starting pass=${mode.name} language=$language',
        );
        final text = await ocrEngine
            .recognize(
              imagePath: file.path,
              tessdataPath: tessdataPath,
              language: language,
              mode: mode,
            )
            .timeout(const Duration(seconds: 60));
        _identityOcrLog(
          'recognize',
          'status=complete pass=${mode.name} characters=${text.length}',
        );
        return text;
      }

      Future<String?> recognizeRegion(
        List<int> bytes,
        String language,
        IdentityOcrMode mode,
      ) async {
        try {
          return await recognize(bytes, language, mode);
        } on PlatformException catch (error) {
          final failure = classifyOcrError(error);
          if (failure.type ==
                  IdentityScanFailureType.ocrInitializationFailure ||
              failure.type == IdentityScanFailureType.tessdataAssetFailure) {
            throw failure;
          }
          _identityOcrLog(
            'recognize',
            'status=skipped pass=${mode.name} code=${error.code}',
          );
          return null;
        } on TimeoutException {
          _identityOcrLog(
            'recognize',
            'status=skipped pass=${mode.name} code=timeout',
          );
          return null;
        } on MissingPluginException {
          rethrow;
        } on Object catch (error) {
          _identityOcrLog(
            'recognize',
            'status=skipped pass=${mode.name} type=${error.runtimeType}',
          );
          return null;
        }
      }

      void logParse(IdentityData identity, String pass) {
        final complete =
            identity.identityNumber.isNotEmpty &&
            identity.fullName.isNotEmpty &&
            identity.birthDate.isNotEmpty;
        _identityOcrLog(
          'parse',
          'status=${complete ? 'complete' : 'partial'} pass=$pass '
              'id=${identity.identityNumber.isNotEmpty} '
              'name=${identity.fullName.isNotEmpty} '
              'birthDate=${identity.birthDate.isNotEmpty}',
        );
      }

      final text = await recognize(
        processed.bytes,
        'ara+eng',
        IdentityOcrMode.fullCard,
      );
      final fullCard = IdentityTextParser.parse(text);
      logParse(fullCard, 'fullCard');
      if (fullCard.identityNumber.isNotEmpty &&
          fullCard.fullName.isNotEmpty &&
          fullCard.birthDate.isNotEmpty) {
        return fullCard;
      }

      final regions = await IdentityCardRegions.extract(
        processed.enhancedBytes,
        nationalId: fullCard.identityNumber.isEmpty,
        arabicNames: fullCard.fullName.isEmpty,
        birthDate: fullCard.birthDate.isEmpty,
      );
      var identityNumber = fullCard.identityNumber;
      var fullName = fullCard.fullName;
      var birthDate = fullCard.birthDate;

      // A structurally valid full-card field is authoritative. Targeted OCR
      // only recovers missing/ambiguous fields, so a weaker conflicting pass
      // can never overwrite an already-good value.
      if (identityNumber.isEmpty) {
        final idText = await recognizeRegion(
          regions.nationalId!,
          'eng',
          IdentityOcrMode.nationalId,
        );
        identityNumber = IdentityTextParser.parse(
          '',
          nationalIdText: idText,
        ).identityNumber;
      }
      if (fullName.isEmpty) {
        final nameText = await recognizeRegion(
          regions.arabicNames!,
          'ara',
          IdentityOcrMode.arabicNames,
        );
        fullName = IdentityTextParser.parse('', nameText: nameText).fullName;
      }
      if (birthDate.isEmpty) {
        final dateText = await recognizeRegion(
          regions.birthDate!,
          'eng',
          IdentityOcrMode.birthDate,
        );
        birthDate = IdentityTextParser.parse(
          '',
          birthDateText: dateText,
        ).birthDate;
      }
      final identity = IdentityData(
        fullName: fullName,
        identityNumber: identityNumber,
        birthDate: birthDate,
        address: '',
      );
      logParse(identity, 'regions');
      return identity;
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
      _identityOcrLog('recognize', 'status=failed code=${error.code}');
      throw classifyOcrError(error);
    } on MissingPluginException catch (error) {
      _identityOcrLog(
        'recognize',
        'status=failed code=missing_plugin type=${error.runtimeType}',
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
      for (final file in files) {
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

  static final _idLabel = RegExp(
    r'رقم\s*(?:ال)?هوية|national\s*id',
    caseSensitive: false,
  );
  static final _birthLabel = RegExp(
    r'تاريخ\s*(?:الميلاد|الولادة)|ميلاد|birth|dob',
    caseSensitive: false,
  );
  static final _fullNameLabel = RegExp(r'(?:الاسم|اسم)\s*(?:الكامل|الرباعي)');
  static final _nameLabels = <RegExp>[
    RegExp(r'(?:الاسم|اسم)\s*(?:الشخصي|الأول|الاول)'),
    RegExp(r'اسم\s*(?:الأب|الاب)'),
    RegExp(r'اسم\s*الجد'),
    RegExp(r'اسم\s*العائلة'),
  ];
  static final _arabicWord = RegExp(r'[ء-ي]{2,}');
  static final _datePattern = RegExp(
    r'(?<![0-9])([0-9]{1,4})\s*[/.-]\s*([0-9]{1,2})\s*[/.-]\s*([0-9]{1,4})(?![0-9])',
  );

  static IdentityData parse(
    String rawText, {
    String? nationalIdText,
    String? nameText,
    String? birthDateText,
  }) {
    final lines = _lines(rawText);
    return IdentityData(
      identityNumber: _extractOrEmpty(() => _nationalId(lines, nationalIdText)),
      fullName: _extractOrEmpty(() => _arabicName(lines, nameText)),
      birthDate: _extractOrEmpty(() => _birthDate(lines, birthDateText)),
      address: '',
    );
  }

  static String _extractOrEmpty(String Function() extract) {
    try {
      return extract();
    } on IdentityScanFailure {
      return '';
    }
  }

  static List<String> _lines(String text) => normalizeDigits(text)
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  static String _nationalId(List<String> lines, String? regionText) {
    final global = _idCandidates(lines);
    final region = regionText == null
        ? <String>{}
        : _idCandidates(_lines(regionText), allowTargetedSplit: true);
    final candidates = {...global, ...region};
    if (candidates.length > 1) {
      throw const IdentityScanFailure(
        'ظهرت عدة أرقام محتملة للهوية. أعد التصوير بحيث تظهر بطاقة واحدة فقط.',
        type: IdentityScanFailureType.ambiguousIdentityData,
        technicalCode: 'multiple_national_ids',
      );
    }
    if (candidates.length == 1) return candidates.single;
    throw const IdentityScanFailure(
      'لم نتمكن من تحديد رقم هوية واحد من 9 أرقام. أعد التصوير بوضوح.',
      technicalCode: 'national_id_missing',
    );
  }

  static Set<String> _idCandidates(
    List<String> lines, {
    bool allowTargetedSplit = false,
  }) {
    final candidates = <String>{};
    // Scan each line independently. The separator set deliberately excludes
    // slashes and newlines, so dates and unrelated rows cannot be joined.
    final numericRun = RegExp(
      r'(?<![0-9])(?:[0-9]+(?:[ \t.·-]+[0-9]+)*)(?![0-9])',
    );
    for (final line in lines) {
      for (final match in numericRun.allMatches(line)) {
        final value = match.group(0)!;
        final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length == 9) candidates.add(digits);
      }
    }
    if (allowTargetedSplit && candidates.isEmpty) {
      for (var i = 0; i + 1 < lines.length; i++) {
        final first = lines[i].replaceAll(_idLabel, '').trim();
        final second = lines[i + 1].trim();
        final numericOnly = RegExp(r'^[0-9 \t.·-]+$');
        if (numericOnly.hasMatch(first) && numericOnly.hasMatch(second)) {
          final digits = '$first$second'.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.length == 9) candidates.add(digits);
        }
      }
    }
    return candidates;
  }

  static String _birthDate(List<String> lines, String? regionText) {
    final labeled = <DateTime>{};
    for (var i = 0; i < lines.length; i++) {
      if (!_birthLabel.hasMatch(lines[i])) continue;
      final same = _validDates(lines[i]);
      if (same.isNotEmpty) {
        labeled.addAll(same);
        continue;
      }
      // A neighboring date is accepted only on a line without another label.
      for (final neighbor in [i + 1, i - 1]) {
        if (neighbor < 0 || neighbor >= lines.length) continue;
        if (_isOtherFieldLabel(lines[neighbor])) continue;
        labeled.addAll(_validDates(lines[neighbor]));
      }
    }
    final targeted = regionText == null
        ? <DateTime>[]
        : _validDates(regionText);
    final dates = <DateTime>{...labeled};
    if (targeted.length > 1) {
      throw const IdentityScanFailure(
        'ظهرت عدة تواريخ ميلاد محتملة. أعد تصوير الهوية بوضوح.',
        type: IdentityScanFailureType.ambiguousIdentityData,
        technicalCode: 'multiple_birth_dates',
      );
    }
    if (targeted.isNotEmpty) dates.addAll(targeted);
    if (dates.length > 1) {
      throw const IdentityScanFailure(
        'ظهرت عدة تواريخ ميلاد محتملة. أعد تصوير الهوية بوضوح.',
        type: IdentityScanFailureType.ambiguousIdentityData,
        technicalCode: 'multiple_birth_dates',
      );
    }
    if (dates.isEmpty) {
      throw const IdentityScanFailure(
        'لم نتمكن من قراءة تاريخ ميلاد صحيح. أعد تصوير الهوية بوضوح.',
        technicalCode: 'birth_date_missing_or_invalid',
      );
    }
    final date = dates.single;
    return '${date.day.toString().padLeft(2, '0')} / '
        '${date.month.toString().padLeft(2, '0')} / ${date.year}';
  }

  static List<DateTime> _validDates(String text) {
    final dates = <DateTime>{};
    final today = DateTime.now();
    for (final match in _datePattern.allMatches(normalizeDigits(text))) {
      final first = match.group(1)!;
      final last = match.group(3)!;
      if (first.length != 4 && last.length != 4) continue;
      final yearFirst = first.length == 4;
      final year = int.parse(yearFirst ? first : last);
      final month = int.parse(match.group(2)!);
      final day = int.parse(yearFirst ? last : first);
      final date = DateTime(year, month, day);
      if (year >= today.year - 120 &&
          year <= today.year &&
          date.year == year &&
          date.month == month &&
          date.day == day &&
          !date.isAfter(DateTime(today.year, today.month, today.day))) {
        dates.add(date);
      }
    }
    return dates.toList();
  }

  static String _arabicName(List<String> lines, String? regionText) {
    final components = <int, String>{};
    var sawSplitLabel = false;
    final sources = [lines, if (regionText != null) _lines(regionText)];
    for (final source in sources) {
      final parsed = _splitNameFields(source);
      sawSplitLabel |= parsed.sawLabel;
      for (final entry in parsed.values.entries) {
        final previous = components[entry.key];
        if (previous != null && previous != entry.value) {
          throw const IdentityScanFailure(
            'تعذّر تمييز الاسم العربي. أعد تصوير الهوية بوضوح.',
            type: IdentityScanFailureType.ambiguousIdentityData,
            technicalCode: 'conflicting_name_fields',
          );
        }
        components[entry.key] = entry.value;
      }
    }

    final fullNames = <String>{
      for (final source in sources) ..._labeledFullNames(source),
    };
    if (fullNames.length > 1) {
      throw const IdentityScanFailure(
        'تعذّر تمييز الاسم العربي. أعد تصوير الهوية بوضوح.',
        type: IdentityScanFailureType.ambiguousIdentityData,
        technicalCode: 'conflicting_name_fields',
      );
    }

    if (sawSplitLabel) {
      if (components.length >= 3) {
        final splitName = [
          for (var i = 0; i < 4; i++)
            if (components.containsKey(i)) components[i]!,
        ].join(' ');
        if (fullNames.isNotEmpty && fullNames.single != splitName) {
          throw const IdentityScanFailure(
            'تعذّر تمييز الاسم العربي. أعد تصوير الهوية بوضوح.',
            type: IdentityScanFailureType.ambiguousIdentityData,
            technicalCode: 'conflicting_name_fields',
          );
        }
        return splitName;
      }
      if (fullNames.isNotEmpty) return fullNames.single;
      throw const IdentityScanFailure(
        'لم نتمكن من قراءة الاسم العربي الكامل. أعد تصوير الهوية بوضوح.',
        technicalCode: 'arabic_name_missing',
      );
    }
    if (fullNames.isNotEmpty) return fullNames.single;
    throw const IdentityScanFailure(
      'لم نتمكن من قراءة الاسم العربي الكامل. أعد تصوير الهوية بوضوح.',
      technicalCode: 'arabic_name_missing',
    );
  }

  // Compatibility with cards that explicitly print one full-name field.
  static Set<String> _labeledFullNames(List<String> lines) {
    final names = <String>{};
    for (var i = 0; i < lines.length; i++) {
      if (!_fullNameLabel.hasMatch(lines[i])) continue;
      for (final candidate in [
        lines[i].replaceAll(_fullNameLabel, ''),
        if (i + 1 < lines.length) lines[i + 1],
      ]) {
        final words = _arabicWord
            .allMatches(candidate)
            .map((m) => m.group(0)!)
            .toList();
        if (words.length >= 3 &&
            words.length <= 5 &&
            _fieldIndex(candidate) == null &&
            !_isOtherFieldLabel(candidate)) {
          names.add(words.join(' '));
        }
      }
    }
    return names;
  }

  static _SplitNameResult _splitNameFields(List<String> lines) {
    final values = <int, String>{};
    final assigned = <int>{};
    var sawLabel = false;
    final firstLabelIndex = lines.indexWhere(
      (line) => _fieldIndex(line) != null,
    );
    final reverseRows =
        firstLabelIndex > 0 &&
        _singleNameValue(lines[firstLabelIndex - 1]) != null;
    for (var i = 0; i < lines.length; i++) {
      final field = _fieldIndex(lines[i]);
      if (field == null) continue;
      sawLabel = true;
      final label = _nameLabels[field];
      String? value = _singleNameValue(lines[i].replaceAll(label, ''));
      if (value == null) {
        final neighbors = reverseRows ? [i - 1, i + 1] : [i + 1, i - 1];
        for (final neighbor in neighbors) {
          if (neighbor < 0 ||
              neighbor >= lines.length ||
              assigned.contains(neighbor)) {
            continue;
          }
          value = _singleNameValue(lines[neighbor]);
          if (value != null) {
            assigned.add(neighbor);
            break;
          }
        }
      }
      if (value == null) continue;
      if (values.containsKey(field) && values[field] != value) {
        throw const IdentityScanFailure(
          'تعذّر تمييز الاسم العربي. أعد تصوير الهوية بوضوح.',
          type: IdentityScanFailureType.ambiguousIdentityData,
          technicalCode: 'conflicting_name_fields',
        );
      }
      values[field] = value;
    }
    return _SplitNameResult(values, sawLabel);
  }

  static int? _fieldIndex(String line) {
    for (var i = 0; i < _nameLabels.length; i++) {
      if (_nameLabels[i].hasMatch(line)) return i;
    }
    return null;
  }

  static String? _singleNameValue(String line) {
    if (_fieldIndex(line) != null || _isOtherFieldLabel(line)) return null;
    final words = _arabicWord.allMatches(line).map((m) => m.group(0)!).toList();
    const excluded = {
      'بطاقة',
      'هوية',
      'الهوية',
      'فلسطين',
      'الفلسطينية',
      'السلطة',
      'الوطنية',
      'وزارة',
      'الداخلية',
      'تاريخ',
      'ميلاد',
      'الميلاد',
      'الولادة',
      'الجنس',
      'ذكر',
      'أنثى',
      'مكان',
      'السكن',
      'العنوان',
      'مدينة',
      'غير',
      'واضح',
      'مقروء',
    };
    if (words.isEmpty || words.length > 2 || words.any(excluded.contains)) {
      return null;
    }
    if (RegExp(r'[0-9]').hasMatch(line)) return null;
    return words.join(' ');
  }

  static bool _isOtherFieldLabel(String line) =>
      _idLabel.hasMatch(line) ||
      _birthLabel.hasMatch(line) ||
      _fullNameLabel.hasMatch(line) ||
      RegExp(
        r'اسم\s*(?:الأم|الام)|مكان\s*الولادة|الجنس|العنوان|تاريخ',
      ).hasMatch(line);
}

class _SplitNameResult {
  const _SplitNameResult(this.values, this.sawLabel);
  final Map<int, String> values;
  final bool sawLabel;
}
