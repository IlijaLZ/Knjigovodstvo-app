import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../widgets/logo.dart';
import '../widgets/magacin_ui.dart';

// Pregled dokumenta prije štampe: prikazuje PDF i nudi štampu i dijeljenje
// (sačuvaj kao PDF). Zajednički za sve dokumente koji se štampaju.
Future<void> prikaziPregledStampe(
  BuildContext context, {
  required String naslov,
  required String nazivFajla,
  required Future<Uint8List> Function(PdfPageFormat format) napravi,
  PdfPageFormat format = PdfPageFormat.a4,
}) {
  return showDialog(
    context: context,
    barrierColor: const Color(0x990F172A),
    builder: (context) => _PregledStampe(
      naslov: naslov,
      nazivFajla: nazivFajla,
      napravi: napravi,
      format: format,
    ),
  );
}

class _PregledStampe extends StatelessWidget {
  final String naslov;
  final String nazivFajla;
  final Future<Uint8List> Function(PdfPageFormat format) napravi;
  final PdfPageFormat format;

  const _PregledStampe({
    required this.naslov,
    required this.nazivFajla,
    required this.napravi,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final velicina = MediaQuery.sizeOf(context);
    final usko = velicina.width < 600;

    final sadrzaj = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: akcentSvijetlo,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.print_outlined,
                  color: akcentAplikacije,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PREGLED ŠTAMPE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: akcentAplikacije,
                      ),
                    ),
                    Text(
                      naslov,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Zatvori',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: MagacinBoje.priguseno,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: MagacinBoje.linija),
        Expanded(
          child: PdfPreview(
            build: napravi,
            pdfFileName: nazivFajla,
            initialPageFormat: format,
            canChangeOrientation: false,
            canChangePageFormat: false,
            // Dinamički raspored na macOS-u blokira glavni thread dok Dart
            // pravi PDF, a Dart radi na istom threadu: aplikacija se zamrzne.
            // Format je ionako fiksan (A4), pa se šalje gotov dokument.
            dynamicLayout: false,
            canDebug: false,
            allowSharing: true,
            allowPrinting: true,
            pdfPreviewPageDecoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x220F172A),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            scrollViewDecoration: const BoxDecoration(
              color: MagacinBoje.pozadina,
            ),
            loadingWidget: const ZecRacuna(
              tekst: 'Pripremam dokument za štampu…',
            ),
            onError: (context, greska) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Dokument se ne može pripremiti za štampu.\n$greska',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: MagacinBoje.crvena),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (usko) {
      return Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: SafeArea(child: sadrzaj),
      );
    }

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 900, height: velicina.height - 48, child: sadrzaj),
    );
  }
}
