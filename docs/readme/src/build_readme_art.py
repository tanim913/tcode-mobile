#!/usr/bin/env python3
"""Build the README artwork (docs/readme/*.svg) for Tcode Mobile.

The art uses the app's own look: its dark editor surface, the #4D9FFF accent,
the `< >` mark from the launcher icon, and JetBrains Mono, the editor's
default font.

All text is outlined to paths. GitHub shows an SVG as an <img>, and an <img>
cannot load web fonts. The font files are the ones the app already bundles
(assets/fonts, SIL Open Font License).

    python3 docs/readme/src/build_readme_art.py      # needs: pip install fonttools
"""
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "docs" / "readme"
FONTS = ROOT / "assets" / "fonts"

# Colours from the app's palettes (lib/core/theme). The syntax colours follow
# the default editor theme, so the code in the banner looks like the app.
THEMES = {
    "dark": dict(
        bg="#0F1217", grid="#171B22", title="#F2F4F8", sub="#9AA4B5",
        accent="#4D9FFF", badge="#16273D", chip="#1A1F28", chip_text="#C9D1DE",
        phone="#1B2029", phone_edge="#2A313D", screen="#12151B", bar="#1A1E26",
        gutter="#4B5566", text="#D6DCE6", kw="#C792EA", str="#A5D6A7",
        type="#FFCB6B", com="#6B7688", fn="#82AAFF", num="#F78C6C",
        key="#202633", key_text="#C9D1DE", active="#4D9FFF", line="#171C24",
    ),
    "light": dict(
        bg="#F4F6FA", grid="#E9EDF3", title="#12151B", sub="#4A5566",
        accent="#1F74E0", badge="#DCE9FB", chip="#FFFFFF", chip_text="#2B3444",
        phone="#1B2029", phone_edge="#2A313D", screen="#12151B", bar="#1A1E26",
        gutter="#4B5566", text="#D6DCE6", kw="#C792EA", str="#A5D6A7",
        type="#FFCB6B", com="#6B7688", fn="#82AAFF", num="#F78C6C",
        key="#202633", key_text="#C9D1DE", active="#4D9FFF", line="#171C24",
    ),
}


class Face:
    def __init__(self, path):
        self.font = TTFont(path)
        self.gs = self.font.getGlyphSet()
        self.cmap = self.font.getBestCmap()
        self.upm = self.font["head"].unitsPerEm
        self.hmtx = self.font["hmtx"]

    def width(self, text, size):
        s = size / self.upm
        return sum(self.hmtx[self.cmap.get(ord(c), self.cmap[32])][0] for c in text) * s

    def path(self, text, size, x, y, fill, anchor="start"):
        """Outlines [text] with its baseline at [y]."""
        s = size / self.upm
        w = self.width(text, size)
        x0 = {"start": x, "middle": x - w / 2, "end": x - w}[anchor]
        pen = SVGPathPen(self.gs, ntos=lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
        cx = 0.0
        for ch in text:
            g = self.cmap.get(ord(ch), self.cmap[32])
            self.gs[g].draw(TransformPen(pen, (s, 0, 0, -s, x0 + cx, y)))
            cx += self.hmtx[g][0] * s
        d = pen.getCommands()
        return f'<path d="{d}" fill="{fill}"/>' if d else ""


def svg(w, h, body, title, desc):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" '
        f'height="{h}" role="img" aria-labelledby="t d"><title id="t">{title}</title>'
        f'<desc id="d">{desc}</desc>{body}</svg>\n'
    )


def mark(x, y, size, fill, stroke):
    """The `< >` mark from the launcher icon, as two open chevrons."""
    r = size * 0.22
    cx, cy = x + size / 2, y + size / 2
    a, b = size * 0.16, size * 0.2
    sw = size * 0.075
    left = f"M{cx - a:.1f},{cy - b:.1f} L{cx - a - b:.1f},{cy:.1f} L{cx - a:.1f},{cy + b:.1f}"
    right = f"M{cx + a:.1f},{cy - b:.1f} L{cx + a + b:.1f},{cy:.1f} L{cx + a:.1f},{cy + b:.1f}"
    return (
        f'<rect x="{x}" y="{y}" width="{size}" height="{size}" rx="{r:.1f}" fill="{fill}"/>'
        f'<path d="{left} {right}" fill="none" stroke="{stroke}" stroke-width="{sw:.1f}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
    )


# One line of code is a list of (text, colour key) runs.
CODE = [
    [("import", "kw"), (" ", "text"), ("'package:flutter/material.dart'", "str"), (";", "text")],
    [],
    [("/// Five days of forecast, offline.", "com")],
    [("class", "kw"), (" ", "text"), ("Forecast", "type"), (" ", "text"), ("extends", "kw"),
     (" ", "text"), ("StatelessWidget", "type"), (" {", "text")],
    [("  ", "text"), ("final", "kw"), (" ", "text"), ("List", "type"), ("<", "text"),
     ("int", "type"), ("> highs;", "text")],
    [],
    [("  ", "text"), ("@override", "com")],
    [("  ", "text"), ("Widget", "type"), (" ", "text"), ("build", "fn"), ("(ctx) {", "text")],
    [("    ", "text"), ("return", "kw"), (" ", "text"), ("ListView", "type"), ("(", "text")],
    [("      children: ", "text"), ("[", "text")],
    [("        ", "text"), ("for", "kw"), (" (", "text"), ("final", "kw"), (" t ", "text"),
     ("in", "kw"), (" highs)", "text")],
    [("          ", "text"), ("Text", "type"), ("(", "text"), ("'$t°C'", "str"), ("),", "text")],
    [("      ],", "text")],
    [("    );", "text")],
    [("  }", "text")],
    [("}", "text")],
]


