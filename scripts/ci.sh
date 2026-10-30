#!/usr/bin/env bash
# Source syntax, extension resource closure and user-visible grading fixtures.
# No browser profile, extension installation, website scan or store publication.
set -euo pipefail
cd "$(dirname "$0")/.."
bun - <<'JSCI'
import {readFileSync,existsSync,realpathSync} from 'node:fs';
import {resolve,dirname,sep} from 'node:path';
import {execFileSync} from 'node:child_process';
import vm from 'node:vm';
const root=realpathSync('.');
const files=execFileSync('git',['ls-files','-z'],{encoding:'utf8'}).split('\0').filter(Boolean);
let parsed=0, references=0;
for(const path of files.filter(x=>x.endsWith('.js'))){
  new Bun.Transpiler({loader:'js',target:'browser'}).transformSync(readFileSync(path,'utf8'));
  parsed++;
}
if(!parsed) throw new Error('No JavaScript validated');
function resource(path,base='.'){
  if(typeof path!=='string' || !path || /^[a-z]+:/i.test(path) || path.startsWith('//')) throw new Error(`Expected local extension resource: ${path}`);
  const full=resolve(base,path.split(/[?#]/,1)[0]);
  if(!full.startsWith(root+sep) || !existsSync(full) || !realpathSync(full).startsWith(root+sep)) throw new Error(`Missing/escaping extension resource: ${path}`);
  references++;
}
const m=JSON.parse(readFileSync('manifest.json','utf8'));
if(m.manifest_version!==3 || !m.name || !/^\d+(\.\d+){0,3}$/.test(m.version)) throw new Error('Invalid Manifest V3 identity');
if(m.background?.service_worker) resource(m.background.service_worker);
for(const path of m.background?.scripts??[]) resource(path);
for(const path of Object.values(m.icons??{})) resource(path);
const actionIcons=m.action?.default_icon;
for(const path of typeof actionIcons==='string'?[actionIcons]:Object.values(actionIcons??{})) resource(path);
if(m.action?.default_popup) resource(m.action.default_popup);
for(const entry of m.content_scripts??[]) for(const path of [...(entry.js??[]),...(entry.css??[])]) resource(path);
for(const path of files.filter(x=>x.endsWith('.html'))){
  const html=readFileSync(path,'utf8');
  for(const match of html.matchAll(/\b(?:src|href)\s*=\s*["']([^"']+)["']/gi)){
    if(/^(?:[a-z]+:|\/\/|#)/i.test(match[1])) continue;
    resource(match[1],dirname(path));
  }
}
const context=vm.createContext({});
vm.runInContext(readFileSync('analyzers/grading.js','utf8'),context,{timeout:1000});
const grade=vm.runInContext('calculateGradePlusMinus',context,{timeout:1000});
for(const [score,max,want] of [[0,0,'?'],[0,100,'F'],[59,100,'F'],[60,100,'D-'],[70,100,'C-'],[80,100,'B-'],[90,100,'A-'],[93,100,'A'],[97,100,'A+'],[100,100,'A+']]){
  if(grade(score,max)!==want) throw new Error(`Grading contract failed: ${score}/${max}`);
}
console.log(`Validated ${parsed} JavaScript sources, ${references} local extension references and 10 grading fixtures.`);
JSCI
