param([string]$NewBuild="")
$ErrorActionPreference="Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$History = Join-Path $Root "ClassCodex-Update-History"
$Snapshots = Join-Path $History "Snapshots"
$ChangelogDir = Join-Path $History "Changelogs"
$Cache = Join-Path $History "ItemCache.json"
New-Item -ItemType Directory -Force -Path $Snapshots,$ChangelogDir | Out-Null

$builds=@(Get-ChildItem -LiteralPath $Snapshots -Directory | Sort-Object Name -Descending)
if($builds.Count -lt 2){ Write-Host "At least two ClassCodex snapshots are required."; exit 0 }
if($NewBuild){ $newSnapshot=@($builds|Where-Object Name -eq $NewBuild|Select-Object -First 1); if(!$newSnapshot){$newSnapshot=$builds[0]} else{$newSnapshot=$newSnapshot[0]} } else{$newSnapshot=$builds[0]}
$selectedNewBuild=$newSnapshot.Name
$oldSnapshot=@($builds|Where-Object Name -ne $selectedNewBuild|Select-Object -First 1)
if(!$oldSnapshot){throw "No OLD snapshot available."};$oldSnapshot=$oldSnapshot[0]

function Get-RelativeFiles([string]$base){$m=@{};foreach($f in @(Get-ChildItem -LiteralPath $base -Recurse -File)){$rel=$f.FullName.Substring($base.Length).TrimStart([char[]]"\\/");$m[$rel]=$f};return $m}
function Get-IcyEntries([string[]]$lines){
  $out=New-Object System.Collections.Generic.List[object];$stack=New-Object System.Collections.Generic.List[object];$ord=@{};$inTalents=$false
  for($i=0;$i -lt $lines.Count;$i++){
    $line=$lines[$i];if([string]::IsNullOrWhiteSpace($line)){continue};$indent=$line.Length-$line.TrimStart().Length
    while($stack.Count -gt 0 -and $stack[$stack.Count-1].Indent -ge $indent){$stack.RemoveAt($stack.Count-1)}
    $km=[regex]::Match($line,'^\\s*(?:\\[\\s*"([^"]+)"\\s*\\]|([A-Za-z_][A-Za-z0-9_-]*))\\s*=\\s*\\{\\s*$')
    if($km.Success){$key=if($km.Groups[1].Success){$km.Groups[1].Value}else{$km.Groups[2].Value};$stack.Add([pscustomobject]@{Indent=$indent;Key=$key});$inTalents=@($stack.Key)-contains "talents";continue}
    if(!$inTalents -or $line -notmatch '\\bexport\\s*=\\s*"([^"]*)"'){continue};$export=$Matches[1]
    $lm=[regex]::Match($line,'\\blabel\\s*=\\s*"([^"]*)"');$label=if($lm.Success){$lm.Groups[1].Value}else{""};$path=@($stack.Key);$ti=[array]::IndexOf($path,"talents");if($ti -lt 0){continue}
    $class=if($ti -ge 2){$path[$ti-2]}else{"Unknown"};$spec=if($ti -ge 1){$path[$ti-1]}else{"Unknown"};$hero=if($ti+1 -lt $path.Count){$path[$ti+1]}else{"Unknown"};$profile=if($ti+2 -lt $path.Count){$path[$ti+2]}else{"Unknown"};$key="$class|$spec|$hero|$profile|$label";if(!$ord.ContainsKey($key)){$ord[$key]=0};$ord[$key]++
    $out.Add([pscustomobject]@{Class=$class;Spec=$spec;HeroTree=$hero;Section=$profile;Label=$label;Export=$export;Ordinal=$ord[$key]})
  };return $out.ToArray()
}
function Get-IcyMap([string[]]$lines){$m=@{};foreach($e in @(Get-IcyEntries $lines)){$k="$($e.Class)|$($e.HeroTree)|$($e.Section)|$($e.Label)|$($e.Ordinal)";$m[$k]=$e};return $m}
function Normalize([string]$v){if($null-eq$v){return ""};return $v.Trim()}
function Display([string]$v){if([string]::IsNullOrWhiteSpace($v)){return "Unknown"};return (($v-split '-')|ForEach-Object{if($_){$_.Substring(0,1).ToUpperInvariant()+$_.Substring(1)}})-join ' '}

