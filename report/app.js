// win-clean report app. Pure functions first (tested via Node), then DOM wiring.
'use strict';

var LEVELS = {
  1: { color: '#3fbf7f', icon: '🟢', name: '可再生缓存', policy: '默认勾选 · 直接删除' },
  2: { color: '#e0c55d', icon: '🟡', name: '系统垃圾',   policy: '默认勾选 · 直接删除' },
  3: { color: '#e0a55d', icon: '🟠', name: '应用缓存',   policy: '手动勾选 · 进可恢复区' },
  4: { color: '#e05d5d', icon: '🔴', name: '深度发现',   policy: '逐项确认 · 进可恢复区' },
  5: { color: '#8a8f9e', icon: '⚫', name: '专家区',     policy: '仅报告 · 给出命令' }
};

function fmtBytes(n) {
  if (!isFinite(n) || n < 0) return '—';
  var u = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return (i === 0 ? n : n.toFixed(1)) + ' ' + u[i];
}

// Squarified treemap. children: [{area:...}]; mutates+returns items with x,y,w,h.
function squarify(children, x, y, w, h) {
  if (!children || children.length === 0 || w <= 0 || h <= 0) return [];
  var total = children.reduce(function (s, c) { return s + c.area; }, 0);
  if (total <= 0) return [];
  var scale = (w * h) / total;
  var items = children.map(function (c) { c._a = c.area * scale; return c; })
    .sort(function (a, b) { return b._a - a._a; });
  function worst(row, len) {
    var s = row.reduce(function (t, c) { return t + c._a; }, 0);
    var max = row[0]._a, min = row[row.length - 1]._a;
    var s2 = s * s, len2 = len * len;
    return Math.max(len2 * max / s2, s2 / (len2 * min));
  }
  var rx = x, ry = y, rw = w, rh = h, i = 0;
  while (i < items.length) {
    var shorter = Math.min(rw, rh);
    var row = [items[i]], j = i + 1;
    while (j < items.length && worst(row.concat([items[j]]), shorter) <= worst(row, shorter)) {
      row.push(items[j]); j++;
    }
    var s = row.reduce(function (t, c) { return t + c._a; }, 0);
    if (rw >= rh) {
      var stripW = s / rh, yy = ry;
      row.forEach(function (c) { var ch = c._a / stripW; c.x = rx; c.y = yy; c.w = stripW; c.h = ch; yy += ch; });
      rx += stripW; rw -= stripW;
    } else {
      var stripH = s / rw, xx = rx;
      row.forEach(function (c) { var cw = c._a / stripH; c.x = xx; c.y = ry; c.w = cw; c.h = stripH; xx += cw; });
      ry += stripH; rh -= stripH;
    }
    i = j;
  }
  return items;
}

