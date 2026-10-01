'use strict';
// A dedicated disposable Preview project only. Never production.
const test=require('node:test');const assert=require('node:assert/strict');
const BASE=process.env.TEST_SITE_URL;const enabled=process.env.RUN_INTEGRATION==='1'&&BASE;
class Client{constructor(){this.cookies=new Map();}async call(url,method='GET',body){const r=await fetch(BASE+url,{method,headers:{Origin:BASE,'Content-Type':'application/json',Cookie:[...this.cookies].map(([k,v])=>k+'='+v).join(';')},body:body?JSON.stringify(body):undefined});for(const raw of r.headers.getSetCookie()){const [k,v]=raw.split(';')[0].split('=');this.cookies.set(k,v);}let data;try{data=await r.json();}catch{data={};}return {status:r.status,data};}async login(email,pass){const r=await this.call('/api/login','POST',{email,pass});assert.equal(r.status,200);return r.data.user;}}
test('Auth + A/B ownership + promotion cannot reset + messages private',{skip:!enabled},async()=>{
 const a=new Client(),b=new Client(),anon=new Client();await a.login(process.env.TEST_A_EMAIL,process.env.TEST_A_PASSWORD);const bu=await b.login(process.env.TEST_B_EMAIL,process.env.TEST_B_PASSWORD);
 const payload={title:'اختبار تكامل مؤقت',desc:'سيتم حذف هذا الإعلان بعد الاختبار',cat:'other',city:'بغداد',price:1,featured:true};const r1=await a.call('/api/listings','POST',payload);assert.equal(r1.status,201);const id=r1.data.listing.id;
 try{assert.equal((await b.call('/api/listings/'+id,'PUT',payload)).status,403);assert.equal((await b.call('/api/listings/'+id,'DELETE')).status,403);assert.equal((await anon.call('/api/admin/data')).status,403);const r2=await a.call('/api/listings','POST',payload);assert.equal(r2.status,201);assert.equal(r2.data.listing.featured,false);await a.call('/api/listings/'+r2.data.listing.id,'DELETE');await a.call('/api/messages','POST',{to:bu.id,text:'اختبار الخصوصية',listingId:id});assert.equal((await anon.call('/api/me/state')).status,401);}
 finally{await a.call('/api/listings/'+id,'DELETE');}
 const third=await a.call('/api/listings','POST',payload);assert.equal(third.status,201);assert.equal(third.data.listing.featured,false);await a.call('/api/listings/'+third.data.listing.id,'DELETE');assert.equal((await a.call('/api/logout','POST',{})).status,200);assert.equal((await a.call('/api/me')).status,401);
});