$report=New-Object System.Collections.Generic.List[string];$report.Add("CLASSCODEX UPDATE SUMMARY");$report.Add("=========================");$report.Add("");$report.Add("OLD: $($oldSnapshot.Name)");$report.Add("NEW: $selectedNewBuild");$report.Add("")
$oldFiles=Get-RelativeFiles $oldSnapshot.FullName;$newFiles=Get-RelativeFiles $newSnapshot.FullName;$added=@();$updated=@();$removed=@();$unchanged=0
foreach($p in $newFiles.Keys){if(!$oldFiles.ContainsKey($p)){$added+=$p}elseif((Get-FileHash $oldFiles[$p].FullName -Algorithm SHA256).Hash-ne(Get-FileHash $newFiles[$p].FullName -Algorithm SHA256).Hash){$updated+=$p}else{$unchanged++}};foreach($p in $oldFiles.Keys){if(!$newFiles.ContainsKey($p)){$removed+=$p}}
$report.Add("FILES CHANGED");$report.Add("-------------");foreach($p in @($added|Sort-Object)){$report.Add("  + $p")};foreach($p in @($updated|Sort-Object)){$report.Add("  ~ $p")};foreach($p in @($removed|Sort-Object)){$report.Add("  - $p")};$report.Add("");$report.Add("File summary:");$report.Add("  Added    : $($added.Count)");$report.Add("  Updated  : $($updated.Count)");$report.Add("  Removed  : $($removed.Count)");$report.Add("  Unchanged: $unchanged")
$oldI=Join-Path $oldSnapshot.FullName "Data\\db_icyveins.lua";$newI=Join-Path $newSnapshot.FullName "Data\\db_icyveins.lua";$report.Add("");$report.Add("ICY VEINS EXPORT CHANGES");$report.Add("------------------------")
if((Test-Path $oldI)-and(Test-Path $newI)){$a=Get-IcyMap @(Get-Content $oldI -Encoding UTF8);$b=Get-IcyMap @(Get-Content $newI -Encoding UTF8);$found=$false;foreach($k in $b.Keys){if(!$a.ContainsKey($k)){continue};if((Normalize $a[$k].Export)-ne(Normalize $b[$k].Export)){$found=$true;$e=$b[$k];$report.Add("");$report.Add("Class : $(Display $e.Class)");$report.Add("Spec  : $(Display $e.Spec)");$report.Add("Hero Tree: $(Display $e.HeroTree)");$report.Add("Profile: $(if($e.Label){$e.Label}else{Display $e.Section})");$report.Add("Export string: changed")}};if(!$found){$report.Add("No Icy Veins changes detected.")}}else{$report.Add("Icy Veins data could not be compared.")}
$oldU=Join-Path $oldSnapshot.FullName "Data\\db_ugg.lua";$newU=Join-Path $newSnapshot.FullName "Data\\db_ugg.lua";$report.Add("");$report.Add("UGG ITEM POPULARITY CHANGES");$report.Add("---------------------------")
if((Test-Path $oldU)-and(Test-Path $newU)){function Ugg([string]$raw){$m=@{};foreach($x in [regex]::Matches($raw,'itemId=(\\d+),pop=([0-9.]+)')){$id=$x.Groups[1].Value;$p=[double]::Parse($x.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture);if(!$m.ContainsKey($id)){$m[$id]=@()};$m[$id]+=$p};return $m};$a=Ugg(Get-Content $oldU -Raw -Encoding UTF8);$b=Ugg(Get-Content $newU -Raw -Encoding UTF8);$n=0;foreach($id in $b.Keys){if($a.ContainsKey($id)){$op=($a[$id]|Measure-Object -Maximum).Maximum;$np=($b[$id]|Measure-Object -Maximum).Maximum;if($op-ne$np){$n++;$report.Add(("Item {0}: {1} -> {2} ({3:+0.0;-0.0;0.0})"-f $id,[math]::Round($op,1),[math]::Round($np,1),[math]::Round($np-$op,1)))}}};if($n-eq0){$report.Add("No UGG popularity changes detected.")}}else{$report.Add("UGG data could not be compared.")}
$out=Join-Path $ChangelogDir ("{0}-vs-{1}.txt"-f $oldSnapshot.Name,$selectedNewBuild);$report|Set-Content -LiteralPath $out -Encoding UTF8;$report|ForEach-Object{Write-Host $_};Write-Host "";Write-Host "Report: $out"
