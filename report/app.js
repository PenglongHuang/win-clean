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

function findingOnDrive(f, drive) { var prefix = String(drive).replace(/:$/, '').toUpperCase() + ':'; return (f.paths || []).some(function(p) { return String(p.expanded || p.path || '').slice(0,2).toUpperCase() === prefix; }); }
var CELL_COLORS = { 1: {light:'#c4efdc', dark:'#155e43'}, 2: {light:'#f8e8b0', dark:'#665000'}, 3: {light:'#f8dccc', dark:'#803d22'}, 4: {light:'#f8d7d7', dark:'#842b32'}, 5: {light:'#d9e5f4', dark:'#304f76'} };
function canBulkSelect(f) { return f.level <= 3 && f.strategy !== 'report-only'; }
function escapeHtml(v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function(c) { return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }

// ---------- page wiring (browser only) ----------
function initPage() {
  if (typeof document === 'undefined' || !window.SCAN_DATA) return;
  var data = window.SCAN_DATA;
  var mode = window.SERVE_MODE || 'auto';           // 'auto' | 'static'
  var query = '';
  var activeDrive = '';
  function visibleFinding(f) { return (!activeDrive || findingOnDrive(f, activeDrive)) && (!query || String(f.name).toLowerCase().indexOf(query) >= 0); }
  var selected = {};                                 // id -> true
  data.findings.forEach(function (f) { if (f.auto_select && f.level <= 2 && f.strategy !== 'report-only') selected[f.id] = true; });

  function el(id) { return document.getElementById(id); }
  function selectedBytes() {
    return data.findings.filter(function (f) { return selected[f.id]; })
      .reduce(function (s, f) { return s + f.bytes; }, 0);
  }
  function refreshBar() {
    var n = Object.keys(selected).length;
    el('sel-count').textContent = n + ' 项';
    el('sel-bytes').textContent = fmtBytes(selectedBytes());
    var chosen = data.findings.filter(function(f) { return !!selected[f.id]; });
    el('selection-summary').innerHTML = chosen.length ? chosen.map(function(f) { return '<div>' + escapeHtml(f.name) + ' · ' + fmtBytes(f.bytes) + ' · ' + LEVELS[f.level].policy + (f.needs_admin ? ' · 需管理员' : '') + '</div>'; }).join('') : '尚未选择项目';
  }
  function toggle(id) {
    if (selected[id]) delete selected[id]; else selected[id] = true;
    refreshBar();
    var cb = Array.prototype.find.call(document.querySelectorAll('[data-cb-id]'), function (x) { return x.getAttribute('data-cb-id') === id; });
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
    var width = host.clientWidth || 900;
    host.innerHTML = '';
    [4,3,2,1,5].forEach(function(lv) {
      var findings = data.findings.filter(function(f) { return f.level === lv && f.bytes > 0 && visibleFinding(f); });
      if (!findings.length) return;
      var meta = LEVELS[lv], group = document.createElement('section');
      group.className = 'map-group';
      var title = document.createElement('div'); title.className = 'map-heading';
      title.textContent = meta.icon + ' ' + meta.name + ' · ' + fmtBytes(findings.reduce(function(n,f) { return n + f.bytes; }, 0));
      var area = document.createElement('div'); area.className = 'map-area';
      group.appendChild(title); group.appendChild(area); host.appendChild(group);
      var H = 112;
      var laid = squarify(findings.map(function(f) { return { finding:f, area:f.bytes }; }), 0, 0, width, H);
      area.innerHTML = laid.map(function(c) {
        var f = c.finding, selectable = f.strategy !== 'report-only';
        var label = (c.w > 70 && c.h > 34) ? '<div class="tm-name">' + escapeHtml(f.name) + '</div><div class="tm-size">' + fmtBytes(f.bytes) + '</div>' : '';
        return '<div class="tm-cell' + (selected[f.id] ? ' selected' : '') + '" role="' + (selectable ? 'checkbox' : 'button') + '" tabindex="0" ' + (selectable ? 'aria-checked="' + (!!selected[f.id]) + '"' : '') + ' aria-label="' + escapeHtml(f.name) + '" style="left:' + c.x + 'px;top:' + c.y + 'px;width:' + c.w + 'px;height:' + c.h + 'px;--cell-light:' + CELL_COLORS[lv].light + ';--cell-dark:' + CELL_COLORS[lv].dark + ';" data-tm-id="' + escapeHtml(f.id) + '" title="' + escapeHtml(f.name) + ' · ' + fmtBytes(f.bytes) + '">' + (selectable ? '<span class="tm-check" aria-hidden="true">' + (selected[f.id] ? '✓' : '') + '</span>' : '') + label + '</div>';
      }).join('');
    });
    if (!host.children.length) host.innerHTML = '<p class="empty">没有可显示的地图项目。</p>';
    Array.prototype.forEach.call(host.querySelectorAll('[data-tm-id]'), function (node) {
      node.onclick = function () { var f = data.findings.find(function(x) { return x.id === node.getAttribute('data-tm-id'); }); if (f && f.strategy !== 'report-only') toggle(f.id); else if (f) showDetail(f.id); };
      node.onkeydown = function(e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); node.click(); } };
    });
  }

  function setLevel(lv, on) {
    data.findings.forEach(function (f) {
      if (f.level === lv && visibleFinding(f) && canBulkSelect(f)) {
        if (on) selected[f.id] = true; else delete selected[f.id];
      }
    });
    refreshBar(); renderTreemap(); renderList();
  }
  function setAll(on) {
    data.findings.forEach(function (f) {
      if (!on || (visibleFinding(f) && canBulkSelect(f))) {
        if (on) selected[f.id] = true; else delete selected[f.id];
      }
    });
    refreshBar(); renderTreemap(); renderList();
  }

  function renderList() {
    var html = '';
    [1, 2, 3, 4, 5].forEach(function (lv) {
      var fs = data.findings.filter(function (f) { return f.level === lv && visibleFinding(f); });
      if (!fs.length) return;
      var m = LEVELS[lv];
      html += '<div class="lv-group" style="border-left:3px solid ' + m.color + '">' +
        '<div class="lv-head">' + m.icon + ' L' + lv + ' ' + m.name +
        '<span class="lv-policy">' + m.policy + '</span>' +
        (lv <= 3 ? '<span class="lv-ops"><button type="button" data-op="all" data-lv="' + lv + '">全选</button><button type="button" data-op="none" data-lv="' + lv + '">清空</button></span>' : '') +
        '</div>';
      fs.forEach(function (f) {
        html += '<label class="lv-item"><input type="checkbox" data-cb-id="' + escapeHtml(f.id) + '"' +
          (selected[f.id] ? ' checked' : '') + (f.strategy === 'report-only' ? ' disabled' : '') + '>' +
          '<span class="lv-name">' + escapeHtml(f.name) + (f.needs_admin ? ' 🔒需管理员' : '') + '</span>' +
          '<span class="lv-bytes">' + fmtBytes(f.bytes) + '</span>' +
          '<a href="#" data-detail="' + escapeHtml(f.id) + '">详情</a></label>';
      });
      html += '</div>';
    });
    el('level-list').innerHTML = html || '<p class="empty">没有找到匹配的项目，请换个关键词。</p>';
    Array.prototype.forEach.call(el('level-list').querySelectorAll('[data-cb-id]'), function (cb) {
      cb.onchange = function () { toggle(cb.getAttribute('data-cb-id')); };
    });
    Array.prototype.forEach.call(el('level-list').querySelectorAll('[data-detail]'), function (a) {
      a.onclick = function (e) { e.preventDefault(); showDetail(a.getAttribute('data-detail')); };
    });
    Array.prototype.forEach.call(el('level-list').querySelectorAll('[data-op]'), function (a) {
      a.onclick = function (e) {
        e.preventDefault();
        setLevel(parseInt(a.getAttribute('data-lv'), 10), a.getAttribute('data-op') === 'all');
      };
    });
  }

  var modalOrigin = null;
  function closeDetail() { el('detail').classList.remove('open'); if (modalOrigin && modalOrigin.isConnected) modalOrigin.focus(); }
  function showDetail(id) {
    modalOrigin = document.activeElement;
    var f = data.findings.filter(function (x) { return x.id === id; })[0];
    if (!f) return;
    var m = LEVELS[f.level];
    el('detail-card').innerHTML = '<button class="close-x" id="detail-x" aria-label="关闭">✕</button><h3>' + m.icon + ' ' + escapeHtml(f.name) + '</h3>' +
      '<p>' + escapeHtml(f.desc) + '</p><p>等级 L' + f.level + ' · ' + m.policy + ' · 来源 ' + escapeHtml(f.source) + ' · ' + fmtBytes(f.bytes) + '</p>' +
      '<pre>' + f.paths.map(function (p) { return escapeHtml(p.expanded || p.path + ' (未展开)'); }).join('\n') + '</pre>' +
      (f.strategy === 'report-only' ? '<p class="warn">此项仅报告，需按报告内命令手动处理</p>' : '');
    el('detail').classList.add('open');
    el('detail-x').onclick = closeDetail; el('detail-x').focus();
  }


  function showStaticCommand(payload, message) {
    var b64 = btoa(unescape(encodeURIComponent(payload)));
    var cmd = '$d=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\'' + b64 + '\')); Set-Content -Path "$env:TEMP\\win-clean-selection.json" -Value $d -Encoding UTF8; Write-Output done';
    el('submit-result').innerHTML = '<p>' + message + '</p><pre>' + escapeHtml(cmd) + '</pre>';
  }
  function submitSelection() {
    if (!Object.keys(selected).length) { el('submit-result').textContent = '请先选择清理项目'; return; }
    var payload = JSON.stringify({ ids: Object.keys(selected), ts: new Date().toISOString(), scanHash: window.SCAN_HASH });
    if (mode === 'auto') {
      fetch('/api/select', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Session-Token': window.SESSION_TOKEN }, body: payload })
        .then(function (r) { return r.json(); })
        .then(function (j) {
          el('submit-result').textContent = j.ok ? '✅ 已提交，可关闭页面回到终端' : '提交失败：' + (j.error || '');
          if (j.ok) { el('submit-btn').disabled = true; el('submit-btn').textContent = '已提交'; }

        })
        .catch(function (e) { showStaticCommand(payload, '提交失败。请复制下面的命令到终端执行：'); });
    } else {
      showStaticCommand(payload, '复制下面的命令到终端执行：');
    }
  }

  var tabs = el('drive-tabs');
  var letters = (data.drives || []).map(function(d) { return String(d.letter); }).filter(function(d) { return data.findings.some(function(f) { return findingOnDrive(f,d); }); });
  function drawDriveTabs() {
    tabs.innerHTML = '<button type="button" data-drive="" aria-pressed="' + (!activeDrive) + '">全部磁盘</button>' + letters.map(function(d) { return '<button type="button" data-drive="' + escapeHtml(d) + '" aria-pressed="' + (activeDrive === d) + '">' + escapeHtml(d) + ' 盘</button>'; }).join('');
    Array.prototype.forEach.call(tabs.querySelectorAll('button'), function(b) { b.onclick = function() { activeDrive = b.getAttribute('data-drive'); drawDriveTabs(); renderTreemap(); renderList(); }; });
  }
  drawDriveTabs(); renderDashboard(); renderTreemap(); renderList(); refreshBar();
  window.addEventListener('resize', renderTreemap);
  el('submit-btn').onclick = submitSelection;
  el('search').oninput = function() { query = this.value.trim().toLowerCase(); renderList(); renderTreemap(); };
  el('view-map').onclick = function() { el('treemap').hidden = false; renderTreemap(); el('view-map').setAttribute('aria-pressed', 'true'); el('view-list').setAttribute('aria-pressed', 'false'); };
  el('view-list').onclick = function() { el('treemap').hidden = true; el('view-map').setAttribute('aria-pressed', 'false'); el('view-list').setAttribute('aria-pressed', 'true'); };
  el('sel-all').onclick = function (e) { e.preventDefault(); setAll(true); };
  el('sel-none').onclick = function (e) { e.preventDefault(); setAll(false); };
  el('detail').onclick = function (e) { if (e.target === el('detail')) closeDetail(); };
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeDetail(); });
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { fmtBytes: fmtBytes, squarify: squarify, LEVELS: LEVELS, canBulkSelect: canBulkSelect, findingOnDrive: findingOnDrive, CELL_COLORS: CELL_COLORS };
}
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initPage);
  else initPage();
}
