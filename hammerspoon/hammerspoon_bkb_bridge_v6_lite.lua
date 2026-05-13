-- BKB Desk Pet v6 Lite bridge
-- Mac event bridge only: Node-RED publishes state, ESP32 owns rendering/runtime.

local bkbV6NodeRedURL = "http://127.0.0.1:1880/bkb/mac/event"
local bkbV6LastLocked = nil
local bkbV6LastApp = nil
local bkbV6LastAppPostTime = 0
local bkbV6LastPostByEvent = {}

local bkbV6IgnoredApps = {
  ["Notification Center"] = true,
  ["Control Center"] = true,
  ["SystemUIServer"] = true,
  ["Dock"] = true,
  ["loginwindow"] = true,
}

local function bkbV6Post(tbl)
  tbl.ts = os.time()
  local body = hs.json.encode(tbl)
  hs.http.asyncPost(bkbV6NodeRedURL, body, { ["Content-Type"] = "application/json" }, function(_, _, _) end)
end

local function bkbV6PostThrottled(eventName, tbl, minGap)
  local now = hs.timer.secondsSinceEpoch()
  local last = bkbV6LastPostByEvent[eventName] or 0
  if now - last < minGap then return end
  bkbV6LastPostByEvent[eventName] = now
  bkbV6Post(tbl)
end

local function bkbV6IsScreenLocked()
  local out = hs.execute("/usr/sbin/ioreg -n Root -d1 | /usr/bin/grep CGSSessionScreenIsLocked", true) or ""
  return out:find("Yes") ~= nil
end

local function bkbV6PublishLockState(force)
  local locked = bkbV6IsScreenLocked()
  if force or bkbV6LastLocked == nil or locked ~= bkbV6LastLocked then
    bkbV6LastLocked = locked
    bkbV6Post({ event = locked and "locked" or "unlocked" })
  end
end

bkbV6LockPoller = hs.timer.doEvery(2, function()
  bkbV6PublishLockState(false)
end)

bkbV6CaffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
  if eventType == hs.caffeinate.watcher.screensDidLock then
    bkbV6LastLocked = true
    bkbV6PostThrottled("locked", { event = "locked" }, 0.5)
  elseif eventType == hs.caffeinate.watcher.screensDidUnlock then
    bkbV6LastLocked = false
    bkbV6PostThrottled("unlocked", { event = "unlocked" }, 0.5)
  elseif eventType == hs.caffeinate.watcher.screensDidSleep then
    bkbV6LastLocked = true
    bkbV6PostThrottled("sleep_lock", { event = "locked" }, 0.5)
  elseif eventType == hs.caffeinate.watcher.screensDidWake or eventType == hs.caffeinate.watcher.systemDidWake then
    hs.timer.doAfter(1, function() bkbV6PublishLockState(true) end)
  end
end)
bkbV6CaffeinateWatcher:start()

bkbV6AppWatcher = hs.application.watcher.new(function(appName, eventType, _)
  if eventType ~= hs.application.watcher.activated then return end
  if bkbV6IsScreenLocked() then return end
  if not appName or appName == "" then return end
  if bkbV6IgnoredApps[appName] then return end

  local now = hs.timer.secondsSinceEpoch()
  if appName == bkbV6LastApp and (now - bkbV6LastAppPostTime) < 1.0 then return end
  if (now - bkbV6LastAppPostTime) < 2.0 then
    bkbV6LastApp = appName
    return
  end

  bkbV6LastApp = appName
  bkbV6LastAppPostTime = now
  bkbV6Post({ event = "app", app = appName })
end)
bkbV6AppWatcher:start()

hs.timer.doAfter(1, function() bkbV6PublishLockState(true) end)
hs.alert.show("BKB v6 Lite bridge loaded")
