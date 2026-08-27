/* Прототип 2: обводка маршрута пальцем + живой расчёт времени.
   Модель повторяет первый прототип один в один (Minetti + бюджет мощности). */

// ---------- модель ----------
const MAXV = 6/3.6, MINV = 0.15;

function minettiCost(i){
  i = Math.max(-0.45, Math.min(0.45, i));
  const c = 280.5*i**5 - 58.7*i**4 - 76.8*i**3 + 51.9*i**2 + 19.6*i + 2.5;
  return Math.max(c, 0.4);
}
function speedOf(slope, body, load, powerPerKg, terrain=1, loadFactor=1.15){
  const cost = minettiCost(slope)*terrain;
  const eff  = body + load*loadFactor;
  const v    = (powerPerKg*body)/(cost*eff);
  return Math.max(MINV, Math.min(MAXV, v));
}
function timeHours(segs, body, load, powerPerKg){
  let t = 0;
  for (const [d, dh] of segs){ if (d > 0) t += d/speedOf(dh/d, body, load, powerPerKg); }
  return t/3600;
}
const naiveHours = m => m/1000/4;
const fmtH = h => { let m = Math.round(h*60); return `${Math.floor(m/60)}:${String(m%60).padStart(2,'0')}`; };

// ---------- геометрия ----------
const R = 6371008.8, rad = d => d*Math.PI/180;
function haversine(a, b){
  const dLat = rad(b[1]-a[1]), dLon = rad(b[0]-a[0]);
  const s = Math.sin(dLat/2)**2 + Math.cos(rad(a[1]))*Math.cos(rad(b[1]))*Math.sin(dLon/2)**2;
  return 2*R*Math.asin(Math.sqrt(s));
}
/* Упрощение в экранных пикселях: допуск сам подстраивается под зум,
   как и договаривались — на дальнем зуме грубее, на ближнем точнее. */
function simplifyPx(pts, tol){
  if (pts.length < 3) return pts;
  const d2 = (p, a, b) => {
    let x = a[0], y = a[1], dx = b[0]-x, dy = b[1]-y;
    if (dx || dy){
      const t = ((p[0]-x)*dx + (p[1]-y)*dy)/(dx*dx + dy*dy);
      if (t > 1){ x = b[0]; y = b[1]; } else if (t > 0){ x += dx*t; y += dy*t; }
    }
    return (p[0]-x)**2 + (p[1]-y)**2;
  };
  const keep = new Array(pts.length).fill(false);
  keep[0] = keep[pts.length-1] = true;
  (function rec(i, j){
    let max = 0, idx = -1;
    for (let k = i+1; k < j; k++){ const d = d2(pts[k], pts[i], pts[j]); if (d > max){ max = d; idx = k; } }
    if (max > tol*tol){ keep[idx] = true; rec(i, idx); rec(idx, j); }
  })(0, pts.length-1);
  return pts.filter((_, i) => keep[i]);
}
function resample(path, step){
  if (path.length < 2) return path.slice();
  const out = [path[0]];
  let acc = 0;
  for (let i = 1; i < path.length; i++){
    let a = path[i-1], b = path[i], d = haversine(a, b);
    while (acc + d >= step){
      const t = (step - acc)/d;
      a = [a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t];
      out.push(a); d = haversine(a, b); acc = 0;
    }
    acc += d;
  }
  out.push(path[path.length-1]);
  return out;
}
function gainLoss(ele, thr=2){
  let g = 0, l = 0, ref = ele[0];
  for (const e of ele.slice(1)){
    const d = e - ref;
    if (d > thr){ g += d; ref = e; } else if (d < -thr){ l -= d; ref = e; }
  }
  return [g, l];
}

// ---------- состояние ----------
const S = {
  path: [], history: [], pts: [], ele: [], segs: [],
  dist: 0, gain: 0, loss: 0,
  body: +(localStorage.getItem('body') || 75),
  load: +(localStorage.getItem('load') || 10),
  power: 3.6, draw: false, busy: false,
  base: 'topo', contours: false, speedColor: false, lastLen: 0
};

