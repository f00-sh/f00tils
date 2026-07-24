/**
 * f00tils (f00.sh) — progressive enhancement.
 * Version labels, copy buttons, Bun-style bench widgets, scoreboard.
 */
(() => {
  "use strict";

  const FALLBACK_VERSION = "v0.15.16";

  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function setVersionLabels(tag) {
    if (!tag) return;
    document.querySelectorAll("[data-version]").forEach((el) => {
      el.textContent = tag;
    });
  }

  setVersionLabels(FALLBACK_VERSION);
  try {
    fetch("https://api.github.com/repos/theesfeld/f00/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
    })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (data && data.tag_name) setVersionLabels(data.tag_name);
      })
      .catch(() => {});
  } catch (_) {}

  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const sel = btn.getAttribute("data-copy");
      const target = sel ? document.querySelector(sel) : null;
      const text = (target ? target.textContent : "").trim();
      if (!text) return;
      const done = () => {
        const prev = btn.textContent;
        btn.textContent = "copied";
        btn.classList.add("copied");
        setTimeout(() => {
          btn.textContent = prev;
          btn.classList.remove("copied");
        }, 1400);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(() => {
          const ta = document.createElement("textarea");
          ta.value = text;
          document.body.appendChild(ta);
          ta.select();
          try {
            document.execCommand("copy");
          } catch (_) {}
          document.body.removeChild(ta);
          done();
        });
      }
    });
  });

  function fmtMs(v) {
    if (v == null || Number.isNaN(v)) return "—";
    return Number(v).toFixed(2);
  }

  function fmtRatio(v) {
    if (v == null || Number.isNaN(v)) return "—";
    return `<strong>${esc(Number(v).toFixed(2))}×</strong>`;
  }

  function benchIndex(tools) {
    const map = Object.create(null);
    (tools || []).forEach((t) => {
      if (t && t.tool) map[t.tool] = t;
    });
    if (map.test && !map["["]) map["["] = map.test;
    return map;
  }

  function computeSummaryFallback(tools) {
    const ok = (tools || []).filter(
      (t) => t.status === "ok" && t.ratio != null && t.ratio > 0
    );
    if (!ok.length) return null;
    const ratios = ok.map((t) => t.ratio);
    const logSum = ratios.reduce((a, r) => a + Math.log(r), 0);
    const geo = Math.exp(logSum / ratios.length);
    const med = ratios.slice().sort((a, b) => a - b)[Math.floor(ratios.length / 2)];
    const gnu = ok.reduce((a, t) => a + (t.time_gnu_ms || 0), 0);
    const f00 = ok.reduce((a, t) => a + (t.time_f00_ms || 0), 0);
    const total = f00 > 0 ? gnu / f00 : null;
    const x = Math.round(geo * 10) / 10;
    const pct = Math.round((geo - 1) * 100);
    return {
      tools_ok: ok.length,
      tools_win: ratios.filter((r) => r > 1).length,
      ratio_geo: geo,
      ratio_median: med,
      ratio_total: total,
      pct_faster_geo: pct,
      headline_x: `${x}×`,
      headline_pct: `${pct}% faster overall`,
      headline: `${x}× faster than GNU coreutils overall`,
      method:
        "geometric mean of per-tool speedups (f00-* --core vs /usr/bin, spawn-inclusive median)",
    };
  }

  function renderOverall(summary, meta) {
    if (!summary) return;
    const hx = summary.headline_x || "—";
    const hp = summary.headline_pct || "";
    const title = summary.headline || "faster than GNU coreutils overall";

    const hero = document.getElementById("hero-speed");
    if (hero) {
      hero.hidden = false;
      const xEl = document.getElementById("hero-speed-x");
      const sub = document.getElementById("hero-speed-sub");
      if (xEl) xEl.textContent = hx;
      if (sub) {
        sub.textContent = `${hp} · geo mean · ${summary.tools_ok || "?"} tools`;
      }
    }

    const overall = document.getElementById("overall-hero");
    if (overall) {
      overall.hidden = false;
      const ox = document.getElementById("overall-x");
      const ot = document.getElementById("overall-title");
      const od = document.getElementById("overall-detail");
      const om = document.getElementById("overall-method");
      if (ox) ox.textContent = hx;
      if (ot) ot.textContent = "faster than GNU coreutils overall";
      if (od) {
        od.textContent = [
          hp,
          summary.tools_win != null
            ? `${summary.tools_win}/${summary.tools_ok} tools win`
            : null,
          summary.ratio_median != null
            ? `median ${Number(summary.ratio_median).toFixed(2)}×`
            : null,
          summary.ratio_total != null
            ? `total-time ${Number(summary.ratio_total).toFixed(2)}×`
            : null,
        ]
          .filter(Boolean)
          .join(" · ");
      }
      if (om) {
        const bits = [];
        if (summary.method) bits.push(summary.method);
        if (meta && meta.generated_at) bits.push(meta.generated_at);
        if (meta && meta.machine) bits.push(meta.machine);
        om.textContent = bits.join(" · ");
      }
    }

    const claim = document.getElementById("scoreboard-speed-claim");
    if (claim) claim.textContent = `${hx} faster overall (geo mean)`;
  }

  function renderRaceCards(showcase, tools) {
    const grid = document.getElementById("race-grid");
    if (!grid) return;
    let rows = showcase && showcase.length ? showcase : null;
    if (!rows) {
      const ok = (tools || [])
        .filter((t) => t.status === "ok" && t.ratio != null)
        .sort((a, b) => b.ratio - a.ratio)
        .slice(0, 8)
        .map((t) => ({
          tool: t.tool,
          time_gnu_ms: t.time_gnu_ms,
          time_f00_ms: t.time_f00_ms,
          ratio: t.ratio,
          command_f00: t.command_f00,
        }));
      rows = ok;
    }
    if (!rows.length) {
      grid.innerHTML = '<p class="muted">No showcase benches yet.</p>';
      return;
    }

    const maxMs = Math.max(
      ...rows.map((r) => Math.max(r.time_gnu_ms || 0, r.time_f00_ms || 0)),
      0.001
    );

    grid.innerHTML = rows
      .map((r, i) => {
        const gPct = Math.max(4, ((r.time_gnu_ms || 0) / maxMs) * 100);
        const fPct = Math.max(4, ((r.time_f00_ms || 0) / maxMs) * 100);
        const delay = (i * 0.06).toFixed(2);
        return (
          `<article class="bench-card race-card" style="--d:${delay}s">` +
          `<header class="race-head">` +
          `<h3><code>${esc(r.tool)}</code></h3>` +
          `<span class="bench-tag win">${esc(Number(r.ratio).toFixed(2))}×</span>` +
          `</header>` +
          `<p class="race-cmd muted small"><code>${esc(r.command_f00 || "f00-" + r.tool + " --core")}</code></p>` +
          `<div class="bench-bars race-bars">` +
          `<div class="bar-row">` +
          `<span class="bar-label">f00tils</span>` +
          `<div class="bar-track"><div class="bar fluid f00" style="--w:${fPct.toFixed(1)}%"></div></div>` +
          `<span class="bar-val"><strong>${esc(fmtMs(r.time_f00_ms))}</strong> ms</span>` +
          `</div>` +
          `<div class="bar-row">` +
          `<span class="bar-label">GNU</span>` +
          `<div class="bar-track"><div class="bar fluid gnu dim" style="--w:${gPct.toFixed(1)}%"></div></div>` +
          `<span class="bar-val">${esc(fmtMs(r.time_gnu_ms))} ms</span>` +
          `</div>` +
          `</div>` +
          `</article>`
        );
      })
      .join("");

    // trigger fluid animation on enter viewport
    requestAnimationFrame(() => {
      grid.classList.add("animate");
    });
  }

  function polyline(xs, ys, w, h, pad) {
    const n = xs.length;
    if (!n) return "";
    const pts = [];
    for (let i = 0; i < n; i++) {
      const x = pad + (xs[i] / Math.max(xs[n - 1], 1)) * (w - pad * 2);
      const y = pad + (1 - ys[i]) * (h - pad * 2);
      pts.push(`${x.toFixed(1)},${y.toFixed(1)}`);
    }
    return pts.join(" ");
  }

  function renderColdChart(cold) {
    const panel = document.getElementById("cold-panel");
    const svg = document.getElementById("cold-chart");
    if (!panel || !svg || !cold || !cold.f00_ms || !cold.gnu_ms) return;

    const f00 = cold.f00_ms.map(Number);
    const gnu = cold.gnu_ms.map(Number);
    const n = Math.min(f00.length, gnu.length);
    if (n < 2) return;

    panel.hidden = false;
    const cap = document.getElementById("cold-caption");
    const ratioEl = document.getElementById("cold-ratio");
    if (cap) {
      const tools = (cold.tools || []).slice(0, 6).join(", ");
      cap.textContent = `${cold.label || "Cold process spawn"} · ${tools}${
        (cold.tools || []).length > 6 ? "…" : ""
      }`;
    }
    if (ratioEl && cold.ratio != null) {
      ratioEl.textContent = `${Number(cold.ratio).toFixed(2)}× faster (median of mean series)`;
    }

    const w = 640;
    const h = 220;
    const pad = 28;
    const maxY = Math.max(...f00.slice(0, n), ...gnu.slice(0, n), 0.001);
    const xs = Array.from({ length: n }, (_, i) => i);
    const norm = (arr) => arr.slice(0, n).map((v) => v / maxY);

    const gPts = polyline(xs, norm(gnu), w, h, pad);
    const fPts = polyline(xs, norm(f00), w, h, pad);

    // grid lines
    const gridYs = [0.25, 0.5, 0.75, 1].map((t) => {
      const y = pad + (1 - t) * (h - pad * 2);
      const label = (maxY * t).toFixed(2);
      return (
        `<line class="grid" x1="${pad}" y1="${y}" x2="${w - pad}" y2="${y}" />` +
        `<text class="axis" x="${pad - 6}" y="${y + 3}" text-anchor="end">${label}</text>`
      );
    });

    svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
    svg.innerHTML =
      gridYs.join("") +
      `<polyline class="line gnu-line" fill="none" points="${gPts}" />` +
      `<polyline class="line f00-line" fill="none" points="${fPts}" />` +
      `<text class="axis" x="${pad}" y="${h - 8}">run 1</text>` +
      `<text class="axis" x="${w - pad}" y="${h - 8}" text-anchor="end">run ${n}</text>` +
      `<text class="axis" x="${w / 2}" y="${h - 8}" text-anchor="middle">ms (mean of entry tools)</text>`;

    // re-trigger stroke animation
    svg.classList.remove("drawn");
    requestAnimationFrame(() => svg.classList.add("drawn"));
  }

  function renderStats(tools, meta, summary) {
    const metaEl = document.getElementById("bench-meta");
    const stats = document.getElementById("bench-stats");
    const ok = (tools || []).filter((t) => t.status === "ok" && t.ratio != null);
    ok.sort((a, b) => b.ratio - a.ratio);

    if (metaEl) {
      const bits = [];
      if (summary && summary.headline) bits.push(summary.headline);
      if (meta && meta.method) bits.push(meta.method);
      if (meta && meta.machine) bits.push(meta.machine);
      if (meta && meta.generated_at) bits.push(meta.generated_at);
      metaEl.textContent = bits.join(" · ") || "Suite benchmarks";
    }

    if (!stats || !ok.length) return;
    stats.hidden = false;
    const ratios = ok.map((t) => t.ratio).sort((a, b) => a - b);
    const mid = ratios[Math.floor(ratios.length / 2)];
    const best = ok[0];
    const set = (id, v) => {
      const el = document.getElementById(id);
      if (el) el.textContent = v;
    };
    set(
      "stat-overall",
      summary && summary.headline_x
        ? summary.headline_x
        : summary && summary.ratio_geo
          ? `${Number(summary.ratio_geo).toFixed(1)}×`
          : "—"
    );
    set(
      "stat-pct",
      summary && summary.pct_faster_geo != null
        ? `${Math.round(summary.pct_faster_geo)}%`
        : "—"
    );
    set("stat-tools", String(ok.length));
    set("stat-median", `${mid.toFixed(2)}×`);
    set("stat-best", `${best.tool} ${best.ratio.toFixed(1)}×`);
    set("stat-n", meta && meta.n_runs ? String(meta.n_runs) : "—");
  }

  function renderScoreboard(progress, bench) {
    const body = document.getElementById("scoreboard-body");
    if (!body) return;
    const rows = (progress && progress.rows) || [];
    const bi = benchIndex(bench && bench.tools);

    if (!rows.length) {
      body.innerHTML =
        '<tr><td colspan="9" class="muted">Missing coreutils-progress.json</td></tr>';
      return;
    }

    body.innerHTML = rows
      .map((r) => {
        const key = r.util === "[" ? "[" : r.util;
        const b = bi[key] || bi[r.util] || null;
        const depth =
          r.depth === "full" ? "<strong>full</strong>" : esc(r.depth);
        let g = "—";
        let f = "—";
        let x = "—";
        if (b && b.status === "ok") {
          g = fmtMs(b.time_gnu_ms);
          f = `<strong>${esc(fmtMs(b.time_f00_ms))}</strong>`;
          x = fmtRatio(b.ratio);
        } else if (r.speed === "win") {
          x = "<strong>win</strong>";
        } else if (r.speed && r.speed !== "—") {
          x = esc(r.speed);
        }
        return (
          `<tr class="shipped">` +
          `<td>${esc(r.n)}</td>` +
          `<td><code>${esc(r.util)}</code></td>` +
          `<td><code>${esc(r.f00)}</code></td>` +
          `<td>${esc(r.shipped)}</td>` +
          `<td>${depth}</td>` +
          `<td>${esc(r.modern)}</td>` +
          `<td>${esc(g)}</td>` +
          `<td>${f}</td>` +
          `<td>${x}</td>` +
          `</tr>`
        );
      })
      .join("");
  }

  Promise.all([
    fetch("coreutils-progress.json", { headers: { Accept: "application/json" } })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null),
    fetch("bench/suite.json", { headers: { Accept: "application/json" } })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null),
  ]).then(([progress, suite]) => {
    if (!suite) {
      renderScoreboard(progress, null);
      return;
    }
    const summary =
      suite.summary || computeSummaryFallback(suite.tools) || null;
    renderOverall(summary, suite.meta);
    renderRaceCards(suite.showcase, suite.tools);
    renderColdChart(suite.cold_startup);
    renderStats(suite.tools, suite.meta, summary);
    renderScoreboard(progress, suite);
  });
})();
