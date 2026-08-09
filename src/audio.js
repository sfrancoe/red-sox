// Audio engine — Web Audio cinematic swell; intensity builds with the story.
// Extracted from the original single-file build; behaviour unchanged.
export function createAudio(){
  let ac=null, master=null, lp=null, verb=null, wet=null;
  let on=true, started=false, timer=null;
  let nextBeat=0, beat=0, intensity=0, target=0;
  const BPM=68, SPB=60/BPM;                 // slow, cinematic
  // Am – F – C – G, voiced for smooth voice-leading (one bar each)
  const CH=[
    {bass:55.00, pad:[220.00,261.63,329.63]},  // Am : A3 C4 E4
    {bass:43.65, pad:[220.00,261.63,349.23]},  // F  : A3 C4 F4
    {bass:65.41, pad:[196.00,261.63,329.63]},  // C  : G3 C4 E4
    {bass:49.00, pad:[196.00,246.94,293.66]}   // G  : G3 B3 D4
  ];
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
    lp=ac.createBiquadFilter(); lp.type='lowpass'; lp.frequency.value=520; lp.Q.value=0.3;
    verb=ac.createConvolver(); verb.buffer=makeIR(2.8,2.3);
    wet=ac.createGain(); wet.gain.value=0.7;
    lp.connect(master); verb.connect(wet); wet.connect(master); master.connect(ac.destination);
  }
  const outDry=n=>{ n.connect(lp); };
  const outWet=n=>{ n.connect(lp); n.connect(verb); };
  function padChord(chord,t){
    const dur=SPB*4;
    chord.pad.forEach((f,idx)=>{
      const g=ac.createGain(); outWet(g);
      [-4,4].forEach(cent=>{                      // two lightly-detuned voices per note
        const o=ac.createOscillator();
        o.type = idx===0?'triangle':'sine';
        o.frequency.value=f; o.detune.value=cent;
        o.connect(g); o.start(t); o.stop(t+dur+0.5);
      });
      const pk=0.055;
      g.gain.setValueAtTime(0.0001,t);
      g.gain.linearRampToValueAtTime(pk,t+1.0);
      g.gain.setValueAtTime(pk,t+dur*0.66);
      g.gain.linearRampToValueAtTime(0.0001,t+dur+0.4);
    });
    const sh=0.028*intensity;                     // high shimmer grows with the story
    if(sh>0.004) chord.pad.forEach(f=>{
      const o=ac.createOscillator(), g=ac.createGain();
      o.type='sine'; o.frequency.value=f*2; outWet(g); o.connect(g);
      g.gain.setValueAtTime(0.0001,t); g.gain.linearRampToValueAtTime(sh,t+1.3);
      g.gain.linearRampToValueAtTime(0.0001,t+dur);
      o.start(t); o.stop(t+dur+0.2);
    });
  }
  function bassNote(chord,t){
    const dur=SPB*4;
    [[chord.bass,0.12],[chord.bass*2,0.05]].forEach(pair=>{
      const o=ac.createOscillator(), g=ac.createGain();
      o.type='sine'; o.frequency.value=pair[0]; outDry(g); o.connect(g);
      g.gain.setValueAtTime(0.0001,t); g.gain.linearRampToValueAtTime(pair[1],t+0.5);
      g.gain.setValueAtTime(pair[1],t+dur*0.7); g.gain.linearRampToValueAtTime(0.0001,t+dur+0.15);
      o.start(t); o.stop(t+dur+0.2);
    });
  }
  function subPulse(t,pk){
    const o=ac.createOscillator(), g=ac.createGain();
    o.type='sine'; o.frequency.setValueAtTime(72,t); o.frequency.exponentialRampToValueAtTime(40,t+0.28);
    g.gain.setValueAtTime(pk,t); g.gain.exponentialRampToValueAtTime(0.0001,t+0.55);
    o.connect(g); g.connect(master); o.start(t); o.stop(t+0.6);
  }
  function noiseSrc(dur){
    const len=Math.max(1,Math.floor(ac.sampleRate*dur)), b=ac.createBuffer(1,len,ac.sampleRate), d=b.getChannelData(0);
    for(let i=0;i<len;i++) d[i]=Math.random()*2-1;
    const s=ac.createBufferSource(); s.buffer=b; return s;
  }
  function brush(t,pk){
    const s=noiseSrc(0.2), f=ac.createBiquadFilter(), g=ac.createGain();
    f.type='bandpass'; f.frequency.value=5400; f.Q.value=0.7;
    g.gain.setValueAtTime(0.0001,t); g.gain.linearRampToValueAtTime(pk,t+0.02); g.gain.exponentialRampToValueAtTime(0.0001,t+0.2);
    s.connect(f); f.connect(g); g.connect(lp); g.connect(verb); s.start(t); s.stop(t+0.24);
  }
  function bell(t,f,pk){
    const o=ac.createOscillator(), g=ac.createGain();
    o.type='sine'; o.frequency.value=f; outWet(g); o.connect(g);
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(pk,t+0.012);
    g.gain.exponentialRampToValueAtTime(0.0001,t+1.7);
    o.start(t); o.stop(t+1.8);
  }
  function schedule(){
    intensity += (target-intensity)*0.05;         // ease toward the story's intensity
    lp.frequency.setTargetAtTime(480+intensity*3200, ac.currentTime, 0.25);
    while(nextBeat<ac.currentTime+0.2){
      const t=nextBeat, bar=Math.floor(beat/4)%4, chord=CH[bar], b=beat%4;
      if(b===0){ padChord(chord,t); bassNote(chord,t); subPulse(t,0.5); }
      if(b===2){ subPulse(t,0.3); }
      if((b===1||b===3) && intensity>0.5) brush(t,0.018+0.02*intensity);
      beat++; nextBeat+=SPB;
    }
  }
  return {
    start(){
      ensure();
      if(ac.state==='suspended') ac.resume();
      master.gain.cancelScheduledValues(ac.currentTime);
      master.gain.linearRampToValueAtTime(on?0.30:0.0, ac.currentTime+1.4);   // soft fade-in
      if(!started){
        try{ const _b=ac.createBuffer(1,1,22050),_s=ac.createBufferSource(); _s.buffer=_b; _s.connect(ac.destination); _s.start(0); }catch(_e){}  // iOS: unlock audio inside the gesture
        started=true; nextBeat=ac.currentTime+0.1; timer=setInterval(schedule,60);
      }
    },
    toggle(){
      on=!on;
      if(ac){ master.gain.cancelScheduledValues(ac.currentTime);
        master.gain.linearRampToValueAtTime(on&&playing?0.30:0.0, ac.currentTime+0.4); }
      return on;
    },
    setIntensity(x){ target=Math.max(0,Math.min(1,x||0)); },
    pause(fade){ if(ac){ master.gain.cancelScheduledValues(ac.currentTime);
      master.gain.linearRampToValueAtTime(0.0, ac.currentTime+(fade||0.5)); } },
    stinger(){ if(!ac||!on)return; const t=ac.currentTime+0.02;   // season change: rising sweep + soft bells
      bell(t,523.25,0.05); bell(t+0.18,783.99,0.04);
      const s=noiseSrc(1.2), f=ac.createBiquadFilter(), g=ac.createGain();
      f.type='bandpass'; f.Q.value=1.1;
      f.frequency.setValueAtTime(300,t); f.frequency.exponentialRampToValueAtTime(4200,t+1.1);
      g.gain.setValueAtTime(0.0001,t); g.gain.linearRampToValueAtTime(0.05,t+0.85); g.gain.linearRampToValueAtTime(0.0001,t+1.2);
      s.connect(f); f.connect(g); g.connect(verb); g.connect(lp); s.start(t); s.stop(t+1.25);
    },
    finale(){ if(!ac||!on)return; const t=ac.currentTime+0.03; target=1;   // warm C-major arrival
      [130.81,196.00,261.63,329.63,392.00].forEach(f=>{
        const o=ac.createOscillator(), o2=ac.createOscillator(), g=ac.createGain();
        o.type='triangle'; o2.type='sine'; o.frequency.value=f; o2.frequency.value=f; o2.detune.value=5;
        outWet(g); o.connect(g); o2.connect(g);
        g.gain.setValueAtTime(0.0001,t); g.gain.linearRampToValueAtTime(0.06,t+0.7);
        g.gain.linearRampToValueAtTime(0.0001,t+4.4);
        o.start(t); o.stop(t+4.6); o2.start(t); o2.stop(t+4.6);
      });
      bell(t+0.1,1046.50,0.06); bell(t+0.55,1567.98,0.04);
      subPulse(t,0.6);
    }
  };
}