def phone(F, t, x, y):
    """A phone showing the editor: tab, gutter, highlighted code, key row."""
    w, h = 420, 600
    out = [
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="46" fill="{t["phone"]}" '
        f'stroke="{t["phone_edge"]}" stroke-width="2"/>'
    ]
    sx, sy, sw, sh = x + 16, y + 16, w - 32, h - 32
    out.append(f'<rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="32" fill="{t["screen"]}"/>')
    # App bar with the file name, then the tab strip.
    out.append(f'<rect x="{sx}" y="{sy}" width="{sw}" height="84" rx="32" fill="{t["bar"]}"/>')
    out.append(f'<rect x="{sx}" y="{sy + 50}" width="{sw}" height="34" fill="{t["bar"]}"/>')
    out.append(F["b"].path("forecast.dart", 17, sx + 28, sy + 58, t["text"]))
    out.append(mark(sx + sw - 60, sy + 34, 30, "#16273D", t["active"]))
    out.append(f'<rect x="{sx}" y="{sy + 84}" width="150" height="3" fill="{t["active"]}"/>')
    # Code.
    size, lh = 12.6, 22
    top = sy + 118
    for i, runs in enumerate(CODE):
        by = top + i * lh
        if i == 7:
            out.append(f'<rect x="{sx}" y="{by - 15}" width="{sw}" height="{lh}" fill="{t["line"]}"/>')
        out.append(F["r"].path(str(i + 1), size, sx + 34, by, t["gutter"], anchor="end"))
        cx = sx + 48
        for text, key in runs:
            out.append(F["r"].path(text, size, cx, by, t[key]))
            cx += F["r"].width(text, size)
    # The accessory key row, the part a phone keyboard does not have.
    keys = ["Tab", "{", "}", "(", ")", ";", "=>"]
    ky = sy + sh - 62
    out.append(f'<rect x="{sx}" y="{ky - 14}" width="{sw}" height="76" fill="{t["bar"]}"/>')
    out.append(f'<rect x="{sx}" y="{ky + 30}" width="{sw}" height="32" rx="0" fill="{t["bar"]}"/>')
    kx, kw, gap = sx + 14, 44, 7
    for i, k in enumerate(keys):
        width = 62 if k == "Tab" else kw
        out.append(f'<rect x="{kx}" y="{ky}" width="{width}" height="40" rx="9" fill="{t["key"]}"/>')
        out.append(F["b"].path(k, 15, kx + width / 2, ky + 26, t["key_text"], anchor="middle"))
        kx += width + gap
    return "".join(out)


def banner(F, t):
    W, H = 1280, 640
    body = [f'<rect width="{W}" height="{H}" fill="{t["bg"]}"/>']
    # A faint editor grid: every 32px, like character cells.
    grid = "".join(
        f'<line x1="0" y1="{y}" x2="{W}" y2="{y}" stroke="{t["grid"]}" stroke-width="1"/>'
        for y in range(16, H, 32)
    )
    body.append(grid)
    body.append(mark(84, 132, 84, t["badge"], t["accent"]))
    body.append(F["b"].path("Tcode Mobile", 70, 80, 312, t["title"]))
    body.append(F["r"].path("A real code editor for your phone.", 25, 84, 370, t["sub"]))
    body.append(F["r"].path("Offline. Touch-first. Open source.", 25, 84, 406, t["sub"]))
    chips = ["27 languages", "Run HTML · JS · Python", "Pull requests"]
    cx = 84
    for c in chips:
        w = F["b"].width(c, 17) + 36
        body.append(f'<rect x="{cx}" y="{458}" width="{w:.0f}" height="42" rx="21" fill="{t["chip"]}" '
                    f'stroke="{t["grid"]}" stroke-width="1.5"/>')
        body.append(F["b"].path(c, 17, cx + 18, 485, t["chip_text"]))
        cx += w + 12
    body.append(phone(F, t, 790, 20))
    return svg(W, H, "".join(body), "Tcode Mobile",
               "Tcode Mobile: a real code editor for your phone. Offline, touch-first, open "
               "source. A phone shows Dart code with syntax highlighting and a row of coding "
               "keys above the keyboard.")


def main():
    F = {"r": Face(FONTS / "JetBrainsMono-Regular.ttf"), "b": Face(FONTS / "JetBrainsMono-Bold.ttf")}
    OUT.mkdir(parents=True, exist_ok=True)
    for name, t in THEMES.items():
        suffix = "-dark" if name == "dark" else ""
        (OUT / f"banner{suffix}.svg").write_text(banner(F, t))
    print("wrote", sorted(p.name for p in OUT.glob("*.svg")))


if __name__ == "__main__":
    main()
