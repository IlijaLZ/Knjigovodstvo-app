import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/routes/app_routes.dart';
import 'package:knjigovodstvo_app/screens/analiticka_kartica.dart';

class RadniNalogScreen extends StatefulWidget {
  const RadniNalogScreen({super.key});

  @override
  State<RadniNalogScreen> createState() => _RadniNalogScreenState();
}

class _RadniNalogScreenState extends State<RadniNalogScreen> {
  int currentPage = 1;

  final int totalPages = 3;

  final List<Map<String, String>> dokumenti = [
    {
      'rb': '1',
      'kupac': 'Firma d.o.o.',
      'datum': '23.09.2026',
      'brojNaloga': 'RN-001',
      'artikal': 'Drveni stol',
      'brojKomada': '10',
    },
    {
      'rb': '2',
      'kupac': 'Komerc Trade',
      'datum': '22.09.2026',
      'brojNaloga': 'RN-002',
      'artikal': 'Stolica',
      'brojKomada': '40',
    },
    {
      'rb': '3',
      'kupac': 'Montenegro Commerce',
      'datum': '20.09.2026',
      'brojNaloga': 'RN-003',
      'artikal': 'Polica',
      'brojKomada': '25',
    },
    {
      'rb': '4',
      'kupac': 'Balkan Trade',
      'datum': '18.09.2026',
      'brojNaloga': 'RN-004',
      'artikal': 'Ormar',
      'brojKomada': '5',
    },
    {
      'rb': '5',
      'kupac': 'Adria Market',
      'datum': '15.09.2026',
      'brojNaloga': 'RN-005',
      'artikal': 'Komoda',
      'brojKomada': '12',
    },
    {
      'rb': '6',
      'kupac': 'Euro Commerce',
      'datum': '12.09.2026',
      'brojNaloga': 'RN-006',
      'artikal': 'Klupa',
      'brojKomada': '30',
    },
    {
      'rb': '7',
      'kupac': 'Primorje Trade',
      'datum': '10.09.2026',
      'brojNaloga': 'RN-007',
      'artikal': 'Radni stol',
      'brojKomada': '8',
    },
    {
      'rb': '8',
      'kupac': 'Market Plus',
      'datum': '08.09.2026',
      'brojNaloga': 'RN-008',
      'artikal': 'Regal',
      'brojKomada': '15',
    },
  ];

  DataColumn _kolona(String naslov) {
    return DataColumn(
      label: Text(naslov, style: const TextStyle(fontWeight: FontWeight.bold)),
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
            // NASLOV + DUGME
            // ------------------------------------------------
            Row(
              children: [
                const Text(
                  'Radni nalog',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),

                const Spacer(),

                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: zamijeniti rutom za dodavanje radnog naloga
                    // kad je napraviš (npr. AppRoutes.dodajRadniNalog)
                    Get.toNamed(AppRoutes.dodajRadniNalog);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj novi dokument'),
                ),
              ],
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

                      columns: [
                        _kolona('RB'),
                        _kolona('Kupac'),
                        _kolona('Datum'),
                        _kolona('Broj naloga'),
                        _kolona('Artikal'),
                        _kolona('Broj komada'),
                        _kolona('Akcije'),
                      ],

                      rows: dokumenti.map((dokument) {
                        return DataRow(
                          cells: [
                            DataCell(Text(dokument['rb']!)),
                            DataCell(Text(dokument['kupac']!)),
                            DataCell(Text(dokument['datum']!)),
                            DataCell(Text(dokument['brojNaloga']!)),
                            DataCell(Text(dokument['artikal']!)),
                            DataCell(Text(dokument['brojKomada']!)),

                            DataCell(
                              Row(
                                children: [
                                  // Pregled
                                  IconButton(
                                    tooltip: 'Pregled',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const AnalitickaKarticaScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.visibility_outlined),
                                  ),

                                  // Izmijeni
                                  IconButton(
                                    tooltip: 'Izmijeni',
                                    onPressed: () {},
                                    icon: const Icon(Icons.edit_outlined),
                                  ),

                                  // Obriši
                                  IconButton(
                                    tooltip: 'Obriši',
                                    onPressed: () {},
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
