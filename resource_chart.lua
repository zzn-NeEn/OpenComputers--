-- resource_chart.lua -- entry point for the OpenComputers resource chart.
--
-- Target: GTNH 2.9.0-beta-2 (Minecraft 1.7.10, OpenComputers 1.8.x / OpenOS).
-- The program only uses documented OC APIs and Lua 5.2/5.3 compatible syntax.
--
-- Usage (in the OpenOS shell):
--   cd /home/oc-resource-chart
--   lua resource_chart.lua
--
-- Options:
--   --demo      force the synthetic demo sources
--   --no-demo   hide demo sources
--   --reset     delete the saved history before starting
--   --help      show command line help

local function scriptDirectory()
  if debug and debug.getinfo then
    local info = debug.getinfo(1, "S")
    if info and info.source then
      local source = info.source
      source = source:gsub("^@", "")
      local dir = source:match("^(.*[/\\])")
      if dir and dir ~= "" then return dir end
    end
  end
  return "./"
end

local base = scriptDirectory()
package.path = base .. "?.lua;" .. base .. "lib/?.lua;" .. package.path

local args = { ... }
local options = {}
for i = 1, #args do
  local a = args[i]
  if a == "--demo" then
    options.demo = true
  elseif a == "--no-demo" then
    options.demo = false
  elseif a == "--reset" then
    options.reset = true
  elseif a == "--help" or a == "-h" then
    options.help = true
  end
end

if options.help then
  print("resource_chart.lua -- OpenComputers resource history chart")
  print("")
  print("  lua resource_chart.lua [--demo|--no-demo] [--reset]")
  print("")
  print("  --demo      use synthetic demo series only")
  print("  --no-demo   hide synthetic demo series")
  print("  --reset     delete saved history before starting")
  print("")
  print("Controls: T picker, P pause, E export, H help, Q quit.")
  return
end

local okConfig, configModule = pcall(require, "rc_config")
if not okConfig or not configModule then
  print("Cannot load rc_config.lua: " .. tostring(configModule))
  return
end

local config = configModule.load("/home/resource_chart.cfg")
if options.demo ~= nil then
  config.demo = options.demo
  config.includeDemo = true
end

if options.reset then
  os.remove(config.dataPath)
  os.remove(config.fallbackDataPath)
  print("Saved history deleted.")
end

local okApp, App = pcall(require, "rc_app")
if not okApp or not App then
  print("Cannot load rc_app.lua: " .. tostring(App))
  return
end

local app = App.new(config)
local ok, result, err = xpcall(function()
  return app:run()
end, function(message)
  if debug and debug.traceback then
    return debug.traceback(tostring(message), 2)
  end
  return tostring(message)
end)

if not ok then
  app:fatal(result)
  return
end

if result == false then
  print(err or "Startup failed.")
end
