import assert from 'node:assert/strict';
import handler, { normalizeKalshi, normalizePoly, cleanHistory, number } from '../netlify/functions/redsox-markets.mjs';
const now = new Date('2026-09-04T20:00:00Z');
const k = { status: 'active', event_ticker: 'KXMLBGAME-26SEP041905BOSBAL', ticker: 'KXMLBGAME-26SEP041905BOSBAL-BOS', yes_bid_dollars: '0.51', yes_ask_dollars: '0.53', title: 'Boston wins', volume_24h_fp: '123' };
assert.equal(normalizeKalshi(k,now).probability, .52);
assert.equal(normalizeKalshi({...k,yes_bid_dollars:null},now).probability, null);
assert.equal(normalizeKalshi({...k,yes_bid_dollars:'0',yes_ask_dollars:'1'},now).probability,null);
assert.equal(normalizeKalshi({...k,yes_bid_dollars:'.8'},now).probability,null);
assert.equal(normalizeKalshi({...k,status:'settled'},now),null);
assert.equal(normalizeKalshi({...k,ticker:k.ticker.replace(/BOS$/, 'BAL')},now),null);
assert.equal(number(''),null);
const e = {slug:'mlb-bal-bos-2026-09-04',title:'Baltimore vs Boston'};
const m = {id:'1',active:true,closed:false,sportsMarketType:'moneyline',question:'Baltimore vs Boston',outcomes:'["Baltimore Orioles","Boston Red Sox"]',outcomePrices:'["0.48","0.52"]',clobTokenIds:'["10","11"]',bestBid:.47,bestAsk:.49};
const p = normalizePoly(e,m);
assert.equal(p.probability,.52);assert.equal(p.historyId,'11');assert.equal(p.bid,.51);assert.equal(p.ask,.53);
assert.equal(p.matchKey,normalizeKalshi(k,now).matchKey);
assert.equal(normalizePoly({...e,slug:'mlb-nyy-bal-2026-09-04'},m),null);
assert.equal(normalizePoly(e,{...m,closed:true}),null);
assert.deepEqual(cleanHistory([{t:10,p:.5},{t:10,p:.6},{t:9,p:.4},{t:11,p:null},{t:12,p:2},{t:30,p:.4}],9,20),[{t:9,p:.4},{t:10,p:.6}]);
// Verify partial and total outages using fixture responses, without live API calls.
const originalFetch = globalThis.fetch;
try {
 globalThis.fetch = async url => {
   if(String(url).includes('kalshi')) throw new Error('Unavailable');
   return Response.json({events:[{...e,markets:[m]}]});
 };
 let r=await handler(new Request('https://test/api/redsox-markets'));let data=await r.json();
 assert.equal(r.status,200);assert.equal(data.sources[0].available,false);assert.equal(data.sources[1].available,true);
 globalThis.fetch=async()=>{throw new Error('Unavailable');};
 r=await handler(new Request('https://test/api/redsox-markets'));assert.equal(r.status,502);assert.equal(r.headers.get('Cache-Control'),'no-store');
} finally {globalThis.fetch=originalFetch;}
console.log('Market normalization, team isolation, outcome inversion, history, and outages: OK');
