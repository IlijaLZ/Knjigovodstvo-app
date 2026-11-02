import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const List<String> _jediniceMjere = ['kg', 'g', 'l', 'ml', 'kom', 'm', 'pak'];

double _parse(String text) {
  return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
}

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

InputDecoration _decoration(String label, {String? suffixText}) {
  return InputDecoration(
    labelText: label,
    suffixText: suffixText,
    filled: true,
    fillColor: Colors.grey.shade50,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.blue, width: 2),
    ),
  );
}

// Jedan red normativa: koliko čega (sirovine) ulazi u artikal.
class Normativ {
  final String naziv;
  final double cijena;
  final double kolicina;
  final String jm;

  const Normativ({
    required this.naziv,
    required this.cijena,
    required this.kolicina,
    required this.jm,
  });

  double get iznos => cijena * kolicina;
}

class Artikal {
  final String sifra;
  final String naziv;
  final String jm;
  final List<Normativ> normativi;

  const Artikal({
    required this.sifra,
    required this.naziv,
    required this.jm,
    required this.normativi,
  });

  double get cijenaNormativa =>
      normativi.fold<double>(0, (suma, n) => suma + n.iznos);
}

class ArtikliScreen extends StatefulWidget {
  const ArtikliScreen({super.key});

  @override
  State<ArtikliScreen> createState() => _ArtikliScreenState();
}

class _ArtikliScreenState extends State<ArtikliScreen> {
  final searchController = TextEditingController();

