[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$banner = @'
+---------------------------------------+
|    _    ____ _____ ____      _        |
|   / \  / ___|_   _|  _ \    / \       |
|  / _ \ \___ \ | | | |_) |  / _ \      |
| / ___ \ ___) || | |  _ <  / ___ \     |
|/_/   \_\____/ |_| |_| \_\/_/   \_\    |
|                                       |
|       S O L   O R C H E S T R A T O R |
|      Plan with Sol. Execute with Luna. |
+---------------------------------------+
'@

[Console]::WriteLine($banner)
[Console]::WriteLine('Interactive Codex setup for Windows')

function Read-Confirmation {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [bool]$DefaultYes
    )

    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        [Console]::Write("$Prompt $suffix ")
        $answer = [Console]::In.ReadLine()
        if ($null -eq $answer) {
            throw 'Input ended before setup was complete.'
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            '' { return $DefaultYes }
            default { [Console]::WriteLine('Please answer yes or no.') }
        }
    }
}

function Read-Plan {
    [Console]::WriteLine('Codex plan:')
    [Console]::WriteLine('  1) Pro  - GPT-5.6 Sol orchestrates, GPT-5.6 Luna executes, GPT-5.6 Sol reviews')
    [Console]::WriteLine('  2) Plus - GPT-5.6 Luna (max reasoning) orchestrates, GPT-5.6 Luna executes, GPT-5.6 Sol reviews')

    while ($true) {
        [Console]::Write('Select plan [1/2] (default 1): ')
        $answer = [Console]::In.ReadLine()
        if ($null -eq $answer) {
            throw 'Input ended before setup was complete.'
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            '1' { return 'pro' }
            'pro' { return 'pro' }
            '' { return 'pro' }
            '2' { return 'plus' }
            'plus' { return 'plus' }
            default { [Console]::WriteLine('Please answer 1 (Pro) or 2 (Plus).') }
        }
    }
}

function Read-Scope {
    [Console]::WriteLine('Installation scope:')
    [Console]::WriteLine('  1) Personal/global - available in every project for this user')
    [Console]::WriteLine('  2) Project - install into one repository')

    while ($true) {
        [Console]::Write('Select scope [1/2] (default 1): ')
        $answer = [Console]::In.ReadLine()
        if ($null -eq $answer) {
            throw 'Input ended before setup was complete.'
        }
        switch ($answer.Trim().ToLowerInvariant()) {
            '1' { return 'global' }
            'global' { return 'global' }
            '' { return 'global' }
            '2' { return 'project' }
            'project' { return 'project' }
            default { [Console]::WriteLine('Please answer 1 (global) or 2 (project).') }
        }
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    foreach ($sourceChild in (Get-ChildItem -LiteralPath $Source -Force)) {
        $destinationChildPath = Join-Path $Destination $sourceChild.Name
        $destinationChild = Get-Item -LiteralPath $destinationChildPath -Force -ErrorAction SilentlyContinue

        if ($sourceChild.PSIsContainer) {
            if ($null -eq $destinationChild) {
                New-Item -ItemType Directory -Path $destinationChildPath | Out-Null
            }
            elseif (-not $destinationChild.PSIsContainer) {
                throw "Cannot merge directory over file: $destinationChildPath"
            }

            Copy-DirectoryContents -Source $sourceChild.FullName -Destination $destinationChildPath
        }
        else {
            if (($null -ne $destinationChild) -and $destinationChild.PSIsContainer) {
                throw "Cannot overwrite directory with file: $destinationChildPath"
            }

            Copy-Item -LiteralPath $sourceChild.FullName -Destination $destinationChildPath -Force
        }
    }
}

function Find-ReparsePoint {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    foreach ($child in (Get-ChildItem -LiteralPath $Path -Force)) {
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $child.FullName
        }
        if ($child.PSIsContainer) {
            $nestedLink = Find-ReparsePoint -Path $child.FullName
            if ($null -ne $nestedLink) {
                return $nestedLink
            }
        }
    }

    return $null
}

function Test-DirectoryMergeCompatible {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    foreach ($sourceChild in (Get-ChildItem -LiteralPath $Source -Force)) {
        $destinationChildPath = Join-Path $Destination $sourceChild.Name
        $destinationChild = Get-Item -LiteralPath $destinationChildPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $destinationChild) {
            continue
        }
        if ($sourceChild.PSIsContainer -ne $destinationChild.PSIsContainer) {
            return $false
        }
        if ($sourceChild.PSIsContainer -and (-not (Test-DirectoryMergeCompatible -Source $sourceChild.FullName -Destination $destinationChildPath))) {
            return $false
        }
    }

    return $true
}

