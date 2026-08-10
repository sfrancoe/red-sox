// Story: WAR Room - DESIGN MOCKUP, not a finished story.
//
// The WAR values below are real (Baseball Reference daily bWAR, fetched 2026-08-10)
// but they are FROZEN - baked into this file rather than read from data/. The
// overnight movement deltas in `d`/`jump` are INVENTED, so the movement UI has
// something to show; the daily archive that would make them real does not exist yet.
// The only true delta is Rafaela's -0.2 (meta.json had him at 5.1 the day before).
//
// `desc` (handedness + position, or handedness + bullpen role) is real, joined from
// the MLB Stats API on mlb_ID. Roles are derived: mostly-starts, or a starter's
// innings per appearance, counts as a starter; 10+ saves counts as a closer.
//
// Before this becomes a real story: extend scripts/fetch_seasons.py to emit
// data/war.json + a dated data/war_history.json, and fetch() them here instead.
const PLAYERS = [{"i": 0, "name": "Ceddanne Rafaela", "war": 4.9, "kind": "bat", "desc": "right-handed center fielder", "g": 113, "pa": 471, "ip": 0.0, "off": 3.3, "def": 2.0, "d": -0.2, "jump": 0}, {"i": 1, "name": "Wilyer Abreu", "war": 4.5, "kind": "bat", "desc": "left-handed right fielder", "g": 114, "pa": 496, "ip": 0.0, "off": 2.3, "def": 1.9, "d": 0.2, "jump": 0}, {"i": 2, "name": "Willson Contreras", "war": 3.9, "kind": "bat", "desc": "right-handed first baseman", "g": 107, "pa": 439, "ip": 0.0, "off": 4.1, "def": -0.7, "d": -0.1, "jump": 0}, {"i": 3, "name": "Caleb Durbin", "war": 3.2, "kind": "bat", "desc": "right-handed third baseman", "g": 110, "pa": 414, "ip": 0.0, "off": 2.1, "def": 1.4, "d": 0.1, "jump": 0}, {"i": 4, "name": "Sonny Gray", "war": 2.9, "kind": "pit", "desc": "right-handed starter", "g": 21, "pa": 0, "ip": 119.7, "off": 0.0, "def": 0.0, "d": 0.0, "jump": 0}, {"i": 5, "name": "Payton Tolle", "war": 1.8, "kind": "pit", "desc": "left-handed starter", "g": 19, "pa": 0, "ip": 107.0, "off": 0.0, "def": 0.0, "d": 0.3, "jump": 1}, {"i": 6, "name": "Connelly Early", "war": 1.7, "kind": "pit", "desc": "left-handed starter", "g": 17, "pa": 0, "ip": 91.7, "off": 0.0, "def": 0.0, "d": -0.1, "jump": -1}, {"i": 7, "name": "Ranger Suarez", "war": 1.6, "kind": "pit", "desc": "left-handed starter", "g": 20, "pa": 0, "ip": 103.0, "off": 0.0, "def": 0.0, "d": 0.1, "jump": 0}, {"i": 8, "name": "Garrett Whitlock", "war": 1.5, "kind": "pit", "desc": "right-handed reliever", "g": 46, "pa": 0, "ip": 44.0, "off": 0.0, "def": 0.0, "d": -0.1, "jump": 0}, {"i": 9, "name": "Jake Bennett", "war": 1.4, "kind": "pit", "desc": "left-handed starter", "g": 13, "pa": 0, "ip": 76.7, "off": 0.0, "def": 0.0, "d": 0.2, "jump": 1}, {"i": 10, "name": "Andruw Monasterio", "war": 1.3, "kind": "bat", "desc": "right-handed shortstop", "g": 77, "pa": 248, "ip": 0.0, "off": 1.5, "def": -0.0, "d": 0.0, "jump": 0}, {"i": 11, "name": "Isiah Kiner-Falefa", "war": 1.3, "kind": "bat", "desc": "right-handed second baseman", "g": 47, "pa": 132, "ip": 0.0, "off": 0.9, "def": 0.6, "d": 0.1, "jump": 1}, {"i": 12, "name": "Aroldis Chapman", "war": 1.2, "kind": "pit", "desc": "left-handed closer", "g": 43, "pa": 0, "ip": 39.7, "off": 0.0, "def": 0.0, "d": -0.2, "jump": -2}, {"i": 13, "name": "Connor Wong", "war": 1.0, "kind": "bat", "desc": "right-handed catcher", "g": 59, "pa": 181, "ip": 0.0, "off": 0.7, "def": 0.7, "d": 0.1, "jump": 0}, {"i": 14, "name": "Jovani Mor\u00e1n", "war": 0.9, "kind": "pit", "desc": "left-handed reliever", "g": 35, "pa": 0, "ip": 48.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 15, "name": "Roman Anthony", "war": 0.7, "kind": "bat", "desc": "left-handed left fielder", "g": 30, "pa": 130, "ip": 0.0, "off": 0.3, "def": 0.3, "d": 0.2, "jump": 1}, {"i": 16, "name": "Masataka Yoshida", "war": 0.7, "kind": "bat", "desc": "left-handed designated hitter", "g": 81, "pa": 272, "ip": 0.0, "off": 1.0, "def": -0.8, "d": 0.0, "jump": 0}, {"i": 17, "name": "Jarren Duran", "war": 0.6, "kind": "bat", "desc": "left-handed left fielder", "g": 110, "pa": 467, "ip": 0.0, "off": -0.2, "def": 0.4, "d": -0.1, "jump": -1}, {"i": 18, "name": "Jahmai Jones", "war": 0.5, "kind": "bat", "desc": "right-handed designated hitter", "g": 13, "pa": 23, "ip": 0.0, "off": 0.6, "def": -0.2, "d": null, "jump": 0}, {"i": 19, "name": "Anthony Seigler", "war": 0.5, "kind": "bat", "desc": "switch-hitting second baseman", "g": 40, "pa": 150, "ip": 0.0, "off": 0.7, "def": -0.1, "d": null, "jump": 0}, {"i": 20, "name": "Tyron Guerrero", "war": 0.5, "kind": "pit", "desc": "right-handed reliever", "g": 29, "pa": 0, "ip": 30.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 21, "name": "Nick Sogard", "war": 0.4, "kind": "bat", "desc": "switch-hitting second baseman", "g": 22, "pa": 90, "ip": 0.0, "off": 0.6, "def": -0.1, "d": null, "jump": 0}, {"i": 22, "name": "Patrick Sandoval", "war": 0.2, "kind": "pit", "desc": "left-handed starter", "g": 5, "pa": 0, "ip": 24.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 23, "name": "Tyler Samaniego", "war": 0.2, "kind": "pit", "desc": "left-handed reliever", "g": 20, "pa": 0, "ip": 20.3, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 24, "name": "Eli White", "war": 0.2, "kind": "bat", "desc": "right-handed right fielder", "g": 5, "pa": 12, "ip": 0.0, "off": 0.1, "def": 0.1, "d": null, "jump": 0}, {"i": 25, "name": "Alec Gamboa", "war": 0.2, "kind": "pit", "desc": "left-handed reliever", "g": 7, "pa": 0, "ip": 13.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 26, "name": "Jake Rogers", "war": 0.2, "kind": "bat", "desc": "right-handed catcher", "g": 3, "pa": 9, "ip": 0.0, "off": 0.2, "def": 0.0, "d": null, "jump": 0}, {"i": 27, "name": "Nate Eaton", "war": 0.2, "kind": "bat", "desc": "right-handed outfielder", "g": 14, "pa": 39, "ip": 0.0, "off": -0.1, "def": 0.2, "d": null, "jump": 0}, {"i": 28, "name": "Curtis Mead", "war": 0.1, "kind": "bat", "desc": "right-handed third baseman", "g": 1, "pa": 2, "ip": 0.0, "off": 0.0, "def": 0.1, "d": null, "jump": 0}, {"i": 29, "name": "Greg Weissert", "war": 0.1, "kind": "pit", "desc": "right-handed reliever", "g": 48, "pa": 0, "ip": 45.3, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 30, "name": "Jack Anderson", "war": 0.1, "kind": "pit", "desc": "right-handed reliever", "g": 3, "pa": 0, "ip": 8.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 31, "name": "Raymond Burgos", "war": 0.1, "kind": "pit", "desc": "left-handed starter", "g": 2, "pa": 0, "ip": 6.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 32, "name": "Erik Miller", "war": 0.1, "kind": "pit", "desc": "left-handed reliever", "g": 3, "pa": 0, "ip": 3.3, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 33, "name": "Tyler Uberstine", "war": 0.0, "kind": "pit", "desc": "right-handed reliever", "g": 1, "pa": 0, "ip": 2.7, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 34, "name": "Zack Kelly", "war": 0.0, "kind": "pit", "desc": "right-handed reliever", "g": 17, "pa": 0, "ip": 16.3, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 35, "name": "Ryan Watson", "war": 0.0, "kind": "pit", "desc": "right-handed reliever", "g": 35, "pa": 0, "ip": 55.7, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 36, "name": "Mickey Gasper", "war": -0.0, "kind": "bat", "desc": "switch-hitting catcher", "g": 34, "pa": 119, "ip": 0.0, "off": 0.1, "def": -0.1, "d": null, "jump": 0}, {"i": 37, "name": "Marcelo Mayer", "war": -0.0, "kind": "bat", "desc": "left-handed second baseman", "g": 70, "pa": 228, "ip": 0.0, "off": 0.2, "def": 0.1, "d": null, "jump": 0}, {"i": 38, "name": "Tsung-Che Cheng", "war": -0.0, "kind": "bat", "desc": "left-handed shortstop", "g": 14, "pa": 44, "ip": 0.0, "off": -0.1, "def": 0.1, "d": null, "jump": 0}, {"i": 39, "name": "Brett Harris", "war": -0.1, "kind": "bat", "desc": "right-handed third baseman", "g": 1, "pa": 3, "ip": 0.0, "off": -0.1, "def": -0.0, "d": null, "jump": 0}, {"i": 40, "name": "Joe La Sorsa", "war": -0.1, "kind": "pit", "desc": "left-handed reliever", "g": 1, "pa": 0, "ip": 0.3, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 41, "name": "Trevor Story", "war": -0.1, "kind": "bat", "desc": "right-handed shortstop", "g": 41, "pa": 176, "ip": 0.0, "off": 0.1, "def": 0.0, "d": 0.1, "jump": 0}, {"i": 42, "name": "Danny Coulombe", "war": -0.1, "kind": "pit", "desc": "left-handed reliever", "g": 29, "pa": 0, "ip": 22.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 43, "name": "Johan Oviedo", "war": -0.1, "kind": "pit", "desc": "right-handed starter", "g": 1, "pa": 0, "ip": 3.7, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 44, "name": "Eduardo Rivera", "war": -0.1, "kind": "pit", "desc": "left-handed starter", "g": 4, "pa": 0, "ip": 10.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 45, "name": "Tommy Kahnle", "war": -0.2, "kind": "pit", "desc": "right-handed reliever", "g": 8, "pa": 0, "ip": 9.0, "off": 0.0, "def": 0.0, "d": null, "jump": 0}, {"i": 46, "name": "Romy Gonzalez", "war": -0.4, "kind": "bat", "desc": "right-handed designated hitter", "g": 19, "pa": 73, "ip": 0.0, "off": -0.3, "def": -0.2, "d": null, "jump": 0}, {"i": 47, "name": "Carlos Narv\u00e1ez", "war": -0.5, "kind": "bat", "desc": "right-handed catcher", "g": 62, "pa": 197, "ip": 0.0, "off": -0.1, "def": 0.0, "d": null, "jump": 0}, {"i": 48, "name": "Brayan Bello", "war": -0.5, "kind": "pit", "desc": "right-handed starter", "g": 18, "pa": 0, "ip": 83.7, "off": 0.0, "def": 0.0, "d": 0.2, "jump": 2}, {"i": 49, "name": "Garrett Crochet", "war": -0.6, "kind": "pit", "desc": "left-handed starter", "g": 6, "pa": 0, "ip": 30.0, "off": 0.0, "def": 0.0, "d": -0.1, "jump": 0}, {"i": 50, "name": "Justin Slaten", "war": -0.6, "kind": "pit", "desc": "right-handed reliever", "g": 35, "pa": 0, "ip": 30.3, "off": 0.0, "def": 0.0, "d": -0.1, "jump": -1}];
// Frozen to the 2026-08-10 data refresh: 64-53 through 117 games. These are baked
// in because the WAR values are too \u2014 a live record against frozen WAR would drift
// apart and quietly misstate the gap.
const GAMES = 117, REAL_W = 64, REPL_PCT = 0.294;
// Displayed values are rounded to a decimal the way Baseball Reference shows them,
// but the team math uses the unrounded sum \u2014 rounding 51 players first loses 0.2
// wins, which is enough to move the projected record by a game.
const TEAM_WAR = 35.4800;
const CUTOFF = 0.3;

