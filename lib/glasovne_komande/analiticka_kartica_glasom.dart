import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/firma_controller.dart';
import '../controllers/navigation_controller.dart';
import '../models/auth_models.dart';
import '../models/stock.dart';
import '../screens/analiticka_kartica.dart';
import '../services/stocks_service.dart';
import '../widgets/magacin_ui.dart';
import 'glasovne_komande.dart' show normalizuj, ZecKaze, ZecRaspolozenje;

// "Analitička kartica brašna" -> pronađi artikal na stanju i otvori karticu.

// Riječi komande koje nisu dio naziva artikla (normalizovane).
const Set<String> _sumRijeci = {
  'otvori',
  'otvorite',
  'mi',
  'pokazi',
  'prikazi',
  'daj',
  'hocu',
  'ocu',
  'zelim',
  'da',
  'vidim',
  'pogledam',
  'molim',
  'te',
  'vas',
  'za',
  'od',
  'artikal',
  'artikla',
  'artikl',
  'artikli',
  'artiklu',
  'robe',
  'roba',
  'materijala',
  'materijal',
  'kartica',
  'karticu',
  'kartice',
  'kartici',
  'karticom',
  'i',
  'na',
  'sa',
  's',
};

// Iz izgovorenog teksta vrati naziv artikla (originalne riječi, s kvačicama,
// jer ih server tako traži). Prazno ako je rečeno samo "analitička kartica".
String izdvojiNazivArtikla(String izgovoreno) {
  final rijeci = izgovoreno
      .split(RegExp(r'\s+'))
      .where((r) => r.trim().isNotEmpty)
      .where((r) {
        final n = normalizuj(r);
        return n.isNotEmpty &&
            !_sumRijeci.contains(n) &&
            !n.startsWith('analiti') &&
            !n.startsWith('kartic');
      })
      .map((r) => r.replaceAll(RegExp(r'[.,!?„“”"]'), ''));
  return rijeci.join(' ').trim();
}

// Korijen riječi za pretragu: "brašna" -> "brašn" (hvata i "Brašno").
String _korijen(String rijec, int skrati) {
  final duzina = rijec.length - skrati;
  return duzina >= 3 ? rijec.substring(0, duzina) : rijec;
}

// Da li naziv artikla odgovara svim izgovorenim riječima (po korijenu).
bool _odgovaraNazivu(StanjeArtikla s, List<String> rijeci) {
  final naziv = normalizuj('${s.artikal.naziv} ${s.artikal.sifra}');
  return rijeci.every((r) => naziv.contains(_korijen(normalizuj(r), 2)));
}

Future<void> otvoriAnalitickuKarticu(String izgovoreno, ZecKaze kaze) async {
  final nav = Get.find<NavigationController>();
  final naziv = izdvojiNazivArtikla(izgovoreno);
  if (naziv.isEmpty) {
    nav.openStanjeMagacina();
    kaze(
      'Čiju karticu? Reci i artikal, npr. „analitička kartica brašna”, '
      'ili klikni na artikal u listi.',
    );
    return;
  }

  final firma = Get.find<FirmaController>().izabranaFirma.value;
  if (firma == null) {
    kaze('Prvo izaberi firmu gore desno.', ZecRaspolozenje.zbunjen);
    return;
  }

  kaze('Tražim „$naziv” po magacinima…', ZecRaspolozenje.racuna);
  final List<StanjeArtikla> nadjeno;
  try {
    nadjeno = await _trazi(firma.id, naziv);
  } on ApiException catch (e) {
    kaze(e.message, ZecRaspolozenje.greska);
    return;
  }

  if (nadjeno.isEmpty) {
    nav.openStanjeMagacina();
    kaze(
      'Prekopao sam magacin — nema „$naziv”. Pogledaj listu.',
      ZecRaspolozenje.zbunjen,
    );
    return;
  }

  // Karticu otvaramo preko stanja magacina, da "nazad" vodi tamo.
  nav.openStanjeMagacina();
  if (nadjeno.length > 1) {
    kaze('Našao sam ${nadjeno.length} — koji ti treba?');
  }
  final izabran = nadjeno.length == 1
      ? nadjeno.first
      : await Get.dialog<StanjeArtikla>(_IzborArtikla(naziv, nadjeno));
  final id = izabran?.artikal.id;
  if (izabran == null || id == null) {
    kaze('Dobro, ništa onda.', ZecRaspolozenje.prica);
    return;
  }
  kaze('Klik! Kartica: ${izabran.artikal.naziv}.', ZecRaspolozenje.klik);

  Get.to(
    () => AnalitickaKarticaScreen(
      articleId: id,
      naziv: izabran.artikal.naziv,
      jm: izabran.artikal.jm,
      warehouseId: izabran.skladiste?.id,
      skladiste: izabran.skladiste?.naziv,
      tipSkladista: izabran.skladiste?.tip,
    ),
  );
}

// Server traži po nazivu/šifri kao podniz, pa "brašna" ne nađe "Brašno".
// Zato se redom pokuša: cijeli tekst, pa korijeni najduže riječi.
Future<List<StanjeArtikla>> _trazi(int firmaId, String naziv) async {
  final servis = StocksService();
  final rijeci = naziv.split(' ');
  final najduza = rijeci.reduce((a, b) => b.length > a.length ? b : a);

  final pokusaji = <String>{naziv, _korijen(najduza, 1), _korijen(najduza, 2)};

  for (final pojam in pokusaji) {
    final stranica = await servis.fetchStocks(
      firmaId,
      search: pojam,
      perPage: 50,
    );
    if (stranica.stanja.isEmpty) continue;
    // Od onoga što server vrati, zadrži artikle koji odgovaraju svim
    // izgovorenim riječima ("ražano brašno" ne vraća pšenično).
    final tacni = stranica.stanja
        .where((s) => _odgovaraNazivu(s, rijeci))
        .toList();
    return tacni.isNotEmpty ? tacni : stranica.stanja;
  }
  return const [];
}

String _kolicina(double v) {
  var t = v.toStringAsFixed(4);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t.replaceAll('.', ',');
}

// Više artikala (ili isti artikal na više skladišta): korisnik bira.
class _IzborArtikla extends StatelessWidget {
  final String pojam;
  final List<StanjeArtikla> stanja;

  const _IzborArtikla(this.pojam, this.stanja);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Analitička kartica — „$pojam”',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zatvori',
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Našao sam više artikala. Izaberi jedan:',
                style: TextStyle(fontSize: 13, color: MagacinBoje.priguseno),
              ),
            ),
            const Divider(height: 1, color: MagacinBoje.linija),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: stanja.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                  color: MagacinBoje.linijaSvijetla,
                ),
                itemBuilder: (context, i) {
                  final s = stanja[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    onTap: () => Get.back(result: s),
                    title: Text(
                      s.artikal.naziv,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (s.artikal.sifra.isNotEmpty)
                          'Šifra ${s.artikal.sifra}',
                        if (s.skladiste != null) s.skladiste!.naziv,
                      ].join(' · '),
                      style: const TextStyle(color: MagacinBoje.priguseno),
                    ),
                    trailing: Text(
                      '${_kolicina(s.kolicina)} ${s.artikal.jm}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: MagacinBoje.tekst,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
