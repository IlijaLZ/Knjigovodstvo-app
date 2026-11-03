import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/models/article.dart';
import 'package:knjigovodstvo_app/widgets/input_widget.dart';

double _parse(String text) {
  return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
}

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

// Količine normativa znaju biti male (0,007 kg) pa prikazujemo do 3 decimale.
String _formatKolicina(double value) {
  var text = value.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text.replaceAll('.', ',');
}

String _formatDatum(DateTime datum) {
  final d = datum.day.toString().padLeft(2, '0');
  final m = datum.month.toString().padLeft(2, '0');
  return '$d.$m.${datum.year}';
}

final _decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

// Demo artikli sa normativima. Kasnije se učitavaju iz baze (Osnovni podaci -> Artikli).
const List<Artikal> _katalogArtikala = [
  Artikal(
    sifra: 'GP-101',
    naziv: 'Krevet 160x200',
    jm: 'kom',
    normativi: [
      Normativ(
        naziv: 'Konstrukcija baze',
        cijena: 45.00,
        kolicina: 1,
        jm: 'kom',
      ),
      Normativ(
        naziv: 'Iverica 8mm jedna strana ofarbana 2,1x2,8',
        cijena: 18.50,
        kolicina: 1,
        jm: 'kom',
      ),
      Normativ(
        naziv: 'Sundjer 14D ELASTO ROOL 32 CMX0,3CM',
        cijena: 1.20,
        kolicina: 4,
        jm: 'm',
      ),
      Normativ(naziv: 'Tkanina', cijena: 5.70, kolicina: 6, jm: 'm'),
      Normativ(naziv: 'Makaze', cijena: 0.80, kolicina: 2, jm: 'kom'),
      Normativ(naziv: 'Amortizeri', cijena: 1.00, kolicina: 2, jm: 'kom'),
      Normativ(naziv: 'Nogare oble', cijena: 2.00, kolicina: 4, jm: 'kom'),
      Normativ(
        naziv: 'Oslonac poklopca',
        cijena: 28.00,
        kolicina: 1,
        jm: 'kom',
      ),
    ],
  ),
  Artikal(
    sifra: 'GP-102',
    naziv: 'Krevet 90x200',
    jm: 'kom',
    normativi: [
      Normativ(
        naziv: 'Konstrukcija baze',
        cijena: 45.00,
        kolicina: 1,
        jm: 'kom',
      ),
      Normativ(
        naziv: 'Sundjer 14D ELASTO ROOL 32 CMX0,3CM',
        cijena: 1.20,
        kolicina: 2,
        jm: 'm',
      ),
      Normativ(naziv: 'Tkanina', cijena: 5.70, kolicina: 3.5, jm: 'm'),
      Normativ(naziv: 'Nogare oble', cijena: 2.00, kolicina: 4, jm: 'kom'),
      Normativ(
        naziv: 'Rucke metalne sa tkaninom',
        cijena: 6.00,
        kolicina: 2,
        jm: 'kom',
      ),
    ],
  ),
  Artikal(
    sifra: 'GP-103',
    naziv: 'Tabure',
    jm: 'kom',
    normativi: [
      Normativ(naziv: 'Tkanina', cijena: 5.70, kolicina: 1.2, jm: 'm'),
      Normativ(naziv: 'Drzac stranice', cijena: 2.00, kolicina: 4, jm: 'kom'),
      Normativ(naziv: 'Nogare oble', cijena: 2.00, kolicina: 4, jm: 'kom'),
    ],
  ),
];

// Jedan red u tabeli artikala radnog naloga.
class _StavkaArtikla {
  final Artikal artikal;
  final TextEditingController kolicina;
  final TextEditingController cijena;

  _StavkaArtikla({required this.artikal, required double kolicina})
    : kolicina = TextEditingController(text: _formatKolicina(kolicina)),
      cijena = TextEditingController(text: _format(artikal.cijenaNormativa));

  void dispose() {
    kolicina.dispose();
    cijena.dispose();
  }
}

// Zbirni red normativa: isti materijal iz više artikala se sabira u jedan red.
class _NormativRed {
  final String kljuc;
  final String naziv;
  final String jm;
  final double cijena;
  double trebovano;

  _NormativRed({
    required this.kljuc,
    required this.naziv,
    required this.jm,
    required this.cijena,
    required this.trebovano,
  });
}

class DodajRadniNalog extends StatefulWidget {
  const DodajRadniNalog({super.key});

  @override
  State<DodajRadniNalog> createState() => _DodajRadniNalogState();
}

class _DodajRadniNalogState extends State<DodajRadniNalog> {
  final datumController = TextEditingController(
    text: _formatDatum(DateTime.now()),
  );
  final redniBrojController = TextEditingController();
  final kupacController = TextEditingController();
  final porudzbinaController = TextEditingController();

  final List<_StavkaArtikla> stavke = [];

  // Izdato po normativu (ključ = naziv|jm). Dok korisnik ne promijeni ručno,
  // izdato prati trebovanu količinu.
  final Map<String, TextEditingController> _izdato = {};
  final Set<String> _izdatoRucno = {};

