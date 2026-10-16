#requires -Version 7.3
# Local UI only. All package/game writes go through the Workspace CLI.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$PSNativeCommandArgumentPassing = 'Standard'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
$script:EntryArguments = @($args)
$script:RuntimeChoice = $null
$script:LastResult = $null

function Show-Help {
    Write-Host @'
DB Modpack Dev Workflow v2 — 本地开发入口（PowerShell 7.3+）
  .\ci.ps1                           中文菜单
  .\ci.ps1 help                      本帮助
  .\ci.ps1 status
  .\ci.ps1 check [-Target <id> | -All]
  .\ci.ps1 build -Target <id>
  .\ci.ps1 deploy -Runtime <name> -Target <id> -Stopped
  .\ci.ps1 changes -Runtime <name>
  .\ci.ps1 collect -Runtime <name> -File <相对路径> -Confirm -Stopped
  .\ci.ps1 mp -- <原始 mp 参数...>     透明转发

快捷参数：-Target -Runtime -All -DryRun -Stopped -Confirm -File -Source
          -Java -Launcher -GameDir -VersionDir -ConfirmGameDir -AdoptExisting
          -Operation -Project -Candidate -AcceptHash -Repo -Run -Release -Sha256 -Delete -Json
原生 --参数 同样可用。含空格路径用引号包围；参数按数组传递，不执行输入中的代码。
直接命令不询问确认，也不会自动加 -Stopped / -Confirm。退出码与 mp 一致。
高级示例：.\ci.ps1 mp -- pakku --target fabric-1.21.1 -- cfg --name '我的整合包'
菜单只调用现有 CLI；此脚本不是 GitHub Actions 运行器，不自动启动游戏或推送 Git。
'@
}

function Initialize-Tools {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw '未找到 Node.js。请安装 Node.js 24，再重新打开 PowerShell。' }
    $script:Pnpm = Get-Command pnpm.ps1 -ErrorAction SilentlyContinue
    if (-not $script:Pnpm) { $script:Pnpm = Get-Command pnpm -ErrorAction SilentlyContinue }
    if (-not $script:Pnpm -or $script:Pnpm.Source -match '\.(cmd|bat)$') {
        throw '未找到可安全调用的 pnpm。请安装 pnpm 10.28.2（Windows 需 pnpm.ps1 或 pnpm.exe），再重新打开 PowerShell。'
    }
    if ((Test-Path -LiteralPath (Join-Path $PSScriptRoot 'package.json')) -and
        -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules/fflate'))) {
        throw '尚未安装项目依赖。请先在项目目录执行 pnpm install --frozen-lockfile。'
    }
}

function Convert-DirectArguments([string[]] $Values) {
    if ($Values[0] -eq 'mp') {
        $rest = @($Values | Select-Object -Skip 1)
        if ($rest.Count -and $rest[0] -eq '--') { $rest = @($rest | Select-Object -Skip 1) }
        return ,$rest
    }
    $aliases = @{
        '-Target'='--target'; '-All'='--all'; '-DryRun'='--dry-run'; '-Stopped'='--stopped'
        '-Confirm'='--confirm'; '-File'='--file'; '-Source'='--source'; '-Java'='--java'
        '-Launcher'='--launcher'; '-GameDir'='--game-dir'; '-VersionDir'='--version-dir'
        '-ConfirmGameDir'='--confirm-game-dir'; '-AdoptExisting'='--adopt-existing'
        '-Operation'='--operation'; '-Project'='--project'; '-Candidate'='--candidate'
        '-AcceptHash'='--accept-hash'; '-Repo'='--repo'; '-Run'='--run'; '-Release'='--release'
        '-Sha256'='--sha256'; '-Delete'='--delete'; '-Json'='--json'
    }
    $valueFlags = @('--target','--file','--source','--java','--launcher','--game-dir','--version-dir','--operation','--project','--candidate','--accept-hash','--repo','--run','--release','--sha256')
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add($Values[0])
    $runtimeName = $null
    for ($i = 1; $i -lt $Values.Count; $i++) {
        $value = $Values[$i]
        if ($value -eq '--') { for (; $i -lt $Values.Count; $i++) { $out.Add($Values[$i]) }; break }
        if ($value -eq '-Runtime') {
            if ($runtimeName -or ++$i -ge $Values.Count -or $Values[$i].StartsWith('-')) { throw '-Runtime 需要一个实例名，且不能重复' }
            $runtimeName = $Values[$i]
            continue
        }
        if ($aliases.ContainsKey($value)) { $value = $aliases[$value] }
        $out.Add($value)
        if ($value -in $valueFlags) {
            if (++$i -ge $Values.Count) { throw "$value 缺少值" }
            $out.Add($Values[$i])
        }
    }
    if ($runtimeName) { $out.Insert(1, $runtimeName) }
    return ,$out.ToArray()
}

