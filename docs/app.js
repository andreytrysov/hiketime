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
function timeHours(segs, body, load, powerPerKg, terrain = 1){
  let t = 0;
  for (const [d, dh] of segs){ if (d > 0) t += d/speedOf(dh/d, body, load, powerPerKg, terrain); }
  return t/3600;
}
const naiveHours = m => m/1000/4;
/* Привалы: походный ритм ~50/10 — десять минут отдыха на каждый час хода,
   плюс обед 30 минут, если ходового времени больше четырёх часов. */
function withBreaks(movH){
  const movMin = movH*60;
  const n10 = Math.max(0, Math.ceil(movMin/55) - 1);
  const lunch = movMin > 240 ? 30 : 0;
  return {total: movH + (n10*10 + lunch)/60, n10, lunch};
}
const fmtH = h => { let m = Math.round(h*60); return `${Math.floor(m/60)}:${String(m%60).padStart(2,'0')}`; };

// ---------- геометрия ----------
const R = 6371008.8, rad = d => d*Math.PI/180;
function haversine(a, b){
  const dLat = rad(b[1]-a[1]), dLon = rad(b[0]-a[0]);
  const s = Math.sin(dLat/2)**2 + Math.cos(rad(a[1]))*Math.cos(rad(b[1]))*Math.sin(dLon/2)**2;
  return 2*R*Math.asin(Math.sqrt(s));
}
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
  dist: 0, gain: 0, loss: 0, sens: 0,
  body: +(localStorage.getItem('body') || 75),
  load: +(localStorage.getItem('load') || 10),
  power: 3.6, terrain: +(localStorage.getItem('terrain') || 1),
  draw: false, busy: false,
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
map.addControl(new maplibregl.GeolocateControl({
  positionOptions: {enableHighAccuracy: true},
  trackUserLocation: true,
  showUserHeading: true
}), 'bottom-left');
map.on('error', e => console.error('MAPERR', e && e.error && e.error.message));

let layersReady = false;
function addRouteLayers(){
  if (layersReady || !map.getStyle()) return;
  if (map.getSource('route')) { layersReady = true; return; }
  layersReady = true;
  map.addSource('route', { type:'geojson', data:{type:'FeatureCollection',features:[]} });
  // отдельный источник для скорости: lineMetrics нужен градиенту вдоль линии
  map.addSource('spd',   { type:'geojson', lineMetrics:true,
    data:{type:'FeatureCollection',features:[]} });
  map.addSource('cur',   { type:'geojson', data:{type:'FeatureCollection',features:[]} });
  map.addSource('ends',  { type:'geojson', data:{type:'FeatureCollection',features:[]} });

  map.addLayer({ id:'route-halo', type:'line', source:'route',
    paint:{'line-color':'#fff','line-width':7,'line-opacity':.85},
    layout:{'line-cap':'round','line-join':'round'} });
  map.addLayer({ id:'route-line', type:'line', source:'route',
    paint:{'line-color':'#2f6f4f','line-width':4},
    layout:{'line-cap':'round','line-join':'round'} });
  map.addLayer({ id:'route-spd', type:'line', source:'spd',
    layout:{visibility:'none','line-cap':'round','line-join':'round'},
    paint:{'line-width':5} });
  map.addLayer({ id:'end-pt', type:'circle', source:'ends',
    paint:{'circle-radius':5.5,'circle-color':'#2f6f4f',
           'circle-stroke-color':'#fff','circle-stroke-width':2.5} });
  map.addLayer({ id:'cur-pt', type:'circle', source:'cur',
    paint:{'circle-radius':6,'circle-color':'#12161c','circle-stroke-color':'#fff','circle-stroke-width':2.5} });
  applyLayers();
}
map.on('load', addRouteLayers);
map.on('styledata', () => { if (map.isStyleLoaded()) addRouteLayers(); });

/* isStyleLoaded() бывает false на уже готовом стиле, а событие idle может
   проскочить до подписки — поэтому просто пробуем и повторяем по таймеру. */
function whenReady(fn, tries = 25){
  try { fn(); } catch(e){
    if (tries > 0) setTimeout(() => whenReady(fn, tries - 1), 400);
    else console.error('whenReady сдался:', e.message);
  }
}