  @override
  void dispose() {
    datumController.dispose();
    redniBrojController.dispose();
    kupacController.dispose();
    porudzbinaController.dispose();
    for (final stavka in stavke) {
      stavka.dispose();
    }
    for (final controller in _izdato.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<_NormativRed> get _normativi {
    final Map<String, _NormativRed> zbir = {};

    for (final stavka in stavke) {
      final kolicinaArtikla = _parse(stavka.kolicina.text);

      for (final normativ in stavka.artikal.normativi) {
        final kljuc =
            '${normativ.naziv.toLowerCase()}|${normativ.jm.toLowerCase()}';
        final kolicina = normativ.kolicina * kolicinaArtikla;

        final postojeci = zbir[kljuc];
        if (postojeci != null) {
          postojeci.trebovano += kolicina;
        } else {
          zbir[kljuc] = _NormativRed(
            kljuc: kljuc,
            naziv: normativ.naziv,
            jm: normativ.jm,
            cijena: normativ.cijena,
            trebovano: kolicina,
          );
        }
      }
    }

    return zbir.values.toList();
  }

  // Poziva se poslije svake promjene artikala da bi se uskladila polja "Izdato".
  void _osvjeziIzdato() {
    final normativi = _normativi;
    final aktivni = normativi.map((n) => n.kljuc).toSet();

    for (final normativ in normativi) {
      final controller = _izdato.putIfAbsent(
        normativ.kljuc,
        () => TextEditingController(),
      );
      if (!_izdatoRucno.contains(normativ.kljuc)) {
        controller.text = _formatKolicina(normativ.trebovano);
      }
    }

    // Normativi koji više ne postoje (obrisan artikal) se uklanjaju.
    final zaBrisanje = _izdato.keys.where((k) => !aktivni.contains(k)).toList();
    for (final kljuc in zaBrisanje) {
      _izdato.remove(kljuc)!.dispose();
      _izdatoRucno.remove(kljuc);
    }
  }

  Future<void> _izaberiDatum() async {
    final izabran = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (izabran == null) return;

    datumController.text = _formatDatum(izabran);
  }

  Future<void> _dodajArtikal() async {
    final rezultat = await showDialog<(Artikal, double)>(
      context: context,
      builder: (context) => const _DodajArtikalDialog(),
    );
    if (rezultat == null || !mounted) return;

    final (artikal, kolicina) = rezultat;

    setState(() {
      final postojeca = stavke
          .where((s) => s.artikal.sifra == artikal.sifra)
          .firstOrNull;

      // Isti artikal dodat ponovo -> samo se povećava količina.
      if (postojeca != null) {
        final nova = _parse(postojeca.kolicina.text) + kolicina;
        postojeca.kolicina.text = _formatKolicina(nova);
      } else {
        stavke.add(_StavkaArtikla(artikal: artikal, kolicina: kolicina));
      }

      _osvjeziIzdato();
    });
  }

  void _obrisiArtikal(_StavkaArtikla stavka) {
    setState(() {
      stavke.remove(stavka);
      stavka.dispose();
      _osvjeziIzdato();
    });
  }

  DataColumn _kolona(String naslov, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(naslov, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _celijaInput(
    TextEditingController controller, {
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: 100,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlign: TextAlign.right,
        inputFormatters: [_decimalFormatter],
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }

  Widget _sekcija(String naslov, {Widget? akcija}) {
    return Row(
      children: [
        Text(
          naslov,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        ?akcija,
      ],
    );
  }

  Widget _okvir(Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: child,
      ),
    );
  }

  Widget _prazno(String poruka) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(poruka, style: TextStyle(color: Colors.grey.shade600)),
    );
  }

  Widget _buildTabelaArtikala() {
    if (stavke.isEmpty) {
      return _prazno('Nema dodatih artikala. Klikni "Dodaj artikal".');
    }

    return _okvir(
      DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        columnSpacing: 32,
        columns: [
          _kolona('Rb'),
          _kolona('Šifra artikla'),
          _kolona('Naziv artikla'),
          _kolona('Jedinica mjere'),
          _kolona('Količina', numeric: true),
          _kolona('Cijena', numeric: true),
          _kolona(''),
        ],
        rows: List.generate(stavke.length, (index) {
          final stavka = stavke[index];

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(stavka.artikal.sifra)),
              DataCell(Text(stavka.artikal.naziv)),
              DataCell(Text(stavka.artikal.jm)),
              DataCell(
                _celijaInput(
                  stavka.kolicina,
                  onChanged: (_) => setState(_osvjeziIzdato),
                ),
              ),
              DataCell(_celijaInput(stavka.cijena)),
              DataCell(
                IconButton(
                  tooltip: 'Obriši',
                  onPressed: () => _obrisiArtikal(stavka),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTabelaNormativa() {
    final normativi = _normativi;

    if (normativi.isEmpty) {
      return _prazno('Normativi se prikazuju automatski kad dodaš artikal.');
    }

    double ukupno = 0;
    final redovi = <DataRow>[];

    for (var i = 0; i < normativi.length; i++) {
      final normativ = normativi[i];
      final izdato = _izdato[normativ.kljuc]!;
      final vrijednost = _parse(izdato.text) * normativ.cijena;
      ukupno += vrijednost;

      redovi.add(
        DataRow(
          cells: [
            DataCell(Text('${i + 1}')),
            DataCell(Text(normativ.naziv)),
            DataCell(Text(normativ.jm)),
            DataCell(Text(_formatKolicina(normativ.trebovano))),
            DataCell(
              _celijaInput(
                izdato,
                onChanged: (_) {
                  setState(() => _izdatoRucno.add(normativ.kljuc));
                },
              ),
            ),
            DataCell(Text('${_format(normativ.cijena)} €')),
            DataCell(Text('${_format(vrijednost)} €')),
          ],
        ),
      );
    }

    const bold = TextStyle(fontWeight: FontWeight.bold);
    redovi.add(
      DataRow(
        color: WidgetStateProperty.all(Colors.grey.shade100),
        cells: [
          const DataCell(Text('')),
          const DataCell(Text('Ukupno', style: bold)),
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('')),
          DataCell(Text('${_format(ukupno)} €', style: bold)),
        ],
      ),
    );

    return _okvir(
      DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        columnSpacing: 32,
        columns: [
          _kolona('Rb'),
          _kolona('Naziv'),
          _kolona('Jed. mjere'),
          _kolona('Trebovano', numeric: true),
          _kolona('Izdato', numeric: true),
          _kolona('Cijena', numeric: true),
          _kolona('Vrijednost', numeric: true),
        ],
        rows: redovi,
      ),
    );
  }

  Widget _dugme({
    required VoidCallback onPressed,
    required Widget label,
    Widget? icon,
    bool outlined = false,
  }) {
    final style = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      ),
      minimumSize: WidgetStateProperty.all(const Size(0, 56)),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );

    if (outlined) {
      return OutlinedButton(onPressed: onPressed, style: style, child: label);
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: label,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj radni nalog')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Radni nalog',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 30),

                // Red 1: Datum + Redni broj
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _izaberiDatum,
                        child: AbsorbPointer(
                          child: buildInput(
                            controller: datumController,
                            label: 'Datum',
                            width: null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: buildInput(
                        controller: redniBrojController,
                        label: 'Redni broj',
                        width: null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Red 2: Kupac + Porudžbina broj
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: buildInput(
                        controller: kupacController,
                        label: 'Kupac',
                        width: null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: buildInput(
                        controller: porudzbinaController,
                        label: 'Porudžbina broj',
                        width: null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Artikli
                _sekcija(
                  'Artikli',
                  akcija: ElevatedButton.icon(
                    onPressed: _dodajArtikal,
                    icon: const Icon(Icons.add),
                    label: const Text('Dodaj artikal'),
                  ),
                ),
                const SizedBox(height: 12),
                _buildTabelaArtikala(),
                const SizedBox(height: 32),

                // Normativi
                _sekcija('Trebovano materijala iz magacina repromaterijala'),
                const SizedBox(height: 12),
                _buildTabelaNormativa(),
                const SizedBox(height: 32),

                // Dugmad
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _dugme(
                      onPressed: () {},
                      icon: const Icon(Icons.save_outlined, size: 24),
                      label: const Text('Sačuvaj dokument'),
                    ),
                    _dugme(
                      onPressed: () {},
                      icon: const Icon(Icons.print),
                      label: const Text('Štampaj'),
                    ),
                    _dugme(
                      onPressed: () => Get.back(),
                      label: const Text('Odustani'),
                      outlined: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// DIJALOG: izbor artikla i količine
// ======================================================================
class _DodajArtikalDialog extends StatefulWidget {
  const _DodajArtikalDialog();

  @override
  State<_DodajArtikalDialog> createState() => _DodajArtikalDialogState();
}

class _DodajArtikalDialogState extends State<_DodajArtikalDialog> {
  final kolicinaController = TextEditingController(text: '1');
  Artikal? _artikal;

  @override
  void dispose() {
    kolicinaController.dispose();
    super.dispose();
  }

  void _potvrdi() {
    final kolicina = _parse(kolicinaController.text);
    if (_artikal == null || kolicina <= 0) return;

    Navigator.of(context).pop((_artikal!, kolicina));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Dodaj artikal'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Artikal>(
              initialValue: _artikal,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Artikal',
                border: OutlineInputBorder(),
              ),
              items: _katalogArtikala.map((artikal) {
                return DropdownMenuItem(
                  value: artikal,
                  child: Text('${artikal.sifra} — ${artikal.naziv}'),
                );
              }).toList(),
              onChanged: (artikal) => setState(() => _artikal = artikal),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: kolicinaController,
              inputFormatters: [_decimalFormatter],
              onSubmitted: (_) => _potvrdi(),
              decoration: InputDecoration(
                labelText: 'Količina',
                suffixText: _artikal?.jm,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Odustani'),
        ),
        ElevatedButton(
          onPressed: _artikal == null ? null : _potvrdi,
          child: const Text('Dodaj'),
        ),
      ],
    );
  }
}
