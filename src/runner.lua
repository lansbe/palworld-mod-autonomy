-- Cooperative autonomous controller. One bounded decision per game-thread tick.
-- Dependencies are injected so goals and interrupted transitions can be tested.
local Rules=require('settings')
local Runner={};Runner.__index=Runner
local function xy(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
local function dist(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
local function sphere(inv,reserve)
    local count=0;local names={}
    for id,n in pairs(inv.counts) do if id:match('^PalSphere') then count=count+n;names[#names+1]=id end end
    table.sort(names)
    if count<=reserve then return nil,count end
    -- Preserve rare spheres when ordinary ones remain.
    for _,id in ipairs(names) do if inv.counts[id]>0 then return id,count end end
end
function Runner.new(cfg,catalog,call,notify,materials)
    local labels={Wood='Wood',Stone='Stone'}
    for _,item in ipairs(materials or {})do labels[item.id]=item.label end
    return setmetatable({cfg=cfg,catalog=catalog,material_labels=labels,call=call,notify=notify or function()end,phase='starting',message='Ready',skip={},events={},stats={captures=0,wood=0,stone=0,throws=0},next_scan=0,wait=0,errors=0},Runner)
end
function Runner:status()
    return {phase=self.phase,message=self.message,objective=self.target and self.target.label,stats=self.stats,inventory=self.inv,origin=self.origin,events=self.events,elapsed=self.now and self.started and self.now-self.started or 0,
        navigation=self.target and {target=self.target.target,position=self.target.position,kind=self.target.kind,waypoint=self.path and self.path[1]},performance=self.performance}
end
function Runner:set(phase,message)
    if self.phase~=phase or self.message~=message then self.phase,self.message=phase,message;self.notify(phase,message) end
end
function Runner:event(message)
    self.events[#self.events+1]=message;if #self.events>10 then table.remove(self.events,1)end
    self.notify('event',message)
end
function Runner:stop()self.call('stop');self.path=nil;self.previous=nil end
function Runner:level_view()
    self.call('camera_follow',{yaw=self.state.pose.camera.yaw,pitch=-12,seconds=1})
end
function Runner:reject(reason)
    if self.target then self.skip[self.target.target]=self.now+90 end
    self:event(reason:gsub('^.-%.lua:%d+: ',''));self.target=nil;self.wait=0;self:stop();self.next_scan=0
end
function Runner:move_to(position,target,radius)
    local p=self.state.pose.position;local horizontal=xy(p,position)
    if horizontal<=radius then
        assert(math.abs(p.z-position.z)<=220,'Destination is on an inaccessible level')
        self:stop();return true
    end
    if self.previous then
        local moved=xy(p,self.previous)
        self.stuck=moved<10 and (self.stuck or 0)+1 or 0
        if self.stuck>=8 then self:stop();error('Path blocked') end
        if self.stuck==4 then self.call('jump');self.call('move',{forward=-.3,right=.8,seconds=.35});self.wait=self.now+.4;return false end
    end
    self.previous=p
    if not self.path or (self.target and self.target.kind=='capture' and self.now>self.path_until) or xy(position,self.path_destination)>350 then
        local route=self.call('path',target and {target=target} or {position=position})
        assert(not route.partial,'No complete path')
        self.path={};for i=2,#route.points do self.path[#self.path+1]=route.points[i] end
        if #self.path==0 then
            assert(horizontal<800 and math.abs(p.z-position.z)<250,'Destination is outside the walkable path')
            self.path={position}
        end
        self.path_until=self.now+4;self.path_destination=position
    end
    while #self.path>1 and xy(p,self.path[1])<110 do table.remove(self.path,1)end
    if #self.path==1 then self.path[1]=position end
    local q=self.path[1];local dx,dy=q.x-p.x,q.y-p.y;local length=math.sqrt(dx*dx+dy*dy)
    if length<1 then self.path=nil;return false end
    self.call('camera_follow',{yaw=math.deg(math.atan(dy,dx)),pitch=-12})
    local yaw=math.rad(self.state.pose.camera.yaw)
    self.call('move',{forward=(dx*math.cos(yaw)+dy*math.sin(yaw))/length,right=(-dx*math.sin(yaw)+dy*math.cos(yaw))/length,seconds=.4})
    return false
end
function Runner:returning(reason,finished)
    self.target=nil
    if dist(self.state.pose.position,self.origin)<250 then
        self:stop();self:level_view();self.return_retry=nil;self.finished=finished;self:set(finished and 'complete' or 'resting',reason)
        return
    end
    if self.now<(self.return_retry or 0) then return end
    self:set(finished and 'returning' or 'retreating',reason..' · Returning to the starting point')
    local ok,err=pcall(self.move_to,self,self.origin,nil,180)
    if not ok then
        self:stop();self.return_retry=self.now+2
        self:set('blocked',reason..' · Return blocked: '..tostring(err):match('[^\n]+'))
    else self.return_retry=nil end
end
function Runner:choose()
    self.next_scan=self.now+3
    local ball=sphere(self.inv,self.cfg.sphere_reserve);local candidates={}
    local function available(t)return not self.skip[t.target] or self.skip[t.target]<self.now end
    if ball and self.cfg.capture_mode~='off' then
        for _,t in ipairs(self.call('autonomy_creatures',{radius_m=self.cfg.radius,snapshot=true}))do
            local c=t.character
            if t.wild and t.is_pal and not t.player and not t.boss and not t.uncapturable and not t.capturing
                and not c.dead and not c.dying and c.level<=self.cfg.max_level and Rules.wanted(self.cfg,self.inv.captures,c.character_id)
                and available(t) and dist(t.position,self.origin)<=self.cfg.radius*100 then
                t.kind='capture';t.id=c.character_id;t.label=t.id;t.score=t.distance_m
                for _,p in ipairs(self.catalog)do if p.id==t.id then t.label=p.label;break end end
                candidates[#candidates+1]=t
            end
        end
    end
    for _,t in ipairs(self.call('autonomy_resources',{radius_m=self.cfg.radius,snapshot=true}))do
        local goal=self.cfg.resources[t.item_id] or 0
        if self.cfg.eat and self.inv.hunger<.4 and t.item_id=='Berries' then goal=math.max(goal,5)end
        if (self.inv.counts[t.item_id] or 0)<goal and available(t) and dist(t.position,self.origin)<=self.cfg.radius*100 then
            t.label=self.material_labels[t.item_id] or t.item_id;t.score=t.distance_m+(t.kind=='node' and 30 or 0)
            candidates[#candidates+1]=t
        end
    end
    table.sort(candidates,function(a,b)return a.score<b.score end)
    local t=candidates[1]
    if t then
        self.patrol=nil;self.target=t;t.started=self.now;t.before=t.kind=='capture' and (self.inv.captures[t.id] or 0) or (self.inv.counts[t.item_id] or 0)
        t.throws=0;self.path=nil;self.previous=nil;self.stuck=0;self.wait=0
        self:set('approaching','Approaching: '..t.label)
    else
        if self.patrol then return end
        self:stop();self:level_view()
        local reason=not ball and self.cfg.capture_mode~='off' and 'No spheres above the reserve' or 'No reachable target in this area'
        self:set('searching',reason..' · Searching again')
        if self.cfg.explore and (ball or next(Rules.remaining_resources(self.cfg,self.inv))~=nil) and self.now>=(self.next_patrol or 0) then
            self.next_patrol=self.now+5
            local q=self.call('autonomy_patrol',{radius_m=math.min(45,self.cfg.radius)})
            if q.position and dist(q.position,self.origin)<=self.cfg.radius*100 and xy(q.position,self.state.pose.position)>700 then
                self.patrol=q.position;self.patrol_until=self.now+30;self.path=nil;self.previous=nil;self.stuck=0
            end
        end
    end
end
-- Keep pending confirmations independent of actor lifetime: a captured/destroyed
-- actor can disappear before replicated records or inventory are updated.
function Runner:observe()
    local t=self.target
    local current=t.kind=='capture' and (self.inv.captures[t.id] or 0) or (self.inv.counts[t.item_id] or 0)
    if current>t.before then
        local n=current-t.before
        if t.kind=='capture' then self.stats.captures=self.stats.captures+n
        elseif t.item_id=='Wood' then self.stats.wood=self.stats.wood+n elseif t.item_id=='Stone' then self.stats.stone=self.stats.stone+n end
        self.stats.resources=self.stats.resources or {};if t.item_id then self.stats.resources[t.item_id]=(self.stats.resources[t.item_id] or 0)+n end
        self:event(t.label..' : +'..n);self.skip[t.target]=self.now+3;self.target=nil;self:stop();self.next_scan=0;return
    end
    return false
end
function Runner:target_step()
    local t=self.target
    if self.now-self.target.started>150 then self:reject('Target timed out: '..t.label);return end
    if self.now<(t.next_result or 0) then return end
    local actor=self.call('autonomy_actor',{target=t.target});t.position=actor.position
    if t.kind=='capture' then
        local c=actor.character
        if actor.player or not actor.wild or actor.uncapturable or not c or c.dead or c.dying then self:reject('Target is no longer available');return end
        if actor.capturing then t.next_result=self.now+1;return end
        if not Rules.wanted(self.cfg,self.inv.captures,t.id) then self.target=nil;self:stop();return end
        if not self:move_to(actor.position,t.target,self.cfg.weaken and c.hp_ratio>.4 and 130 or 420) then return end
        local game=self.call('gameplay')
        if self.cfg.weaken and c.hp_ratio>.4 then
            assert(game.melee,'Weakening requires a melee weapon')
            if t.last_hp then t.hit=math.max(t.hit or 0,t.last_hp-c.hp_ratio)end
            if not t.hit or c.hp_ratio>t.hit*1.8+.12 then
                self:set('weakening','Weakening: '..t.label)
                if self.call('aim_at',{target=t.target,melee=true,smooth=true}).aligned==false then return end
                t.last_hp=c.hp_ratio
                self.call('move',{forward=1,seconds=.15});self.call('act',{name='fire',seconds=.25});self.wait=self.now+1.1;return
            end
        end
        if t.throws>=self.cfg.max_throws then self:reject('Sphere limit reached: '..t.label);return end
        local ball=sphere(self.inv,self.cfg.sphere_reserve)
        if not ball then self:reject('No spheres available');return end
        if self.call('aim_at',{target=t.target,smooth=true}).aligned==false then return end
        self.call('autonomy_ball',{id=ball})
        self.call('act',{name='throw_object',seconds=.65})
        t.throws=t.throws+1;self.stats.throws=self.stats.throws+1;t.last_throw=self.now;t.next_result=self.now+10
        self:set('capturing','Capture : '..t.label..' · Attempt '..t.throws)
    else
        -- Shoreline pickups may lie below the walkable surface. Do not keep
        -- returning to the projected navmesh edge while their height is unreachable.
        if t.kind=='pickup' and xy(self.state.pose.position,actor.position)<600 and self.state.pose.position.z-actor.position.z>260 then
            self:reject('Pickup is below the walkable surface: '..t.label);return
        end
        if not self:move_to(actor.position,t.target,t.kind=='node' and 240 or 160) then return end
        if self.call('aim_at',{target=t.target,melee=t.kind=='node',smooth=true}).aligned==false then return end
        if t.kind=='pickup' then
            local game=self.call('gameplay')
            if game.interaction_target and game.interaction_target.object==t.interaction then
                self.call('act',{name='interact',seconds=.3});t.next_result=self.now+1.2
                self:set('gathering','Picking up: '..t.label)
            else
                t.aligns=(t.aligns or 0)+1
                if t.aligns>8 then self:reject('Interaction is unreachable: '..t.label);return end
                self.call('move',{forward=1,seconds=.12});self.wait=self.now+.4
            end
        else
            assert(self.call('gameplay').melee,'Gathering requires a melee weapon')
            self.call('act',{name='fire',seconds=.7});self.wait=self.now+1.1
            self:set('gathering','Gathering: '..t.label)
        end
    end
end
function Runner:flee()
    self.target=nil;self.patrol=nil;self.recovering=true
    if not self.state.in_combat then self:stop();self.escape=nil;self.escape_search=nil;self:set('resting','Recovering health');return end
    if self.escape and self.now>(self.escape_until or 0) then self.escape=nil;self.escape_search=nil end
    if not self.escape then
        -- Keep streaming observations current while recovering, and spread the
        -- four escape candidates across decisions. An unreachable route used to
        -- trigger four synchronous searches and two log messages every 100ms.
        self.call('autonomy_scan',{radius_m=self.cfg.radius,capture=true})
        if not self.escape_search and self.now>=(self.escape_retry or 0) then
            self.escape_search={remaining=4,score=-1,threats=self.call('autonomy_creatures',{radius_m=40,snapshot=true})}
        end
        local search=self.escape_search
        if search then
            self:set('retreating','Finding a retreat route')
            local candidate=self.call('autonomy_patrol',{radius_m=45}).position
            if candidate and xy(candidate,self.state.pose.position)>1500 then
                local distance=100000
                for _,threat in ipairs(search.threats)do distance=math.min(distance,xy(candidate,threat.position))end
                if distance>search.score then search.best,search.score=candidate,distance end
            end
            search.remaining=search.remaining-1
            if search.remaining==0 then
                self.escape=search.best;self.escape_search=nil;self.escape_retry=self.now+1
                self.escape_until=self.now+20;self.path=nil;self.previous=nil;self.stuck=0
            end
        end
        -- Do not add a fifth path search to the last candidate's decision.
        self:stop()
        if not self.escape and not self.escape_search then self:set('blocked','Retreat blocked: no walkable path') end
        return
    end
    self:set('retreating','Retreating to recover health')
    local ok,arrived=pcall(self.move_to,self,self.escape,nil,180)
    if not ok or arrived then self.escape=nil;self:stop()end
end
function Runner:tick(now,state)
    self.now=now
    state=state or self.call('state',{light=true});self.state=state
    if not state.playable then
        self:stop();self.wait=0;self:set('paused',state.dead and 'Player defeated: autonomy stopped' or state.phase=='world' and 'Paused while menus are open' or 'Waiting for the player');return
    end
    if not self.origin then self.origin=state.pose.position;self.started=now end
    if not self.inv or now>=(self.next_inventory or 0) then
        self.inv=self.call('autonomy_inventory',{light=true});self.next_inventory=now+.6
    end
    if self.target then self:observe() end
    if self.pending_food and (self.inv.counts[self.pending_food.requested] or 0)<self.pending_food.before then
        self:event('Food consumed');self.pending_food=nil
    end
    if self.cfg.eat and self.inv.hunger<.5 and now>=(self.next_food or 0) then
        self.pending_food=self.call('autonomy_food');self.next_food=now+5
    end
    if (state.hp_ratio or 0)<self.cfg.health/100 then self:flee();return end
    if self.recovering then
        if state.in_combat then self:flee();return end
        if state.hp_ratio<math.min(.98,self.cfg.health/100+.25) then self:stop();self:set('resting','Recovering health');return end
        self.recovering=false;self.escape=nil;self.escape_search=nil;self:event('Health recovered')
    end
    if self.finished then self:set('complete',self.finish_reason or 'Goals completed');return end
    local complete=Rules.complete(self.cfg,self.inv,self.catalog)
    if complete or now-self.started>=self.cfg.session_minutes*60 then
        self.finish_reason=complete and 'Goals completed' or 'Session time reached'
        if state.in_combat then self:flee()
        elseif self.cfg.return_home then self:returning(self.finish_reason,true)
        else self:stop();self:level_view();self.finished=true;self:set('complete',self.finish_reason) end
        return
    end
    if self.inv.max_weight>0 and self.inv.weight>=self.inv.max_weight*.9 then
        self:returning('Inventory almost full: empty the bag',false);return
    end
    if self.inv.hunger<.12 then self:stop();self:set('blocked','Food is required');return end
    -- Evade a new hit while awaiting capture; held inputs still expire on their own.
    if self.last_hp and state.hp_ratio<self.last_hp-.015 and now>=(self.next_dodge or 0)
        and self.target and self.target.kind=='capture' and now>(self.target.last_throw or -10)+1 then
        self.call('move',{forward=-1,seconds=.5});self.call('act',{name='dodge',seconds=.25});self.next_dodge=now+2;self.wait=now+.7
    end
    self.last_hp=state.hp_ratio
    local scan=self.call('autonomy_scan',{radius_m=self.cfg.radius,capture=self.cfg.capture_mode~='off'})
    if not scan.ready then self:stop();self:set('searching','Observing the area');return end
    if now<self.wait then return end
    if self.target then
        local ok,err=pcall(self.target_step,self)
        if not ok then self:reject(tostring(err):match('[^\n]+')) end
    elseif now>=self.next_scan then self:choose()end
    if not self.target and self.patrol then
        self:set('exploring','Exploring the area')
        local ok,arrived=pcall(self.move_to,self,self.patrol,nil,200)
        if not ok or arrived or now>self.patrol_until then self.patrol=nil;self:stop();self.next_scan=0 end
    end
end
return Runner
