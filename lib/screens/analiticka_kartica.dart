import 'package:flutter/material.dart';

class AnalitickaKarticaScreen extends StatelessWidget {
  const AnalitickaKarticaScreen({super.key});

  static const Color primaryColor = Color(0xFF2563EB);
  static const Color headerColor = Color(0xFFE2E8F0);
  static const Color groupHeaderColor = Color(0xFFCBD5E1);
  static const Color borderColor = Color(0xFFCBD5E1);

  final List<Map<String, String>> podaci = const [
    {
      'rb': '1',
      'nalog': 'NAL-001',
      'dokument': 'Početno stanje',
      'duguje': '50,00',
      'potrazuje': '0,00',
      'saldo': '50,00',
      'cijena': '50,00',
      'duguje2': '50,00',
      'potrazuje2': '0,00',
      'saldo2': '50,00',
    },
    {
      'rb': '2',
      'nalog': 'NAL-002',
      'dokument': 'Kalkulacija 001',
      'duguje': '100,00',
      'potrazuje': '0,00',
      'saldo': '100,00',
      'cijena': '100,00',
      'duguje2': '100,00',
      'potrazuje2': '0,00',
      'saldo2': '100,00',
    },
  ];

  static const List<double> sirine = [
    55,
    115,
    175,
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
    'Dokument',
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
    'dokument',
    'duguje',
    'potrazuje',
    'saldo',
    'cijena',
    'duguje2',
    'potrazuje2',
    'saldo2',
  ];

  @override
  Widget build(BuildContext context) {
    final ukupnaSirina = sirine.reduce((a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analitička kartica'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Brasno tip 100',
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
                            _blok(sirine[0] + sirine[1] + sirine[2], null),
                            _blok(sirine[3] + sirine[4] + sirine[5], 'Komadno'),
                            _blok(sirine[6], null),
                            _blok(
                              sirine[7] + sirine[8] + sirine[9],
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

                                return Container(
                                  height: 52,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  alignment: columnIndex == 0
                                      ? Alignment.center
                                      : columnIndex >= 3
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
