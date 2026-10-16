import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn,spawnSync} from 'node:child_process';

const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const probe=spawnSync('pwsh',['-NoProfile','-Command',"if ($PSVersionTable.PSVersion -lt [version]'7.3') { exit 1 }; (Get-Process -Id $PID).Path"],{encoding:'utf8'});
const pwsh=probe.status===0?probe.stdout.trim():null;
const psQuote=value=>`'${value.replaceAll("'","''")}'`;
const mock=String.raw`
import fs from 'node:fs';
const args=process.argv.slice(2), command=args[0]==='--silent'?args[4]:null;
fs.appendFileSync(process.env.MENU_LOG,JSON.stringify(args)+'\n');
const spec=JSON.parse(fs.readFileSync(process.env.MENU_SPEC));
const out=x=>console.log(JSON.stringify(x,null,2));
const id=args[5];
if(command===spec.fail){console.error('fixture failure');process.exit(37);}
switch(command){
case 'status':out({selected:spec.selected,gitDirty:true,runtimes:[],targets:spec.targets.map(id=>({id})),bindings:spec.bindings});break;
case 'targets':out(spec.targets.map(id=>({id,path:'packs/'+id,artifacts:['modrinth']})));break;
case 'runtimes':out({bindings:spec.bindings});break;
case 'use':spec.selected=id;fs.writeFileSync(process.env.MENU_SPEC,JSON.stringify(spec));out({selected:id});break;
case 'dev':case 'deploy':case 'restore-deps':out({actions:[{type:'delete',path:'config/old.json'}],conflicts:[]});break;
case 'apply':out({action:'apply',target:spec.selected,version:'0.1.0',git:'a'.repeat(40),provenance:{kind:'file',packageHash:'b'.repeat(64)}});out({actions:[{type:'update',path:'config/a.json'}],conflicts:[]});break;
case 'collect':case 'changes':out({managed:[{path:'config/a.json',state:spec.conflict?'conflict':'runtime-only',source:'config/a.json',runtime:spec.deleted?null:'hash',diff:{text:'--- source\n+++ runtime\n-old\n+new'}}],candidates:[{path:'config/new.json',state:'candidate',diff:{text:'+new config'}}],dependencies:[],conflicts:[]});break;
case 'deps-review':out({id:'candidate-id',hash:'c'.repeat(64),operation:'add',project:'sodium',projectPath:'.work/candidate',diff:{text:'-old\n+new'}});break;
case 'bind':out({action:'bind',runtime:{id,launcher:'hmcl',targetId:spec.selected,mc:'1.21.1',loaders:{fabric:'0.16.14'},gameDir:args[args.indexOf('--game-dir')+1],versionDir:'version',layout:'isolated'},existing:[]});break;
case 'build':out({target:args[args.indexOf('--target')+1],output:'dist/output',artifacts:[{kind:'modrinth',name:'example.mrpack'}]});break;
default:out({received:args});
}
`;
async function fixture(t,override={}) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'DB 菜单 空格-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  await fs.copyFile(path.join(repo,'ci.ps1'),path.join(root,'ci.ps1'));
  const bin=path.join(root,'bin');await fs.mkdir(bin);
  await fs.writeFile(path.join(root,'mock.mjs'),mock);
  await fs.writeFile(path.join(bin,'pnpm.ps1'),`& ${psQuote(process.execPath)} ${psQuote(path.join(root,'mock.mjs'))} @args\nexit $LASTEXITCODE\n`);
  await fs.writeFile(path.join(bin,'node.ps1'),'# environment detection fixture\n');
  if(process.platform!=='win32')await fs.symlink(process.execPath,path.join(bin,'node'));
  const spec=path.join(root,'spec.json'),log=path.join(root,'calls.jsonl');
  await fs.writeFile(spec,JSON.stringify({selected:'a',targets:['a','b'],bindings:[{id:'dev-a',targetId:'a'},{id:'dev-b',targetId:'b'}],...override}));
  const execute=(args=[],input='',extraEnv={})=>new Promise((resolve,reject)=>{
    const child=spawn(pwsh,['-NoProfile','-NonInteractive','-File',path.join(root,'ci.ps1'),...args],{
      cwd:os.tmpdir(),env:{...process.env,PATH:bin,MENU_LOG:log,MENU_SPEC:spec,...extraEnv},windowsHide:true,
    });
    let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);
    const timeout=setTimeout(()=>{child.kill();reject(new Error(`menu timed out: ${stdout.slice(-1500)} ${stderr}`));},20000);
    child.on('error',reject);child.on('close',code=>{clearTimeout(timeout);resolve({code,stdout,stderr});});child.stdin.end(input);
  });
  const calls=async()=>{try{return (await fs.readFile(log,'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse);}catch(e){if(e.code==='ENOENT')return [];throw e;}};
  const commands=async()=> (await calls()).filter(a=>a[0]==='--silent').map(a=>a.slice(4));
  return {root,bin,execute,calls,commands};
}
const options={skip:pwsh?false:'未安装 PowerShell 7.3+，菜单测试未执行'};

test('纯菜单导航不重复查询状态，手动刷新和失败操作后重新读取',options,async t=>{
  const f=await fixture(t,{fail:'doctor'});
  const result=await f.execute([], '1\n0\n2\n0\nd\nwrong\nr\n7\n3\n0\n0\n');
  assert.equal(result.code,0,result.stdout+result.stderr);
  const calls=await f.commands();
  // Initial load, explicit refresh, and refresh after the failed operation.
  assert.equal(calls.filter(a=>a[0]==='status').length,3,JSON.stringify(calls));
  assert.ok(calls.filter(a=>a[0]==='status').every(a=>a.includes('--light')));
  assert.ok(!calls.some(a=>['targets','runtimes'].includes(a[0])));
  assert.equal(calls.filter(a=>a[0]==='doctor').length,1);
  assert.match(result.stdout,/fixture failure/);
});
test('菜单无绑定可启动退出，无效选择返回菜单，帮助不依赖 pnpm',options,async t=>{
  const f=await fixture(t,{bindings:[]});
  const result=await f.execute([], 'wrong\n0\n');assert.equal(result.code,0,result.stdout+result.stderr);
  assert.match(result.stdout,/未绑定/);assert.match(result.stdout,/有未提交改动/);assert.match(result.stdout,/请输入菜单编号/);
  await fs.unlink(path.join(f.bin,'pnpm.ps1'));
  assert.equal((await f.execute(['help'])).code,0);
  const missing=await f.execute(['status']);assert.equal(missing.code,1);assert.match(missing.stdout,/pnpm/);
  await fs.unlink(path.join(f.bin,'node.ps1'));
  if(process.platform!=='win32')await fs.unlink(path.join(f.bin,'node'));
  assert.match((await f.execute(['status'])).stdout,/Node.js/);
});
test('缺少项目依赖给出安装提示，不自动安装',options,async t=>{
  const f=await fixture(t);await fs.writeFile(path.join(f.root,'package.json'),'{}');
  const result=await f.execute(['status']);assert.equal(result.code,1);assert.match(result.stdout,/pnpm install --frozen-lockfile/);
  assert.equal((await f.calls()).length,0);
});
test('直接模式安全转发中文、空格、引号及 shell 字符；退出码不丢失',options,async t=>{
  const f=await fixture(t,{fail:'check'});
  const special='中文 空格 "quoted" $(touch nope); & | %value%';
  let result=await f.execute(['mp','--','pakku','--target','a','--','cfg','--name',special]);
  assert.equal(result.code,0,result.stdout+result.stderr);
  assert.deepEqual((await f.commands()).at(-1),['pakku','--target','a','--','cfg','--name',special]);
  result=await f.execute(['check','-All']);assert.equal(result.code,37,result.stdout+result.stderr);
  assert.deepEqual((await f.commands()).at(-1),['check','--all']);
  assert.doesNotMatch(result.stdout,/\[y\/N\]|选择/);
});
test('直接模式不会偷偷补 Deploy Collect Apply 的确认参数',options,async t=>{
  const f=await fixture(t);
  for(const command of ['deploy','collect','apply']) {
    const result=await f.execute([command,'-Runtime','dev-a','-Target','a']);
    assert.equal(result.code,0,result.stdout+result.stderr);
    assert.deepEqual((await f.commands()).at(-1),[command,'dev-a','--target','a']);
    assert.doesNotMatch(result.stdout,/\[y\/N\]/);
  }
  await f.execute(['collect','-Runtime','dev-a','-File','config/中文 空格.json','-Confirm','-Stopped']);
  assert.deepEqual((await f.commands()).at(-1),['collect','dev-a','--file','config/中文 空格.json','--confirm','--stopped']);
});
test('Target 复用 use，切换目标后不会部署到旧 Runtime',options,async t=>{
  const f=await fixture(t);
  const result=await f.execute([], '1\n4\n2\n1\ny\nn\nn\n0\n0\n');
  assert.equal(result.code,0,result.stdout+result.stderr);
  const calls=await f.commands();assert.ok(calls.some(a=>a[0]==='use'&&a[1]==='b'),result.stdout+'\n'+JSON.stringify(calls));
  const preview=calls.find(a=>a[0]==='dev');assert.deepEqual(preview,['dev','dev-b','--target','b','--dry-run']);
  assert.ok(!calls.some(a=>a.includes('--stopped')));
});
test('多 Runtime 需明确选择并在会话内保留，真实部署需独立停止确认',options,async t=>{
  const f=await fixture(t,{targets:['a'],bindings:[{id:'one',targetId:'a'},{id:'two',targetId:'a'}]});
  const result=await f.execute([], '1\n3\n2\n1\ny\nn\ny\n0\n0\n');
  assert.equal(result.code,0,result.stdout+result.stderr);
  const calls=await f.commands();assert.ok(calls.some(a=>a[0]==='dev'&&a[1]==='two'&&a.includes('--stopped')));
  assert.ok(!calls.some(a=>a[0]==='dev'&&a[1]==='one'));
});
test('Collect 先展示单文件差异，删除单独确认；冲突不发写入命令',options,async t=>{
  const f=await fixture(t,{deleted:true});
  const result=await f.execute([], '4\n3\nconfig/a.json\ny\ny\n0\n0\n');
  assert.equal(result.code,0,result.stdout+result.stderr);assert.match(result.stdout,/-old\n\+new/);
  assert.ok((await f.commands()).some(a=>a[0]==='collect'&&a.includes('--delete')&&a.includes('--confirm')&&a.includes('--stopped')));
  const conflict=await fixture(t,{conflict:true});
  const blocked=await conflict.execute([], '4\n3\nconfig/a.json\n0\n0\n');
  assert.match(blocked.stdout,/冲突需要先人工合并/);
  assert.ok(!(await conflict.commands()).some(a=>a.includes('--confirm')));
});
test('Collect 新配置需选择来源，拒绝或取消不会回收所有文件',options,async t=>{
  const f=await fixture(t);
  const result=await f.execute([], '4\n3\nconfig/new.json\n1\ny\n0\n0\n');
  assert.equal(result.code,0,result.stdout+result.stderr);
  assert.ok((await f.commands()).some(a=>a.includes('.pakku/client-overrides/config/new.json')&&a.includes('--confirm')));
  const cancelled=await fixture(t);await cancelled.execute([], '4\n3\nconfig/new.json\n0\n0\n0\n');
  assert.ok(!(await cancelled.commands()).some(a=>a.includes('--confirm')));
});
test('Apply 必须先预览，拒绝则不写；确认时转发预览哈希和停止确认',options,async t=>{
  for(const answer of ['n','y']) {
    const f=await fixture(t);const result=await f.execute([], `6\n1\n中文 空格/包.mrpack\nn\n${answer}\n0\n0\n`);
    assert.equal(result.code,0,result.stdout+result.stderr);
    const calls=(await f.commands()).filter(a=>a[0]==='apply');assert.equal(calls.length,answer==='y'?2:1);
    assert.ok(!calls[0].includes('--confirm'));
    if(answer==='y')assert.deepEqual(calls[1].slice(-4),['--sha256','b'.repeat(64),'--confirm','--stopped']);
  }
});
test('绑定先预览再确认，解绑明确确认；未选择不写',options,async t=>{
  const f=await fixture(t,{bindings:[]});
  const result=await f.execute([], '3\n3\nnew-dev\nD:\\游戏 测试\\Example\n\ny\n0\n0\n');
  assert.equal(result.code,0,result.stdout+result.stderr);
  const calls=(await f.commands()).filter(a=>a[0]==='bind');assert.equal(calls.length,2);
  assert.ok(calls[0].includes('--dry-run'));assert.ok(calls[1].includes('--confirm-game-dir'));
  assert.ok(calls[0].includes('D:\\游戏 测试\\Example'),JSON.stringify(calls));
  const cancelled=await fixture(t);await cancelled.execute([], '3\n5\n1\nn\n0\n0\n');
  assert.ok(!(await cancelled.commands()).some(a=>a[0]==='unbind'));
});
test('候选接受使用审查哈希；恢复和批量更新可取消',options,async t=>{
  const f=await fixture(t);const result=await f.execute([], '2\n6\nadd\nsodium\ny\ny\n7\n\nn\n4\nn\n0\n0\n');
  assert.equal(result.code,0,result.stdout+result.stderr);
  const calls=await f.commands();assert.ok(calls.some(a=>a[0]==='deps-accept'&&a.includes('c'.repeat(64))&&a.includes('--confirm')));
  assert.ok(!calls.some(a=>a[0]==='update'||a[0]==='restore-deps'&&a.includes('--confirm')));
});
test('构建所有目标顺序调用已有 build，失败可返回菜单，提交使用原脚本',options,async t=>{
  const f=await fixture(t,{selected:null,fail:'build'});const result=await f.execute([], '5\n2\n0\n8\n4\n0\n0\n');
  assert.equal(result.code,0,result.stdout+result.stderr);assert.match(result.stdout,/fixture failure/);
  const calls=await f.commands();assert.deepEqual(calls.filter(a=>a[0]==='build'),[['build','--target','a'],['build','--target','b']],result.stdout);
  assert.ok((await f.calls()).some(a=>a.join(' ')==='run lint:commits'));
  const source=await fs.readFile(path.join(repo,'ci.ps1'),'utf8');assert.match(source,/run commit/);assert.doesNotMatch(source,/Invoke-Expression|git add \./);
});
