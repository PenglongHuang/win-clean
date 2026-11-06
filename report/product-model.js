(function(root){
'use strict';
function selectable(f){return f.strategy==='delete-permanent'||f.strategy==='recycle-bin';}
function recommended(f){return selectable(f)&&f.level<=2&&!f.needs_admin;}
function normalizePath(p){return String(p||'').replace(/\//g,'\\').replace(/\\+$/,'').toLowerCase();}
function within(child,parent){return child===parent||child.startsWith(parent+'\\');}
function totals(fs,ids){const result={release:0,quarantine:0,admin:0,count:0},paths=[];for(const f of fs.filter(f=>ids.includes(f.id)&&selectable(f))){result.count++;const kind=f.needs_admin?'admin':f.strategy==='delete-permanent'?'release':'quarantine';const ps=(f.paths||[]).filter(p=>p.exists&&p.expanded);if(!ps.length){paths.push({path:'@'+f.id,bytes:f.bytes,kind});continue;}for(const p of ps)paths.push({path:normalizePath(p.expanded),bytes:p.bytes,kind});}paths.sort((a,b)=>a.path.length-b.path.length);const claimed=[];for(const p of paths){if(claimed.some(c=>within(p.path,c)))continue;claimed.push(p.path);result[p.kind]+=p.bytes;}return result;}
function directoryRows(dirs,roots,current){const parents=current?[current]:roots;return dirs.filter(d=>parents.some(p=>normalizePath(d.parent)===normalizePath(p))&&!parents.some(p=>normalizePath(d.path)===normalizePath(p))).sort((a,b)=>b.bytes-a.bytes);}
function directorySummary(dirs,roots,current){const parents=current?[current]:roots;const own=dirs.filter(d=>parents.some(p=>normalizePath(p)===normalizePath(d.path)));const total=own.reduce((n,d)=>n+d.bytes,0),direct=own.reduce((n,d)=>n+(d.directBytes||0),0),children=directoryRows(dirs,roots,current).reduce((n,d)=>n+d.bytes,0);return {total,direct,other:Math.max(0,total-direct-children)};}
function visible(fs,query,tab){return fs.filter(f=>f.bytes>0&&(!query||(f.name+' '+(f.desc||'')+' '+(f.paths||[]).map(p=>p.expanded).join(' ')).toLowerCase().includes(query.toLowerCase()))&&(tab==='all'||(tab==='recommended'?recommended(f):tab==='review'?selectable(f)&&!recommended(f):!selectable(f)))).sort((a,b)=>b.bytes-a.bytes);}
function fmt(n){let u=['B','KB','MB','GB','TB'],i=0;while(n>=1024&&i<4){n/=1024;i++;}return (i?n.toFixed(1):n)+' '+u[i];}
const api={selectable,recommended,totals,visible,fmt,directoryRows,directorySummary};if(typeof module!=='undefined')module.exports=api;root.WinClean=api;
})(typeof window==='undefined'?globalThis:window);
