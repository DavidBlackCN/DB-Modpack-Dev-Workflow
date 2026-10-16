import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {setup,save,snapshot} from './sync-fixture.mjs';
import {scanImportDependencies,importDependencies} from '../tools/lib/import-dependencies.mjs';
import {acceptDependencies} from '../tools/lib/dependencies.mjs';
import {digest} from '../tools/lib/prepare.mjs';
import {atomicJson} from '../tools/lib/runtime-fs.mjs';

const bytes=Buffer.from('fixture-known-mod-not-executable');
const project={pakku_id:'fixture',type:'MOD',slug:{modrinth:'fixture-mod'},name:{modrinth:'Fixture Mod'},id:{modrinth:'fixture-id'},files:[{type:'modrinth',file_name:'fixture.jar',hashes:{sha1:digest(bytes,'sha1'),sha512:digest(bytes,'sha512')}}]};
const execute=async(_java,args,{cwd})=>{
  if(args.includes('sync')) {
    assert.deepEqual(args.slice(-3),['--yes','sync','--additions']);
    const staged=await fs.readFile(path.join(cwd,'mods/import.jar'));
    const config=JSON.parse(await fs.readFile(path.join(cwd,'pakku.json')));await fs.writeFile(path.join(cwd,'pakku.json'),JSON.stringify(Object.fromEntries(Object.entries(config).reverse())));
    if(staged.equals(bytes)) {
      const lock=JSON.parse(await fs.readFile(path.join(cwd,'pakku-lock.json')));
      lock.projects=[...(lock.projects??[]),project];await atomicJson(path.join(cwd,'pakku-lock.json'),lock);
    }
  }else assert.equal(args.at(-1),'ls');
  return {code:0,stdout:'Projects total: 1',stderr:''};
};
async function ready(t) {
  const f=await setup(t);await save(path.join(f.gameDir,'mods/new.jar'),bytes);
  const scan=await scanImportDependencies(f.root,f.runtime,f.target);
  return {...f,selection:{file:'mods/new.jar',sha256:scan.candidates[0].hash,execute}};
}
const review=f=>importDependencies(f.root,f.runtime,f.target,f.selection);
const accept=(f,c,extra={})=>importDependencies(f.root,f.runtime,f.target,{candidate:c.id,acceptHash:c.hash,confirm:true,execute,...extra});

test('Import 扫描只读，按锁文件哈希识别已管理 JAR，跳过禁用和嵌套文件',async t=>{
  const f=await ready(t);
  await save(path.join(f.gameDir,'mods/off.jar.disabled'),bytes);await save(path.join(f.gameDir,'mods/sub/nested.jar'),bytes);
  const lockFile=path.join(f.root,f.target.path,'pakku-lock.json'),lock=JSON.parse(await fs.readFile(lockFile));
  lock.projects=[project];await atomicJson(lockFile,lock);
  const before=await snapshot(f.base),scan=await scanImportDependencies(f.root,f.runtime,f.target);
  assert.equal(scan.candidates.length,0);assert.equal(scan.skipped.length,3);assert.deepEqual(await snapshot(f.base),before);
});

test('Import 只在确认后接受 Pakku 候选，不复制 JAR；结果可以由 Git 检查',async t=>{
  const f=await ready(t),sourceBefore=await snapshot(path.join(f.root,'packs')),runtimeBefore=await snapshot(f.gameDir);
  await assert.rejects(importDependencies(f.root,f.runtime,f.target,{...f.selection,sha256:'0'.repeat(64)}),/扫描哈希/);
  await assert.rejects(importDependencies(f.root,f.runtime,f.target,{...f.selection,confirm:true}),/先生成/);
  const c=await review(f);assert.equal(c.project,'fixture-mod');assert.equal(c.added.length,1);
  assert.deepEqual(await snapshot(path.join(f.root,'packs')),sourceBefore);
  assert.ok(!(await snapshot(path.join(f.root,c.projectPath)))['mods/import.jar']);
  await assert.rejects(accept(f,c,{confirm:false}),/confirm/);
  await assert.rejects(accept(f,c,{acceptHash:'0'.repeat(64)}),/哈希/);
  await accept(f,c);
  const after=await snapshot(path.join(f.root,'packs'));
  assert.deepEqual(Object.keys(after),Object.keys(sourceBefore));
  assert.deepEqual(Object.keys(after).filter(n=>after[n]!==sourceBefore[n]),['example/pakku-lock.json']);
  assert.deepEqual(await snapshot(f.gameDir),runtimeBefore);
  assert.equal((await scanImportDependencies(f.root,f.runtime,f.target)).candidates.length,0);
});

test('Import 拒绝未知 JAR、原生工具失败和对已有依赖的修改',async t=>{
  const f=await ready(t),before=await snapshot(path.join(f.root,'packs'));
  await save(path.join(f.gameDir,'mods/unknown.jar'),'unknown');
  await assert.rejects(importDependencies(f.root,f.runtime,f.target,{file:'mods/unknown.jar',sha256:digest(Buffer.from('unknown')),execute}),/未唯一识别/);
  await assert.rejects(importDependencies(f.root,f.runtime,f.target,{...f.selection,execute:async()=>({code:1,stderr:'network failed'})}),/network failed/);
  const lockFile=path.join(f.root,f.target.path,'pakku-lock.json'),lock=JSON.parse(await fs.readFile(lockFile));
  lock.projects=[{...project,pakku_id:'old',files:[],slug:{modrinth:'old'}}];await atomicJson(lockFile,lock);
  await assert.rejects(importDependencies(f.root,f.runtime,f.target,{...f.selection,execute:async(java,args,options)=>{
    const result=await execute(java,args,options);if(args.includes('sync')){const p=path.join(options.cwd,'pakku-lock.json'),l=JSON.parse(await fs.readFile(p));l.projects.shift();await atomicJson(p,l);}return result;
  }}),/现有依赖/);
  assert.equal(JSON.parse(await fs.readFile(lockFile)).projects.length,1);
  assert.equal((await snapshot(f.gameDir))['mods/new.jar'],digest(bytes));
  assert.ok(before['example/pakku-lock.json']);
});

test('Import 候选在源、Runtime JAR、绑定或候选哈希变化后失效',async t=>{
  for(const mutation of ['source','jar','binding','candidate']) {
    const f=await ready(t),c=await review(f);
    if(mutation==='source')await f.change('source changed');
    if(mutation==='jar')await save(path.join(f.gameDir,'mods/new.jar'),'changed');
    if(mutation==='binding')await atomicJson(path.join(f.root,'.local/runtimes.json'),{schema:1,bindings:[]});
    if(mutation==='candidate')await fs.appendFile(path.join(f.root,c.projectPath,'pakku-lock.json'),' ');
    const before=await snapshot(path.join(f.root,'packs'));
    await assert.rejects(accept(f,c));
    // The legacy accept command also enforces the import-source guard.
    await assert.rejects(acceptDependencies(f.root,f.target,{candidate:c.id,acceptHash:c.hash,confirm:true,execute}));
    assert.deepEqual(await snapshot(path.join(f.root,'packs')),before);
  }
});
