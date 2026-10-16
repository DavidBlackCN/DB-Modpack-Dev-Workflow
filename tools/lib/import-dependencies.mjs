import fs from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {safePath,readJson} from './workspace.mjs';
import {verifyRuntime} from './runtimes.mjs';
import {checkJournal} from './deploy.mjs';
import {inventory,textDiff,sourceBytes} from './changes.mjs';
import {sourceSnapshot,digest} from './prepare.mjs';
import {fileInfo,atomicJson} from './runtime-fs.mjs';
import {pakku,requireSuccess} from './pakku.mjs';
import {checkTarget} from './check.mjs';
import {acceptDependencies} from './dependencies.mjs';

const matches=(file,hashes)=>['sha512','sha256','sha1'].some(algorithm=>file.hashes?.[algorithm]===hashes[algorithm]);

// Pakku 1.5.0 Project.pakkuLinks is a set of Pakku IDs, not part of file identity.
// Keep every other field (including future fields) exact; only additive links to new projects are allowed.
function checkImportIntegrity(before,after) {
  const omit=(value,key)=>Object.fromEntries(Object.entries(value).filter(([k])=>k!==key));
  if(!isDeepStrictEqual(omit(before,'projects'),omit(after,'projects')))throw new Error('导入候选修改了目标版本或顶层上下文，拒绝接受');
  const index=lock=>{
    const projects=lock.projects??[];
    if(!Array.isArray(projects))throw new Error('导入候选 Project 列表无效');
    const result=new Map();
    for(const project of projects) {
      if(!project||typeof project.pakku_id!=='string'||!project.pakku_id.trim()||result.has(project.pakku_id))throw new Error('导入候选存在缺失或重复的 pakku_id');
      result.set(project.pakku_id,project);
    }
    return result;
  };
  const old=index(before),next=index(after),added=[...next.values()].filter(p=>!old.has(p.pakku_id));
  const addedIds=new Set(added.map(p=>p.pakku_id));
  const links=project=>{
    const values=Object.hasOwn(project,'pakku_links')?project.pakku_links:[];
    if(!Array.isArray(values)||values.some(v=>typeof v!=='string'||!v.trim())||new Set(values).size!==values.length)throw new Error('导入候选 pakku_links 必须是无重复的 Project ID 列表');
    return new Set(values);
  };
  for(const [id,project] of old) {
    const current=next.get(id);
    if(!current||!isDeepStrictEqual(omit(project,'pakku_links'),omit(current,'pakku_links')))throw new Error('导入候选删除或修改了现有依赖核心内容，拒绝接受');
    const previousLinks=links(project),currentLinks=links(current);
    if([...previousLinks].some(link=>!currentLinks.has(link)))throw new Error('导入候选删除了已有 pakku_links，拒绝接受');
    if([...currentLinks].some(link=>!previousLinks.has(link)&&!addedIds.has(link)))throw new Error('新增 pakku_links 未指向本次新增 Project，拒绝接受');
  }
  for(const project of added)if([...links(project)].some(link=>!next.has(link)))throw new Error('新增 Project 的 pakku_links 指向不存在的 Project，拒绝接受');
  return added;
}

// Only inventory active top-level mods. Pakku, not filenames or embedded metadata, resolves identity.
export async function scanImportDependencies(root,runtime,target) {
  await verifyRuntime(root,runtime,target);await checkJournal(root,runtime);
  const info=await sourceSnapshot(root,target),known=(info.lock.projects??[]).flatMap(p=>p.files??[]);
  const candidates=[],skipped=[];
  for(const name of await inventory(runtime.gameDir,'mods')) {
    if(!/^mods\/[^/]+\.jar$/i.test(name)) {skipped.push({path:name,reason:'仅识别 mods 根目录中启用的 JAR'});continue;}
    const file=await safePath(runtime.gameDir,name),stat=await fs.lstat(file);
    if(stat.size>256*1024*1024) {skipped.push({path:name,reason:'文件超过 256 MiB'});continue;}
    const current=await fileInfo(runtime.gameDir,name);
    if(!current)throw new Error('扫描期间 JAR 已变化');
    const bytes=await fs.readFile(current.file),hashes=Object.fromEntries(['sha1','sha256','sha512'].map(a=>[a,digest(bytes,a)]));
    if(hashes.sha256!==current.hash)throw new Error('扫描期间 JAR 已变化');
    if(known.some(f=>matches(f,hashes))) {skipped.push({path:name,reason:'当前 Pakku 锁文件已管理相同内容'});continue;}
    candidates.push({path:name,hash:hashes.sha256,size:bytes.length,hashes});
  }
  return {action:'import-deps',runtime:runtime.id,target:target.id,candidates,skipped,notice:'候选尚未确认项目身份。点选后由 Pakku 按文件哈希联网识别；不复制 JAR 到正式源。'};
}