  // Demo artikli
  final List<Artikal> artikli = [
    const Artikal(
      sifra: 'GP-001',
      naziv: 'Hljeb bijeli 500g',
      jm: 'kom',
      normativi: [
        Normativ(naziv: 'Brašno tip 500', cijena: 0.90, kolicina: 0.35, jm: 'kg'),
        Normativ(naziv: 'Kvasac svježi', cijena: 4.50, kolicina: 0.01, jm: 'kg'),
        Normativ(naziv: 'So', cijena: 0.53, kolicina: 0.007, jm: 'kg'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();

    searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _dodajNoviArtikal() async {
    final noviArtikal = await showDialog<Artikal>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _DodajArtikalDialog(),
    );

    if (noviArtikal == null || !mounted) return;

    setState(() {
      artikli.add(noviArtikal);
    });
  }

  void _prikaziNormative(Artikal artikal) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Normativi: ${artikal.naziv}'),
          content: _NormativiTabela(normativi: artikal.normativi),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zatvori'),
            ),
          ],
        );
      },
    );
  }

  void _obrisiArtikal(Artikal artikal) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Obriši artikal'),
          content: Text(
            'Da li ste sigurni da želite obrisati ${artikal.naziv}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Odustani'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  artikli.remove(artikal);
                });
                Navigator.pop(context);
              },
              child: const Text('Obriši'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchText = searchController.text.toLowerCase();

    final filtriraniArtikli = artikli.where((artikal) {
      return artikal.sifra.toLowerCase().contains(searchText) ||
          artikal.naziv.toLowerCase().contains(searchText);
    }).toList();

    const boldText = TextStyle(fontWeight: FontWeight.bold);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Artikli',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 24),

          // --------------------------------------------------
          // PRETRAGA + DUGME "DODAJ NOVI ARTIKAL" + TABELA
          // --------------------------------------------------
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        width: 350,
                        child: TextField(
                          controller: searchController,
                          decoration: _decoration('Pretraži artikle...')
                              .copyWith(
                                labelText: null,
                                hintText: 'Pretraži artikle...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: searchController.text.isNotEmpty
                                    ? IconButton(
                                        onPressed: searchController.clear,
                                        icon: const Icon(Icons.clear),
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      ElevatedButton.icon(
                        onPressed: _dodajNoviArtikal,
                        icon: const Icon(Icons.add),
                        label: const Text('Dodaj novi artikal'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Colors.grey.shade100,
                        ),
                        dataRowMinHeight: 55,
                        dataRowMaxHeight: 65,
                        columnSpacing: 35,
                        columns: const [
                          DataColumn(label: Text('Šifra', style: boldText)),
                          DataColumn(
                            label: Text('Naziv artikla', style: boldText),
                          ),
                          DataColumn(
                            label: Text('Jedinica mjere', style: boldText),
                          ),
                          DataColumn(
                            label: Text('Br. normativa', style: boldText),
                          ),
                          DataColumn(
                            label: Text('Cijena po normativu', style: boldText),
                          ),
                          DataColumn(label: Text('Akcije', style: boldText)),
                        ],
                        rows: filtriraniArtikli.map((artikal) {
                          return DataRow(
                            cells: [
                              DataCell(Text(artikal.sifra)),
                              DataCell(Text(artikal.naziv)),
                              DataCell(Text(artikal.jm)),
                              DataCell(Text('${artikal.normativi.length}')),
                              DataCell(
                                Text(
                                  '${_format(artikal.cijenaNormativa)} €',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'Normativi',
                                      onPressed: () =>
                                          _prikaziNormative(artikal),
                                      icon: const Icon(Icons.list_alt),
                                    ),
                                    IconButton(
                                      tooltip: 'Obriši',
                                      onPressed: () => _obrisiArtikal(artikal),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// TABELA NORMATIVA (prikaz u dijalogu)
// Ako je onObrisi != null, svaki red ima dugme za brisanje.
// ======================================================================
class _NormativiTabela extends StatelessWidget {
  final List<Normativ> normativi;
  final ValueChanged<Normativ>? onObrisi;

  const _NormativiTabela({required this.normativi, this.onObrisi});

  @override
  Widget build(BuildContext context) {
    const boldText = TextStyle(fontWeight: FontWeight.bold);
    final ukupno = normativi.fold<double>(0, (suma, n) => suma + n.iznos);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        columnSpacing: 24,
        columns: [
          const DataColumn(label: Text('Naziv', style: boldText)),
          const DataColumn(label: Text('Cijena', style: boldText)),
          const DataColumn(label: Text('Količina', style: boldText)),
          const DataColumn(label: Text('JM', style: boldText)),
          const DataColumn(label: Text('Iznos', style: boldText)),
          if (onObrisi != null) const DataColumn(label: Text('')),
        ],
        rows: [
          ...normativi.map((n) {
            return DataRow(
              cells: [
                DataCell(Text(n.naziv)),
                DataCell(Text('${_format(n.cijena)} €')),
                DataCell(Text(n.kolicina.toString().replaceAll('.', ','))),
                DataCell(Text(n.jm)),
                DataCell(Text('${_format(n.iznos)} €')),
                if (onObrisi != null)
                  DataCell(
                    IconButton(
                      tooltip: 'Ukloni normativ',
                      onPressed: () => onObrisi!(n),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            );
          }),
          DataRow(
            cells: [
              const DataCell(Text('Ukupno', style: boldText)),
              const DataCell(Text('')),
              const DataCell(Text('')),
              const DataCell(Text('')),
              DataCell(Text('${_format(ukupno)} €', style: boldText)),
              if (onObrisi != null) const DataCell(Text('')),
            ],
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// POP UP: DODAJ NOVI ARTIKAL
// Artikal se može sačuvati samo ako ima bar jedan normativ.
// Vraća Artikal ili null ako korisnik odustane.
// ======================================================================
class _DodajArtikalDialog extends StatefulWidget {
  const _DodajArtikalDialog();

  @override
  State<_DodajArtikalDialog> createState() => _DodajArtikalDialogState();
}

class _DodajArtikalDialogState extends State<_DodajArtikalDialog> {
  final _artikalFormKey = GlobalKey<FormState>();
  final _normativFormKey = GlobalKey<FormState>();

  final sifraController = TextEditingController();
  final nazivController = TextEditingController();
  String _jm = 'kom';

  // Polja za unos jednog normativa
  final normativNazivController = TextEditingController();
  final normativCijenaController = TextEditingController();
  final normativKolicinaController = TextEditingController();
  String _normativJm = 'kg';

  final List<Normativ> _normativi = [];
  bool _prikaziGreskuNormativa = false;

  @override
  void dispose() {
    sifraController.dispose();
    nazivController.dispose();
    normativNazivController.dispose();
    normativCijenaController.dispose();
    normativKolicinaController.dispose();
    super.dispose();
  }

  String? _obavezno(String? value) {
    if (value == null || value.trim().isEmpty) return 'Obavezno polje';
    return null;
  }

  String? _obaveznBroj(String? value) {
    if (value == null || value.trim().isEmpty) return 'Obavezno polje';
    final broj = double.tryParse(value.trim().replaceAll(',', '.'));
    if (broj == null) return 'Unesite ispravan broj';
    if (broj <= 0) return 'Mora biti veće od 0';
    return null;
  }

  void _dodajNormativ() {
    if (!_normativFormKey.currentState!.validate()) return;

    setState(() {
      _normativi.add(
        Normativ(
          naziv: normativNazivController.text.trim(),
          cijena: _parse(normativCijenaController.text),
          kolicina: _parse(normativKolicinaController.text),
          jm: _normativJm,
        ),
      );
      _prikaziGreskuNormativa = false;
    });

    normativNazivController.clear();
    normativCijenaController.clear();
    normativKolicinaController.clear();
  }

  void _sacuvaj() {
    final artikalOk = _artikalFormKey.currentState!.validate();

    setState(() {
      _prikaziGreskuNormativa = _normativi.isEmpty;
    });

    if (!artikalOk || _normativi.isEmpty) return;

    Navigator.pop(
      context,
      Artikal(
        sifra: sifraController.text.trim(),
        naziv: nazivController.text.trim(),
        jm: _jm,
        normativi: List.unmodifiable(_normativi),
      ),
    );
  }

  Widget _jmDropdown(String value, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _decoration('Jedinica mjere'),
      items: _jediniceMjere
          .map((jm) => DropdownMenuItem(value: jm, child: Text(jm)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const polje = 200.0;

    final decimalFormatter = FilteringTextInputFormatter.allow(
      RegExp(r'[0-9,.]'),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dodaj novi artikal',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --------------------------------------------------
                      // PODACI O ARTIKLU
                      // --------------------------------------------------
                      Form(
                        key: _artikalFormKey,
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            SizedBox(
                              width: polje,
                              child: TextFormField(
                                controller: sifraController,
                                decoration: _decoration('Šifra'),
                                validator: _obavezno,
                              ),
                            ),
                            SizedBox(
                              width: polje * 2 + 16,
                              child: TextFormField(
                                controller: nazivController,
                                decoration: _decoration('Naziv artikla'),
                                validator: _obavezno,
                              ),
                            ),
                            SizedBox(
                              width: polje,
                              child: _jmDropdown(
                                _jm,
                                (v) => setState(() => _jm = v),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // --------------------------------------------------
                      // NORMATIVI
                      // --------------------------------------------------
                      const Text(
                        'Normativi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Artikal mora imati bar jedan normativ.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),

                      const SizedBox(height: 16),

                      Form(
                        key: _normativFormKey,
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: polje,
                              child: TextFormField(
                                controller: normativNazivController,
                                decoration: _decoration('Naziv'),
                                validator: _obavezno,
                              ),
                            ),
                            SizedBox(
                              width: polje * 0.75,
                              child: TextFormField(
                                controller: normativCijenaController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [decimalFormatter],
                                decoration: _decoration(
                                  'Cijena',
                                  suffixText: '€',
                                ),
                                validator: _obaveznBroj,
                              ),
                            ),
                            SizedBox(
                              width: polje * 0.75,
                              child: TextFormField(
                                controller: normativKolicinaController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [decimalFormatter],
                                decoration: _decoration('Količina'),
                                validator: _obaveznBroj,
                                onFieldSubmitted: (_) => _dodajNormativ(),
                              ),
                            ),
                            SizedBox(
                              width: polje * 0.75,
                              child: _jmDropdown(
                                _normativJm,
                                (v) => setState(() => _normativJm = v),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _dodajNormativ,
                              icon: const Icon(Icons.add),
                              label: const Text('Dodaj normativ'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_normativi.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: _NormativiTabela(
                              normativi: _normativi,
                              onObrisi: (n) =>
                                  setState(() => _normativi.remove(n)),
                            ),
                          ),
                        ),

                      if (_prikaziGreskuNormativa)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Dodajte bar jedan normativ prije čuvanja artikla.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // DUGMAD
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    child: const Text('Odustani'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _sacuvaj,
                    icon: const Icon(Icons.check),
                    label: const Text('Dodaj artikal'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
