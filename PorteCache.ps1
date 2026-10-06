# =====================================================================
#  PORTE CLEANER  v1.0  -  Limpieza de cache segura para Windows
#  Uso:  irm https://raw.githubusercontent.com/TU_USUARIO/TU_REPO/main/PorteCleaner.ps1 | iex
#  (cambia la URL de $PC.Url por la tuya)
# =====================================================================

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host '  Porte Cleaner necesita Windows PowerShell (STA). Abre "powershell.exe" y vuelve a ejecutar el comando.' -ForegroundColor Yellow
    return
}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $host.UI.RawUI.WindowTitle = 'Porte Cleaner' } catch {}

$global:PC = @{
    Url       = 'https://raw.githubusercontent.com/TU_USUARIO/TU_REPO/main/PorteCleaner.ps1'
    Pct       = 0
    Safe      = $true
    Dark      = $true
    Sel       = $null
    SelFiles  = (New-Object System.Collections.ArrayList)
    RowChecks = (New-Object System.Collections.ArrayList)
    Log       = (New-Object System.Collections.ArrayList)
    Cursor    = $true
    Tick      = 0
    Busy      = $false
    ScanSecs  = 0
    IncBytes  = [long]0
    RiskyExt  = @('.exe','.dll','.sys','.msi','.bat','.cmd','.ps1','.vbs')
}
$global:PC.Cmd = 'irm ' + $PC.Url + ' | iex'
$PC.LastScan = Get-Date
$PC.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$w_ = $env:WINDIR
$PC.Locs = @(
    @{ Key='prefetch'; Name='Prefetch';          Glyph=0xE945; Paths=@("$w_\Prefetch");                              Filter=$null; Admin=$true;  Risk=12; Include=$true }
    @{ Key='systemp';  Name='System Temp';       Glyph=0xE8B7; Paths=@("$w_\Temp");                                  Filter=$null; Admin=$true;  Risk=6;  Include=$true }
    @{ Key='usertemp'; Name='%Temp% (Usuario)';  Glyph=0xE77B; Paths=@($env:TEMP);                                   Filter=$null; Admin=$false; Risk=4;  Include=$true }
    @{ Key='wu';       Name='Windows Update';    Glyph=0xE896; Paths=@("$w_\SoftwareDistribution\Download");         Filter=$null; Admin=$true;  Risk=10; Include=$true }
    @{ Key='thumbs';   Name='Miniaturas';        Glyph=0xE91B; Paths=@("$env:LOCALAPPDATA\Microsoft\Windows\Explorer"); Filter='thumbcache_*.db'; Admin=$false; Risk=2; Include=$true }
    @{ Key='dx';       Name='Caché DirectX';     Glyph=0xE7FC; Paths=@("$env:LOCALAPPDATA\D3DSCache");               Filter=$null; Admin=$false; Risk=4;  Include=$true }
    @{ Key='browsers'; Name='Navegadores';       Glyph=0xE774; Paths=@("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data","$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\Cache_Data","$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache\Cache_Data"); Filter=$null; Admin=$false; Risk=5; Include=$true }
    @{ Key='wer';      Name='Informes de errores'; Glyph=0xE7BA; Paths=@("$env:ProgramData\Microsoft\Windows\WER"); Filter=$null; Admin=$true;  Risk=3;  Include=$true }
    @{ Key='recycle';  Name='Papelera';          Glyph=0xE74D; Paths=@();                                            Filter=$null; Admin=$false; Risk=15; Include=$false }
)

# ------------------------------------------------------------------ helpers
function PcFmt($b) {
    if (-not $b) { $b = 0 }
    $b = [double]$b
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N1} KB' -f ($b / 1KB)) }
    return ('{0:N0} B' -f $b)
}

function PcArt([int]$cw) {
    $g = @{
        P = @('####.','#...#','####.','#....','#....')
        O = @('.###.','#...#','#...#','#...#','.###.')
        R = @('####.','#...#','####.','#..#.','#...#')
        T = @('#####','..#..','..#..','..#..','..#..')
        E = @('#####','#....','####.','#....','#####')
    }
    $blk = [string][char]0x2588
    $out = @()
    for ($r = 0; $r -lt 5; $r++) {
        $s = ''
        foreach ($ch in 'P','O','R','T','E') {
            foreach ($c in $g[$ch][$r].ToCharArray()) {
                if ($c -eq '#') { $s += ($blk * $cw) } else { $s += (' ' * $cw) }
            }
            $s += (' ' * $cw)
        }
        $out += $s.TrimEnd()
    }
    return , $out
}

function PcBanner {
    Clear-Host
    $wd = 120
    try { $wd = $host.UI.RawUI.WindowSize.Width } catch {}
    $cw = 2
    if ($wd -ge 96) { $cw = 3 }
    $art = PcArt $cw
    Write-Host ''
    $row = 0
    foreach ($line in $art) {
        for ($k = 0; $k -lt 2; $k++) {
            $col = 'DarkGray'
            if ($row -lt 4) { $col = 'White' } elseif ($row -lt 7) { $col = 'Gray' }
            Write-Host ('  ' + $line) -ForegroundColor $col
            $row++
            Start-Sleep -Milliseconds 45
        }
    }
    Write-Host ''
    Write-Host ('  C L E A N E R   ' + [char]0x00B7 + '   v1.0   ' + [char]0x00B7 + '   limpieza de cach' + [char]0x00E9 + ' segura') -ForegroundColor DarkGray
    Write-Host ''
}

function PcBar([int]$pct, [string]$label) {
    $wd = 44
    $f = [int][Math]::Floor($wd * $pct / 100)
    $bar = ([string][char]0x2588) * $f + ([string][char]0x2591) * ($wd - $f)
    Write-Host ("`r  {0}  {1,3}%  {2}" -f $bar, $pct, $label.PadRight(40)) -NoNewline -ForegroundColor White
}

function PcStep([int]$to, [string]$label) {
    $from = [int]$PC.Pct
    if ($to -le $from) { PcBar $from $label; return }
    for ($p = $from; $p -le $to; $p++) { PcBar $p $label; Start-Sleep -Milliseconds 7 }
    $PC.Pct = $to
}

function PcCol([string]$h) { [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString($h)) }

function PcBrush($spec) {
    if ($spec -is [string]) {
        $b = [System.Windows.Media.SolidColorBrush]::new((PcCol $spec))
    } else {
        $mode = $spec[2]
        if ($mode -eq 'r') {
            $b = [System.Windows.Media.RadialGradientBrush]::new((PcCol $spec[0]), (PcCol $spec[1]))
        } else {
            $ang = 90.0
            if ($mode -eq 'h') { $ang = 0.0 } elseif ($mode -eq 'd') { $ang = 45.0 }
            $b = [System.Windows.Media.LinearGradientBrush]::new((PcCol $spec[0]), (PcCol $spec[1]), $ang)
        }
    }
    $b.Freeze()
    return $b
}

function PcScan($loc) {
    $items = New-Object System.Collections.Generic.List[object]
    $size = [long]0
    $risky = 0
    try {
        if ($loc.Key -eq 'recycle') {
            $ns = (New-Object -ComObject Shell.Application).Namespace(10)
            foreach ($i in $ns.Items()) {
                $len = [long]$i.Size
                $items.Add([pscustomobject]@{ Name = [string]$i.Name; FullName = [string]$i.Path; Length = $len; LastWriteTime = [datetime]$i.ModifyDate; Extension = '' })
                $size += $len
            }
        } else {
            foreach ($p in $loc.Paths) {
                if (-not (Test-Path -LiteralPath $p)) { continue }
                $a = @{ LiteralPath = $p; Force = $true; Recurse = $true; File = $true; ErrorAction = 'SilentlyContinue' }
                if ($loc.Filter) { $a.Filter = $loc.Filter }
                foreach ($f in (Get-ChildItem @a)) {
                    $items.Add($f)
                    $size += $f.Length
                    if ($PC.RiskyExt -contains $f.Extension.ToLowerInvariant()) { $risky++ }
                }
            }
        }
    } catch {}
    $loc.List = $items
    $loc.Bytes = $size
    $loc.NFiles = $items.Count
    $loc.RiskyCount = $risky
    $loc.Sorted = @($items | Sort-Object Length -Descending)
}

