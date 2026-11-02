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
      'redniBroj': 'RN-001',
      'datum': '23.09.2026',
      'kupac': 'Firma d.o.o.',
      'porudzbina': 'POR-101',
      'artikli': 'Krevet 160x200, Tabure',
      'vrijednost': '1.250,00',
    },
    {
      'rb': '2',
      'redniBroj': 'RN-002',
      'datum': '22.09.2026',
      'kupac': 'Komerc Trade',
      'porudzbina': 'POR-102',
      'artikli': 'Krevet 90x200',
      'vrijednost': '860,40',
    },
    {
      'rb': '3',
      'redniBroj': 'RN-003',
      'datum': '20.09.2026',
      'kupac': 'Montenegro Commerce',
      'porudzbina': 'POR-103',
      'artikli': 'Tabure',
      'vrijednost': '312,00',
    },
    {
      'rb': '4',
      'redniBroj': 'RN-004',
      'datum': '18.09.2026',
      'kupac': 'Balkan Trade',
      'porudzbina': 'POR-104',
      'artikli': 'Krevet 160x200',
      'vrijednost': '2.140,00',
    },
    {
      'rb': '5',
      'redniBroj': 'RN-005',
      'datum': '15.09.2026',
      'kupac': 'Adria Market',
      'porudzbina': 'POR-105',
      'artikli': 'Krevet 90x200, Tabure',
      'vrijednost': '978,60',
    },
    {
      'rb': '6',
      'redniBroj': 'RN-006',
      'datum': '12.09.2026',
      'kupac': 'Euro Commerce',
      'porudzbina': 'POR-106',
      'artikli': 'Krevet 160x200',
      'vrijednost': '1.070,00',
    },
    {
      'rb': '7',
      'redniBroj': 'RN-007',
      'datum': '10.09.2026',
      'kupac': 'Primorje Trade',
      'porudzbina': 'POR-107',
      'artikli': 'Tabure',
      'vrijednost': '156,00',
    },
    {
      'rb': '8',
      'redniBroj': 'RN-008',
      'datum': '08.09.2026',
      'kupac': 'Market Plus',
      'porudzbina': 'POR-108',
      'artikli': 'Krevet 90x200',
      'vrijednost': '430,20',
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
                  onPressed: () => Get.toNamed(AppRoutes.dodajRadniNalog),
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
                        _kolona('Redni broj'),
                        _kolona('Datum'),
                        _kolona('Kupac'),
                        _kolona('Porudžbina broj'),
                        _kolona('Artikli'),
                        _kolona('Vrijednost materijala'),
                        _kolona('Akcije'),
                      ],

                      rows: dokumenti.map((dokument) {
                        return DataRow(
                          cells: [
                            DataCell(Text(dokument['rb']!)),
                            DataCell(Text(dokument['redniBroj']!)),
                            DataCell(Text(dokument['datum']!)),
                            DataCell(Text(dokument['kupac']!)),
                            DataCell(Text(dokument['porudzbina']!)),
                            DataCell(Text(dokument['artikli']!)),
                            DataCell(Text('${dokument['vrijednost']!} €')),

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