# Both modes use this exact forwarding path. No shell command strings or eval.
function Invoke-Mp([string[]] $Arguments, [switch] $Capture) {
    $global:LASTEXITCODE = 0
    $pnpmArguments = @('--silent','run','mp','--') + $Arguments
    if (-not $Capture) {
        & $script:Pnpm.Source @pnpmArguments | Out-Host
        return $LASTEXITCODE
    }
    $lines = @(& $script:Pnpm.Source @pnpmArguments 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $records = [System.Collections.Generic.List[object]]::new()
    $messages = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $found = $false
        if ($lines[$i] -match '^[\[{]') {
            $buffer = ''
            for ($j = $i; $j -lt $lines.Count; $j++) {
                $buffer += $lines[$j] + "`n"
                if ($lines[$j] -notmatch '[\]}]\s*$') { continue }
                try {
                    # ConvertFrom-Json accepts some incomplete arrays; validate the full document first.
                    $document = [System.Text.Json.JsonDocument]::Parse($buffer)
                    $document.Dispose()
                    $value = ConvertFrom-Json -InputObject $buffer -AsHashtable -NoEnumerate -ErrorAction Stop
                    $records.Add($value); $i = $j; $found = $true; break
                } catch { }
            }
        }
        if (-not $found) { $messages.Add($lines[$i]) }
    }
    return @{ Code=$code; Records=$records.ToArray(); Messages=$messages.ToArray(); Raw=($lines -join "`n") }
}