/* Правила слоёв: подложка — одна из трёх; горизонтали поверх топо не имеют
   смысла (это те же тайлы), поэтому там пункт гаснет; цвет по скорости —
   режим отображения маршрута, он заменяет зелёную линию. */
function applyLayers(){
  const contoursOn = S.contours && S.base !== 'topo';
  whenReady(() => {
    const vis = on => on ? 'visible' : 'none';
    map.setLayoutProperty('l-topo',  'visibility', vis(S.base === 'topo'));
    map.setLayoutProperty('l-plain', 'visibility', vis(S.base === 'plain'));
    map.setLayoutProperty('l-sat',   'visibility', vis(S.base === 'sat'));
    map.setLayoutProperty('l-cont',  'visibility', vis(contoursOn));
    if (map.getLayer('route-spd')){
      map.setLayoutProperty('route-spd',  'visibility', vis(S.speedColor));
      map.setLayoutProperty('route-line', 'visibility', vis(!S.speedColor));
    }
  });
  document.querySelectorAll('#layers .row[data-base]').forEach(r =>
    r.classList.toggle('sel', r.dataset.base === S.base));
  const cont = document.querySelector('#layers .row[data-ov="contours"]');
  cont.classList.toggle('sel', contoursOn);
  cont.classList.toggle('dis', S.base === 'topo');
  document.querySelector('#layers .row[data-ov="speed"]')
    .classList.toggle('sel', S.speedColor);
}

// ---------- жесты рисования: один палец рисует, два двигают карту ----------
const el = map.getCanvasContainer();
let cur = null;

function beginStroke(x, y){ cur = [[x, y]]; }
function extendStroke(x, y){
  if (!cur) return;
  const p = cur[cur.length-1];
  if ((x-p[0])**2 + (y-p[1])**2 > 4) cur.push([x, y]);
  drawPreview();
}

const SNAP_PX = 45;

function projOnSeg(p, a, b){
  const dx = b[0]-a[0], dy = b[1]-a[1], L = dx*dx + dy*dy;
  let t = L ? ((p[0]-a[0])*dx + (p[1]-a[1])*dy)/L : 0;
  t = Math.max(0, Math.min(1, t));
  return {t, d: Math.hypot(p[0] - (a[0]+dx*t), p[1] - (a[1]+dy*t))};
}
/* Мерить близость надо до отрезков, не до вершин: после упрощения прямой
   участок — это две точки на пол-экрана. */
function nearestOnPolyline(p, px){
  let best = {i:0, t:0, d:Infinity};
  for (let i = 0; i < px.length - 1; i++){
    const r = projOnSeg(p, px[i], px[i+1]);
    if (r.d < best.d) best = {i, t:r.t, d:r.d};
  }
  return best;
}
const lerpLL = (a, b, t) => [a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t];

/* Куда девать новый мазок: продление с ближайшего конца, правка
   перечёркиванием, отклонение далёкого. */
