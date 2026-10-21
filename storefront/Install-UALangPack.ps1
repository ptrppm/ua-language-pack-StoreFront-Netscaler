<#
.SYNOPSIS
    Ukrainian language pack for Citrix StoreFront: install, uninstall, status.

.DESCRIPTION
    Finds every Receiver for Web site (a folder with custom\script.js) and every
    authentication service (a folder with App_Data\resources\*.resx) under -CitrixRoot.
    Backs up everything it changes, copies the pack files and appends one marked
    loader block to custom\script.js - existing customizations in script.js are kept.

    Petro Pikulin, petr.pikulin@gmail.com, https://t.me/UA_Language_pack_Citrix

.EXAMPLE
    .\Install-UALangPack.ps1                  # install on this server
.EXAMPLE
    .\Install-UALangPack.ps1 -WhatIf          # show what would change, change nothing
.EXAMPLE
    .\Install-UALangPack.ps1 -Status
.EXAMPLE
    .\Install-UALangPack.ps1 -Uninstall
.EXAMPLE
    .\Install-UALangPack.ps1 -RecycleAuthPool # install and make the logon form pick up the translation
.EXAMPLE
    .\Install-UALangPack.ps1 -Propagate       # install, then push to the server group
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Uninstall', Mandatory)]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = 'Status', Mandatory)]
    [switch]$Status,

    # Folder that holds the StoreFront IIS applications (StoreWeb, StoreAuth, ...)
    [string]$CitrixRoot = "$env:SystemDrive\inetpub\wwwroot\Citrix",

    [string]$BackupRoot = "$env:ProgramData\UA_LangPack\backup",

    # Publish-STFServerGroupConfiguration after the change
    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [switch]$Propagate,

    # Recycle the IIS pool of the authentication services after .resx changes - the service
    # reads them only at start. Users who are typing their password at that moment retry the logon;
    # sessions in Receiver for Web are not affected.
    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [switch]$RecycleAuthPool
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$Pack          = $PSScriptRoot
$WebFiles      = 'culture.uk.js', 'wrstrings.uk.js'   # always ours, overwritten on install
$CustomStrings = 'strings.uk.js'                      # admin's own strings: copied only if absent
$Begin         = '// UA_LANGPACK BEGIN - Ukrainian language pack, do not edit this block'
$End           = '// UA_LANGPACK END'
# A <script src> tag, not $.ctxsAjax: StoreFront 2507+ sends CSP script-src 'self', which blocks
# jQuery's eval of an ajax-loaded script. script.js is itself loaded with document.write while the
# page is parsing, so document.write keeps the order; createElement is the fallback if it is not.
$Loader        = @(
    $Begin
    '(function () {'
    "    var src = 'custom/culture.uk.js';"
    "    if (document.readyState === 'loading') {"
    "        document.write('<script src=`"' + src + '`"><\/script>');"
    '    } else {'
    "        var s = document.createElement('script');"
    '        s.src = src;'
    '        document.head.appendChild(s);'
    '    }'
    '})();'
    $End
) -join "`r`n"

$script:Session = $null   # backup folder of this run, created on first use
$script:Changed = 0
$script:ResxChanged = $false

function Write-Step([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

function Get-FileHashOrNull([string]$Path) {
    if (Test-Path -LiteralPath $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } else { $null }
}

function Backup-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not $script:Session) {
        $script:Session = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    }
    $relative = $Path.Substring($CitrixRoot.TrimEnd('\').Length).TrimStart('\')
    $target = Join-Path $script:Session $relative
    if ($PSCmdlet.ShouldProcess($Path, "Back up to $target")) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $Path -Destination $target -Force
    }
}

function Copy-PackFile([string]$Source, [string]$Target) {
    if ((Get-FileHashOrNull $Source) -eq (Get-FileHashOrNull $Target)) { return }
    Backup-File $Target
    if ($PSCmdlet.ShouldProcess($Target, 'Copy pack file')) {
        Copy-Item -LiteralPath $Source -Destination $Target -Force
    }
    Write-Step "    copied   $(Split-Path $Target -Leaf)"
    $script:Changed++
}

# script.js is read and written as bytes + UTF-8 so the original BOM and line endings stay as they were
function Read-Text([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($bom) { 3 } else { 0 }
    [pscustomobject]@{ Text = [Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset); Bom = $bom }
}

function Write-Text([string]$Path, [string]$Text, [bool]$Bom) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($Bom)))
}

function Get-ScriptState([string]$ScriptJs) {
    if (-not (Test-Path -LiteralPath $ScriptJs)) { return 'missing' }
    $text = (Read-Text $ScriptJs).Text
    if ($text.Contains($Begin)) { return 'installed' }
    if ($text -match "custom/culture\.uk\.js") { return 'legacy' }    # v1.x replaced the whole script.js
    return 'none'
}

# Folders under $CitrixRoot that IIS actually serves. Leftovers of deleted stores stay on disk
# but are no IIS applications, so they are skipped. Without the IIS module: every folder.
function Get-AppFolders {
    $all = Get-ChildItem -LiteralPath $CitrixRoot -Directory
    # read-only IIS queries; the module runs Set-Item internally, keep -WhatIf from echoing that
    $keep = $WhatIfPreference; $WhatIfPreference = $false
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $served = @(Get-WebApplication | ForEach-Object {
            [Environment]::ExpandEnvironmentVariables($_.PhysicalPath).TrimEnd('\').ToLowerInvariant()
        })
    } catch {
        Write-Step 'IIS module not available - checking every folder' 'Yellow'
        return $all
    } finally {
        $WhatIfPreference = $keep
    }
    foreach ($d in $all) {
        if ($served -contains $d.FullName.TrimEnd('\').ToLowerInvariant()) { $d }
        elseif ((Test-Path -LiteralPath (Join-Path $d.FullName 'custom\script.js')) -or
                (Test-Path -Path (Join-Path $d.FullName 'App_Data\resources\*.resx'))) {
            Write-Step "Skipped $($d.Name): not an IIS application (leftover of a deleted store?)" 'Yellow'
        }
    }
}

function Find-WebSites($Folders) {
    $Folders | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'custom\script.js') }
}

function Find-AuthServices($Folders) {
    $Folders | Where-Object { Test-Path -Path (Join-Path $_.FullName 'App_Data\resources\*.resx') }
}

# The pack translates the classic UI (receiver.html); the new Workspace UI has its own localization
function Test-WorkspaceUI($Site) {
    $cfg = Join-Path $Site.FullName 'web.config'
    (Test-Path -LiteralPath $cfg) -and (Select-String -LiteralPath $cfg -Pattern '<userInterfaceExperience\s+experience="Workspace"' -Quiet)
}

function Install-WebSite($Site) {
    Write-Step "  Web: $($Site.Name)" 'Cyan'
    if (Test-WorkspaceUI $Site) {
        Write-Step '    note: this store uses the new Workspace UI - the pack translates the classic UI only' 'Yellow'
    }
    $custom = Join-Path $Site.FullName 'custom'
    foreach ($f in $WebFiles) { Copy-PackFile (Join-Path $Pack "custom\$f") (Join-Path $custom $f) }

    $own = Join-Path $custom $CustomStrings
    if (-not (Test-Path -LiteralPath $own)) { Copy-PackFile (Join-Path $Pack "custom\$CustomStrings") $own }

    $scriptJs = Join-Path $custom 'script.js'
    $state = Get-ScriptState $scriptJs
    if ($state -eq 'legacy') {
        # v1.x used $.ctxsAjax, which CSP blocks on current StoreFront; ours goes next to it
        Write-Step '    script.js: v1.x loader found (does not work with CSP) - you may delete it; adding the current one' 'Yellow'
    }
    switch ($state) {
        'installed' {
            $doc = Read-Text $scriptJs
            $pattern = [regex]::Escape($Begin) + '[\s\S]*?' + [regex]::Escape($End)
            if ([regex]::Match($doc.Text, $pattern).Value -eq $Loader) {
                Write-Step '    script.js: loader already present'
            } else {
                Backup-File $scriptJs
                if ($PSCmdlet.ShouldProcess($scriptJs, 'Update language pack loader')) {
                    # MatchEvaluator: the loader text holds '$' that Replace would treat as substitutions
                    $new = [regex]::Replace($doc.Text, $pattern, [Text.RegularExpressions.MatchEvaluator] { param($m) $Loader })
                    Write-Text $scriptJs $new $doc.Bom
                }
                Write-Step '    script.js: loader updated'
                $script:Changed++
            }
        }
        default {
            Backup-File $scriptJs
            if ($PSCmdlet.ShouldProcess($scriptJs, 'Append language pack loader')) {
                $doc = Read-Text $scriptJs
                $text = $doc.Text
                if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`r`n" }
                Write-Text $scriptJs ($text + $Loader + "`r`n") $doc.Bom
            }
            Write-Step '    script.js: loader appended'
            $script:Changed++
        }
    }
}

function Install-AuthService($Svc) {
    Write-Step "  Auth: $($Svc.Name)" 'Cyan'
    $res = Join-Path $Svc.FullName 'App_Data\resources'
    $before = $script:Changed
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $Pack 'resources') -Filter '*.uk.resx') {
        Copy-PackFile $f.FullName (Join-Path $res $f.Name)
    }
    if ($script:Changed -ne $before) { $script:ResxChanged = $true }
}

function Remove-PackFile([string]$Source, [string]$Target) {
    if (-not (Test-Path -LiteralPath $Target)) { return }
    if ((Get-FileHashOrNull $Source) -ne (Get-FileHashOrNull $Target)) {
        Write-Step "    kept     $(Split-Path $Target -Leaf) (differs from the pack - edited by someone?)" 'Yellow'
        return
    }
    Backup-File $Target
    if ($PSCmdlet.ShouldProcess($Target, 'Remove pack file')) { Remove-Item -LiteralPath $Target -Force }
    Write-Step "    removed  $(Split-Path $Target -Leaf)"
    $script:Changed++
}

function Uninstall-WebSite($Site) {
    Write-Step "  Web: $($Site.Name)" 'Cyan'
    $custom = Join-Path $Site.FullName 'custom'
    $scriptJs = Join-Path $custom 'script.js'
    switch (Get-ScriptState $scriptJs) {
        'installed' {
            Backup-File $scriptJs
            if ($PSCmdlet.ShouldProcess($scriptJs, 'Remove language pack loader')) {
                $doc = Read-Text $scriptJs
                $pattern = [regex]::Escape($Begin) + '[\s\S]*?' + [regex]::Escape($End) + '\r?\n?'
                Write-Text $scriptJs ([regex]::Replace($doc.Text, $pattern, '')) $doc.Bom
            }
            Write-Step '    script.js: loader removed'
            $script:Changed++
        }
        'legacy' {
            Write-Step '    script.js: v1.x loader found - remove the culture.uk.js block by hand, then run -Uninstall again' 'Yellow'
            Write-Step '    files kept: the v1.x loader still references them' 'Yellow'
            return
        }
    }
    # files go after the loader, so the site never references a missing file
    foreach ($f in $WebFiles + $CustomStrings) { Remove-PackFile (Join-Path $Pack "custom\$f") (Join-Path $custom $f) }
}

function Uninstall-AuthService($Svc) {
    Write-Step "  Auth: $($Svc.Name)" 'Cyan'
    $res = Join-Path $Svc.FullName 'App_Data\resources'
    $before = $script:Changed
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $Pack 'resources') -Filter '*.uk.resx') {
        Remove-PackFile $f.FullName (Join-Path $res $f.Name)
    }
    if ($script:Changed -ne $before) { $script:ResxChanged = $true }
}

function Show-Status($Sites, $Services) {
    foreach ($s in $Sites) {
        $custom = Join-Path $s.FullName 'custom'
        $files = @(foreach ($f in $WebFiles) {
            if ((Get-FileHashOrNull (Join-Path $Pack "custom\$f")) -eq (Get-FileHashOrNull (Join-Path $custom $f))) { "$f=ok" }
            elseif (Test-Path -LiteralPath (Join-Path $custom $f)) { "$f=DIFFERENT" } else { "$f=MISSING" }
        })
        # required by culture.uk.js (customStringBundle); its content is the admin's own
        $files += if (Test-Path -LiteralPath (Join-Path $custom $CustomStrings)) { "$CustomStrings=present" } else { "$CustomStrings=MISSING" }
        if (Test-WorkspaceUI $s) { $files += 'UI=Workspace (not translated)' }
        Write-Step ("  Web  {0,-30} script.js={1}; {2}" -f $s.Name, (Get-ScriptState (Join-Path $custom 'script.js')), ($files -join '; '))
    }
    foreach ($a in $Services) {
        $res = Join-Path $a.FullName 'App_Data\resources'
        $packResx = @(Get-ChildItem -LiteralPath (Join-Path $Pack 'resources') -Filter '*.uk.resx')
        $ok = @($packResx | Where-Object { (Get-FileHashOrNull $_.FullName) -eq (Get-FileHashOrNull (Join-Path $res $_.Name)) }).Count
        Write-Step ("  Auth {0,-30} resx {1}/{2} from the pack" -f $a.Name, $ok, $packResx.Count)
    }
}

function Invoke-Propagate {
    if (-not (Get-Command Publish-STFServerGroupConfiguration -ErrorAction SilentlyContinue)) {
        Import-Module Citrix.StoreFront -ErrorAction SilentlyContinue
    }
    if (-not (Get-Command Publish-STFServerGroupConfiguration -ErrorAction SilentlyContinue)) {
        $legacy = "$env:ProgramFiles\Citrix\Receiver StoreFront\Scripts\ImportModules.ps1"
        if (Test-Path $legacy) { . $legacy }
    }
    if (-not (Get-Command Publish-STFServerGroupConfiguration -ErrorAction SilentlyContinue)) {
        Write-Step 'Propagate: StoreFront PowerShell module not found - use the console: Server Group > Propagate Changes' 'Yellow'
        return
    }
    if ($PSCmdlet.ShouldProcess('StoreFront server group', 'Propagate changes')) {
        Write-Step 'Propagating changes to the server group...' 'Cyan'
        Publish-STFServerGroupConfiguration
    }
}

# Pools that host the authentication services found above (usually one:
# "Citrix Delivery Services Authentication")
function Invoke-RecycleAuthPool($Services) {
    $paths = @($Services | ForEach-Object { $_.FullName.TrimEnd('\').ToLowerInvariant() })
    $keep = $WhatIfPreference; $WhatIfPreference = $false
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $pools = @(Get-WebApplication | Where-Object {
            $paths -contains [Environment]::ExpandEnvironmentVariables($_.PhysicalPath).TrimEnd('\').ToLowerInvariant()
        } | ForEach-Object { $_.applicationPool } | Sort-Object -Unique)
    } finally { $WhatIfPreference = $keep }
    foreach ($pool in $pools) {
        if ($PSCmdlet.ShouldProcess($pool, 'Recycle IIS application pool')) {
            Restart-WebAppPool -Name $pool
            Write-Step "  recycled $pool"
        }
    }
}

# ---- main -------------------------------------------------------------------

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Status -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run PowerShell as Administrator.'
}
foreach ($p in (Join-Path $Pack 'custom'), (Join-Path $Pack 'resources')) {
    if (-not (Test-Path $p)) { throw "Pack folder not found: $p (run the script from the StoreFront folder of the pack)" }
}
if (-not (Test-Path -LiteralPath $CitrixRoot)) { throw "StoreFront folder not found: $CitrixRoot (use -CitrixRoot)" }

$folders  = @(Get-AppFolders)
$sites    = @(Find-WebSites $folders)
$services = @(Find-AuthServices $folders)
Write-Step "StoreFront folder: $CitrixRoot"
Write-Step "Found $($sites.Count) Receiver for Web site(s): $(($sites | ForEach-Object { $_.Name }) -join ', ')"
Write-Step "Found $($services.Count) authentication service(s): $(($services | ForEach-Object { $_.Name }) -join ', ')"
if ($sites.Count -eq 0 -and $services.Count -eq 0) { throw 'Nothing to do: no StoreFront sites found.' }

if ($Status) {
    Show-Status $sites $services
    return
}

if ($Uninstall) {
    Write-Step 'Uninstalling...' 'Green'
    foreach ($s in $sites)    { Uninstall-WebSite $s }
    foreach ($a in $services) { Uninstall-AuthService $a }
} else {
    Write-Step 'Installing...' 'Green'
    foreach ($s in $sites)    { Install-WebSite $s }
    foreach ($a in $services) { Install-AuthService $a }
}

if ($script:Changed -eq 0) {
    Write-Step 'Nothing changed.' 'Green'
} else {
    Write-Step "$($script:Changed) change(s)." 'Green'
    if ($script:Session -and -not $WhatIfPreference) { Write-Step "Backup: $($script:Session)" }
    if ($Propagate) { Invoke-Propagate }
    else { Write-Step 'Server group? Run this script on every server, or once with -Propagate on the primary.' }
    if ($script:ResxChanged) {
        if ($RecycleAuthPool) { Invoke-RecycleAuthPool $services }
        else {
            Write-Step 'The logon form keeps its old texts until the authentication pool restarts:' 'Yellow'
            Write-Step '  run again with -RecycleAuthPool, or recycle "Citrix Delivery Services Authentication" in IIS.' 'Yellow'
        }
    }
    Write-Step 'Texts still old in the browser? Clear the browser cache.'
}
