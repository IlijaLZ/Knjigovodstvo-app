import 'dart:async' show Timer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../controllers/navigation_controller.dart';
import 'diktat.dart' show VrstaPolja;
import 'diktat_u_polje.dart';
import 'glasovne_komande.dart';

// Glasovne komande: ⌘⇧Space ili klik na zeca -> slušaj -> otvori ekran ili
// diktiraj u polje.

const String _bundleId = 'com.example.knjigovodstvoApp';

// macOS traži dozvolu za mikrofon u ime aplikacije koja je pokrenula
// Kalkulino (VS Code, Terminal). Ona nema opis dozvole u svom Info.plist,
// pa macOS odmah ugasi Kalkulino. Zato ovdje ni ne pokušavamo.
// Rješenje: pokretanje preko tool/pokreni_macos.sh ili direktno Kalkulino.app.
bool get _pokrenutIzDrugeAplikacije {
  if (kIsWeb || !Platform.isMacOS) return false;
  final env = Platform.environment;
  final pokretac = env['__CFBundleIdentifier'];
  if (pokretac != null) return pokretac != _bundleId;
  return env.containsKey('FLUTTER_ROOT');
}

// Jedini jezici na kojima se sluša, po redu želje (latinica prije srpske
// ćirilice). Ako nijedan nije dostupan, ne sluša se uopšte — paket bi
// inače tiho prešao na sistemski jezik (npr. engleski).
const List<String> _zeljeniJezici = [
  'bs_BA',
  'bs-BA',
  'hr_HR',
  'hr-HR',
  'sr_Latn_RS',
  'sr-Latn-RS',
  'sr_RS',
  'sr-RS',
  'sr_ME',
  'sr-ME',
];

class GlasovniController extends GetxController {
  final SpeechToText _govor = SpeechToText();
  bool _inicijalizovano = false;
  String? _jezik;

  final RxBool slusa = false.obs;

  // Šta je korisnik rekao (uživo dok priča).
  final RxString tekst = ''.obs;

  // Zec: raspoloženje (null = sakriven) i šta kaže.
  final Rxn<ZecRaspolozenje> zec = Rxn<ZecRaspolozenje>();
  final RxString zecTekst = ''.obs;

  // Jačina glasa 0..1 (za talase i sjaj oko zeca).
  final RxDouble nivo = 0.0.obs;
  double _nivoMin = 0, _nivoMax = 0;

  Timer? _sakrivanje;

  // Diktiranje u polje (kad je polje za unos u fokusu); null = komande.
  DiktatSesija? _diktat;
  Future<void> _diktatLanac = Future.value();
  final RxnString diktatPolje = RxnString();

  @override
  void onInit() {
    super.onInit();
    HardwareKeyboard.instance.addHandler(_precica);
  }

