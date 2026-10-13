import 'package:flutter/material.dart';

class MagacinRepromaterijala extends StatelessWidget {
  const MagacinRepromaterijala({super.key});

  static const Color primaryColor = Color(0xFF2563EB);
  static const Color headerColor = Color(0xFFE2E8F0);
  static const Color groupHeaderColor = Color(0xFFCBD5E1);
  static const Color borderColor = Color(0xFFCBD5E1);

  final List<Map<String, String>> podaci = const [
    {
      'rb': '1',
      'nalog': 'NAL-001',
      'idKalk': 'KNC-1001',
      'artikal': 'Brašno tip 500',
      'sifra': 'ART-0001',
      'jm': 'kg',
      'kategorija': 'Sirovine',
      'dobavljac': 'Mlin d.o.o.',
      'minZaliha': '100 kg',
      'napomena': 'Čuvati na suvom mjestu.',
      'duguje': '500,00',
      'potrazuje': '0,00',
      'saldo': '500,00',
      'cijena': '0,85',
      'duguje2': '425,00',
      'potrazuje2': '0,00',
      'saldo2': '425,00',
    },
    {
      'rb': '2',
      'nalog': 'NAL-002',
      'idKalk': 'KNC-1002',
      'artikal': 'Šećer kristal',
      'sifra': 'ART-0002',
      'jm': 'kg',
      'kategorija': 'Sirovine',
      'dobavljac': 'Slatka trgovina',
      'minZaliha': '80 kg',
      'napomena': 'Zaštititi od vlage.',
      'duguje': '300,00',
      'potrazuje': '50,00',
      'saldo': '250,00',
      'cijena': '1,10',
      'duguje2': '330,00',
      'potrazuje2': '55,00',
      'saldo2': '275,00',
    },
    {
      'rb': '3',
      'nalog': 'NAL-003',
      'idKalk': 'KNC-1003',
      'artikal': 'Kvasac svježi',
      'sifra': 'ART-0003',
      'jm': 'kg',
      'kategorija': 'Dodaci',
      'dobavljac': 'Fermenta d.o.o.',
      'minZaliha': '20 kg',
      'napomena': 'Čuvati u frižideru (2–8 °C).',
      'duguje': '80,00',
      'potrazuje': '20,00',
      'saldo': '60,00',
      'cijena': '4,50',
      'duguje2': '360,00',
      'potrazuje2': '90,00',
      'saldo2': '270,00',
    },
    {
      'rb': '4',
      'nalog': 'NAL-004',
      'idKalk': 'KNC-1004',
      'artikal': 'Ulje suncokretovo 1L',
      'sifra': 'ART-0004',
      'jm': 'l',
      'kategorija': 'Sirovine',
      'dobavljac': 'Uljara Zlatno',
      'minZaliha': '50 l',
      'napomena': 'Čuvati dalje od direktne svjetlosti.',
      'duguje': '200,00',
      'potrazuje': '40,00',
      'saldo': '160,00',
      'cijena': '2,20',
      'duguje2': '440,00',
      'potrazuje2': '88,00',
      'saldo2': '352,00',
    },
    {
      'rb': '5',
      'nalog': 'NAL-005',
      'idKalk': 'KNC-1005',
      'artikal': 'So fina',
      'sifra': 'ART-0005',
      'jm': 'kg',
      'kategorija': 'Dodaci',
      'dobavljac': 'Solana Ulcinj',
      'minZaliha': '30 kg',
      'napomena': '',
      'duguje': '150,00',
      'potrazuje': '10,00',
      'saldo': '140,00',
      'cijena': '0,40',
      'duguje2': '60,00',
      'potrazuje2': '4,00',
      'saldo2': '56,00',
    },
  ];

  static const List<double> sirine = [
    55,
    115,
    150,
    190,
    100,
    100,
    100,
    200,
    120,
    120,
    120,
  ];

  static const List<String> zaglavlja = [
    'Rb',
    'Br. naloga',
    'ID kalk. nab. cijene',
    'Artikal',
    'Duguje',
    'Potražuje',
    'Saldo',
    'Prosječna nabavna cijena',
    'Duguje',
    'Potražuje',
    'Saldo',
  ];