function Get-OverwritePaths {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $Source.PSIsContainer) {
        if ($null -ne (Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue)) {
            return $Name
        }
        return
    }

    foreach ($sourceFile in (Get-ChildItem -LiteralPath $Source.FullName -File -Recurse -Force)) {
        $relativePath = $sourceFile.FullName.Substring($Source.FullName.Length + 1)
        $destinationFile = Join-Path $Destination $relativePath
        if ($null -ne (Get-Item -LiteralPath $destinationFile -Force -ErrorAction SilentlyContinue)) {
            $path = $Name + [IO.Path]::DirectorySeparatorChar + $relativePath
            Write-Output $path
        }
    }
}

function Show-OverwriteWarning {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $paths = @(Get-OverwritePaths -Source $Source -Destination $Destination -Name $Name)
    if ($paths.Count -eq 0) {
        return
    }

    [Console]::WriteLine('WARNING: the following existing files will be overwritten:')
    foreach ($path in $paths) {
        [Console]::WriteLine("  - $path")
    }
}

function Install-Component {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TargetDirectory,

        [string]$SourcePath
    )

    if ([string]::IsNullOrEmpty($SourcePath)) {
        $SourcePath = Join-Path $scriptDir $Name
    }
    $sourcePath = $SourcePath
    $destinationPath = Join-Path $TargetDirectory $Name
    $sourceItem = Get-Item -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue
    if ($null -eq $sourceItem) {
        throw "Setup source is missing: $sourcePath"
    }

    $destinationItem = Get-Item -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $destinationItem) {
        if (($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            [Console]::Error.WriteLine("Skipped ${Name}: the existing target is a symbolic link or junction.")
            return $false
        }

        if ($sourceItem.PSIsContainer -and $destinationItem.PSIsContainer) {
            $linkedPath = Find-ReparsePoint -Path $destinationPath
            if ($null -ne $linkedPath) {
                [Console]::Error.WriteLine("Skipped ${Name}: the existing target contains a symbolic link or junction ($linkedPath).")
                return $false
            }
            if (-not (Test-DirectoryMergeCompatible -Source $sourcePath -Destination $destinationPath)) {
                [Console]::Error.WriteLine("Skipped ${Name}: source and target types are incompatible.")
                return $false
            }
        }
        elseif (($sourceItem.PSIsContainer -and (-not $destinationItem.PSIsContainer)) -or ((-not $sourceItem.PSIsContainer) -and $destinationItem.PSIsContainer)) {
            [Console]::Error.WriteLine("Skipped ${Name}: source and target types are incompatible.")
            return $false
        }

        if ($Name -eq 'AGENTS.md') {
            $instructions = [IO.File]::ReadAllText($sourcePath)
            $existing = [IO.File]::ReadAllText($destinationPath)
            if ($existing.Contains('use the `astra-orchestrator` skill')) {
                Copy-Item -LiteralPath $destinationPath -Destination "$destinationPath.backup-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
                $existing = $existing.Replace('astra-orchestrator', 'sol-orchestrator')
                [IO.File]::WriteAllText($destinationPath, $existing, [Text.UTF8Encoding]::new($false))
                [Console]::WriteLine("Migrated legacy Astra skill references in ${Name}.")
            }
            $normalizedInstructions = $instructions.Replace("`r`n", "`n").TrimEnd("`n")
            if ($existing.Replace("`r`n", "`n").Contains($normalizedInstructions)) {
                [Console]::WriteLine("Skipped ${Name}: instructions already present.")
                return $false
            }
            $reader = [IO.StreamReader]::new($destinationPath, [Text.Encoding]::UTF8, $true)
            try {
                $null = $reader.ReadToEnd()
                $encoding = $reader.CurrentEncoding
            }
            finally {
                $reader.Dispose()
            }
            [IO.File]::AppendAllText($destinationPath, "`n`n" + $instructions, $encoding)
            [Console]::WriteLine("Appended instructions to ${Name}. Existing contents preserved.")
            return $true
        }

        Show-OverwriteWarning -Source $sourceItem -Destination $destinationPath -Name $Name

        if (-not (Read-Confirmation -Prompt "Update ${Name}? New files will be added; only paths listed above will be replaced." -DefaultYes $false)) {
            [Console]::WriteLine("Skipped $Name (existing target left unchanged).")
            return $false
        }

        if ($sourceItem.PSIsContainer -and $destinationItem.PSIsContainer) {
            Copy-DirectoryContents -Source $sourcePath -Destination $destinationPath
        }
        elseif ((-not $sourceItem.PSIsContainer) -and (-not $destinationItem.PSIsContainer)) {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }
        else {
            [Console]::Error.WriteLine("Skipped ${Name}: source and target types are incompatible.")
            return $false
        }

        [Console]::WriteLine("Updated $Name.")
        return $true
    }

    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
    [Console]::WriteLine("Installed $Name.")
    return $true
}