// ---------- карта ----------
const OTM = 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png';
const map = new maplibregl.Map({
  container: 'map',
  center: [7.6900, 45.9740], zoom: 13.2,
  style: {
    version: 8,
    sources: {
      topo:  { type:'raster', tiles:[OTM], tileSize:256, maxzoom:17,
               attribution:'© OpenTopoMap (CC-BY-SA), © OpenStreetMap' },
      plain: { type:'raster', tiles:['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
               tileSize:256, maxzoom:19, attribution:'© OpenStreetMap' },
      sat:   { type:'raster', tiles:['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
               tileSize:256, maxzoom:18, attribution:'Esri' }
    },
    layers: [
      { id:'l-plain', type:'raster', source:'plain', layout:{visibility:'none'} },
      { id:'l-sat',   type:'raster', source:'sat',   layout:{visibility:'none'} },
      { id:'l-topo',  type:'raster', source:'topo' },
      { id:'l-cont',  type:'raster', source:'topo', paint:{'raster-opacity':0.45},
        layout:{visibility:'none'} }
    ]
  }
});
map.addControl(new maplibregl.NavigationControl({showCompass:false}), 'bottom-left');

map.on('error', e => console.error('MAPERR', e && e.error && e.error.message));

let layersReady = false;
function addRouteLayers(){
  if (layersReady || !map.getStyle()) return;
  if (map.getSource('route')) { layersReady = true; return; }
  layersReady = true;
  map.addSource('route', { type:'geojson', data:{type:'FeatureCollection',features:[]} });
  map.addSource('segs',  { type:'geojson', data:{type:'FeatureCollection',features:[]} });
  map.addSource('cur',   { type:'geojson', data:{type:'FeatureCollection',features:[]} });
  map.addSource('ends',  { type:'geojson', data:{type:'FeatureCollection',features:[]} });

  map.addLayer({ id:'route-halo', type:'line', source:'route',
    paint:{'line-color':'#fff','line-width':7,'line-opacity':.85},
    layout:{'line-cap':'round','line-join':'round'} });
  map.addLayer({ id:'route-line', type:'line', source:'route',
    paint:{'line-color':'#2f6f4f','line-width':4},
    layout:{'line-cap':'round','line-join':'round'} });
  map.addLayer({ id:'route-spd', type:'line', source:'segs',
    layout:{visibility:'none','line-cap':'round'},
    paint:{'line-width':5,'line-color':
      ['interpolate',['linear'],['get','v'],
        0.3,'#a33a2a', 0.7,'#d9a05b', 1.1,'#c9c07a', 1.4,'#2f6f4f']} });
  map.addLayer({ id:'end-pt', type:'circle', source:'ends',
    paint:{'circle-radius':5.5,'circle-color':'#2f6f4f',
           'circle-stroke-color':'#fff','circle-stroke-width':2.5} });
  map.addLayer({ id:'cur-pt', type:'circle', source:'cur',
    paint:{'circle-radius':6,'circle-color':'#12161c','circle-stroke-color':'#fff','circle-stroke-width':2.5} });
  applyLayers();
}
map.on('load', addRouteLayers);
// подстраховка: 'load' ждёт первой отрисовки тайлов и при медленной сети может не прийти
map.on('styledata', () => { if (map.isStyleLoaded()) addRouteLayers(); });

// ---------- жесты рисования: один палец рисует, два двигают карту ----------
const el = map.getCanvasContainer();
let cur = null;

function beginStroke(x, y){ cur = [[x, y]]; }
function extendStroke(x, y){
  if (!cur) return;
  const p = cur[cur.length-1];
  if ((x-p[0])**2 + (y-p[1])**2 > 4) cur.push([x, y]);   // не копим дрожь пальца
  drawPreview();
}
const SNAP_PX = 45;   // насколько близко мазок должен подойти, чтобы приклеиться

/* Проекция точки на отрезок: доля вдоль него и расстояние. */
function projOnSeg(p, a, b){
  const dx = b[0]-a[0], dy = b[1]-a[1], L = dx*dx + dy*dy;
  let t = L ? ((p[0]-a[0])*dx + (p[1]-a[1])*dy)/L : 0;
  t = Math.max(0, Math.min(1, t));
  return {t, d: Math.hypot(p[0] - (a[0]+dx*t), p[1] - (a[1]+dy*t))};
}
/* Ближайшее место на ломаной. Мерить до вершин нельзя: после упрощения
   прямой участок — это две точки, и правка в его середине не находится. */
function nearestOnPolyline(p, px){
  let best = {i:0, t:0, d:Infinity};
  for (let i = 0; i < px.length - 1; i++){
    const r = projOnSeg(p, px[i], px[i+1]);
    if (r.d < best.d) best = {i, t:r.t, d:r.d};
  }
  return best;
}
const lerpLL = (a, b, t) => [a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t];

/* Куда девать новый мазок. Раньше он тупо дописывался в конец, из-за чего
   между несвязанными штрихами возникали прямые перемычки через пол-карты. */
function applyStroke(strokePx){
  const stroke = strokePx.map(([x,y]) => { const c = map.unproject([x,y]); return [c.lng, c.lat]; });
  if (S.path.length < 2){ S.path = stroke; return 'начало'; }

  const pathPx = S.path.map(c => { const p = map.project(c); return [p.x, p.y]; });
  const head = pathPx[0], tail = pathPx[pathPx.length-1];
  const s0 = strokePx[0], s1 = strokePx[strokePx.length-1];
  const dist = (a, b) => Math.hypot(a[0]-b[0], a[1]-b[1]);

  // 1. оба конца мазка легли на линию — это правка, заменяем участок между ними
  const a = nearestOnPolyline(s0, pathPx), b = nearestOnPolyline(s1, pathPx);
  if (a.d < SNAP_PX && b.d < SNAP_PX){
    const [p1, p2, seg] = (a.i + a.t) <= (b.i + b.t)
      ? [a, b, stroke] : [b, a, stroke.slice().reverse()];
    const cut1 = lerpLL(S.path[p1.i], S.path[p1.i+1], p1.t);
    const cut2 = lerpLL(S.path[p2.i], S.path[p2.i+1], p2.t);
    S.path = S.path.slice(0, p1.i+1).concat([cut1], seg, [cut2], S.path.slice(p2.i+1));
    return 'участок заменён';
  }

  // 2. иначе продлеваем от того конца маршрута, к которому мазок ближе
  const opts = [
    {d: dist(s0, tail), at:'tail', add: stroke},
    {d: dist(s1, tail), at:'tail', add: stroke.slice().reverse()},
    {d: dist(s0, head), at:'head', add: stroke.slice().reverse()},
    {d: dist(s1, head), at:'head', add: stroke}
  ].sort((x, y) => x.d - y.d)[0];

  if (opts.d > SNAP_PX) return null;              // далеко от всего — не приклеиваем
  S.path = opts.at === 'head' ? opts.add.concat(S.path) : S.path.concat(opts.add);
  return 'продлено';
}

function endStroke(){
  if (!cur || cur.length < 2){ cur = null; return; }
  const simp = simplifyPx(cur, 2.5);
  const before = S.path.slice();
  const what = applyStroke(simp);
  cur = null;
  if (!what){
    drawPreview();
    flash('Мазок далеко от маршрута — начните у его конца или поверх линии');
    return;
  }
  S.history.push(before);
  if (S.history.length > 40) S.history.shift();
  recompute();
}

let flashTimer = null;
function flash(msg){
  hint.textContent = msg;
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => {
    hint.textContent = S.draw ? 'Один палец рисует, два — двигают карту'
                              : 'Тяните слайдер — время пересчитается';
  }, 2600);
}
function drawPreview(){
  const feats = [];
  if (S.path.length > 1) feats.push({type:'Feature',geometry:{type:'LineString',coordinates:S.path}});
  if (cur && cur.length > 1){
    feats.push({ type:'Feature', geometry:{ type:'LineString',
      coordinates: cur.map(([x,y]) => { const c = map.unproject([x,y]); return [c.lng,c.lat]; }) }});
  }
  whenReady(() => {
    map.getSource('route').setData({type:'FeatureCollection',features:feats});
    // концы маршрута видно — сразу понятно, откуда его продолжать
    const ends = S.path.length > 1 ? [S.path[0], S.path[S.path.length-1]] : [];
    map.getSource('ends').setData({type:'FeatureCollection',
      features: ends.map(c => ({type:'Feature',geometry:{type:'Point',coordinates:c}}))});
  });
}

function localXY(e, t){
  const r = el.getBoundingClientRect();
  const s = t || e;
  return [s.clientX - r.left, s.clientY - r.top];
}
el.addEventListener('touchstart', e => {
  if (!S.draw) return;
  if (e.touches.length === 1){ e.stopPropagation(); e.preventDefault(); beginStroke(...localXY(e, e.touches[0])); }
  else { cur = null; drawPreview(); }          // два пальца — отдаём карте
}, {capture:true, passive:false});
el.addEventListener('touchmove', e => {
  if (!S.draw || !cur) return;
  if (e.touches.length > 1){ endStroke(); return; }
  e.stopPropagation(); e.preventDefault(); extendStroke(...localXY(e, e.touches[0]));
}, {capture:true, passive:false});
el.addEventListener('touchend', e => {
  if (!S.draw || !cur) return;
  e.stopPropagation(); endStroke();
}, {capture:true, passive:false});
// мышь — чтобы можно было пробовать с ноутбука
el.addEventListener('mousedown', e => {
  if (!S.draw) return; e.stopPropagation(); e.preventDefault(); beginStroke(...localXY(e));
}, {capture:true});
el.addEventListener('mousemove', e => {
  if (!S.draw || !cur) return; e.stopPropagation(); extendStroke(...localXY(e));
}, {capture:true});
window.addEventListener('mouseup', () => { if (S.draw && cur) endStroke(); }, {capture:true});

// ---------- высоты ----------
/* Локально их считает наш сервер по тем же тайлам, что и первый прототип.
   На статическом хостинге сервера нет, поэтому падаем на Open-Meteo:
   он единственный из бесплатных отдаёт высоты с заголовками CORS.
   Цифры чуть разойдутся — у него другой DEM. */
const ELEV = { local: null };

async function fetchElev(pts){
  if (ELEV.local !== false){
    try {
      const r = await fetch('/elev', {method:'POST',
        body: JSON.stringify(pts.map(([lng,lat]) => [lat,lng]))});
      if (r.ok){ ELEV.local = true; return await r.json(); }
    } catch(e){}
    ELEV.local = false;
  }
  const out = [];
  for (let i = 0; i < pts.length; i += 100){
    const c = pts.slice(i, i+100);
    const u = 'https://api.open-meteo.com/v1/elevation?latitude=' +
      c.map(p => p[1].toFixed(5)).join(',') + '&longitude=' + c.map(p => p[0].toFixed(5)).join(',');
    const j = await fetch(u).then(r => r.json());
    if (!j.elevation) throw new Error(j.reason || 'Open-Meteo не ответил');
    out.push(...j.elevation);
  }
  return out;
}

// ---------- пересчёт ----------
async function recompute(){
  const path = S.path;
  if (path.length < 2){ clearRoute(); return; }
  S.lastLen = path.reduce((sum, p, i, a) => i ? sum + haversine(a[i-1], p) : 0, 0);
  S.busy = true;
  // На статическом хостинге высоты берём из Open-Meteo, там реже точки:
  // у него лимит 100 координат на запрос, не хочется долбить его сотнями.
  const step = ELEV.local === false ? Math.max(25, S.lastLen/450) : 25;
  const pts = resample(path, step);
  let ele;
  try { ele = await fetchElev(pts); }
  catch(err){ S.busy = false; console.error('высоты не получены', err); return; }

  // сглаживание профиля: без него шум DEM раздувает набор
  const sm = ele.map((_, i, a) => {
    const lo = Math.max(0, i-2), hi = Math.min(a.length, i+3);
    return a.slice(lo, hi).reduce((s,v)=>s+v,0)/(hi-lo);
  });

  const segs = [];
  for (let i = 1; i < pts.length; i++) segs.push([haversine(pts[i-1], pts[i]), sm[i]-sm[i-1]]);

  Object.assign(S, {
    pts, ele: sm, segs,
    dist: segs.reduce((s,[d])=>s+d, 0),
    ...(([g,l]) => ({gain:g, loss:l}))(gainLoss(sm))
  });
  S.busy = false;
  render();
}

function clearRoute(){
  Object.assign(S, {path:[], history:[], pts:[], ele:[], segs:[], dist:0, gain:0, loss:0});
  map.getSource('route')?.setData({type:'FeatureCollection',features:[]});
  map.getSource('segs')?.setData({type:'FeatureCollection',features:[]});
  map.getSource('cur')?.setData({type:'FeatureCollection',features:[]});
  map.getSource('ends')?.setData({type:'FeatureCollection',features:[]});
  pill.classList.remove('on');
  bUndo.classList.remove('on'); bClear.classList.remove('on');
  hint.textContent = 'Нажмите карандаш и обведите маршрут пальцем';
  ['sDist','sGain','sLoss'].forEach(id => document.getElementById(id).textContent = '—');
  document.getElementById('prof').innerHTML = '';
  document.getElementById('sensVal').textContent = '—';
}

// ---------- отрисовка ----------
function loadBand(load, body){
  const p = load/body*100;
  if (p < 10)  return ['#2f6f4f', `${p.toFixed(0)}% массы тела — вес почти не мешает`];
  if (p < 20)  return ['#2f6f4f', `${p.toFixed(0)}% массы тела — нормальная многодневка`];
  if (p < 25)  return ['#b8860b', `${p.toFixed(0)}% массы тела — тяжело, риск растёт`];
  if (p < 30)  return ['#a33a2a', `${p.toFixed(0)}% массы тела — расход выше на треть, травмы вдвое чаще`];
  return ['#a33a2a', `${p.toFixed(0)}% массы тела — так ходить не надо`];
}

/* Цветная шкала нагрузки: пороги в процентах от массы тела,
   поэтому раскраска пересобирается под конкретного человека. */
function paintBand(){
  const max = +wSlider.max, b = S.body;
  const at = pct => Math.max(0, Math.min(100, b*pct/100/max*100)).toFixed(1) + '%';
  document.getElementById('band').style.background =
    `linear-gradient(90deg,#7fae8e 0 ${at(10)},#c9c07a ${at(10)} ${at(20)},`+
    `#d9a05b ${at(20)} ${at(25)},#c4705c ${at(25)} ${at(30)},#a33a2a ${at(30)} 100%)`;
}

function render(){
  const {segs, body, load, power} = S;
  const t = timeHours(segs, body, load, power);
  const n = naiveHours(S.dist);

  pill.classList.add('on');
  pTime.textContent = fmtH(t);
  pNaive.textContent = fmtH(n);
  pSub.textContent = `${(S.dist/1000).toFixed(1)} км · ↑${Math.round(S.gain)} м · ↓${Math.round(S.loss)} м`;
  bUndo.classList.add('on'); bClear.classList.add('on');
  hint.textContent = 'Тяните слайдер — время пересчитается';

  sDist.textContent = (S.dist/1000).toFixed(1) + ' км';
  sGain.textContent = Math.round(S.gain) + ' м';
  sLoss.textContent = Math.round(S.loss) + ' м';

  const t1 = timeHours(segs, body, load+1, power);
  document.getElementById('sensVal').textContent = `+${Math.round((t1-t)*60)} мин`;

  const [c, txt] = loadBand(load, body);
  bandTxt.textContent = txt; bandTxt.style.color = c;

  // трек, раскрашенный по скорости
  const feats = [];
  for (let i = 1; i < S.pts.length; i++){
    const [d, dh] = segs[i-1];
    feats.push({ type:'Feature', properties:{ v: d>0 ? speedOf(dh/d, body, load, power) : 1 },
      geometry:{ type:'LineString', coordinates:[S.pts[i-1], S.pts[i]] }});
  }
  whenReady(() => map.getSource('segs').setData({type:'FeatureCollection',features:feats}));
  drawProfile();
}

function drawProfile(){
  const svg = document.getElementById('prof');
  const e = S.ele; if (e.length < 2){ svg.innerHTML = ''; return; }
  const W = 340, H = 104, pad = 6;
  const lo = Math.min(...e), hi = Math.max(...e), span = Math.max(hi-lo, 1);
  const X = i => i/(e.length-1)*W;
  const Y = v => H - pad - (v-lo)/span*(H-pad*2);
  const line = e.map((v,i) => `${i?'L':'M'}${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join('');
  svg.innerHTML =
    `<path d="${line}L${W},${H}L0,${H}Z" fill="#2f6f4f" opacity=".13"/>` +
    `<path d="${line}" fill="none" stroke="#2f6f4f" stroke-width="1.8"/>` +
    `<circle id="pdot" r="4" fill="#12161c" stroke="#fff" stroke-width="2" style="display:none"/>`;
  svg.dataset.lo = lo; svg.dataset.hi = hi;
}

// касание графика подсвечивает точку на карте — и наоборот доверие к цифрам
const profEl = document.getElementById('prof');
function profTouch(clientX){
  if (!S.ele.length) return;
  const r = profEl.getBoundingClientRect();
  const f = Math.max(0, Math.min(1, (clientX - r.left)/r.width));
  const i = Math.round(f*(S.ele.length-1));
  const dot = document.getElementById('pdot');
  if (dot){ dot.setAttribute('cx', (i/(S.ele.length-1)*340).toFixed(1));
    const lo = +profEl.dataset.lo, hi = +profEl.dataset.hi;
    dot.setAttribute('cy', (104-6-(S.ele[i]-lo)/Math.max(hi-lo,1)*(104-12)).toFixed(1));
    dot.style.display = ''; }
  map.getSource('cur')?.setData({type:'Feature',geometry:{type:'Point',coordinates:S.pts[i]}});
  const km = (S.pts.slice(0,i+1).reduce((s,p,j,a)=> j? s+haversine(a[j-1],p):0, 0)/1000).toFixed(1);
  document.getElementById('profTxt').textContent = `${km} км · ${Math.round(S.ele[i])} м`;
}
profEl.addEventListener('touchmove', e => { e.preventDefault(); profTouch(e.touches[0].clientX); }, {passive:false});
profEl.addEventListener('touchstart', e => { e.preventDefault(); profTouch(e.touches[0].clientX); }, {passive:false});
profEl.addEventListener('mousemove', e => profTouch(e.clientX));

// ---------- органы управления ----------
const pill = document.getElementById('pill');
const bUndo = document.getElementById('bUndo'), bClear = document.getElementById('bClear');
const sheet = document.getElementById('sheet'), hint = document.getElementById('hint');
const pTime = document.getElementById('pTime'), pNaive = document.getElementById('pNaive');
const pSub = document.getElementById('pSub'), bandTxt = document.getElementById('bandTxt');
const sDist = document.getElementById('sDist'), sGain = document.getElementById('sGain');
const sLoss = document.getElementById('sLoss');

document.getElementById('bDraw').onclick = function(){
  S.draw = !S.draw;
  this.classList.toggle('on', S.draw);
  map.dragPan[S.draw ? 'disable' : 'enable']();
  hint.textContent = S.draw
    ? 'Один палец рисует, два — двигают карту'
    : (S.segs.length ? 'Тяните слайдер — время пересчитается' : 'Нажмите карандаш и обведите маршрут пальцем');
};
bUndo.onclick = () => {
  if (!S.history.length) return clearRoute();
  S.path = S.history.pop();
  drawPreview();
  S.path.length > 1 ? recompute() : clearRoute();
};
bClear.onclick = () => clearRoute();

/* Слои переключаем только по готовому стилю: иначе setLayoutProperty бросает
   'Style is not done loading' и карта остаётся пустой. */
/* isStyleLoaded() у MapLibre бывает false на уже готовом стиле,
   поэтому просто пробуем и повторяем по следующему событию. */
function whenReady(fn){
  try { fn(); } catch(e){ map.once('idle', () => whenReady(fn)); }
}
function applyLayers(){
  whenReady(() => {
    const vis = on => on ? 'visible' : 'none';
    map.setLayoutProperty('l-topo',  'visibility', vis(S.base === 'topo'));
    map.setLayoutProperty('l-plain', 'visibility', vis(S.base === 'plain'));
    map.setLayoutProperty('l-sat',   'visibility', vis(S.base === 'sat'));
    map.setLayoutProperty('l-cont',  'visibility', vis(S.contours));
    if (map.getLayer('route-spd')){
      map.setLayoutProperty('route-spd',  'visibility', vis(S.speedColor));
      map.setLayoutProperty('route-line', 'visibility', vis(!S.speedColor));
      map.setLayoutProperty('route-halo', 'visibility', vis(!S.speedColor));
    }
  });
}
document.getElementById('bLayers').onclick = () => document.getElementById('layers').classList.toggle('on');
document.querySelectorAll('#layers .row').forEach(row => row.onclick = () => {
  if (row.dataset.base){
    S.base = row.dataset.base;
    document.querySelectorAll('#layers .row[data-base]').forEach(r => r.classList.toggle('sel', r === row));
  } else if (row.dataset.ov === 'contours'){
    S.contours = !S.contours; row.classList.toggle('sel', S.contours);
  } else {
    S.speedColor = !S.speedColor; row.classList.toggle('sel', S.speedColor);
  }
  applyLayers();
});

const wSlider = document.getElementById('wSlider');
wSlider.value = S.load;
document.getElementById('wVal').textContent = S.load + ' кг';
wSlider.oninput = () => {
  S.load = +wSlider.value;
  localStorage.setItem('load', S.load);
  document.getElementById('wVal').textContent = S.load + ' кг';
  const [c, txt] = loadBand(S.load, S.body);
  bandTxt.textContent = txt; bandTxt.style.color = c;
  if (S.segs.length) render();
};
document.querySelectorAll('#pace button').forEach(b => b.onclick = () => {
  document.querySelectorAll('#pace button').forEach(x => x.classList.remove('sel'));
  b.classList.add('sel'); S.power = +b.dataset.p; if (S.segs.length) render();
});
document.getElementById('grip').onclick = () => sheet.classList.toggle('open');
pill.onclick = () => sheet.classList.toggle('open');

// ---------- онбординг ----------
let sample = null, obStep = 0;
const ob = document.getElementById('ob'), obBody = document.getElementById('obBody');

const OB = [
  () => {
    const n = naiveHours(sample.dist_m), t = timeHours(sample.segments, 75, 0, 3.6);
    return `<h2>Обычные приложения делят расстояние на скорость</h2>
      <p>Маршрут к хижине Хёрнли под Маттерхорном: 2,8 км, набор ${sample.gain_m} м.
         Справочное время — 2 часа.</p>
      <div class="cmp">
        <div class="bad"><div class="k">расстояние ÷ скорость</div><div class="v">${fmtH(n)}</div></div>
        <div class="good"><div class="k">с учётом рельефа</div><div class="v">${fmtH(t)}</div></div>
      </div>
      <div class="note">Разница почти втрое. Это и есть весь смысл приложения.</div>`;
  },
  () => `<h2>Рюкзак меняет время сильнее, чем кажется</h2>
      <p>Тот же маршрут. Подвигайте ползунок.</p>
      <div class="big" id="obT">—</div>
      <div class="note" id="obN">—</div>
      <input type="range" id="obW" min="0" max="30" step="1" value="0" style="margin-top:18px">`,
  () => `<h2>Сколько вы весите?</h2>
      <p>Пороги нагрузки считаются в процентах от массы тела — двадцать килограммов
         для разных людей это очень разная тяжесть. Можно пропустить.</p>
      <input type="number" id="obB" value="${S.body}" min="35" max="160">`
];

function obRender(){
  obBody.innerHTML = OB[obStep]();
  document.querySelectorAll('#dots i').forEach((d,i) => d.classList.toggle('on', i === obStep));
  document.getElementById('obNext').textContent = obStep === OB.length-1 ? 'Начать' : 'Дальше';
  if (obStep === 1){
    const w = document.getElementById('obW');
    const upd = () => {
      const t = timeHours(sample.segments, 75, +w.value, 3.6);
      const t0 = timeHours(sample.segments, 75, 0, 3.6);
      document.getElementById('obT').textContent = fmtH(t);
      document.getElementById('obN').textContent =
        +w.value === 0 ? 'налегке' : `рюкзак ${w.value} кг — это +${Math.round((t-t0)*60)} мин`;
    };
    w.oninput = upd; upd();
  }
}
document.getElementById('obNext').onclick = () => {
  if (obStep === 2){ const v = +document.getElementById('obB').value;
    if (v >= 35 && v <= 160){ S.body = v; localStorage.setItem('body', v); paintBand(); } }
  if (obStep < OB.length-1){ obStep++; obRender(); } else obClose();
};
document.getElementById('obSkip').onclick = () => obClose();
function obClose(){ ob.classList.remove('on'); localStorage.setItem('onboarded','1'); }

paintBand();
fetch('sample.json').then(r => r.json()).then(j => {
  sample = j;
  if (!localStorage.getItem('onboarded') || location.hash === '#ob'){ ob.classList.add('on'); obRender(); }
});
