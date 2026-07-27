#!/usr/bin/env python3
"""Render f00tils brand PNGs and terminal screenshots (color).

Writes into:
  press-kit/
  site/assets/
  docs/images/   (README screenshots)

Requires: pillow, local ./asm/f00
"""
from __future__ import annotations

import os
import pty
import re
import select
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASM = ROOT / "asm"
F00 = ASM / "f00"

# Brand palette (matches site/styles.css)
BG = (10, 12, 15)
BG_ELEV = (17, 21, 27)
BG_PANEL = (20, 26, 34)
BORDER = (30, 38, 51)
TEXT = (232, 237, 244)
TEXT_DIM = (139, 149, 168)
ACCENT = (61, 255, 154)  # #3dff9a
ACCENT_HOT = (125, 255, 224)
WARN = (240, 193, 74)
RED = (255, 107, 129)
BLUE = (102, 179, 255)
CYAN = (80, 220, 230)
MAGENTA = (200, 140, 255)
YELLOW = (240, 193, 74)
GREEN = (61, 255, 154)
ORANGE = (255, 167, 92)
WHITE = (232, 237, 244)
BLACK = (0, 0, 0)

ANSI_FG = {
    30: (90, 98, 110),
    31: RED,
    32: GREEN,
    33: YELLOW,
    34: BLUE,
    35: MAGENTA,
    36: CYAN,
    37: TEXT_DIM,
    39: TEXT,
    90: (92, 102, 120),
    91: (255, 140, 160),
    92: (100, 255, 180),
    93: (255, 220, 120),
    94: (130, 190, 255),
    95: (220, 170, 255),
    96: (120, 240, 245),
    97: WHITE,
}

# bold + color variants often used with 01;3x
SGR_RE = re.compile(r"\x1b\[([0-9;]*)m")


def find_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    # Mono for ASCII/ANSI text (not color-emoji CBDT fonts).
    candidates = [
        "/usr/share/fonts/noto/NotoSansMono-Bold.ttf" if bold else "",
        "/usr/share/fonts/noto/NotoSansMono-Regular.ttf",
        "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf" if bold else "",
        "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf",
    ]
    if bold:
        candidates = [
            "/usr/share/fonts/noto/NotoSansMono-Bold.ttf",
            "/usr/share/fonts/noto/NotoSansMono-Medium.ttf",
            "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf",
            *candidates,
        ]
    for c in candidates:
        if c and Path(c).is_file():
            try:
                return ImageFont.truetype(c, size=size)
            except OSError:
                pass
    return ImageFont.load_default()


def find_emoji_font(pixel_size: int = 109) -> ImageFont.FreeTypeFont | None:
    # Noto Color Emoji is CBDT and only accepts its design size (109).
    for c in (
        "/usr/share/fonts/noto/NotoColorEmoji.ttf",
        "/usr/share/fonts/TTF/NotoColorEmoji.ttf",
    ):
        if Path(c).is_file():
            try:
                return ImageFont.truetype(c, size=pixel_size)
            except OSError:
                continue
    return None


def is_emoji_char(ch: str) -> bool:
    o = ord(ch)
    return (
        o >= 0x1F300
        or o in (0x2699, 0xFE0F, 0x200D)
        or 0x2600 <= o <= 0x27BF
        or 0x1F000 <= o <= 0x1FAFF
    )


def draw_mixed_text(
    img: Image.Image,
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    font,
    fill: tuple[int, int, int],
    emoji_font,
    emoji_px: int = 16,
) -> int:
    """Draw text using mono font + optional color-emoji font. Returns advance width."""
    x, y = xy
    if not text:
        return 0
    i = 0
    while i < len(text):
        ch = text[i]
        # gather emoji cluster (emoji + FE0F)
        if is_emoji_char(ch) and emoji_font is not None:
            j = i + 1
            while j < len(text) and (is_emoji_char(text[j]) or ord(text[j]) == 0xFE0F):
                j += 1
            cluster = text[i:j]
            # render at native size then scale
            try:
                bbox = emoji_font.getbbox(cluster)
                ew = max(1, (bbox[2] - bbox[0]) if bbox else emoji_px)
                eh = max(1, (bbox[3] - bbox[1]) if bbox else emoji_px)
                tile = Image.new("RGBA", (ew + 4, eh + 4), (0, 0, 0, 0))
                td = ImageDraw.Draw(tile)
                td.text((2, 2), cluster, font=emoji_font, embedded_color=True)
                scale = emoji_px / max(eh, 1)
                nw = max(1, int((ew + 4) * scale))
                nh = max(1, int((eh + 4) * scale))
                tile = tile.resize((nw, nh), Image.Resampling.LANCZOS)
                img.paste(tile, (x, y - 1), tile)
                x += nw + 2
            except Exception:
                draw.text((x, y), "·", fill=fill, font=font)
                tw, _ = measure_text(draw, "·", font)
                x += tw
            i = j
            continue
        # ascii / mono run
        j = i + 1
        while j < len(text) and not is_emoji_char(text[j]):
            j += 1
        run = text[i:j]
        draw.text((x, y), run, fill=fill, font=font)
        tw, _ = measure_text(draw, run, font)
        x += tw
        i = j
    return x - xy[0]


