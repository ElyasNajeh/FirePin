import 'package:crypto/crypto.dart';
import 'package:firepin_ui/features/onboarding/identity_document_processor.dart';
import 'package:firepin_ui/features/onboarding/identity_image_processor.dart';
import 'package:firepin_ui/features/onboarding/identity_screens.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'test_fakes.dart';

void _mobileSize(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _PreparedImagePreprocessor implements IdentityImagePreprocessor {
  const _PreparedImagePreprocessor();

  @override
  Future<ProcessedIdentityImage> process(
    Uint8List bytes, {
    IdentityCaptureRegion? region,
  }) async => ProcessedIdentityImage(
    bytes: bytes,
    width: 1200,
    height: 760,
    wasCropped: region != null,
  );
}

class _ReadyTessdataProvider implements IdentityTessdataProvider {
  const _ReadyTessdataProvider();

  @override
  Future<String> prepare() async => '/tmp/firepin-test-tessdata';
}

class _FailingOcrEngine implements IdentityOcrEngine {
  const _FailingOcrEngine(this.code);
  final String code;

  @override
  Future<String> recognize({
    required String imagePath,
    required String tessdataPath,
    required String language,
    IdentityOcrMode mode = IdentityOcrMode.fullCard,
  }) => throw PlatformException(code: code, message: 'synthetic failure');
}

class _ScriptedOcrEngine implements IdentityOcrEngine {
  const _ScriptedOcrEngine(this.responses, {this.failingMode});

  final Map<IdentityOcrMode, String> responses;
  final IdentityOcrMode? failingMode;

  @override
  Future<String> recognize({
    required String imagePath,
    required String tessdataPath,
    required String language,
    IdentityOcrMode mode = IdentityOcrMode.fullCard,
  }) async {
    if (mode == failingMode) {
      throw PlatformException(code: 'OCR_EXECUTION_FAILED');
    }
    return responses[mode] ?? '';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Palestinian identity OCR parsing', () {
    test('only ID is extracted without blocking missing fields', () {
      final result = IdentityTextParser.parse('رقم الهوية: 123 456 789');
      expect(result.identityNumber, '123456789');
      expect(result.fullName, isEmpty);
      expect(result.birthDate, isEmpty);
    });

    test('only ordered Arabic name is extracted', () {
      final result = IdentityTextParser.parse('''
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
''');
      expect(result.fullName, 'أحمد محمد سالم خليل');
      expect(result.identityNumber, isEmpty);
      expect(result.birthDate, isEmpty);
    });

    test('only labeled birth date is extracted', () {
      final result = IdentityTextParser.parse('تاريخ الميلاد: 07/11/2000');
      expect(result.birthDate, '07 / 11 / 2000');
      expect(result.identityNumber, isEmpty);
      expect(result.fullName, isEmpty);
    });

    test('conflicting name leaves name empty while retaining ID and date', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
الاسم الشخصي: خالد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
تاريخ الميلاد: 07/11/2000
''');
      expect(result.fullName, isEmpty);
      expect(result.identityNumber, '123456789');
      expect(result.birthDate, '07 / 11 / 2000');
    });

    test('unreadable OCR returns empty editable fields', () {
      final result = IdentityTextParser.parse('؟ ؟ ؟');
      expect(result.fullName, isEmpty);
      expect(result.identityNumber, isEmpty);
      expect(result.birthDate, isEmpty);
      expect(result.address, isEmpty);
    });

    test('an unlabeled card date is never substituted for birth date', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
تاريخ الطباعة: 28/12/2025
''');
      expect(result.birthDate, isEmpty);
    });

    test('assembles four labeled Arabic name rows on a structured card', () {
      final result = IdentityTextParser.parse('''
بطاقة هوية
رقم الهوية: 123 456 789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
اسم الأم: ليلى
تاريخ الميلاد: 07/11/2000
مكان الولادة: مدينة تجريبية
الجنس: ذكر
''');
      expect(result.fullName, 'أحمد محمد سالم خليل');
      expect(result.identityNumber, '123456789');
      expect(result.birthDate, '07 / 11 / 2000');
    });

    test('associates values on following lines with their name labels', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي
أحمد
اسم الاب
محمد
اسم الجد
سالم
اسم العائلة
خليل
تاريخ الميلاد
07/11/2000
''');
      expect(result.fullName, 'أحمد محمد سالم خليل');
      expect(result.birthDate, '07 / 11 / 2000');
    });

    test('associates values preceding labels in reversed OCR rows', () {
      final result = IdentityTextParser.parse('''
رقم الهوية 123456789
أحمد
الاسم الشخصي
محمد
اسم الأب
سالم
اسم الجد
خليل
اسم العائلة
تاريخ الميلاد 07/11/2000
''');
      expect(result.fullName, 'أحمد محمد سالم خليل');
    });

    test('accepts punctuation and narrow spacing inside one ID', () {
      for (final id in ['123.456.789', '123 · 456 · 789', '1 23456789']) {
        final result = IdentityTextParser.parse('''
رقم الهوية: $id
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
تاريخ الميلاد: 07/11/2000
''');
        expect(result.identityNumber, '123456789');
      }
    });

    test('selects labeled birth date over another printed date', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
تاريخ الميلاد: 07/11/2000
تاريخ الطباعة: 28/12/2025
''');
      expect(result.birthDate, '07 / 11 / 2000');
    });

    test(
      'does not use a nearby printing date when birth date is unreadable',
      () {
        final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
تاريخ الميلاد: غير واضح
تاريخ الطباعة: 28/12/2025
''');
        expect(result.birthDate, isEmpty);
        expect(result.identityNumber, '123456789');
      },
    );

    test('does not treat a sole labeled printing date as birth date', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
تاريخ الطباعة: 28/12/2025
''');
      expect(result.birthDate, isEmpty);
    });

    test('ignores Hebrew and unrelated Arabic text around split fields', () {
      final result = IdentityTextParser.parse('''
بطاقة هوية זהות
رقم الهوية: 123-456-789 מספר
الاسم الشخصي: أحمد עברית
اسم الأب: محمد אב
اسم الجد: سالم סבא
اسم العائلة: خليل משפחה
תאריך تاريخ الميلاد: 07/11/2000
مكان الولادة: مدينة تجريبية
''');
      expect(result.fullName, 'أحمد محمد سالم خليل');
    });

    test('accepts three independently labeled name parts', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم العائلة: خليل
تاريخ الميلاد: 07/11/2000
''');
      expect(result.fullName, 'أحمد محمد خليل');
    });

    test('leaves name empty when only two split fields can be read', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
مكان الولادة: مدينة تجريبية
تاريخ الميلاد: 07/11/2000
''');
      expect(result.fullName, isEmpty);
      expect(result.identityNumber, '123456789');
    });

    test('does not turn unreadable name text into a component', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: غير واضح
تاريخ الميلاد: 07/11/2000
''');
      expect(result.fullName, isEmpty);
    });

    test('recovers split ID only inside its targeted region', () {
      final result = IdentityTextParser.parse('''
رقم الهوية غير واضح
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
تاريخ الميلاد: 07/11/2000
''', nationalIdText: 'رقم الهوية\n123 456\n789');
      expect(result.identityNumber, '123456789');
    });

    test('recovers missing fields from matching card regions', () {
      final result = IdentityTextParser.parse(
        '''
بطاقة هوية
رقم الهوية غير واضح
الاسم الشخصي: أحمد
اسم الأب: محمد
تاريخ الميلاد غير واضح
''',
        nationalIdText: '123.456.789',
        nameText: 'اسم الجد: سالم\nاسم العائلة: خليل',
        birthDateText: '07/11/2000',
      );
      expect(result.identityNumber, '123456789');
      expect(result.fullName, 'أحمد محمد سالم خليل');
      expect(result.birthDate, '07 / 11 / 2000');
    });

    test('accepts valid Palestinian identity OCR text', () {
      final result = IdentityTextParser.parse('''
دولة فلسطين
وزارة الداخلية
بطاقة هوية
رقم الهوية: ١٢٣ ٤٥٦ ٧٨٩
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: ١٤/٠٥/١٩٩٨
تاريخ الانتهاء: 01/01/2030
''');

      expect(result.identityNumber, '123456789');
      expect(result.fullName, 'أحمد محمد عبد الله');
      expect(result.birthDate, '14 / 05 / 1998');
      expect(result.address, isEmpty);
    });

    test('normalizes Arabic digits', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: ١٢٣ ٤٥٦ ٧٨٩
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: ١٤-٠٥-١٩٩٨
''');
      expect(result.identityNumber, '123456789');
      expect(result.birthDate, '14 / 05 / 1998');
    });

    test('normalizes Persian digits', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: ۱۲۳ ۴۵۶ ۷۸۹
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: ۱۴.۰۵.۱۹۹۸
''');
      expect(result.identityNumber, '123456789');
      expect(result.birthDate, '14 / 05 / 1998');
    });

    test('accepts exactly one valid nine-digit ID', () {
      final result = IdentityTextParser.parse('''
123-456-789
الاسم الكامل
أحمد محمد عبد الله
تاريخ الميلاد 14/05/1998
''');
      expect(result.identityNumber, '123456789');
    });

    test('leaves ambiguous nine-digit ID empty and retains other fields', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
رقم آخر: 987654321
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 14/05/1998
''');
      expect(result.identityNumber, isEmpty);
      expect(result.fullName, 'أحمد محمد عبد الله');
      expect(result.birthDate, '14 / 05 / 1998');
    });

    test('leaves missing nine-digit ID empty', () {
      final result = IdentityTextParser.parse('''
بطاقة هوية فلسطينية
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 14/05/1998
''');
      expect(result.identityNumber, isEmpty);
    });

    test('leaves invalid birth date empty', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 31/02/1998
''');
      expect(result.birthDate, isEmpty);
    });

    test('accepts a valid labeled birth date', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 1998/05/14
''');
      expect(result.birthDate, '14 / 05 / 1998');
    });

    test('extracts a labeled Arabic full name', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الرباعي
أحمد محمد عبد الله صالح
تاريخ الميلاد: 14/05/1998
''');
      expect(result.fullName, 'أحمد محمد عبد الله صالح');
    });

    test(
      'uses labeled full-name fallback when split fields are incomplete',
      () {
        final result = IdentityTextParser.parse('''
الاسم الشخصي: أحمد
اسم الأب: محمد
الاسم الكامل: أحمد محمد سالم خليل
''');
        expect(result.fullName, 'أحمد محمد سالم خليل');
      },
    );

    test('leaves name empty when split and full-name fields conflict', () {
      final result = IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
الاسم الكامل: خالد محمود علي حسن
تاريخ الميلاد: 07/11/2000
''');
      expect(result.fullName, isEmpty);
      expect(result.identityNumber, '123456789');
      expect(result.birthDate, '07 / 11 / 2000');
    });

    test('leaves missing Arabic name empty', () {
      final result = IdentityTextParser.parse('''
دولة فلسطين وزارة الداخلية
رقم الهوية: 123456789
تاريخ الميلاد: 14/05/1998
العنوان: رام الله
''');
      expect(result.fullName, isEmpty);
    });
  });

  group('OCR runtime errors', () {
    test('classifies tessdata, initialization, and execution failures', () {
      expect(
        TesseractIdentityDocumentProcessor.classifyOcrError(
          PlatformException(code: 'TESSDATA_INVALID'),
        ).type,
        IdentityScanFailureType.tessdataAssetFailure,
      );
      expect(
        TesseractIdentityDocumentProcessor.classifyOcrError(
          PlatformException(code: 'INIT_FAILED'),
        ).type,
        IdentityScanFailureType.ocrInitializationFailure,
      );
      expect(
        TesseractIdentityDocumentProcessor.classifyOcrError(
          PlatformException(code: 'OCR_EXECUTION_FAILED'),
        ).type,
        IdentityScanFailureType.ocrExecutionFailure,
      );
    });

    test('processor preserves classified native OCR failures', () async {
      const processor = TesseractIdentityDocumentProcessor(
        preprocessor: _PreparedImagePreprocessor(),
        ocrEngine: _FailingOcrEngine('INIT_FAILED'),
        tessdataProvider: _ReadyTessdataProvider(),
      );

      await expectLater(
        processor.extract(Uint8List.fromList([1, 2, 3])),
        throwsA(
          isA<IdentityScanFailure>()
              .having(
                (failure) => failure.type,
                'type',
                IdentityScanFailureType.ocrInitializationFailure,
              )
              .having(
                (failure) => failure.technicalCode,
                'technicalCode',
                'INIT_FAILED',
              ),
        ),
      );
    });

    test('targeted OCR contributes fields independently', () async {
      const processor = TesseractIdentityDocumentProcessor(
        preprocessor: _PreparedImagePreprocessor(),
        ocrEngine: _ScriptedOcrEngine({
          IdentityOcrMode.fullCard: 'رقم الهوية: 123456789',
          IdentityOcrMode.arabicNames:
              'الاسم الشخصي: أحمد\nاسم الأب: محمد\nاسم الجد: سالم\nاسم العائلة: خليل',
          IdentityOcrMode.birthDate: '07/11/2000',
        }),
        tessdataProvider: _ReadyTessdataProvider(),
      );
      final photo = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 1000, height: 650)),
      );

      final result = await processor.extract(photo);
      expect(result.identityNumber, '123456789');
      expect(result.fullName, 'أحمد محمد سالم خليل');
      expect(result.birthDate, '07 / 11 / 2000');
    });

    test('one targeted OCR execution error retains other fields', () async {
      const processor = TesseractIdentityDocumentProcessor(
        preprocessor: _PreparedImagePreprocessor(),
        ocrEngine: _ScriptedOcrEngine({
          IdentityOcrMode.fullCard: 'رقم الهوية: 123456789',
          IdentityOcrMode.arabicNames:
              'الاسم الشخصي: أحمد\nاسم الأب: محمد\nاسم الجد: سالم\nاسم العائلة: خليل',
        }, failingMode: IdentityOcrMode.birthDate),
        tessdataProvider: _ReadyTessdataProvider(),
      );
      final photo = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 1000, height: 650)),
      );

      final result = await processor.extract(photo);
      expect(result.identityNumber, '123456789');
      expect(result.fullName, 'أحمد محمد سالم خليل');
      expect(result.birthDate, isEmpty);
    });

    test('bundled Arabic and English traineddata hashes are pinned', () async {
      final arabic = await rootBundle.load('assets/tessdata/ara.traineddata');
      final english = await rootBundle.load('assets/tessdata/eng.traineddata');
      expect(
        sha256.convert(arabic.buffer.asUint8List()).toString(),
        'e3206d3dc87fd50c24a0fb9f01838615911d25168f4e64415244b67d2bb3e729',
      );
      expect(
        sha256.convert(english.buffer.asUint8List()).toString(),
        '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
      );
    });
  });

  group('identity image crop and preprocessing', () {
    test('maps the visible cover-preview guide to capture pixels', () {
      final crop = IdentityCropGeometry.fromCoverPreview(
        imageSize: const Size(1200, 1600),
        previewSize: const Size(400, 800),
        guideRect: const Rect.fromLTWH(20, 286, 360, 228),
      );
      expect(crop.x, 240);
      expect(crop.y, 572);
      expect(crop.width, 720);
      expect(crop.height, 456);
    });

    test('rejects invalid crop geometry', () {
      expect(
        () => IdentityCropGeometry.fromCoverPreview(
          imageSize: Size.zero,
          previewSize: const Size(400, 800),
          guideRect: const Rect.fromLTWH(20, 286, 360, 228),
        ),
        throwsFormatException,
      );
    });

    test('bakes orientation, crops, and conservatively preprocesses', () async {
      final source = image.Image(width: 1600, height: 1200);
      image.fill(source, color: image.ColorRgb8(150, 100, 50));
      source.exif.imageIfd.orientation = 6;
      final sourceBytes = Uint8List.fromList(image.encodeJpg(source));

      final result = await const ConservativeIdentityImagePreprocessor()
          .process(
            sourceBytes,
            region: const IdentityCaptureRegion(
              previewSize: Size(400, 800),
              guideRect: Rect.fromLTWH(20, 286, 360, 228),
            ),
          );

      expect(result.wasCropped, isTrue);
      expect(result.width, 1280);
      expect(result.width / result.height, closeTo(720 / 456, 0.01));
      final decoded = image.decodeJpg(result.bytes)!;
      final pixel = decoded.getPixel(100, 100);
      expect((pixel.r - pixel.g).abs(), lessThanOrEqualTo(2));
      expect((pixel.g - pixel.b).abs(), lessThanOrEqualTo(2));
    });

    test('accepts and upscales a modest guide crop for OCR', () async {
      final source = image.Image(width: 800, height: 600);
      image.fill(source, color: image.ColorRgb8(140, 150, 130));
      final result = await const ConservativeIdentityImagePreprocessor()
          .process(
            Uint8List.fromList(image.encodeJpg(source)),
            region: const IdentityCaptureRegion(
              previewSize: Size(800, 600),
              guideRect: Rect.fromLTWH(100, 100, 522, 332),
            ),
          );

      expect(result.wasCropped, isTrue);
      expect(result.width, 1280);
      expect(result.width / result.height, closeTo(522 / 332, 0.01));
      final decoded = image.decodeJpg(result.bytes)!;
      expect(decoded.width, result.width);
      expect(decoded.height, result.height);
    });

    test('still rejects a genuinely tiny guide crop', () async {
      final source = image.Image(width: 800, height: 600);
      await expectLater(
        const ConservativeIdentityImagePreprocessor().process(
          Uint8List.fromList(image.encodeJpg(source)),
          region: const IdentityCaptureRegion(
            previewSize: Size(800, 600),
            guideRect: Rect.fromLTWH(100, 100, 300, 190),
          ),
        ),
        throwsA(isA<IdentityImageProcessingException>()),
      );
    });

    test('keeps the stricter floor for an uncropped full image', () async {
      final source = image.Image(width: 522, height: 332);
      await expectLater(
        const ConservativeIdentityImagePreprocessor().process(
          Uint8List.fromList(image.encodeJpg(source)),
        ),
        throwsA(isA<IdentityImageProcessingException>()),
      );
    });
  });

  testWidgets('camera-only capture extracts a new photo and has no gallery', (
    tester,
  ) async {
    _mobileSize(tester);
    final camera = FakeCamera();
    final processor = FakeIdentityDocumentProcessor();
    IdentityData? extracted;

    await tester.pumpWidget(
      MaterialApp(
        home: IdentityCaptureScreen(
          cameraFactory: () => camera,
          permissions: FakePermissions(),
          processor: processor,
          onExtracted: (value) => extracted = value,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('المعرض'), findsNothing);
    expect(find.byIcon(Icons.photo_library), findsNothing);
    await tester.tap(find.text('التقاط الهوية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(camera.captures, 1);
    expect(processor.calls, 1);
    expect(processor.receivedImage, testPhoto);
    expect(processor.receivedRegion, isNotNull);
    expect(
      processor.receivedRegion!.guideRect.width /
          processor.receivedRegion!.guideRect.height,
      closeTo(1.58, 0.01),
    );
    expect(extracted?.identityNumber, '123456789');
  });

  testWidgets('failed extraction shows a retake message and allows retry', (
    tester,
  ) async {
    _mobileSize(tester);
    final camera = FakeCamera();
    final processor = FakeIdentityDocumentProcessor(
      failure: const IdentityScanFailure(
        'لم نتمكن من قراءة الهوية. أعد التصوير بوضوح.',
      ),
      failuresRemaining: 1,
    );
    IdentityData? extracted;

    await tester.pumpWidget(
      MaterialApp(
        home: IdentityCaptureScreen(
          cameraFactory: () => camera,
          permissions: FakePermissions(),
          processor: processor,
          onExtracted: (identity) => extracted = identity,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('التقاط الهوية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.byKey(const ValueKey('identity-scan-error')), findsOneWidget);
    expect(find.textContaining('أعد التصوير'), findsOneWidget);
    await tester.tap(find.text('التقاط الهوية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(processor.calls, 2);
    expect(extracted?.identityNumber, '123456789');
  });

  testWidgets('extracted identity data prefills registration details', (
    tester,
  ) async {
    const identity = IdentityData(
      fullName: 'أحمد محمد عبد الله',
      identityNumber: '123456789',
      birthDate: '14 / 05 / 1998',
      address: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityDetailsScreen(initialData: identity, onContinue: (_) {}),
      ),
    );

    String fieldText(String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    expect(fieldText('identity-full-name'), identity.fullName);
    expect(fieldText('identity-national-id'), identity.identityNumber);
    expect(fieldText('identity-birth-date'), identity.birthDate);
  });

  testWidgets('partial capture opens review and requires manual completion', (
    tester,
  ) async {
    _mobileSize(tester);
    final camera = FakeCamera();
    final processor = FakeIdentityDocumentProcessor(
      result: const IdentityData(
        fullName: '',
        identityNumber: '123456789',
        birthDate: '',
        address: '',
      ),
    );
    IdentityData? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => IdentityCaptureScreen(
            cameraFactory: () => camera,
            permissions: FakePermissions(),
            processor: processor,
            onExtracted: (identity) {
              Navigator.of(context).push(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => IdentityDetailsScreen(
                    initialData: identity,
                    onContinue: (value) => submitted = value,
                  ),
                  transitionDuration: Duration.zero,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('التقاط الهوية'));
    await tester.pumpAndSettle();

    expect(find.byType(IdentityDetailsScreen), findsOneWidget);
    expect(
      find.text('تحقق من البيانات وأكمل أي حقل لم تتم قراءته تلقائيًا.'),
      findsOneWidget,
    );
    String fieldText(String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    expect(fieldText('identity-national-id'), '123456789');
    expect(fieldText('identity-full-name'), isEmpty);
    expect(fieldText('identity-birth-date'), isEmpty);

    await tester.tap(find.text('متابعة'));
    await tester.pump();
    expect(submitted, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('identity-full-name')),
      'أحمد محمد',
    );
    await tester.tap(find.text('متابعة'));
    await tester.pump();
    expect(submitted, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('identity-birth-date')),
      '07/11/2000',
    );
    await tester.tap(find.text('متابعة'));
    await tester.pump();
    expect(submitted?.identityNumber, '123456789');
    expect(submitted?.fullName, 'أحمد محمد');
    expect(submitted?.birthDate, '07/11/2000');
  });

  for (final entry in <String, IdentityData>{
    'name only': const IdentityData(
      fullName: 'أحمد محمد سالم خليل',
      identityNumber: '',
      birthDate: '',
      address: '',
    ),
    'birth date only': const IdentityData(
      fullName: '',
      identityNumber: '',
      birthDate: '07 / 11 / 2000',
      address: '',
    ),
  }.entries) {
    testWidgets('review receives ${entry.key} partial OCR', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IdentityDetailsScreen(
            initialData: entry.value,
            onContinue: (_) {},
          ),
        ),
      );
      String fieldText(String key) => tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text;
      expect(fieldText('identity-full-name'), entry.value.fullName);
      expect(fieldText('identity-national-id'), isEmpty);
      expect(fieldText('identity-birth-date'), entry.value.birthDate);
    });
  }
}
