import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DodajKalkulacijuScreen extends StatefulWidget {
  const DodajKalkulacijuScreen({super.key});

  @override
  State<DodajKalkulacijuScreen> createState() => _DodajKalkulacijuScreenState();
}

class _DodajKalkulacijuScreenState extends State<DodajKalkulacijuScreen> {
  final rbController = TextEditingController();
  final datumController = TextEditingController();
  final dobavljacController = TextEditingController();
  final rcBrController = TextEditingController();
  final prijemnicaBrController = TextEditingController();
  final kalkulisaoController = TextEditingController();
  final robuPrimioController = TextEditingController();
  final prevozController = TextEditingController();
  final spedicionController = TextEditingController();
  final svegaController = TextEditingController();
  final fvController = TextEditingController();
  final ztnController = TextEditingController();

  final searchController = TextEditingController();

  // Objekti (dropdown)
  static const List<String> _objekti = [
    'Magacin repromaterijala',
    'Proizvodnja u toku',
    'Magacin gotovih proizvoda',
  ];

  String? _objekat;
  // Demo artikli
  final List<Map<String, String>> artikli = [
    {
      'artikla': '1',
      'sifra': 'ART-001',
      'naziv': 'Brašno tip 500',
      'dokument': 'PR-001',
      'jm': 'kg',
      'kolicina': '50',
      'fakturna': '0,85 €',
      'zavisni': '0,05 €',
      'nabavna': '0,90 €',
    },
    {
      'artikla': '2',
      'sifra': 'ART-002',
      'naziv': 'Šećer',
      'dokument': 'PR-001',
      'jm': 'kg',
      'kolicina': '30',
      'fakturna': '1,10 €',
      'zavisni': '0,07 €',
      'nabavna': '1,17 €',
    },
    {
      'artikla': '3',
      'sifra': 'ART-003',
      'naziv': 'Ulje suncokretovo',
      'dokument': 'PR-001',
      'jm': 'l',
      'kolicina': '20',
      'fakturna': '1,45 €',
      'zavisni': '0,10 €',
      'nabavna': '1,55 €',
    },
    {
      'artikla': '4',
      'sifra': 'ART-004',
      'naziv': 'So',
      'dokument': 'PR-001',
      'jm': 'kg',
      'kolicina': '15',
      'fakturna': '0,50 €',
      'zavisni': '0,03 €',
      'nabavna': '0,53 €',
    },
  ];

  @override
  void initState() {
    super.initState();

    searchController.addListener(() {
      setState(() {});
    });

    // Odmah prikaži početne vrijednosti (0,00)
    _izracunajRekapitulaciju();
  }

  @override
  void dispose() {
    rbController.dispose();
    datumController.dispose();
    dobavljacController.dispose();
    rcBrController.dispose();
    prijemnicaBrController.dispose();
    kalkulisaoController.dispose();
    robuPrimioController.dispose();
    searchController.dispose();
    prevozController.dispose();
    spedicionController.dispose();
    svegaController.dispose();
    fvController.dispose();
    ztnController.dispose();

    super.dispose();
  }

  // Ako je width == null, input se rasteže (koristi se unutar Expanded).
  // readOnly = true -> polje samo za prikaz (sivo, bez fokusa).
  Widget _buildInput({
    required String label,
    required TextEditingController controller,
    double? width = 320,
    bool readOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    final field = TextField(
      controller: controller,
      readOnly: readOnly,
      onChanged: onChanged,
      style: readOnly ? const TextStyle(fontWeight: FontWeight.w600) : null,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: readOnly ? Colors.grey.shade200 : Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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
          borderSide: readOnly
              ? BorderSide(color: Colors.grey.shade300)
              : const BorderSide(color: Colors.blue, width: 2),
        ),
      ),
    );

    if (width == null) return field;

