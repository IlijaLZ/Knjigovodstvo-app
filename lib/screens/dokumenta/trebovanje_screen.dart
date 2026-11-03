import 'package:flutter/material.dart';
import 'package:knjigovodstvo_app/models/article.dart';

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

// Količine normativa znaju biti male (0,007 kg) pa prikazujemo do 3 decimale.
String _formatKolicina(double value) {
  var text = value.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text.replaceAll('.', ',');
}

// Demo artikli sa normativima. Kasnije se učitavaju iz baze (Osnovni podaci -> Artikli).
const _krevet160 = Artikal(
  sifra: 'GP-101',
  naziv: 'Krevet 160x200',
  jm: 'kom',
  normativi: [
    Normativ(naziv: 'Konstrukcija baze', cijena: 45.00, kolicina: 1, jm: 'kom'),
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
    Normativ(naziv: 'Oslonac poklopca', cijena: 28.00, kolicina: 1, jm: 'kom'),
  ],
);

const _krevet90 = Artikal(
  sifra: 'GP-102',
  naziv: 'Krevet 90x200',
  jm: 'kom',
  normativi: [
    Normativ(naziv: 'Konstrukcija baze', cijena: 45.00, kolicina: 1, jm: 'kom'),
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
);

const _tabure = Artikal(
  sifra: 'GP-103',
  naziv: 'Tabure',
  jm: 'kom',
  normativi: [
    Normativ(naziv: 'Tkanina', cijena: 5.70, kolicina: 1.2, jm: 'm'),
    Normativ(naziv: 'Drzac stranice', cijena: 2.00, kolicina: 4, jm: 'kom'),
    Normativ(naziv: 'Nogare oble', cijena: 2.00, kolicina: 4, jm: 'kom'),
  ],
);

// Jedan artikal na trebovanju i koliko komada se proizvodi.
class _StavkaArtikla {
  final Artikal artikal;
  final double kolicina;

  const _StavkaArtikla(this.artikal, this.kolicina);
}

// Zbirni red normativa: isti materijal iz više artikala se sabira u jedan red.
class _NormativRed {
  final String naziv;
  final String jm;
  final double cijena;
  double trebovano;
  double izdato = 0;

  _NormativRed({
    required this.naziv,
    required this.jm,
    required this.cijena,
    required this.trebovano,
  });

  double get vrijednost => izdato * cijena;
}

class _Trebovanje {
  final String broj;
  final String datum;
  final String radniNalog;
  final String magacin;
  final String primalac;
  final List<_StavkaArtikla> artikli;

  // Izdato po normativu (ključ = naziv|jm) kad se razlikuje od trebovanog.
  final Map<String, double> izdatoRucno;

  const _Trebovanje({
    required this.broj,
    required this.datum,
    required this.radniNalog,
    required this.magacin,
    required this.primalac,
    required this.artikli,
    this.izdatoRucno = const {},
  });

  List<_NormativRed> get normativi {
    final Map<String, _NormativRed> zbir = {};

    for (final stavka in artikli) {
      for (final normativ in stavka.artikal.normativi) {
        final kljuc =
            '${normativ.naziv.toLowerCase()}|${normativ.jm.toLowerCase()}';
        final kolicina = normativ.kolicina * stavka.kolicina;

        final postojeci = zbir[kljuc];
        if (postojeci != null) {
          postojeci.trebovano += kolicina;
        } else {
          zbir[kljuc] = _NormativRed(
            naziv: normativ.naziv,
            jm: normativ.jm,
            cijena: normativ.cijena,
            trebovano: kolicina,
          );
        }
      }
    }

    for (final entry in zbir.entries) {
      entry.value.izdato = izdatoRucno[entry.key] ?? entry.value.trebovano;
    }

    return zbir.values.toList();
  }

  double get vrijednost =>
      normativi.fold<double>(0, (suma, n) => suma + n.vrijednost);

  String get nazivArtikala => artikli.map((s) => s.artikal.naziv).join(', ');
}

class TrebovanjeScreen extends StatefulWidget {
  const TrebovanjeScreen({super.key});

  @override
  State<TrebovanjeScreen> createState() => _TrebovanjeScreenState();
}

class _TrebovanjeScreenState extends State<TrebovanjeScreen> {
  int currentPage = 1;

  final int totalPages = 3;

  final List<_Trebovanje> trebovanja = const [
    _Trebovanje(
      broj: 'TR-001',
      datum: '23.09.2026',
      radniNalog: 'RN-001',
      magacin: 'Magacin repromaterijala',
      primalac: 'Proizvodnja',
      artikli: [_StavkaArtikla(_krevet160, 1), _StavkaArtikla(_tabure, 2)],
    ),
    _Trebovanje(
      broj: 'TR-002',
      datum: '22.09.2026',
      radniNalog: 'RN-002',
      magacin: 'Magacin repromaterijala',
      primalac: 'Proizvodnja',
      artikli: [_StavkaArtikla(_krevet90, 2)],
      izdatoRucno: {'tkanina|m': 7.5},
    ),
    _Trebovanje(
      broj: 'TR-003',
      datum: '20.09.2026',
      radniNalog: 'RN-003',
      magacin: 'Magacin repromaterijala',
      primalac: 'Proizvodnja',
      artikli: [_StavkaArtikla(_tabure, 4)],
    ),
    _Trebovanje(
      broj: 'TR-004',
      datum: '18.09.2026',
      radniNalog: 'RN-004',
      magacin: 'Magacin repromaterijala',
      primalac: 'Proizvodnja',
      artikli: [_StavkaArtikla(_krevet160, 2)],
      izdatoRucno: {'nogare oble|kom': 7},
    ),
    _Trebovanje(
      broj: 'TR-005',
      datum: '15.09.2026',
      radniNalog: 'RN-005',
      magacin: 'Magacin repromaterijala',
      primalac: 'Proizvodnja',
      artikli: [_StavkaArtikla(_krevet90, 1), _StavkaArtikla(_tabure, 1)],
    ),
  ];

  DataColumn _kolona(String naslov, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(naslov, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _prikaziTrebovanje(_Trebovanje trebovanje) {
    showDialog(
      context: context,
      builder: (context) => _TrebovanjeDialog(trebovanje: trebovanje),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------
            // NASLOV
            // ------------------------------------------------
            const Text(
              'Trebovanje',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 24),

            // ------------------------------------------------
            // TABELA
            // ------------------------------------------------
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Colors.grey.shade100,
                      ),
                      columnSpacing: 40,
                      showCheckboxColumn: false,

                      columns: [
                        _kolona('RB'),
                        _kolona('Broj trebovanja'),
                        _kolona('Datum'),
                        _kolona('Radni nalog'),
                        _kolona('Izdaje'),
                        _kolona('Prima'),
                        _kolona('Artikli'),
                        _kolona('Vrijednost', numeric: true),
                        _kolona('Akcije'),
                      ],

                      rows: List.generate(trebovanja.length, (index) {
                        final trebovanje = trebovanja[index];

                        return DataRow(
                          // Klik bilo gdje na red otvara pregled trebovanja.
                          onSelectChanged: (_) =>
                              _prikaziTrebovanje(trebovanje),
                          cells: [
                            DataCell(Text('${index + 1}')),
                            DataCell(Text(trebovanje.broj)),
                            DataCell(Text(trebovanje.datum)),
                            DataCell(Text(trebovanje.radniNalog)),
                            DataCell(Text(trebovanje.magacin)),
                            DataCell(Text(trebovanje.primalac)),
                            DataCell(Text(trebovanje.nazivArtikala)),
                            DataCell(
                              Text('${_format(trebovanje.vrijednost)} €'),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'Pregled',
                                onPressed: () =>
                                    _prikaziTrebovanje(trebovanje),
                                icon: const Icon(Icons.visibility_outlined),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ------------------------------------------------
            // PAGINACIJA
            // ------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Prethodna stranica',
                  onPressed: currentPage > 1
                      ? () {
                          setState(() {
                            currentPage--;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),

                const SizedBox(width: 8),

                ...List.generate(totalPages, (index) {
                  final page = index + 1;
                  final isSelected = currentPage == page;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          currentPage = page;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$page',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(width: 8),

                IconButton(
                  tooltip: 'Sljedeća stranica',
                  onPressed: currentPage < totalPages
                      ? () {
                          setState(() {
                            currentPage++;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Pop-up sa podacima jednog trebovanja: zaglavlje, artikli i normativi.
class _TrebovanjeDialog extends StatelessWidget {
  final _Trebovanje trebovanje;

  const _TrebovanjeDialog({required this.trebovanje});

  static const _bold = TextStyle(fontWeight: FontWeight.bold);

  DataColumn _kolona(String naslov, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(naslov, style: _bold),
    );
  }

  Widget _okvir(Widget tabela) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: tabela,
      ),
    );
  }

  Widget _sekcija(String naslov) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        naslov,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _podatak(String label, String vrijednost) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(vrijednost, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildTabelaArtikala() {
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
        ],
        rows: List.generate(trebovanje.artikli.length, (index) {
          final stavka = trebovanje.artikli[index];

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(stavka.artikal.sifra)),
              DataCell(Text(stavka.artikal.naziv)),
              DataCell(Text(stavka.artikal.jm)),
              DataCell(Text(_formatKolicina(stavka.kolicina))),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTabelaNormativa() {
    final normativi = trebovanje.normativi;
    final ukupno = normativi.fold<double>(0, (suma, n) => suma + n.vrijednost);

    final redovi = List.generate(normativi.length, (index) {
      final normativ = normativi[index];
      final razlika = normativ.izdato != normativ.trebovano;

      return DataRow(
        cells: [
          DataCell(Text('${index + 1}')),
          DataCell(Text(normativ.naziv)),
          DataCell(Text(normativ.jm)),
          DataCell(Text(_formatKolicina(normativ.trebovano))),
          DataCell(
            Text(
              _formatKolicina(normativ.izdato),
              style: razlika
                  ? TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
          ),
          DataCell(Text('${_format(normativ.cijena)} €')),
          DataCell(Text('${_format(normativ.vrijednost)} €')),
        ],
      );
    });

    redovi.add(
      DataRow(
        color: WidgetStateProperty.all(Colors.grey.shade100),
        cells: [
          const DataCell(Text('')),
          const DataCell(Text('Ukupno', style: _bold)),
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('')),
          DataCell(Text('${_format(ukupno)} €', style: _bold)),
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Naslov
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
              child: Row(
                children: [
                  Text(
                    'Trebovanje ${trebovanje.broj}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Zatvori',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 48,
                      runSpacing: 16,
                      children: [
                        _podatak('Datum', trebovanje.datum),
                        _podatak('Radni nalog', trebovanje.radniNalog),
                        _podatak('Izdaje', trebovanje.magacin),
                        _podatak('Prima', trebovanje.primalac),
                        _podatak(
                          'Vrijednost',
                          '${_format(trebovanje.vrijednost)} €',
                        ),
                      ],
                    ),

                    _sekcija('Artikli'),
                    _buildTabelaArtikala(),

                    _sekcija('Normativi'),
                    _buildTabelaNormativa(),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Zatvori'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
