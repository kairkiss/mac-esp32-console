-- BKB Desk Node v5 bridge: robust lock state + throttled foreground app overlay
-- Remove older BKB bridge snippets first, then paste this at the end of ~/.hammerspoon/init.lua.

local bkbNodeRedURL = "http://127.0.0.1:1880/bkb/mac/event"
local bkbLastLocked = nil
local bkbLastApp = nil
local bkbLastAppPostTime = 0

local bkbIgnoredApps = {
  ["Notification Center"] = true,
  ["Control Center"] = true,
  ["SystemUIServer"] = true,
  ["Dock"] = true,
  ["loginwindow"] = true,
}

local function bkbPost(tbl)
  tbl.ts = os.time()
  local body = hs.json.encode(tbl)
  hs.http.asyncPost(bkbNodeRedURL, body, { ["Content-Type"] = "application/json" }, function(code, body, headers) end)
end

local function bkbIsScreenLocked()
  local out = hs.execute("/usr/sbin/ioreg -n Root -d1 | /usr/bin/grep CGSSessionScreenIsLocked", true) or ""
  return out:find("Yes") ~= nil
end

local function bkbPublishLockState(force)
  local locked = bkbIsScreenLocked()
  if force or bkbLastLocked == nil or locked ~= bkbLastLocked then
    bkbLastLocked = locked
    bkbPost({ event = locked and "locked" or "unlocked" })
  end
end

bkbLockPoller = hs.timer.doEvery(2, function() bkbPublishLockState(false) end)

bkbCaffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
  if eventType == hs.caffeinate.watcher.screensDidLock then
    bkbLastLocked = true; bkbPost({ event = "locked" })
  elseif eventType == hs.caffeinate.watcher.screensDidUnlock then
    bkbLastLocked = false; bkbPost({ event = "unlocked" })
  elseif eventType == hs.caffeinate.watcher.screensDidSleep then
    bkbLastLocked = true; bkbPost({ event = "locked" })
  elseif eventType == hs.caffeinate.watcher.screensDidWake or eventType == hs.caffeinate.watcher.systemDidWake then
    bkbPublishLockState(true)
  end
end)
bkbCaffeinateWatcher:start()

bkbAppWatcher = hs.application.watcher.new(function(appName, eventType, appObject)
  if eventType ~= hs.application.watcher.activated then return end
  if bkbIsScreenLocked() then return end
  if not appName or appName == "" then return end
  if bkbIgnoredApps[appName] then return end

  local now = hs.timer.secondsSinceEpoch()
  if appName == bkbLastApp and (now - bkbLastAppPostTime) < 1.0 then return end
  if (now - bkbLastAppPostTime) < 2.0 then bkbLastApp = appName; return end

  bkbLastApp = appName
  bkbLastAppPostTime = now
  bkbPost({ event = "app", app = appName })
end)
bkbAppWatcher:start()

hs.timer.doAfter(1, function() bkbPublishLockState(true) end)
hs.alert.show("BKB v5 bridge loaded")