def resolve_bin(argv0: str) -> str:
    if argv0.startswith("/"):
        return argv0
    link = ASM / argv0
    if link.exists():
        return str(link)
    if argv0.startswith("f00-") and F00.exists():
        return str(F00)
    return argv0


def color_env(extra: dict | None = None) -> dict[str, str]:
    """Force a color-capable terminal environment (never NO_COLOR)."""
    e = os.environ.copy()
    e.pop("NO_COLOR", None)
    e["TERM"] = "xterm-256color"
    e["COLORTERM"] = "truecolor"
    e["FORCE_COLOR"] = "3"
    e["CLICOLOR"] = "1"
    e["CLICOLOR_FORCE"] = "1"
    e["F00_NERD"] = e.get("F00_NERD", "1")
    # Prefer site-matching theme when available
    theme = ROOT / "site" / "themes" / "tokyo-night.theme"
    if theme.is_file():
        e.setdefault("F00_THEME", "tokyo-night")
    if extra:
        e.update({k: str(v) for k, v in extra.items()})
    return e


def tool_argv(argv: list[str]) -> list[str]:
    """Resolve multicall symlink so argv0 basename selects the tool."""
    a0 = argv[0]
    if a0.startswith("f00-") and not a0.startswith("/"):
        link = ASM / a0
        if link.exists():
            return [str(link)] + argv[1:]
    return [resolve_bin(a0)] + argv[1:]


def run_f00(argv: list[str], env: dict | None = None, *, use_pty: bool = True) -> str:
    """Run f00 tool. Default: real PTY (no shell) so is_tty chrome/color engages."""
    e = color_env(env)
    real = tool_argv(argv)

    if not use_pty:
        r = subprocess.run(
            real,
            cwd=str(ASM),
            env=e,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        return r.stdout.decode("utf-8", "replace")

    # Direct PTY — no shell (avoids zsh nomatch on globs like *.sh)
    master, slave = pty.openpty()
    try:
        # Make slave look like a reasonably wide terminal
        try:
            import fcntl
            import struct
            import termios

            winsz = struct.pack("HHHH", 40, 120, 0, 0)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, winsz)
        except Exception:
            pass
        proc = subprocess.Popen(
            real,
            cwd=str(ASM),
            env=e,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            close_fds=True,
            start_new_session=True,
        )
        os.close(slave)
        slave = -1
        chunks: list[bytes] = []
        deadline = time.time() + 12.0
        while True:
            if time.time() > deadline:
                proc.kill()
                break
            ready, _, _ = select.select([master], [], [], 0.15)
            if ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                chunks.append(data)
            elif proc.poll() is not None:
                # drain remaining
                while True:
                    ready, _, _ = select.select([master], [], [], 0.05)
                    if not ready:
                        break
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        data = b""
                    if not data:
                        break
                    chunks.append(data)
                break
        try:
            proc.wait(timeout=2)
        except Exception:
            proc.kill()
    finally:
        try:
            os.close(master)
        except OSError:
            pass
        if slave >= 0:
            try:
                os.close(slave)
            except OSError:
                pass

    out = b"".join(chunks).decode("utf-8", "replace")
    out = out.replace("\r\n", "\n").replace("\r", "\n")
    # drop stray C0 controls except \n \t ESC
    out = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1a\x1c-\x1f]", "", out)
    return out


