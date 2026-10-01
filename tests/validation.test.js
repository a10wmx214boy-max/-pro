'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const V=require('../lib/validation');
test('safe HTTPS only',()=>{assert.equal(V.safeUrl('https://t.me/HarryScloser6'),'https://t.me/HarryScloser6');for(const x of ['javascript:alert(1)','http://example.com','https://localhost/x','https://user:pass@example.com','https://127.0.0.1'])assert.throws(()=>V.safeUrl(x));});
test('UUID rejects PostgREST injection',()=>{assert.throws(()=>V.uuid('x&user_id=eq.other'));assert.equal(V.uuid('d0fb4c4e-607b-41da-8e49-ed1e34af3f75'),'d0fb4c4e-607b-41da-8e49-ed1e34af3f75');});
test('magic bytes required',()=>{assert.equal(V.mediaMime(Buffer.from('<svg onload="evil">')),'');assert.equal(V.mediaMime(Buffer.from('not an image file')),'');assert.equal(V.mediaMime(Buffer.from([255,216,255,0,0,0,0,0,0,0,0,0])),'image/jpeg');});
test('mass assignment rejected by allowlist',()=>{const r=V.listing({title:'منتج صالح',desc:'تفاصيل المنتج',cat:'other',city:'بغداد',price:50,user_id:'victim',featured:true,pinned:true,views:999999});assert.equal(r.featured,undefined);assert.equal(r.user_id,undefined);assert.equal(r.views,undefined);});
test('invalid prices rejected',()=>{for(const p of ['Infinity',-1,'not-number'])assert.throws(()=>V.listing({title:'abc',desc:'abc',cat:'other',city:'بغداد',price:p}));});