// ---------- page wiring (browser only) ----------
function initPage() {
  if (typeof document === 'undefined' || !window.SCAN_DATA) return;
  var data = window.SCAN_DATA;
  var mode = window.SERVE_MODE || 'auto';           // 'auto' | 'static'
  var selected = {};                                 // id -> true
  data.findings.forEach(function (f) { if (f.auto_select && f.level <= 2) selected[f.id] = true; });

  function el(id) { return document.getElementById(id); }
  function selectedBytes() {
    return data.findings.filter(function (f) { return selected[f.id]; })
      .reduce(function (s, f) { return s + f.bytes; }, 0);
  }
  function refreshBar() {
    var n = Object.keys(selected).length;
    el('sel-count').textContent = n + ' 项';
    el('sel-bytes').textContent = fmtBytes(selectedBytes());
  }
  function toggle(id) {
    if (selected[id]) delete selected[id]; else selected[id] = true;
    refreshBar();
    var cb = document.querySelector('[data-cb-id="' + id + '"]');
    if (cb) cb.checked = !!selected[id];
    renderTreemap();
  }

  function renderDashboard() {
    el('stat-releasable').textContent = fmtBytes(data.totalBytes);
    el('stat-count').textContent = data.findings.length;
    el('drive-bars').innerHTML = data.drives.map(function (d) {
      var pct = d.total ? Math.round((d.total - d.free) / d.total * 100) : 0;
      var color = pct > 90 ? '#e05d5d' : (pct > 75 ? '#e0c55d' : '#3fbf7f');
      return '<div class="drive-row"><span>' + d.letter + '</span>' +
        '<div class="drive-track"><div class="drive-fill" style="width:' + pct + '%;background:' + color + '"></div></div>' +
        '<span>' + pct + '% · 剩 ' + fmtBytes(d.free) + '</span></div>';
    }).join('');
  }

  function renderTreemap() {
    var host = el('treemap');
    var W = host.clientWidth || 900, H = host.clientHeight || 420;
    var items = data.findings.filter(function (f) { return f.bytes > 0; })
      .map(function (f) { return { finding: f, area: f.bytes }; });
    var laid = squarify(items, 0, 0, W, H);
    host.innerHTML = laid.map(function (c) {
      var f = c.finding, meta = LEVELS[f.level];
      var dim = selected[f.id] ? '' : 'opacity:.45;';
      var label = (c.w > 70 && c.h > 34)
        ? '<div class="tm-name">' + f.name + '</div><div class="tm-size">' + fmtBytes(f.bytes) + '</div>' : '';
      return '<div class="tm-cell" style="left:' + c.x + 'px;top:' + c.y + 'px;width:' + c.w + 'px;height:' + c.h +
        'px;background:' + meta.color + ';' + dim + '" data-tm-id="' + f.id + '" title="' + f.name + ' · ' +
        fmtBytes(f.bytes) + ' · L' + f.level + '">' + label + '</div>';
    }).join('');
    Array.prototype.forEach.call(host.querySelectorAll('[data-tm-id]'), function (node) {
      node.onclick = function () { toggle(node.getAttribute('data-tm-id')); };
      node.ondblclick = function () { showDetail(node.getAttribute('data-tm-id')); };
    });
  }

  function renderList() {
    var html = '';
    [1, 2, 3, 4, 5].forEach(function (lv) {
      var fs = data.findings.filter(function (f) { return f.level === lv; });
      if (!fs.length) return;
      var m = LEVELS[lv];
      html += '<div class="lv-group" style="border-left:3px solid ' + m.color + '">' +
        '<div class="lv-head">' + m.icon + ' L' + lv + ' ' + m.name +
        '<span class="lv-policy">' + m.policy + '</span></div>';
      fs.forEach(function (f) {
        html += '<label class="lv-item"><input type="checkbox" data-cb-id="' + f.id + '"' +
          (selected[f.id] ? ' checked' : '') + (f.strategy === 'report-only' ? ' disabled' : '') + '>' +
          '<span class="lv-name">' + f.name + (f.needs_admin ? ' 🔒需管理员' : '') + '</span>' +
          '<span class="lv-bytes">' + fmtBytes(f.bytes) + '</span>' +
          '<a href="#" data-detail="' + f.id + '">详情</a></label>';
      });
      html += '</div>';
    });
    el('level-list').innerHTML = html;
    Array.prototype.forEach.call(el('level-list').querySelectorAll('[data-cb-id]'), function (cb) {
      cb.onchange = function () { toggle(cb.getAttribute('data-cb-id')); };
    });
    Array.prototype.forEach.call(el('level-list').querySelectorAll('[data-detail]'), function (a) {
      a.onclick = function (e) { e.preventDefault(); showDetail(a.getAttribute('data-detail')); };
    });
  }

  function showDetail(id) {
    var f = data.findings.filter(function (x) { return x.id === id; })[0];
    if (!f) return;
    var m = LEVELS[f.level];
    el('detail').innerHTML = '<h3>' + m.icon + ' ' + f.name + '</h3>' +
      '<p>' + f.desc + '</p><p>等级 L' + f.level + ' · ' + m.policy + ' · 来源 ' + f.source + ' · ' + fmtBytes(f.bytes) + '</p>' +
      '<pre>' + f.paths.map(function (p) { return p.expanded || p.path + ' (未展开)'; }).join('\n') + '</pre>' +
      (f.strategy === 'report-only' ? '<p class="warn">此项仅报告，需按报告内命令手动处理</p>' : '');
    el('detail').style.display = 'block';
  }

  function submitSelection() {
    var payload = JSON.stringify({ ids: Object.keys(selected), ts: new Date().toISOString() });
    if (mode === 'auto') {
      fetch('/api/select', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: payload })
        .then(function (r) { return r.json(); })
        .then(function (j) {
          el('submit-result').textContent = j.ok ? '✅ 已提交，可关闭页面回到终端' : '提交失败：' + (j.error || '');
          if (j.ok && window.fetch) fetch('/shutdown', { method: 'POST' }).catch(function () {});
        })
        .catch(function (e) { el('submit-result').textContent = '提交失败，请使用复制命令方式：' + e; });
    } else {
      var b64 = btoa(unescape(encodeURIComponent(payload)));
      var cmd = '$d=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\'' + b64 +
        '\')); Set-Content -Path "$env:TEMP\\win-clean-selection.json" -Value $d -Encoding UTF8; Write-Output done';
      el('submit-result').innerHTML = '<p>复制下面命令到终端执行：</p><pre>' + cmd + '</pre>';
      if (navigator.clipboard) navigator.clipboard.writeText(cmd);
    }
  }

  renderDashboard(); renderTreemap(); renderList(); refreshBar();
  window.addEventListener('resize', renderTreemap);
  el('submit-btn').onclick = submitSelection;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { fmtBytes: fmtBytes, squarify: squarify, LEVELS: LEVELS };
}
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initPage);
  else initPage();
}
