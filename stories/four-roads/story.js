// Story: Four Roads, One Record.
// Presentation config (colors, arc labels, narrative beats) + data wiring.
//
// Every beat below states something the data can be checked against — run
// `python3 scripts/story_facts.py` after a data refresh and make sure the peaks,
// valleys, streaks and records still say what these lines claim.
import { initStory } from '../../src/chart.js';

const CONFIG = {
  2023:{color:'#38bdf8',label:'The Grind',beats:[
    {g:0,t:'2023 · The steady climb begins.'},
    {g:13,t:'Two weeks in — three games under. A soft open.'},
    {g:35,t:'An 8-game winning streak lifts them to +7.'},
    {g:103,t:'Cresting at +9 — the season high.'},
    {g:108,t:'Checkpoint: 57–51. No drama — just a grind.'},
    {g:159,t:'The floor gives way: seven under, the season low.'},
    {g:162,t:'Fade to 78–84. Last place in the AL East.'}]},
  2024:{color:'#f7b500',label:'The Flatline',beats:[
    {g:0,t:'2024 · Life on the .500 tightrope.'},
    {g:46,t:'The season low is just two games under. That is the whole drama.'},
    {g:96,t:'A late surge to +10 — the high-water mark.'},
    {g:108,t:'Checkpoint: 57–51. The exact same number, again.'},
    {g:140,t:'A five-game slide erases the cushion.'},
    {g:162,t:'Dead even: 81–81.'}]},
  2025:{color:'#ab8bff',label:'The Bounce-Back',beats:[
    {g:0,t:'2025 · The best of the four — it just hid it early.'},
    {g:63,t:'Season low: five games under, and sinking.'},
    {g:83,t:'A six-game skid — the worst stretch of the year.'},
    {g:98,t:'The answer: ten wins in a row.'},
    {g:108,t:'Checkpoint: 57–51 too.'},
    {g:140,t:'+16 — the season high, and clear of the pack.'},
    {g:162,t:'89–73. A Wild Card berth.'}]},
  2026:{color:'#ff3b47',label:'The Rollercoaster',beats:[
    {g:0,t:'2026 · Buckle up.'},
    {g:6,t:'Five straight losses out of the gate.'},
    {g:72,t:'Rock bottom — FOURTEEN games under .500.'},
    {g:95,t:'Then the turn: ten wins in a row.'},
    {g:108,t:'Checkpoint: 57–51 — the same number, a fourth straight year.'}]}
};
const YEARS = [2023, 2024, 2025, 2026];

const DATA = await fetch('../../data/seasons.json').then(r => r.json());

// The live season's closing beat has to come from the data, not from a hardcoded
// string — the daily refresh moves it, and a stale record on screen is exactly the
// kind of quiet wrongness this project is trying to avoid.
for (const year of YEARS) {
  const season = DATA[String(year)];
  if (!season?.in_progress) continue;
  CONFIG[year].beats.push({
    g: season.end_game,
    t: `Still being written: ${season.record.replace('-', '–')} through ${season.end_game} games.`,
  });
}

initStory({ DATA, CONFIG, YEARS });