function PcLoc($key) { $PC.Locs | Where-Object { $_.Key -eq $key } | Select-Object -First 1 }

# ------------------------------------------------------------------ UI logic
function PcPump { $PC.Win.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render) }

function PcBusy([bool]$on, [string]$t = '', [string]$s = '') {
    $u = $PC.UI
    if ($on) {
        $u.BusyText.Text = $t; $u.BusySub.Text = $s
        $u.BusyOverlay.Visibility = 'Visible'
        PcPump
    } else {
        $u.BusyOverlay.Visibility = 'Collapsed'
    }
}

function PcLog([string]$m) {
    [void]$PC.Log.Add(('[{0}] {1}' -f (Get-Date).ToString('HH:mm:ss'), $m))
    if ($PC.Log.Count -gt 60) { $PC.Log.RemoveAt(0) }
}

function PcConsole {
    $cur = ' '
    if ($PC.Cursor) { $cur = [string][char]0x258C }
    $tot = 0
    foreach ($l in $PC.Locs) { $tot += $l.NFiles }
    $lines = @()
    $lines += '> porte --scan --safe'
    $lines += ('  ubicaciones : {0}' -f $PC.Locs.Count)
    $lines += ('  archivos    : {0:N0}' -f $tot)
    $lines += ('  recuperable : {0}' -f (PcFmt $PC.IncBytes))
    $lines += ''
    foreach ($m in ($PC.Log | Select-Object -Last 7)) { $lines += ('  ' + $m) }
    $lines += ('_ esperando una acci' + [char]0x00F3 + 'n segura ' + $cur)
    $PC.UI.LogText.Text = ($lines -join "`n")
}

function PcLast {
    $m = [int]((Get-Date) - $PC.LastScan).TotalMinutes
    if ($m -lt 1) { $PC.UI.LastScanText.Text = ([string][char]0x00DA + 'ltimo an' + [char]0x00E1 + 'lisis hace instantes') }
    else { $PC.UI.LastScanText.Text = ([string][char]0x00DA + 'ltimo an' + [char]0x00E1 + 'lisis hace ' + $m + ' min') }
}

function PcTotals {
    $u = $PC.UI
    $inc = @($PC.Locs | Where-Object { $_.Include })
    $bytes = [long]0; $files = 0; $risk = 6; $rc = 0; $tot = [long]0
    foreach ($l in $PC.Locs) { $tot += $l.Bytes }
    foreach ($l in $inc) { $bytes += $l.Bytes; $files += $l.NFiles; $risk += $l.Risk; $rc += $l.RiskyCount }
    if ($risk -gt 100) { $risk = 100 }
    $PC.IncBytes = $bytes
    $u.ValRec.Text = (PcFmt $bytes)
    $u.SubRec.Text = 'en ubicaciones seleccionadas'
    $u.ValFiles.Text = ('{0:N0}' -f $files)
    if ($rc -gt 0) { $u.SubFiles.Text = ('{0:N0} archivos a revisar' -f $rc) } else { $u.SubFiles.Text = 'sin riesgo cr' + [char]0x00ED + 'tico' }
    $u.ValRisk.Text = ('{0}/100' -f $risk)
    if ($risk -lt 30) { $u.SubRisk.Text = 'bajo ' + [char]0x00B7 + ' controlado' } elseif ($risk -lt 60) { $u.SubRisk.Text = 'medio ' + [char]0x00B7 + ' revisa antes' } else { $u.SubRisk.Text = 'alto ' + [char]0x00B7 + ' con cuidado' }
    $mm = [int][Math]::Floor($PC.ScanSecs / 60); $ss = [int]($PC.ScanSecs % 60)
    $u.ValScan.Text = ('{0:00}:{1:00}' -f $mm, $ss)
    $u.SubScan.Text = 'duraci' + [char]0x00F3 + 'n del proceso'
    $pct = 0
    if ($tot -gt 0) { $pct = [int][Math]::Round(100.0 * $bytes / $tot) }
    $u.RecPct.Text = ('{0}%' -f $pct)
    $u.RecCol0.Width = [System.Windows.GridLength]::new([double]$pct, [System.Windows.GridUnitType]::Star)
    $u.RecCol1.Width = [System.Windows.GridLength]::new([double](100 - $pct), [System.Windows.GridUnitType]::Star)
    $sep = ' ' + [char]0x00B7 + ' '
    if ($inc.Count -gt 0) { $u.RecNames.Text = (($inc | ForEach-Object { $_.Name }) -join $sep) + '   ' + (PcFmt $tot) + ' detectados' } else { $u.RecNames.Text = 'Ninguna ubicaci' + [char]0x00F3 + 'n activa' }
    $u.BarInfo1.Text = ('{0} ubicaciones activas' -f $inc.Count)
    $u.BarInfo2.Text = ('{0} recuperables' -f (PcFmt $bytes))
    $u.LocCount.Text = ('{0} rutas' -f $PC.Locs.Count)
    PcConsole
}

function PcSidebar {
    foreach ($l in $PC.Locs) {
        if ($l.Admin -and (-not $PC.IsAdmin) -and $l.NFiles -eq 0) { $l.Sub.Text = 'requiere administrador' }
        else { $l.Sub.Text = ('{0:N0} archivos ' -f $l.NFiles) + [char]0x00B7 + ' ' + (PcFmt $l.Bytes) }
    }
}

function PcSel {
    $u = $PC.UI
    $sum = [long]0
    foreach ($f in $PC.SelFiles) { $sum += $f.Length }
    $u.SelText.Text = ('{0} seleccionados ' -f $PC.SelFiles.Count) + [char]0x00B7 + ' ' + (PcFmt $sum)
    if ($PC.SelFiles.Count -gt 0) { $u.BtnDelSel.Visibility = 'Visible' } else { $u.BtnDelSel.Visibility = 'Collapsed' }
}

function PcText([string]$text, [string]$key, [double]$size, [string]$family = '', [string]$weight = '') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text
    $t.FontSize = $size
    $t.VerticalAlignment = 'Center'
    $t.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $key)
    if ($family) { $t.FontFamily = [System.Windows.Media.FontFamily]::new($family) }
    if ($weight) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    return $t
}

function PcRow($f) {
    $mono = 'Cascadia Mono, Consolas'
    $b = New-Object System.Windows.Controls.Border
    $b.Height = 38
    $b.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $b.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
    $b.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'RowBrush')
    $g = New-Object System.Windows.Controls.Grid
    foreach ($wd in 40, -1, 110, 110, 100) {
        $c = New-Object System.Windows.Controls.ColumnDefinition
        if ($wd -lt 0) { $c.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        else { $c.Width = [System.Windows.GridLength]::new($wd) }
        $g.ColumnDefinitions.Add($c)
    }
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Style = $PC.Win.FindResource('PorteCheck')
    $cb.Tag = $f
    $cb.HorizontalAlignment = 'Center'; $cb.VerticalAlignment = 'Center'
    $cb.Add_Checked({ param($s, $e) [void]$PC.SelFiles.Add($s.Tag); PcSel })
    $cb.Add_Unchecked({ param($s, $e) $PC.SelFiles.Remove($s.Tag); PcSel })
    [void]$PC.RowChecks.Add($cb)
    [void]$g.Children.Add($cb)

    $n = PcText $f.Name 'TextBrush' 12
    $n.TextTrimming = 'CharacterEllipsis'
    $n.ToolTip = $f.FullName
    $n.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
    [System.Windows.Controls.Grid]::SetColumn($n, 1); [void]$g.Children.Add($n)

    $sz = PcText (PcFmt $f.Length) 'MutedBrush' 11 $mono
    [System.Windows.Controls.Grid]::SetColumn($sz, 2); [void]$g.Children.Add($sz)

    $dt = PcText $f.LastWriteTime.ToString('yyyy-MM-dd') 'DimBrush' 11 $mono
    [System.Windows.Controls.Grid]::SetColumn($dt, 3); [void]$g.Children.Add($dt)

    $risky = $PC.RiskyExt -contains ([string]$f.Extension).ToLowerInvariant()
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 6; $dot.Height = 6; $dot.Margin = [System.Windows.Thickness]::new(0, 0, 7, 0)
    $keyc = 'GreenBrush'; $lbl = 'Seguro'
    if ($risky) { $keyc = 'AmberBrush'; $lbl = 'Revisar' }
    $dot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $keyc)
    [void]$sp.Children.Add($dot)
    [void]$sp.Children.Add((PcText $lbl $keyc 11))
    [System.Windows.Controls.Grid]::SetColumn($sp, 4); [void]$g.Children.Add($sp)
    $b.Child = $g
    return $b
}

