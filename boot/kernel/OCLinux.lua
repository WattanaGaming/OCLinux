-- OCLinux kernel by Atirut Wattanamongkol(WattanaGaming)
_G.boot_invoke = nil

-- These are needed to do literally anything.
local component = component or require('component')
local computer = computer or require('computer')
-- local unicode = unicode or require('unicode')

-- Kernel table containing built-in functions.
local kernel = {}
os.kernel = {}
os.kernel.modules = {}
os.simpleDisplay = {
    gpu = nil,
    screenWidth = nil,
    screenHeight = nil,
    cursorY = 1,
}

function os.simpleDisplay.status(msg)
    local simpleDisplay = os.simpleDisplay
    simpleDisplay.gpu.set(1, simpleDisplay.cursorY, msg)
    if simpleDisplay.cursorY == simpleDisplay.screenHeight then
        simpleDisplay.gpu.copy(1, 2, simpleDisplay.screenWidth, simpleDisplay.screenHeight - 1, 0, -1)
        simpleDisplay.gpu.fill(1, simpleDisplay.screenHeight, simpleDisplay.screenWidth, 1, " ")
    else
        simpleDisplay.cursorY = simpleDisplay.cursorY + 1
    end
end

os.thread = {
    threads = {},
    nextPID = 1,
    
    new = function(self, func, name, options)
        local options = options or {}
        local pid = self.nextPID

        local threadData = {
            name = name,
            pid = pid,
            status = "normal",
            coroutine = coroutine.create(func),
            cpuTime = 0,

            errorHandler = (options.errorHandler or nil),
            argument = (options.argument or nil)
        }
        table.insert(self.threads, threadData)

        self.nextPID = self.nextPID + 1
        return pid
    end,
    
    cycle = function(self)
        for i,thread in ipairs(self.threads) do
            if coroutine.status(thread.coroutine) == "dead" then
                table.remove(self.threads, i)
                goto skipThread
            elseif thread.status == "suspended" then
                goto skipThread
            end

            local startTime = computer.uptime()
            local success, result = coroutine.resume(thread.coroutine, thread.argument)
            thread.cpuTime = computer.uptime() - startTime

            if thread.argument ~= nil then thread.argument = nil end

            if not success and thread.errorHandler then
                thread.errorHandler(result)
            elseif not success then
                error(result)
            end
            ::skipThread::
        end
    end,

    getIndex = function(self, pid)
        for index,thread in ipairs(self.threads) do
            if thread.pid == pid then
                return index
            end
        end
    end,

    get = function(self, pid)
        if self:getIndex(pid) then return self.threads[self:getIndex(pid)] end
    end,

    kill = function(self, pid)
        if self:exists(pid) then self.threads[self:getIndex(pid)] = nil end
    end,

    exists = function(self, pid)
        if self:get(pid) then return true end
    end
}

kernel.internal = {
    isInitialized = false,
    
    readfile = function(file)
        local addr, invoke = computer.getBootAddress(), component.invoke
        local handle = assert(invoke(addr, "open", file), "Requested file "..file.." not found")
        local buffer = ""
        repeat
            local data = invoke(addr, "read", handle, math.huge)
            buffer = buffer .. (data or "")
        until not data
        invoke(addr, "close", handle)
        return buffer
    end,
    
    copy = function(obj, seen)
        if type(obj) ~= 'table' then return obj end
        if seen and seen[obj] then return seen[obj] end
        local s = seen or {}
        local res = setmetatable({}, getmetatable(obj))
        s[obj] = res
        for k, v in pairs(obj) do res[kernel.internal.copy(k, s)] = kernel.internal.copy(v, s) end
        return res
    end,
    
    loadfile = function(file, env, isSandbox)
        if isSandbox == true then
            local sandbox = kernel.internal.copy(env)
            sandbox._G = sandbox
            return load(kernel.internal.readfile(file), "=" .. file, "bt", sandbox)
        else
            return load(kernel.internal.readfile(file), "=" .. file, "bt", env)
        end
    end,
    
    initialize = function(self)
        if (self.isInitialized) then -- Prevent the function from running again once initialized
            return false
        end
        self.bootAddr = computer.getBootAddress()
        os.simpleDisplay.gpu = component.proxy(component.list("gpu")())
        os.simpleDisplay.screenWidth, os.simpleDisplay.screenHeight = os.simpleDisplay.gpu.getResolution()
        
        os.simpleDisplay.status("Loading and executing /sbin/init.lua")
        
        os.thread:new(self.loadfile("/sbin/init.lua", _G, false), "init", {
            errorHandler = function(err) -- Special handler.
                computer.beep(1000, 0.1)
                local print = function(a) os.simpleDisplay.status(a) end
                print("Error whilst executing init:")
                print("  "..tostring(err))
                print("")
                print("Halted.")
                while true do computer.pullSignal() end
            end,
            sandbox = true
        })
        
        self.isInitialized = true
        return true
    end
}

function os.kernel.initModule(name, data, isSandbox)
    assert(name ~= "", "Module name cannot be blank or nil")
    assert(data ~= "", "Module data cannot be blank or nil")
    
    local modfunc = nil
    if isSandbox == true then
        modfunc = load(data, "=" .. name, "bt", kernel.internal.copy(_G))
    else
        modfunc = load(data, "=" .. name, "bt", _G)
    end
    local success, result = pcall(modfunc)
    
    if success and result then os.kernel.modules[name] = result return true
    elseif not success then error("Module execution error:\r"..result) end
end

function os.kernel.getModule(name)
    assert(os.kernel.modules[name], "Invalid module name")
    return os.kernel.modules[name]
end

os.kernel.readfile = function(file) return kernel.internal.readfile(file) end

kernel.internal:initialize()
while os.thread:exists(1) do
    os.thread:cycle()
end

os.simpleDisplay.status("Init has returned.")
