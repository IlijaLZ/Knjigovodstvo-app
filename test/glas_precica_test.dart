import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/glasovne_komande/glasovno_dugme.dart';
import 'package:knjigovodstvo_app/glasovne_komande/zec_panel.dart';

void main() {
  testWidgets('⌘⇧Space pokreće zeca bez ikakvog dugmeta', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: Text('glavni')),
        builder: (context, child) => ZecSloj(child: child!),
      ),
    );
    final c = glasovniController();
    expect(c.zec.value, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    // Test se ne pokreće kao Kalkulino.app, pa zec javlja da ne može
    // slušati — dokaz da je prečica stigla do kontrolera.
    expect(c.zec.value, isNotNull);
    c.sakrij();
    await tester.pump(const Duration(seconds: 1));
  });
}