function PcFiles {
    $u = $PC.UI
    $PC.Busy = $true
    $u.FileList.Children.Clear(); $PC.SelFiles.Clear(); $PC.RowChecks.Clear(); $u.ChkAll.IsChecked = $false
    $PC.Busy = $false
    $loc = $PC.Sel
    if (-not $loc) { return }
    $flt = $u.FilterBox.Text.Trim()
    $src = $loc.Sorted
    if ($flt) { $src = @($src | Where-Object { $_.Name -like "*$flt*" }) }
    $total = @($src).Count
    $shown = 0
    foreach ($f in $src) {
        if ($shown -ge 120) { break }
        [void]$u.FileList.Children.Add((PcRow $f))
        $shown++
    }
    if ($total -eq 0) {
        $e = PcText 'x' 'DimBrush' 12
        $e.Text = 'Sin archivos en esta ubicaci' + [char]0x00F3 + 'n.'
        $e.HorizontalAlignment = 'Center'; $e.Margin = [System.Windows.Thickness]::new(0, 40, 0, 0)
        [void]$u.FileList.Children.Add($e)
    }
    $u.CountText.Text = ('{0} de {1:N0} archivos' -f $shown, $total)
    PcSel
}

function PcShow($loc) {
    $PC.Sel = $loc
    foreach ($l in $PC.Locs) {
        $b = $l.Border
        if ($l.Key -eq $loc.Key) {
            $b.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'SelBrush')
            $b.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'CardBorderBrush')
        } else {
            $b.Background = [System.Windows.Media.Brushes]::Transparent
            $b.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        }
    }
    if ($loc.Key -eq 'recycle') { $PC.UI.ExpPath.Text = 'shell:RecycleBinFolder' } else { $PC.UI.ExpPath.Text = $loc.Paths[0] }
    PcFiles
}

function PcTheme([bool]$dark) {
    $PC.Dark = $dark
    if ($dark) {
        $t = @{
            BgBrush = @('#0E0E10', '#060607', 'v')
            SidebarBrush = '#B80B0B0D'
            CardBrush = @('#16FFFFFF', '#07FFFFFF', 'd')
            CardBorderBrush = @('#30FFFFFF', '#0EFFFFFF', 'd')
            TextBrush = '#F4F4F5'
            MutedBrush = '#9A9AA2'
            DimBrush = '#5E5E66'
            HoverBrush = '#14FFFFFF'
            SelBrush = @('#2AFFFFFF', '#10FFFFFF', 'd')
            RowBrush = '#09FFFFFF'
            AccentBrush = '#F4F4F5'
            AccentTextBrush = '#0A0A0B'
            GreenBrush = '#4ADE80'
            AmberBrush = '#FBBF24'
            TitleBrush = @('#FFFFFF', '#7E7E88', 'h')
            BarBrush = @('#40FFFFFF', '#FFFFFFFF', 'h')
            TrackBrush = '#16FFFFFF'
            ConsoleBrush = '#B3000000'
            GlowBrush = @('#26FFFFFF', '#00FFFFFF', 'r')
        }
        $fc = '#FFFFFF'; $fa = 0.9
    } else {
        $t = @{
            BgBrush = @('#F7F7F8', '#E7E7EA', 'v')
            SidebarBrush = '#CCFFFFFF'
            CardBrush = @('#F2FFFFFF', '#B8FFFFFF', 'd')
            CardBorderBrush = @('#26000000', '#0C000000', 'd')
            TextBrush = '#0B0B0C'
            MutedBrush = '#6B6B73'
            DimBrush = '#A1A1AA'
            HoverBrush = '#0F000000'
            SelBrush = @('#FFFFFFFF', '#E8FFFFFF', 'd')
            RowBrush = '#0A000000'
            AccentBrush = '#0B0B0C'
            AccentTextBrush = '#FAFAFA'
            GreenBrush = '#16A34A'
            AmberBrush = '#D97706'
            TitleBrush = @('#0B0B0C', '#7A7A82', 'h')
            BarBrush = @('#40000000', '#FF0B0B0C', 'h')
            TrackBrush = '#16000000'
            ConsoleBrush = '#12000000'
            GlowBrush = @('#1A000000', '#00000000', 'r')
        }
        $fc = '#000000'; $fa = 0.5
    }
    foreach ($k in @($t.Keys)) { $PC.Win.Resources[$k] = (PcBrush $t[$k]) }
    $u = $PC.UI
    $tr = [System.Windows.Media.Brushes]::Transparent
    $BD = [System.Windows.Controls.Border]; $TB = [System.Windows.Controls.TextBlock]
    if ($dark) {
        $u.SegDark.SetResourceReference($BD::BackgroundProperty, 'AccentBrush'); $u.SegDarkT.SetResourceReference($TB::ForegroundProperty, 'AccentTextBrush')
        $u.SegLight.Background = $tr; $u.SegLightT.SetResourceReference($TB::ForegroundProperty, 'MutedBrush')
    } else {
        $u.SegLight.SetResourceReference($BD::BackgroundProperty, 'AccentBrush'); $u.SegLightT.SetResourceReference($TB::ForegroundProperty, 'AccentTextBrush')
        $u.SegDark.Background = $tr; $u.SegDarkT.SetResourceReference($TB::ForegroundProperty, 'MutedBrush')
    }
    $PC.Field.SetColor((PcCol $fc), $fa)
}

function PcDelFile([string]$p) {
    try { [System.IO.File]::Delete($p); return $true }
    catch {
        try { [System.IO.File]::SetAttributes($p, [System.IO.FileAttributes]::Normal); [System.IO.File]::Delete($p); return $true }
        catch { return $false }
    }
}

function PcConfirm([string]$kind, [string]$title, [string]$text) {
    $u = $PC.UI
    $PC.ConfirmKind = $kind
    $u.CfTitle.Text = $title; $u.CfText.Text = $text
    if ($kind -eq 'info') { $u.CfCancel.Visibility = 'Collapsed' } else { $u.CfCancel.Visibility = 'Visible' }
    $u.ConfirmOverlay.Visibility = 'Visible'
}

function PcClean {
    $locs = @($PC.Locs | Where-Object { $_.Include })
    $freed = [long]0; $del = 0; $fail = 0; $skip = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    PcLog 'porte --clean'
    PcBusy $true 'Limpiando...' ''
    foreach ($l in $locs) {
        PcBusy $true 'Limpiando...' $l.Name
        if ($l.Key -eq 'recycle') {
            try { Clear-RecycleBin -Force -ErrorAction Stop; $freed += $l.Bytes; $del += $l.NFiles } catch { $fail += $l.NFiles }
            continue
        }
        $svc = $false
        if ($l.Key -eq 'wu' -and $PC.IsAdmin) {
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            Stop-Service bits -Force -ErrorAction SilentlyContinue
            $svc = $true
        }
        $i = 0
        foreach ($f in $l.List) {
            $i++
            if ($PC.Safe -and ($PC.RiskyExt -contains ([string]$f.Extension).ToLowerInvariant())) { $skip++; continue }
            if (PcDelFile $f.FullName) { $freed += $f.Length; $del++ } else { $fail++ }
            if (($i % 150) -eq 0) { PcBusy $true ('Limpiando ' + $l.Name) ('{0:N0} de {1:N0}' -f $i, $l.NFiles) }
        }
        if ($svc) {
            Start-Service bits -ErrorAction SilentlyContinue
            Start-Service wuauserv -ErrorAction SilentlyContinue
        }
    }
    foreach ($l in $locs) { PcBusy $true 'Actualizando...' $l.Name; PcScan $l }
    $PC.LastScan = Get-Date
    PcLog ('liberados {0} ({1:N0} archivos)' -f (PcFmt $freed), $del)
    if ($skip -gt 0) { PcLog ('omitidos por modo seguro: {0:N0}' -f $skip) }
    if ($fail -gt 0) { PcLog ('en uso / sin permiso: {0:N0}' -f $fail) }
    PcSidebar; PcTotals; PcShow $PC.Sel; PcLast
    PcBusy $true ('Listo ' + [char]0x00B7 + ' ' + (PcFmt $freed) + ' liberados') ('{0:N0} archivos eliminados' -f $del)
    Start-Sleep -Milliseconds 1500
    PcBusy $false
}

