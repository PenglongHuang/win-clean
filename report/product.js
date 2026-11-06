'use strict';
const M=window.WinClean,$=id=>document.getElementById(id);
let state={},selected=new Set(),tab='recommended',query='',lastRun='',lastPhase='',disksDrawn=false,pending=false,choosing=false,reviewId=null,directoryFocus='',directoryHistory=[],visibleLimit=20;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function api(path,body){const r=await fetch('/api/'+path,{method:body===undefined?'GET':'POST',headers:{'X-Session-Token':window.SESSION_TOKEN,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error(data.error||'请求失败');return data;}
function notice(text){$('notice').textContent=text;$('notice').hidden=!text;}
async function action(fn){if(pending)return;pending=true;try{notice('');await fn();await poll();}catch(e){notice(e.message);}finally{pending=false;}}
function show(id){for(const name of ['choose','busy','results','done'])$(name).hidden=name!==id;}
function drawDisks(){if(disksDrawn)return;disksDrawn=true;const initial=(state.initialDrives||'').split(',').map(x=>x.trim().toUpperCase());$('disks').innerHTML=state.disks.map(d=>{let pct=d.total?Math.round((d.total-d.free)/d.total*100):0;return `<label class="disk"><div class="disk-head"><input type="checkbox" value="${esc(d.letter)}" ${initial.includes(d.letter)||(!initial[0]&&d.letter==='C')?'checked':''}><b>${esc(d.letter)}:</b><small>${esc(d.label||'本地磁盘')}</small></div><div class="track"><span style="width:${pct}%"></span></div><p>剩余 ${M.fmt(d.free)} / ${M.fmt(d.total)} · 已用 ${pct}%</p></label>`;}).join('');}
function updateSelection(){const t=M.totals(state.scan?.findings||[],[...selected]);$('chosen').textContent=`已选 ${t.count} 项`;$('estimate').textContent=`预计释放 ${M.fmt(t.release)}${t.quarantine?' · 移入恢复区 '+M.fmt(t.quarantine):''}${t.admin?' · 需管理员 '+M.fmt(t.admin):''}`;$('preview').disabled=!t.count;}
function drawList(){const all=M.visible(state.scan?.findings||[],query,tab),fs=all.slice(0,visibleLimit);$('list').innerHTML=fs.map(f=>`<article class="item"><input type="checkbox" aria-label="选择${esc(f.name)}" data-id="${esc(f.id)}" ${selected.has(f.id)?'checked':''} ${!M.selectable(f)?'disabled':''}><div><b>${esc(f.name)}</b>${f.needs_admin?'<span class="badge">需管理员</span>':''}<p>${esc(f.desc)}</p><details><summary>查看路径与处理方式</summary><p>${f.strategy==='delete-permanent'?'直接删除 · 无法通过本工具恢复':f.strategy==='recycle-bin'?'移入可恢复区 · 同盘移动通常不释放空间':'仅供查看 · 不执行清理'}</p>${(f.paths||[]).filter(p=>p.exists).map(p=>`<div class="path">${esc(p.expanded)} · ${M.fmt(p.bytes)}</div>`).join('')}<p>规则等级 L${f.level}</p></details></div><span class="size">${M.fmt(f.bytes)}</span></article>`).join('')||'<p class="empty">此分类下没有发现项目。可切换“全部项目”，或查看下方空间大户。</p>';
 if(all.length>visibleLimit){const more=document.createElement('button');more.textContent='再显示 20 项（还有 '+(all.length-visibleLimit)+' 项）';more.onclick=()=>{visibleLimit+=20;drawList();};$('list').appendChild(more);}
 $('list').querySelectorAll('[data-id]').forEach(cb=>cb.onchange=()=>{cb.checked?selected.add(cb.dataset.id):selected.delete(cb.dataset.id);updateSelection();});updateSelection();}
function drawDirectories(){
 const d=state.discovery,dirs=d?.directories||[];
 const rows=M.directoryRows(dirs,d?.roots||[],directoryFocus);
 const focus=directoryFocus?dirs.find(x=>x.path===directoryFocus):null,partition=M.directorySummary(dirs,d?.roots||[],directoryFocus);
 $('directories').innerHTML=`<div class="directory-nav"><button id="dir-root">全部所选磁盘</button>${directoryFocus?'<button id="dir-back">返回上层</button><span class="path">'+esc(directoryFocus)+'</span>':''}</div>`+
  (focus?`<p class="hint">此目录${focus.complete?'':'已统计'} ${M.fmt(focus.bytes)} · 本层文件 ${M.fmt(focus.directBytes||0)}；下方仅列同层子目录。</p>`:'<p class="hint">每行代表一个独立目录，点击查看其子目录；不混排父目录和子目录。</p>')+
  (rows.map((x,i)=>`<div class="space-row"><button data-directory="${i}" class="directory-link">${esc(x.path)}</button><b>${x.complete?'':'已统计 '}${M.fmt(x.bytes)}</b></div>`).join('')||'<p class="hint">未发现达到 100 MB 的子目录；本层文件已包含在目录大小内。</p>');
 if(partition.direct)$('directories').insertAdjacentHTML('beforeend',`<div class="space-row"><span>本层直接文件（不包含子目录）</span><b>${M.fmt(partition.direct)}</b></div>`);
 if(partition.other)$('directories').insertAdjacentHTML('beforeend',`<div class="space-row"><span>其他小目录（每项小于 100 MB）</span><b>${M.fmt(partition.other)}</b></div>`);
 $('dir-root').onclick=()=>{directoryFocus='';directoryHistory=[];drawDirectories();};
 if($('dir-back'))$('dir-back').onclick=()=>{directoryFocus=directoryHistory.pop()||'';drawDirectories();};
 $('directories').querySelectorAll('[data-directory]').forEach(b=>b.onclick=()=>{directoryHistory.push(directoryFocus);directoryFocus=rows[Number(b.dataset.directory)].path;drawDirectories();});
}
function drawResults(){const fs=state.scan?.findings||[],t=M.totals(fs,fs.map(f=>f.id));$('release').textContent=M.fmt(t.release);$('quarantine').textContent=M.fmt(t.quarantine);const d=state.discovery;
 const reviewCount=fs.filter(f=>M.selectable(f)&&!M.recommended(f)&&f.bytes>0).length;
 $('coverage').textContent=(state.cancelled?'扫描已停止，以下为部分结果。 ':d?`检查了 ${d.files.toLocaleString()} 个文件 · 已统计 ${M.fmt(d.scannedBytes)}${d.reason==='budget'?' · 达到指定预算，结果不完整':''}${d.inaccessible?' · '+d.inaccessible+' 个位置无法访问':''}${d.skippedLinks?' · 跳过 '+d.skippedLinks+' 个链接':''}。 `:'已完成规则扫描。 ')+(reviewCount?`发现 ${reviewCount} 项需要核对的清理候选；个人资料与项目依赖仅供查看。`:'未发现经过识别的清理候选；可查看空间分布，不能仅凭体积判断可删。');
 if(!fs.some(f=>M.recommended(f)&&f.bytes>0)&&reviewCount)tab='review';
 document.querySelectorAll('[data-tab]').forEach(b=>{const key=b.dataset.tab,count=M.visible(fs,'',key).length;b.textContent=({recommended:'建议清理',review:'需要确认',all:'全部项目'}[key])+` (${count})`;b.setAttribute('aria-pressed',String(key===tab));});
 $('large').hidden=!d;if(d){$('large').open=true;drawDirectories();}
 $('files').innerHTML=(d?.largeFiles||[]).map(x=>`<div class="space-row"><span>${esc(x.path)}</span><b>${M.fmt(x.bytes)}</b></div>`).join('')||'<p class="hint">本次范围内未发现达到 100 MB 的文件。</p>';drawList();}
function review(){reviewId=state.previewId;selected=new Set((state.selectedIds||[]).filter(Boolean));const fs=(state.scan?.findings||[]).filter(f=>selected.has(f.id));$('review-items').innerHTML=fs.map(f=>`<div class="review-item"><b>${esc(f.name)} · ${M.fmt(f.bytes)}</b><p>${f.strategy==='delete-permanent'?'直接删除':'移入可恢复区'}${f.needs_admin?' · 需管理员，本次可能跳过':''}</p>${(f.paths||[]).filter(p=>p.exists).map(p=>`<div class="path">${esc(p.expanded)}</div>`).join('')}</div>`).join('');const s=state.summary;$('review-summary').textContent=`演练预计释放 ${M.fmt(s?.freedBytes||0)} · 拒绝处理 ${s?.refusedCount||0} 项 · 错误 ${s?.errorCount||0} 项`;$('review').showModal();}
function render(){drawDisks();const phase=state.phase;
 if(state.run!==lastRun){lastRun=state.run;visibleLimit=20;directoryFocus='';directoryHistory=[];selected=new Set((state.selectedIds||[]).filter(Boolean));}
 if(choosing&&!['scanning','previewing','executing'].includes(phase))return;choosing=false;
 if(phase==='idle')show('choose');
 else if(['scanning','previewing','executing'].includes(phase)){
  show('busy');$('cancel').hidden=phase!=='scanning';$('busy-title').textContent=phase==='scanning'?'正在检查磁盘空间':phase==='previewing'?'正在演练清理方案':'正在处理已确认的项目';
  const p=state.progress||{};$('busy-text').textContent=phase==='scanning'?(p.phase==='discovery'?`目录分析 · 已检查 ${p.files||0} 个文件 · ${M.fmt(p.bytesSoFar||0)}`:`已知缓存检查 · ${p.done||0} / ${p.total||'…'} 项`):phase==='previewing'?'演练不会删除文件，完成后会展示核对清单。':'处理完成后会显示执行记录与恢复脚本位置。';
  $('current').textContent=phase==='scanning'?(p.currentName||'准备扫描…'):'';
  if(p.total&&p.phase!=='discovery'&&phase==='scanning'){$('progress').max=p.total;$('progress').value=p.done;}else $('progress').removeAttribute('value');
 }else if(['results','preview'].includes(phase)){
  show('results');if(lastPhase!==phase){drawResults();if(phase==='preview')review();}
 }else if(phase==='done'){
  show('done');const s=state.summary||{};$('outcome').textContent=`已删除项目的扫描大小 ${M.fmt(s.freedBytes||0)}。实际空闲空间变化还会受到其他程序与文件系统影响。`;
  $('done-details').innerHTML=`<p>错误 ${s.errorCount||0} 项 · 保护规则拒绝 ${s.refusedCount||0} 项</p><p>执行日志</p><div class="path">${esc(s.logFile)}</div><p>可恢复项目的恢复脚本（直接删除项不可恢复）</p><div class="path">${esc(s.restoreFile||'本次无恢复脚本')}</div>`;
 }else if(phase==='error'){show('choose');notice((state.error||'任务未完成')+' 日志保存在：'+(state.run||''));}
 lastPhase=phase;
}
async function poll(){try{state=await api('state');render();}catch(e){notice('无法连接本地服务。请重新运行 Start-WinClean，再打开页面。');}}
$('scan').onclick=()=>action(async()=>{const drives=[...$('disks').querySelectorAll('input:checked')].map(x=>x.value);if(!drives.length)throw Error('请至少选择一个磁盘。');$('cancel').disabled=false;$('cancel').textContent='停止扫描，保留已发现结果';await api('scan',{drives,mode:document.querySelector('[name=mode]:checked').value});});
$('cancel').onclick=()=>action(async()=>{await api('cancel',{});$('cancel').disabled=true;$('cancel').textContent='正在停止，请稍候…';});
$('preview').onclick=()=>action(()=>api('preview',{ids:[...selected]}));
$('execute').onclick=()=>action(async()=>{$('review').close();await api('execute',{previewId:reviewId});});
$('back').onclick=()=>$('review').close();
for(const id of ['again','restart'])$(id).onclick=()=>{choosing=true;show('choose');};
document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{tab=b.dataset.tab;visibleLimit=20;document.querySelectorAll('[data-tab]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));drawList();});
$('search').oninput=e=>{query=e.target.value;visibleLimit=20;drawList();};
poll();setInterval(poll,1200);