def parse_ansi_line(line: str) -> list[tuple[str, tuple[int, int, int], bool]]:
    """Return list of (text, fg_rgb, bold). Supports classic + truecolor + dim."""
    parts: list[tuple[str, tuple[int, int, int], bool]] = []
    fg = TEXT
    bold = False
    dim = False
    pos = 0

    def apply_dim(c: tuple[int, int, int]) -> tuple[int, int, int]:
        if not dim:
            return c
        return (max(0, c[0] * 2 // 3), max(0, c[1] * 2 // 3), max(0, c[2] * 2 // 3))

    for m in SGR_RE.finditer(line):
        if m.start() > pos:
            parts.append((line[pos : m.start()], apply_dim(fg), bold))
        codes_raw = m.group(1)
        codes = [c for c in codes_raw.split(";") if c != ""] if codes_raw else ["0"]
        i = 0
        while i < len(codes):
            try:
                code = int(codes[i])
            except ValueError:
                i += 1
                continue
            if code == 0:
                fg, bold, dim = TEXT, False, False
            elif code == 1:
                bold = True
            elif code == 2:
                dim = True
            elif code == 22:
                bold = False
                dim = False
            elif code == 39:
                fg = TEXT
            elif code in ANSI_FG:
                fg = ANSI_FG[code]
            elif code == 38 and i + 1 < len(codes):
                mode = codes[i + 1]
                if mode == "2" and i + 4 < len(codes):
                    try:
                        fg = (int(codes[i + 2]), int(codes[i + 3]), int(codes[i + 4]))
                    except ValueError:
                        pass
                    i += 4
                elif mode == "5" and i + 2 < len(codes):
                    # 256-color: approximate a few common ranges
                    try:
                        n = int(codes[i + 2])
                    except ValueError:
                        n = 7
                    if 16 <= n <= 231:
                        n0 = n - 16
                        r = (n0 // 36) * 51
                        g = ((n0 // 6) % 6) * 51
                        b = (n0 % 6) * 51
                        fg = (r, g, b)
                    elif n >= 232:
                        v = 8 + (n - 232) * 10
                        fg = (v, v, v)
                    else:
                        fg = ANSI_FG.get(30 + (n % 8), TEXT)
                    i += 2
                else:
                    i += 1
            i += 1
        pos = m.end()
    if pos < len(line):
        parts.append((line[pos:], apply_dim(fg), bold))
    cleaned: list[tuple[str, tuple[int, int, int], bool]] = []
    for text, c, b in parts:
        text = re.sub(r"\x1b\].*?(?:\x07|\x1b\\)", "", text)
        text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
        text = text.replace("\x00", "")
        if text:
            cleaned.append((text, c, b))
    if not cleaned:
        cleaned = [("", TEXT, False)]
    return cleaned


def measure_text(draw: ImageDraw.ImageDraw, text: str, font) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=font)
    return box[2] - box[0], box[3] - box[1]


def render_terminal(
    title: str,
    prompt_lines: list[str],
    body: str,
    out: Path,
    width: int = 980,
    min_height: int = 360,
) -> None:
    """prompt_lines: shell prompts shown before body (plain or with $)."""
    font = find_font(15)
    font_bold = find_font(15, bold=True)
    font_title = find_font(13)
    font_prompt = find_font(15, bold=True)
    emoji_font = find_emoji_font(109)
    emoji_px = 16

    pad_x = 28
    pad_y = 22
    chrome_h = 40
    line_h = 24
    lines = body.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    # trim trailing empties but keep one
    while len(lines) > 1 and lines[-1] == "":
        lines.pop()

    content_lines = len(prompt_lines) + len(lines) + 1
    height = max(min_height, chrome_h + pad_y * 2 + content_lines * line_h + 24)

    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)

    # outer card
    margin = 12
    draw.rounded_rectangle(
        [margin, margin, width - margin, height - margin],
        radius=14,
        fill=BG_ELEV,
        outline=BORDER,
        width=2,
    )
    # title bar
    draw.rounded_rectangle(
        [margin, margin, width - margin, margin + chrome_h],
        radius=14,
        fill=BG_PANEL,
        outline=BORDER,
        width=0,
    )
    draw.rectangle(
        [margin, margin + chrome_h - 10, width - margin, margin + chrome_h],
        fill=BG_PANEL,
    )
    # traffic lights
    for i, col in enumerate([(255, 95, 87), (255, 189, 46), (40, 200, 64)]):
        cx = margin + 22 + i * 18
        cy = margin + chrome_h // 2
        draw.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], fill=col)
    # title
    tw, th = measure_text(draw, title, font_title)
    draw.text(
        ((width - tw) // 2, margin + (chrome_h - th) // 2 - 1),
        title,
        fill=TEXT_DIM,
        font=font_title,
    )

    y = margin + chrome_h + pad_y
    x0 = margin + pad_x

    # prompts
    for pl in prompt_lines:
        # draw prompt with accent $
        if pl.startswith("$"):
            draw.text((x0, y), "$", fill=ACCENT, font=font_prompt)
            rest = pl[1:]
            if rest.startswith(" "):
                rest = rest[1:]
                draw.text((x0 + 14, y), rest, fill=TEXT, font=font)
            else:
                draw.text((x0 + 12, y), rest, fill=TEXT, font=font)
        else:
            draw.text((x0, y), pl, fill=TEXT_DIM, font=font)
        y += line_h

    for line in lines:
        x = x0
        for text, color, bold in parse_ansi_line(line):
            f = font_bold if bold else font
            c = color
            if bold and color == TEXT:
                c = WHITE
            adv = draw_mixed_text(
                img, draw, (x, y), text, f, c, emoji_font, emoji_px=emoji_px
            )
            x += adv
        y += line_h

    # bottom accent line
    draw.rectangle(
        [margin + 2, height - margin - 3, width - margin - 2, height - margin - 1],
        fill=ACCENT,
    )

    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG", optimize=True)
    print(f"wrote {out} ({width}x{height})")


def render_logo_png(out: Path, size: int = 512) -> None:
    """Square app icon / favicon source — terminal listing mark + accent."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # rounded square background
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=size // 5, fill=(7, 9, 12, 255))
    # window
    m = int(size * 0.14)
    draw.rounded_rectangle(
        [m, m, size - m, size - m],
        radius=size // 12,
        fill=(17, 22, 30, 255),
        outline=(28, 36, 48, 255),
        width=max(2, size // 90),
    )
    # dots
    dy = m + int(size * 0.08)
    r = max(3, size // 50)
    for i, col in enumerate([(92, 103, 120), (92, 103, 120), ACCENT]):
        cx = m + int(size * 0.08) + i * int(size * 0.06)
        draw.ellipse([cx - r, dy - r, cx + r, dy + r], fill=col + (255,))
    # listing bars
    bar_x = m + int(size * 0.08)
    bar_w_base = size - 2 * m - int(size * 0.16)
    y0 = m + int(size * 0.18)
    gaps = int(size * 0.09)
    widths = [0.55, 0.78, 0.44, 0.68, 0.36]
    for i, wfrac in enumerate(widths):
        y = y0 + i * gaps
        h = max(6, size // 28)
        w = int(bar_w_base * wfrac)
        col = ACCENT if i == 2 else (42, 53, 68)
        if i == 2:
            # highlight row
            draw.rounded_rectangle(
                [bar_x - 4, y - 4, bar_x + bar_w_base + 4, y + h + 4],
                radius=6,
                fill=(61, 255, 154, 36),
            )
        draw.rounded_rectangle([bar_x, y, bar_x + w, y + h], radius=4, fill=col + (255,))
    # monogram
    font = find_font(max(14, size // 16), bold=True)
    label = "f00"
    tw, th = measure_text(draw, label, font)
    draw.text(
        (size - m - tw - int(size * 0.04), m + int(size * 0.05)),
        label,
        fill=TEXT_DIM + (255,),
        font=font,
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG", optimize=True)
    print(f"wrote {out}")


def write_svg_mark(path: Path, light: bool = False) -> None:
    bg = "#f4f6f8" if light else "#07090c"
    panel = "#ffffff" if light else "#11161e"
    stroke = "#d0d7e2" if light else "#1c2430"
    bar = "#c5cedb" if light else "#2a3544"
    label = "#5c6678" if light else "#8b97a8"
    accent = "#12b36a" if light else "#3dff9a"
    title = "f00tils"
    path.write_text(
        f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="{title}">
  <title>{title}</title>
  <desc>f00tils brand mark — colored directory listing with active row.</desc>
  <rect width="512" height="512" rx="96" fill="{bg}"/>
  <rect x="72" y="88" width="368" height="336" rx="28" fill="{panel}" stroke="{stroke}" stroke-width="6"/>
  <circle cx="112" cy="128" r="10" fill="#5c6778"/>
  <circle cx="144" cy="128" r="10" fill="#5c6778"/>
  <circle cx="176" cy="128" r="10" fill="{accent}"/>
  <g fill="{bar}">
    <rect x="112" y="176" width="200" height="22" rx="6"/>
    <rect x="112" y="224" width="288" height="22" rx="6"/>
    <rect x="112" y="272" width="160" height="22" rx="6"/>
    <rect x="112" y="320" width="248" height="22" rx="6"/>
    <rect x="112" y="368" width="120" height="22" rx="6"/>
  </g>
  <rect x="104" y="260" width="304" height="46" rx="10" fill="{accent}" opacity="0.16"/>
  <rect x="112" y="272" width="160" height="22" rx="6" fill="{accent}"/>
  <text x="280" y="136"
        font-family="ui-monospace, 'IBM Plex Mono', 'JetBrains Mono', Menlo, monospace"
        font-size="22" font-weight="600" fill="{label}" letter-spacing="0.5">f00tils</text>
</svg>
''',
        encoding="utf-8",
    )
    print(f"wrote {path}")


def write_svg_lockup(path: Path) -> None:
    path.write_text(
        '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 160" role="img" aria-label="f00tils">
  <title>f00tils</title>
  <desc>f00tils lockup — mark + wordmark</desc>
  <rect width="720" height="160" rx="24" fill="#07090c"/>
  <!-- mark -->
  <g transform="translate(24,24)">
    <rect width="112" height="112" rx="28" fill="#11161e" stroke="#1c2430" stroke-width="3"/>
    <circle cx="28" cy="28" r="5" fill="#5c6778"/>
    <circle cx="44" cy="28" r="5" fill="#5c6778"/>
    <circle cx="60" cy="28" r="5" fill="#3dff9a"/>
    <rect x="24" y="48" width="40" height="8" rx="3" fill="#2a3544"/>
    <rect x="24" y="64" width="58" height="8" rx="3" fill="#2a3544"/>
    <rect x="20" y="76" width="72" height="16" rx="4" fill="#3dff9a" opacity="0.18"/>
    <rect x="24" y="80" width="36" height="8" rx="3" fill="#3dff9a"/>
    <rect x="24" y="96" width="48" height="8" rx="3" fill="#2a3544"/>
  </g>
  <text x="160" y="78"
        font-family="ui-monospace, 'IBM Plex Mono', Menlo, monospace"
        font-size="52" font-weight="700" fill="#e8edf4" letter-spacing="-1">f00tils</text>
  <text x="164" y="118"
        font-family="ui-sans-serif, 'IBM Plex Sans', system-ui, sans-serif"
        font-size="20" font-weight="500" fill="#8b95a8">coreutils → freestanding assembly</text>
  <text x="620" y="78"
        font-family="ui-monospace, 'IBM Plex Mono', Menlo, monospace"
        font-size="22" font-weight="600" fill="#3dff9a">f00</text>
</svg>
''',
        encoding="utf-8",
    )
    print(f"wrote {path}")


def write_svg_og(path: Path) -> None:
    path.write_text(
        '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" role="img" aria-label="f00tils">
  <title>f00tils</title>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0a0c0f"/>
      <stop offset="100%" stop-color="#121820"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <circle cx="1040" cy="90" r="220" fill="#3dff9a" opacity="0.06"/>
  <circle cx="160" cy="560" r="180" fill="#7dffe0" opacity="0.05"/>
  <!-- mark -->
  <g transform="translate(96,150)">
    <rect width="200" height="200" rx="44" fill="#11161e" stroke="#1e2633" stroke-width="4"/>
    <circle cx="48" cy="48" r="9" fill="#5c6778"/>
    <circle cx="76" cy="48" r="9" fill="#5c6778"/>
    <circle cx="104" cy="48" r="9" fill="#3dff9a"/>
    <rect x="40" y="88" width="72" height="14" rx="5" fill="#2a3544"/>
    <rect x="40" y="118" width="110" height="14" rx="5" fill="#2a3544"/>
    <rect x="34" y="142" width="132" height="28" rx="8" fill="#3dff9a" opacity="0.16"/>
    <rect x="40" y="150" width="64" height="14" rx="5" fill="#3dff9a"/>
    <rect x="40" y="188" width="90" height="14" rx="5" fill="#2a3544"/>
  </g>
  <text x="340" y="230"
        font-family="ui-monospace, 'IBM Plex Mono', Menlo, monospace"
        font-size="92" font-weight="700" fill="#e8edf4" letter-spacing="-2">f00tils</text>
  <text x="348" y="290"
        font-family="ui-sans-serif, 'IBM Plex Sans', system-ui, sans-serif"
        font-size="36" font-weight="500" fill="#8b95a8">coreutils → pure freestanding assembly</text>
  <text x="348" y="360"
        font-family="ui-monospace, 'IBM Plex Mono', Menlo, monospace"
        font-size="28" fill="#3dff9a">modern by default · --core for scripts · faster always</text>
  <text x="348" y="430"
        font-family="ui-sans-serif, system-ui, sans-serif"
        font-size="26" fill="#5c6678">f00.sh · multicall binary f00 · MIT · Linux x86-64</text>
  <rect x="96" y="520" width="1008" height="4" rx="2" fill="#3dff9a" opacity="0.5"/>
</svg>
''',
        encoding="utf-8",
    )
    print(f"wrote {path}")


def write_favicon_svg(path: Path) -> None:
    path.write_text(
        '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="f00tils">
  <rect width="64" height="64" rx="14" fill="#07090c"/>
  <rect x="10" y="12" width="44" height="40" rx="6" fill="#11161e" stroke="#1c2430" stroke-width="1.5"/>
  <circle cx="18" cy="20" r="2.2" fill="#5c6778"/>
  <circle cx="24" cy="20" r="2.2" fill="#5c6778"/>
  <circle cx="30" cy="20" r="2.2" fill="#3dff9a"/>
  <rect x="16" y="28" width="18" height="3.5" rx="1.5" fill="#2a3544"/>
  <rect x="16" y="35" width="26" height="3.5" rx="1.5" fill="#2a3544"/>
  <rect x="15" y="40.5" width="28" height="7" rx="2" fill="#3dff9a" opacity="0.18"/>
  <rect x="16" y="42.5" width="14" height="3.5" rx="1.5" fill="#3dff9a"/>
  <rect x="16" y="49" width="20" height="3.5" rx="1.5" fill="#2a3544"/>
</svg>
''',
        encoding="utf-8",
    )
    print(f"wrote {path}")


def prepare_demo_tree(root: Path) -> None:
    """Rich fixture tree that shows icons, types, links, and modern extras."""
    if root.exists():
        shutil.rmtree(root)
    (root / "src").mkdir(parents=True)
    (root / "docs").mkdir()
    (root / "bin").mkdir()
    # no .git: incomplete repo makes `ls` print git discovery noise
    (root / "src" / "main.c").write_text(
        "/* sample */\nint main(void) { return 0; }\n", encoding="utf-8"
    )
    (root / "src" / "util.asm").write_text("; f00tils util\n", encoding="utf-8")
    (root / "src" / "config.json").write_text('{"theme":"tokyo-night"}\n', encoding="utf-8")
    (root / "docs" / "GUIDE.md").write_text(
        "# Guide\n\nUse f00tils with --core for scripts.\n", encoding="utf-8"
    )
    (root / "README.md").write_text(
        "# f00tils\n\ncoreutils → freestanding assembly\nhello from the fixture\n",
        encoding="utf-8",
    )
    (root / "Makefile").write_text("all:\n\t@echo f00tils\n", encoding="utf-8")
    script = root / "install.sh"
    script.write_text("#!/usr/bin/env bash\necho f00tils\n", encoding="utf-8")
    script.chmod(0o755)
    (root / "bin" / "tool").write_bytes(b"\x7fELF" + b"\0" * 12)
    (root / "bin" / "tool").chmod(0o755)
    (root / "notes.txt").write_text(
        "alpha line\nhello world\nhello there\nend of file\n", encoding="utf-8"
    )
    os.symlink("src", root / "lib")
    os.symlink("README.md", root / "README")


def write_shot(name: str, title: str, prompts: list[str], body: str, dests: list[Path], **kw) -> None:
    for dest in dests:
        render_terminal(title, prompts, body, dest, **kw)


def session_body(blocks: list[tuple[str, str]]) -> str:
    """Interleave $ prompts with captured tool output for multi-command shots."""
    parts: list[str] = []
    for prompt, out in blocks:
        parts.append(prompt if prompt.startswith("$") else f"$ {prompt}")
        text = out.rstrip("\n")
        if text:
            parts.append(text)
        parts.append("")
    return "\n".join(parts).rstrip() + "\n"


def main() -> int:
    if not F00.is_file():
        print("build f00 first: cd asm && make", flush=True)
        return 1
    subprocess.run(["make", "-C", str(ASM), "links"], check=False, stdout=subprocess.DEVNULL)

    press = ROOT / "press-kit"
    site = ROOT / "site" / "assets"
    shots = ROOT / "docs" / "images"
    for d in (press, site, shots, press / "screenshots", site / "screenshots"):
        d.mkdir(parents=True, exist_ok=True)

    # SVGs / icons (brand)
    for dest_root in (press, site):
        write_favicon_svg(dest_root / "favicon.svg")
        write_svg_mark(dest_root / "logo.svg", light=False)
        write_svg_mark(dest_root / "logo-light.svg", light=True)
        write_svg_lockup(dest_root / "logo-lockup.svg")
        write_svg_og(dest_root / "og.svg")
        render_logo_png(dest_root / "icon-512.png", 512)
        render_logo_png(dest_root / "icon-192.png", 192)
        render_logo_png(dest_root / "apple-touch-icon.png", 180)
        render_logo_png(dest_root / "favicon-32.png", 32)
        render_logo_png(dest_root / "favicon-16.png", 16)

    # Fixed path so screenshot prompts stay readable across regenerations
    demo = Path("/tmp/f00-demo")
    try:
        prepare_demo_tree(demo)
        rel = "f00-demo"  # short path for prompts (basename)
        triple = lambda n: [shots / n, press / "screenshots" / n, site / "screenshots" / n]

        # glyph icons render cleanly without Nerd font private-use blanks
        icon = "--icons=glyph"
        ls_common = ["--no-git", icon]

        # ── 1) Hero: version + modern ls tour ─────────────────────────
        ver = run_f00(["f00-ls", "--version"], use_pty=False).splitlines()[0]
        out_ls_short = run_f00(["f00-ls", *ls_common, str(demo)])
        out_ls_la = run_f00(["f00-ls", "-la", *ls_common, str(demo)])
        hero_body = session_body(
            [
                ("$ f00-ls --version", f"\x1b[1;32m{ver}\x1b[0m\n\x1b[2mLicense: MIT · https://f00.sh\x1b[0m"),
                (f"$ f00-ls --no-git {icon} {rel}/", out_ls_short),
            ]
        )
        write_shot(
            "hero.png",
            "f00tils · https://f00.sh",
            [],
            hero_body,
            triple("hero.png"),
            width=1040,
            min_height=440,
        )

        # ── 2) Modern long listing (icons, types, links) ───────────────
        write_shot(
            "f00-ls-la.png",
            "f00-ls · modern long listing",
            [f"$ f00-ls -la --no-git {icon} {rel}/"],
            out_ls_la,
            triple("f00-ls-la.png"),
            width=1040,
            min_height=460,
        )
        write_shot(
            "f00-ls.png",
            "f00-ls · modern grid",
            [f"$ f00-ls --no-git {icon} {rel}/"],
            out_ls_short,
            triple("f00-ls.png"),
            width=920,
            min_height=320,
        )

        # ── 3) Modern vs --core (law 1/3 story) ────────────────────────
        modern = run_f00(["f00-ls", *ls_common, "-1", str(demo)])
        core = run_f00(["f00-ls", "--core", "-1", str(demo)])
        compare = session_body(
            [
                (
                    f"$ f00-ls --no-git {icon} -1 {rel}/",
                    "\x1b[1;36m# modern — icons, theme chrome\x1b[0m\n" + modern.rstrip(),
                ),
                (
                    f"$ f00-ls --core -1 {rel}/",
                    "\x1b[1;33m# --core — GNU-plain for scripts / CI\x1b[0m\n" + core.rstrip(),
                ),
            ]
        )
        write_shot(
            "f00-core-vs-modern.png",
            "f00tils · modern vs --core",
            [],
            compare,
            triple("f00-core-vs-modern.png"),
            width=960,
            min_height=480,
        )

        # ── 4) grep: highlight + json machine I/O ─────────────────────
        notes = demo / "notes.txt"
        # denser fixture so -n + highlight + context tell a story
        notes.write_text(
            "# sample log\n"
            "alpha line stays plain\n"
            "hello world\n"
            "middle noise\n"
            "hello there from f00-grep\n"
            "end of file\n",
            encoding="utf-8",
        )
        g_hi = run_f00(["f00-grep", "-n", "hello", str(notes)])
        g_json = run_f00(["f00-grep", "--json", "hello", str(notes)], use_pty=False)
        # shorten absolute paths in json for readability
        g_json = g_json.replace(str(demo), rel)
        grep_body = session_body(
            [
                (f"$ f00-grep -n hello {rel}/notes.txt", g_hi),
                (
                    f"$ f00-grep --json hello {rel}/notes.txt",
                    g_json if g_json.strip() else '{"schema":"f00/v1",...}',
                ),
            ]
        )
        write_shot(
            "f00-grep.png",
            "f00-grep · match chrome + --json",
            [],
            grep_body,
            triple("f00-grep.png"),
            width=1000,
            min_height=400,
        )

        # ── 5) diff: unified color + word-diff ─────────────────────────
        a = demo / "a.txt"
        b = demo / "b.txt"
        a.write_text("alpha\nhello world\nshared tail\n", encoding="utf-8")
        b.write_text("alpha\nhello there\nshared tail\n", encoding="utf-8")
        d_u = run_f00(["f00-diff", "-u", str(a), str(b)])
        d_w = run_f00(["f00-diff", "--word-diff", str(a), str(b)])
        # Collapse absolute paths in headers for readable prompts
        d_u = d_u.replace(str(demo), rel)
        d_w = d_w.replace(str(demo), rel)
        diff_body = session_body(
            [
                (f"$ f00-diff -u {rel}/a.txt {rel}/b.txt", d_u),
                (f"$ f00-diff --word-diff {rel}/a.txt {rel}/b.txt", d_w),
            ]
        )
        write_shot(
            "f00-diff.png",
            "f00-diff · unified + --word-diff",
            [],
            diff_body,
            triple("f00-diff.png"),
            width=1000,
            min_height=480,
        )

        # ── 6) cat shebang paint + find modern (.git skip) ─────────────
        sh = demo / "demo.sh"
        sh.write_text(
            "#!/usr/bin/env bash\n# install helper\necho hello\nfor i in 1 2 3; do echo \"$i\"; done\n",
            encoding="utf-8",
        )
        sh.chmod(0o755)
        cat_out = run_f00(["f00-cat", str(sh)])
        # put a decoy .git so modern skip is meaningful vs --core
        (demo / ".git").mkdir(exist_ok=True)
        (demo / ".git" / "config").write_text("[core]\n", encoding="utf-8")
        (demo / ".git" / "secret.sh").write_text("#!/bin/sh\necho secret\n", encoding="utf-8")
        find_mod = run_f00(
            ["f00-find", str(demo), "-maxdepth", "2", "-name", "*.sh"]
        )
        find_core = run_f00(
            ["f00-find", "--core", str(demo), "-maxdepth", "2", "-name", "*.sh"],
            use_pty=False,
        )
        find_json = run_f00(
            ["f00-find", "--json", str(demo), "-maxdepth", "1", "-type", "d"],
            use_pty=False,
        )
        cat_find_body = session_body(
            [
                (f"$ f00-cat {rel}/demo.sh", cat_out.replace(str(demo), rel)),
                (
                    f"$ f00-find {rel} -maxdepth 2 -name '*.sh'",
                    "\x1b[2m# modern: skips .git (no secret.sh)\x1b[0m\n"
                    + find_mod.replace(str(demo), rel).rstrip()
                    + "\n\x1b[2m# --core would include .git/secret.sh\x1b[0m\n"
                    + find_core.replace(str(demo), rel).rstrip(),
                ),
                (
                    f"$ f00-find --json {rel} -maxdepth 1 -type d",
                    find_json.replace(str(demo), rel),
                ),
            ]
        )
        write_shot(
            "f00-cat-find.png",
            "f00-cat · shebang paint  ·  f00-find · modern + --json",
            [],
            cat_find_body,
            triple("f00-cat-find.png"),
            width=1000,
            min_height=560,
        )

        # ── 7) Multicall power tour (not one-liners only) ──────────────
        sort_in = demo / "names.txt"
        sort_in.write_text("zeta\nalpha\nmiddle\nbeta\n", encoding="utf-8")
        blocks = [
            ("$ f00-id", run_f00(["f00-id"], use_pty=False)),
            ("$ f00-nproc", run_f00(["f00-nproc"], use_pty=False)),
            ("$ f00-uname -srm", run_f00(["f00-uname", "-srm"], use_pty=False)),
            (
                f"$ f00-sort {rel}/names.txt",
                run_f00(["f00-sort", str(sort_in)], use_pty=False),
            ),
            (
                f"$ f00-sha256sum {rel}/README.md",
                run_f00(["f00-sha256sum", str(demo / "README.md")], use_pty=False),
            ),
            (
                f"$ f00-wc -l {rel}/notes.txt",
                run_f00(["f00-wc", "-l", str(notes)], use_pty=False),
            ),
            (
                f"$ f00-grep -c hello {rel}/notes.txt",
                run_f00(["f00-grep", "-c", "hello", str(notes)], use_pty=False),
            ),
        ]
        body_parts: list[str] = []
        for prompt, out in blocks:
            body_parts.append(prompt)
            for line in (out.splitlines() or [""]):
                if re.fullmatch(r"[0-9a-f]{32,}.*", line.strip()):
                    body_parts.append(f"\x1b[32m{line}\x1b[0m")
                elif re.fullmatch(r"\d+", line.strip()):
                    body_parts.append(f"\x1b[36m{line}\x1b[0m")
                elif "uid=" in line:
                    body_parts.append(
                        line.replace("uid=", "\x1b[33muid=\x1b[0m")
                        .replace("gid=", "\x1b[33mgid=\x1b[0m")
                        .replace("groups=", "\x1b[33mgroups=\x1b[0m")
                    )
                else:
                    body_parts.append(line)
            body_parts.append("")
        suite_body = "\n".join(body_parts).rstrip() + "\n"
        write_shot(
            "f00-suite.png",
            "f00tils · multicall tour (id · sort · hash · grep · wc)",
            ["# one binary · argv0 dispatch · 115 tools"],
            suite_body,
            triple("f00-suite.png"),
            width=1000,
            min_height=520,
        )

    finally:
        shutil.rmtree(demo, ignore_errors=True)

    readme = """# f00tils screenshots

Color **PTY** captures of the multicall (`f00` / `f00-*`). Regenerated every ship.

| File | Story |
|------|--------|
| `hero.png` | Version + modern `ls` icons |
| `f00-ls-la.png` | Long listing: types, links, glyph icons, theme |
| `f00-ls.png` | Compact modern grid |
| `f00-core-vs-modern.png` | Modern chrome vs `--core` GNU-plain |
| `f00-grep.png` | Match highlight + `--json` |
| `f00-diff.png` | Unified color + `--word-diff` |
| `f00-cat-find.png` | `cat` shebang paint + modern `find` (.git skip) / `--json` |
| `f00-suite.png` | Multicall tour across tools |

```bash
cd asm && make
# forced color terminal: real PTY + TERM/COLORTERM/FORCE_COLOR (no shell)
python3 scripts/render-brand-assets.py
```

Copies to `press-kit/screenshots/`, `site/assets/screenshots/`, `docs/images/`.
"""
    (press / "screenshots" / "README.md").write_text(readme, encoding="utf-8")
    (site / "screenshots" / "README.md").write_text(readme, encoding="utf-8")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