function PcDelFiles {
    $loc = $PC.Sel
    $files = @($PC.SelFiles)
    $freed = [long]0; $ok = 0; $bad = 0; $i = 0
    PcBusy $true 'Eliminando archivos...' ''
    foreach ($f in $files) {
        if (PcDelFile $f.FullName) { $freed += $f.Length; $ok++ } else { $bad++ }
        $i++
        if (($i % 80) -eq 0) { PcBusy $true 'Eliminando archivos...' ('{0} de {1}' -f $i, $files.Count) }
    }
    PcLog ('eliminados {0} archivos ({1})' -f $ok, (PcFmt $freed))
    if ($bad -gt 0) { PcLog ('en uso / sin permiso: {0}' -f $bad) }
    PcScan $loc
    PcSidebar; PcTotals; PcShow $loc
    PcBusy $false
}

function PcRescanAll {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($l in $PC.Locs) { PcBusy $true 'Analizando sistema...' $l.Name; PcScan $l }
    $PC.ScanSecs = $sw.Elapsed.TotalSeconds
    $PC.LastScan = Get-Date
    PcLog ('an' + [char]0x00E1 + 'lisis completo')
    PcSidebar; PcTotals; PcShow $PC.Sel; PcLast
    PcBusy $false
}

# ------------------------------------------------------------------ XAML
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Porte Cleaner" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True" SnapsToDevicePixels="True">
<Window.Resources>
  <Style x:Key="PorteCheck" TargetType="CheckBox">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Border x:Name="Box" Width="20" Height="20" CornerRadius="6" Background="Transparent" BorderThickness="1.2" BorderBrush="{DynamicResource DimBrush}">
            <Path x:Name="Tick" Data="M5,10 L8.5,13.5 L15,6.5" Stroke="{DynamicResource AccentTextBrush}" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed" Stretch="None"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource MutedBrush}"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="Box" Property="Background" Value="{DynamicResource AccentBrush}"/>
              <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="GhostBtn" TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="B" CornerRadius="12" Background="Transparent" BorderThickness="1" BorderBrush="{DynamicResource CardBorderBrush}" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="{DynamicResource HoverBrush}"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="PrimaryBtn" TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource AccentTextBrush}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="B" CornerRadius="12" Background="{DynamicResource AccentBrush}" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.85"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="ScrollBar">
    <Setter Property="Width" Value="8"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Grid Background="Transparent">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0"/></Track.DecreaseRepeatButton>
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Border Background="{DynamicResource DimBrush}" CornerRadius="3" Margin="2,0" MinHeight="24"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
              <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0"/></Track.IncreaseRepeatButton>
            </Track>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</Window.Resources>
