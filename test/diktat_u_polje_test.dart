import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/glasovne_komande/diktat.dart';
import 'package:knjigovodstvo_app/glasovne_komande/diktat_u_polje.dart';
import 'package:knjigovodstvo_app/widgets/magacin_ui.dart';

// Forma kao na ekranima za unos: OznakaPolja iznad TextField-a.
class _Forma extends StatelessWidget {
  final TextEditingController broj;
  final TextEditingController datum;
  final TextEditingController izdao;
  final FocusNode fokus;
  final ValueChanged<String> onBroj;

  const _Forma({
    required this.broj,
    required this.datum,
    required this.izdao,
    required this.fokus,
    required this.onBroj,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Column(
              children: [
                const OznakaPolja('Količina'),
                TextField(
                  controller: broj,
                  focusNode: fokus,
                  onChanged: onBroj,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                ),
              ],
            ),
            Column(
              children: [
                const OznakaPolja('Datum'),
                // Samo za čitanje (bira se kalendarom) — diktat ga preskače.
                TextField(controller: datum, readOnly: true),
              ],
            ),
            Column(
              children: [
                const OznakaPolja('Izdao'),
                TextField(controller: izdao),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late TextEditingController broj, datum, izdao;
  late FocusNode fokus;
  late List<String> promjene;

  Future<void> pripremi(WidgetTester tester) async {
    broj = TextEditingController(text: '7');
    datum = TextEditingController(text: '12.11.2026.');
    izdao = TextEditingController();
    fokus = FocusNode();
    promjene = [];
    await tester.pumpWidget(
      _Forma(
        broj: broj,
        datum: datum,
        izdao: izdao,
        fokus: fokus,
        onBroj: promjene.add,
      ),
    );
    fokus.requestFocus();
    await tester.pump();
  }

  testWidgets('bez fokusa nema diktata (to su komande)', (tester) async {
    await pripremi(tester);
    fokus.unfocus();
    await tester.pump();
    expect(DiktatSesija.izFokusa(), isNull);
  });

  testWidgets('ispravka u brojčanom polju + onChanged ekrana', (tester) async {
    await pripremi(tester);
    final d = DiktatSesija.izFokusa()!;
    expect(d.oznaka, 'Količina');
    expect(d.vrsta, VrstaPolja.broj);

    // Uživo, kako rezultati stižu.
    await tester.runAsync(() => d.primijeni('1232'));
    expect(broj.text, '1232');
    await tester.runAsync(() => d.primijeni('1232 ne nego'));
    expect(broj.text, '1232');
    await tester.runAsync(() => d.primijeni('1232 ne nego 1234'));
    expect(broj.text, '1234');
    expect(promjene.last, '1234'); // ekran je dobio onChanged
    expect(d.upisano.single.$2, '1234');
  });

  testWidgets('dalje: preskače datum i piše u sljedeće polje', (tester) async {
    await pripremi(tester);
    final d = DiktatSesija.izFokusa()!;
    await tester.runAsync(
      () => d.primijeni('dva zarez pet dalje Marko je izdao'),
    );
    await tester.pump();
    expect(broj.text, '2,5');
    expect(datum.text, '12.11.2026.');
    expect(izdao.text, 'Marko');
    expect(d.oznakaTrenutnog, 'Izdao');
    expect(d.upisano.map((u) => u.$1), ['Količina', 'Izdao']);
  });

  testWidgets('slova u brojčanom polju: vraća staru vrijednost', (
    tester,
  ) async {
    await pripremi(tester);
    final d = DiktatSesija.izFokusa()!;
    await tester.runAsync(() => d.primijeni('kakvo je vrijeme'));
    d.vratiPrazna();
    expect(broj.text, '7');
    expect(d.upisano, isEmpty);
  });

  testWidgets('obriši prazni polje; poništi vraća sve', (tester) async {
    await pripremi(tester);
    final d = DiktatSesija.izFokusa()!;
    await tester.runAsync(() => d.primijeni('obriši'));
    expect(broj.text, '');
    expect(d.upisano.single.$3, isTrue);
    d.ponisti();
    expect(broj.text, '7');
  });
}
