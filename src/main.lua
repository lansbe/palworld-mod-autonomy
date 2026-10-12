local Rules=require('settings')
local Runner=require('runner')
local Backend=require('backend')
local catalog=require('catalog')
local materials={}
for _,id in ipairs({'Wood','Stone','Pal_crystal_S','CopperOre','Coal','Sulfur','Quartz','Fiber','Berries','Mushroom'}) do
    materials[#materials+1]={id=id,label=id}
end
local config=Rules.validate(api.settings,catalog,materials)
for key in pairs(Rules.defaults) do api.settings[key]=config[key] end
api.settings.running=false
local backend=Backend.new()
local runner
local function stop()
    api.settings.running=false
    if runner then runner:stop();runner:set('off','Stopped') end
    backend:stop()
end
local function start()
    local state=api.game.state()
    assert(state.phase=='world' and not state.dead and not state.loading,'Join a world before starting autonomy')
    runner=Runner.new(config,catalog,function(action,args)return backend:call(action,args or {})end,nil,materials)
    api.settings.running=true
end
api.on_stop(stop)
api.on_travel(stop)
api.on_toggle(function(enabled) if not enabled then stop() end end)
api.provide('status',function() return runner and runner:status() or {phase='off',message='Stopped'} end)
api.provide('start',start)
api.provide('stop',stop)
api.provide('catalog',function() return catalog end)
api.provide('settings',function() return require('fields') end)
api.provide('configure',function(values)
    local merged={};for key,value in pairs(api.settings) do merged[key]=value end
    for key,value in pairs(values) do merged[key]=value end
    local next_config=Rules.validate(merged,catalog,materials)
    local running=merged.running==true
    stop();config=next_config
    for key in pairs(Rules.defaults) do api.settings[key]=config[key] end
    if running then start() end
end)
api.every(.1,function()
    if not api.settings.running then return end
    local state=api.game.state()
    if state.dead then stop();return end
    local ok,failure=xpcall(function()runner:tick(Engine.clock(),state)end,api.traceback)
    if ok and runner.finished then api.settings.running=false end
    if not ok then stop();runner:set('error',tostring(failure):match('[^\n]+'));error(failure) end
end)