export async function importDependencies(root,runtime,target,options={}) {
  if(options.candidate) {
    if(options.file||options.sha256)throw new Error('接受候选不能同时指定 --file / --sha256');
    if(!/^[a-f0-9-]{36}$/.test(options.candidate))throw new Error('候选 ID 无效');
    const record=await readJson(await safePath(root,`.work/candidates/${options.candidate}/review.json`));
    if(record.importSource?.key!==runtime.key||record.importSource?.runtime!==runtime.id)throw new Error('候选不属于当前导入实例');
    return acceptDependencies(root,target,options);
  }
  if(options.confirm||options.acceptHash)throw new Error('请先生成并审查导入候选，再通过 --candidate / --accept-hash / --confirm 接受');
  const report=await scanImportDependencies(root,runtime,target);
  if(!options.file) {if(options.sha256)throw new Error('--sha256 需要 --file');return report;}
  const selected=report.candidates.find(c=>c.path===options.file);
  if(!selected||options.sha256!==selected.hash)throw new Error('请选择列表中的新增 JAR，并用 --sha256 确认其扫描哈希');
  const info=await sourceSnapshot(root,target),id=randomUUID(),projectPath=`.work/candidates/${id}/project`,dir=await safePath(root,projectPath);
  // Limit this first implementation to Pakku's default Mod directory.
  if(info.config.paths?.mods && info.config.paths.mods!=='mods')throw new Error('依赖导入暂只支持默认 mods 路径');
  await fs.mkdir(dir,{recursive:true});
  for(const name of info.source) {const dest=await safePath(dir,name);await fs.mkdir(path.dirname(dest),{recursive:true});await fs.copyFile(path.join(info.dir,name),dest);}
  const originalConfig=await fs.readFile(path.join(dir,'pakku.json'));
  const staged=await safePath(dir,'mods/import.jar');await fs.mkdir(path.dirname(staged),{recursive:true});
  const bytes=await fs.readFile(await safePath(runtime.gameDir,selected.path));
  if(digest(bytes)!==selected.hash)throw new Error('准备期间 JAR 已变化');
  await fs.writeFile(staged,bytes,{flag:'wx'});
  try {requireSuccess(await pakku(root,dir,['--yes','sync','--additions'],{...options,capture:true}));}
  finally {await fs.unlink(staged);await fs.rmdir(path.dirname(staged)).catch(e=>{if(e.code!=='ENOTEMPTY')throw e;});}
  // sync also serializes pakku.json; preserve original formatting only when its data is identical.
  if(!isDeepStrictEqual(info.config,await readJson(await safePath(dir,'pakku.json'))))throw new Error('Pakku 修改了项目配置，拒绝导入');
  await fs.writeFile(await safePath(dir,'pakku.json'),originalConfig);
  await checkTarget(root,{...target,path:projectPath},options);
  const candidate=await sourceSnapshot(root,{...target,path:projectPath});
  for(const name of new Set([...info.source,...candidate.source]))if(name!=='pakku-lock.json'&&info.hashes[name]!==candidate.hashes[name])throw new Error('Pakku 修改了锁文件之外的源，拒绝导入');
  const added=checkImportIntegrity(info.lock,candidate.lock);
  const identified=added.filter(p=>p.type==='MOD'&&(p.files??[]).some(f=>matches(f,selected.hashes)));
  if(identified.length!==1)throw new Error('Pakku 未唯一识别该新增 Mod；可能来源未知、版本不兼容或项目已被管理。未导入');
  if((await fileInfo(runtime.gameDir,selected.path))?.hash!==selected.hash)throw new Error('识别期间 JAR 已变化');
  const before=await sourceBytes(info.dir,'pakku-lock.json'),after=await sourceBytes(dir,'pakku-lock.json');
  const record={schema:1,id,targetId:target.id,sourceFingerprint:info.fingerprint,operation:'import',project:Object.values(identified[0].slug??{}).join(' / '),hash:digest(after),before:digest(before),importSource:{runtime:runtime.id,key:runtime.key,file:selected.path,hash:selected.hash}};
  await atomicJson(await safePath(root,`.work/candidates/${id}/review.json`),record);
  return {...record,projectPath,added:added.map(p=>({name:p.name,id:p.id,slug:p.slug,files:p.files?.map(f=>({name:f.file_name,id:f.id}))})),diff:textDiff(before,after),notice:'请审查全部新增依赖及许可后接受；只有 Pakku 锁文件会写回正式源。'};
}