/* ---------- shared bar scale: zero sits at 12%, same units both directions ---------- */
const MAXW = Math.max(...PLAYERS.map(p=>p.war));
const UNIT = 88 / MAXW;                 // % of track per win

/* ---------- Concept 1: the ladder ---------- */
const board = document.getElementById('board');
const moreBtn = document.getElementById('more');
let filter = 'all', expanded = false;

const CROWN = '<svg class="crown" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 20h20l-2-11-5 4-3-7-3 7-5-4z"/></svg>';

function movement(p){
  if(p.d === null) return '<span class="mv flat">\u2013</span>';
  const up = p.d > 0;
  const jump = p.jump ? ` <span class="jump">${up?'\u2191':'\u2193'}${Math.abs(p.jump)}</span>` : '';
  return `<span class="mv ${up?'up':'dn'}">${up?'\u25B2':'\u25BC'}${Math.abs(p.d).toFixed(1)}${jump}</span>`;
}

function detail(p){
  const wins = p.war.toFixed(1);
  const line = p.kind === 'bat'
    ? `<div class="stats">
         <div class="stat"><b>${p.g}</b><span>Games</span></div>
         <div class="stat"><b>${p.pa}</b><span>Plate app.</span></div>
         <div class="stat"><b>${p.off>=0?'+':''}${p.off.toFixed(1)}</b><span>Bat</span></div>
         <div class="stat"><b>${p.def>=0?'+':''}${p.def.toFixed(1)}</b><span>Glove</span></div>
       </div>`
    : `<div class="stats">
         <div class="stat"><b>${p.g}</b><span>Appearances</span></div>
         <div class="stat"><b>${p.ip.toFixed(1)}</b><span>Innings</span></div>
       </div>`;
  const bought = p.war >= 0
    ? `Swap him for a Triple-A call-up and the Red Sox are <b>${wins} wins</b> worse off.`
    : `A freely available replacement would have been <b>${Math.abs(p.war).toFixed(1)} wins better</b>.`;
  return `<div class="det">${line}<div class="bought">${bought}</div></div>`;
}

