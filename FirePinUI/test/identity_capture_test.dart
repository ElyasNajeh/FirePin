import 'package:firepin_ui/features/onboarding/identity_document_processor.dart';
import 'package:firepin_ui/features/onboarding/identity_screens.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void _mobileSize(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('Palestinian identity OCR parsing', () {
    test('extracts Arabic name, nine-digit ID, and labeled birth date', () {
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

    test('rejects missing or ambiguous nine-digit identity numbers', () {
      expect(
        () => IdentityTextParser.parse('''
بطاقة هوية فلسطينية
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 14/05/1998
'''),
        throwsA(isA<IdentityScanFailure>()),
      );
      expect(
        () => IdentityTextParser.parse('''
رقم الهوية: 123456789
رقم آخر: 987654321
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 14/05/1998
'''),
        throwsA(isA<IdentityScanFailure>()),
      );
    });

    test('rejects invalid birth dates and does not invent missing names', () {
      expect(
        () => IdentityTextParser.parse('''
رقم الهوية: 123456789
الاسم الكامل: أحمد محمد عبد الله
تاريخ الميلاد: 31/02/1998
'''),
        throwsA(isA<IdentityScanFailure>()),
      );
      expect(
        () => IdentityTextParser.parse('''
دولة فلسطين وزارة الداخلية
رقم الهوية: 123456789
تاريخ الميلاد: 14/05/1998
'''),
        throwsA(isA<IdentityScanFailure>()),
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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: IdentityCaptureScreen(
          cameraFactory: () => camera,
          permissions: FakePermissions(),
          processor: processor,
          onExtracted: (_) => fail('Extraction must not continue'),
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
    expect(processor.calls, 2);
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
