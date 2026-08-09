// Audio engine — Web Audio hip-hop bed; the arrangement builds with the story.
//
// Original composition, synthesised at runtime: no samples, no files, nothing
// to license or ship. The brief was the arc of the 2026 line — fourteen games
// under, then the climb — so this is a half-time beat in C minor that starts as
// little more than a sub and a hat and adds a layer every time the story gains
// altitude. `setIntensity` is the single knob the chart drives.
export function createAudio(){
  let ac=null, master=null, comp=null, musicLP=null, drumBus=null, verb=null, wet=null;
  let on=true, started=false, playing=false, timer=null;
  let nextStep=0, step=0, intensity=0, target=0;

  const BPM=84, SPB=60/BPM, STEP=SPB/4;   // 16th-note grid, half-time feel
  const LEVEL=0.34;

  // i – VI – III – VII in C minor, one bar each. Roots sit low enough to read
  // as an 808 rather than a bass guitar.
  const CH=[
    {root:65.41,  pad:[261.63,311.13,392.00]},  // Cm : C4 Eb4 G4
    {root:51.91,  pad:[261.63,311.13,415.30]},  // Ab : C4 Eb4 Ab4
    {root:77.78,  pad:[233.08,311.13,392.00]},  // Eb : Bb3 Eb4 G4
    {root:58.27,  pad:[233.08,293.66,349.23]}   // Bb : Bb3 D4 F4
  ];
  // Riff, one entry per bar: [16th step, frequency]. C natural minor.
  const RIFF=[
    [[0,783.99],[3,932.33],[6,783.99],[10,622.25]],
    [[0,830.61],[4,783.99],[8,622.25]],
    [[0,932.33],[3,1046.50],[6,932.33],[10,783.99]],
    [[0,698.46],[4,783.99],[8,587.33]]
  ];
  const KICK=[0,7,10], KICK_EXTRA=[3];

  function makeIR(sec,decay){
    const n=Math.max(1,Math.floor(ac.sampleRate*sec)), b=ac.createBuffer(2,n,ac.sampleRate);
    for(let c=0;c<2;c++){ const d=b.getChannelData(c);
      for(let i=0;i<n;i++) d[i]=(Math.random()*2-1)*Math.pow(1-i/n,decay); }
    return b;
  }
  function ensure(){
    if(ac) return;
    ac=new (window.AudioContext||window.webkitAudioContext)();
    master=ac.createGain(); master.gain.value=0.0;
    // glue: keeps the 808 and the kick from fighting each other
    comp=ac.createDynamicsCompressor();
    comp.threshold.value=-16; comp.knee.value=24; comp.ratio.value=3.5;
    comp.attack.value=0.006; comp.release.value=0.18;
    // tonal parts sit behind a filter that opens as the story climbs; drums stay
    // out in front of it so the groove keeps its snap the whole way through
    musicLP=ac.createBiquadFilter(); musicLP.type='lowpass';
    musicLP.frequency.value=420; musicLP.Q.value=0.4;
    drumBus=ac.createGain(); drumBus.gain.value=1.0;
    verb=ac.createConvolver(); verb.buffer=makeIR(1.9,3.0);
    wet=ac.createGain(); wet.gain.value=0.34;
    musicLP.connect(comp); drumBus.connect(comp); verb.connect(wet); wet.connect(comp);
    comp.connect(master); master.connect(ac.destination);
  }
  const outDry=n=>n.connect(musicLP);
  const outWet=n=>{ n.connect(musicLP); n.connect(verb); };

  function noiseSrc(dur){
    const len=Math.max(1,Math.floor(ac.sampleRate*dur)), b=ac.createBuffer(1,len,ac.sampleRate), d=b.getChannelData(0);
    for(let i=0;i<len;i++) d[i]=Math.random()*2-1;
    const s=ac.createBufferSource(); s.buffer=b; return s;
  }

  // ---- drums ----
  function kick(t,pk){
    const o=ac.createOscillator(), g=ac.createGain();
    o.type='sine';
    o.frequency.setValueAtTime(128,t);
    o.frequency.exponentialRampToValueAtTime(42,t+0.09);
    g.gain.setValueAtTime(pk,t);
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.42);
    o.connect(g); g.connect(drumBus); o.start(t); o.stop(t+0.45);
    // click, so it still cuts through on a phone speaker
    const c=noiseSrc(0.02), cf=ac.createBiquadFilter(), cg=ac.createGain();
    cf.type='highpass'; cf.frequency.value=1600;
    cg.gain.setValueAtTime(pk*0.35,t); cg.gain.exponentialRampToValueAtTime(0.0001,t+0.02);
    c.connect(cf); cf.connect(cg); cg.connect(drumBus); c.start(t); c.stop(t+0.03);
  }
  function clap(t,pk){
    // three fast bursts read as a clap where one burst reads as noise
    [0,0.011,0.023].forEach((off,i)=>{
      const s=noiseSrc(0.14), f=ac.createBiquadFilter(), g=ac.createGain();
      f.type='bandpass'; f.frequency.value=1750; f.Q.value=1.1;
      const a=pk*(i===2?1:0.55);
      g.gain.setValueAtTime(0.0001,t+off);
      g.gain.linearRampToValueAtTime(a,t+off+0.003);
      g.gain.exponentialRampToValueAtTime(0.0001,t+off+(i===2?0.16:0.045));
      s.connect(f); f.connect(g); g.connect(drumBus); g.connect(verb);
      s.start(t+off); s.stop(t+off+0.18);
    });
  }
  function hat(t,pk,open){
    const dur=open?0.20:0.045;
    const s=noiseSrc(dur+0.02), f=ac.createBiquadFilter(), g=ac.createGain();
    f.type='highpass'; f.frequency.value=7800;
    g.gain.setValueAtTime(pk,t);
    g.gain.exponentialRampToValueAtTime(0.0001,t+dur);
    s.connect(f); f.connect(g); g.connect(drumBus); s.start(t); s.stop(t+dur+0.02);
  }

  // ---- tonal ----
  function sub(chord,t,dur,glideFrom){
    const o=ac.createOscillator(), g=ac.createGain();
    o.type='sine';
    if(glideFrom){ o.frequency.setValueAtTime(glideFrom,t);
                   o.frequency.exponentialRampToValueAtTime(chord.root,t+0.07); }
    else o.frequency.setValueAtTime(chord.root,t);
    g.gain.setValueAtTime(0.0001,t);
    g.gain.linearRampToValueAtTime(0.30,t+0.02);
    g.gain.setValueAtTime(0.30,t+dur*0.55);
    g.gain.exponentialRampToValueAtTime(0.0001,t+dur);
    o.connect(g); g.connect(drumBus);   // 808 belongs with the drums, not behind the filter
    o.start(t); o.stop(t+dur+0.05);
  }
  function pad(chord,t){
    const dur=SPB*4;
    chord.pad.forEach((f,idx)=>{
      const g=ac.createGain(); outWet(g);
      [-5,5].forEach(cent=>{
        const o=ac.createOscillator();
        o.type = idx===0?'triangle':'sine';
        o.frequency.value=f; o.detune.value=cent;
        o.connect(g); o.start(t); o.stop(t+dur+0.4);
      });
      const pk=0.042;
      g.gain.setValueAtTime(0.0001,t);
      g.gain.linearRampToValueAtTime(pk,t+0.6);
      g.gain.setValueAtTime(pk,t+dur*0.7);
      g.gain.linearRampToValueAtTime(0.0001,t+dur+0.3);
    });
  }
  function pluck(t,f,pk){
    const o=ac.createOscillator(), o2=ac.createOscillator(), g=ac.createGain();
    o.type='triangle'; o2.type='sine';
    o.frequency.value=f; o2.frequency.value=f*2; o2.detune.value=6;
    const g2=ac.createGain(); g2.gain.value=0.3; o2.connect(g2); g2.connect(g);
    o.connect(g); outWet(g);
    g.gain.setValueAtTime(0.0001,t);
    g.gain.exponentialRampToValueAtTime(pk,t+0.008);
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.5);
    o.start(t); o.stop(t+0.55); o2.start(t); o2.stop(t+0.55);
  }
  function bell(t,f,pk){
    const o=ac.createOscillator(), g=ac.createGain();
    o.type='sine'; o.frequency.value=f; outWet(g); o.connect(g);
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(pk,t+0.01);
    g.gain.exponentialRampToValueAtTime(0.0001,t+1.5);
    o.start(t); o.stop(t+1.6);
  }

  // ---- sequencer ----
  // Every layer is gated on intensity, so the beat literally builds as the
  // seasons stack up: sub and hat at the bottom, full kit by the finale.
  function schedule(){
    intensity += (target-intensity)*0.05;
    const I=intensity;
    musicLP.frequency.setTargetAtTime(420+I*3400, ac.currentTime, 0.25);
    wet.gain.setTargetAtTime(0.34-I*0.14, ac.currentTime, 0.3);

    while(nextStep<ac.currentTime+0.25){
      const t=nextStep, s=step%16, bar=Math.floor(step/16)%4, chord=CH[bar];

      if(s===0){ pad(chord,t); sub(chord,t,SPB*2.2, step?CH[(bar+3)%4].root:0); }
      if(s===8 && I>0.55) sub(chord,t,SPB*1.4,chord.root*1.5);

      if(KICK.includes(s)) kick(t,0.85);
      if(I>0.5 && KICK_EXTRA.includes(s)) kick(t,0.6);
      if(s===8) clap(t,0.34);
      if(s===8 && I>0.7) clap(t+STEP*0.5,0.10);

      // hats: 8ths, then 16ths, then rolls — the clearest signal of the climb
      const hatOn = (s%4===0) || (I>0.2 && s%2===0) || (I>0.45);
      if(hatOn) hat(t, 0.055+0.02*I, false);
      if(I>0.4 && s===14) hat(t,0.075,true);
      if(I>0.75 && s===15){        // 32nd roll into the bar line
        for(let k=0;k<4;k++) hat(t+STEP*k/4, 0.05+0.012*k, false);
      }

      if(I>0.3){
        const pk=0.05+0.05*I;
        RIFF[bar].forEach(n=>{ if(n[0]===s) pluck(t,n[1],pk); });
      }
      step++; nextStep+=STEP;
    }
  }

  function level(){ return on&&playing?LEVEL:0.0; }

  return {
    start(){
      ensure();
      if(ac.state==='suspended') ac.resume();
      playing=true;
      master.gain.cancelScheduledValues(ac.currentTime);
      master.gain.linearRampToValueAtTime(level(), ac.currentTime+0.9);
      if(!started){
        try{ const _b=ac.createBuffer(1,1,22050),_s=ac.createBufferSource(); _s.buffer=_b; _s.connect(ac.destination); _s.start(0); }catch(_e){}  // iOS: unlock audio inside the gesture
        started=true; nextStep=ac.currentTime+0.1; timer=setInterval(schedule,60);
      }
    },
    toggle(){
      on=!on;
      if(ac){ master.gain.cancelScheduledValues(ac.currentTime);
        master.gain.linearRampToValueAtTime(level(), ac.currentTime+0.4); }
      return on;
    },
    setIntensity(x){ target=Math.max(0,Math.min(1,x||0)); },
    pause(fade){ playing=false;
      if(ac){ master.gain.cancelScheduledValues(ac.currentTime);
        master.gain.linearRampToValueAtTime(0.0, ac.currentTime+(fade||0.5)); } },
    stinger(){ if(!ac||!on)return; const t=ac.currentTime+0.02;   // season change
      bell(t,1046.50,0.05); bell(t+0.16,1567.98,0.035);
      for(let k=0;k<6;k++) hat(t+0.055*k, 0.03+0.008*k, false);
      kick(t,0.7);
    },
    finale(){ if(!ac||!on)return; const t=ac.currentTime+0.03; target=1;   // Cm arrival
      [65.41,130.81,261.63,311.13,392.00,622.25].forEach(f=>{
        const o=ac.createOscillator(), o2=ac.createOscillator(), g=ac.createGain();
        o.type='triangle'; o2.type='sine'; o.frequency.value=f; o2.frequency.value=f; o2.detune.value=6;
        outWet(g); o.connect(g); o2.connect(g);
        g.gain.setValueAtTime(0.0001,t); g.gain.linearRampToValueAtTime(0.055,t+0.5);
        g.gain.linearRampToValueAtTime(0.0001,t+4.2);
        o.start(t); o.stop(t+4.4); o2.start(t); o2.stop(t+4.4);
      });
      kick(t,1.0);
      const drop=ac.createOscillator(), dg=ac.createGain();
      drop.type='sine';
      drop.frequency.setValueAtTime(98,t); drop.frequency.exponentialRampToValueAtTime(32.7,t+1.6);
      dg.gain.setValueAtTime(0.0001,t); dg.gain.linearRampToValueAtTime(0.34,t+0.05);
      dg.gain.exponentialRampToValueAtTime(0.0001,t+2.6);
      drop.connect(dg); dg.connect(drumBus); drop.start(t); drop.stop(t+2.7);
      bell(t+0.1,1046.50,0.06); bell(t+0.5,1567.98,0.04);
    }
  };
}
