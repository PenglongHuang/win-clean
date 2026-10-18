param([Parameter(Mandatory=$true)][string]$Root)
# Fixture layout (bytes deterministic):
#   <Root>\Local\pip\cache\a1.bin (1024), a2.bin (2048)         -> pip-cache = 3072
#   <Root>\Local\Temp\t1.tmp (512)                               -> user-temp = 512
#   <Root>\Local\uv\cache\u1.bin (4096)                          -> uv-cache  = 4096
#   <Root>\Roaming\Code\CachedExtensionVSIXs\e1.vsix (256)       -> vscode-vsix-cache = 256
$dirs = @(
    "$Root\Local\pip\cache", "$Root\Local\Temp", "$Root\Local\uv\cache",
    "$Root\Roaming\Code\CachedExtensionVSIXs"
)
foreach ($d in $dirs) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$files = @(
    @("$Root\Local\pip\cache\a1.bin", 1024),
    @("$Root\Local\pip\cache\a2.bin", 2048),
    @("$Root\Local\Temp\t1.tmp", 512),
    @("$Root\Local\uv\cache\u1.bin", 4096),
    @("$Root\Roaming\Code\CachedExtensionVSIXs\e1.vsix", 256)
)
foreach ($f in $files) {
    $bytes = New-Object byte[] $f[1]
    [IO.File]::WriteAllBytes($f[0], $bytes)
}
