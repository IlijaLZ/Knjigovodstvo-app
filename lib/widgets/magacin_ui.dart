import 'package:flutter/material.dart';

import 'logo.dart';

// Zajednički izgled ekrana magacina (stanje magacina, analitička kartica).

// Boja, ikona i opis za svako od tri skladišta.
class TemaSkladista {
  final Color boja;
  final Color tamna;
  final Color svijetla;
  final List<Color> gradijent;
  final IconData ikona;
  final String opis;

  // Zec koji stoji, u majici boje magacina.
  final PozaZeca zec;

  const TemaSkladista({
    required this.boja,
    required this.tamna,
    required this.svijetla,
    required this.gradijent,
    required this.ikona,
    required this.opis,
    this.zec = PozaZeca.stoji,
  });

  static const _repromaterijal = TemaSkladista(
    boja: Color(0xFFD97706),
    tamna: Color(0xFF92400E),
    svijetla: Color(0xFFFEF3C7),
    gradijent: [Color(0xFF451A03), Color(0xFF92400E), Color(0xFFD97706)],
    ikona: Icons.inventory_2_rounded,
    opis: 'Sirovine i repromaterijal za proizvodnju',
    zec: PozaZeca.stojiRepro,
  );

  static const _proizvodnja = TemaSkladista(
    boja: Color(0xFF2563EB),
    tamna: Color(0xFF1E40AF),
    svijetla: Color(0xFFDBEAFE),
    gradijent: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF2563EB)],
    ikona: Icons.precision_manufacturing_rounded,
    opis: 'Materijal i poluproizvodi u procesu proizvodnje',
    zec: PozaZeca.stojiProizvodnja,
  );

  static const _gotoviProizvodi = TemaSkladista(
    boja: Color(0xFF059669),
    tamna: Color(0xFF065F46),
    svijetla: Color(0xFFD1FAE5),
    gradijent: [Color(0xFF022C22), Color(0xFF065F46), Color(0xFF059669)],
    ikona: Icons.local_shipping_rounded,
    opis: 'Gotovi proizvodi spremni za prodaju',
  );

  static const _ostalo = TemaSkladista(
    boja: Color(0xFF0F5C66),
    tamna: Color(0xFF0B434B),
    svijetla: Color(0xFFE6F4F3),
    gradijent: [Color(0xFF062226), Color(0xFF0D4950), Color(0xFF0F5C66)],
    ikona: Icons.warehouse_rounded,
    opis: 'Pregled zaliha po artiklima',
  );

  factory TemaSkladista.za(String tip) => switch (tip) {
    'raw_materials' => _repromaterijal,
    'production' => _proizvodnja,
    'finished_goods' => _gotoviProizvodi,
    _ => _ostalo,
  };
}

// Paleta ekrana stanja magacina.
class MagacinBoje {
  static const pozadina = Color(0xFFF3F7F7);
  static const zaglavlje = Color(0xFFF7FAFA);
  static const linija = Color(0xFFE1E9EA);
  static const linijaSvijetla = Color(0xFFEFF4F4);
  static const naslov = Color(0xFF0A3238);
  static const tekst = Color(0xFF334155);
  static const priguseno = Color(0xFF64748B);
  static const svijetlo = Color(0xFF94A3B8);
  static const plava = Color(0xFF0F5C66);
  static const zelena = Color(0xFF059669);
  static const zelenaSvijetlo = Color(0xFFD1FAE5);
  static const crvena = Color(0xFFDC2626);
  static const crvenaSvijetlo = Color(0xFFFEE2E2);
  // Pozadina reda sa upozorenjem (npr. ispod minimalne količine).
  static const crvenaPozadina = Color(0xFFFEF2F2);
  static const narandzasta = Color(0xFFD97706);
  static const narandzastaSvijetlo = Color(0xFFFEF3C7);
}

