$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Config=Join-Path $Root "config.txt"
$History=Join-Path $Root "ClassCodex-Update-History"
$Snapshots=Join-Path $History "Snapshots"
$ChangelogDir=Join-Path $History "Changelogs"
New-Item -ItemType Directory -Force -Path $Snapshots,$ChangelogDir | Out-Null

function Get-Config {
    $r=@{}
    if(!(Test-Path -LiteralPath $Config -PathType Leaf)){return $r}
    foreach($line in Get-Content -LiteralPath $Config){
        $s=$line.Trim()
        if(!$s -or $s.StartsWith("#") -or !$s.Contains("=")){continue}
        $p=$s.Split("=",2);$r[$p[0].Trim()]=$p[1].Trim()
    }
    return $r
}
function HashFile($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}

function Get-RelativeFiles([string]$basePath) {
    $map=@{}
    if(!(Test-Path -LiteralPath $basePath -PathType Container)){ return $map }
    foreach($f in Get-ChildItem -LiteralPath $basePath -Recurse -File){
        $rel=$f.FullName.Substring($basePath.Length).TrimStart([char[]]('/'))
        $map[$rel]=$f
    }
    return $map
}

function Show-UpdateFileSummary([string]$newPath,[string]$previousPath) {
    if([string]::IsNullOrWhiteSpace($previousPath)){
        Write-Host ""
        Write-Host "No previous snapshot available; file change summary skipped." -ForegroundColor Yellow
        return
    }
    if(!(Test-Path -LiteralPath $previousPath -PathType Container)){
        Write-Host ""
        Write-Host "No previous snapshot available; file change summary skipped." -ForegroundColor Yellow
        return
    }

    $oldFiles=Get-RelativeFiles $previousPath
    $newFiles=Get-RelativeFiles $newPath
    $added=@()
    $updated=@()
    $removed=@()
    $unchanged=0

    foreach($path in $newFiles.Keys){
        if(!$oldFiles.ContainsKey($path)){
            $added += $path
        }else{
            $oldHash=(Get-FileHash -LiteralPath $oldFiles[$path].FullName -Algorithm SHA256).Hash
            $newHash=(Get-FileHash -LiteralPath $newFiles[$path].FullName -Algorithm SHA256).Hash
            if($oldHash -ne $newHash){
                $updated += $path
            }else{
                $unchanged++
            }
        }
    }

    foreach($path in $oldFiles.Keys){
        if(!$newFiles.ContainsKey($path)){
            $removed += $path
        }
    }

    if($added.Count){
        Write-Host ""
        Write-Host "Added:"
        foreach($path in @($added | Sort-Object)){ Write-Host "  + $path" }
    }

    if($updated.Count){
        Write-Host ""
        Write-Host "Updated:"
        foreach($path in @($updated | Sort-Object)){ Write-Host "  ~ $path" }
    }

    if($removed.Count){
        Write-Host ""
        Write-Host "Removed:"
        foreach($path in @($removed | Sort-Object)){ Write-Host "  - $path" }
    }

    if(!$added.Count -and !$updated.Count -and !$removed.Count){
        Write-Host ""
        Write-Host "No file changes detected."
    }

}
$c=Get-Config

