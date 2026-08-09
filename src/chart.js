// Chart engine — canvas render, animation state machine, scrub, controls.
// One chart per page; module scope holds its state.
import { createAudio } from './audio.js';

// ES modules are strict mode already, and a "use strict" directive is illegal in a
// function with a destructured parameter list — so there is deliberately none here.
export function initStory({ DATA, CONFIG, YEARS }){
  const audio = createAudio();


// ---- build season models ----
const seasons = YEARS.map(y=>{
  const d=DATA[String(y)], c=CONFIG[y];
  const pts=[{g:0,d:0}];
  const cumW=[0], cumL=[0], streak=[''];
  for(let i=0;i<d.diff.length;i++){
    const g=i+1, df=d.diff[i];
    pts.push({g:g,d:df});
    cumW[g]=(g+df)/2; cumL[g]=(g-df)/2;
  }
  // smoothed display series: shrinking symmetric moving average (endpoints pinned exact)
  const rawFull=[0]; for(let i=0;i<d.diff.length;i++) rawFull.push(d.diff[i]);
  const SMOOTH_K=3, disp=rawFull.map((_,g)=>{
    const k=Math.min(SMOOTH_K,g,(rawFull.length-1)-g); let sum=0,c=0;
    for(let j=g-k;j<=g+k;j++){sum+=rawFull[j];c++;}
    return sum/c;
  });
  if(disp.length>108) disp[108]=6;   // pin the exact 57–51 convergence at game 108
  // streak labels
  for(let g=1;g<=d.seq.length;g++){
    const r=d.seq[g-1]; let n=1;
    while(g-1-n>=0 && d.seq[g-1-n]===r) n++;
    streak[g]=r+n;
  }
  return {year:y,color:c.color,label:c.label,beats:c.beats,
          diff:d.diff,seq:d.seq,pts,disp,cumW,cumL,streak,
          record:d.record,endDiff:d.diff[d.diff.length-1],
          warLeader:d.war_leader||null,
          endGame:d.end_game||d.diff.length, inProgress:!!d.in_progress, visible:true};
});

// =========================================================
// Canvas + scales
// =========================================================
const canvas=document.getElementById('chart');
const ctx=canvas.getContext('2d');
let W=0,H=0,DPR=1;
const DMIN=-15.5, DMAX=18, GMAX=162;
let padL=64,padR=132,padT=26,padB=44;

function resize(){
  const r=canvas.getBoundingClientRect();
  DPR=Math.min(window.devicePixelRatio||1,2);
  W=r.width; H=r.height;
  canvas.width=Math.round(W*DPR); canvas.height=Math.round(H*DPR);
  ctx.setTransform(DPR,0,0,DPR,0,0);
  // the right gutter carries year + record + WAR leader, so it needs the room
  padL = W<520?46:64; padR = W<520?96:182; padB = W<520?36:44;
}
const xFor=g=>padL+(g/GMAX)*(W-padL-padR);
const yFor=d=>padT+(1-(d-DMIN)/(DMAX-DMIN))*(H-padT-padB);

// =========================================================
// State machine
// =========================================================
const HOLD=0.7;               // pause between seasons (s)
const BASE_GPS=26;            // games per second at 1x (covers a full 162-game season)
let state, playing=false, lastT=0, speed=1;
function reset(toFinale){
  state={phase:0,prog:0,hold:0,finale:0,idle:0,done:false};
  seasons.forEach(s=>s.visible = s.visible!==false);
  if(toFinale){state.phase=seasons.length;state.done=true;state.finale=1;}
  activeBeat='';
  updateScoreboard(true);
}

// =========================================================
// Drawing
// =========================================================
function clear(){ctx.clearRect(0,0,W,H);}

function drawGrid(){
  ctx.save();
  ctx.font='500 11px OswaldX, sans-serif';
  ctx.textBaseline='middle';
  // horizontal grid + y labels
  const ticks=[15,10,5,0,-5,-10,-15];
  ticks.forEach(t=>{
    const y=yFor(t);
    const base = t===0;
    if(base){
      // chalk .500 line (dashed)
      ctx.strokeStyle='rgba(233,227,208,.55)';
      ctx.lineWidth=1.5; ctx.setLineDash([7,7]);
      ctx.beginPath();ctx.moveTo(padL,y);ctx.lineTo(W-padR,y);ctx.stroke();
      ctx.setLineDash([]);
    }else{
      ctx.strokeStyle='rgba(23,48,35,.9)';
      ctx.lineWidth=1;
      ctx.beginPath();ctx.moveTo(padL,y);ctx.lineTo(W-padR,y);ctx.stroke();
    }
    ctx.fillStyle=base?'rgba(233,227,208,.9)':'rgba(138,163,147,.75)';
    ctx.textAlign='right';
    const lbl = base?'.500' : (t>0?'+'+t:''+t);
    ctx.fillText(lbl,padL-10,y);
  });
  // x ticks (quarters)
  ctx.textAlign='center';ctx.textBaseline='top';
  [0,54,162].forEach(g=>{
    const x=xFor(g);
    ctx.strokeStyle='rgba(23,48,35,.7)';ctx.lineWidth=1;
    ctx.beginPath();ctx.moveTo(x,padT);ctx.lineTo(x,H-padB);ctx.stroke();
    ctx.fillStyle='rgba(138,163,147,.75)';
    // the finish label sits out in the right gutter — centred on the plot edge it
    // lands under the narration panel now that the gutter carries WAR lines. On a
    // phone the panel is wide enough to swallow it either way, and nudging it right
    // just leaves a fragment poking out, so only do this where there's room.
    if(g===162 && W>=520){
      ctx.textAlign='right'; ctx.fillText('G162 · Finish',W-6,H-padB+7); ctx.textAlign='center';
    }else{
      ctx.fillText(g===0?'Opening Day':(g===162?'G162 · Finish':('G'+g)),x,H-padB+7);
    }
  });
  // checkpoint emphasis at 108
  const xc=xFor(108);
  ctx.strokeStyle='rgba(255,207,90,.35)';ctx.lineWidth=1.5;
  ctx.setLineDash([3,5]);
  ctx.beginPath();ctx.moveTo(xc,padT);ctx.lineTo(xc,H-padB);ctx.stroke();
  ctx.setLineDash([]);
  ctx.save();
  ctx.translate(xc,padT-2);
  ctx.fillStyle='rgba(255,207,90,.8)';ctx.textAlign='right';ctx.textBaseline='alphabetic';
  ctx.font='500 10px OswaldX, sans-serif';
  ctx.fillText('GAME 108 · 57–51 EVERY SEASON',-4,10);
  ctx.restore();
  ctx.restore();
}

// smooth curve through points (Catmull-Rom -> cubic bezier)
function smoothPath(P){
  if(!P.length) return;
  ctx.moveTo(P[0].x,P[0].y);
  if(P.length<3){ for(let i=1;i<P.length;i++) ctx.lineTo(P[i].x,P[i].y); return; }
  for(let i=0;i<P.length-1;i++){
    const p0=P[i-1]||P[i], p1=P[i], p2=P[i+1], p3=P[i+2]||P[i+1];
    const cp1x=p1.x+(p2.x-p0.x)/6, cp1y=p1.y+(p2.y-p0.y)/6;
    const cp2x=p2.x-(p3.x-p1.x)/6, cp2y=p2.y-(p3.y-p1.y)/6;
    ctx.bezierCurveTo(cp1x,cp1y,cp2x,cp2y,p2.x,p2.y);
  }
}

// draw a season line up to game `upto` (float), using the smoothed series. glow = active
function drawLine(s,upto,opts){
  opts=opts||{};
  const disp=s.disp;
  const EG=s.endGame;
  const full = upto>=EG;
  const whole = Math.min(Math.floor(upto),EG);
  const P=[];
  for(let g=0;g<=whole;g++) P.push({x:xFor(g),y:yFor(disp[g])});
  let head;
  if(!full && whole<EG){
    const frac=upto-whole;
    if(frac>0){
      const di=disp[whole]+(disp[whole+1]-disp[whole])*frac;
      P.push({x:xFor(whole+frac),y:yFor(di)});
      head={g:whole+frac,d:di};
    } else head={g:whole,d:disp[whole]};
  } else head={g:EG,d:disp[EG]};
  ctx.save();
  ctx.lineJoin='round';ctx.lineCap='round';
  ctx.strokeStyle=s.color;
  ctx.globalAlpha=opts.alpha!=null?opts.alpha:1;
  ctx.lineWidth=opts.width||(opts.active?3:2);
  if(opts.glow){ctx.shadowColor=s.color;ctx.shadowBlur=opts.active?18:9;}
  ctx.beginPath();
  smoothPath(P);
  ctx.stroke();
  ctx.restore();
  return head;
}

// Wally's head — the leading tip of a line being drawn. Vector rather than a
// bitmap: it stays crisp at any DPR and adds nothing to the payload, and a
// photo scaled to 28px turns to mush anyway. Authored in a 24-unit box centered
// on the head, so the line's leading point sits mid-face and never jumps.
// Draw order matters: head, cap, grin, then nose over the grin, then eyes.
function drawWally(x,y,size){
  const s=size/24;
  ctx.save();
  ctx.translate(x,y);ctx.scale(s,s);
  ctx.lineJoin='round';ctx.lineCap='round';

  // fuzzy green head — alternating radii give the fur its ragged edge
  const N=46;
  ctx.beginPath();
  for(let i=0;i<=N;i++){
    const a=i/N*Math.PI*2;
    const r=9.7+(i%2?1.0+0.4*Math.sin(i*3.1):0);
    const px=Math.cos(a)*r*1.06, py=Math.sin(a)*r*0.95;
    i?ctx.lineTo(px,py):ctx.moveTo(px,py);
  }
  ctx.closePath();
  const fur=ctx.createRadialGradient(-3,-4,1,0,0,13);
  fur.addColorStop(0,'#63d96e');fur.addColorStop(.55,'#2bb443');fur.addColorStop(1,'#0f7a2e');
  ctx.fillStyle=fur;ctx.fill();

  // cap, tilted back
  ctx.save();
  ctx.translate(-2.2,-8.2);ctx.rotate(-0.36);
  ctx.fillStyle='#16295c';
  ctx.beginPath();ctx.moveTo(-6.4,0.9);
  ctx.bezierCurveTo(-6.6,-4.4,-2.6,-5.4,0.2,-5.4);
  ctx.bezierCurveTo(3.4,-5.4,6.2,-3.6,6.3,0.6);
  ctx.lineTo(6.3,1.0);ctx.lineTo(-6.4,0.9);ctx.closePath();ctx.fill();
  ctx.fillStyle='#101f47';
  ctx.beginPath();ctx.moveTo(-5.4,0.2);
  ctx.bezierCurveTo(-9.0,-0.4,-11.0,0.7,-10.7,1.8);
  ctx.bezierCurveTo(-9.0,2.7,-6.2,2.2,-5.0,1.5);
  ctx.closePath();ctx.fill();
  ctx.fillStyle='#c8102e';
  ctx.font='700 4.2px Georgia, serif';ctx.textAlign='center';ctx.textBaseline='middle';
  ctx.fillText('B',0.4,-2.0);
  ctx.restore();

  // grin — kept inside the fur outline so the tongue never floats loose
  ctx.fillStyle='#0f1014';
  ctx.beginPath();
  ctx.moveTo(-0.6,3.2);
  ctx.bezierCurveTo(2.6,2.6,6.8,3.2,7.6,4.2);
  ctx.bezierCurveTo(6.8,7.4,2.8,8.4,0.6,6.2);
  ctx.closePath();ctx.fill();
  ctx.fillStyle='#e0243a';
  ctx.beginPath();ctx.ellipse(4.6,5.6,1.6,1.1,-0.25,0,7);ctx.fill();

  // nose, overlapping the top of the grin
  const nose=ctx.createRadialGradient(0.9,0.2,0.3,2.2,1.7,4.0);
  nose.addColorStop(0,'#ffd85c');nose.addColorStop(.5,'#ff9f22');nose.addColorStop(1,'#ee6b00');
  ctx.fillStyle=nose;
  ctx.beginPath();ctx.ellipse(2.1,1.5,3.3,2.8,-0.15,0,7);ctx.fill();

  // eyes
  ctx.fillStyle='#fff';ctx.strokeStyle='#10240f';ctx.lineWidth=0.5;
  ctx.beginPath();ctx.ellipse(0.2,-3.2,3.0,3.4,-0.1,0,7);ctx.fill();ctx.stroke();
  ctx.beginPath();ctx.ellipse(5.6,-2.6,2.5,2.9,0.05,0,7);ctx.fill();ctx.stroke();
  ctx.fillStyle='#0d0d10';
  ctx.beginPath();ctx.ellipse(1.0,-2.8,1.35,1.6,0,0,7);ctx.fill();
  ctx.beginPath();ctx.ellipse(6.1,-2.3,1.2,1.45,0,0,7);ctx.fill();
  ctx.fillStyle='#fff';
  ctx.beginPath();ctx.arc(0.6,-3.5,0.45,0,7);ctx.fill();
  ctx.beginPath();ctx.arc(5.75,-2.95,0.4,0,7);ctx.fill();
  ctx.restore();
}

function drawCometHead(s,head){
  const x=xFor(head.g),y=yFor(head.d);
  const size=W<520?22:28;
  const rad=size*0.9;
  // Wally is the same green on all four lines, so the halo carries the season
  // color — it's what still ties the moving head to the line it belongs to.
  ctx.save();
  const g=ctx.createRadialGradient(x,y,size*0.35,x,y,rad);
  g.addColorStop(0,s.color+'99');g.addColorStop(.55,s.color+'44');g.addColorStop(1,s.color+'00');
  ctx.globalAlpha=.9;ctx.fillStyle=g;
  ctx.beginPath();ctx.arc(x,y,rad,0,7);ctx.fill();
  ctx.restore();
  drawWally(x,y,size);

  // floating label with year + live record
  const gInt=Math.max(0,Math.min(s.endGame,Math.round(head.g)));
  const w=Math.round(s.cumW[gInt]||0), l=Math.round(s.cumL[gInt]||0);
  const txt=s.year+'  '+w+'–'+l;
  ctx.save();
  ctx.font='400 15px AntonX, sans-serif';
  const tw=ctx.measureText(txt).width;
  const off=size*0.5+7;
  let lx=x+off, ly=y-off;
  if(lx+tw+14>W-6) lx=x-off-tw-8;
  ctx.globalAlpha=.92;
  ctx.fillStyle='rgba(8,18,12,.72)';
  roundRect(lx-7,ly-15,tw+14,22,6);ctx.fill();
  ctx.globalAlpha=1;ctx.fillStyle=s.color;ctx.textBaseline='alphabetic';
  ctx.fillText(txt,lx,ly);
  ctx.restore();
}

function roundRect(x,y,w,h,r){
  ctx.beginPath();
  ctx.moveTo(x+r,y);ctx.arcTo(x+w,y,x+w,y+h,r);ctx.arcTo(x+w,y+h,x,y+h,r);
  ctx.arcTo(x,y+h,x,y,r);ctx.arcTo(x,y,x+w,y,r);ctx.closePath();
}

// Small gold crown, marking the season's WAR leader. Drawn rather than typed:
// an emoji would render differently on every platform, and this page self-hosts
// its fonts precisely so it looks the same everywhere. Returns its width.
function drawCrown(x,y,h){
  const s=h/7;
  ctx.save();
  ctx.translate(x,y-h/2); ctx.scale(s,s);
  ctx.beginPath();
  ctx.moveTo(0,7); ctx.lineTo(0,1); ctx.lineTo(2.5,4); ctx.lineTo(5,0.4);
  ctx.lineTo(7.5,4); ctx.lineTo(10,1); ctx.lineTo(10,7);
  ctx.closePath();
  ctx.fillStyle='#ffcf5a'; ctx.fill();
  ctx.restore();
  return 10*s;
}

// endpoint tags in right gutter with collision avoidance
function drawEndpointTags(list,opts){
  opts=opts||{};
  const big=opts.big;
  list.forEach(s=>{
    const x=xFor(s.endGame), y=yFor(s.endDiff);
    // endpoint dot
    ctx.save();
    ctx.shadowColor=s.color;ctx.shadowBlur=opts.pulse?opts.pulse:8;
    ctx.fillStyle=s.color;
    ctx.beginPath();ctx.arc(x,y,big?5.5:4,0,7);ctx.fill();
    ctx.restore();
    // finished seasons tag to the right (in the gutter); 2026 (in progress) tags up-left of its live head
    const lx = s.inProgress ? x-12 : x+12;
    const align = s.inProgress ? 'right' : 'left';
    ctx.save();
    ctx.textAlign=align; ctx.textBaseline='middle';
    ctx.font='400 '+(big?18:15)+'px AntonX, sans-serif';
    ctx.fillStyle=s.color;
    ctx.fillText(s.inProgress? (s.year+' \u25b8') : (''+s.year), lx, y-(big?16:13));
    ctx.font='500 '+(big?13:11)+'px OswaldX, sans-serif';
    ctx.fillStyle='rgba(238,244,236,.9)';
    ctx.fillText(s.record.replace('-','\u2013')+(s.inProgress?' \u00b7 live':''), lx, y+(big?1:1));
    // who carried the season \u2014 bWAR leader. The gutter is narrow, so drop to the
    // surname when the full name won't fit rather than letting it run off-canvas.
    const wl=s.warLeader;
    if(wl && wl.name){
      ctx.font='500 '+(big?14:12)+'px OswaldX, sans-serif';
      const num=wl.war.toFixed(1), last=wl.name.split(' ').pop();
      // an unfinished season's WAR is a running total, so say so
      const suf=s.inProgress?' WAR YTD':' WAR';
      const ch=big?9:8, cw=ch*10/7, gap=4;
      const gutter=(s.inProgress? lx-padL : W-6-lx)-cw-gap;
      // widest form that still fits the gutter \u2014 on a phone that's the last one
      const forms=[wl.name+' \u00b7 '+num+suf, last+' \u00b7 '+num+suf,
                   last+' '+num+(s.inProgress?' YTD':'')];
      const txt=forms.find(t=>ctx.measureText(t).width<=gutter) || forms[forms.length-1];
      const ty=y+(big?19:16);
      ctx.globalAlpha=.9;
      // crown leads the name, whichever side the tag is anchored on
      const tw=ctx.measureText(txt).width;
      drawCrown(s.inProgress? lx-tw-gap-cw : lx, ty, ch);
      ctx.fillStyle=s.color;
      ctx.fillText(txt, s.inProgress? lx : lx+cw+gap, ty);
    }
    ctx.restore();
  });
}

function drawConvergenceBand(alpha){
  const yTop=yFor(7.6), yBot=yFor(4.4);
  const x1=xFor(88), x2=xFor(108);
  ctx.save();
  ctx.globalAlpha=alpha*.5;
  const g=ctx.createLinearGradient(x1,0,x2,0);
  g.addColorStop(0,'rgba(255,207,90,0)');g.addColorStop(1,'rgba(255,207,90,.18)');
  ctx.fillStyle=g;
  roundRect(x1,yTop,x2-x1,yBot-yTop,10);ctx.fill();
  ctx.globalAlpha=alpha*.8;
  ctx.strokeStyle='rgba(255,207,90,.7)';ctx.lineWidth=1.4;ctx.setLineDash([4,4]);
  ctx.shadowColor='rgba(255,207,90,.6)';ctx.shadowBlur=14;
  roundRect(x1,yTop,x2-x1,yBot-yTop,10);ctx.stroke();
  ctx.setLineDash([]);
  // caption
  ctx.globalAlpha=alpha;
  ctx.fillStyle='rgba(255,207,90,.95)';ctx.textAlign='center';
  ctx.font='500 12px OswaldX, sans-serif';
  ctx.fillText('57–51 AFTER 108 · EVERY TIME',(x1+x2)/2,yTop-9);
  ctx.restore();
}

// =========================================================
// Render
// =========================================================
let pulseT=0;
function render(){
  clear();
  drawGrid();
  const revealed=[]; // fully drawn seasons
  for(let i=0;i<state.phase && i<seasons.length;i++) revealed.push(seasons[i]);

  // completed (ghost) lines
  revealed.forEach(s=>{ if(s.visible) drawLine(s,s.endGame,{alpha:state.done?0.9:0.5,glow:true,width:state.done?2.4:2}); });

  // active line
  const inFinale = state.phase>=seasons.length;
  if(!inFinale){
    const s=seasons[state.phase];
    if(s && s.visible){
      const head=drawLine(s,state.prog,{active:true,glow:true,alpha:1});
      if(state.prog>0.2 && state.prog<s.endGame) drawCometHead(s,head);
    }
  }

  // endpoint tags for revealed
  const tagList=revealed.filter(s=>s.visible);
  if(tagList.length){
    if(state.done){
      if(!reduce) pulseT+=0.05;
      const pulse=10+Math.sin(pulseT)*7;
      drawConvergenceBand(Math.min(1,state.finale));
      drawEndpointTags(tagList,{big:true,pulse:pulse});
    }else{
      drawEndpointTags(tagList,{});
    }
  }

  // scrub overlay
  if(scrub.active) drawScrub();
}

// =========================================================
// Scrub / explore
// =========================================================
const scrub={active:false,x:0};
function drawScrub(){
  const revealed=[];
  for(let i=0;i<state.phase && i<seasons.length;i++) if(seasons[i].visible) revealed.push(seasons[i]);
  if(!revealed.length) return;
  let g=Math.round(((scrub.x-padL)/(W-padL-padR))*GMAX);
  g=Math.max(0,Math.min(GMAX,g));
  const x=xFor(g);
  ctx.save();
  ctx.strokeStyle='rgba(233,227,208,.35)';ctx.lineWidth=1;ctx.setLineDash([3,4]);
  ctx.beginPath();ctx.moveTo(x,padT);ctx.lineTo(x,H-padB);ctx.stroke();ctx.setLineDash([]);
  // gather
  const rows=revealed.map(s=>{const gg=Math.min(g,s.endGame);return {s,gg,d:s.pts[gg].d,w:Math.round(s.cumW[gg]),l:Math.round(s.cumL[gg])};})
                     .sort((a,b)=>b.d-a.d);
  rows.forEach(r=>{
    const y=yFor(r.s.disp[r.gg]);
    ctx.fillStyle=r.s.color;ctx.shadowColor=r.s.color;ctx.shadowBlur=8;
    ctx.beginPath();ctx.arc(x,y,3.4,0,7);ctx.fill();ctx.shadowBlur=0;
  });
  // tooltip box
  const bw=132, lineH=17, bh=14+rows.length*lineH;
  let bx=x+12; if(bx+bw>W-4) bx=x-12-bw;
  let by=padT+8;
  ctx.fillStyle='rgba(8,18,12,.9)';ctx.strokeStyle='rgba(23,48,35,1)';ctx.lineWidth=1;
  roundRect(bx,by,bw,bh,8);ctx.fill();ctx.stroke();
  ctx.textBaseline='middle';ctx.textAlign='left';
  ctx.fillStyle='rgba(138,163,147,.9)';ctx.font='500 11px OswaldX, sans-serif';
  ctx.fillText((g===0?'OPENING DAY':'AFTER GAME '+g),bx+10,by+11);
  rows.forEach((r,i)=>{
    const yy=by+22+i*lineH;
    ctx.fillStyle=r.s.color;ctx.beginPath();ctx.arc(bx+13,yy,3.2,0,7);ctx.fill();
    ctx.fillStyle='rgba(238,244,236,.92)';ctx.font='400 13px AntonX, sans-serif';
    ctx.fillText(r.s.year,bx+22,yy+1);
    ctx.font='500 12px OswaldX, sans-serif';ctx.fillStyle='rgba(238,244,236,.85)';
    const rec=r.w+'–'+r.l;
    ctx.textAlign='right';ctx.fillText(rec,bx+bw-10,yy+1);ctx.textAlign='left';
  });
  ctx.restore();
}

// =========================================================
// Scoreboard + narration
// =========================================================
const el=id=>document.getElementById(id);
let activeBeat='';
function setSeasonColor(c){
  el('scoreboard').style.setProperty('--seasoncol',c);
  el('nInner').parentElement.style.setProperty('--seasoncol',c);
  el('nInner').style.setProperty('--seasoncol',c);
  document.querySelector('.narration .n-inner').style.borderLeftColor=c;
}
function updateScoreboard(force){
  const inFinale=state.phase>=seasons.length;
  if(inFinale){
    el('sbYear').textContent='4 SEASONS';
    el('sbArc').textContent='Same at 108 — then four fates';
    el('sbW').textContent='57';el('sbL').textContent='51';
    el('sbGame').textContent='Game 108';
    el('sbStreak').textContent='—';
    el('sbDiff').textContent=seasons.map(s=>s.record.replace('-','–')+(s.inProgress?' (live)':'')).join(' · ');
    el('scoreboard').style.setProperty('--seasoncol','var(--gold)');
    el('sbYear').style.color='var(--gold)';
    el('sbYear').style.fontSize='clamp(22px,2.4vw,32px)';
    return;
  }
  const s=seasons[state.phase]; if(!s)return;
  const EG=s.endGame;
  const gTrue=Math.max(0,Math.min(EG,Math.floor(state.prog)));
  // scoreboard updates in 5-game steps (snaps to the exact end) to avoid flicker
  const gShow=state.prog>=EG?EG:Math.floor(gTrue/5)*5;
  const w=Math.round(s.cumW[gShow]||0), l=Math.round(s.cumL[gShow]||0), df=(s.pts[gShow]?s.pts[gShow].d:0);
  el('sbYear').textContent=s.year; el('sbYear').style.fontSize='';
  el('sbYear').style.color=s.color;
  el('sbArc').textContent=s.label;
  el('sbW').textContent=w; el('sbL').textContent=l;
  el('sbGame').textContent='Game '+gShow;
  el('sbStreak').textContent = gShow>0 ? s.streak[gShow] : '—';
  el('sbDiff').textContent = df===0?'Even' : (df>0?('+'+df+' over .500'):(df+' under .500'));
  setSeasonColor(s.color);
  // narration beats track the true game so callouts stay on time
  let beat=null;
  for(const b of s.beats){ if(gTrue>=b.g) beat=b; }
  if(beat && beat.t!==activeBeat){
    activeBeat=beat.t;
    const nInner=el('nInner');
    el('narration').classList.remove('show');
    setTimeout(()=>{nInner.textContent=beat.t;el('narration').classList.add('show');},110);
  }
}

// =========================================================
// Animation loop
// =========================================================
function frame(t){
  const dt=Math.max(0,Math.min(0.05,(t-lastT)/1000||0)); lastT=t;
  if(playing) step(dt);
  // feed the story's progress to the music so it swells as the seasons stack up
  audio.setIntensity(state.phase>=seasons.length ? 1 : (state.phase + state.prog/seasons[state.phase].endGame)/seasons.length);
  render();
  requestAnimationFrame(frame);
}
function step(dt){
  if(state.phase>=seasons.length){ // finale
    if(state.finale<1) state.finale=Math.min(1,state.finale+dt*0.8);
    else if(playing) pause(1.8);   // show over → stop; let the finale chord ring out, then silence
    return;
  }
  if(state.hold>0){ state.hold-=dt; if(state.hold<=0) advancePhase(); return; }
  state.prog += dt*BASE_GPS*speed;
  const EG=seasons[state.phase].endGame;
  if(state.prog>=EG){
    state.prog=EG;
    updateScoreboard();
    state.hold=HOLD;
    audio.stinger(seasons[state.phase].color); // season-complete cue
  } else {
    updateScoreboard();
  }
}
function advancePhase(){
  state.phase++;
  state.prog=0;
  if(state.phase>=seasons.length){
    state.done=true;state.finale=0;
    updateScoreboard();
    showFinaleNarration();
    audio.finale();
  }else{
    activeBeat='';
    updateScoreboard(true);
  }
}
function showFinaleNarration(){
  const nInner=el('nInner');
  el('narration').classList.remove('show');
  setTimeout(()=>{
    // Built from the data so the daily refresh can never leave a stale record here.
    const R = Object.fromEntries(seasons.map(s=>[s.year, s.record.replace('-','–')]));
    const live = seasons.find(s=>s.inProgress);
    nInner.textContent =
      `Four roads met at 57–51 after 108 games — then split: 2023 faded to ${R[2023]}, `
      + `2024 held at ${R[2024]}, 2025 surged to ${R[2025]} and October…`
      + (live ? ` and ${live.year}? Still being written (${R[live.year]}).` : '');
    document.querySelector('.narration .n-inner').style.borderLeftColor='var(--gold)';
    el('narration').classList.add('show');
  },140);
}

// =========================================================
// Controls
// =========================================================
const playBtn=el('playBtn'),restartBtn=el('restartBtn'),muteBtn=el('muteBtn');
function play(){
  if(state.done){ reset(false); }         // replay from top
  playing=true; playBtn.textContent='❚❚ Pause';
  audio.start();
}
function pause(fade){ playing=false; playBtn.textContent='► Play'; audio.pause(fade); }
playBtn.addEventListener('click',()=>{ playing?pause():play(); });
restartBtn.addEventListener('click',()=>{ reset(false); playing=true; playBtn.textContent='❚❚ Pause'; audio.start(); });
el('speed').addEventListener('input',e=>{ speed=parseFloat(e.target.value); el('speedVal').textContent=speed+'×'; });
muteBtn.addEventListener('click',()=>{
  const on=audio.toggle();
  muteBtn.textContent = on?'♪ Music: On':'♪ Music: Off';
  muteBtn.setAttribute('aria-pressed',String(!on));
});

// scrub interactions
canvas.addEventListener('pointermove',e=>{
  const r=canvas.getBoundingClientRect();
  scrub.x=e.clientX-r.left;
  scrub.active = (!playing || state.done) && scrub.x>padL && scrub.x<W-padR;
});
canvas.addEventListener('pointerleave',()=>{scrub.active=false;});


// =========================================================
// Boot
// =========================================================
const reduce=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
new ResizeObserver(resize).observe(canvas);
resize();
reset(reduce);          // reduced motion → show full picture, no autoplay
if(reduce){ el('nInner').textContent='Four seasons, four roads, one record — hover to explore each game.'; el('narration').classList.add('show'); }
requestAnimationFrame(frame);

// Big center Play button on load: it's the obvious call-to-action AND the click
// is the user gesture that unlocks audio, so one press starts the animation with
// music together. Reduced-motion users skip it and get the full static picture.
const playOverlay=el('playOverlay');
if(reduce){
  playOverlay.remove();
}else{
  let launched=false;
  const startFromOverlay=()=>{
    if(launched) return; launched=true;                 // guard against tap firing twice
    playOverlay.classList.add('hide');
    setTimeout(()=>{ if(playOverlay.parentNode) playOverlay.remove(); },550);
    play();   // starts animation + music (this tap is the audio-unlocking gesture)
  };
  playOverlay.addEventListener('click',startFromOverlay);
  playOverlay.addEventListener('keydown',e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); startFromOverlay(); } });
  playOverlay.focus();
}
}
