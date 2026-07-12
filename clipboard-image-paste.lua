-- =================================================
-- Terminal Clipboard-Image-to-File Paste (for Hammerspoon)
-- =================================================
-- When pressing Cmd+V inside the configured terminal app:
--   - If the clipboard contains an image -> save it to
--     <TMP_DIR>/clipboard-<timestamp>-<uuid>.png, then type the file path
--     into the terminal (useful for CLI tools that accept image file paths,
--     e.g. Claude Code / Codex CLI and other AI coding agents)
--   - If the clipboard contains text/other -> paste normally, unaffected
--   - If the focused app is not in the configured terminal list -> do
--     nothing, native behavior is untouched
--
-- Core logic adapted from:
--   https://eshlox.net/clipboard-image-to-file-hammerspoon
--   (Przemysław Kołodziejczyk, CC BY-SA 4.0)
-- Uses hs.pasteboard.readImage() to detect/read clipboard images, and
-- img:saveToFile() to write them to disk.
--
-- Differences from the original:
--   - Saves to a fixed temp directory (default /tmp) instead of relying
--     on the current tmux pane directory
--   - Only active in the configured terminal app(s), other apps are untouched
--   - Types the full path directly, no need to paste a second time
--   - Uses hs.eventtap instead of hs.hotkey.bind to intercept the keystroke,
--     so non-image paste can properly pass through to the system
--     (hs.hotkey.bind cannot pass events through — a synthesized Cmd+V
--     event gets re-captured by the same binding, breaking text paste)
--   - Debounces repeated Cmd+V presses for the same clipboard image so
--     accidental double-presses don't create duplicate files
--   - Self-heals if macOS silently disables the eventtap (both via the
--     documented disabled-event listener, and a periodic health-check
--     timer as a backup)

-- =================================================
-- Configuration
-- =================================================
local TARGET_APPS = { "iTerm2" }  -- add more terminal app names here, e.g. { "iTerm2", "Terminal", "Ghostty" }
local TMP_DIR = "/tmp"
local DEBOUNCE_SECONDS = 2   -- ignore repeated Cmd+V for the same clipboard image within this window

-- =================================================
-- First-run setup: auto-trigger the macOS Accessibility permission prompt
-- =================================================
-- hs.accessibilityState(true):
--   - if already granted -> returns true, does nothing else
--   - if not granted -> triggers the native macOS permission dialog and
--     jumps straight to System Settings > Privacy & Security > Accessibility,
--     so the user just needs to check the box for Hammerspoon
-- This is the one step that cannot (and should not) be automated away —
-- it's a deliberate macOS security gate requiring explicit human consent.
-- This call just saves the user from hunting for the settings page.
if not hs.accessibilityState(true) then
    hs.alert.show(
        "⚠️ Accessibility permission required\nPlease check Hammerspoon in the System Settings window that just opened,\nthen restart Hammerspoon.",
        { textSize = 15, radius = 8 },
        hs.screen.mainScreen(),
        6
    )
end

local function isTargetAppFocused()
    local app = hs.application.frontmostApplication()
    if not app then return false end
    local name = app:name()
    for _, targetName in ipairs(TARGET_APPS) do
        if name == targetName then return true end
    end
    return false
end

-- =================================================
-- Small alert toast
-- =================================================
-- Note: hs.notify (native macOS notifications) was unreliable in testing
-- (did not show up even with permissions granted), so we use hs.alert instead.
local function showToast(message, isError)
    hs.alert.show(message, {
        textSize = 13,
        radius = 8,
        fillColor = isError and { red = 0.55, green = 0.15, blue = 0.15, alpha = 0.9 }
                             or { white = 0.1, alpha = 0.85 },
        strokeColor = { white = 1, alpha = 0 },
        textColor = { white = 1, alpha = 0.95 },
        padding = 10,
    }, 1.4)
end

-- =================================================
-- Intercept Cmd+V via eventtap (not hs.hotkey.bind)
-- =================================================
-- Why: hs.hotkey.bind always consumes the keystroke once bound and cannot pass
-- events through — even a synthesized Cmd+V event sent from inside the
-- callback gets re-captured by the same binding, breaking text paste.
-- hs.eventtap's callback can return false to let the event propagate normally.
local eventtap = hs.eventtap
local eventTypes = eventtap.event.types
local keyCodes = hs.keycodes.map

-- Debounce state: pressing Cmd+V repeatedly for the same clipboard image
-- (e.g. an accidental double press) would otherwise create a new duplicate
-- file each time. Skip re-saving if the same image is pasted again within
-- DEBOUNCE_SECONDS — just re-type the previously saved path instead.
local lastPastedImagePath = nil
local lastPastedChangeCount = nil
local lastPastedAt = 0

