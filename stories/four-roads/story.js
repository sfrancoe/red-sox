// Story: Four Roads, One Record.
// Presentation config (colors, arc labels, narrative beats) + data wiring.
import { initStory } from '../../src/chart.js';

const CONFIG = {
  2023:{color:'#38bdf8',label:'The Grind',beats:[
    {g:0,t:'2023 · The steady climb begins.'},
    {g:35,t:'An 8-game winning streak flips them over the line for good.'},
    {g:103,t:'Cresting at +9 — the season high.'},
    {g:108,t:'Checkpoint: 57\u201351. No drama — just a grind.'},
    {g:132,t:'The grind turns to grind-down — back under .500.'},
    {g:162,t:'Fade to 78\u201384. Last place in the AL East.'}]},
  2024:{color:'#f7b500',label:'The Flatline',beats:[
    {g:0,t:'2024 · Life on the .500 tightrope.'},
    {g:96,t:'A late surge to +10 — the high-water mark.'},
    {g:108,t:'Checkpoint: 57\u201351. The exact same number, again.'},
    {g:135,t:'August sags (13\u201316); the tightrope dips.'},
    {g:162,t:'Dead even: 81\u201381.'}]},
  2025:{color:'#ab8bff',label:'The Bounce-Back',beats:[
    {g:0,t:'2025 · The best of the four — it just hid it early.'},
    {g:63,t:'Mid-June: five games under, sinking.'},
    {g:98,t:'The answer: ten wins in a row.'},
    {g:108,t:'Checkpoint: 57\u201351 too.'},
    {g:140,t:'The surge holds — pulling clear of the pack.'},
    {g:162,t:'89\u201373. A Wild Card berth — first October since 2021.'}]},
  2026:{color:'#ff3b47',label:'The Rollercoaster',beats:[
    {g:0,t:'2026 · Buckle up.'},
    {g:72,t:'Rock bottom — FOURTEEN games under .500.'},
    {g:100,t:'Then history: 15 straight, tying the 1946 franchise record.'},
    {g:108,t:'Checkpoint: 57\u201351 — right back to where 2023 finished.'},
    {g:113,t:'Still red-hot: 62\u201351 and counting. This road is still being written.'}]}
};
const YEARS = [2023, 2024, 2025, 2026];

const DATA = await fetch('../../data/seasons.json').then(r => r.json());
initStory({ DATA, CONFIG, YEARS });