// Red tabele sa hover efektom; onTap je opcion (npr. otvara karticu).
// Zajednički tempo hover animacija: dovoljno dug da prelaz sa reda na red
// izgleda glatko, a dovoljno kratak da ne kasni za mišem.
const Duration hoverTrajanje = Duration(milliseconds: 250);
const Curve hoverKriva = Curves.easeInOut;

// Providnu nijansu stapa sa podlogom u neprozirnu boju. Animacija između
// providne i pune boje miješa i alfu, pa na pola puta boja bljesne jače
// nego na kraju; između dvije neprozirne boje prelaz je ravnomjeran.
Color hoverNijansa(Color akcent, double alfa, [Color podloga = Colors.white]) =>
    Color.alphaBlend(akcent.withValues(alpha: alfa), podloga);

class HoverRed extends StatefulWidget {
  final Color akcent;
  final double visina;
  final VoidCallback? onTap;
  final Widget Function(bool hover) builder;

  // Pozadina reda bez hovera (npr. crvenkasta za upozorenje).
  final Color pozadina;

  const HoverRed({
    super.key,
    required this.akcent,
    required this.visina,
    required this.builder,
    this.onTap,
    this.pozadina = Colors.white,
  });

  @override
  State<HoverRed> createState() => _HoverRedStanje();
}

class _HoverRedStanje extends State<HoverRed> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: hoverTrajanje,
              curve: hoverKriva,
              height: widget.visina,
              decoration: BoxDecoration(
                color: _hover
                    ? hoverNijansa(widget.akcent, 0.04, widget.pozadina)
                    : widget.pozadina,
                border: const Border(
                  bottom: BorderSide(color: MagacinBoje.linijaSvijetla),
                ),
              ),
              child: widget.builder(_hover),
            ),
            // Akcent lijevo izraste iz sredine reda; crta se preko reda,
            // pa ne oduzima širinu kolonama.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedFractionallySizedBox(
                  duration: hoverTrajanje,
                  curve: hoverKriva,
                  heightFactor: _hover ? 0.56 : 0,
                  child: AnimatedOpacity(
                    duration: hoverTrajanje,
                    curve: hoverKriva,
                    opacity: _hover ? 1 : 0,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: widget.akcent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
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
}

// Staklena kartica sa jednim podatkom u zaglavlju.
class StatKartica extends StatelessWidget {
  final IconData ikona;
  final String naslov;
  final String vrijednost;
  final String? napomena;
  final bool upozorenje;
  final bool saIkonom;

  // Ikona na mint-zelenoj pločici (kartice u bojama brenda, npr. početna).
  final bool brend;

  // Dugačak tekst (npr. naziv firme) se skraćuje sa "…" umjesto smanjivanja.
  final bool skrati;

  const StatKartica({
    super.key,
    required this.ikona,
    required this.naslov,
    required this.vrijednost,
    this.napomena,
    this.upozorenje = false,
    this.saIkonom = true,
    this.skrati = false,
    this.brend = false,
  });