function Read-Choice([string] $Prompt) {
    if ([Console]::IsInputRedirected) { Write-Host $Prompt; $value = [Console]::ReadLine() }
    else { $value = Read-Host $Prompt }
    if ($null -eq $value) { throw '输入已结束；菜单已停止。' }
    return $value.Trim()
}
function Confirm-Action([string] $Prompt) { return (Read-Choice "$Prompt [y/N]") -ceq 'y' }
function Read-Required([string] $Prompt) {
    $value = Read-Choice "$Prompt（0 取消）"
    if (-not $value -or $value -eq '0') { throw '已取消。' }
    return $value
}
function Show-Rows($Rows) {
    foreach ($row in $Rows) {
        if ($row -is [string]) { Write-Host "  $row"; continue }
        Write-Host "  $($row.type)$($row.state) $($row.path) $($row.reason)"
    }
}
function Show-Summary($Result) {
    foreach ($message in $Result.Messages) { if ($message) { Write-Host $message } }
    foreach ($record in $Result.Records) {
        if ($record -isnot [System.Collections.IDictionary]) { continue }
        if ($record.output) {
            Write-Host "目标: $($record.target) | 输出: $($record.output)"
            foreach ($artifact in $record.artifacts) { Write-Host "  $($artifact.kind): $($artifact.name)" }
            Write-Host "报告: $(Join-Path $record.output 'build-report.json')"
        } elseif ($record.action -eq 'bind') {
            $r = $record.runtime
            Write-Host "实例: $($r.id) / $($r.targetId) / $($r.launcher)"
            Write-Host "游戏目录: $($r.gameDir)`n版本目录: $($r.versionDir)`nMinecraft: $($r.mc)"
            Write-Host "加载器: $(ConvertTo-Json $r.loaders -Compress) | 隔离: $($r.layout)"
            Write-Host $r.evidence
            Write-Host "现有 Mod/配置: $(@($record.existing).Count) 个（不自动接管）"
        } elseif ($record.action -eq 'apply') {
            Write-Host "目标: $($record.target) | 包版本: $($record.version) | Git: $($record.git) | dirty: $($record.dirty)"
            Write-Host "来源: $(ConvertTo-Json $record.provenance -Compress)"
        } elseif ($record.Contains('managed')) {
            $labels=@{managed='受管文件';conflicts='冲突';candidates='新增配置';dependencies='Mod 变化'}
            foreach ($key in @('managed','conflicts','candidates','dependencies')) {
                Write-Host "$($labels[$key]) : $(@($record[$key]).Count)"; Show-Rows $record[$key]
            }
        } elseif ($record.Contains('actions')) {
            Write-Host "文件变更: $(@($record.actions).Count) | 冲突: $(@($record.conflicts).Count)"
            Show-Rows $record.actions; Show-Rows $record.conflicts
            Write-Host "保留未知文件: $(@($record.preserved).Count) | 待下载: $(@($record.downloads).Count)"
        } elseif ($record.projectPath) {
            Write-Host "候选: $($record.id) | $($record.operation) $($record.project)"
            Write-Host "SHA256: $($record.hash)`n副本: $($record.projectPath)"
            Write-Host $record.diff.text
        } elseif ($record.Contains('gitDirty')) {
            Write-Host "Target: $($record.selected) | Git dirty: $($record.gitDirty)"
            foreach ($r in $record.runtimes) { Write-Host "  $($r.runtime) / $($r.targetId) 待回收: $(@($r.pendingCollect).Count) 冲突: $($r.conflicts) $($r.error)" }
        } elseif ($record.Contains('bindings')) {
            foreach ($r in $record.bindings) { Write-Host "  $($r.id) / $($r.targetId) / $($r.launcher) / $($r.gameDir)" }
            if (-not $record.bindings.Count) { Write-Host '未绑定' }
        } elseif ($record.directory) {
            Write-Host "目标: $($record.target) | 准备文件: $(@($record.files).Count) | 临时目录: $($record.directory)"
        } else {
            foreach ($key in @('check','target','applied','adopted','unchanged','recovery','restored','collected','backup','notice','retained','node','pnpm','java','git','pakku')) {
                if ($record.Contains($key)) { Write-Host "$key : $($record[$key])" }
            }
        }
    }
    if ($Result.Code -eq 0) { Write-Host '操作成功。' -ForegroundColor Green }
    else { Write-Host "操作失败（退出码 $($Result.Code)）。详情保留在上方；d 可查看完整输出。" -ForegroundColor Red }
}
function Run-Mp([string[]] $Arguments) {
    Write-Host "执行: mp $($Arguments -join ' ')" -ForegroundColor Cyan
    $script:LastResult = Invoke-Mp $Arguments -Capture
    Show-Summary $script:LastResult
    if ($script:LastResult.Code -ne 0) { throw "命令未完成。涉及实例写入时，可在开发测试菜单执行 Recover；请先处理上述原因。" }
    return $script:LastResult
}
function Query-Mp([string[]] $Arguments) {
    $result = Invoke-Mp $Arguments -Capture
    if ($result.Code -ne 0) { $script:LastResult=$result; Show-Summary $result; throw '无法读取状态，请使用项目与环境检查。' }
    if (-not $result.Records.Count) { throw 'CLI 未返回可读取的状态。' }
    return $result.Records[-1]
}
function Refresh-Selection {
    $script:State = Query-Mp @('status','--json')
    $script:Targets = @(Query-Mp @('targets'))
    $script:Bindings = @((Query-Mp @('runtimes')).bindings)
    $script:TargetChoice = $script:State.selected
    $available = @($script:Bindings | Where-Object targetId -EQ $script:TargetChoice)
    if ($script:RuntimeChoice -notin @($available.id)) { $script:RuntimeChoice = $null }
    if (-not $script:RuntimeChoice -and $available.Count -eq 1) { $script:RuntimeChoice = $available[0].id }
}
function Choose-Item($Items, [string] $Label) {
    if (-not $Items.Count) { throw "没有可选的 $Label。" }
    while ($true) {
        Show-Page "📋 选择 $Label"
        for ($i=0; $i -lt $Items.Count; $i++) { Write-Host "  [$($i+1)] 📦 $($Items[$i].id)" }
        Write-Host "`n  [0] ↩️ 返回" -ForegroundColor DarkGray
        $choice=Read-Choice "$Label（0 返回）"
        if ($choice -eq '0') { return $null }
        $number=0
        if ([int]::TryParse($choice,[ref]$number) -and $number -ge 1 -and $number -le $Items.Count) { return $Items[$number-1].id }
        Write-Host '请输入列表中的编号。' -ForegroundColor Yellow
    }
}
function Select-Target {
    $id=Choose-Item $script:Targets 'Target'
    if ($id) { $null=Run-Mp @('use',$id); Refresh-Selection }
}
function Require-Target {
    Refresh-Selection
    if (-not $script:TargetChoice) { Select-Target }
    if (-not $script:TargetChoice) { throw '未选择 Target。' }
}
function Select-Runtime {
    Require-Target
    $available=@($script:Bindings | Where-Object targetId -EQ $script:TargetChoice)
    $id=Choose-Item $available 'Runtime'
    if ($id) { $script:RuntimeChoice=$id }
}
function Runtime-Arguments([string] $Command) {
    Require-Target
    if (-not $script:RuntimeChoice) { Select-Runtime }
    if (-not $script:RuntimeChoice) { throw '未绑定或未选择 Runtime，请先绑定测试实例。' }
    return ,@($Command,$script:RuntimeChoice,'--target',$script:TargetChoice)
}
function Confirm-Stopped { return Confirm-Action '确认游戏已关闭，操作结束前不会启动，并执行上述写入？' }
function Invoke-Development([string] $Choice) {
    if ($Choice -eq '3') { Select-Runtime; return }
    if ($Choice -eq '4') { Select-Target; return }
    $command=if ($Choice -eq '5') { 'recover' } else { 'dev' }
    $forward=Runtime-Arguments $command
    if ($Choice -eq '5') { if (Confirm-Stopped) { $null=Run-Mp ($forward+@('--stopped')) }; return }
    if (-not (Confirm-Action '准备最新清单会在 .work/.cache 中写入临时文件，是否继续？')) { return }
    $null=Run-Mp @('prepare','--target',$script:TargetChoice)
    if (Confirm-Action '是否接管内容完全相同的已有文件？不同内容仍会拒绝') { $forward+= '--adopt-existing' }
    $null=Run-Mp ($forward+@('--dry-run'))
    if ($Choice -eq '1' -and (Confirm-Stopped)) { $null=Run-Mp ($forward+@('--stopped')) }
}
function Invoke-Mods([string] $Choice) {
    Require-Target
    if ($Choice -in @('1','2','3','4','5')) {
        $command=@{'1'='add';'2'='remove';'3'='update';'4'='update';'5'='list'}[$Choice]
        $forward=@($command,'--target',$script:TargetChoice)
        if ($Choice -in @('1','2','3')) { $forward+=Read-Required 'Mod slug / 项目 ID' }
        if ($Choice -ne '5' -and -not (Confirm-Action "确认 $command 当前目标的依赖（不指定项目的 update 会更新全部）？")) { return }
        # Pakku's own interaction remains attached to the terminal.
        $code=Invoke-Mp $forward
        if ($code -ne 0) { throw "Pakku 操作失败（退出码 $code）。" }
        Write-Host '操作成功。' -ForegroundColor Green
    } elseif ($Choice -eq '6') {
        $forward=Runtime-Arguments 'deps-review'
        $null=Run-Mp (Runtime-Arguments 'changes')
        $operation=Read-Required '候选操作 add 或 remove'
        if ($operation -notin @('add','remove')) { throw '仅支持 add 或 remove。' }
        $project=Read-Required '已核实来源的项目 ID / slug'
        if (-not (Confirm-Action '生成完整 Pakku 候选副本（可能联网并写入 .work）？')) { return }
        $result=Run-Mp ($forward+@('--operation',$operation,'--project',$project))
        $candidate=$result.Records | Where-Object { $_.projectPath } | Select-Object -Last 1
        if (-not $candidate) { throw '没有可接受的候选。' }
        if (Confirm-Action '已审查上方锁文件差异，接受此候选写入正式源？') {
            $null=Run-Mp ((Runtime-Arguments 'deps-accept')+@('--candidate',$candidate.id,'--accept-hash',$candidate.hash,'--confirm'))
        }
    } elseif ($Choice -eq '7') {
        $forward=Runtime-Arguments 'restore-deps'
        $file=Read-Choice '可选：额外/禁用 JAR 的相对路径（留空只恢复受管依赖，0 取消）'
        if ($file -eq '0') { return }; if ($file) { $forward+=@('--file',$file) }
        $null=Run-Mp $forward
        if (Confirm-Stopped) { $null=Run-Mp ($forward+@('--confirm','--stopped')) }
    }
}
function Invoke-Runtimes([string] $Choice) {
    if ($Choice -eq '1') { $null=Run-Mp @('runtimes'); return }
    if ($Choice -eq '4') { Select-Runtime; return }
    if ($Choice -eq '5') {
        Refresh-Selection; $id=Choose-Item $script:Bindings '要解除的实例'
        if ($id -and (Confirm-Action "解除 $id 的绑定？游戏文件和备份保留")) { $null=Run-Mp @('unbind',$id); Refresh-Selection }; return
    }
    Require-Target
    Write-Host "绑定到 Target: $script:TargetChoice（如需切换，先返回开发测试菜单）"
    $name=Read-Required '绑定名称'
    $gameDir=Read-Required '实际游戏目录（绝对路径，不需要额外引号）'
    $versionDir=Read-Choice '版本 JSON 所在目录（相同时留空，0 取消）'
    if ($versionDir -eq '0') { return }
    $launcher=if ($Choice -eq '2') { 'pcl2' } else { 'hmcl' }
    $forward=@('bind',$name,'--launcher',$launcher,'--target',$script:TargetChoice,'--game-dir',$gameDir)
    if ($versionDir) { $forward+=@('--version-dir',$versionDir) }
    $null=Run-Mp ($forward+@('--dry-run'))
    if (Confirm-Action '版本和实际游戏目录正确，保存绑定？') {
        $null=Run-Mp ($forward+@('--confirm-game-dir')); $script:RuntimeChoice=$name
    }
}
function Invoke-Collect([string] $Choice) {
    $forward=Runtime-Arguments 'collect'
    if ($Choice -eq '1') { $null=Run-Mp (Runtime-Arguments 'changes'); return }
    $result=Run-Mp ($forward+@('--json'))
    $report=$result.Records[-1]
    if ($Choice -eq '5') { Show-Rows $report.dependencies; return }
    if ($Choice -eq '4') { foreach ($item in $report.candidates) { Write-Host $item.path; Write-Host $item.diff.text }; return }
    $file=Read-Required '要查看/回收的相对路径，例如 config/example.json'
    $items=@($report.managed)+@($report.candidates)
    $item=$items | Where-Object path -CEQ $file | Select-Object -First 1
    if (-not $item) { throw '该路径不在配置变更或新增候选中。' }
    Write-Host "$file → $($item.source) | $($item.state)"
    Write-Host ($item.diff.text ?? $item.diff.description ?? '文件无文本差异。')
    if ($Choice -eq '2') { return }
    $forward+=@('--file',$file)
    if ($item.state -eq 'candidate') {
        Write-Host "`n  [1] 🖥️ 客户端覆盖`n  [2] 📦 公共覆盖`n  [0] ↩️ 取消"
        $location=Read-Choice '选择新增配置来源'
        if ($location -eq '0') { return }
        $prefix=@{'1'='.pakku/client-overrides/';'2'='.pakku/overrides/'}[$location]
        if (-not $prefix) { throw '来源选择无效。' }
        $forward+=@('--source',($prefix+$file)); Write-Host "写入源位置: $prefix$file"
    } elseif ($item.state -ne 'runtime-only') { throw '只能回收仅实例变化的文件；冲突需要先人工合并。' }
    elseif ($null -eq $item.runtime) {
        if (-not (Confirm-Action "单独确认删除正式源文件 $($item.source)？")) { return }
        $forward+='--delete'
    }
    if (Confirm-Stopped) { $null=Run-Mp ($forward+@('--confirm','--stopped')) }
}
function Invoke-Builds([string] $Choice) {
    if ($Choice -eq '2') { Refresh-Selection } else { Require-Target }
    if ($Choice -eq '3') {
        $directory=Join-Path $PSScriptRoot "dist/$script:TargetChoice"
        $latest=Get-ChildItem -LiteralPath $directory -Filter build-report.json -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) { Write-Host '当前目标还没有本地构建结果。'; return }
        $report=Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json -AsHashtable
        $report.output=$latest.DirectoryName; $report.target=$report.targetId
        Show-Summary @{Code=0;Records=@($report);Messages=@()}; return
    }
    $ids=if ($Choice -eq '2') { @($script:Targets.id) } else { @($script:TargetChoice) }
    $failed=@()
    foreach ($id in $ids) {
        try { $null=Run-Mp @('build','--target',$id) } catch { Write-Host $_.Exception.Message -ForegroundColor Red; $failed+=$id }
    }
    if ($failed.Count) { throw "构建失败: $($failed -join ', ')" }
}
function Invoke-Apply([string] $Choice) {
    $forward=Runtime-Arguments 'apply'
    if ($Choice -eq '1') { $forward+=@('--file',(Read-Required 'MRPACK 路径（同目录需要报告和 SHA256SUMS）')) }
    else {
        $forward+=@('--repo',(Read-Required 'GitHub 仓库 owner/repository'))
        if ($Choice -eq '2') { $forward+=@('--run',(Read-Required 'Actions Run ID')) }
        else { $forward+=@('--release',(Read-Required 'Release Tag')) }
        Write-Host '预览会联网读取包，不写入游戏目录。'
    }
    if (Confirm-Action '是否接管内容完全相同的已有文件？') { $forward+='--adopt-existing' }
    $result=Run-Mp $forward
    $source=$result.Records | Where-Object { $_.action -eq 'apply' } | Select-Object -Last 1
    if (-not $source.provenance.packageHash) { throw '没有可确认的包哈希，停止应用。' }
    if (Confirm-Stopped) { $null=Run-Mp ($forward+@('--sha256',$source.provenance.packageHash,'--confirm','--stopped')) }
}
function Invoke-Checks([string] $Choice) {
    $forward=switch ($Choice) {
        '1' { Require-Target; @('check','--target',$script:TargetChoice) }
        '2' { @('check','--all') }
        '3' { @('doctor') }
        '4' { if (-not (Confirm-Action '下载或校验固定 Pakku（可能联网并写入 .cache）？')) { return }; @('bootstrap') }
        '5' { @('status','--json') }
    }
    if ($forward) { $null=Run-Mp $forward }
}
function Invoke-Git([string] $Choice) {
    $global:LASTEXITCODE=0
    switch ($Choice) {
        '1' { & git status --short }
        '2' { & git --no-pager diff; & git --no-pager diff --cached }
        '3' {
            Write-Host '只提交已暂存文件；请在终端用 git add <文件> 明确暂存。'
            & git --no-pager diff --cached --stat
            if (-not (Confirm-Action '打开 cz-git 提交菜单？')) { return }
            & $script:Pnpm.Source run commit
        }
        '4' { & $script:Pnpm.Source run lint:commits }
    }
    if ($LASTEXITCODE -ne 0) { throw "Git/提交工具失败（退出码 $LASTEXITCODE）。" }
    Write-Host '操作成功。' -ForegroundColor Green
}
function Invoke-Advanced {
    Show-Page '🛠️ Pakku 高级操作' '逐个输入原生参数，空行结束；输入 0 取消。'
    Require-Target
    Write-Host 'Pakku 原生命令可能修改工程。逐个输入参数，不需要 shell 引号；空行结束，0 取消。'
    $native=@()
    while ($true) {
        $value=Read-Choice "参数 $($native.Count+1)"
        if ($value -eq '0') { return }
        if ($value -eq '') { break }; $native+= $value
    }
    if (-not $native.Count) { return }
    Write-Host ($native | ConvertTo-Json -Compress)
    if (Confirm-Action "对 $script:TargetChoice 执行上述原生参数？") {
        $code=Invoke-Mp (@('pakku','--target',$script:TargetChoice,'--')+$native)
        if ($code -ne 0) { throw "Pakku 失败（退出码 $code）。" }
        Write-Host '操作成功。' -ForegroundColor Green
    }
}
function Show-Page([string] $Title, [string] $Description) {
    Write-Host "`n────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host '  DB Modpack Dev Workflow v2' -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────' -ForegroundColor DarkGray
    $runtimeLabel=if ($script:RuntimeChoice) { $script:RuntimeChoice } elseif (@($script:Bindings | Where-Object targetId -EQ $script:TargetChoice).Count) { '未选择' } else { '未绑定' }
    $gitState=if ($null -eq $script:State.gitDirty) { '未知' } elseif ($script:State.gitDirty) { '有未提交改动' } else { '干净' }
    Write-Host "  🎯 目标  $($script:TargetChoice ?? '未选择')"
    Write-Host "  🎮 实例  $runtimeLabel"
    Write-Host "  🌿 Git   $gitState"
    if ($Description) { Write-Host "`n  $Description" -ForegroundColor DarkGray }
    Write-Host ''
}
function Show-Menu {
    $titles=@('🏠 主菜单','🚀 开发测试','🧩 Mod / 依赖管理','🎮 启动器实例管理','📥 查看与回收游戏修改','📦 构建整合包','📲 应用 CI / Release 构建','🔍 项目与环境检查','🌿 Git 提交','🛠️ Pakku 高级操作')
    $hints=@('输入编号进入功能页。','先预览变化，再确认部署；游戏须保持关闭。','由 Pakku 管理依赖；修改后可检查差异。','绑定启动器已有实例，按目标选择测试实例。','先查看差异，再逐个回收配置文件。','构建结果保存在 dist/，可查看最近一次输出。','先预览包来源与变化，再确认写入实例。','检查源工程、工具环境和当前状态。','先暂存需要提交的文件，再打开规范提交菜单。')
    $menus=@{
        '1'=@('🚀 部署到当前实例','👀 准备并预览部署变化','🎮 切换测试实例','🎯 切换目标','🛟 恢复失败部署（Recover）')
        '2'=@('➕ 添加 Mod','➖ 删除 Mod','🔄 更新指定 Mod','🔄 更新全部 Mod','📋 查看 Mod 列表','🔎 审查并接受本地依赖变化','↩️ 恢复正式依赖')
        '3'=@('📋 查看已绑定实例','🔗 绑定 PCL2 实例','🔗 绑定 HMCL 实例','🎮 切换当前实例','🔓 解除绑定')
        '4'=@('📋 查看全部变化','🔎 查看指定配置差异','📥 回收指定配置','🆕 审查新增配置候选','🧩 查看依赖偏离')
        '5'=@('📦 构建当前目标','📦 构建所有目标','📂 查看最近构建结果')
        '6'=@('📂 应用本地 MRPACK','⚙️ 应用 GitHub Actions Run','🏷️ 应用 GitHub Release')
        '7'=@('🔍 检查当前目标','🔍 检查全部目标','🩺 环境诊断','📥 安装 / 校验 Pakku','📋 查看工作区状态')
        '8'=@('🌿 查看 Git 状态','🔎 查看 Git Diff','📝 交互式提交','✅ 校验提交信息')
    }
    $section=''
    while ($true) {
        try { Refresh-Selection } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
        Show-Page $titles[[int]$section] $hints[[int]$section]
        if (-not $section) {
            for ($i=1; $i -le 9; $i++) {
                if ($i -in @(1,5,7)) {
                    $group=@{1='开发与同步';5='构建与应用';7='检查与维护'}[$i]
                    Write-Host "  ── $group ──" -ForegroundColor DarkGray
                }
                Write-Host "  [$i] $($titles[$i])"
                if ($i -in @(4,6)) { Write-Host '' }
            }
        } else {
            $items=$menus[$section]
            for ($i=0; $i -lt $items.Count; $i++) { Write-Host "  [$($i+1)] $($items[$i])" }
        }
        Write-Host "`n  [d] 📄 查看上次操作的完整输出" -ForegroundColor DarkGray
        $backLabel=if ($section) { '返回上一级' } else { '退出' }
        Write-Host "  [0] ↩️ $backLabel`n" -ForegroundColor DarkGray
        $choice=Read-Choice '请选择'
        if ($choice -eq '0') { if (-not $section) { return }; $section=''; continue }
        if ($choice -eq 'd') { Write-Host ($script:LastResult.Raw ?? '暂无操作输出。'); continue }
        try {
            if (-not $section) {
                if ($choice -eq '9') { Invoke-Advanced }
                elseif ($menus.ContainsKey($choice)) { $section=$choice }
                else { Write-Host '请输入菜单编号。' -ForegroundColor Yellow }
                continue
            }
            $number=0
            if (-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $menus[$section].Count) { Write-Host '请输入菜单编号。' -ForegroundColor Yellow; continue }
            switch ($section) {
                '1' { Invoke-Development $choice }; '2' { Invoke-Mods $choice }; '3' { Invoke-Runtimes $choice }
                '4' { Invoke-Collect $choice }; '5' { Invoke-Builds $choice }; '6' { Invoke-Apply $choice }
                '7' { Invoke-Checks $choice }; '8' { Invoke-Git $choice }
            }
        } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    }
}

$exitCode=0
Push-Location -LiteralPath $PSScriptRoot
try {
    if ($script:EntryArguments.Count -and $script:EntryArguments[0] -in @('help','--help','-h')) { Show-Help }
    else {
        Initialize-Tools
        if ($script:EntryArguments.Count) {
            $forward=Convert-DirectArguments $script:EntryArguments
            # Stream child output to the terminal; only the final integer is the exit code.
            $global:LASTEXITCODE=0
            Invoke-Mp $forward | ForEach-Object { if ($_ -is [int]) { $script:exitCode=$_ } else { Write-Output $_ } }
        } else { Show-Menu }
    }
} catch { Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red; $exitCode=1 }
finally { Pop-Location }
exit $exitCode