<Viewbox Stretch="Uniform">
<Border x:Name="Root" Width="1440" Height="900" CornerRadius="22" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1">
<Grid>
  <Grid x:Name="ParticleHost" IsHitTestVisible="False"/>
  <Ellipse Width="1000" Height="520" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-300,-160,0" Fill="{DynamicResource GlowBrush}" IsHitTestVisible="False"/>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="264"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

    <!-- SIDEBAR -->
    <Border Grid.Column="0" Background="{DynamicResource SidebarBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="0,0,1,0" CornerRadius="21,0,0,21">
      <Grid Margin="16,22,16,18">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="4,0,0,26">
          <Border Width="40" Height="40" CornerRadius="13" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1">
            <TextBlock Text="&#x2726;" FontFamily="Segoe UI Symbol" FontSize="18" Foreground="{DynamicResource TextBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="Porte Cleaner" FontSize="15" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
            <TextBlock Text="V1.0 &#x00B7; WINDOWS" FontSize="9.5" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas" Margin="0,2,0,0"/>
          </StackPanel>
        </StackPanel>
        <Grid Grid.Row="1" Margin="8,0,8,10">
          <TextBlock Text="UBICACIONES" FontSize="10" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas"/>
          <TextBlock x:Name="LocCount" HorizontalAlignment="Right" FontSize="10" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas"/>
        </Grid>
        <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel x:Name="LocList"/>
        </ScrollViewer>
        <Border Grid.Row="3" CornerRadius="16" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="14" Margin="0,12,0,0">
          <StackPanel>
            <StackPanel Orientation="Horizontal">
              <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE756;" FontSize="13" Foreground="{DynamicResource TextBrush}" VerticalAlignment="Center"/>
              <TextBlock Text="Ejecuci&#x00F3;n local" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" Margin="8,0,0,0"/>
            </StackPanel>
            <TextBlock TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource MutedBrush}" Margin="0,8,0,0" Text="Todo corre en este script local. Solo lee y limpia tu Windows, nada sale de tu PC."/>
            <Button x:Name="BtnCopySide" Style="{StaticResource GhostBtn}" Content="Copiar comando irm" Padding="10,7" Margin="0,12,0,0" FontSize="11.5"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>

    <!-- MAIN -->
    <Grid Grid.Column="1" Margin="28,0,28,0">
      <Grid.RowDefinitions>
        <RowDefinition Height="60"/><RowDefinition Height="84"/><RowDefinition Height="112"/><RowDefinition Height="16"/>
        <RowDefinition Height="*"/><RowDefinition Height="16"/><RowDefinition Height="112"/><RowDefinition Height="76"/>
      </Grid.RowDefinitions>

      <!-- topbar -->
      <Grid x:Name="TopBar" Grid.Row="0" Background="Transparent">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE71D;" FontSize="13" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center"/>
          <TextBlock Text="Dashboard" FontSize="12.5" Foreground="{DynamicResource MutedBrush}" Margin="8,0,0,0" VerticalAlignment="Center"/>
          <TextBlock Text="&#x203A;" FontSize="14" Foreground="{DynamicResource DimBrush}" Margin="10,0,10,0" VerticalAlignment="Center"/>
          <TextBlock Text="Limpieza inteligente" FontSize="12.5" Foreground="{DynamicResource TextBrush}" VerticalAlignment="Center"/>
          <Border x:Name="Badge" Margin="14,0,0,0" CornerRadius="9" BorderThickness="1" BorderBrush="{DynamicResource CardBorderBrush}" Background="{DynamicResource HoverBrush}" Padding="9,3" Cursor="Hand">
            <TextBlock x:Name="BadgeText" FontSize="9.5" Foreground="{DynamicResource TextBrush}" FontFamily="Cascadia Mono, Consolas"/>
          </Border>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Border CornerRadius="12" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="3">
            <StackPanel Orientation="Horizontal">
              <Border x:Name="SegDark" CornerRadius="9" Padding="14,6" Cursor="Hand" Background="Transparent"><TextBlock x:Name="SegDarkT" Text="Oscuro" FontSize="11.5"/></Border>
              <Border x:Name="SegLight" CornerRadius="9" Padding="14,6" Cursor="Hand" Background="Transparent"><TextBlock x:Name="SegLightT" Text="Claro" FontSize="11.5"/></Border>
            </StackPanel>
          </Border>
          <Border Width="32" Height="32" CornerRadius="16" Margin="14,0,0,0" Background="{DynamicResource AccentBrush}">
            <TextBlock Text="PC" FontSize="10.5" FontWeight="SemiBold" Foreground="{DynamicResource AccentTextBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <Button x:Name="BtnMin" Style="{StaticResource GhostBtn}" Width="32" Height="32" Margin="14,0,0,0" Padding="0"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE921;" FontSize="10"/></Button>
          <Button x:Name="BtnClose" Style="{StaticResource GhostBtn}" Width="32" Height="32" Margin="6,0,0,0" Padding="0"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE8BB;" FontSize="10"/></Button>
        </StackPanel>
      </Grid>

      <!-- title -->
      <Grid Grid.Row="1">
        <StackPanel VerticalAlignment="Top">
          <TextBlock Text="SISTEMA &#x00B7; AN&#x00C1;LISIS LOCAL" FontSize="10.5" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas"/>
          <TextBlock Text="Limpia lo que ya no necesitas." FontSize="36" FontWeight="SemiBold" Foreground="{DynamicResource TitleBrush}" Margin="0,2,0,0"/>
          <TextBlock Text="Revisa la cach&#x00E9; de Windows antes de borrar. T&#x00FA; decides qu&#x00E9; sale." FontSize="12.5" Foreground="{DynamicResource MutedBrush}" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,0,4">
          <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE121;" FontSize="11" Foreground="{DynamicResource DimBrush}" VerticalAlignment="Center"/>
          <TextBlock x:Name="LastScanText" FontSize="11" Foreground="{DynamicResource MutedBrush}" Margin="7,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>

      <!-- stat cards -->
      <Grid Grid.Row="2">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="14"/><ColumnDefinition/><ColumnDefinition Width="14"/><ColumnDefinition/><ColumnDefinition Width="14"/><ColumnDefinition/></Grid.ColumnDefinitions>
        <Border Grid.Column="0" CornerRadius="18" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="20,16">
          <Grid>
            <StackPanel VerticalAlignment="Center">
              <TextBlock Text="RECUPERABLE" FontSize="10.5" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas"/>
              <TextBlock x:Name="ValRec" FontSize="28" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" FontFamily="Cascadia Mono, Consolas" Margin="0,4,0,2"/>
              <TextBlock x:Name="SubRec" FontSize="11" Foreground="{DynamicResource MutedBrush}"/>
            </StackPanel>
            <Border HorizontalAlignment="Right" VerticalAlignment="Top" Width="34" Height="34" CornerRadius="17" Background="{DynamicResource HoverBrush}"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xEDA2;" FontSize="14" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          </Grid>
        </Border>
        <Border Grid.Column="2" CornerRadius="18" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="20,16">
          <Grid>
            <StackPanel VerticalAlignment="Center">
              <TextBlock Text="ARCHIVOS DETECTADOS" FontSize="10.5" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas"/>
              <TextBlock x:Name="ValFiles" FontSize="28" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" FontFamily="Cascadia Mono, Consolas" Margin="0,4,0,2"/>
              <TextBlock x:Name="SubFiles" FontSize="11" Foreground="{DynamicResource MutedBrush}"/>
            </StackPanel>
            <Border HorizontalAlignment="Right" VerticalAlignment="Top" Width="34" Height="34" CornerRadius="17" Background="{DynamicResource HoverBrush}"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE8A5;" FontSize="14" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          </Grid>
        </Border>
        <Border Grid.Column="4" CornerRadius="18" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="20,16">
          <Grid>
            <StackPanel VerticalAlignment="Center">
              <TextBlock Text="RIESGO DEL SISTEMA" FontSize="10.5" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas"/>
              <TextBlock x:Name="ValRisk" FontSize="28" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" FontFamily="Cascadia Mono, Consolas" Margin="0,4,0,2"/>
              <TextBlock x:Name="SubRisk" FontSize="11" Foreground="{DynamicResource MutedBrush}"/>
            </StackPanel>
            <Border HorizontalAlignment="Right" VerticalAlignment="Top" Width="34" Height="34" CornerRadius="17" Background="{DynamicResource HoverBrush}"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xEA18;" FontSize="14" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          </Grid>
        </Border>
        <Border Grid.Column="6" CornerRadius="18" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="20,16">
          <Grid>
            <StackPanel VerticalAlignment="Center">
              <TextBlock Text="&#x00DA;LTIMO ESCANEO" FontSize="10.5" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas"/>
              <TextBlock x:Name="ValScan" FontSize="28" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" FontFamily="Cascadia Mono, Consolas" Margin="0,4,0,2"/>
              <TextBlock x:Name="SubScan" FontSize="11" Foreground="{DynamicResource MutedBrush}"/>
            </StackPanel>
            <Border HorizontalAlignment="Right" VerticalAlignment="Top" Width="34" Height="34" CornerRadius="17" Background="{DynamicResource HoverBrush}"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE121;" FontSize="14" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          </Grid>
        </Border>
      </Grid>

      <!-- middle: explorer + console -->
      <Grid Grid.Row="4">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="340"/></Grid.ColumnDefinitions>

        <Border Grid.Column="0" CornerRadius="20" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="20,16,20,10">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="46"/><RowDefinition Height="30"/><RowDefinition Height="*"/><RowDefinition Height="34"/></Grid.RowDefinitions>
            <Grid Grid.Row="0">
              <StackPanel VerticalAlignment="Top">
                <StackPanel Orientation="Horizontal">
                  <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE8B7;" FontSize="14" Foreground="{DynamicResource TextBrush}" VerticalAlignment="Center"/>
                  <TextBlock Text="Explorador de cach&#x00E9;" FontSize="15" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" Margin="9,0,0,0"/>
                  <Border CornerRadius="7" Background="{DynamicResource HoverBrush}" Padding="7,2" Margin="10,0,0,0" VerticalAlignment="Center"><TextBlock Text="datos reales" FontSize="9.5" Foreground="{DynamicResource MutedBrush}" FontFamily="Cascadia Mono, Consolas"/></Border>
                </StackPanel>
                <TextBlock x:Name="ExpPath" FontSize="10" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas" Margin="0,4,0,0" TextTrimming="CharacterEllipsis" MaxWidth="400" HorizontalAlignment="Left"/>
              </StackPanel>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
                <Border CornerRadius="12" Background="{DynamicResource HoverBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Width="190" Height="34">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="32"/><ColumnDefinition/></Grid.ColumnDefinitions>
                    <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE721;" FontSize="12" Foreground="{DynamicResource DimBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    <TextBlock x:Name="FilterHint" Grid.Column="1" Text="Filtrar archivos" FontSize="12" Foreground="{DynamicResource DimBrush}" VerticalAlignment="Center" IsHitTestVisible="False"/>
                    <TextBox x:Name="FilterBox" Grid.Column="1" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource TextBrush}" CaretBrush="{DynamicResource TextBrush}" VerticalContentAlignment="Center" FontSize="12"/>
                  </Grid>
                </Border>
                <Button x:Name="BtnRefresh" Style="{StaticResource GhostBtn}" Width="34" Height="34" Margin="8,0,0,0" Padding="0"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE72C;" FontSize="12"/></Button>
                <Button x:Name="BtnOpen" Style="{StaticResource GhostBtn}" Width="34" Height="34" Margin="6,0,0,0" Padding="0"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE712;" FontSize="12"/></Button>
              </StackPanel>
            </Grid>
            <Grid Grid.Row="1" Margin="0,4,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/><ColumnDefinition Width="110"/><ColumnDefinition Width="100"/></Grid.ColumnDefinitions>
              <CheckBox x:Name="ChkAll" Style="{StaticResource PorteCheck}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="1" Text="ARCHIVO" FontSize="10" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="2" Text="TAMA&#x00D1;O" FontSize="10" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="3" Text="MODIFICADO" FontSize="10" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="4" Text="ESTADO" FontSize="10" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas" VerticalAlignment="Center"/>
            </Grid>
            <ScrollViewer Grid.Row="2" x:Name="FileScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
              <StackPanel x:Name="FileList"/>
            </ScrollViewer>
            <Grid Grid.Row="3">
              <TextBlock x:Name="SelText" FontSize="11" Foreground="{DynamicResource MutedBrush}" FontFamily="Cascadia Mono, Consolas" VerticalAlignment="Center"/>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                <Button x:Name="BtnDelSel" Style="{StaticResource GhostBtn}" Content="Eliminar selecci&#x00F3;n" FontSize="11" Padding="12,5" Margin="0,0,14,0" Visibility="Collapsed"/>
                <TextBlock x:Name="CountText" FontSize="11" Foreground="{DynamicResource MutedBrush}" FontFamily="Cascadia Mono, Consolas" VerticalAlignment="Center"/>
              </StackPanel>
            </Grid>
          </Grid>
        </Border>

        <Border Grid.Column="2" CornerRadius="20" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="18,16">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="86"/><RowDefinition Height="*"/><RowDefinition Height="22"/><RowDefinition Height="38"/></Grid.RowDefinitions>
            <Grid Grid.Row="0">
              <TextBlock Text="&gt;_  PowerShell Console" FontSize="13.5" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" VerticalAlignment="Top"/>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,3,0,0">
                <Ellipse Width="6" Height="6" Fill="{DynamicResource GreenBrush}" Margin="0,0,6,0"/>
                <TextBlock Text="ready" FontSize="10" Foreground="{DynamicResource GreenBrush}" FontFamily="Cascadia Mono, Consolas"/>
              </StackPanel>
            </Grid>
            <Border Grid.Row="1" CornerRadius="12" Background="{DynamicResource ConsoleBrush}" Padding="12,10">
              <TextBlock x:Name="ArtText" FontFamily="Consolas" FontSize="8" LineHeight="8" LineStackingStrategy="BlockLineHeight" Foreground="{DynamicResource TextBrush}" VerticalAlignment="Center" HorizontalAlignment="Center"/>
            </Border>
            <ScrollViewer Grid.Row="2" Margin="0,10,0,0" VerticalScrollBarVisibility="Hidden" HorizontalScrollBarVisibility="Disabled">
              <TextBlock x:Name="LogText" FontFamily="Cascadia Mono, Consolas" FontSize="10.5" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap"/>
            </ScrollViewer>
            <TextBlock Grid.Row="3" Text="COMANDO POWERSHELL" FontSize="9.5" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas" VerticalAlignment="Bottom" Margin="0,0,0,4"/>
            <Border Grid.Row="4" CornerRadius="10" Background="{DynamicResource ConsoleBrush}" Padding="10,0,6,0">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="CmdText" FontFamily="Cascadia Mono, Consolas" FontSize="9.5" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                <Button x:Name="BtnCopy" Grid.Column="1" Style="{StaticResource GhostBtn}" Width="26" Height="26" Padding="0" BorderThickness="0"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE8C8;" FontSize="11"/></Button>
              </Grid>
            </Border>
          </Grid>
        </Border>
      </Grid>

      <!-- bottom cards -->
      <Grid Grid.Row="6">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Grid.Column="0" CornerRadius="18" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="22,14">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Grid Grid.Row="0">
              <TextBlock Text="Estado de recuperaci&#x00F3;n" FontSize="14.5" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
              <TextBlock x:Name="RecPct" HorizontalAlignment="Right" FontSize="12" Foreground="{DynamicResource MutedBrush}" FontFamily="Cascadia Mono, Consolas"/>
            </Grid>
            <TextBlock Grid.Row="1" Text="Potencial estimado sobre las ubicaciones activas" FontSize="11" Foreground="{DynamicResource MutedBrush}" Margin="0,2,0,0"/>
            <Border Grid.Row="2" Height="9" CornerRadius="5" Background="{DynamicResource TrackBrush}" VerticalAlignment="Center">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition x:Name="RecCol0" Width="0*"/><ColumnDefinition x:Name="RecCol1" Width="1*"/></Grid.ColumnDefinitions>
                <Border CornerRadius="5" Background="{DynamicResource BarBrush}"/>
              </Grid>
            </Border>
            <TextBlock Grid.Row="3" x:Name="RecNames" FontSize="10" Foreground="{DynamicResource DimBrush}" FontFamily="Cascadia Mono, Consolas" TextTrimming="CharacterEllipsis"/>
          </Grid>
        </Border>
        <Border x:Name="SafeCard" Grid.Column="2" CornerRadius="18" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="20,14" Cursor="Hand">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition Width="*"/><ColumnDefinition Width="26"/></Grid.ColumnDefinitions>
            <Border Width="36" Height="36" CornerRadius="12" Background="{DynamicResource HoverBrush}" VerticalAlignment="Top"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xEA18;" FontSize="15" Foreground="{DynamicResource TextBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <StackPanel Grid.Column="1" VerticalAlignment="Center">
              <TextBlock x:Name="SafeTitle" FontSize="14.5" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
              <TextBlock x:Name="SafeText" FontSize="11" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap" Margin="0,3,0,0"/>
            </StackPanel>
            <TextBlock x:Name="SafeMark" Grid.Column="2" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="{DynamicResource GreenBrush}" VerticalAlignment="Top" HorizontalAlignment="Right" Margin="0,4,0,0"/>
          </Grid>
        </Border>
      </Grid>

      <!-- floating action bar -->
      <Border Grid.Row="7" HorizontalAlignment="Center" VerticalAlignment="Center" CornerRadius="18" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="20,10">
        <StackPanel Orientation="Horizontal">
          <StackPanel VerticalAlignment="Center" Margin="0,0,28,0">
            <TextBlock x:Name="BarInfo1" FontSize="10.5" Foreground="{DynamicResource MutedBrush}" FontFamily="Cascadia Mono, Consolas"/>
            <TextBlock x:Name="BarInfo2" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" FontFamily="Cascadia Mono, Consolas"/>
          </StackPanel>
          <Button x:Name="BtnScan" Style="{StaticResource GhostBtn}" Padding="16,10" Margin="0,0,10,0">
            <StackPanel Orientation="Horizontal"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE72C;" FontSize="12" VerticalAlignment="Center"/><TextBlock Text="Analizar sistema" FontSize="12.5" Margin="9,0,0,0"/></StackPanel>
          </Button>
          <Button x:Name="BtnClean" Style="{StaticResource PrimaryBtn}" Padding="18,10">
            <StackPanel Orientation="Horizontal"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE74D;" FontSize="12" VerticalAlignment="Center"/><TextBlock Text="Limpiar seleccionados" FontSize="12.5" FontWeight="SemiBold" Margin="9,0,0,0"/></StackPanel>
          </Button>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>

  <!-- overlays -->
  <Border x:Name="BusyOverlay" Visibility="Collapsed" CornerRadius="22" Background="#D0050506">
    <Border HorizontalAlignment="Center" VerticalAlignment="Center" CornerRadius="20" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="36,28" MinWidth="380">
      <StackPanel>
        <TextBlock x:Name="BusyText" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" HorizontalAlignment="Center"/>
        <TextBlock x:Name="BusySub" FontSize="11.5" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Center" Margin="0,6,0,18" FontFamily="Cascadia Mono, Consolas"/>
        <Border Height="4" CornerRadius="2" Background="{DynamicResource TrackBrush}" ClipToBounds="True">
          <Border Width="90" HorizontalAlignment="Left" CornerRadius="2" Background="{DynamicResource BarBrush}">
            <Border.RenderTransform><TranslateTransform x:Name="BusyTrans"/></Border.RenderTransform>
          </Border>
        </Border>
      </StackPanel>
    </Border>
  </Border>
  <Border x:Name="ConfirmOverlay" Visibility="Collapsed" CornerRadius="22" Background="#D0050506">
    <Border HorizontalAlignment="Center" VerticalAlignment="Center" CornerRadius="20" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1" Padding="30,26" Width="440">
      <StackPanel>
        <TextBlock x:Name="CfTitle" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
        <TextBlock x:Name="CfText" FontSize="12.5" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap" Margin="0,8,0,22"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="CfCancel" Style="{StaticResource GhostBtn}" Content="Cancelar" Padding="18,9" Margin="0,0,10,0"/>
          <Button x:Name="CfOk" Style="{StaticResource PrimaryBtn}" Content="Continuar" Padding="20,9"/>
        </StackPanel>
      </StackPanel>
    </Border>
  </Border>
</Grid>
</Border>
</Viewbox>
</Window>
'@

# ------------------------------------------------------------------ campo de particulas (nodes glow)
$fieldSrc = @'
using System;
using System.Windows;
using System.Windows.Media;

public class PorteField : FrameworkElement
{
    class Node { public double X, Y, VX, VY, R, Ph, Sp; }
    Node[] nodes;
    Random rnd = new Random();
    Color col = Colors.White;
    double alphaMul = 0.9;
    Brush glow;
    Pen[] pens;
    long last;
    double t = 0;
    public double Radius = 22;

    public PorteField()
    {
        IsHitTestVisible = false;
        Loaded += delegate { CompositionTarget.Rendering += Tick; last = DateTime.UtcNow.Ticks; };
        Unloaded += delegate { CompositionTarget.Rendering -= Tick; };
        Rebuild();
    }

    public void SetColor(Color c, double a) { col = c; alphaMul = a; Rebuild(); InvalidateVisual(); }

    void Rebuild()
    {
        RadialGradientBrush rb = new RadialGradientBrush();
        rb.GradientStops.Add(new GradientStop(Color.FromArgb(255, col.R, col.G, col.B), 0.0));
        rb.GradientStops.Add(new GradientStop(Color.FromArgb(70, col.R, col.G, col.B), 0.30));
        rb.GradientStops.Add(new GradientStop(Color.FromArgb(0, col.R, col.G, col.B), 1.0));
        rb.Freeze();
        glow = rb;
        pens = new Pen[24];
        for (int i = 0; i < pens.Length; i++)
        {
            byte al = (byte)(Math.Min(255.0, (i + 1) / 24.0 * 80.0 * alphaMul));
            SolidColorBrush b = new SolidColorBrush(Color.FromArgb(al, col.R, col.G, col.B));
            b.Freeze();
            Pen p = new Pen(b, 0.8);
            p.Freeze();
            pens[i] = p;
        }
    }

    void Init()
    {
        int n = 58;
        nodes = new Node[n];
        for (int i = 0; i < n; i++)
        {
            Node d = new Node();
            d.X = rnd.NextDouble() * ActualWidth;
            d.Y = rnd.NextDouble() * ActualHeight;
            double a = rnd.NextDouble() * Math.PI * 2;
            double sp = 5 + rnd.NextDouble() * 13;
            d.VX = Math.Cos(a) * sp; d.VY = Math.Sin(a) * sp;
            d.R = 1.0 + rnd.NextDouble() * 1.7;
            d.Ph = rnd.NextDouble() * 6.28;
            d.Sp = 0.6 + rnd.NextDouble() * 1.4;
            nodes[i] = d;
        }
    }

    void Tick(object s, EventArgs e)
    {
        if (ActualWidth < 10 || ActualHeight < 10) return;
        if (nodes == null) Init();
        long now = DateTime.UtcNow.Ticks;
        double dt = (now - last) / 10000000.0;
        last = now;
        if (dt > 0.1) dt = 0.1;
        t += dt;
        double w = ActualWidth, h = ActualHeight;
        for (int i = 0; i < nodes.Length; i++)
        {
            Node d = nodes[i];
            d.X += d.VX * dt; d.Y += d.VY * dt;
            if (d.X < -10) d.X = w + 10; else if (d.X > w + 10) d.X = -10;
            if (d.Y < -10) d.Y = h + 10; else if (d.Y > h + 10) d.Y = -10;
        }
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        if (nodes == null) return;
        double w = ActualWidth, h = ActualHeight;
        dc.PushClip(new RectangleGeometry(new Rect(0, 0, w, h), Radius, Radius));
        double link = 150.0, link2 = link * link;
        for (int i = 0; i < nodes.Length; i++)
        {
            for (int j = i + 1; j < nodes.Length; j++)
            {
                double dx = nodes[i].X - nodes[j].X, dy = nodes[i].Y - nodes[j].Y;
                double d2 = dx * dx + dy * dy;
                if (d2 < link2)
                {
                    double a = 1.0 - Math.Sqrt(d2) / link;
                    int idx = (int)(a * 23);
                    if (idx < 0) idx = 0; if (idx > 23) idx = 23;
                    dc.DrawLine(pens[idx], new Point(nodes[i].X, nodes[i].Y), new Point(nodes[j].X, nodes[j].Y));
                }
            }
        }
        for (int i = 0; i < nodes.Length; i++)
        {
            Node d = nodes[i];
            double tw = 0.55 + 0.45 * Math.Sin(t * d.Sp + d.Ph);
            dc.PushOpacity(Math.Max(0.05, Math.Min(1.0, tw * alphaMul)));
            dc.DrawEllipse(glow, null, new Point(d.X, d.Y), d.R * 7, d.R * 7);
            dc.Pop();
        }
        dc.Pop();
    }
}
'@

# ------------------------------------------------------------------ 1) carga en consola
PcBanner
PcStep 6 'Inicializando...'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
PcStep 14 'Cargando interfaz...'
if (-not ('PorteField' -as [type])) {
    Add-Type -ReferencedAssemblies PresentationCore, PresentationFramework, WindowsBase, System.Xaml -TypeDefinition $fieldSrc -Language CSharp
}
PcStep 22 'Comprobando permisos...'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$n = $PC.Locs.Count; $k = 0
foreach ($l in $PC.Locs) {
    $target = 24 + [int](66 * $k / $n)
    PcStep $target ('Escaneando ' + $l.Name + '...')
    PcScan $l
    $k++
}
$PC.ScanSecs = $sw.Elapsed.TotalSeconds
PcStep 96 'Construyendo ventana...'

# ------------------------------------------------------------------ 2) ventana
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
$PC.Win = $win
$wa = [System.Windows.SystemParameters]::WorkArea
$scale = [Math]::Min(1.0, [Math]::Min(($wa.Width - 30) / 1440, ($wa.Height - 30) / 900))
$win.Width = 1440 * $scale
$win.Height = 900 * $scale

$PC.UI = @{}
foreach ($nm in 'Root','ParticleHost','TopBar','Badge','BadgeText','SegDark','SegDarkT','SegLight','SegLightT','BtnMin','BtnClose','LocList','LocCount','BtnCopySide',
    'ValRec','SubRec','ValFiles','SubFiles','ValRisk','SubRisk','ValScan','SubScan','LastScanText','ExpPath','FilterBox','FilterHint','BtnRefresh','BtnOpen','ChkAll',
    'FileList','SelText','CountText','BtnDelSel','ArtText','LogText','CmdText','BtnCopy','RecPct','RecCol0','RecCol1','RecNames','SafeCard','SafeTitle','SafeText','SafeMark',
    'BarInfo1','BarInfo2','BtnScan','BtnClean','BusyOverlay','BusyText','BusySub','BusyTrans','ConfirmOverlay','CfTitle','CfText','CfCancel','CfOk') {
    $PC.UI[$nm] = $win.FindName($nm)
}
$u = $PC.UI

# particulas
$PC.Field = New-Object PorteField
[void]$u.ParticleHost.Children.Add($PC.Field)

# arte PORTE
$u.ArtText.Text = ((PcArt 2) -join "`n")
$u.CmdText.Text = $PC.Cmd

# badge admin
if ($PC.IsAdmin) { $u.BadgeText.Text = 'ADMIN' } else { $u.BadgeText.Text = 'SIN ADMIN ' + [char]0x00B7 + ' ELEVAR' }

# sidebar
foreach ($loc in $PC.Locs) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = [System.Windows.CornerRadius]::new(14)
    $b.Padding = [System.Windows.Thickness]::new(10, 9, 12, 9)
    $b.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
    $b.BorderThickness = [System.Windows.Thickness]::new(1)
    $b.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    $b.Background = [System.Windows.Media.Brushes]::Transparent
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.Tag = $loc.Key
    $g = New-Object System.Windows.Controls.Grid
    foreach ($wd in 44, -1, 28) {
        $c = New-Object System.Windows.Controls.ColumnDefinition
        if ($wd -lt 0) { $c.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) } else { $c.Width = [System.Windows.GridLength]::new($wd) }
        $g.ColumnDefinitions.Add($c)
    }
    $ib = New-Object System.Windows.Controls.Border
    $ib.Width = 34; $ib.Height = 34; $ib.CornerRadius = [System.Windows.CornerRadius]::new(11)
    $ib.HorizontalAlignment = 'Left'
    $ib.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'HoverBrush')
    $ic = PcText ([string][char][int]$loc.Glyph) 'MutedBrush' 14 'Segoe MDL2 Assets'
    $ic.HorizontalAlignment = 'Center'
    $ib.Child = $ic
    [void]$g.Children.Add($ib)
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'
    $nm1 = PcText $loc.Name 'TextBrush' 13 '' 'b'
    $nm1.TextTrimming = 'CharacterEllipsis'
    $sub = PcText '' 'DimBrush' 10 'Cascadia Mono, Consolas'
    $sub.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    [void]$sp.Children.Add($nm1); [void]$sp.Children.Add($sub)
    [System.Windows.Controls.Grid]::SetColumn($sp, 1); [void]$g.Children.Add($sp)
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Style = $win.FindResource('PorteCheck')
    $cb.Tag = $loc.Key
    $cb.IsChecked = [bool]$loc.Include
    $cb.VerticalAlignment = 'Center'; $cb.HorizontalAlignment = 'Right'
    $cb.Add_Checked({ param($s, $e) (PcLoc $s.Tag).Include = $true; PcTotals })
    $cb.Add_Unchecked({ param($s, $e) (PcLoc $s.Tag).Include = $false; PcTotals })
    [System.Windows.Controls.Grid]::SetColumn($cb, 2); [void]$g.Children.Add($cb)
    $b.Child = $g
    $b.Add_MouseLeftButtonUp({ param($s, $e) PcShow (PcLoc $s.Tag) })
    $b.Add_MouseEnter({ param($s, $e) if ($PC.Sel.Key -ne $s.Tag) { $s.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'HoverBrush') } })
    $b.Add_MouseLeave({ param($s, $e) if ($PC.Sel.Key -ne $s.Tag) { $s.Background = [System.Windows.Media.Brushes]::Transparent } })
    $loc.Border = $b; $loc.Sub = $sub
    [void]$u.LocList.Children.Add($b)
}