  // Ista kartica bez ikone, za uske ekrane.
  StatKartica kompaktna() => StatKartica(
    ikona: ikona,
    naslov: naslov,
    vrijednost: vrijednost,
    napomena: napomena,
    upozorenje: upozorenje,
    saIkonom: false,
    skrati: skrati,
    brend: brend,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: saIkonom ? 14 : 12,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: upozorenje && !saIkonom
            ? const Color(0x33FCA5A5)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: upozorenje && !saIkonom
              ? const Color(0x99FCA5A5)
              : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          if (saIkonom) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: upozorenje
                    ? const Color(0xFFFCA5A5)
                    : brend
                    ? mint
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                ikona,
                color: upozorenje
                    ? const Color(0xFF991B1B)
                    : brend
                    ? akcentTamni
                    : Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  naslov.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 2),
                if (skrati)
                  Text(
                    vrijednost,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      vrijednost,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                if (napomena != null)
                  Text(
                    napomena!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Forme i dugmad
// ---------------------------------------------------------------------------

// Boje brenda: petrolej je primarna, mint-zelena sekundarna.
// Mint-zelena ide samo na tamne površine; na bijeloj se koristi tamnija
// zelena (mintTamni) da bi bila vidljiva.
const Color akcentAplikacije = Color(0xFF0F5C66);
const Color akcentTamni = Color(0xFF0A3238);
const Color akcentNoc = Color(0xFF062226);
const Color akcentSvijetlo = Color(0xFFE6F4F3);
const Color mint = Color(0xFF7FE3C4);
const Color mintTamni = Color(0xFF1F9C78);
const Color mintSvijetlo = Color(0xFFDDF6EE);
const Color sloganBoja = Color(0xFF8FB8BB);

// Polje forme: zaobljeno, svijetla pozadina, ljubičast okvir u fokusu.
InputDecoration dekoracijaPolja({
  String? hint,
  IconData? ikona,
  Widget? suffix,
  String? errorText,
}) {
  OutlineInputBorder okvir(Color boja, [double sirina = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: boja, width: sirina),
      );

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: MagacinBoje.svijetlo),
    errorText: errorText,
    counterText: '',
    isDense: true,
    prefixIcon: ikona == null ? null : Icon(ikona, size: 19),
    prefixIconColor: WidgetStateColor.resolveWith(
      (s) => s.contains(WidgetState.error)
          ? MagacinBoje.crvena
          : s.contains(WidgetState.focused)
          ? akcentAplikacije
          : MagacinBoje.svijetlo,
    ),
    suffixIcon: suffix,
    filled: true,
    fillColor: MagacinBoje.zaglavlje,
    hoverColor: const Color(0xFFF1F5F9),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: okvir(MagacinBoje.linija),
    enabledBorder: okvir(MagacinBoje.linija),
    disabledBorder: okvir(MagacinBoje.linijaSvijetla),
    focusedBorder: okvir(akcentAplikacije, 1.6),
    errorBorder: okvir(hoverNijansa(MagacinBoje.crvena, 0.5)),
    focusedErrorBorder: okvir(MagacinBoje.crvena, 1.6),
  );
}

// Naziv polja iznad unosa.
class OznakaPolja extends StatelessWidget {
  final String tekst;
  final bool obavezno;

  const OznakaPolja(this.tekst, {super.key, this.obavezno = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Text.rich(
        TextSpan(
          text: tekst,
          children: [
            if (obavezno)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: MagacinBoje.crvena),
              ),
          ],
        ),
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: MagacinBoje.tekst,
        ),
      ),
    );
  }
}

enum VrstaDugmeta { primarno, sekundarno, opasno, svijetlo }

// Dugme sa glatkim hoverom (neprozirne boje, bez bljeska).
// `svijetlo` je za dugmad na tamnoj (gradijent) pozadini.
class GlatkoDugme extends StatefulWidget {
  final String tekst;
  final IconData? ikona;
  final VoidCallback? onTap;
  final bool ucitavanje;
  final VrstaDugmeta vrsta;
  final double visina;

  const GlatkoDugme({
    super.key,
    required this.tekst,
    this.ikona,
    this.onTap,
    this.ucitavanje = false,
    this.vrsta = VrstaDugmeta.primarno,
    this.visina = 46,
  });

  @override
  State<GlatkoDugme> createState() => _GlatkoDugmeState();
}

