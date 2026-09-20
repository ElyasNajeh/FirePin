import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

import 'onboarding_models.dart';

abstract interface class IdentityDocumentProcessor {
  Future<IdentityData> extract(Uint8List imageBytes);
}

class IdentityScanFailure implements Exception {
  const IdentityScanFailure(this.message);
  final String message;
}

class TesseractIdentityDocumentProcessor implements IdentityDocumentProcessor {
  const TesseractIdentityDocumentProcessor();

  @override
  Future<IdentityData> extract(Uint8List imageBytes) async {
    await _validateImage(imageBytes);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'firepin-id-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    try {
      await file.writeAsBytes(imageBytes, flush: true);
      final text = await TesseractOcr.extractText(
        file.path,
        config: const OCRConfig(
          language: 'ara+eng',
          engine: OCREngine.tesseract,
        ),
      );
      return IdentityTextParser.parse(text);
    } on IdentityScanFailure {
      rethrow;
    } on Object {
      throw const IdentityScanFailure(
        'تعذّرت قراءة صورة الهوية. تأكد من الإضاءة والوضوح ثم أعد التصوير.',
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _validateImage(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const IdentityScanFailure(
        'لم يتم التقاط صورة قابلة للقراءة. أعد تصوير بطاقة الهوية.',
      );
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      if (image.width < 640 || image.height < 400) {
        throw const IdentityScanFailure(
          'دقة الصورة منخفضة. قرّب بطاقة الهوية وأعد التصوير بوضوح.',
        );
      }
    } on IdentityScanFailure {
      rethrow;
    } on Object {
      throw const IdentityScanFailure(
        'الصورة غير صالحة أو غير قابلة للقراءة. أعد تصوير بطاقة الهوية.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
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
    final labeledText = _labeledText(
      lines,
      (line) => RegExp(
        r'(رقم\s*(الهوية|هويه)|هوية\s*رقم|identity|\bid\b)',
        caseSensitive: false,
      ).hasMatch(line),
    );
    final labeled = _idCandidates(labeledText);
    if (labeled.length == 1) return labeled.single;
    final all = _idCandidates(lines.join('\n'));
    if (all.length == 1) return all.single;
    throw const IdentityScanFailure(
      'لم نتمكن من تحديد رقم هوية واحد من 9 أرقام. أعد التصوير بوضوح.',
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
    final fromLabel = _bestName(labeled);
    if (fromLabel != null) return fromLabel;
    final fromDocument = _bestName(lines);
    if (fromDocument != null) return fromDocument;
    throw const IdentityScanFailure(
      'لم نتمكن من قراءة الاسم العربي الكامل. أعد تصوير الهوية بوضوح.',
    );
  }

  static String? _bestName(Iterable<String> lines) {
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
      if (candidateWords.length >= 2 && candidateWords.length > bestWords) {
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
