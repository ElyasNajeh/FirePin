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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Palestinian identity OCR parsing', () {
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
        expect(
          () => IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
تاريخ الميلاد: غير واضح
تاريخ الطباعة: 28/12/2025
'''),
          throwsA(
            isA<IdentityScanFailure>().having(
              (failure) => failure.technicalCode,
              'technicalCode',
              'birth_date_missing_or_invalid',
            ),
          ),
        );
      },
    );

    test('does not treat a sole labeled printing date as birth date', () {
      expect(
        () => IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: سالم
اسم العائلة: خليل
تاريخ الطباعة: 28/12/2025
'''),
        throwsA(
          isA<IdentityScanFailure>().having(
            (failure) => failure.technicalCode,
            'technicalCode',
            'birth_date_missing_or_invalid',
          ),
        ),
      );
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

    test('fails when only two split name fields can be read', () {
      expect(
        () => IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
مكان الولادة: مدينة تجريبية
تاريخ الميلاد: 07/11/2000
'''),
        throwsA(
          isA<IdentityScanFailure>().having(
            (failure) => failure.technicalCode,
            'technicalCode',
            'arabic_name_missing',
          ),
        ),
      );
    });

    test('does not turn unreadable name text into a component', () {
      expect(
        () => IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الشخصي: أحمد
اسم الأب: محمد
اسم الجد: غير واضح
تاريخ الميلاد: 07/11/2000
'''),
        throwsA(
          isA<IdentityScanFailure>().having(
            (failure) => failure.technicalCode,
            'technicalCode',
            'arabic_name_missing',
          ),
        ),
      );
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

    test('rejects multiple ambiguous nine-digit IDs', () {
      expect(
        () => IdentityTextParser.parse('''
رقم الهوية: 123456789
رقم آخر: 987654321
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 14/05/1998
'''),
        throwsA(
          isA<IdentityScanFailure>()
              .having(
                (failure) => failure.type,
                'type',
                IdentityScanFailureType.ambiguousIdentityData,
              )
              .having(
                (failure) => failure.technicalCode,
                'technicalCode',
                'multiple_national_ids',
              ),
        ),
      );
    });

    test('rejects missing nine-digit ID', () {
      expect(
        () => IdentityTextParser.parse('''
بطاقة هوية فلسطينية
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 14/05/1998
'''),
        throwsA(
          isA<IdentityScanFailure>().having(
            (failure) => failure.technicalCode,
            'technicalCode',
            'national_id_missing',
          ),
        ),
      );
    });

    test('rejects invalid birth date', () {
      expect(
        () => IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 31/02/1998
'''),
        throwsA(
          isA<IdentityScanFailure>().having(
            (failure) => failure.technicalCode,
            'technicalCode',
            'birth_date_missing_or_invalid',
          ),
        ),
      );
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

    test('rejects invalid or missing Arabic name', () {
      expect(
        () => IdentityTextParser.parse('''
دولة فلسطين وزارة الداخلية
رقم الهوية: 123456789
تاريخ الميلاد: 14/05/1998
العنوان: رام الله
'''),
        throwsA(
          isA<IdentityScanFailure>().having(
            (failure) => failure.technicalCode,
            'technicalCode',
            'arabic_name_missing',
          ),
        ),
      );
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
      expect(result.width, 720);
      expect(result.height, 456);
      final decoded = image.decodeJpg(result.bytes)!;
      final pixel = decoded.getPixel(100, 100);
      expect((pixel.r - pixel.g).abs(), lessThanOrEqualTo(2));
      expect((pixel.g - pixel.b).abs(), lessThanOrEqualTo(2));
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
}