function visible(){
  const pool = PLAYERS.filter(p => filter === 'all' || p.kind === filter);
  return expanded ? pool : pool.filter(p => p.war >= CUTOFF);
}

function render(){
  const list = visible();
  board.innerHTML = list.map((p,i) => {
    const neg = p.war < 0;
    const w = Math.abs(p.war) * UNIT;
    const style = neg ? `left:${12-w}%;width:${w}%` : `left:12%;width:${w}%`;
    const cls = neg ? 'negb' : p.kind;
    return `<button class="row ${i===0&&filter==='all'&&p.war>0?'lead':''} ${neg?'neg':''}"
        aria-expanded="false" data-i="${p.i}">
      <div class="rk">${i+1}</div>
      <div class="nm">
        <span class="who">${p.name}</span>
        ${movement(p)}
      </div>
      <div class="meta ${p.kind}">${p.desc}</div>
      <div class="trk"><div class="zero"></div><div class="bar ${cls}" data-w="${style}">
        ${i===0&&filter==='all'&&p.war>0?CROWN:''}</div></div>
      <div class="war">${p.war>0?'':(p.war<0?'\u2212':'')}${Math.abs(p.war).toFixed(1)}</div>
      ${detail(p)}
    </button>`;
  }).join('');

  // let layout settle, then run the bars out so the board builds itself
  requestAnimationFrame(()=>requestAnimationFrame(()=>{
    board.querySelectorAll('.bar').forEach((b,n)=>{
      b.style.transitionDelay = Math.min(n*26,700)+'ms';
      b.style.cssText += ';'+b.dataset.w;
    });
  }));

  const pool = PLAYERS.filter(p => filter === 'all' || p.kind === filter);
  const hidden = pool.length - pool.filter(p=>p.war>=CUTOFF).length;
  moreBtn.style.display = hidden > 0 ? 'block' : 'none';
  moreBtn.textContent = expanded
    ? 'Show only the contributors'
    : `Show the other ${hidden} \u2014 including the negatives`;
}

