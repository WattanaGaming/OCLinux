_G._INITVERSION = "INDEV"
local modDir = "/boot/kmod/base/"
local shell = "/sbin/luashell.lua"
local autoRestartShell = false

print = system.display.simplePrint
write = system.display.simpleWrite

-- List of built-in modules to load
local baseModules = {
    "filesystem"
}

print("TinyInit v".._G._INITVERSION)

print("Loading base kernel modules")
for i=1,#baseModules do
  write (baseModules[i].."... ")
  local modString = system.kernel.readfile(modDir..baseModules[i]..".lua")
  system.kernel.initModule(baseModules[i], modString)
  coroutine.yield()
end
print("Done")

local filesystem = system.kernel.getModule("filesystem")
print("Mounting "..system.bootAddress.." as root(/)... ")
filesystem.mount(system.bootAddress, "/")

print("Attempting to load and execute " .. shell .."...")
-- Load file into function
local file = filesystem.open(shell, "r")
assert(file, shell.." not found")
local shellScript = file:read(math.huge)
file:close()
local shellFunc = load(shellScript, "=" .. shell, "t", _G)

local function shellErrorHandler(err)
    print("Shell process exited with the following error:")
    print("    "..(err or "not specified"))
end
local shellProcessID = system.kernel.thread.new(shellFunc, shell, {errHandler = shellErrorHandler})

local running = true
while running do
    coroutine.yield()
    if autoRestartShell and not system.kernel.thread.exists(shellProcessID) then
        shellProcessID = system.kernel.thread.new(shellFunc, shell, {errHandler = shellErrorHandler})
    elseif not system.kernel.thread.exists(shellProcessID) then
        running = false
    end
end