# eventos
$u.TopBar.Add_MouseLeftButtonDown({ try { $PC.Win.DragMove() } catch {} })
$u.BtnMin.Add_Click({ $PC.Win.WindowState = 'Minimized' })
$u.BtnClose.Add_Click({ $PC.Win.Close() })
$u.SegDark.Add_MouseLeftButtonUp({ PcTheme $true })
$u.SegLight.Add_MouseLeftButtonUp({ PcTheme $false })
$u.FilterBox.Add_TextChanged({
    if ($PC.UI.FilterBox.Text.Length -gt 0) { $PC.UI.FilterHint.Visibility = 'Collapsed' } else { $PC.UI.FilterHint.Visibility = 'Visible' }
    PcFiles
})
$u.ChkAll.Add_Checked({ if (-not $PC.Busy) { foreach ($c in @($PC.RowChecks)) { $c.IsChecked = $true } } })
$u.ChkAll.Add_Unchecked({ if (-not $PC.Busy) { foreach ($c in @($PC.RowChecks)) { $c.IsChecked = $false } } })
$u.BtnRefresh.Add_Click({
    PcBusy $true 'Analizando...' $PC.Sel.Name
    PcScan $PC.Sel
    PcSidebar; PcTotals; PcShow $PC.Sel
    PcBusy $false
})
$u.BtnOpen.Add_Click({
    if ($PC.Sel.Key -eq 'recycle') { Start-Process 'explorer.exe' 'shell:RecycleBinFolder' }
    elseif (Test-Path -LiteralPath $PC.Sel.Paths[0]) { Start-Process 'explorer.exe' $PC.Sel.Paths[0] }
})
$copy = { [System.Windows.Clipboard]::SetText($PC.Cmd); PcLog 'comando copiado al portapapeles'; PcConsole }
$u.BtnCopy.Add_Click($copy)
$u.BtnCopySide.Add_Click($copy)
$u.BtnScan.Add_Click({ PcRescanAll })
$u.BtnClean.Add_Click({
    $inc = @($PC.Locs | Where-Object { $_.Include })
    if ($inc.Count -eq 0) { PcConfirm 'info' 'Nada seleccionado' ('Activa al menos una ubicaci' + [char]0x00F3 + 'n en la barra lateral.'); return }
    $msg = ('Se eliminar' + [char]0x00E1 + 'n archivos de {0} ubicaciones ({1}). Esta acci' + [char]0x00F3 + 'n no se puede deshacer.') -f $inc.Count, (PcFmt $PC.IncBytes)
    PcConfirm 'clean' 'Limpiar ubicaciones' $msg
})
$u.BtnDelSel.Add_Click({
    if ($PC.Sel.Key -eq 'recycle') { PcConfirm 'info' 'Papelera' ('La papelera se vac' + [char]0x00ED + 'a completa desde "Limpiar seleccionados".'); return }
    $sum = [long]0; foreach ($f in $PC.SelFiles) { $sum += $f.Length }
    PcConfirm 'files' 'Eliminar archivos' (('Se eliminar' + [char]0x00E1 + 'n {0} archivos ({1}).') -f $PC.SelFiles.Count, (PcFmt $sum))
})
$u.CfCancel.Add_Click({ $PC.UI.ConfirmOverlay.Visibility = 'Collapsed' })
$u.CfOk.Add_Click({
    $PC.UI.ConfirmOverlay.Visibility = 'Collapsed'
    switch ($PC.ConfirmKind) { 'clean' { PcClean } 'files' { PcDelFiles } }
})
$u.Badge.Add_MouseLeftButtonUp({
    if ($PC.IsAdmin) { return }
    if ($PC.Url -match 'TU_USUARIO') { PcLog 'configura $PC.Url para poder elevar'; PcConsole; return }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $PC.Cmd)
        $PC.Win.Close()
    } catch { PcLog ('elevaci' + [char]0x00F3 + 'n cancelada'); PcConsole }
})