function applyStroke(strokePx){
  const stroke = strokePx.map(([x,y]) => { const c = map.unproject([x,y]); return [c.lng, c.lat]; });
  if (S.path.length < 2){ S.path = stroke; return 'начало'; }

  const pathPx = S.path.map(c => { const p = map.project(c); return [p.x, p.y]; });
  const head = pathPx[0], tail = pathPx[pathPx.length-1];
  const s0 = strokePx[0], s1 = strokePx[strokePx.length-1];
  const dist = (a, b) => Math.hypot(a[0]-b[0], a[1]-b[1]);

  const a = nearestOnPolyline(s0, pathPx), b = nearestOnPolyline(s1, pathPx);
  if (a.d < SNAP_PX && b.d < SNAP_PX){
    const [p1, p2, seg] = (a.i + a.t) <= (b.i + b.t)
      ? [a, b, stroke] : [b, a, stroke.slice().reverse()];
    const cut1 = lerpLL(S.path[p1.i], S.path[p1.i+1], p1.t);
    const cut2 = lerpLL(S.path[p2.i], S.path[p2.i+1], p2.t);
    S.path = S.path.slice(0, p1.i+1).concat([cut1], seg, [cut2], S.path.slice(p2.i+1));
    return 'участок заменён';
  }

  const opts = [
    {d: dist(s0, tail), at:'tail', add: stroke},
    {d: dist(s1, tail), at:'tail', add: stroke.slice().reverse()},
    {d: dist(s0, head), at:'head', add: stroke.slice().reverse()},
    {d: dist(s1, head), at:'head', add: stroke}
  ].sort((x, y) => x.d - y.d)[0];

  if (opts.d > SNAP_PX) return null;
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
    toast('Линия далеко от маршрута — начните у его конца или проведите поверх него');
    return;
  }
  S.history.push(before);
  if (S.history.length > 40) S.history.shift();
  recompute();
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
  else { cur = null; drawPreview(); }
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
el.addEventListener('mousedown', e => {
  if (!S.draw) return; e.stopPropagation(); e.preventDefault(); beginStroke(...localXY(e));
}, {capture:true});
el.addEventListener('mousemove', e => {
  if (!S.draw || !cur) return; e.stopPropagation(); extendStroke(...localXY(e));
}, {capture:true});
window.addEventListener('mouseup', () => { if (S.draw && cur) endStroke(); }, {capture:true});

// ---------- высоты ----------
/* Локально — наш сервер по тайлам terrarium. На статическом хостинге его нет,
   падаем на Open-Meteo: единственный бесплатный источник с CORS. */
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
  const step = ELEV.local === false ? Math.max(25, S.lastLen/450) : 25;
  const pts = resample(path, step);
  let ele;
  try { ele = await fetchElev(pts); }
  catch(err){
    S.busy = false;
    console.error('высоты не получены', err);
    // молчать нельзя: иначе цифры и цвет тихо отстают от нарисованного
    toast('Не удалось получить высоты — цифры не обновились. Попробуйте ещё раз.');
    return;
  }

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
  // после первой нарисованной линии настройки веса всплывают сами
  if (SHEET.pos === 'hidden') sheetTo('half');
}

function clearRoute(){
  Object.assign(S, {path:[], history:[], pts:[], ele:[], segs:[], dist:0, gain:0, loss:0});
  whenReady(() => {
    ['route','spd','cur','ends'].forEach(id =>
      map.getSource(id)?.setData({type:'FeatureCollection',features:[]}));
  });
  pill.classList.remove('on');
  bUndo.classList.remove('on'); bClear.classList.remove('on');
  ['sGain','sLoss','sPaceAvg'].forEach(id => document.getElementById(id).textContent = '—');
  ['restSummary','restLine'].forEach(id => document.getElementById(id).textContent = '');
  document.getElementById('prof').innerHTML = '';
  sheetTo('hidden');
  updateEmptyHint();
}

// ---------- шкала нагрузки ----------
function loadBand(load, body){
  const p = load/body*100;
  if (p < 10)  return ['#2f6f4f', `${p.toFixed(0)}% массы тела — вес почти не мешает`];
  if (p < 20)  return ['#2f6f4f', `${p.toFixed(0)}% массы тела — нормальная многодневка`];
  if (p < 25)  return ['#b8860b', `${p.toFixed(0)}% массы тела — тяжело, риск растёт`];
  if (p < 30)  return ['#a33a2a', `${p.toFixed(0)}% массы тела — расход выше на треть, травмы вдвое чаще`];
  return ['#a33a2a', `${p.toFixed(0)}% массы тела — так ходить не надо`];
}

/* Слайдер красится сам: заполненная часть — цветом зоны. Отдельной
   полосы-радуги больше нет, она читалась как второй слайдер. */
function paintSlider(elm, pct, color){
  elm.style.setProperty('--fill',
    `linear-gradient(90deg, ${color} 0 ${pct}%, #e3e6ea ${pct}% 100%)`);
}
function paintTicks(){
  const wrap = document.getElementById('ticks');
  wrap.innerHTML = '';
  [10, 20, 25, 30].forEach(p => {
    const kg = S.body*p/100;
    if (kg > +wSlider.max) return;
    const i = document.createElement('i');
    i.style.left = (kg / +wSlider.max * 100) + '%';
    wrap.appendChild(i);
  });
}
function updateWeightUI(){
  document.getElementById('wVal').textContent = S.load + ' кг';
  const [c, txt] = loadBand(S.load, S.body);
  paintSlider(wSlider, S.load / +wSlider.max * 100, c);
  const sens = S.segs.length ? ` · +${S.sens} мин/кг` : '';
  statusLine.textContent = txt + sens;
  statusLine.style.color = c;
}

