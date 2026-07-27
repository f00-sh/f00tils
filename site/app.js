/**
 * f00tils (f00.sh) — progressive enhancement.
 * Version labels, copy buttons, Bun-style bench widgets, scoreboard.
 */
(() => {
  "use strict";

  const FALLBACK_VERSION = "v0.16.7";

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

  const PKG_ORDER = ["coreutils", "grep", "findutils", "diffutils"];
  const PKG_LABEL = {
    coreutils: "coreutils",
    grep: "grep",
    findutils: "findutils",
    diffutils: "diffutils",
  };
  const PKG_SHIPPED = {
    coreutils: 106,
    grep: 3,
    findutils: 2,
    diffutils: 4,
  };
  const GREP_TOOLS = new Set(["grep", "egrep", "fgrep"]);
  const FIND_TOOLS = new Set(["find", "xargs"]);
  const DIFF_TOOLS = new Set(["diff", "cmp", "diff3", "sdiff"]);

  function toolPackage(name) {
    if (GREP_TOOLS.has(name)) return "grep";
    if (FIND_TOOLS.has(name)) return "findutils";
    if (DIFF_TOOLS.has(name)) return "diffutils";
    return "coreutils";
  }

  function computeSummaryFallback(tools, packageName) {
    const pkg = packageName || "coreutils";
    const label = PKG_LABEL[pkg] || pkg;
    const ok = (tools || []).filter(
      (t) => t.status === "ok" && t.ratio != null && t.ratio > 0
    );
    if (!ok.length) {
      return {
        package: pkg,
        package_label: label,
        tools_ok: 0,
        tools_win: 0,
        headline_x: "—",
        headline: `pending vs GNU ${label}`,
        headline_pct: "—",
      };
    }
    const ratios = ok.map((t) => t.ratio);
    const logSum = ratios.reduce((a, r) => a + Math.log(r), 0);
    const geo = Math.exp(logSum / ratios.length);
    const med = ratios.slice().sort((a, b) => a - b)[Math.floor(ratios.length / 2)];
    const gnu = ok.reduce((a, t) => a + (t.time_gnu_ms || 0), 0);
    const f00 = ok.reduce((a, t) => a + (t.time_f00_ms || 0), 0);
    const total = f00 > 0 ? gnu / f00 : null;
    const x = Math.round(geo * 10) / 10;
    const pct = Math.round((geo - 1) * 100);
    const cpuOk = ok.filter((t) => t.cpu_ratio != null && t.cpu_ratio > 0);
    const cpuGeo = cpuOk.length
      ? Math.exp(
          cpuOk.reduce((a, t) => a + Math.log(t.cpu_ratio), 0) / cpuOk.length
        )
      : null;
    const cpuX =
      cpuGeo != null ? `${Math.round(cpuGeo * 10) / 10}×` : "—";
    return {
      package: pkg,
      package_label: label,
      tools_ok: ok.length,
      tools_win: ratios.filter((r) => r > 1).length,
      ratio_geo: geo,
      ratio_median: med,
      ratio_total: total,
      pct_faster_geo: pct,
      cpu_ratio_geo: cpuGeo,
      cpu_wins: cpuOk.filter((t) => t.cpu_ratio > 1).length,
      cpu_tools_ok: cpuOk.length,
      headline_x: `${x}×`,
      headline_cpu_x: cpuX,
      headline_pct: `${pct}% faster wall (${pkg})`,
      headline: `${x}× wall vs GNU ${label}`,
      headline_cpu: cpuGeo != null ? `${cpuX} CPU vs GNU ${label}` : null,
      method: `separate wall and CPU geos (f00-* --core vs GNU ${label})`,
    };
  }

  const USERLAND = {
    grep: [
      { n: 1, util: "grep", f00: "f00-grep", shipped: "yes", depth: "full", modern: "deep" },
      { n: 2, util: "egrep", f00: "f00-egrep", shipped: "yes", depth: "full", modern: "yes" },
      { n: 3, util: "fgrep", f00: "f00-fgrep", shipped: "yes", depth: "full", modern: "yes" },
    ],
    findutils: [
      { n: 1, util: "find", f00: "f00-find", shipped: "yes", depth: "full", modern: "deep" },
      { n: 2, util: "xargs", f00: "f00-xargs", shipped: "yes", depth: "full", modern: "yes" },
    ],
    diffutils: [
      { n: 1, util: "diff", f00: "f00-diff", shipped: "yes", depth: "full", modern: "deep" },
      { n: 2, util: "cmp", f00: "f00-cmp", shipped: "yes", depth: "full", modern: "yes" },
      { n: 3, util: "diff3", f00: "f00-diff3", shipped: "yes", depth: "full", modern: "yes" },
      { n: 4, util: "sdiff", f00: "f00-sdiff", shipped: "yes", depth: "full", modern: "deep" },
    ],
  };

  function packagesFromSuite(suite) {
    if (suite && suite.packages && typeof suite.packages === "object") {
      // Ensure all four keys exist even if a set had no timed tools
      const out = {};
      PKG_ORDER.forEach((p) => {
        out[p] = suite.packages[p] || {
          package: p,
          package_label: PKG_LABEL[p],
          tools_ok: 0,
          headline_x: "—",
          headline: `pending vs GNU ${PKG_LABEL[p]}`,
        };
      });
      return out;
    }
    // Fall back: derive from tools[].package or tool name
    const by = { coreutils: [], grep: [], findutils: [], diffutils: [] };
    (suite && suite.tools ? suite.tools : []).forEach((t) => {
      const p = t.package || toolPackage(t.tool || "");
      if (!by[p]) by[p] = [];
      by[p].push(t);
    });
    const out = {};
    PKG_ORDER.forEach((p) => {
      out[p] = computeSummaryFallback(by[p], p);
    });
    return out;
  }

  function pkgTileHtml(p, s, compact) {
    const hx = s.headline_x || "—";
    const cx =
      s.headline_cpu_x ||
      (s.cpu_ratio_geo != null
        ? `${Math.round(Number(s.cpu_ratio_geo) * 10) / 10}×`
        : "—");
    const n = s.tools_ok != null ? s.tools_ok : 0;
    if (compact) {
      return (
        `<article class="hero-pkg-tile" data-pkg="${esc(p)}">` +
        `<span class="hero-pkg-name">${esc(PKG_LABEL[p])}</span>` +
        `<span class="hero-pkg-wall">${esc(hx)}</span>` +
        `<span class="hero-pkg-meta">wall · CPU ${esc(cx)}</span>` +
        `</article>`
      );
    }
    const wins = s.tools_win != null ? `${s.tools_win}/${n}` : "—";
    const cpuWins =
      s.cpu_wins != null && s.cpu_tools_ok != null
        ? `${s.cpu_wins}/${s.cpu_tools_ok}`
        : "—";
    return (
      `<article class="pkg-card" data-pkg="${esc(p)}">` +
      `<header><span class="pkg-name">${esc(PKG_LABEL[p])}</span>` +
      `<span class="pkg-x">${esc(hx)} <span class="pkg-x-sub">wall</span></span></header>` +
      `<p class="pkg-cpu"><strong>${esc(cx)}</strong> <span class="muted">CPU</span></p>` +
      `<p class="pkg-meta muted small">${n} timed · wall ${esc(wins)} · CPU ${esc(cpuWins)}</p>` +
      `</article>`
    );
  }

  function renderPackageCards(packages, meta) {
    const host = document.getElementById("pkg-cards");
    if (host) {
      host.innerHTML = PKG_ORDER.map((p) =>
        pkgTileHtml(p, (packages && packages[p]) || {}, false)
      ).join("");
    }

    // Hero: one tile per GNU package (wall + CPU), never blended
    const heroGrid = document.getElementById("hero-pkg-grid");
    if (heroGrid) {
      heroGrid.innerHTML = PKG_ORDER.map((p) =>
        pkgTileHtml(p, (packages && packages[p]) || {}, true)
      ).join("");
    }

    const claim = document.getElementById("scoreboard-speed-claim");
    if (claim) {
      claim.textContent = PKG_ORDER.map((p) => {
        const s = packages[p] || {};
        if (!s.headline_x) return null;
        const cpu =
          s.headline_cpu_x ||
          (s.cpu_ratio_geo != null
            ? `${Number(s.cpu_ratio_geo).toFixed(1)}×`
            : "—");
        return `${PKG_LABEL[p]} ${s.headline_x}/${cpu}`;
      })
        .filter(Boolean)
        .join(" · ");
    }
  }

  function raceCardHtml(r, maxMs, i) {
    const gPct = Math.max(4, ((r.time_gnu_ms || 0) / maxMs) * 100);
    const fPct = Math.max(4, ((r.time_f00_ms || 0) / maxMs) * 100);
    const delay = (i * 0.04).toFixed(2);
    const pkg = r.package || toolPackage(r.tool || "");
    const cpu =
      r.cpu_ratio != null
        ? ` · CPU ${Number(r.cpu_ratio).toFixed(2)}×`
        : "";
    return (
      `<article class="bench-card race-card" style="--d:${delay}s">` +
      `<header class="race-head">` +
      `<h3><code>${esc(r.tool)}</code></h3>` +
      `<span class="bench-tag win">${esc(Number(r.ratio).toFixed(2))}×</span>` +
      `</header>` +
      `<p class="race-cmd muted small"><span class="pkg-tag">${esc(pkg)}</span> · <code>${esc(r.command_f00 || "f00-" + r.tool + " --core")}</code>${esc(cpu)}</p>` +
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
  }

  function toolsByPackage(suite) {
    if (suite && suite.showcase_by_package) {
      return suite.showcase_by_package;
    }
    const by = { coreutils: [], grep: [], findutils: [], diffutils: [] };
    (suite && suite.tools ? suite.tools : []).forEach((t) => {
      if (t.status !== "ok" || t.ratio == null) return;
      const p = t.package || toolPackage(t.tool || "");
      if (!by[p]) by[p] = [];
      by[p].push({
        tool: t.tool,
        package: p,
        command_f00: t.command_f00,
        time_gnu_ms: t.time_gnu_ms,
        time_f00_ms: t.time_f00_ms,
        cpu_gnu_ms: t.cpu_gnu_ms,
        cpu_f00_ms: t.cpu_f00_ms,
        ratio: t.ratio,
        cpu_ratio: t.cpu_ratio,
      });
    });
    PKG_ORDER.forEach((p) => {
      by[p].sort((a, b) => (b.ratio || 0) - (a.ratio || 0));
    });
    return by;
  }

  function renderRaceCards(suite, packages, filterPkg) {
    const host = document.getElementById("race-grid");
    if (!host) return;
    const by = toolsByPackage(suite);
    const filter = filterPkg || "all";
    const pkgs =
      filter === "all" ? PKG_ORDER.slice() : PKG_ORDER.filter((p) => p === filter);

    // coreutils has ~90 timed tools — show top 12 in "all", all when filtered
    const CORE_CAP_ALL = 12;

    let html = "";
    let cardI = 0;
    pkgs.forEach((p) => {
      let rows = (by[p] || []).slice();
      if (!rows.length) {
        html +=
          `<section class="race-pkg" data-race-pkg="${esc(p)}">` +
          `<h3 class="subhead race-pkg-title">${esc(PKG_LABEL[p])} <span class="muted small">no timed races yet</span></h3>` +
          `</section>`;
        return;
      }
      const total = rows.length;
      let note = "";
      if (p === "coreutils" && filter === "all" && rows.length > CORE_CAP_ALL) {
        rows = rows.slice(0, CORE_CAP_ALL);
        note = ` · showing top ${CORE_CAP_ALL} of ${total} by wall × — open coreutils tab or scoreboard for all`;
      }
      const sum = (packages && packages[p]) || {};
      const wall = sum.headline_x || "—";
      const cpu =
        sum.headline_cpu_x ||
        (sum.cpu_ratio_geo != null
          ? `${Number(sum.cpu_ratio_geo).toFixed(1)}×`
          : "—");
      const maxMs = Math.max(
        ...rows.map((r) => Math.max(r.time_gnu_ms || 0, r.time_f00_ms || 0)),
        0.001
      );
      html +=
        `<section class="race-pkg" data-race-pkg="${esc(p)}">` +
        `<h3 class="subhead race-pkg-title">` +
        `${esc(PKG_LABEL[p])} ` +
        `<span class="muted small">wall ${esc(wall)} · CPU ${esc(cpu)} · ${total} timed${esc(note)}</span>` +
        `</h3>` +
        `<div class="bench-grid two race-pkg-grid">` +
        rows.map((r) => raceCardHtml(r, maxMs, cardI++)).join("") +
        `</div></section>`;
    });

    if (!html) {
      host.innerHTML = '<p class="muted">No showcase benches yet.</p>';
      return;
    }
    host.innerHTML = html;
    requestAnimationFrame(() => {
      host.classList.add("animate");
    });
  }

  function wireRacePkgTabs(suite, packages) {
    const tabs = document.getElementById("race-pkg-tabs");
    if (!tabs) {
      renderRaceCards(suite, packages, "all");
      return;
    }
    tabs.addEventListener("click", (ev) => {
      const btn = ev.target.closest(".pkg-tab");
      if (!btn) return;
      tabs.querySelectorAll(".pkg-tab").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      renderRaceCards(suite, packages, btn.getAttribute("data-race-pkg") || "all");
    });
    renderRaceCards(suite, packages, "all");
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

  function renderStats(tools, meta, summary, pkg) {
    const packageName = pkg || (summary && summary.package) || "coreutils";
    const label = PKG_LABEL[packageName] || packageName;
    const metaEl = document.getElementById("bench-meta");
    const stats = document.getElementById("bench-stats");
    const ok = (tools || []).filter((t) => t.status === "ok" && t.ratio != null);
    ok.sort((a, b) => b.ratio - a.ratio);

    if (metaEl) {
      const bits = [];
      if (summary && summary.headline) bits.push(`Wall ${summary.headline}`);
      else bits.push(`GNU ${label}`);
      if (summary && summary.headline_cpu) bits.push(summary.headline_cpu);
      if (meta && meta.machine) bits.push(meta.machine);
      if (meta && meta.generated_at) bits.push(meta.generated_at);
      bits.push("wall · CPU separate · per package");
      metaEl.textContent = bits.join(" · ");
    }

    const lbl = document.getElementById("stat-overall-lbl");
    if (lbl) lbl.textContent = `${label} wall`;

    if (!stats) return;
    if (!ok.length && !(summary && summary.tools_ok)) {
      stats.hidden = true;
      return;
    }
    stats.hidden = false;
    const ratios = ok.map((t) => t.ratio).sort((a, b) => a - b);
    const mid = ratios.length ? ratios[Math.floor(ratios.length / 2)] : null;
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
    set(
      "stat-tools",
      summary && summary.tools_ok != null
        ? String(summary.tools_ok)
        : String(ok.length)
    );
    set("stat-median", mid != null ? `${mid.toFixed(2)}×` : "—");
    set(
      "stat-best",
      best ? `${best.tool} ${best.ratio.toFixed(1)}×` : "—"
    );
    set("stat-n", meta && meta.n_runs ? String(meta.n_runs) : "—");
  }

  function updatePkgProgress(pkg, rows) {
    const bar = document.getElementById("pkg-progress");
    const fill = document.getElementById("pkg-progress-fill");
    const total = PKG_SHIPPED[pkg] || rows.length || 1;
    const shipped = rows.filter((r) => r.shipped === "yes" || r.shipped === true).length
      || (pkg === "coreutils" ? 106 : rows.length);
    const pct = Math.min(100, Math.round((shipped / total) * 100));
    if (fill) fill.style.width = `${pct}%`;
    if (bar) bar.setAttribute("aria-label", `shipped ${shipped} of ${total} (${pkg})`);
  }

  function rowHtml(r, bi) {
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
      const bits = [`wall ${fmtRatio(b.ratio)}`];
      if (b.cpu_ratio != null) bits.push(`CPU ${fmtRatio(b.cpu_ratio)}`);
      x = bits.join(" · ");
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
  }

  function renderScoreboard(progress, suite, packages, pkg) {
    const body = document.getElementById("scoreboard-body");
    if (!body) return;
    const bi = benchIndex(suite && suite.tools);
    let rows = [];
    if (pkg === "coreutils") {
      rows = (progress && progress.rows) || [];
      if (!rows.length) {
        body.innerHTML =
          '<tr><td colspan="9" class="muted">Missing coreutils-progress.json</td></tr>';
        return;
      }
    } else {
      rows = USERLAND[pkg] || [];
      if (!rows.length) {
        body.innerHTML =
          '<tr><td colspan="9" class="muted">No tools in this package set</td></tr>';
        return;
      }
    }
    body.innerHTML = rows.map((r) => rowHtml(r, bi)).join("");
    updatePkgProgress(pkg, rows);

    const pkgTools = (suite && suite.tools ? suite.tools : []).filter(
      (t) => (t.package || toolPackage(t.tool || "")) === pkg
    );
    const sum = (packages && packages[pkg]) || null;
    renderStats(pkgTools, suite && suite.meta, sum, pkg);
  }

  function wirePkgTabs(progress, suite, packages) {
    const tabs = document.getElementById("pkg-tabs");
    if (!tabs) {
      renderScoreboard(progress, suite, packages, "coreutils");
      return;
    }
    tabs.addEventListener("click", (ev) => {
      const btn = ev.target.closest(".pkg-tab");
      if (!btn) return;
      tabs.querySelectorAll(".pkg-tab").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      renderScoreboard(
        progress,
        suite,
        packages,
        btn.getAttribute("data-pkg") || "coreutils"
      );
    });
    renderScoreboard(progress, suite, packages, "coreutils");
  }

  Promise.all([
    fetch("coreutils-progress.json", { headers: { Accept: "application/json" } })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null),
    fetch("bench/suite.json", { headers: { Accept: "application/json" } })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null),
  ]).then(([progress, suite]) => {
    const packages = suite ? packagesFromSuite(suite) : null;
    if (suite) {
      renderPackageCards(packages, suite.meta);
      wireRacePkgTabs(suite, packages);
      renderColdChart(suite.cold_startup);
    } else {
      renderPackageCards(
        {
          coreutils: { headline_x: "—", tools_ok: 0, headline: "pending" },
          grep: { headline_x: "—", tools_ok: 0, headline: "pending" },
          findutils: { headline_x: "—", tools_ok: 0, headline: "pending" },
          diffutils: { headline_x: "—", tools_ok: 0, headline: "pending" },
        },
        null
      );
    }
    wirePkgTabs(progress, suite, packages);
  });
})();