    return SizedBox(width: width, child: field);
  }

  void _obrisiArtikal(Map<String, String> artikal) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Obriši artikal'),
          content: Text(
            'Da li ste sigurni da želite obrisati '
            '${artikal['naziv']}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
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

  double _parseNumber(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  String _formatNumber(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  // Svega = Prevoz + Špedicija
  // ZTN   = Svega / FV
  void _izracunajRekapitulaciju() {
    final prevoz = _parseNumber(prevozController.text);
    final spedicija = _parseNumber(spedicionController.text);
    final fv = _parseNumber(fvController.text);

    final svega = prevoz + spedicija;
    svegaController.text = _formatNumber(svega);
    if (fv > 0) {
      final ztn = (svega / fv) * 100;
      ztnController.text = '${_formatNumber(ztn)}%';
    } else {
      ztnController.text = '${_formatNumber(0)}%';
    }
  }

  // ZTN kao koeficijent (Svega / FV). Koristi se za zavisni trošak artikla.
  double _ztnKoeficijent() {
    final svega =
        _parseNumber(prevozController.text) +
        _parseNumber(spedicionController.text);
    final fv = _parseNumber(fvController.text);

    return fv > 0 ? svega / fv : 0;
  }

  Future<void> _dodajNoviArtikal() async {
    // Sljedeći redni broj = najveći postojeći + 1
    final sljedeciRb =
        artikli
            .map((a) => int.tryParse(a['artikla'] ?? '') ?? 0)
            .fold<int>(0, (max, e) => e > max ? e : max) +
        1;

    final noviArtikal = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return _DodajArtikalDialog(
          redniBroj: sljedeciRb.toString(),
          dokument: prijemnicaBrController.text,
          ztn: _ztnKoeficijent(),
        );
      },
    );

    if (noviArtikal == null || !mounted) return;

    setState(() {
      artikli.add(noviArtikal);
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchText = searchController.text.toLowerCase();

    final filtriraniArtikli = artikli.where((artikal) {
      return artikal['sifra']!.toLowerCase().contains(searchText) ||
          artikal['naziv']!.toLowerCase().contains(searchText) ||
          artikal['dokument']!.toLowerCase().contains(searchText);
    }).toList();

    // Stil za veća dugmad (Sačuvaj dokument / Odustani)
    const bigButtonPadding = EdgeInsets.symmetric(horizontal: 28, vertical: 20);
    const bigButtonMinSize = Size(0, 56);
    const bigButtonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dodaj novu kalkulaciju nabavnih cijena'),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // --------------------------------------------------
            // NASLOV
            // --------------------------------------------------
            const Text(
              'Dodaj novu kalkulaciju nabavnih cijena',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 24),

            // --------------------------------------------------
            // OSNOVNI PODACI + DUGMAD (sve u istom redu)
            // --------------------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _buildInput(
                    label: 'RB',
                    controller: rbController,
                    width: null,
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: _buildInput(
                    label: 'Datum',
                    controller: datumController,
                    width: null,
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: _buildInput(
                    label: 'Dobavljač',
                    controller: dobavljacController,
                    width: null,
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: _buildInput(
                    label: 'RC.BR',
                    controller: rcBrController,
                    width: null,
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: _buildInput(
                    label: 'Prijemnica br',
                    controller: prijemnicaBrController,
                    width: null,
                  ),
                ),
                const SizedBox(width: 16),

                // Objekti (dropdown)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _objekat,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Objekti',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
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
                        borderSide: const BorderSide(
                          color: Colors.blue,
                          width: 2,
                        ),
                      ),
                    ),
                    items: _objekti
                        .map(
                          (objekat) => DropdownMenuItem(
                            value: objekat,
                            child: Text(
                              objekat,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _objekat = value;
                      });
                    },
                  ),
                ),

                const SizedBox(width: 24),

                // Sačuvaj
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.save_outlined, size: 24),
                  label: const Text('Sačuvaj dokument'),
                  style: ElevatedButton.styleFrom(
                    padding: bigButtonPadding,
                    minimumSize: bigButtonMinSize,
                    textStyle: bigButtonText,
                  ),
                ),
                SizedBox(width: 12),

                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.print),
                  label: const Text('Štampaj'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                ),

                const SizedBox(width: 12),

                // Odustani
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: bigButtonPadding,
                    minimumSize: bigButtonMinSize,
                    textStyle: bigButtonText,
                  ),
                  child: const Text('Odustani'),
                ),
              ],
            ),

            const SizedBox(height: 35),

            // --------------------------------------------------
            // ARTIKLI
            // --------------------------------------------------
            const Text(
              'Artikli',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            // --------------------------------------------------
            // PRETRAGA + DUGME "DODAJ NOVI ARTIKAL" + TABELA
            // IntrinsicWidth: red sa pretragom i dugmetom se rasteže
            // tačno na širinu tabele (space-between), pa je dugme
            // iznad kolone "Akcije".
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
                        // Pretraga
                        SizedBox(
                          width: 350,
                          child: TextField(
                            controller: searchController,
                            decoration: InputDecoration(
                              hintText: 'Pretraži artikle...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: searchController.text.isNotEmpty
                                  ? IconButton(
                                      onPressed: () {
                                        searchController.clear();
                                      },
                                      icon: const Icon(Icons.clear),
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Dodaj novi artikal
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
                            DataColumn(
                              label: Text(
                                'Artikla',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Šifra',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Naziv artikla',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Dokument',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Jedinica mjere',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Količina',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Fakturna cijena',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Zavisni trošak nabavke',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Nabavna cijena',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),

                            DataColumn(
                              label: Text(
                                'Akcije',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],

                          rows: filtriraniArtikli.map((artikal) {
                            return DataRow(
                              cells: [
                                DataCell(Text(artikal['artikla']!)),

                                DataCell(Text(artikal['sifra']!)),

                                DataCell(Text(artikal['naziv']!)),

                                DataCell(Text(artikal['dokument']!)),

                                DataCell(Text(artikal['jm']!)),

                                DataCell(Text(artikal['kolicina']!)),

                                DataCell(Text(artikal['fakturna']!)),

                                DataCell(Text(artikal['zavisni']!)),

                                DataCell(
                                  Text(
                                    artikal['nabavna']!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                                // AKCIJE
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(
                                        tooltip: 'Izmijeni',
                                        onPressed: () {
                                          // Kasnije otvaramo formu za izmjenu
                                        },
                                        icon: const Icon(Icons.edit_outlined),
                                      ),

                                      IconButton(
                                        tooltip: 'Obriši',
                                        onPressed: () {
                                          _obrisiArtikal(artikal);
                                        },
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

            const SizedBox(height: 32),

            // --------------------------------------------------
            // REKAPITULACIJA
            // --------------------------------------------------
            const Text(
              'Rekapitulacija',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prevoz
                  _buildInput(
                    label: 'Prevoz',
                    controller: prevozController,
                    onChanged: (_) => _izracunajRekapitulaciju(),
                  ),

                  const SizedBox(height: 12),

                  // Špedicija
                  _buildInput(
                    label: 'Špedicija',
                    controller: spedicionController,
                    onChanged: (_) => _izracunajRekapitulaciju(),
                  ),

                  const SizedBox(height: 12),

                  // Svega = Prevoz + Špedicija (samo prikaz)
                  _buildInput(
                    label: 'Svega (Prevoz + Špedicija)',
                    controller: svegaController,
                    readOnly: true,
                  ),

                  const SizedBox(height: 12),

                  // FV
                  _buildInput(
                    label: 'FV',
                    controller: fvController,
                    onChanged: (_) => _izracunajRekapitulaciju(),
                  ),

                  const SizedBox(height: 12),

                  // ZTN = Svega / FV (samo prikaz)
                  _buildInput(
                    label: 'ZTN (Svega / FV)',
                    controller: ztnController,
                    readOnly: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // --------------------------------------------------
            // KALKULISAO + ROBU PRIMIO
            // --------------------------------------------------
            Wrap(
              spacing: 20,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildInput(
                  label: 'Kalkulisao',
                  controller: kalkulisaoController,
                ),

                _buildInput(
                  label: 'Robu primio',
                  controller: robuPrimioController,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// POP UP: DODAJ NOVI ARTIKAL
// Vraća Map<String, String> (isti format kao artikli u tabeli)
// ili null ako korisnik odustane.
// ======================================================================
class _DodajArtikalDialog extends StatefulWidget {
  final String redniBroj;
  final String dokument;
  final double ztn; // koeficijent: Svega / FV

  const _DodajArtikalDialog({
    required this.redniBroj,
    required this.dokument,
    required this.ztn,
  });

  @override
  State<_DodajArtikalDialog> createState() => _DodajArtikalDialogState();
}

class _DodajArtikalDialogState extends State<_DodajArtikalDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController rbController;
  final sifraController = TextEditingController();
  final nazivController = TextEditingController();
  late final TextEditingController dokumentController;
  final kolicinaController = TextEditingController();
  final fakturnaController = TextEditingController();
  final zavisniController = TextEditingController(text: '0,00');
  final nabavnaController = TextEditingController(text: '0,00');

  static const List<String> _jediniceMjere = [
    'kg',
    'g',
    'l',
    'ml',
    'kom',
    'm',
    'pak',
  ];

  String _jm = 'kg';

  @override
  void initState() {
    super.initState();

    rbController = TextEditingController(text: widget.redniBroj);
    dokumentController = TextEditingController(text: widget.dokument);
    fakturnaController.addListener(_izracunajNabavnu);
    kolicinaController.addListener(_izracunajNabavnu);
  }

  @override
  void dispose() {
    rbController.dispose();
    sifraController.dispose();
    nazivController.dispose();
    dokumentController.dispose();
    kolicinaController.dispose();
    fakturnaController.dispose();
    zavisniController.dispose();
    nabavnaController.dispose();

    super.dispose();
  }

  double _parse(String text) {
    return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
  }

  String _format(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  // Zavisni trošak = Fakturna cijena * ZTN
  double _zavisniTrosak() {
    return _parse(fakturnaController.text) * widget.ztn;
  }

  // Nabavna cijena = Količina * (Fakturna cijena + Zavisni trošak)
  double _nabavnaCijena() {
    return _parse(kolicinaController.text) *
        (_parse(fakturnaController.text) + _zavisniTrosak());
  }

  void _izracunajNabavnu() {
    zavisniController.text = _format(_zavisniTrosak());
    nabavnaController.text = _format(_nabavnaCijena());
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

  String? _obavezno(String? value) {
    if (value == null || value.trim().isEmpty) return 'Obavezno polje';
    return null;
  }

  String? _obaveznBroj(String? value) {
    if (value == null || value.trim().isEmpty) return 'Obavezno polje';
    if (double.tryParse(value.trim().replaceAll(',', '.')) == null) {
      return 'Unesite ispravan broj';
    }
    return null;
  }

  void _sacuvaj() {
    if (!_formKey.currentState!.validate()) return;

    final fakturna = _parse(fakturnaController.text);
    final zavisni = _zavisniTrosak();
    final nabavna = _nabavnaCijena();

    Navigator.pop(context, {
      'artikla': rbController.text.trim(),
      'sifra': sifraController.text.trim(),
      'naziv': nazivController.text.trim(),
      'dokument': dokumentController.text.trim(),
      'jm': _jm,
      'kolicina': kolicinaController.text.trim(),
      'fakturna': '${_format(fakturna)} €',
      'zavisni': '${_format(zavisni)} €',
      'nabavna': '${_format(nabavna)} €',
    });
  }

  @override
  Widget build(BuildContext context) {
    const polje = 260.0; // širina jednog polja
    const punaSirina = polje * 2 + 16; // dva polja + razmak

    final decimalFormatter = FilteringTextInputFormatter.allow(
      RegExp(r'[0-9,.]'),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // NASLOV
              const Text(
                'Dodaj novi artikal',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              // FORMA
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        // Artikla (redni broj) - predloženo, ali se može mijenjati
                        SizedBox(
                          width: polje,
                          child: TextFormField(
                            controller: rbController,
                            decoration: _decoration('Artikla'),
                            validator: _obavezno,
                          ),
                        ),

                        // Šifra
                        SizedBox(
                          width: polje,
                          child: TextFormField(
                            controller: sifraController,
                            decoration: _decoration('Šifra'),
                            validator: _obavezno,
                          ),
                        ),

                        // Naziv artikla
                        SizedBox(
                          width: punaSirina,
                          child: TextFormField(
                            controller: nazivController,
                            decoration: _decoration('Naziv artikla'),
                            validator: _obavezno,
                          ),
                        ),

                        // Dokument
                        SizedBox(
                          width: polje,
                          child: TextFormField(
                            controller: dokumentController,
                            decoration: _decoration('Dokument'),
                          ),
                        ),

                        // Jedinica mjere
                        SizedBox(
                          width: polje,
                          child: DropdownButtonFormField<String>(
                            value: _jm,
                            decoration: _decoration('Jedinica mjere'),
                            items: _jediniceMjere
                                .map(
                                  (jm) => DropdownMenuItem(
                                    value: jm,
                                    child: Text(jm),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _jm = value;
                                });
                              }
                            },
                          ),
                        ),

                        // Količina
                        SizedBox(
                          width: polje,
                          child: TextFormField(
                            controller: kolicinaController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [decimalFormatter],
                            decoration: _decoration('Količina'),
                            validator: _obaveznBroj,
                          ),
                        ),

                        // Fakturna cijena
                        SizedBox(
                          width: polje,
                          child: TextFormField(
                            controller: fakturnaController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [decimalFormatter],
                            decoration: _decoration(
                              'Fakturna cijena',
                              suffixText: '€',
                            ),
                            validator: _obaveznBroj,
                          ),
                        ),

                        // Zavisni trošak nabavke = Fakturna cijena * ZTN (automatski)
                        SizedBox(
                          width: polje,
                          child: TextFormField(
                            controller: zavisniController,
                            readOnly: true,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            decoration: _decoration(
                              'Zavisni trošak nabavke',
                              suffixText: '€',
                            ),
                          ),
                        ),

                        // Nabavna cijena - računa se automatski
                        SizedBox(
                          width: polje,
                          child: TextFormField(
                            controller: nabavnaController,
                            readOnly: true,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            decoration: _decoration(
                              'Nabavna cijena',
                              suffixText: '€',
                            ),
                          ),
                        ),
                      ],
                    ),
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
                  SizedBox(width: 12),

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