// ---------- отрисовка ----------
const zoneColor = v => v < 0.5 ? '#a33a2a' : v < 0.9 ? '#d9a05b' : v < 1.25 ? '#c9c07a' : '#2f6f4f';

/* Скорость — одна непрерывная линия с градиентом, а не пачка кусочков по
   25 м: кусочки на отдалении разваливались в штриховку. */
function speedGradient(){
  if (S.pts.length < 2 || !S.dist) return;
  const stops = [];
  const every = Math.max(1, Math.floor(S.segs.length/60));
  let cum = 0, last = -1;
  for (let i = 0; i < S.segs.length; i++){
    const [d, dh] = S.segs[i];
    if (i % every === 0 || i === S.segs.length-1){
      const p = Math.min(1, (cum + d/2)/S.dist);
      if (p > last + 1e-4){
        stops.push(p, zoneColor(d > 0 ? speedOf(dh/d, S.body, S.load, S.power, S.terrain) : 1));
        last = p;
      }
    }
    cum += d;
  }
  if (stops.length < 4) return;
  if (stops[0] !== 0){ stops.unshift(0, stops[1]); }
  whenReady(() => {
    map.setPaintProperty('route-spd', 'line-gradient',
      ['interpolate', ['linear'], ['line-progress'], ...stops]);
    map.getSource('spd').setData({type:'Feature',
      geometry:{type:'LineString', coordinates:S.pts}});
  });
}

function render(){
  const {segs, body, load, power} = S;
  const t = timeHours(segs, body, load, power, S.terrain);
  const n = naiveHours(S.dist);
  const br = withBreaks(t);

  pill.classList.add('on');
  pTime.textContent = fmtH(br.total);
  pSub.textContent = `${(S.dist/1000).toFixed(1)} км · ↑${Math.round(S.gain)} м · ↓${Math.round(S.loss)} м`;
  bUndo.classList.add('on'); bClear.classList.add('on');

  sGain.textContent = Math.round(S.gain) + ' м';
  sLoss.textContent = Math.round(S.loss) + ' м';
  sPaceAvg.textContent = t > 0 ? (S.dist/1000/t).toFixed(1) + ' км/ч' : '—';
  document.getElementById('restSummary').textContent =
    `в движении ${fmtH(t)}` +
    (br.n10 ? ` · привалы ${br.n10} × 10 мин` : ' · без привалов') +
    (br.lunch ? ` · обед ${br.lunch} мин` : '');
  document.getElementById('restLine').textContent =
    `без учёта рельефа и веса вышло бы ${fmtH(n)}`;

  const t1 = timeHours(segs, body, load+1, power, S.terrain);
  S.sens = Math.round((t1-t)*60);
  updateWeightUI();
  speedGradient();
  drawProfile();
  updateEmptyHint();
}