  // ⌘⇧Space (Ctrl+Shift+Space na Windowsu/Linuxu): slušaj / prestani.
  bool _precica(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.space) {
      return false;
    }
    final k = HardwareKeyboard.instance;
    final mod = !kIsWeb && Platform.isMacOS
        ? k.isMetaPressed
        : k.isControlPressed;
    if (!mod || !k.isShiftPressed) return false;
    prekidac();
    return true;
  }

  void kaze(String t, [ZecRaspolozenje r = ZecRaspolozenje.prica]) {
    zecTekst.value = t;
    zec.value = r;
    _sakrivanje?.cancel();
    final trajanje = switch (r) {
      ZecRaspolozenje.slusa ||
      ZecRaspolozenje.pise ||
      ZecRaspolozenje.racuna => null,
      ZecRaspolozenje.klik => const Duration(milliseconds: 2600),
      _ => const Duration(seconds: 6),
    };
    if (trajanje != null) _sakrivanje = Timer(trajanje, sakrij);
  }

  void sakrij() {
    _sakrivanje?.cancel();
    if (slusa.value) _govor.stop();
    zec.value = null;
  }

  Future<bool> _pripremi() async {
    if (_inicijalizovano) return true;
    _inicijalizovano = await _govor.initialize(
      onStatus: _naStatus,
      onError: _naGresku,
    );
    if (_inicijalizovano) {
      final jezici = await _govor.locales();
      final ids = jezici.map((l) => l.localeId).toSet();
      _jezik = _zeljeniJezici.firstWhereOrNull(ids.contains);
      debugPrint('[glas] izabran jezik: $_jezik (od ${ids.length} jezika)');
    } else {
      debugPrint('[glas] initialize nije uspio');
    }
    return _inicijalizovano;
  }

  Future<void> prekidac() async {
    if (slusa.value) {
      await _govor.stop();
      return;
    }
    // Polje u fokusu se uzima odmah, prije bilo čega asinhronog.
    final diktat = DiktatSesija.izFokusa();
    if (_pokrenutIzDrugeAplikacije) {
      kaze(
        'Ne čujem te kad me pokreneš iz VS Code-a ili terminala — macOS bi me '
        'ugasio. Pokreni me sa tool/pokreni_macos.sh.',
        ZecRaspolozenje.greska,
      );
      return;
    }
    if (!await _pripremi()) {
      kaze(
        'Ne čujem te — mikrofon ili prepoznavanje govora nije dozvoljeno.',
        ZecRaspolozenje.greska,
      );
      return;
    }
    if (_jezik == null) {
      kaze(
        'Na ovom uređaju nema prepoznavanja govora za naš jezik, a na '
        'drugom jeziku ne slušam.',
        ZecRaspolozenje.greska,
      );
      return;
    }
    tekst.value = '';
    _nivoMin = 0;
    _nivoMax = 0;
    nivo.value = 0;
    _diktat = diktat;
    _diktatLanac = Future.value();
    diktatPolje.value = diktat?.oznaka;
    if (diktat != null) {
      kaze('Diktiraj u „${diktat.oznaka}”.', ZecRaspolozenje.pise);
    } else {
      kaze('Slušam te! Šta da otvorim?', ZecRaspolozenje.slusa);
    }
    _izvrseno = false;
    _ponovljeno = false;
    _imaKonacan = false;
    _odgoda?.cancel();
    await _slusaj();
  }

  // Jedan automatski ponovni pokušaj kod prolaznih grešaka (veza sa Apple/
  // Google serverom za prepoznavanje govora).
  bool _ponovljeno = false;

  // Apple zna poslati grešku i nakon konačnog rezultata; tada je ignorišemo.
  bool _imaKonacan = false;

  Future<void> _slusaj() async {
    slusa.value = true;
    try {
      final krenulo = await _govor.listen(
        onResult: _naRezultat,
        onSoundLevelChange: _naNivo,
        listenOptions: SpeechListenOptions(
          localeId: _jezik,
          // Diktat više polja ("… dalje …") traje duže od komande.
          listenFor: Duration(seconds: _diktat != null ? 40 : 8),
          pauseFor: const Duration(seconds: 3),
          listenMode: _diktat != null
              ? ListenMode.dictation
              : ListenMode.confirmation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
      debugPrint('[glas] listen jezik=$_jezik krenulo=$krenulo');
    } catch (e) {
      debugPrint('[glas] listen izuzetak: $e');
      slusa.value = false;
      kaze('Ne mogu upaliti mikrofon ($e).', ZecRaspolozenje.greska);
    }
  }

  // Nivo zvuka dolazi u različitim jedinicama po platformi, pa se
  // normalizuje prema najtišem/najglasnijem u ovoj sesiji.
  void _naNivo(double n) {
    if (_nivoMin == 0 && _nivoMax == 0) {
      _nivoMin = n;
      _nivoMax = n + 0.001;
    }
    if (n < _nivoMin) _nivoMin = n;
    if (n > _nivoMax) _nivoMax = n;
    final novi = ((n - _nivoMin) / (_nivoMax - _nivoMin)).clamp(0.0, 1.0);
    nivo.value = nivo.value * 0.55 + novi * 0.45;
  }

  // Kratka pauza poslije posljednje riječi prije otvaranja ekrana, da
  // "kalkulacija…" ne otvori nabavne cijene prije nego se kaže "…koštanja".
  Timer? _odgoda;

  void _naRezultat(SpeechRecognitionResult r) {
    tekst.value = ispraviPrikaz(r.recognizedWords);
    if (_diktat != null) {
      _naDiktat(r);
      return;
    }
    _odgoda?.cancel();
    final komanda = pronadjiKomandu(r.recognizedWords);
    debugPrint('[glas] "${r.recognizedWords}" -> ${komanda?.naziv}');
    if (r.finalResult) {
      _imaKonacan = true;
      if (komanda != null) {
        _izvrsi(komanda, r.recognizedWords);
      } else {
        _nijeRazumio(r.recognizedWords);
      }
    } else if (komanda != null) {
      // Kod komandi sa nastavkom (naziv artikla) čeka se malo duže.
      // Rezervno poklapanje ("trebao") čeka najduže: možda slijedi
      // "…bih stanje magacina".
      final n = normalizuj(r.recognizedWords);
      final rezervno = !komanda.odgovara(n) && !komanda.priblizno(n);
      // Poslije samog "u excel" obično slijedi ekran ("…radne naloge"),
      // pa se tu čeka najduže. I kod otvaranja ekrana se čeka malo duže,
      // jer "excel" može doći i na kraju ("radne naloge u excel").
      final cekaj = identical(komanda, komandaIzvozaTrenutnog)
          ? 2000
          : rezervno
          ? 1500
          : komanda.akcija != null
          ? 1300
          : 1100;
      final izgovoreno = r.recognizedWords;
      _odgoda = Timer(Duration(milliseconds: cekaj), () {
        _govor.stop();
        _izvrsi(komanda, izgovoreno);
      });
    }
  }

  bool _izvrseno = false;

  void _naDiktat(SpeechRecognitionResult r) {
    final d = _diktat!;
    final t = r.recognizedWords;
    debugPrint('[glas] diktat "$t"');
    // Rezultati se primjenjuju redom (prelazak u sljedeće polje je async).
    _diktatLanac = _diktatLanac.then((_) async {
      await d.primijeni(t);
      diktatPolje.value = d.oznakaTrenutnog;
    });
    if (r.finalResult) {
      _imaKonacan = true;
      _diktatLanac.then((_) => _zavrsiDiktat());
    }
  }

  void _zavrsiDiktat() {
    final d = _diktat;
    if (d == null || _izvrseno) return;
    _izvrseno = true;
    d.vratiPrazna();
    final upisano = d.upisano;
    if (upisano.isEmpty) {
      d.ponisti();
      kaze(
        tekst.value.trim().isEmpty
            ? 'Nisam ništa čuo. Klikni me pa probaj ponovo.'
            : d.vrsta == VrstaPolja.broj
            ? 'U „${d.oznaka}” ide broj, a nisam ga čuo. Probaj ponovo.'
            : 'Nisam skontao šta da upišem. Probaj ponovo.',
        ZecRaspolozenje.zbunjen,
      );
    } else if (upisano.length == 1) {
      final (oznaka, vrijednost, obrisano) = upisano.first;
      kaze(
        obrisano
            ? 'Klik! Obrisao sam „$oznaka”.'
            : 'Klik! „$oznaka”: $vrijednost',
        ZecRaspolozenje.klik,
      );
    } else {
      kaze(
        'Klik! Popunio sam ${upisano.length} polja: '
        '${upisano.map((u) => u.$1).join(', ')}.',
        ZecRaspolozenje.klik,
      );
    }
    _diktat = null;
    diktatPolje.value = null;
  }

  Future<void> _izvrsi(GlasovnaKomanda k, String izgovoreno) async {
    if (_izvrseno) return;
    _izvrseno = true;
    final akcija = k.akcija;
    // "Zatvori" sam zatvara, a "izvezi u excel" radi na ekranu navrhu;
    // ostale komande vode na ekran glavnog prozora, pa prvo treba zatvoriti
    // ono što je otvoreno preko njega (unos kalkulacije, kartica…), inače
    // se promjena ne vidi.
    if (k.naGlavni && !await naGlavniEkran()) {
      kaze(
        'Sačekaj da se dokument sačuva, pa ću te prebaciti.',
        ZecRaspolozenje.zbunjen,
      );
      return;
    }
    if (akcija != null) {
      akcija(izgovoreno, kaze);
      return;
    }
    final nav = Get.find<NavigationController>();
    k.otvori(nav);
    kaze(k.napomena ?? 'Klik! Otvaram ${k.naziv}.', ZecRaspolozenje.klik);
    final ruta = k.ruta;
    if (ruta != null) _dodaj(nav, k, ruta);
  }

  // Zatvara ekrane i dijaloge otvorene preko glavnog prozora, redovnim
  // putem (kao dugme nazad), pa ekran za unos sam odluči: dok čuva, ne
  // pušta. Vraća false ako nešto nije htjelo da se zatvori.
  Future<bool> naGlavniEkran() async {
    final navigator = Get.key.currentState;
    if (navigator == null) return true;
    for (var i = 0; i < 8 && navigator.canPop(); i++) {
      await navigator.maybePop();
    }
    return !navigator.canPop();
  }

  // Ekran za dodavanje preko liste; nakon čuvanja lista se ponovo učita
  // (kao kad se klikne "Novi …" na samoj listi).
  Future<void> _dodaj(
    NavigationController nav,
    GlasovnaKomanda k,
    String ruta,
  ) async {
    final sacuvano = await Get.toNamed(ruta);
    if (sacuvano != true) return;
    // Lista se učitava pri otvaranju, pa je kratko zamijenimo da se
    // napravi iznova i pokaže novi dokument.
    nav.openPocetna();
    await WidgetsBinding.instance.endOfFrame;
    k.otvori(nav);
    if (k.sacuvano != null) kaze(k.sacuvano!, ZecRaspolozenje.klik);
  }

  void _naStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      slusa.value = false;
      nivo.value = 0;
      // Ako se slušanje završi bez rezultata i bez greške (npr. korisnik
      // klikne da prekine), zec ne smije ostati da "sluša".
      Timer(const Duration(milliseconds: 900), () {
        if (slusa.value) return;
        if (_diktat != null) {
          _diktatLanac.then((_) => _zavrsiDiktat());
        } else if (zec.value == ZecRaspolozenje.slusa) {
          _nijeRazumio(tekst.value);
        }
      });
    }
  }

  void _nijeRazumio(String t) {
    kaze(
      t.trim().isEmpty
          ? 'Nisam ništa čuo. Klikni me pa probaj ponovo.'
          : 'Hmm, to nisam skontao. Probaj npr. „otvori trebovanja”.',
      ZecRaspolozenje.zbunjen,
    );
  }

  void _naGresku(SpeechRecognitionError e) {
    debugPrint('[glas] greška: ${e.errorMsg} (trajna: ${e.permanent})');
    if (_izvrseno || _imaKonacan || e.errorMsg == 'error_request_cancelled') {
      slusa.value = false;
      return;
    }
    if (_prolazneGreske.contains(e.errorMsg) && !_ponovljeno) {
      _ponovljeno = true;
      Future.delayed(const Duration(milliseconds: 400), _slusaj);
      return;
    }
    slusa.value = false;
    if (e.errorMsg == 'error_no_match' ||
        e.errorMsg == 'error_speech_timeout') {
      _nijeRazumio(tekst.value);
    } else {
      kaze(_opisGreske(e.errorMsg), ZecRaspolozenje.greska);
    }
  }

  static const _prolazneGreske = {
    'error_retry',
    'error_network',
    'error_server',
    'error_speech_recognizer_connection_invalidated',
    'error_speech_recognizer_connection_interrupted',
    'error_speech_recognizer_already_active',
    'error_busy',
  };

  String _opisGreske(String kod) {
    switch (kod) {
      case 'error_no_match':
      case 'error_speech_timeout':
        return 'Nisam razumio. Pokušajte ponovo.';
      case 'error_speech_recognizer_disabled':
        return 'Prepoznavanje govora je isključeno. Uključi Siri/diktiranje u '
            'System Settings.';
      case 'error_speech_recognizer_request_not_authorized':
      case 'error_permission':
        return 'Nema dozvole za prepoznavanje govora. Dozvoli je u System '
            'Settings → Privacy & Security → Speech Recognition.';
      case 'error_listen_failed':
      case 'error_audio':
        return 'Ne mogu pokrenuti mikrofon. Provjeri dozvolu za mikrofon u '
            'System Settings → Privacy & Security → Microphone.';
      case 'error_assets_not_installed':
      case 'error_language_unavailable':
      case 'error_language_not_supported':
        return 'Jezik za prepoznavanje govora nije dostupan na ovom uređaju.';
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
      case 'error_retry':
        return 'Prepoznavanje govora treba internet. Provjeri vezu i pokušaj '
            'ponovo.';
      default:
        return 'Greška pri prepoznavanju govora ($kod).';
    }
  }

  @override
  void onClose() {
    HardwareKeyboard.instance.removeHandler(_precica);
    _odgoda?.cancel();
    _sakrivanje?.cancel();
    _govor.cancel();
    super.onClose();
  }
}

// Jedan kontroler za zeca i prečicu ⌘⇧Space (pravi ga ZecSloj pri
// pokretanju aplikacije).
GlasovniController glasovniController() =>
    Get.isRegistered<GlasovniController>()
    ? Get.find<GlasovniController>()
    : Get.put(GlasovniController(), permanent: true);
