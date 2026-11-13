import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/firma_controller.dart';
import '../models/auth_models.dart';
import '../widgets/magacin_ui.dart';
import 'excel_izvoz.dart';
import 'pdf_izvoz.dart';
import 'registar_izvoza.dart';

enum FormatIzvoza { excel, pdf }

// Dugme "Izvoz": klik otvori izbor Excel / PDF, pa se pripreme podaci
// (može učitati sve stranice sa servera), otvori "Sačuvaj kao" i javi
// rezultat. Dok traje, dugme se vrti. Dok je na ekranu, prijavljeno je u
// RegistarIzvoza (izvoz glasom ide u Excel).
class DugmeIzvoza extends StatefulWidget {
  // Naziv fajla bez ekstenzije.
  final String Function() nazivFajla;

  // Listovi za Excel i PDF; može trajati (učitavanje svih stranica). Prazna lista
  // znači da je korisnik odustao (npr. zatvorio izbor perioda).
  final Future<List<ListExcel>> Function() pripremi;

  final double visina;
  final String tekst;
  final String opis;
  final VrstaDugmeta vrsta;

  const DugmeIzvoza({
    super.key,
    required this.nazivFajla,
    required this.pripremi,
    this.visina = 38,
    this.tekst = 'Izvoz',
    this.opis = 'Izvezi u Excel ili PDF',
    this.vrsta = VrstaDugmeta.sekundarno,
  });

  @override
  State<DugmeIzvoza> createState() => _DugmeIzvozaState();
}

class _DugmeIzvozaState extends State<DugmeIzvoza> {
  bool _radi = false;
  late final PrijavaIzvoza _prijava;

  @override
  void initState() {
    super.initState();
    _prijava = RegistarIzvoza.prijavi(
      opis: () => widget.nazivFajla(),
      izvezi: () => _izvezi(FormatIzvoza.excel),
    );
  }

  @override
  void dispose() {
    RegistarIzvoza.odjavi(_prijava);
    super.dispose();
  }

  Future<IshodIzvoza> _izvezi(FormatIzvoza format) async {
    if (_radi) return IshodIzvoza.vecRadi;
    setState(() => _radi = true);
    final poruke = ScaffoldMessenger.of(context);

    void javi(String tekst) {
      poruke
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(tekst),
            behavior: SnackBarBehavior.floating,
            backgroundColor: MagacinBoje.naslov,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
    }

    try {
      final listovi = await widget.pripremi();
      if (listovi.isEmpty) return IshodIzvoza.odustao;
      final naziv = bezbjedanNazivFajla(widget.nazivFajla());
      final sacuvano = switch (format) {
        FormatIzvoza.excel => await sacuvajExcel(naziv, listovi),
        FormatIzvoza.pdf => await sacuvajPdf(naziv, listovi, firma: _firma),
      };
      if (!sacuvano) return IshodIzvoza.odustao;
      javi(switch (format) {
        FormatIzvoza.excel => 'Excel je sačuvan ($naziv.xlsx).',
        FormatIzvoza.pdf => 'PDF je sačuvan ($naziv.pdf).',
      });
      return IshodIzvoza.sacuvano;
    } on ApiException catch (e) {
      javi('Izvoz nije uspio: ${e.message}');
      return IshodIzvoza.greska;
    } catch (e) {
      debugPrint('Izvoz (${format.name}) nije uspio: $e');
      javi('Izvoz nije uspio. Pokušajte ponovo.');
      return IshodIzvoza.greska;
    } finally {
      if (mounted) setState(() => _radi = false);
    }
  }

  // Naziv izabrane firme za zaglavlje PDF-a.
  String? get _firma => Get.isRegistered<FirmaController>()
      ? Get.find<FirmaController>().izabranaFirma.value?.name
      : null;

  // Meni ispod dugmeta: Excel ili PDF.
  Future<void> _izaberiFormat(BuildContext dugme) async {
    if (_radi) return;
    final kutija = dugme.findRenderObject() as RenderBox;
    final prekrivac = Overlay.of(dugme).context.findRenderObject() as RenderBox;
    final gore = kutija.localToGlobal(
      Offset(0, kutija.size.height + 4),
      ancestor: prekrivac,
    );
    final dole = kutija.localToGlobal(
      kutija.size.bottomRight(Offset.zero),
      ancestor: prekrivac,
    );

    PopupMenuItem<FormatIzvoza> stavka(
      FormatIzvoza f,
      IconData ikona,
      Color boja,
      String naslov,
      String opis,
    ) => PopupMenuItem(
      value: f,
      child: Row(
        children: [
          Icon(ikona, color: boja, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                naslov,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.naslov,
                ),
              ),
              Text(
                opis,
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final format = await showMenu<FormatIzvoza>(
      context: dugme,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromRect(
        Rect.fromPoints(gore, dole),
        Offset.zero & prekrivac.size,
      ),
      items: [
        stavka(
          FormatIzvoza.excel,
          Icons.table_chart_rounded,
          MagacinBoje.zelena,
          'Excel',
          'Tabela (.xlsx) za dalju obradu',
        ),
        stavka(
          FormatIzvoza.pdf,
          Icons.picture_as_pdf_rounded,
          MagacinBoje.crvena,
          'PDF',
          'Dokument za štampu i slanje',
        ),
      ],
    );
    if (format != null && mounted) await _izvezi(format);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.opis,
      child: Builder(
        builder: (dugme) => GlatkoDugme(
          tekst: widget.tekst,
          ikona: Icons.download_rounded,
          vrsta: widget.vrsta,
          visina: widget.visina,
          ucitavanje: _radi,
          onTap: () => _izaberiFormat(dugme),
        ),
      ),
    );
  }
}
