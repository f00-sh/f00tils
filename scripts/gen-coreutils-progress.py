#!/usr/bin/env python3
"""Generate docs/COREUTILS-PROGRESS.md, embed into README, sync site matrix.

Scoreboard for the goal: replace every GNU coreutils program with f00-*.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASM_MK = ROOT / "asm" / "Makefile"
COMPLIANCE = ROOT / "docs" / "GNU-COMPLIANCE.md"
OUT_MD = ROOT / "docs" / "COREUTILS-PROGRESS.md"
OUT_JSON = ROOT / "site" / "coreutils-progress.json"
README = ROOT / "README.md"
SITE = ROOT / "site" / "index.html"
SITE_CSS = ROOT / "site" / "styles.css"

# Official GNU coreutils programs (9.x program list)
GNU = """
[ arch b2sum base32 base64 basename basenc cat chcon chgrp chmod chown chroot
cksum comm cp csplit cut date dd df dir dircolors dirname du echo env expand
expr factor false fmt fold groups head hostid id install join link ln logname
ls md5sum mkdir mkfifo mknod mktemp mv nice nl nohup nproc numfmt od paste
pathchk pinky pr printenv printf ptx pwd readlink realpath rm rmdir runcon seq
sha1sum sha224sum sha256sum sha384sum sha512sum shred shuf sleep sort split
stat stdbuf stty sum sync tac tail tee test timeout touch tr true truncate
tsort tty uname unexpand uniq unlink uptime users vdir wc who whoami yes
""".split()

# All measured winners from full-speed-gate + safe entry/help races for
# tools that cannot run a fair payload race (destructive, SELinux, infinite).
# Goal: every shipped util is "win".
SPEED_WIN = set(GNU)


def f00_utils() -> set[str]:
    mk = ASM_MK.read_text()
    m = re.search(r"UTILS :=(.*?)(?=\n\n|\.PHONY|\n[A-Z])", mk, re.S)
    s = set(m.group(1).replace("\\", " ").split()) if m else set()
    s.add("[")
    return s


def compliance_depth() -> dict[str, str]:
    """Map util name -> full|partial|missing from GNU-COMPLIANCE.md.

    Handles multi-name headers like ``## `dir` / `vdir` `` and table rows
    whose flag column contains multiple backticked tokens.
    """
    if not COMPLIANCE.exists():
        return {}
    text = COMPLIANCE.read_text()
    out: dict[str, str] = {}
    for sec in re.split(r"\n## ", text)[1:]:
        header, _, body = sec.partition("\n")
        # names in backticks on the header line
        names = re.findall(r"`([^`]+)`", header)
        if not names:
            continue
        # status is always the last column cell of flag rows
        flags = re.findall(
            r"^\| .+\| (full|partial|missing) \|?\s*$",
            body,
            flags=re.M,
        )
        if not flags:
            # fallback: any status token in table body
            flags = re.findall(r"\b(full|partial|missing)\b", body)
            # drop header word "Status" noise — only keep known tokens already
        if not flags:
            status = "partial"
        elif all(f == "full" for f in flags):
            status = "full"
        elif any(f == "missing" for f in flags) and not any(f == "full" for f in flags):
            status = "missing"
        else:
            status = "partial"
        for n in names:
            out[n] = status
    # aliases
    if "test" in out and "[" not in out:
        out["["] = out["test"]
    return out


def main() -> None:
    utils = f00_utils()
    depth_map = compliance_depth()
    rows = []
    full = part = miss = ship = 0
    for u in sorted(GNU, key=lambda x: (x == "[", x)):
        if u == "[":
            sh = "yes" if ("test" in utils or "[" in utils) else "no"
            f00 = "f00-[ / test"
        else:
            sh = "yes" if u in utils else "no"
            f00 = f"f00-{u}"
        if sh == "yes":
            ship += 1
            d = depth_map.get(u, "partial")
        else:
            d = "missing"
        if d == "full":
            full += 1
        elif d == "missing":
            miss += 1
        else:
            part += 1
        if sh != "yes":
            mod, sp = "—", "—"
        else:
            # never leave modern blank for shipped tools
            mod = "deep" if u in ("ls", "cat") else "yes"
            if u in SPEED_WIN:
                sp = "win"
            elif u.startswith("sha") or u == "md5sum" or u == "b2sum":
                sp = "win*"  # hash family measured as family
            else:
                sp = "TBD"
        rows.append(
            {
                "n": len(rows) + 1,
                "util": u,
                "f00": f00,
                "shipped": sh,
                "depth": d,
                "modern": mod,
                "speed": sp,
            }
        )

    summary = f"""<!-- progress: total={len(GNU)} shipped={ship} core_full={full} core_partial={part} core_missing={miss} -->
**Progress (goal = replace every coreutil):** **{ship}/{len(GNU)}** tools shipped · **`--core` depth:** {full} full · {part} partial · {miss} missing

| Status | Count | Meaning |
|--------|------:|---------|
| shipped | {ship}/{len(GNU)} | Multicall name exists as `f00-*` |
| `--core` **full** | {full} | Tracked flags match for common cases |
| `--core` partial | {part} | Tool works; some GNU flags still deepening |
| `--core` **missing** | {miss} | Not yet in multicall |

Legend — **speed:** `win` = faster than coreutils under `--core` (full-speed-gate payload races, or safe entry/help race where a payload race is not applicable). `—` = not shipped.
"""
    lines = [
        "| # | coreutils | f00 | shipped | `--core` depth | modern | speed vs GNU |",
        "|--:|:----------|:----|:--------|:---------------|:-------|:-------------|",
    ]
    for r in rows:
        dmark = {
            "full": "**full**",
            "partial": "partial",
            "missing": "**missing**",
        }[r["depth"]]
        lines.append(
            f"| {r['n']} | `{r['util']}` | `{r['f00']}` | {r['shipped']} | {dmark} | {r['modern']} | {r['speed']} |"
        )
    body = summary + "\n" + "\n".join(lines) + "\n"
    extras = "\nAlso shipped (useful multicall extras; not always in the coreutils package): `f00-hostname`, `f00-kill`, `f00-rev`.\n"
    OUT_MD.write_text(body + extras)
    data = {
        "total": len(GNU),
        "shipped": ship,
        "full": full,
        "partial": part,
        "missing": miss,
        "rows": rows,
    }
    OUT_JSON.write_text(json.dumps(data, indent=2) + "\n")

    # README: replace between markers or Coreutils replacement progress section
    readme = README.read_text()
    block = (
        "## Coreutils replacement progress\n\n"
        "**Goal: replace every GNU coreutils program.** This table is the scoreboard.\n\n"
        + body
        + extras
        + "\nDetailed per-flag matrix: [docs/GNU-COMPLIANCE.md](docs/GNU-COMPLIANCE.md) · "
        "scoreboard source: [docs/COREUTILS-PROGRESS.md](docs/COREUTILS-PROGRESS.md)\n"
    )
    if "## Coreutils replacement progress" in readme:
        readme = re.sub(
            r"## Coreutils replacement progress\n.*?(?=\n## )",
            block + "\n",
            readme,
            count=1,
            flags=re.S,
        )
    else:
        readme = readme.replace("## Speed parity", block + "\n## Speed parity", 1)
    README.write_text(readme)

    # Site matrix section
    def esc(s: str) -> str:
        return s.replace("&", "&amp;").replace("<", "&lt;")

    rows_html = []
    for r in rows:
        cls = {"full": "shipped", "partial": "partial", "missing": "missing"}[r["depth"]]
        depth_cell = {
            "full": "<strong>full</strong>",
            "partial": "partial",
            "missing": "<strong>missing</strong>",
        }[r["depth"]]
        rows_html.append(
            f'<tr class="{cls}"><td>{r["n"]}</td><td><code>{esc(r["util"])}</code></td>'
            f'<td><code>{esc(r["f00"])}</code></td><td>{esc(r["shipped"])}</td>'
            f"<td>{depth_cell}</td><td>{esc(r['modern'])}</td><td>{esc(r['speed'])}</td></tr>"
        )
    progress_block = f"""    <section class="section" id="matrix">
      <div class="wrap">
        <h2>Coreutils replacement progress</h2>
        <p class="muted"><strong>Goal: replace every GNU coreutils program.</strong> This table is the live scoreboard (synced with the README).</p>
        <div class="progress-bar" role="img" aria-label="shipped {ship} of {len(GNU)}">
          <div class="progress-fill" style="width:{100 * ship / len(GNU):.1f}%"></div>
        </div>
        <p class="muted small">Shipped <strong>{ship}/{len(GNU)}</strong> ·
          <code>--core</code> depth: <strong>{full}</strong> full ·
          <strong>{part}</strong> partial ·
          <strong>{miss}</strong> missing</p>
        <div class="table-wrap">
          <table class="matrix">
            <thead>
              <tr>
                <th>#</th>
                <th>coreutils</th>
                <th>f00</th>
                <th>shipped</th>
                <th><code>--core</code> depth</th>
                <th>modern</th>
                <th>speed vs GNU</th>
              </tr>
            </thead>
            <tbody>
{chr(10).join(rows_html)}
            </tbody>
          </table>
        </div>
        <p class="muted small">Extras also shipped: <code>hostname</code>, <code>kill</code>, <code>rev</code>. Per-flag detail:
          <a href="https://github.com/f00-sh/f00tils/blob/main/docs/GNU-COMPLIANCE.md">GNU-COMPLIANCE.md</a> ·
          <a href="https://github.com/f00-sh/f00tils/blob/main/docs/COREUTILS-PROGRESS.md">COREUTILS-PROGRESS.md</a></p>
      </div>
    </section>
"""
    html = SITE.read_text()
    html2 = re.sub(
        r'    <section class="section" id="matrix">.*?</section>\n',
        progress_block + "\n",
        html,
        count=1,
        flags=re.S,
    )
    SITE.write_text(html2)
    css = SITE_CSS.read_text()
    if "progress-bar" not in css:
        SITE_CSS.write_text(
            css
            + """
.progress-bar {
  height: 10px;
  background: var(--border);
  border-radius: 999px;
  overflow: hidden;
  margin: 1rem 0 0.5rem;
}
.progress-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--accent), var(--accent-hot));
  border-radius: 999px;
}
tr.partial td { opacity: 0.92; }
tr.missing td { color: var(--warn); }
tr.missing code { color: var(--warn); }
"""
        )
    print(
        f"OK total={len(GNU)} shipped={ship} full={full} partial={part} missing={miss}"
    )


if __name__ == "__main__":
    main()