function Get-ReparsePointInPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Target
    )

    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $targetPath = [IO.Path]::GetFullPath($Target)
    $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $rootItem = Get-Item -LiteralPath $rootPath -Force -ErrorAction SilentlyContinue
    if (($null -ne $rootItem) -and (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return $rootPath }
    if ([string]::Equals($rootPath, $targetPath, $comparison)) { return $null }
    $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    if (-not $targetPath.StartsWith($prefix, $comparison)) { return $null }

    $current = $rootPath
    $relative = $targetPath.Substring($prefix.Length)
    foreach ($component in $relative.Split([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar), [StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $component
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if (($null -ne $item) -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return $current }
    }
    return $null
}

function Install-GlobalFiles {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    $linkedPath = Get-ReparsePointInPath -Root $DestinationRoot -Target $Destination
    if ($null -ne $linkedPath) {
        [Console]::Error.WriteLine("Skipped ${Label}: destination path contains a symbolic link or junction: $linkedPath")
        return
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    foreach ($sourceFile in (Get-ChildItem -LiteralPath $Source -File -Recurse -Force)) {
        $relativePath = $sourceFile.FullName.Substring($Source.Length + 1)
        $destinationFile = Join-Path $Destination $relativePath
        $linkedPath = Get-ReparsePointInPath -Root $DestinationRoot -Target $destinationFile
        if ($null -ne $linkedPath) {
            [Console]::Error.WriteLine("Skipped managed path: $destinationFile contains symbolic link or junction $linkedPath")
            continue
        }
        $destinationFileItem = Get-Item -LiteralPath $destinationFile -Force -ErrorAction SilentlyContinue

        if (($null -ne $destinationFileItem) -and $destinationFileItem.PSIsContainer) {
            [Console]::Error.WriteLine("Skipped incompatible target: $destinationFile")
            continue
        }
        if (($null -ne $destinationFileItem) -and ((Get-FileHash -LiteralPath $sourceFile.FullName).Hash -eq (Get-FileHash -LiteralPath $destinationFile).Hash)) {
            [Console]::WriteLine("Unchanged $destinationFile")
            continue
        }
        if ($null -ne $destinationFileItem) {
            if (-not (Read-Confirmation -Prompt "Update $destinationFile? A timestamped backup will be created." -DefaultYes $false)) {
                [Console]::WriteLine("Kept existing $destinationFile")
                continue
            }
            $backup = "$destinationFile.backup-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
            Copy-Item -LiteralPath $destinationFile -Destination $backup
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationFile) -Force | Out-Null
        $temporaryFile = "$destinationFile.solsetup-$([Guid]::NewGuid().ToString('N'))"
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $temporaryFile
        Move-Item -LiteralPath $temporaryFile -Destination $destinationFile -Force
        [Console]::WriteLine("Installed $destinationFile")
    }
}

function Archive-LegacySkill {
    param([Parameter(Mandatory)][string]$AgentsHome)

    $legacy = Join-Path $AgentsHome 'skills/astra-orchestrator'
    $linkedPath = Get-ReparsePointInPath -Root $AgentsHome -Target $legacy
    if ($null -ne $linkedPath) {
        [Console]::Error.WriteLine("Legacy skill path contains a symbolic link or junction and was not changed: $linkedPath")
        return
    }
    $legacyItem = Get-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue
    if ($null -eq $legacyItem) { return }
    if (($legacyItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        [Console]::Error.WriteLine("Legacy skill is managed by a symbolic link or junction and was not changed: $legacy")
        return
    }
    if (-not (Read-Confirmation -Prompt 'Archive the legacy astra-orchestrator skill to prevent duplicate matching?' -DefaultYes $true)) {
        [Console]::WriteLine("Kept legacy skill $legacy")
        return
    }
    $backup = Join-Path $AgentsHome "skill-backups/astra-orchestrator-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    Move-Item -LiteralPath $legacy -Destination $backup
    [Console]::WriteLine("Archived legacy skill at $backup")
}

function Merge-GlobalCodexConfig {
    param(
        [Parameter(Mandatory)][string]$Plan,
        [Parameter(Mandatory)][string]$CodexHome
    )

    $destination = Join-Path $CodexHome 'config.toml'
    $linkedPath = Get-ReparsePointInPath -Root $CodexHome -Target $destination
    if ($null -ne $linkedPath) {
        [Console]::Error.WriteLine("Skipped config: destination path contains a symbolic link or junction: $linkedPath")
        return
    }
    $destinationItem = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    if (($null -ne $destinationItem) -and $destinationItem.PSIsContainer) {
        [Console]::Error.WriteLine("Skipped config: target is not a regular file: $destination")
        return
    }

    $rootValues = [ordered]@{}
    $agentValues = [ordered]@{}
    if ($Plan -eq 'pro') {
        $rootValues.model = 'model = "gpt-5.6-sol"'
        $rootValues.model_reasoning_effort = 'model_reasoning_effort = "medium"'
        $agentValues.default_subagent_reasoning_effort = 'default_subagent_reasoning_effort = "max"'
    }
    else {
        $rootValues.model = 'model = "gpt-5.6-luna"'
        $rootValues.model_reasoning_effort = 'model_reasoning_effort = "max"'
        $agentValues.default_subagent_reasoning_effort = 'default_subagent_reasoning_effort = "medium"'
    }
    $agentValues.enabled = 'enabled = true'
    $agentValues.max_concurrent_threads_per_session = 'max_concurrent_threads_per_session = 4'
    $agentValues.default_subagent_model = 'default_subagent_model = "gpt-5.6-luna"'

    $lines = if ($null -eq $destinationItem) { @() } else { [IO.File]::ReadAllLines($destination) }
    for ($lineNumber = 0; $lineNumber -lt $lines.Count; $lineNumber++) {
        $candidate = $lines[$lineNumber]
        if ($candidate.Contains('"""') -or $candidate.Contains("'''")) {
            [Console]::Error.WriteLine("Skipped config: multiline TOML strings require a manual merge: $destination")
            return
        }
        $trimmed = $candidate.TrimStart()
        if (($trimmed.Length -eq 0) -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed.StartsWith('[')) {
            if ($trimmed -notmatch '^\[\[?[^\]]+\]\]?\s*(#.*)?$') {
                [Console]::Error.WriteLine("Skipped config: unsupported TOML table syntax on line $($lineNumber + 1) requires a manual merge: $destination")
                return
            }
            continue
        }
        if ($trimmed -notmatch '^[A-Za-z_][A-Za-z0-9_-]*\s*=') {
            [Console]::Error.WriteLine("Skipped config: unsupported TOML key or continuation on line $($lineNumber + 1) requires a manual merge: $destination")
            return
        }
    }
    $output = [Collections.Generic.List[string]]::new()
    $rootSeen = @{}
    $agentSeen = @{}
    $section = ''
    $rootFinished = $false
    $agentsFound = $false
    $agentsFinished = $false

    $emitRoot = {
        foreach ($key in $rootValues.Keys) {
            if (-not $rootSeen.ContainsKey($key)) { $output.Add($rootValues[$key]) }
        }
        $script:rootFinished = $true
    }
    $emitAgents = {
        foreach ($key in $agentValues.Keys) {
            if (-not $agentSeen.ContainsKey($key)) { $output.Add($agentValues[$key]) }
        }
        $script:agentsFinished = $true
    }

    foreach ($line in $lines) {
        if ($line -match '^\s*\[\[?[^\]]+\]\]?\s*(#.*)?$') {
            if (-not $rootFinished) { & $emitRoot; $rootFinished = $true }
            if (($section -eq 'agents') -and (-not $agentsFinished)) { & $emitAgents; $agentsFinished = $true }
            if ($line -match '^\s*\[\s*agents\s*\]\s*(#.*)?$') {
                if ($agentsFound) { throw "Multiple [agents] sections make a safe merge ambiguous: $destination" }
                $agentsFound = $true
                $section = 'agents'
            }
            else { $section = 'other' }
            $output.Add($line)
            continue
        }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') {
            $key = $Matches[1]
            if (($section -eq '') -and $rootValues.Contains($key)) {
                if ($rootSeen.ContainsKey($key)) { throw "Duplicate global key '$key' makes a safe merge ambiguous: $destination" }
                $rootSeen[$key] = $true
                $output.Add($rootValues[$key])
                continue
            }
            if (($section -eq 'agents') -and $agentValues.Contains($key)) {
                if ($agentSeen.ContainsKey($key)) { throw "Duplicate agents key '$key' makes a safe merge ambiguous: $destination" }
                $agentSeen[$key] = $true
                $output.Add($agentValues[$key])
                continue
            }
        }
        $output.Add($line)
    }
    if (-not $rootFinished) { & $emitRoot; $rootFinished = $true }
    if (($section -eq 'agents') -and (-not $agentsFinished)) { & $emitAgents; $agentsFinished = $true }
    if (-not $agentsFound) {
        if (($output.Count -gt 0) -and ($output[$output.Count - 1] -ne '')) { $output.Add('') }
        $output.Add('[agents]')
        foreach ($key in $agentValues.Keys) { $output.Add($agentValues[$key]) }
    }

    $newContent = [string]::Join("`n", $output) + "`n"
    $oldContent = if ($null -eq $destinationItem) { '' } else { [IO.File]::ReadAllText($destination).Replace("`r`n", "`n") }
    if ($newContent -eq $oldContent) {
        [Console]::WriteLine("Unchanged $destination")
        return
    }
    if ($null -ne $destinationItem) {
        if (-not (Read-Confirmation -Prompt 'Apply this global Codex profile? A timestamped backup will be created.' -DefaultYes $true)) {
            [Console]::WriteLine("Kept existing $destination")
            return
        }
        Copy-Item -LiteralPath $destination -Destination "$destination.backup-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
    }
    New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
    $temporaryFile = "$destination.solsetup-$([Guid]::NewGuid().ToString('N'))"
    [IO.File]::WriteAllText($temporaryFile, $newContent, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryFile -Destination $destination -Force
    [Console]::WriteLine("Merged $Plan profile into $destination")
}

function Install-GlobalInstructions {
    param(
        [Parameter(Mandatory)][string]$CodexHome
    )

    $destination = Join-Path $CodexHome 'AGENTS.md'
    $override = Join-Path $CodexHome 'AGENTS.override.md'
    if ((Test-Path -LiteralPath $override -PathType Leaf) -and ((Get-Item -LiteralPath $override).Length -gt 0)) {
        [Console]::Error.WriteLine("Warning: $override is active and shadows AGENTS.md.")
    }
    $linkedPath = Get-ReparsePointInPath -Root $CodexHome -Target $destination
    $destinationItem = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    if ($null -ne $linkedPath) {
        [Console]::Error.WriteLine("Protected managed instructions: $destination")
        if ([string]::IsNullOrWhiteSpace($env:CODEX_MANAGED_AGENTS_SOURCE)) {
            [Console]::Error.WriteLine('No file was changed. Set CODEX_MANAGED_AGENTS_SOURCE to the declarative source and rerun.')
            [Console]::Error.WriteLine([IO.File]::ReadAllText((Join-Path $scriptDir 'AGENTS.md')))
            return
        }
        $destination = $env:CODEX_MANAGED_AGENTS_SOURCE
        $destinationItem = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    }
    if (($null -ne $destinationItem) -and ((($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $destinationItem.PSIsContainer)) {
        [Console]::Error.WriteLine("Skipped instructions: target must be a regular, unmanaged file: $destination")
        return
    }
    $instructions = [IO.File]::ReadAllText((Join-Path $scriptDir 'AGENTS.md'))
    if (($null -ne $destinationItem) -and [IO.File]::ReadAllText($destination).Contains('use the `astra-orchestrator` skill')) {
        Copy-Item -LiteralPath $destination -Destination "$destination.backup-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
        $migrated = [IO.File]::ReadAllText($destination).Replace('astra-orchestrator', 'sol-orchestrator')
        [IO.File]::WriteAllText($destination, $migrated, [Text.UTF8Encoding]::new($false))
        [Console]::WriteLine("Migrated legacy Astra skill references in $destination")
        return
    }
    if (($null -ne $destinationItem) -and [IO.File]::ReadAllText($destination).Contains('use the `sol-orchestrator` skill')) {
        [Console]::WriteLine("Unchanged $destination")
        return
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    if ($null -ne $destinationItem) {
        Copy-Item -LiteralPath $destination -Destination "$destination.backup-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
        [IO.File]::AppendAllText($destination, "`n`n" + $instructions, [Text.UTF8Encoding]::new($false))
    }
    else {
        [IO.File]::WriteAllText($destination, $instructions, [Text.UTF8Encoding]::new($false))
    }
    [Console]::WriteLine("Installed global instructions in $destination")
}

try {
    $scope = Read-Scope
    $plan = Read-Plan
    $profileDirectory = Join-Path $scriptDir "profiles/$plan"

    if ($scope -eq 'global') {
        $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $HOME '.codex' } else { $env:CODEX_HOME }
        $agentsHome = if ([string]::IsNullOrWhiteSpace($env:AGENTS_HOME)) { Join-Path $HOME '.agents' } else { $env:AGENTS_HOME }
        [Console]::WriteLine("Global Codex home: $codexHome")
        [Console]::WriteLine("Global skills home: $agentsHome")

        if (Read-Confirmation -Prompt 'Install or update the five global custom agents?' -DefaultYes $true) {
            Install-GlobalFiles -Label 'custom agents' -Source (Join-Path $profileDirectory 'codex/agents') -Destination (Join-Path $codexHome 'agents') -DestinationRoot $codexHome
        }
        if (Read-Confirmation -Prompt 'Install or update the global sol-orchestrator skill?' -DefaultYes $true) {
            Install-GlobalFiles -Label 'sol-orchestrator skill' -Source (Join-Path $profileDirectory 'agents/skills/sol-orchestrator') -Destination (Join-Path $agentsHome 'skills/sol-orchestrator') -DestinationRoot $agentsHome
            Archive-LegacySkill -AgentsHome $agentsHome
        }
        if (Read-Confirmation -Prompt 'Merge the selected profile into the global Codex config?' -DefaultYes $true) {
            Merge-GlobalCodexConfig -Plan $plan -CodexHome $codexHome
        }
        if (Read-Confirmation -Prompt 'Add the orchestration policy to global Codex instructions?' -DefaultYes $true) {
            Install-GlobalInstructions -CodexHome $codexHome
        }
        [Console]::WriteLine("Global setup complete (plan: $plan). Start a new Codex session to load it.")
        exit 0
    }

    [Console]::Write('Target repository path: ')
    $targetPath = [Console]::In.ReadLine()
    if ($null -eq $targetPath) { throw 'Input ended before a target repository was provided.' }
    if ([string]::IsNullOrWhiteSpace($targetPath)) { throw 'Target repository path cannot be empty.' }
    $targetItem = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
    if (($null -eq $targetItem) -or (-not $targetItem.PSIsContainer)) { throw "Target must be an existing directory: $targetPath" }
    $targetDirectory = $targetItem.FullName
    if ([string]::Equals($targetDirectory, $scriptDir, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Target repository must be different from the setup source directory.'
    }

    $installed = 0
    foreach ($component in '.codex', '.agents', 'AGENTS.md') {
        if (Read-Confirmation -Prompt "Install $component?" -DefaultYes $true) {
            $result = if ($component -eq '.codex') {
                Install-Component -Name $component -TargetDirectory $targetDirectory -SourcePath (Join-Path $profileDirectory 'codex')
            }
            elseif ($component -eq '.agents') {
                Install-Component -Name $component -TargetDirectory $targetDirectory -SourcePath (Join-Path $profileDirectory 'agents')
            }
            else {
                Install-Component -Name $component -TargetDirectory $targetDirectory
            }
            if ($result) { $installed++ }
        }
        else {
            [Console]::WriteLine("Skipped $component.")
        }
    }

    Archive-LegacySkill -AgentsHome (Join-Path $targetDirectory '.agents')

    [Console]::WriteLine()
    [Console]::WriteLine("Setup complete. $installed component(s) installed in $targetDirectory (plan: $plan).")
    [Console]::WriteLine('See guides/ for optional Codex model and Fast-mode configurations.')
}
catch {
    [Console]::Error.WriteLine("Setup cancelled: $($_.Exception.Message)")
    exit 1
}