$configuredAddons=""
if($c.ContainsKey("ADDONS_PATH") -and $c["ADDONS_PATH"]){
    $configuredAddons=[Environment]::ExpandEnvironmentVariables(([string]$c["ADDONS_PATH"]).Trim('"'))
}
if($configuredAddons){
    if (!(Test-Path -LiteralPath $configuredAddons -PathType Container)) {
        throw "Configured ADDONS_PATH does not exist: $configuredAddons"
    }
    $AddonsPath=(Resolve-Path -LiteralPath $configuredAddons).Path
    Write-Host "Using configured AddOns target: $AddonsPath" -ForegroundColor Yellow
}else{
    $roots=New-Object System.Collections.Generic.List[string]
    foreach($key in @("HKCU:SoftwareBlizzard EntertainmentWorld of Warcraft","HKLM:SoftwareBlizzard EntertainmentWorld of Warcraft","HKLM:SoftwareWOW6432NodeBlizzard EntertainmentWorld of Warcraft")){
        try{if(Test-Path -LiteralPath $key){$v=Get-ItemProperty -LiteralPath $key -ErrorAction Stop;foreach($n in @("InstallPath","GamePath")){if($v.$n){[void]$roots.Add([string]$v.$n)}}}}catch{}
    }
    foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)})){if($base){[void]$roots.Add((Join-Path $base "World of Warcraft"))}}
    foreach($drive in [Environment]::GetLogicalDrives()){[void]$roots.Add((Join-Path $drive "World of Warcraft"));[void]$roots.Add((Join-Path $drive "GamesWorld of Warcraft"))}
    $found=New-Object System.Collections.Generic.List[string]
    foreach($r in $roots){
        if(!$r){continue};$r=[Environment]::ExpandEnvironmentVariables(([string]$r).Trim('"'))
        if($r -match '(?i)[\/]_retail_[\/]?$'){$r=Split-Path $r -Parent}
        if((Split-Path $r -Leaf) -ieq "AddOns"){$a=$r}else{$a=Join-Path $r "_retail_InterfaceAddOns"}
        if(Test-Path -LiteralPath $a -PathType Container){$q=(Resolve-Path -LiteralPath $a).Path;if($q -notin $found){[void]$found.Add($q)}}
    }
    if($found.Count -eq 1){$AddonsPath=$found[0];Write-Host "Detected WoW Retail AddOns: $AddonsPath" -ForegroundColor Green}
    elseif($found.Count -gt 1){
        for($i=0;$i-lt$found.Count;$i++){Write-Host ("[{0}] {1}"-f($i+1),$found[$i])}
        $pick=Read-Host "Choose the folder number";$num=0
        if(![int]::TryParse($pick,[ref]$num)-or$num-lt1-or$num-gt$found.Count){throw "Invalid folder selection."}
        $AddonsPath=$found[$num-1]
    }else{
        $wowRoot=Read-Host "Enter your WoW root folder (the folder containing _retail_)"
        if(!$wowRoot){throw "No WoW folder was entered."}
        $AddonsPath=Join-Path ([Environment]::ExpandEnvironmentVariables($wowRoot.Trim('"'))) "_retail_InterfaceAddOns"
    }
}
if(!(Test-Path -LiteralPath $AddonsPath -PathType Container)){throw "AddOns target folder not found: $AddonsPath"}

$Cdn="https://wow-class-codex.s3.us-east-1.amazonaws.com"
$Headers=@{"User-Agent"="ClassCodex-Windows-Downloader/1.15.3"}
Write-Host "";Write-Host "Checking ClassCodex production channel..." -ForegroundColor Cyan
$channel=Invoke-RestMethod "$Cdn/channels/retail/production/config.json" -Headers $Headers -TimeoutSec 60
$build=[string]$channel.buildId;$manifestUrl=[string]$channel.manifestUrl;$manifestHash=([string]$channel.manifestSha256).ToLowerInvariant()
if(!$build-or!$manifestUrl-or!$manifestHash){throw "Production channel config is incomplete."}