board.addEventListener('click', e => {
  const row = e.target.closest('.row');
  if(!row) return;
  const open = row.getAttribute('aria-expanded') === 'true';
  board.querySelectorAll('.row').forEach(r=>r.setAttribute('aria-expanded','false'));
  row.setAttribute('aria-expanded', open ? 'false' : 'true');
});

document.querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => {
  document.querySelectorAll('.chip').forEach(o=>o.setAttribute('aria-pressed','false'));
  c.setAttribute('aria-pressed','true');
  filter = c.dataset.f;
  render();
}));

moreBtn.addEventListener('click', () => { expanded = !expanded; render(); });

/* ---------- Concept 2: the replacement line ---------- */
const removed = new Set();
const pills = document.getElementById('pills');
const projRec = document.getElementById('projRec');
const projSub = document.getElementById('projSub');
const gapNote = document.getElementById('gapNote');
const TOP = PLAYERS.filter(p=>p.war>0).slice(0,12);

pills.innerHTML = TOP.map(p =>
  `<button class="pill" aria-pressed="false" data-i="${p.i}">${p.name}
     <span class="w">${p.war.toFixed(1)}</span></button>`).join('');

function updateLine(){
  const kept = TEAM_WAR - PLAYERS.filter(p=>removed.has(p.i)).reduce((s,p)=>s+p.war,0);
  const wins = Math.round(REPL_PCT*GAMES + kept);
  projRec.innerHTML = `${wins}<span class="dash">\u2013</span>${GAMES-wins}`;
  projSub.textContent = removed.size
    ? `Replacement baseline plus ${kept.toFixed(1)} wins \u2014 ${removed.size} player${removed.size>1?'s':''} removed`
    : `Replacement baseline plus ${kept.toFixed(1)} wins`;
  const diff = wins - REAL_W;
  gapNote.innerHTML = removed.size
    ? `Without ${removed.size === 1 ? 'him' : 'those ' + removed.size}, WAR pegs this roster at
       <b>${wins}\u2013${GAMES-wins}</b> \u2014 ${diff <= 0
         ? `<b>${Math.abs(diff)} games worse</b> than the team actually is.`
         : `still <b>${diff} better</b> than their real record.`}`
    : `WAR says this roster is worth about <b>${wins}\u2013${GAMES-wins}</b>. They're
       ${REAL_W}\u2013${GAMES-REAL_W}. That's roughly <b>six wins</b> left on the table \u2014
       bullpen, sequencing, luck, or all three.`;
}

pills.addEventListener('click', e => {
  const pill = e.target.closest('.pill');
  if(!pill) return;
  const i = +pill.dataset.i;
  if(removed.has(i)) removed.delete(i); else removed.add(i);
  pill.setAttribute('aria-pressed', removed.has(i) ? 'true' : 'false');
  updateLine();
});

document.getElementById('resetBtn').addEventListener('click', () => {
  removed.clear();
  pills.querySelectorAll('.pill').forEach(p=>p.setAttribute('aria-pressed','false'));
  updateLine();
});

document.getElementById('topBtn').addEventListener('click', () => {
  removed.clear();
  TOP.slice(0,4).forEach(p=>removed.add(p.i));
  pills.querySelectorAll('.pill').forEach(p =>
    p.setAttribute('aria-pressed', removed.has(+p.dataset.i) ? 'true' : 'false'));
  updateLine();
});

render();
updateLine();
