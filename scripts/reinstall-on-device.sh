#!/bin/zsh
# Keeps Interval Timer installed on an iPhone signed with a free Apple ID, whose
# signing runs out after 7 days. A daily launchd job rebuilds `main` from GitHub
# and reinstalls it once the last install is MIN_DAYS old, retrying the next day
# if the phone wasn't reachable or the build failed.
#
#   scripts/reinstall-on-device.sh setup     install (or update) the daily job
#   scripts/reinstall-on-device.sh remove    remove the daily job
#   scripts/reinstall-on-device.sh run       what the job runs; add --force to skip the age check
#
# launchd jobs can't read ~/Documents, so `setup` copies this script, and the job
# builds its own clone, under ~/Library/Application Support/IntervalTimerReinstall.
#
# Settings (env vars, defaults for this Mac): DEVICE_ID, TEAM_ID, MIN_DAYS, HOUR.

set -u
SELF="${0:A}"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"

DEVICE_ID="${DEVICE_ID:-00008101-00167D223450001E}"
TEAM_ID="${TEAM_ID:-K2T6KDC64F}"
MIN_DAYS="${MIN_DAYS:-4}"
HOUR="${HOUR:-19}"
REPO_URL="https://github.com/MrMallon/Interval-Timer.git"

LABEL="com.mrmallon.intervaltimer.reinstall"
STATE_DIR="$HOME/Library/Application Support/IntervalTimerReinstall"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/IntervalTimerReinstall.log"

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

setup() {
  mkdir -p "$STATE_DIR" "$(dirname "$PLIST")"
  cp "$SELF" "$STATE_DIR/reinstall-on-device.sh"
  chmod +x "$STATE_DIR/reinstall-on-device.sh"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$STATE_DIR/reinstall-on-device.sh</string>
        <string>run</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DEVICE_ID</key><string>$DEVICE_ID</string>
        <key>TEAM_ID</key><string>$TEAM_ID</string>
        <key>MIN_DAYS</key><string>$MIN_DAYS</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>$HOUR</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST" && \
    print "Daily job set for $HOUR:00. Log: $LOG"
}

remove() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  rm -f "$PLIST"
  rm -rf "$STATE_DIR"
  print "Removed the daily reinstall job."
}

run() {
  local stamp="$STATE_DIR/last-install" src="$STATE_DIR/repo" derived="$STATE_DIR/DerivedData"
  mkdir -p "$STATE_DIR"

  if [[ "${1:-}" != "--force" && -f "$stamp" ]]; then
    local age_days=$(( ( $(date +%s) - $(stat -f %m "$stamp") ) / 86400 ))
    if (( age_days < MIN_DAYS )); then
      log "Last install was $age_days day(s) ago; nothing to do."
      return 0
    fi
  fi

  if ! xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE_ID.*connected"; then
    log "iPhone $DEVICE_ID isn't reachable (needs the same Wi-Fi or a cable). Will retry next run."
    return 1
  fi

  log "Updating source from GitHub main"
  if [[ -d "$src/.git" ]]; then
    git -C "$src" fetch --quiet origin main && git -C "$src" reset --quiet --hard origin/main
  else
    git clone --quiet --branch main "$REPO_URL" "$src"
  fi || { log "Couldn't fetch the source. Will retry next run."; return 1; }

  cd "$src" || return 1
  xcodegen --quiet || { log "xcodegen failed"; return 1; }

  log "Building $(git rev-parse --short HEAD)"
  if ! xcodebuild -project IntervalTimer.xcodeproj -scheme IntervalTimer \
       -configuration Debug -destination "id=$DEVICE_ID" \
       -derivedDataPath "$derived" -allowProvisioningUpdates \
       DEVELOPMENT_TEAM="$TEAM_ID" build -quiet; then
    log "Build failed; the installed app was left alone. Will retry next run."
    return 1
  fi

  log "Installing"
  if ! xcrun devicectl device install app --device "$DEVICE_ID" \
       "$derived/Build/Products/Debug-iphoneos/IntervalTimer.app" >/dev/null; then
    log "Install failed. Will retry next run."
    return 1
  fi

  touch "$stamp"
  log "Installed; signing is good for another 7 days."
}

case "${1:-}" in
  setup)  setup ;;
  remove) remove ;;
  run)    shift; run "$@" ;;
  *)      print "Usage: $0 setup | remove | run [--force]"; exit 2 ;;
esac
