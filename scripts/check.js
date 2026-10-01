'use strict';
const fs=require('node:fs');const path=require('node:path');const cp=require('node:child_process');
const root=path.join(__dirname,'..');
for(const file of ['server.js','script.js','upgrade.js','register-sw.js','sw.js','lib/validation.js','scripts/check.js','tests/validation.test.js','tests/integration.test.js']){const r=cp.spawnSync(process.execPath,['--check',path.join(root,file)],{stdio:'inherit'});if(r.status)process.exit(r.status||1);}
for(const file of ['package.json','package-lock.json','vercel.json','manifest.webmanifest'])JSON.parse(fs.readFileSync(path.join(root,file),'utf8'));
if(/localStorage|SERVICE_ROLE_KEY/.test(fs.readFileSync(path.join(root,'script.js'),'utf8')+fs.readFileSync(path.join(root,'upgrade.js'),'utf8')))throw new Error('browser security regression');
console.log('Syntax, JSON and frontend secret guards passed. Not a browser or Supabase integration test.');
