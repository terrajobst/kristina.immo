# Builds the site and serves it locally with live reload, inside a Linux
# container matching CI (Ruby 3.4). No local Ruby install needed.
#
# Requires Podman:
#     winget install --id RedHat.Podman
#
# Any extra arguments are passed through to Jekyll, for example:
#     .\run.ps1 --incremental

Set-Location $PSScriptRoot

$image = "docker.io/library/ruby:3.4"
$container = "kristina-immo-serve"
$gemVolume = "kristina-immo-gems"

if (-not (Get-Command podman -ErrorAction Ignore)) {
    Write-Host ""
    Write-Host "ERROR: Podman was not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install it with:"
    Write-Host "    winget install --id RedHat.Podman"
    Write-Host ""
    exit 1
}

# The Podman VM does not survive a reboot, so start it on demand.
podman info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Starting the Podman machine..."
    podman machine start
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: could not start the Podman machine." -ForegroundColor Red
        Write-Host "Create one first with: podman machine init" -ForegroundColor Red
        exit 1
    }
}

# inotify events do not cross the Windows/Linux filesystem boundary, so Jekyll
# has to poll for changes instead of watching. Gems live in a named volume so
# 'bundle install' only does real work the first time.
$jekyllArgs = "--host 127.0.0.1 --livereload --force_polling"
if ($args.Count -gt 0) {
    $jekyllArgs += " " + ($args -join " ")
}

$inner = "bundle install --quiet && exec bundle exec jekyll serve $jekyllArgs"

# Attached but with no TTY: Jekyll's output is plain text, and asking for a TTY
# fails in any context without a real console. Podman still forwards Ctrl+C.
#
# --network=host rather than -p: WSL only forwards localhost into Windows for
# listeners in the VM's own network namespace, and rootless Podman would
# otherwise publish the ports inside a namespace Windows cannot see.
[string[]] $runArgs = @("run", "--rm", "--replace", "--name", $container, "-i") + @(
    "--network", "host",
    "-v", "$($PWD.Path):/srv/jekyll",
    "-v", "${gemVolume}:/usr/local/bundle",
    "-w", "/srv/jekyll",
    $image,
    "bash", "-lc", $inner
)

Write-Host ""
Write-Host "Serving on http://localhost:4000 -- press Ctrl+C to stop."
Write-Host ""
& podman @runArgs
exit $LASTEXITCODE