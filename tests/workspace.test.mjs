import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { loadWorkspace, selectTarget, safePath } from '../tools/lib/workspace.mjs';
import { inspectTarget } from '../tools/lib/check.mjs';
import { run, requireSuccess, bootstrap, sha256 } from '../tools/lib/pakku.mjs';
import { inspectArchive } from '../tools/lib/build.mjs';
import { zipSync, strToU8 } from 'fflate';

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'DB 中文 空格-'));
  t.after(() => fs.rm(root, {recursive:true,force:true}));
  await fs.mkdir(path.join(root,'packs','测试 target'),{recursive:true});
  const target = {id:'example',path:'packs/测试 target',artifacts:['modrinth']};
  const save = async (file,value) => fs.writeFile(path.join(root,file),JSON.stringify(value));
  await save('workspace.json',{targets:[target]});
  await save(`${target.path}/pakku.json`,{name:'Example',version:'0.1.0'});
  await save(`${target.path}/pakku-lock.json`,{lockfile_version:2,target:'modrinth',mc_versions:['1.21.1'],loaders:{fabric:'0.16.14'}});
  return {root,target,save};
}
test('单目标、显式目标、本机优先级、共享默认与 UTF-8 路径',async t=>{
  const {root,target,save}=await fixture(t);
  const w=await loadWorkspace(root);
  assert.equal((await selectTarget(root,w)).id,'example');
  await assert.rejects(selectTarget(root,w,'missing'));
  await fs.mkdir(path.join(root,'packs','other'));
  w.targets.push({...target,id:'other',path:'packs/other'});
  await assert.rejects(selectTarget(root,w));
  w.defaultTarget='example';
  assert.equal((await selectTarget(root,w)).id,'example');
  await fs.mkdir(path.join(root,'.local'));
  await save('.local/selection.json',{target:'other'});
  assert.equal((await selectTarget(root,w)).id,'other');
  assert.equal((await selectTarget(root,w,'example')).id,'example');
});
test('Schema 拒绝重复、嵌套、缺失、越界与失效默认目标',async t=>{
  const {root,target,save}=await fixture(t);
  for(const value of [
    {targets:[target,target]}, {targets:[target],defaultTarget:'none'},
    {targets:[{...target,path:'../elsewhere'}]}, {targets:[{...target,path:'C:/Windows'}]},
    {targets:[{...target,path:'packs/missing'}]}, {targets:[{...target,artifacts:['modrinth','modrinth']}]},
    {targets:[{...target,path:'packs/测试 target/../other'}]},
    {targets:[{...target,mc:'1.21.1'}]},
  ]) {await save('workspace.json',value);await assert.rejects(loadWorkspace(root));}
});
test('junction/symlink 拒绝，包括缓存写入路径',async t=>{
  const {root}=await fixture(t);
  const external=await fs.mkdtemp(path.join(os.tmpdir(),'db-outside-'));
  t.after(()=>fs.rm(external,{recursive:true,force:true}));
  await fs.symlink(external,path.join(root,'.cache'),process.platform==='win32'?'junction':'dir');
  await assert.rejects(safePath(root,'.cache/tool.jar'),/junction/);
  await assert.rejects(safePath(path.join(root,'.cache'),'nested/tool.jar'),/junction/);
});
test('只读检查检测私密文件、输出冲突和无效 JSON',async t=>{
  const {root,target,save}=await fixture(t);
  await inspectTarget(root,target);
  await fs.writeFile(path.join(root,target.path,'options.txt'),'private');
  await assert.rejects(inspectTarget(root,target),/私密/);
  await fs.rm(path.join(root,target.path,'options.txt'));
  await save(`${target.path}/demo.json`,{safe:true});
  await save(`${target.path}/pakku.json`,{name:'Example',version:'1',overrides:['demo.json'],client_overrides:['demo.json']});
  await assert.rejects(inspectTarget(root,target),/冲突/);
  await fs.writeFile(path.join(root,target.path,'pakku.json'),'{');
  await assert.rejects(inspectTarget(root,target),SyntaxError);
});
test('spawn 保留参数和非零退出码，无 shell 插值',async()=>{
  const result=await run(process.execPath,['-e','console.log(process.argv[1]);process.exit(17)','中文 空格 & echo bad'],{capture:true});
  assert.equal(result.code,17);
  assert.match(result.stdout,/中文 空格 & echo bad/);
  assert.throws(()=>requireSuccess(result),e=>e.exitCode===17);
  await assert.rejects(run('db-missing-executable-123',[]));
});
test('bootstrap 哈希失败/网络失败无有效缓存，成功后复用',async t=>{
  const {root,save}=await fixture(t);
  const bytes=Buffer.from('test-tool');
  await save('toolchain.json',{pakku:{version:'1.5.0',url:'https://example.invalid/tool',sha256:sha256(bytes)}});
  await assert.rejects(bootstrap(root,async()=>new Response('bad')),/SHA/);
  await assert.rejects(bootstrap(root,async()=>{throw Error('offline')}),/offline/);
  assert.deepEqual(await fs.readdir(path.join(root,'.cache')),[]);
  await bootstrap(root,async()=>new Response(bytes));
  await bootstrap(root,async()=>{throw Error('must not download')});
});
test('ZIP 可读取性、索引与路径穿越检测',()=>{
  assert.throws(()=>inspectArchive(Buffer.from('broken'),'modrinth'));
  assert.throws(()=>inspectArchive(zipSync({'../escape':strToU8('x')}),'serverpack'),/路径/);
  assert.throws(()=>inspectArchive(zipSync({'modrinth.index.json':strToU8('{}')}),'modrinth'));
});