local cmdVWatcher = eventtap.new({ eventTypes.keyDown, eventTypes.tapDisabledByTimeout, eventTypes.tapDisabledByUserInput }, function(event)
    -- macOS can silently disable an eventtap (e.g. if the callback is slow to
    -- respond, or due to other system-level protections). When that happens,
    -- re-enable it immediately so Cmd+V doesn't silently stop working.
    local eventType = event:getType()
    if eventType == eventTypes.tapDisabledByTimeout or eventType == eventTypes.tapDisabledByUserInput then
        cmdVWatcher:start()
        return false
    end

    local keyCode = event:getKeyCode()
    local flags = event:getFlags()

    -- Only handle plain Cmd+V (exclude combos like Cmd+Shift+V)
    if keyCode ~= keyCodes["v"] or not flags.cmd or flags.shift or flags.alt or flags.ctrl then
        return false -- not our combo, let it through
    end

    if not isTargetAppFocused() then
        return false -- not a target app, let the system handle it
    end

    local img = hs.pasteboard.readImage()
    if not img then
        return false -- clipboard is not an image, let native text paste happen
    end

    -- If the clipboard also contains a file reference (e.g. you copied a
    -- file in Finder, which puts both a file URL AND an image thumbnail on
    -- the pasteboard for image files), this is a "copy file" action, not a
    -- screenshot. Don't hijack it — let the system paste the file/path natively.
    local pasteboardTypes = hs.pasteboard.contentTypes() or {}
    for _, t in ipairs(pasteboardTypes) do
        if t == "public.file-url" then
            return false
        end
    end

    -- Same clipboard image, pasted again within the debounce window ->
    -- re-type the previously saved path instead of creating a new file.
    local imageChangeCount = hs.pasteboard.changeCount()
    local now = hs.timer.secondsSinceEpoch()
    if lastPastedImagePath and lastPastedChangeCount == imageChangeCount and (now - lastPastedAt) < DEBOUNCE_SECONDS then
        hs.eventtap.keyStrokes(lastPastedImagePath)
        lastPastedAt = now
        return true
    end

    -- Clipboard is an image: consume this keystroke, save file + type path instead
    local filename = os.date("clipboard-%Y%m%d-%H%M%S-") .. tostring(hs.host.uuid()):sub(1, 8) .. ".png"
    local path = TMP_DIR .. "/" .. filename

    local ok = img:saveToFile(path)
    if ok then
        hs.eventtap.keyStrokes(path)
        showToast("Saved & pasted path: " .. filename, false)
        lastPastedImagePath = path
        lastPastedChangeCount = imageChangeCount
        lastPastedAt = now
    else
        showToast("Failed to save image", true)
    end

    return true -- consume the original Cmd+V, don't let the system process it again
end)

cmdVWatcher:start()

-- =================================================
-- Watchdog: actively poll eventtap health
-- =================================================
-- The tapDisabledByTimeout/tapDisabledByUserInput event listener above is
-- the documented way to detect a disabled eventtap, but in practice the tap
-- can still end up stopped without that event firing reliably (e.g. after
-- system sleep/wake or other session interruptions). This timer is a
-- belt-and-suspenders check.
--
-- IMPORTANT: after sleep/idle, macOS can leave the eventtap effectively dead
-- while isEnabled() still reports true. Trusting isEnabled() therefore misses
-- exactly the failure mode we care about (works at first, silently stops
-- after being idle for a while). So we unconditionally cycle stop()+start():
-- restarting an already-healthy tap is cheap and harmless, and it guarantees
-- recovery even when isEnabled() lies.
hs.timer.doEvery(10, function()
    cmdVWatcher:stop()
    cmdVWatcher:start()
end)

-- =================================================
-- Sleep/wake watchdog (the real fix for "stops working after idle")
-- =================================================
-- The polling timer above cannot fire while the system is asleep, and on wake
-- it may not resume cleanly. More importantly, the eventtap itself is the
-- thing macOS tends to kill across display sleep, system sleep, screen lock,
-- and fast user switching. hs.caffeinate.watcher lets us react to those exact
-- transitions and force a fresh stop()+start() the moment the session comes
-- back, instead of waiting (possibly forever) for a polling tick.
local caffeinateEvents = hs.caffeinate.watcher
local wakeWatcher = caffeinateEvents.new(function(eventType)
    if eventType == caffeinateEvents.systemDidWake
        or eventType == caffeinateEvents.screensDidWake
        or eventType == caffeinateEvents.screensDidUnlock
        or eventType == caffeinateEvents.sessionDidBecomeActive then
        cmdVWatcher:stop()
        cmdVWatcher:start()
    end
end)
wakeWatcher:start()