$manifestTmp=Join-Path ([IO.Path]::GetTempPath()) ("ClassCodex-manifest-"+[guid]::NewGuid().ToString("N")+".json")
try{
    Invoke-WebRequest -Uri $manifestUrl -Headers $Headers -OutFile $manifestTmp -TimeoutSec 60 -UseBasicParsing
    if((HashFile $manifestTmp)-ne$manifestHash){throw "Manifest SHA-256 verification failed."}
    $manifest=Get-Content -LiteralPath $manifestTmp -Raw -Encoding UTF8|ConvertFrom-Json
    if(!$manifest.files){throw "Manifest contains no files."}

    $items=@($manifest.files)
    $manifestMap=@{}
    foreach($f in $items){
        $rel=[string]$f.path
        if(!$rel.StartsWith("ClassCodex/")-or$rel.Split("/")-contains".."){throw "Unsafe manifest path: $rel"}
        $shortRel=($rel.Substring("ClassCodex/".Length) -replace "/","")
        if($manifestMap.ContainsKey($shortRel)){throw "Duplicate manifest path: $rel"}
        $manifestMap[$shortRel]=$f
    }

    $live=Join-Path $AddonsPath "ClassCodex"
    $liveExists=Test-Path -LiteralPath $live -PathType Container

    # The installed WoW AddOn is the update baseline. Snapshots are history/rollback
    # only; unchanged files are never copied from a snapshot during normal updates.
    $installedBuild=""
    $liveToc=Join-Path $live "ClassCodex.toc"
    if(Test-Path -LiteralPath $liveToc -PathType Leaf){
        $tocLines=Get-Content -LiteralPath $liveToc -Encoding UTF8
        foreach($tocLine in $tocLines){
            if($tocLine -match '^## Build:s*(.+)$'){
                $installedBuild=$Matches[1].Trim()
                break
            }
        }
    }

    if($installedBuild -eq $build -and $liveExists){
        Write-Host ""
        Write-Host "ClassCodex is already up to date." -ForegroundColor Green
        Write-Host "Build: $build"
        Write-Host "No files need to be downloaded or rewritten."
        return
    }

    $stage=Join-Path ([IO.Path]::GetTempPath()) ("ClassCodex-stage-"+[guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $stage|Out-Null
    try{
        $downloadItems=New-Object System.Collections.Generic.List[object]
        $unchangedCount=0
        $addedCount=0
        $updatedCount=0
        $removedCount=0

        # First pass: compare the installed AddOn to the verified production manifest.
        # This reads the live files but does not rewrite any of them.
        foreach($f in $items){
            $rel=[string]$f.path
            $shortRel=$rel.Substring("ClassCodex/".Length)
            $liveFile=Join-Path $live ($shortRel -replace "/","")
            $needsDownload=$true

            if(Test-Path -LiteralPath $liveFile -PathType Leaf){
                $item=Get-Item -LiteralPath $liveFile
                $expectedSize=[int64]$f.size
                $expectedHash=([string]$f.sha256).ToLowerInvariant()
                if($item.Length -eq $expectedSize -and (HashFile $liveFile) -eq $expectedHash){
                    $needsDownload=$false
                    $unchangedCount++
                }else{
                    $updatedCount++
                }
            }else{
                $addedCount++
            }

            if($needsDownload){[void]$downloadItems.Add($f)}
        }

        # Files present in the live AddOn but absent from the production manifest are obsolete.
        $liveFiles=@{}
        if($liveExists){$liveFiles=Get-RelativeFiles $live}
        $removedFiles=New-Object System.Collections.Generic.List[string]
        foreach($oldRel in $liveFiles.Keys){
            if(!$manifestMap.ContainsKey($oldRel)){[void]$removedFiles.Add($oldRel);$removedCount++}
        }

        Write-Host ""
        Write-Host "Production build: $build" -ForegroundColor Cyan
        Write-Host ("Files unchanged : {0}" -f $unchangedCount)
        Write-Host ("Files to download: {0}" -f $downloadItems.Count)
        Write-Host ("Files to remove  : {0}" -f $removedCount)

        # Safety check: if every production file matches the installed AddOn, an
        # obsolete-file count can only be caused by a comparison/path bug. Never
        # delete live files in that situation.
        if($unchangedCount -eq $items.Count -and $removedCount -gt 0){
            throw "Safety check stopped the update: all production files match the installed AddOn, but $removedCount files were incorrectly classified as obsolete. No live files were removed."
        }

        if($downloadItems.Count -eq 0 -and $removedCount -eq 0){
            Write-Host ""
            Write-Host "ClassCodex is already up to date." -ForegroundColor Green
            Write-Host "The installed files already match the production manifest."
            Write-Host "No files need to be downloaded or rewritten."
            return
        }

        # Download only changed/new files into a temporary directory. Nothing in the
        # live AddOn is touched until every download has passed size/hash verification.
        for($i=0;$i-lt$downloadItems.Count;$i++){
            $f=$downloadItems[$i]
            $rel=[string]$f.path
            $shortRel=$rel.Substring("ClassCodex/".Length)
            $dest=Join-Path $stage ($shortRel -replace "/","")
            New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)|Out-Null
            $encoded=($rel-split"/"|ForEach-Object{[uri]::EscapeDataString($_)})-join"/"
            Write-Progress -Activity "Downloading ClassCodex" -Status "$($i+1) / $($downloadItems.Count): $rel" -PercentComplete ([int](($i+1)*100/$downloadItems.Count))
            Invoke-WebRequest "$Cdn/builds/retail/$build/$encoded" -Headers $Headers -OutFile $dest -TimeoutSec 120 -UseBasicParsing
            if((Get-Item -LiteralPath $dest).Length-ne[int64]$f.size){throw "Size verification failed: $rel"}
            if((HashFile $dest)-ne([string]$f.sha256).ToLowerInvariant()){throw "SHA-256 verification failed: $rel"}
        }
        if($downloadItems.Count -gt 0){Write-Progress -Activity "Downloading ClassCodex" -Completed}

        # Final manifest verification: every production file must exist either in the
        # live AddOn (unchanged) or in the verified download staging area.
        foreach($f in $items){
            $rel=[string]$f.path
            $shortRel=$rel.Substring("ClassCodex/".Length)
            $liveFile=Join-Path $live ($shortRel -replace "/","")
            $stageFile=Join-Path $stage ($shortRel -replace "/","")
            $source=$null
            if(Test-Path -LiteralPath $stageFile -PathType Leaf){$source=$stageFile}
            elseif(Test-Path -LiteralPath $liveFile -PathType Leaf){$source=$liveFile}
            else{throw "Required manifest file is missing: $rel"}

            if((Get-Item -LiteralPath $source).Length-ne[int64]$f.size){throw "Size verification failed: $rel"}
            if((HashFile $source)-ne([string]$f.sha256).ToLowerInvariant()){throw "SHA-256 verification failed: $rel"}
        }

        # Installation phase. Changed/new files are moved from the verified temp area,
        # Remove the old live file before moving in the verified replacement.
        # immutable. Obsolete files are removed only after all downloads are verified.
        foreach($oldRel in @($removedFiles | Sort-Object)){
            $oldPath=Join-Path $live ($oldRel -replace "/","")
            if(Test-Path -LiteralPath $oldPath -PathType Leaf){
                Remove-Item -LiteralPath $oldPath -Force
                Write-Host "Removed: $oldRel" -ForegroundColor Yellow
            }
        }

        foreach($f in $downloadItems){
            $rel=[string]$f.path
            $shortRel=$rel.Substring("ClassCodex/".Length)
            $stageFile=Join-Path $stage ($shortRel -replace "/","")
            $liveFile=Join-Path $live ($shortRel -replace "/","")
            New-Item -ItemType Directory -Force -Path (Split-Path $liveFile -Parent)|Out-Null
            if(Test-Path -LiteralPath $liveFile -PathType Leaf){Remove-Item -LiteralPath $liveFile -Force}
            Move-Item -LiteralPath $stageFile -Destination $liveFile -Force
        }

        Write-Host ""
        Write-Host "ClassCodex updated successfully." -ForegroundColor Green
        Write-Host "Installed to: $live"
        Write-Host ("Downloaded : {0} / {1} files" -f $downloadItems.Count,$items.Count)
        Write-Host ("Unchanged  : {0} files" -f $unchangedCount)
        Write-Host ("Removed    : {0} files" -f $removedCount)

        # Save a normal independent snapshot for history/rollback only.
        # The live WoW AddOn remains the update baseline; snapshots are never used
        # as the source for unchanged files during normal updates.
        $snap=Join-Path $Snapshots $build
        if(Test-Path -LiteralPath $snap){Remove-Item -LiteralPath $snap -Recurse -Force}
        New-Item -ItemType Directory -Force -Path $snap|Out-Null
        foreach($file in Get-ChildItem -LiteralPath $live -Recurse -File){
            $rel=$file.FullName.Substring($live.Length).TrimStart([char[]]('/'))
            $snapFile=Join-Path $snap $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $snapFile -Parent)|Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $snapFile -Force
        }
        Write-Host ""
        Write-Host "Snapshot saved: $snap" -ForegroundColor DarkCyan

        # Compare the installed result with the previous snapshot only for reporting.
        $previousSnapshot=$null
        $existingSnapshots=@(Get-ChildItem -LiteralPath $Snapshots -Directory | Where-Object {$_.Name -ne $build} | Sort-Object Name -Descending)
        if($existingSnapshots.Count -gt 0){$previousSnapshot=$existingSnapshots[0].FullName}
        if($previousSnapshot){
            Write-Host ""
            Write-Host "Comparing with previous snapshot: $(Split-Path $previousSnapshot -Leaf)" -ForegroundColor Cyan
            Show-UpdateFileSummary $live $previousSnapshot
        }else{
            Show-UpdateFileSummary $live ""
        }
    }finally{if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}}
}finally{if(Test-Path -LiteralPath $manifestTmp){Remove-Item -LiteralPath $manifestTmp -Force -ErrorAction SilentlyContinue}}

$answer=Read-Host "Generate detailed update summary now? [Y/N]"
if($answer-match"^[Yy]$"){
    $psExe=Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe";$diffScript=Join-Path $Root "ClassCodex-Diff.ps1"
    Unblock-File -LiteralPath $diffScript -ErrorAction SilentlyContinue
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $diffScript -NewBuild $build
    if($LASTEXITCODE-ne 0){throw "ClassCodex-Diff failed with exit code $LASTEXITCODE."}
}