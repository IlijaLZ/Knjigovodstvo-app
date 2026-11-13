import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/glasovne_komande/glasovno_dugme.dart';

// Ekran za unos kao "Nova kalkulacija": PopScope koji sam radi Get.back,
// osim dok čuva.
class _Unos extends StatelessWidget {
  final bool cuva;

  const _Unos({this.cuva = false});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !cuva) Get.back(result: false);
      },
      child: const Scaffold(body: Text('unos')),
    );
  }
}

void main() {
  Future<void> pokreni(WidgetTester tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: Text('glavni'))),
    );
  }

  testWidgets('zatvori ekran za unos prije prelaska na početnu', (
    tester,
  ) async {
    await pokreni(tester);
    Get.to(() => const _Unos());
    await tester.pumpAndSettle();
    expect(find.text('unos'), findsOneWidget);

    final ok = await glasovniController().naGlavniEkran();
    await tester.pumpAndSettle();
    expect(ok, isTrue);
    expect(find.text('glavni'), findsOneWidget);
    expect(find.text('unos'), findsNothing);
  });

  testWidgets('dva ekrana jedan preko drugog + dijalog', (tester) async {
    await pokreni(tester);
    Get.to(() => const _Unos());
    await tester.pumpAndSettle();
    Get.to(() => const Scaffold(body: Text('kartica')));
    await tester.pumpAndSettle();
    Get.dialog(const AlertDialog(content: Text('dijalog')));
    await tester.pumpAndSettle();

    final ok = await glasovniController().naGlavniEkran();
    await tester.pumpAndSettle();
    expect(ok, isTrue);
    expect(find.text('glavni'), findsOneWidget);
  });

  testWidgets('dok se čuva, ekran ostaje i javlja se false', (tester) async {
    await pokreni(tester);
    Get.to(() => const _Unos(cuva: true));
    await tester.pumpAndSettle();

    final ok = await glasovniController().naGlavniEkran();
    await tester.pumpAndSettle();
    expect(ok, isFalse);
    expect(find.text('unos'), findsOneWidget);
  });
}
