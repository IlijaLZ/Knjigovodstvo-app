# Pravi ikone aplikacije za sve platforme iz slike zeca (treba Pillow).
# Pokretanje iz korijena projekta:
#   python3 tool/napravi_ikone.py assets/ikona/zec_izvor.png . /tmp/pregled.png
import sys
from PIL import Image, ImageDraw, ImageFilter

izvor, projekat = sys.argv[1], sys.argv[2]

zec = Image.open(izvor).convert("RGBA")
zec = zec.crop(zec.split()[3].point(lambda v: 255 if v > 20 else 0).getbbox())

GORE = (0xEE, 0xF9, 0xF5)
DOLE = (0xC9, 0xEE, 0xE0)


def gradijent(n):
    g = Image.new("RGBA", (n, n))
    d = ImageDraw.Draw(g)
    for y in range(n):
        t = y / (n - 1)
        c = tuple(round(GORE[i] + (DOLE[i] - GORE[i]) * t) for i in range(3))
        d.line([(0, y), (n, y)], fill=c + (255,))
    return g


# Prikazuje se samo gornji dio zeca (glava, majica i vrh kalkulatora);
# donja ivica isječka leži na donjoj ivici pločice.
KROJ = 0.68
poprsje = zec.crop((0, 0, zec.width, round(zec.height * KROJ)))


def zalijepi_zeca(platno, okvir, maska, visina_udio):
    x0, y0, x1, y1 = okvir
    h = round((y1 - y0) * visina_udio)
    w = round(poprsje.width * h / poprsje.height)
    z = poprsje.resize((w, h), Image.LANCZOS)
    sloj = Image.new("RGBA", platno.size, (0, 0, 0, 0))
    sloj.alpha_composite(z, (round((x0 + x1 - w) / 2), y1 - h))
    # Odsijeci sve što izlazi van pločice.
    puna = Image.new("L", platno.size, 0)
    puna.paste(maska, (x0, y0))
    sloj.putalpha(Image.composite(sloj.split()[3], Image.new("L", platno.size, 0), puna))
    platno.alpha_composite(sloj)


def ikona(n, *, margina=0.0, radijus=0.0, visina_udio=0.92, providno=True):
    """margina/radijus su udio veličine platna."""
    S = 1024
    platno = Image.new("RGBA", (S, S), (0, 0, 0, 0) if providno else DOLE + (255,))
    m = round(S * margina)
    vel = S - 2 * m
    maska = Image.new("L", (vel, vel), 0)
    ImageDraw.Draw(maska).rounded_rectangle([0, 0, vel - 1, vel - 1], radius=round(S * radijus), fill=255)
    if margina > 0:
        # Sjenka pločice (macOS stil).
        sj = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sm = Image.new("L", (S, S), 0)
        ImageDraw.Draw(sm).rounded_rectangle([m, m + S * 0.012, m + vel, m + vel + S * 0.012], radius=round(S * radijus), fill=90)
        sj.putalpha(sm.filter(ImageFilter.GaussianBlur(S * 0.018)))
        platno.alpha_composite(sj)
    plocica = gradijent(vel)
    plocica.putalpha(maska)
    platno.alpha_composite(plocica, (m, m))
    zalijepi_zeca(platno, (m, m, m + vel, m + vel), maska, visina_udio)
    # Tanak svijetli rub pločice.
    if radijus > 0:
        ImageDraw.Draw(platno).rounded_rectangle([m, m, m + vel - 1, m + vel - 1], radius=round(S * radijus), outline=(255, 255, 255, 140), width=max(2, S // 256))
    out = platno.resize((n, n), Image.LANCZOS)
    if not providno:
        out = out.convert("RGB")
    return out


P = projekat
# Glavna slika (u projektu, za buduće izmjene).
ikona(1024, margina=0.0, radijus=0.0, visina_udio=0.92, providno=False).save(f"{P}/assets/ikona/ikona_aplikacije.png")

# macOS: pločica po Apple mreži (824/1024, zaobljena).
for n in [16, 32, 64, 128, 256, 512, 1024]:
    ikona(n, margina=100 / 1024, radijus=185 / 1024, visina_udio=0.92).save(
        f"{P}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{n}.png")

# iOS: puni kvadrat bez providnosti (sistem sam zaobljava).
ios = {
    "20x20@1x": 20, "20x20@2x": 40, "20x20@3x": 60, "29x29@1x": 29, "29x29@2x": 58, "29x29@3x": 87,
    "40x40@1x": 40, "40x40@2x": 80, "40x40@3x": 120, "60x60@2x": 120, "60x60@3x": 180,
    "76x76@1x": 76, "76x76@2x": 152, "83.5x83.5@2x": 167, "1024x1024@1x": 1024,
}
for ime, n in ios.items():
    ikona(n, providno=False).save(f"{P}/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{ime}.png")

# Android: zaobljeni kvadrat.
for folder, n in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    ikona(n, margina=0.04, radijus=0.2, visina_udio=0.92).save(f"{P}/android/app/src/main/res/mipmap-{folder}/ic_launcher.png")

# Web.
ikona(32, margina=0.0, radijus=0.2, visina_udio=0.92).save(f"{P}/web/favicon.png")
for n in [192, 512]:
    ikona(n, margina=0.0, radijus=0.2, visina_udio=0.92).save(f"{P}/web/icons/Icon-{n}.png")
    # Maskable: zec u sigurnoj zoni (krug 80%).
    ikona(n, providno=False, visina_udio=0.8).save(f"{P}/web/icons/Icon-maskable-{n}.png")

# Windows .ico (više veličina u jednom fajlu).
win = ikona(256, margina=0.03, radijus=0.2, visina_udio=0.92)
win.save(f"{P}/windows/runner/resources/app_icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

# Pregled za provjeru.
pregled = Image.new("RGBA", (1100, 300), (255, 255, 255, 255))
x = 20
for n, slika in [(256, Image.open(f"{P}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png")),
                 (180, Image.open(f"{P}/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png")),
                 (192, Image.open(f"{P}/web/icons/Icon-maskable-192.png")),
                 (64, Image.open(f"{P}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png")),
                 (32, Image.open(f"{P}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png")),
                 (32, Image.open(f"{P}/web/favicon.png"))]:
    pregled.alpha_composite(slika.convert("RGBA"), (x, 20))
    x += n + 30
pregled.save(sys.argv[3])
print("gotovo")