function PcSafe {
    $u = $PC.UI
    if ($PC.Safe) {
        $u.SafeTitle.Text = 'Modo seguro activado'
        $u.SafeText.Text = 'Se omiten ejecutables y librer' + [char]0x00ED + 'as (.exe, .dll, .sys...). Toca para cambiar.'
        $u.SafeMark.Text = [string][char]0xE73E
    } else {
        $u.SafeTitle.Text = 'Modo seguro desactivado'
        $u.SafeText.Text = 'Tambi' + [char]0x00E9 + 'n se eliminar' + [char]0x00E1 + 'n archivos marcados como "Revisar". Toca para cambiar.'
        $u.SafeMark.Text = [string][char]0xE711
    }
}
$u.SafeCard.Add_MouseLeftButtonUp({ $PC.Safe = -not $PC.Safe; PcSafe })

# animacion barra de carga (overlay)
$an = [System.Windows.Media.Animation.DoubleAnimation]::new(-90.0, 340.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1100)))
$an.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
$u.BusyTrans.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $an)

# timer (cursor consola + "ultimo analisis")
$PC.Timer = New-Object System.Windows.Threading.DispatcherTimer
$PC.Timer.Interval = [TimeSpan]::FromMilliseconds(500)
$PC.Timer.Add_Tick({
    $PC.Cursor = -not $PC.Cursor
    $PC.Tick++
    PcConsole
    if (($PC.Tick % 40) -eq 0) { PcLast }
})

