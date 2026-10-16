import { selectTarget } from './workspace.mjs';
import { runtimes, getRuntime } from './runtimes.mjs';
import { changes } from './changes.mjs';
import { run } from './pakku.mjs';

export async function status(root,workspace) {
  let selected=null,selectionError=null;
  try{selected=(await selectTarget(root,workspace)).id;}catch(e){selectionError=e.message;}
  const git=await run('git',['status','--porcelain','--untracked-files=normal'],{cwd:root,capture:true});
  const reports=[];
  for(const binding of (await runtimes(root)).bindings) {
    try {
      const runtime=await getRuntime(root,binding.id),target=workspace.targets.find(t=>t.id===runtime.targetId);
      if(!target)throw new Error('绑定 Target 已移除');
      const report=await changes(root,runtime,target);
      reports.push({runtime:binding.id,targetId:runtime.targetId,baseline:report.baseline,pendingCollect:report.managed.filter(f=>f.state==='runtime-only').map(f=>f.path),conflicts:report.conflicts.length,candidates:report.candidates.length,dependencies:report.dependencies.length,dependencySource:report.dependencySource});
    }catch{reports.push({runtime:binding.id,targetId:binding.targetId,error:'检查失败；运行 changes 查看原因'});}
  }
  return {selected,selectionError,gitDirty:git.code===0?Boolean(git.stdout.trim()):null,runtimes:reports};
}