function drawProfile(){
  const svg = document.getElementById('prof');
  const e = S.ele; if (e.length < 2){ svg.innerHTML = ''; return; }
  const W = 340, H = 104, pt = 6, pb = 18;
  const lo = Math.min(...e), hi = Math.max(...e), span = Math.max(hi-lo, 1);
  const X = i => i/(e.length-1)*W;
  const Y = v => H - pb - (v-lo)/span*(H-pb-pt);
  const line = e.map((v,i) => `${i?'L':'M'}${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join('');

  // километровые риски по низу — иначе у графика нет масштаба
  const totalKm = S.dist/1000;
  const stepKm = totalKm <= 6 ? 1 : totalKm <= 14 ? 2 : 5;
  let ticks = '';
  for (let k = stepKm; k < totalKm; k += stepKm){
    const x = (k/totalKm*W).toFixed(1);
    ticks += `<line x1="${x}" y1="${H-pb+2}" x2="${x}" y2="${H-pb+7}" stroke="#b6bcc4" stroke-width="1"/>` +
             `<text x="${x}" y="${H-2}" font-size="8.5" fill="#8b939e" text-anchor="middle">${k}</text>`;
  }
  svg.innerHTML =
    `<path d="${line}L${W},${H-pb}L0,${H-pb}Z" fill="#2f6f4f" opacity=".13"/>` +
    `<path d="${line}" fill="none" stroke="#2f6f4f" stroke-width="1.8"/>` + ticks +
    `<circle id="pdot" r="4" fill="#12161c" stroke="#fff" stroke-width="2" style="display:none"/>`;
  svg.dataset.lo = lo; svg.dataset.hi = hi;
}

const profEl = document.getElementById('prof');
function profTouch(clientX){
  if (!S.ele.length) return;
  const r = profEl.getBoundingClientRect();
  const f = Math.max(0, Math.min(1, (clientX - r.left)/r.width));
  const i = Math.round(f*(S.ele.length-1));
  const dot = document.getElementById('pdot');
  if (dot){
    const lo = +profEl.dataset.lo, hi = +profEl.dataset.hi;
    const span = Math.max(hi-lo, 1);
    dot.setAttribute('cx', (i/(S.ele.length-1)*340).toFixed(1));
    dot.setAttribute('cy', (104-18-(S.ele[i]-lo)/span*(104-18-6)).toFixed(1));
    dot.style.display = '';
  }
  whenReady(() => map.getSource('cur').setData({type:'Feature',
    geometry:{type:'Point',coordinates:S.pts[i]}}));
  const km = (i/(S.ele.length-1)*S.dist/1000).toFixed(1);
  document.getElementById('profTxt').textContent = `${km} км · ${Math.round(S.ele[i])} м`;
}
profEl.addEventListener('touchmove', e => { e.preventDefault(); profTouch(e.touches[0].clientX); }, {passive:false});
profEl.addEventListener('touchstart', e => { e.preventDefault(); profTouch(e.touches[0].clientX); }, {passive:false});
profEl.addEventListener('mousemove', e => profTouch(e.clientX));

// ---------- элементы ----------
const pill = document.getElementById('pill');
const pTime = document.getElementById('pTime');
const pSub = document.getElementById('pSub');
const bUndo = document.getElementById('bUndo'), bClear = document.getElementById('bClear');
const bDraw = document.getElementById('bDraw');
const sheet = document.getElementById('sheet');
const statusLine = document.getElementById('statusLine');
const sGain = document.getElementById('sGain'), sLoss = document.getElementById('sLoss');
const sPaceAvg = document.getElementById('sPaceAvg');
const wSlider = document.getElementById('wSlider');
const layersEl = document.getElementById('layers');
const toastEl = document.getElementById('toast');
const emptyHint = document.getElementById('emptyHint');

// ---------- тосты и пустое состояние ----------
let toastTimer = null;
function toast(msg, ms = 2800){
  toastEl.textContent = msg;
  toastEl.classList.add('on');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.classList.remove('on'), ms);
}
function updateEmptyHint(){
  emptyHint.classList.toggle('on', S.path.length < 2 && !S.draw);
}

// ---------- шторка: hidden / half / full ----------
const SHEET = { pos: 'hidden' };
function sheetPositions(){
  const h = sheet.offsetHeight;
  const inp = document.getElementById('inputs');
  const halfVisible = inp.offsetTop + inp.offsetHeight + 6;
  return { hidden: h + 30, half: Math.max(h - halfVisible, 0), full: 0, h };
}
function sheetTo(pos){
  SHEET.pos = pos;
  const p = sheetPositions();
  sheet.style.transform = `translateY(${p[pos]}px)`;
  if (pos !== 'hidden'){ closeLayers(); closeRoutes(); }
  // кнопки рисования уезжают выше шторки, а в полной позиции прячутся
  const visible = pos === 'hidden' ? 0 : p.h - p[pos];
  [bDraw, bUndo, bClear].forEach(b => b.classList.toggle('tucked', pos === 'full'));
  const base = visible ? visible + 14 : 96;
  bDraw.style.bottom  = `calc(env(safe-area-inset-bottom,0px) + ${base}px)`;
  bUndo.style.bottom  = `calc(env(safe-area-inset-bottom,0px) + ${base + 68}px)`;
  bClear.style.bottom = `calc(env(safe-area-inset-bottom,0px) + ${base + 120}px)`;
}
window.addEventListener('resize', () => sheetTo(SHEET.pos));

// перетаскивание за ручку + тап по ней переключает половину/полную
const headEl = document.getElementById('sheetHead');
let dragY = null, dragStart = 0;
headEl.addEventListener('pointerdown', e => {
  dragY = e.clientY;
  dragStart = sheetPositions()[SHEET.pos];
  sheet.classList.add('drag');
  headEl.setPointerCapture(e.pointerId);
});
headEl.addEventListener('pointermove', e => {
  if (dragY === null) return;
  const p = sheetPositions();
  let t = dragStart + (e.clientY - dragY);
  t = Math.max(p.full, Math.min(p.hidden, t));
  sheet.style.transform = `translateY(${t}px)`;
});
headEl.addEventListener('pointerup', e => {
  if (dragY === null) return;
  sheet.classList.remove('drag');
  const moved = e.clientY - dragY;
  dragY = null;
  if (Math.abs(moved) < 6){ sheetTo(SHEET.pos === 'full' ? 'half' : 'full'); return; }
  const p = sheetPositions();
  const t = dragStart + moved;
  const cands = [['full', p.full], ['half', p.half]];
  if (t > p.half + 70) cands.push(['hidden', p.hidden]);
  cands.sort((a, b) => Math.abs(a[1]-t) - Math.abs(b[1]-t));
  sheetTo(cands[0][0]);
});

pill.onclick = () => sheetTo(SHEET.pos === 'hidden' ? 'half' : 'hidden');

// ---------- слои ----------
function closeLayers(){
  layersEl.classList.remove('on');
  updatePillVis();
}
document.getElementById('bLayers').onclick = () => {
  if (layersEl.classList.contains('on')) return closeLayers();
  closeRoutes();
  layersEl.classList.add('on');
  updatePillVis();   // панель и плашка не должны перекрываться
};
document.querySelectorAll('#layers .row').forEach(row => row.onclick = () => {
  if (row.dataset.base){
    S.base = row.dataset.base;
  } else if (row.dataset.ov === 'contours'){
    if (S.base === 'topo'){ toast('На топокарте линии высот уже есть'); return; }
    S.contours = !S.contours;
  } else {
    S.speedColor = !S.speedColor;
    if (S.speedColor && S.segs.length) speedGradient();
  }
  applyLayers();
});

// ---------- рисование ----------
bDraw.onclick = function(){
  S.draw = !S.draw;
  this.classList.toggle('on', S.draw);
  map.dragPan[S.draw ? 'disable' : 'enable']();
  if (S.draw){
    sheetTo('hidden');
    toast('Один палец рисует, два — двигают карту');
  } else if (S.path.length > 1){
    sheetTo('half');
  }
  updateEmptyHint();
};
bUndo.onclick = () => {
  if (!S.history.length) return clearRoute();
  S.path = S.history.pop();
  drawPreview();
  S.path.length > 1 ? recompute() : clearRoute();
};
bClear.onclick = () => clearRoute();

// ---------- вес и темп ----------
wSlider.value = S.load;
wSlider.oninput = () => {
  S.load = +wSlider.value;
  localStorage.setItem('load', S.load);
  if (S.segs.length) render(); else updateWeightUI();
};
const surfSel = document.getElementById('surfSel');
const paceSel = document.getElementById('paceSel');
surfSel.value = String(S.terrain);
surfSel.onchange = () => {
  S.terrain = +surfSel.value;
  localStorage.setItem('terrain', S.terrain);
  if (S.segs.length) render();
};
paceSel.onchange = () => {
  S.power = +paceSel.value;
  if (S.segs.length) render();
};

// ---------- сохранённые маршруты (локально, на этом устройстве) ----------
const routesEl = document.getElementById('routes');

function loadRoutes(){
  try { return JSON.parse(localStorage.getItem('routes') || '[]'); }
  catch(e){ return []; }
}
function persistRoutes(r){ localStorage.setItem('routes', JSON.stringify(r)); }

function saveCurrent(){
  if (S.path.length < 2) return;
  const r = loadRoutes();
  r.unshift({
    id: Date.now(),
    name: `Маршрут ${(S.dist/1000).toFixed(1)} км`,
    ts: Date.now(),
    path: S.path, load: S.load, terrain: S.terrain, power: S.power,
    dist: S.dist, time: pTime.textContent
  });
  if (r.length > 30) r.pop();          // прототип, не база данных
  persistRoutes(r);
  renderRoutes();
  toast('Маршрут сохранён на этом устройстве');
}

function openRoute(o){
  S.path = o.path.slice(); S.history = [];
  S.load = o.load; wSlider.value = o.load; localStorage.setItem('load', o.load);
  S.terrain = o.terrain || 1; surfSel.value = String(S.terrain);
  S.power = o.power || 3.6; paceSel.value = String(S.power);
  drawPreview(); recompute();
  const lons = o.path.map(p => p[0]), lats = o.path.map(p => p[1]);
  map.fitBounds([[Math.min(...lons), Math.min(...lats)],
                 [Math.max(...lons), Math.max(...lats)]], {padding: 70});
  closeRoutes();
}

function renderRoutes(){
  const list = loadRoutes();
  let html = S.path.length > 1
    ? '<div class="row saveRow" id="rSave">Сохранить текущий маршрут</div><div class="sep"></div>'
    : '';
  html += '<div class="cap">Мои маршруты</div>';
  html += list.length ? list.map(o =>
      `<div class="row" data-id="${o.id}"><span><span>${o.name}</span><br>` +
      `<span class="meta">${(o.dist/1000).toFixed(1)} км · ${o.time} · ` +
      `${new Date(o.ts).toLocaleDateString('ru-RU',{day:'numeric',month:'short'})}</span></span>` +
      `<span class="rx" data-del="${o.id}">✕</span></div>`).join('')
    : '<div class="row" style="color:var(--muted)">Пока пусто — нарисуйте и сохраните</div>';
  routesEl.innerHTML = html;
  const sv = document.getElementById('rSave');
  if (sv) sv.onclick = saveCurrent;
  routesEl.querySelectorAll('.rx').forEach(x => x.onclick = e => {
    e.stopPropagation();
    persistRoutes(loadRoutes().filter(o => o.id !== +x.dataset.del));
    renderRoutes();
  });
  routesEl.querySelectorAll('.row[data-id]').forEach(r => r.onclick = () => {
    const o = loadRoutes().find(q => q.id === +r.dataset.id);
    if (o) openRoute(o);
  });
}

function closeRoutes(){ routesEl.classList.remove('on'); updatePillVis(); }
function updatePillVis(){
  pill.style.visibility =
    (layersEl.classList.contains('on') || routesEl.classList.contains('on')) ? 'hidden' : '';
}
document.getElementById('bRoutes').onclick = () => {
  if (routesEl.classList.contains('on')) return closeRoutes();
  closeLayers();
  renderRoutes();
  routesEl.classList.add('on');
  updatePillVis();
};

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
      paintSlider(w, +w.value/30*100, '#2f6f4f');
    };
    w.oninput = upd; upd();
  }
}
document.getElementById('obNext').onclick = () => {
  if (obStep === 2){ const v = +document.getElementById('obB').value;
    if (v >= 35 && v <= 160){ S.body = v; localStorage.setItem('body', v); paintTicks(); updateWeightUI(); } }
  if (obStep < OB.length-1){ obStep++; obRender(); } else obClose();
};
document.getElementById('obSkip').onclick = () => obClose();
function obClose(){ ob.classList.remove('on'); localStorage.setItem('onboarded','1'); }

// ---------- запуск ----------
paintTicks();
updateWeightUI();
updateEmptyHint();
applyLayers();

fetch('sample.json').then(r => r.json()).then(j => {
  sample = j;
  if (!localStorage.getItem('onboarded') || location.hash === '#ob'){ ob.classList.add('on'); obRender(); }
});
