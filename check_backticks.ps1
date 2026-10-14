$path = 'f:\APP\pdf.html'
$s = Get-Content -Raw -Path $path
$count = ($s -split '`').Length - 1
Write-Output "backtick count: $count"
$open = $false
foreach ($c in $s.ToCharArray()) {
    if ($c -eq '`') { $open = -not $open }
}
Write-Output "template open at end: $open"
# print lines around potential issue: find index of first unmatched backtick occurrence if open true
if ($open) {
    $indexes = @()
    for ($i=0;$i -lt $s.Length;$i++) { if ($s[$i] -eq '`') { $indexes += $i } }
    Write-Output "backtick positions count: $($indexes.Count)"
    Write-Output "last backtick pos: $($indexes[-1])"
    $pos = $indexes[-1]
    $start = [Math]::Max(0,$pos-200)
    $len = [Math]::Min(400,$s.Length - $start)
    Write-Output "Context around last backtick (approx):"
    Write-Output $s.Substring($start,$len)
}
