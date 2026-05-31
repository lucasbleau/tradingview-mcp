#!/bin/bash
# Launch TradingView Desktop on macOS with Chrome DevTools Protocol enabled
# Usage: ./scripts/launch_tv_debug_mac.sh [port]

PORT="${1:-9222}"

# Auto-detect TradingView install location
APP=""
LOCATIONS=(
  "/Applications/TradingView.app/Contents/MacOS/TradingView"
  "$HOME/Applications/TradingView.app/Contents/MacOS/TradingView"
)

for loc in "${LOCATIONS[@]}"; do
  if [ -f "$loc" ]; then
    APP="$loc"
    break
  fi
done

# Fallback: search with mdfind (Spotlight)
if [ -z "$APP" ]; then
  APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.niceincontact.TradingView'" 2>/dev/null | head -1)
  if [ -n "$APP" ]; then
    APP="$APP/Contents/MacOS/TradingView"
  fi
fi

# Fallback: find any TradingView.app
if [ -z "$APP" ] || [ ! -f "$APP" ]; then
  APP=$(find /Applications "$HOME/Applications" -name "TradingView.app" -maxdepth 2 2>/dev/null | head -1)
  if [ -n "$APP" ]; then
    APP="$APP/Contents/MacOS/TradingView"
  fi
fi

if [ -z "$APP" ] || [ ! -f "$APP" ]; then
  echo "Error: TradingView not found."
  echo "Checked: /Applications/TradingView.app, ~/Applications/TradingView.app"
  echo ""
  echo "If installed elsewhere, run manually:"
  echo "  /path/to/TradingView.app/Contents/MacOS/TradingView --remote-debugging-port=$PORT"
  exit 1
fi

# If CDP already responding on the requested port, do nothing.
if curl -s "http://localhost:$PORT/json/version" > /dev/null 2>&1; then
  echo "CDP already responding on port $PORT — nothing to do."
  curl -s "http://localhost:$PORT/json/version"
  exit 0
fi

# SIGTERM is trapped by the app (single-instance lock survives), so launching
# again would just forward to the running instance and the new process — with
# the debug flag — would exit immediately. Use SIGKILL and poll.
if pgrep -f "TradingView" > /dev/null 2>&1; then
  echo "Stopping existing TradingView..."
  pkill -9 -f "TradingView" 2>/dev/null
  for i in $(seq 1 10); do
    pgrep -f "TradingView" > /dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -f "TradingView" > /dev/null 2>&1; then
    echo "Error: TradingView processes still alive after SIGKILL."
    pgrep -lf "TradingView" | head -5
    exit 1
  fi
fi

echo "Found TradingView at: $APP"
echo "Launching with --remote-debugging-port=$PORT ..."
nohup "$APP" --remote-debugging-port=$PORT > /tmp/tradingview-cdp.log 2>&1 &
TV_PID=$!
disown $TV_PID 2>/dev/null
echo "PID: $TV_PID  (log: /tmp/tradingview-cdp.log)"

# Wait for CDP to be ready
echo "Waiting for CDP..."
for i in $(seq 1 15); do
  if curl -s "http://localhost:$PORT/json/version" > /dev/null 2>&1; then
    echo "CDP ready at http://localhost:$PORT"
    curl -s "http://localhost:$PORT/json/version" | python3 -m json.tool 2>/dev/null || curl -s "http://localhost:$PORT/json/version"
    exit 0
  fi
  sleep 1
done

echo "Warning: CDP not responding after 15s. TradingView may still be loading."
echo "Check manually: curl http://localhost:$PORT/json/version"