# estado inicial
PcTheme $true
PcSafe
PcLog ('sesi' + [char]0x00F3 + 'n iniciada')
if (-not $PC.IsAdmin) { PcLog 'sin admin: Prefetch/WU limitados' }
PcSidebar
PcTotals
$best = $PC.Locs | Sort-Object { $_.Bytes } -Descending | Select-Object -First 1
PcShow $best
PcLast
$PC.Timer.Start()

$win.Opacity = 0
$win.Add_ContentRendered({
    $fade = [System.Windows.Media.Animation.DoubleAnimation]::new(0.0, 1.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(550)))
    $PC.Win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)
})

PcStep 100 'Listo'
Write-Host ''
Write-Host '  Abriendo Porte Cleaner...' -ForegroundColor Gray
[void]$win.ShowDialog()

# ------------------------------------------------------------------ limpieza al cerrar
try { $PC.Timer.Stop() } catch {}
Write-Host '  Hasta pronto.' -ForegroundColor DarkGray
Get-ChildItem Function:\Pc* -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
Remove-Variable PC, xaml, fieldSrc, win, wa, scale, u, w_, sw, n, k, an, best, copy, loc, b, g, ib, ic, sp, nm1, sub, cb, c, wd, nm, target, l -Scope Global -ErrorAction SilentlyContinue