class _GlatkoDugmeState extends State<GlatkoDugme> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final aktivno = widget.onTap != null && !widget.ucitavanje;
    final h = _hover && aktivno;

    final (
      Color pozadina,
      Color okvir,
      Color tekst,
      Color? sjenka,
    ) = switch (widget.vrsta) {
      VrstaDugmeta.primarno => (
        h ? akcentTamni : akcentAplikacije,
        h ? akcentTamni : akcentAplikacije,
        Colors.white,
        const Color(0x400F5C66),
      ),
      VrstaDugmeta.opasno => (
        h ? const Color(0xFFB91C1C) : MagacinBoje.crvena,
        h ? const Color(0xFFB91C1C) : MagacinBoje.crvena,
        Colors.white,
        const Color(0x40DC2626),
      ),
      VrstaDugmeta.sekundarno => (
        h ? const Color(0xFFF1F5F9) : Colors.white,
        h ? const Color(0xFFCBD5E1) : MagacinBoje.linija,
        MagacinBoje.naslov,
        null,
      ),
      VrstaDugmeta.svijetlo => (
        h ? const Color(0xFF9FEBD3) : mint,
        h ? const Color(0xFF9FEBD3) : mint,
        akcentTamni,
        const Color(0x407FE3C4),
      ),
    };

    return Opacity(
      opacity: aktivno || widget.ucitavanje ? 1 : 0.5,
      child: MouseRegion(
        cursor: aktivno ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: aktivno ? widget.onTap : null,
          child: AnimatedContainer(
            duration: hoverTrajanje,
            curve: hoverKriva,
            height: widget.visina,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pozadina,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: okvir),
              boxShadow: sjenka == null
                  ? null
                  : [
                      BoxShadow(
                        color: sjenka,
                        blurRadius: h ? 18 : 10,
                        offset: Offset(0, h ? 8 : 4),
                      ),
                    ],
            ),
            child: AnimatedSwitcher(
              duration: hoverTrajanje,
              child: widget.ucitavanje
                  ? SizedBox(
                      key: const ValueKey('ucitavanje'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: tekst,
                      ),
                    )
                  : Row(
                      key: const ValueKey('tekst'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.ikona != null) ...[
                          Icon(
                            widget.ikona,
                            size: 18,
                            // Na petrolej dugmetu ikona je mint-zelena.
                            color: widget.vrsta == VrstaDugmeta.primarno
                                ? mint
                                : tekst,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            widget.tekst,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: tekst,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// Malo kvadratno dugme sa ikonom (akcije u redu tabele).
class IkonaAkcija extends StatefulWidget {
  final IconData ikona;
  final String poruka;
  final Color boja;
  final VoidCallback? onTap;

  const IkonaAkcija({
    super.key,
    required this.ikona,
    required this.poruka,
    required this.boja,
    this.onTap,
  });

  @override
  State<IkonaAkcija> createState() => _IkonaAkcijaState();
}

class _IkonaAkcijaState extends State<IkonaAkcija> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final aktivno = widget.onTap != null;
    final h = _hover && aktivno;
    return Tooltip(
      message: widget.poruka,
      child: MouseRegion(
        cursor: aktivno ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: hoverTrajanje,
            curve: hoverKriva,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: h ? hoverNijansa(widget.boja, 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: h ? hoverNijansa(widget.boja, 0.35) : MagacinBoje.linija,
              ),
            ),
            child: TweenAnimationBuilder<Color?>(
              duration: hoverTrajanje,
              curve: hoverKriva,
              tween: ColorTween(end: h ? widget.boja : MagacinBoje.priguseno),
              builder: (context, c, _) =>
                  Icon(widget.ikona, size: 17, color: c),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dokumenta (kalkulacije, radni nalozi...)
// ---------------------------------------------------------------------------

// Ikona dokumenta sa "presavijenim uglom" za zaglavlje liste dokumenata.
class ZnakDokumenta extends StatelessWidget {
  final IconData ikona;
  final bool malo;

  const ZnakDokumenta({super.key, required this.ikona, this.malo = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: malo ? 46 : 54,
      height: malo ? 52 : 60,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [akcentAplikacije, akcentTamni],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x330F5C66),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(ikona, color: mint, size: malo ? 22 : 26),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: mint,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Kartice filtera (npr. Sve · Nacrti · Proknjižene) sa kliznom podvlakom.
// opcije: (oznaka, vrijednost); null vrijednost = sve.
class KarticeFiltera extends StatelessWidget {
  final List<(String, String?)> opcije;
  final String? izabrano;
  final ValueChanged<String?>? onIzaberi;

  const KarticeFiltera({
    super.key,
    required this.opcije,
    required this.izabrano,
    required this.onIzaberi,
  });

  static const double _najvise = 116;

  @override
  Widget build(BuildContext context) {
    final indeks = opcije.indexWhere((s) => s.$2 == izabrano);

    // Na uskom ekranu kartice dijele raspoloživu širinu.
    return LayoutBuilder(
      builder: (context, c) {
        final sirina = (c.maxWidth / opcije.length).clamp(0.0, _najvise);
        return SizedBox(
          height: 46,
          width: sirina * opcije.length,
          child: Stack(
            children: [
              // Podvlaka ispod izabrane kartice klizi do nove.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                left: sirina * indeks + sirina * 0.12,
                width: sirina * 0.76,
                bottom: 0,
                height: 4,
                child: Container(
                  decoration: const BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    for (final (naziv, vrijednost) in opcije)
                      SizedBox(
                        width: sirina,
                        child: _KarticaFiltera(
                          naziv: naziv,
                          izabrana: vrijednost == izabrano,
                          onTap: onIzaberi == null
                              ? null
                              : () => onIzaberi!(vrijednost),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KarticaFiltera extends StatefulWidget {
  final String naziv;
  final bool izabrana;
  final VoidCallback? onTap;

  const _KarticaFiltera({
    required this.naziv,
    required this.izabrana,
    this.onTap,
  });

  @override
  State<_KarticaFiltera> createState() => _KarticaFilteraState();
}

class _KarticaFilteraState extends State<_KarticaFiltera> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final aktivno = widget.onTap != null;
    final boja = widget.izabrana
        ? akcentAplikacije
        : _hover && aktivno
        ? MagacinBoje.naslov
        : MagacinBoje.priguseno;

    return Semantics(
      button: true,
      selected: widget.izabrana,
      child: MouseRegion(
        cursor: aktivno && !widget.izabrana
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.izabrana ? null : widget.onTap,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Center(
              child: TweenAnimationBuilder<Color?>(
                duration: hoverTrajanje,
                curve: hoverKriva,
                tween: ColorTween(end: boja),
                builder: (context, c, _) => Text(
                  widget.naziv,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: widget.izabrana
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: c,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Dijalog potvrde (knjiženje, izdavanje, brisanje...).
// Vraća true kad korisnik potvrdi.
class PotvrdaDijalog extends StatelessWidget {
  final String naslov;
  final String tekst;
  final String dugme;
  final IconData ikona;
  final bool opasno;

  const PotvrdaDijalog({
    super.key,
    required this.naslov,
    required this.tekst,
    required this.dugme,
    required this.ikona,
    required this.opasno,
  });

  @override
  Widget build(BuildContext context) {
    final boja = opasno ? MagacinBoje.crvena : MagacinBoje.zelena;
    final pozadina = opasno
        ? MagacinBoje.crvenaSvijetlo
        : MagacinBoje.zelenaSvijetlo;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ZecStanja(
                  poza: opasno ? PozaZeca.sjedi : PozaZeca.racuna,
                  ikona: ikona,
                  boja: boja,
                  pozadina: pozadina,
                  visina: 104,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                naslov,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tekst,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: MagacinBoje.priguseno,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  GlatkoDugme(
                    tekst: 'Odustani',
                    vrsta: VrstaDugmeta.sekundarno,
                    onTap: () => Navigator.pop(context, false),
                  ),
                  GlatkoDugme(
                    tekst: dugme,
                    ikona: ikona,
                    vrsta: opasno ? VrstaDugmeta.opasno : VrstaDugmeta.primarno,
                    onTap: () => Navigator.pop(context, true),
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