  static const List<String> kljucevi = [
    'rb',
    'nalog',
    'idKalk',
    'artikal',
    'duguje',
    'potrazuje',
    'saldo',
    'cijena',
    'duguje2',
    'potrazuje2',
    'saldo2',
  ];

  static const int artikalKolona = 3;

  @override
  Widget build(BuildContext context) {
    final ukupnaSirina = sirine.reduce((a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Magacin repromaterijala'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lista artikala',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: ukupnaSirina,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Krovno zaglavlje (Komadno / Vrijednosno)
                        Row(
                          children: [
                            _blok(
                              sirine[0] + sirine[1] + sirine[2] + sirine[3],
                              null,
                            ),
                            _blok(sirine[4] + sirine[5] + sirine[6], 'Komadno'),
                            _blok(sirine[7], null),
                            _blok(
                              sirine[8] + sirine[9] + sirine[10],
                              'Vrijednosno',
                            ),
                          ],
                        ),

                        // Zaglavlje kolona
                        Table(
                          columnWidths: {
                            for (int i = 0; i < sirine.length; i++)
                              i: FixedColumnWidth(sirine[i]),
                          },
                          border: TableBorder.all(color: borderColor, width: 1),
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(
                                color: headerColor,
                              ),
                              children: List.generate(
                                zaglavlja.length,
                                (index) => Container(
                                  height: 60,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    zaglavlja[index],
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Redovi sa podacima
                        Table(
                          columnWidths: {
                            for (int i = 0; i < sirine.length; i++)
                              i: FixedColumnWidth(sirine[i]),
                          },
                          border: TableBorder.all(color: borderColor, width: 1),
                          children: List.generate(podaci.length, (rowIndex) {
                            final red = podaci[rowIndex];

                            return TableRow(
                              decoration: BoxDecoration(
                                color: rowIndex.isEven
                                    ? Colors.white
                                    : const Color(0xFFF8FAFC),
                              ),
                              children: List.generate(kljucevi.length, (
                                columnIndex,
                              ) {
                                final vrijednost =
                                    red[kljucevi[columnIndex]] ?? '';

                                // Kolona "Artikal" -> dugme
                                if (columnIndex == artikalKolona) {
                                  return Container(
                                    height: 52,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _prikaziInfoArtikla(context, red),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryColor,
                                        side: const BorderSide(
                                          color: primaryColor,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(
                                        Icons.info_outline,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Pogledaj artikle',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  );
                                }

                                return Container(
                                  height: 52,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  alignment: columnIndex == 0
                                      ? Alignment.center
                                      : columnIndex >= 4
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Text(
                                    vrijednost,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                );
                              }),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _prikaziInfoArtikla(BuildContext context, Map<String, String> red) {
    final napomena = (red['napomena'] ?? '').isEmpty ? '-' : red['napomena']!;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          red['artikal'] ?? '',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRed('Šifra artikla', red['sifra'] ?? ''),
              _infoRed('Jedinica mjere', red['jm'] ?? ''),
              _infoRed('Kategorija', red['kategorija'] ?? ''),
              _infoRed('Dobavljač', red['dobavljac'] ?? ''),
              _infoRed('Minimalna zaliha', red['minZaliha'] ?? ''),
              _infoRed('ID kalk. nab. cijene', red['idKalk'] ?? ''),
              _infoRed('Prosječna nabavna cijena', red['cijena'] ?? ''),
              _infoRed('Napomena', napomena),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }

  Widget _infoRed(String naslov, String vrijednost) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              naslov,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              vrijednost,
              style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blok(double sirina, String? naslov) {
    return Container(
      width: sirina,
      height: 42,
      decoration: BoxDecoration(
        color: naslov == null ? Colors.transparent : groupHeaderColor,
        border: naslov == null
            ? null
            : Border.all(color: borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: naslov == null
          ? null
          : Text(
              naslov,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF0F172A),
              ),
            ),
    );
  }
}
