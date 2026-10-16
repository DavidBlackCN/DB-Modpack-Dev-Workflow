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
function Confirm-Action([string] $Prompt) {
    while ($true) {
        $answer=Read-Choice "$Prompt [y/N，d 查看详细输出]"
        if ($answer -eq 'd') { Write-Host $script:LastResult.Raw; continue }
        return $answer -ceq 'y'
    }
}
# Redirected input accepts key names, keeping the same state machine testable without a terminal.
function Read-SelectionKey {
    if ([Console]::IsInputRedirected) {
        $key=Read-Choice '按键（up/down/space/a/n/enter/esc）'
        if ($key -eq '') { return 'enter' }; return $key.ToLowerInvariant()
    }
    switch ([Console]::ReadKey($true).Key) {
        UpArrow { 'up' }; DownArrow { 'down' }; Spacebar { 'space' }
        A { 'a' }; N { 'n' }; Enter { 'enter' }; Escape { 'esc' }
    }
}
function Select-Multiple($Items, [string] $Label) {
    $Items=@($Items)
    if (-not $Items.Count) { Write-Host 'ℹ️ 没有可选文件。'; return ,@() }
    $selected=[bool[]]::new($Items.Count); $cursor=0
    while ($true) {
        if (-not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected) { Clear-Host }
        Show-Page $Label '↑ / ↓ 移动 · Space 选择 · A 全选 · N 全不选 · Enter 确认 · Esc 返回'
        Write-Host "  已选择 $(@($selected | Where-Object { $_ }).Count) / $($Items.Count)"
        $pageSize=12
        if (-not [Console]::IsOutputRedirected) { $pageSize=[Math]::Max(1,[Math]::Min(12,[Console]::WindowHeight-16)) }
        $start=[Math]::Max(0,$cursor-[int][Math]::Floor($pageSize/2)); $end=[Math]::Min($Items.Count,$start+$pageSize)
        for ($i=$start; $i -lt $end; $i++) {
            $mark=if ($selected[$i]) { 'x' } else { ' ' }
            $arrow=if ($cursor -eq $i) { '›' } else { ' ' }
            Write-Host "  $arrow [$mark] $(Format-DisplayPath $Items[$i].path)"
        }
        Write-Host "  第 $($cursor+1) / $($Items.Count) 项" -ForegroundColor DarkGray
        switch (Read-SelectionKey) {
            'up' { $cursor=[Math]::Max(0,$cursor-1) }
            'down' { $cursor=[Math]::Min($Items.Count-1,$cursor+1) }
            'space' { $selected[$cursor]=-not $selected[$cursor] }
            'a' { for ($i=0; $i -lt $selected.Length; $i++) { $selected[$i]=$true } }
            'n' { [Array]::Clear($selected,0,$selected.Length) }
            'esc' { throw '已取消。' }
            'enter' { return ,@((0..($Items.Count-1)) | Where-Object { $selected[$_] } | ForEach-Object { $Items[$_] }) }
        }
    }
}
function Pause-ForContinue {
    while ((Read-Choice '按 Enter 继续') -ne '') { Write-Host '请直接按 Enter 返回菜单。' -ForegroundColor DarkGray }
}
function Invoke-MenuOperation([scriptblock] $Action, [switch] $KeepDetails) {
    if (-not $KeepDetails) { $script:LastResult=$null }
    $script:OperationWarning=$false
    try {
        & $Action
        if ($script:OperationWarning) { Write-Host "`n⚠️ 操作结束，请查看上方提示。" -ForegroundColor Yellow }
        else { Write-Host "`n✅ 操作结束。" -ForegroundColor Green }
    }
    catch {
        if ($_.Exception.Message -eq '已取消。') { Write-Host "`nℹ️ 已取消操作。" -ForegroundColor Yellow }
        else { Save-Details $_.Exception.Message; Write-Host "`n❌ $($_.Exception.Message)" -ForegroundColor Red }
    }
    finally { Pause-ForContinue }
}
function Format-DisplayPath([string] $Value) {
    if ($Value.StartsWith($PSScriptRoot + [IO.Path]::DirectorySeparatorChar)) { $Value='.' + $Value.Substring($PSScriptRoot.Length) }
    $Value=$Value.Replace("`r",'␍').Replace("`n",'␊').Replace("`t",'⇥')
    if ($Value.Length -gt 100) { return $Value.Substring(0,35)+'…'+$Value.Substring($Value.Length-60) }
    return $Value
}
function Read-RuntimeId {
    while ($true) {
        $value=Read-Required '实例名称，例如 pcl2-debug / hmcl-dev / pcl2-fabric-1211'
        if ($value -cmatch '^[a-z0-9][a-z0-9_-]*$') { return $value }
        Write-Host '⚠️ 实例名称须以小写字母或数字开头，仅允许小写字母、数字、-、_；不能含句点。示例：pcl2-debug、hmcl-dev、pcl2-fabric-1211。' -ForegroundColor Yellow
    }
}
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
    if ($Result.Code -ne 0) {
        $message=@($Result.Messages | Where-Object { $_ }) | Select-Object -Last 1
        if ($message) { Write-Host (Format-DisplayPath $message) -ForegroundColor Red }
    }
    foreach ($record in $Result.Records) {
        if ($record -isnot [System.Collections.IDictionary]) { continue }
        if ($record.output) {
            Write-Host "目标: $($record.target)`n输出: $(Format-DisplayPath $record.output)"
            foreach ($artifact in $record.artifacts) { Write-Host "  $($artifact.kind): $($artifact.name)" }
            Write-Host "报告: $(Format-DisplayPath (Join-Path $record.output 'build-report.json'))"
        } elseif ($record.action -eq 'bind') {
            $r = $record.runtime
            Write-Host "实例: $($r.id) / $($r.targetId) / $($r.launcher)"
            Write-Host "游戏目录: $(Format-DisplayPath $r.gameDir)`n版本目录: $(Format-DisplayPath $r.versionDir)`nMinecraft: $($r.mc)"
            Write-Host "加载器: $(ConvertTo-Json $r.loaders -Compress) | 隔离: $($r.layout)"
            Write-Host $r.evidence
            Write-Host "现有 Mod/配置: $(@($record.existing).Count) 个（不自动接管）"
        } elseif ($record.action -eq 'apply') {
            Write-Host "目标: $($record.target) | 包版本: $($record.version) | 来源: $($record.provenance.kind)"
        } elseif ($record.action -eq 'import-deps') {
            Write-Host "待识别 JAR: $(@($record.candidates).Count) | 已跳过: $(@($record.skipped).Count)"
        } elseif ($record.Contains('managed')) {
            $labels=@{managed='受管文件';conflicts='冲突';candidates='新增配置';dependencies='Mod 变化'}
            foreach ($key in @('managed','conflicts','candidates','dependencies')) {
                Write-Host "$($labels[$key]) : $(@($record[$key]).Count)"
            }
            if (@($record.conflicts).Count) { $script:OperationWarning=$true }
        } elseif ($record.Contains('actions')) {
            Write-Host "文件变更: $(@($record.actions).Count) | 冲突: $(@($record.conflicts).Count)"
            if (@($record.conflicts).Count) { $script:OperationWarning=$true }
            Write-Host "保留未知文件: $(@($record.preserved).Count) | 待下载: $(@($record.downloads).Count)"
        } elseif ($record.projectPath) {
            Write-Host "待接受依赖: $($record.operation) $($record.project) | 新增项目: $(@($record.added).Count)"
            foreach ($item in $record.added) {
                Write-Host "  ➕ $($item.name.Values -join ' / ')（$($item.slug.Values -join ' / ')）"
                foreach ($file in $item.files) { Write-Host "     文件: $($file.name) | 平台版本 ID: $($file.id)" }
            }
            Write-Host '输入 d 可查看完整候选与锁文件差异。' -ForegroundColor DarkGray
        } elseif ($record.Contains('gitDirty')) {
            Write-Host "Target: $($record.selected) | Git dirty: $($record.gitDirty)"
            foreach ($r in $record.runtimes) { Write-Host "  $($r.runtime) / $($r.targetId) 待回收: $(@($r.pendingCollect).Count) 冲突: $($r.conflicts) $($r.error)" }
        } elseif ($record.Contains('bindings')) {
            foreach ($r in $record.bindings) { Write-Host "  $($r.id) / $($r.targetId) / $($r.launcher) / $(Format-DisplayPath $r.gameDir)" }
            if (-not $record.bindings.Count) { Write-Host '未绑定' }
        } elseif ($record.directory) {
            Write-Host "目标: $($record.target) | 准备文件: $(@($record.files).Count)"
        } else {
            foreach ($key in @('check','target','applied','adopted','unchanged','recovery','restored','collected','backup','notice','retained','node','pnpm','java','git','pakku')) {
                if ($record.Contains($key)) { Write-Host "$key : $($record[$key])" }
            }
        }
    }
}
function Run-Mp([string[]] $Arguments) {
    Write-Host "⏳ 执行: $($Arguments[0])" -ForegroundColor Cyan
    $result = Invoke-Mp $Arguments -Capture
    Save-Details $result.Raw
    Show-Summary $result
    if ($result.Code -ne 0) { throw "命令失败（退出码 $($result.Code)）。按 d 可查看完整日志。" }
    return $result
}
function Save-Details([string] $Text) {
    $script:LastResult=@{Raw=(@($script:LastResult.Raw,$Text) | Where-Object { $_ }) -join "`n"}
}
function Query-Mp([string[]] $Arguments) {
    $result = Invoke-Mp $Arguments -Capture
    if ($result.Code -ne 0) { $script:LastResult=$result; Show-Summary $result; throw '无法读取状态，请使用项目与环境检查。' }
    if (-not $result.Records.Count) { throw 'CLI 未返回可读取的状态。' }
    return $result.Records[-1]
}
function Refresh-Selection {
    $script:State = Query-Mp @('status','--light','--json')
    $script:Targets = @($script:State.targets)
    $script:Bindings = @($script:State.bindings)
    $script:TargetChoice = $script:State.selected
    $available = @($script:Bindings | Where-Object targetId -EQ $script:TargetChoice)
    if ($script:RuntimeChoice -notin @($available.id)) { $script:RuntimeChoice = $null }
    if (-not $script:RuntimeChoice -and $available.Count -eq 1) { $script:RuntimeChoice = $available[0].id }
}
function Choose-Item($Items, [string] $Label) {
    if (-not $Items.Count) { throw "没有可选的 $Label。" }
    while ($true) {
        Show-Page "📋 选择 $Label"
        for ($i=0; $i -lt $Items.Count; $i++) { Write-Host "  [$($i+1)] 📦 $($Items[$i].id)  $($Items[$i].launcher)" }
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
    if ($id) { $null=Run-Mp @('use',$id); Refresh-Selection; Write-Host "🎯 当前目标: $id" }
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
    if ($id) { $script:RuntimeChoice=$id; Write-Host "🎮 当前实例: $id | 启动器: $(($available | Where-Object id -EQ $id).launcher)" }
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
    } elseif ($Choice -eq '6') {
        $forward=Runtime-Arguments 'deps-review'
        $operation=Read-Required '候选操作 add 或 remove'
        if ($operation -notin @('add','remove')) { throw '仅支持 add 或 remove。' }
        $project=Read-Required '已核实来源的项目 ID / slug'
        if (-not (Confirm-Action '生成完整 Pakku 候选副本（可能联网并写入 .work）？')) { return }
        $result=Run-Mp ($forward+@('--operation',$operation,'--project',$project))
        $candidate=$result.Records | Where-Object { $_.projectPath } | Select-Object -Last 1
        if (-not $candidate) { throw '没有可接受的候选。' }
        if (Confirm-Action '接受此候选写入正式源？输入 d 可审查锁文件差异') {
            $null=Run-Mp ((Runtime-Arguments 'deps-accept')+@('--candidate',$candidate.id,'--accept-hash',$candidate.hash,'--confirm'))
        }
    } elseif ($Choice -eq '7') {
        $forward=Runtime-Arguments 'restore-deps'
        $file=Read-Choice '可选：额外/禁用 JAR 的相对路径（留空只恢复受管依赖，0 取消）'
        if ($file -eq '0') { return }; if ($file) { $forward+=@('--file',$file) }
        $null=Run-Mp $forward
        if (Confirm-Stopped) { $null=Run-Mp ($forward+@('--confirm','--stopped')) }
    } elseif ($Choice -eq '8') {
        $forward=Runtime-Arguments 'import-deps'
        $result=Run-Mp ($forward+@('--json'))
        $report=$result.Records[-1]
        if (-not $report.candidates.Count) { Write-Host 'ℹ️ 没有需要识别的新增 JAR。'; return }
        $items=Select-Multiple $report.candidates '📥 选择要导入的依赖'
        $completed=0; $skipped=0
        try {
            foreach ($item in $items) {
                Write-Host "📦 识别: $(Format-DisplayPath $item.path)"
                if (-not (Confirm-Action '使用 Pakku 联网识别此文件并生成临时候选？正式源暂不修改')) { $skipped++; continue }
                # Generate against the latest source after each acceptance; never reuse stale candidates.
                $result=Run-Mp ($forward+@('--file',$item.path,'--sha256',$item.hash,'--json'))
                $candidate=$result.Records[-1]
                if (-not $candidate.projectPath -or -not $candidate.hash) { throw '未生成有效导入候选。' }
                if (Confirm-Action '确认新增依赖及许可，将此候选导入项目？可输入 d 审查差异') {
                    $null=Run-Mp ($forward+@('--candidate',$candidate.id,'--accept-hash',$candidate.hash,'--confirm','--json'))
                    $completed++
                } else { $skipped++ }
            }
        } finally {
            Write-Host "📥 导入完成 $completed / $($items.Count) 项，跳过 $skipped 项。已完成项保留，可用 git diff 检查。"
        }
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
    $name=Read-RuntimeId
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
    if ($Choice -eq '1') { $null=Run-Mp ((Runtime-Arguments 'changes')+@('--json')); return }
    $result=Run-Mp ($forward+@('--json'))
    $report=$result.Records[-1]
    if ($Choice -eq '5') { Show-Rows $report.dependencies; return }
    if ($Choice -eq '4') { foreach ($item in $report.candidates) { Write-Host (Format-DisplayPath $item.path) }; return }
    $items=@($report.managed)+@($report.candidates)
    if ($Choice -eq '2') {
        $file=Read-Required '要查看的相对路径，例如 config/example.json'
        $item=$items | Where-Object path -CEQ $file | Select-Object -First 1
        if (-not $item) { throw '该路径不在配置变更或新增候选中。' }
        Write-Host ($item.diff.text ?? $item.diff.description ?? '文件无文本差异。'); return
    }
    Write-Host '仅列出可回收文件；冲突需要先人工合并，二进制文件不自动回收。'
    $selected=Select-Multiple @($items | Where-Object { $_.state -in @('runtime-only','candidate') -and -not $_.binary -and -not $_.diff.binary }) '📥 选择要回收的配置'
    $completed=0
    try {
        foreach ($item in $selected) {
            $file=$item.path; $writeArgs=$forward+@('--file',$file)
            Write-Host "📄 $(Format-DisplayPath $file) → $(Format-DisplayPath $item.source) | $($item.state)"
            if ($item.state -eq 'candidate') {
                Write-Host "  [1] 🖥️ 客户端覆盖`n  [2] 📦 公共覆盖`n  [0] ↩️ 跳过此文件"
                $location=Read-Choice '选择新增配置来源'
                if ($location -eq '0') { continue }
                $prefix=@{'1'='.pakku/client-overrides/';'2'='.pakku/overrides/'}[$location]
                if (-not $prefix) { throw '来源选择无效。' }
                $writeArgs+=@('--source',($prefix+$file)); Write-Host "写入源位置: $(Format-DisplayPath ($prefix+$file))"
            } elseif ($null -eq $item.runtime) {
                if (-not (Confirm-Action "单独确认删除正式源文件 $($item.source)？")) { continue }
                $writeArgs+='--delete'
            }
            if (Confirm-Stopped) { $null=Run-Mp ($writeArgs+@('--confirm','--stopped')); $completed++ }
        }
    } finally { Write-Host "📥 回收完成 $completed / $($selected.Count) 项。已完成项保留，可用 git diff 检查。" }
}
function Invoke-Builds([string] $Choice) {
    if ($Choice -eq '2') { Refresh-Selection } else { Require-Target }
    if ($Choice -eq '3') {
        $directory=Join-Path $PSScriptRoot "dist/$script:TargetChoice"
        $latest=Get-ChildItem -LiteralPath $directory -Filter build-report.json -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) { $script:OperationWarning=$true; Write-Host '⚠️ 当前目标还没有本地构建结果。' -ForegroundColor Yellow; return }
        $report=Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json -AsHashtable
        $report.output=$latest.DirectoryName; $report.target=$report.targetId
        Save-Details ($report | ConvertTo-Json -Depth 20)
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
        '4' { @('bootstrap') }
        '5' { @('status','--json') }
    }
    if ($forward) { $null=Run-Mp $forward }
}
# Capture NUL-delimited Git output without PowerShell's line conversion.
function Read-Git([string[]] $Arguments) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    # -CommandType may return several PATH matches; ProcessStartInfo needs one executable.
    $start.FileName=(Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $start.WorkingDirectory=$PSScriptRoot; $start.UseShellExecute=$false
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $start.StandardOutputEncoding=[Text.Encoding]::UTF8
    foreach ($arg in $Arguments) { $start.ArgumentList.Add($arg) }
    $process=[Diagnostics.Process]::Start($start)
    try {
        $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit(); $output=$outTask.GetAwaiter().GetResult(); $errorText=$errTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { Save-Details $errorText; throw "Git 失败：$(Format-DisplayPath $errorText)" }
        return $output
    } finally { $process.Dispose() }
}
function Read-GitFiles {
    $raw=Read-Git @('status','--porcelain=v1','-z','--untracked-files=all')
    $parts=$raw.Split([char]0); $items=@()
    for ($i=0; $i -lt $parts.Length; $i++) {
        if (-not $parts[$i]) { continue }
        $state=$parts[$i].Substring(0,2); $name=$parts[$i].Substring(3); $paths=@($name)
        if ($state -match '[RC]') { $paths+= $parts[++$i] }
        if ($state -match 'U' -or $state -in @('AA','DD')) { throw '存在未解决的 Git 合并冲突，请先在编辑器中处理。' }
        $items+=@{path=$name;paths=$paths;state=$state;staged=($state[0] -notin @(' ','?'))}
    }
    return ,$items
}
function Invoke-Git([string] $Choice) {
    if ($Choice -eq '4') {
        $output=@(& $script:Pnpm.Source run lint:commits 2>&1); Save-Details ($output -join "`n")
        if ($LASTEXITCODE -ne 0) { throw '提交信息校验失败，按 d 查看详情。' }
        Write-Host '✅ 提交信息校验通过。'; return
    }
    if ($Choice -eq '2') {
        Save-Details (Read-Git @('--no-pager','diff','--no-ext-diff'))
        Save-Details (Read-Git @('--no-pager','diff','--cached','--no-ext-diff'))
        Write-Host (Read-Git @('diff','--stat')); Write-Host (Read-Git @('diff','--cached','--stat'))
        Write-Host '📄 完整差异已保留，返回后按 d 查看。'; return
    }
    $items=Read-GitFiles
    Save-Details ($items | ConvertTo-Json -Depth 5)
    if ($Choice -eq '1') {
        Write-Host "🌿 变化文件: $($items.Count) | 已暂存: $(@($items | Where-Object staged).Count)"
        foreach ($item in $items) { Write-Host "  $($item.state) $(Format-DisplayPath $item.path)" }; return
    }
    $selected=Select-Multiple $items '🌿 选择需要暂存的文件（包含该文件全部修改）'
    if (-not $selected.Count) { Write-Host 'ℹ️ 未选择文件，暂存区保持原样。'; return }
    $paths=@($selected | ForEach-Object { $_.paths })
    if ($Choice -eq '3' -and @($items | Where-Object { $_.staged -and $_.path -cnotin $selected.path }).Count) {
        throw '暂存区包含未选中的文件。请一并选择，或先在编辑器中调整暂存区；本次未暂存或提交。'
    }
    # Already-staged deletions/renames have no old index path left for git add.
    $stagePaths=@($selected | Where-Object { $_.state[1] -ne ' ' } | ForEach-Object { $_.path })
    # Literal pathspecs and NUL records preserve spaces, Unicode and special filenames.
    $pathFile=Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    try {
        if ($stagePaths.Count) {
            [IO.File]::WriteAllText($pathFile,($stagePaths -join [char]0)+[char]0,[Text.UTF8Encoding]::new($false))
            $null=Read-Git @('--literal-pathspecs','add',"--pathspec-from-file=$pathFile",'--pathspec-file-nul')
        }
    } finally { Remove-Item -LiteralPath $pathFile -Force -ErrorAction SilentlyContinue }
    Write-Host "✅ 已暂存 $($selected.Count) 个文件。"
    Save-Details (Read-Git @('--no-pager','diff','--cached','--no-ext-diff'))
    if ($Choice -eq '3') {
        # Recheck the index before opening cz-git; preserve any unrelated staged work.
        $staged=@((Read-Git @('diff','--cached','--name-only','--no-renames','-z')).Split([char]0) | Where-Object { $_ })
        if (@($staged | Where-Object { $_ -cnotin $paths }).Count) { throw '暂存区出现未选择的文件，已停止提交。请检查 Git 状态。' }
        if (-not $staged.Count) { Write-Host 'ℹ️ 没有需要提交的变化。'; return }
        & $script:Pnpm.Source run commit
        if ($LASTEXITCODE -ne 0) { throw '提交未完成，已暂存文件保留。' }
    }
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
    $launcher=($script:Bindings | Where-Object id -EQ $script:RuntimeChoice | Select-Object -First 1).launcher
    Write-Host "  🕹️ 启动器  $($launcher ?? '未选择')"
    Write-Host "  🌿 Git   $gitState"
    if ($Description) { Write-Host "`n  $Description" -ForegroundColor DarkGray }
    Write-Host ''
}
function Show-Menu {
    $titles=@('🏠 主菜单','🚀 开发测试','🧩 Mod / 依赖管理','🎮 启动器实例管理','📥 查看与回收游戏修改','📦 构建整合包','📲 应用 CI / Release 构建','🔍 项目与环境检查','🌿 Git 提交','🛠️ Pakku 高级操作')
    $hints=@('输入编号进入功能页。','先预览变化，再确认部署；游戏须保持关闭。','由 Pakku 管理依赖；修改后可检查差异。','绑定启动器已有实例，按目标选择测试实例。','先查看差异，再逐个回收配置文件。','构建结果保存在 dist/，可查看最近一次输出。','先预览包来源与变化，再确认写入实例。','检查源工程、工具环境和当前状态。','先暂存需要提交的文件，再打开规范提交菜单。')
    $menus=@{
        '1'=@('🚀 部署到当前实例','👀 准备并预览部署变化','🎮 切换测试实例','🎯 切换目标','🛟 恢复失败部署（Recover）')
        '2'=@('➕ 添加 Mod','➖ 删除 Mod','🔄 更新指定 Mod','🔄 更新全部 Mod','📋 查看 Mod 列表','🔎 按项目 ID 审查依赖增删','↩️ 恢复实例中的正式依赖','📥 从实例导入新增依赖')
        '3'=@('📋 查看已绑定实例','🔗 绑定 PCL2 实例','🔗 绑定 HMCL 实例','🎮 切换当前实例','🔓 解除绑定')
        '4'=@('📋 查看全部变化','🔎 查看指定配置差异','📥 选择配置并回收','🆕 审查新增配置候选','🧩 查看依赖偏离')
        '5'=@('📦 构建当前目标','📦 构建所有目标','📂 查看最近构建结果')
        '6'=@('📂 应用本地 MRPACK','⚙️ 应用 GitHub Actions Run','🏷️ 应用 GitHub Release')
        '7'=@('🔍 检查当前目标','🔍 检查全部目标','🩺 环境诊断','📥 安装 / 校验 Pakku','📋 查看工作区状态')
        '8'=@('🌿 查看 Git 状态','🔎 查看 Git Diff','📝 选择文件并提交','✅ 校验提交信息','📥 选择文件并暂存')
    }
    $section=''
    $refresh=$true
    while ($true) {
        if ($refresh) {
            try { Refresh-Selection } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
            $refresh=$false
        }
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
        Write-Host "`n  [r] 🔄 刷新目标、实例与 Git 状态" -ForegroundColor DarkGray
        Write-Host '  [d] 📄 查看上次操作的完整输出' -ForegroundColor DarkGray
        $backLabel=if ($section) { '返回上一级' } else { '退出' }
        Write-Host "  [0] ↩️ $backLabel`n" -ForegroundColor DarkGray
        $choice=Read-Choice '请选择'
        if ($choice -eq '0') { if (-not $section) { return }; $section=''; continue }
        if ($choice -eq 'r') { $refresh=$true; continue }
        if ($choice -eq 'd') { Invoke-MenuOperation -KeepDetails { Write-Host ($script:LastResult.Raw ?? '暂无操作输出。') }; continue }
        try {
            if (-not $section) {
                if ($choice -eq '9') { $refresh=$true; Invoke-MenuOperation { Invoke-Advanced } }
                elseif ($menus.ContainsKey($choice)) { $section=$choice }
                else { Write-Host '请输入菜单编号。' -ForegroundColor Yellow }
                continue
            }
            $number=0
            if (-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $menus[$section].Count) { Write-Host '请输入菜单编号。' -ForegroundColor Yellow; continue }
            $refresh=$true
            Invoke-MenuOperation { switch ($section) {
                '1' { Invoke-Development $choice }; '2' { Invoke-Mods $choice }; '3' { Invoke-Runtimes $choice }
                '4' { Invoke-Collect $choice }; '5' { Invoke-Builds $choice }; '6' { Invoke-Apply $choice }
                '7' { Invoke-Checks $choice }; '8' { Invoke-Git $choice }
            } }
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
