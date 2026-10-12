local Inventory=require('inventory')
local Scanner=require('scanner')
local Backend={};Backend.__index=Backend
function Backend.new() return setmetatable({scanner=Scanner.new()},Backend) end
function Backend:stop() return api.controls('stop',{}) end
function Backend:actor(command)
    local object=api.target(assert(command.target,'Missing target'))
    local point=object:K2_GetActorLocation()
    local row={target=command.target,position={x=point.X,y=point.Y,z=point.Z}}
    if Engine.is_a(object,'PalCharacter') then
        local utility=Engine.find('/Script/Pal.Default__PalUtility')
        local component=object.CharacterParameterComponent
        row.character=Scanner.character(object)
        row.player=object:IsPlayerControlled()
        row.wild=utility:IsWildNPC(object)
        row.capturing=component:GetIsCapturedProcessing()
        row.uncapturable=component:GetIndividualParameter():IsUncapturable()
    end
    return row
end
function Backend:patrol(command)
    local controller=assert(api.game.controller(),'Player is unavailable')
    local player=assert(api.game.subject(controller),'Player is unavailable')
    local origin=player:K2_GetActorLocation()
    local radius=math.max(15,math.min(command.radius_m or 40,100))
    local candidates,seen={},{}
    for _,rows in ipairs({self.scanner.resources,self.scanner.characters}) do
        for _,row in ipairs(rows) do
            local p=row.position
            local distance=((p.x-origin.X)^2+(p.y-origin.Y)^2+(p.z-origin.Z)^2)/10000
            if distance>=64 and distance<=radius*radius and not seen[row.target] then
                candidates[#candidates+1]=row;seen[row.target]=true
            end
        end
    end
    if #candidates>0 then
        local target=candidates[math.random(1,#candidates)]
        local ok,path=pcall(api.controls,'path',{target=target.target})
        if ok and not path.partial and #path.points>1 then return {position=path.points[#path.points]} end
    end
    return {unavailable=true}
end
function Backend:call(action,arguments)
    if action=='autonomy_inventory' then return Inventory.read() end
    if action=='autonomy_ball' then return Inventory.ball(arguments) end
    if action=='autonomy_food' then return Inventory.food() end
    if action=='autonomy_scan' then return self.scanner:step(arguments) end
    if action=='autonomy_creatures' then return self.scanner.characters end
    if action=='autonomy_resources' then return self.scanner.resources end
    if action=='autonomy_actor' then return self:actor(arguments) end
    if action=='autonomy_patrol' then return self:patrol(arguments) end
    return api.controls(action,arguments)
end
return Backend
