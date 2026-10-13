package.path='src/?.lua;'..package.path
local Rules=require('settings');local Runner=require('runner')
local cat={{id='SheepBall',label='Lamball'},{id='PinkCat',label='Cattiva'}}
local function cfg(changes)local c={};for k,v in pairs(Rules.defaults)do c[k]=v end;c.capture_mode='selected';c.targets='Lamball=5';for k,v in pairs(changes or {})do c[k]=v end;return Rules.validate(c,cat)end
local materials={{id='CopperOre',label='Metal ore'}}
assert(Rules.targets('Metal ore=35',materials,'Item').CopperOre==35)
assert(Rules.targets(' lamball = 5; CATTIVA=2',cat).SheepBall==5)
for _,s in ipairs({'Lamball=-1','Lamball=0','Lamball=2.5','Lamball=1000','Lamball=5;SheepBall=2','Lamball=5;;Cattiva=2','Unknown=5','Lamball=5;'})do assert(not pcall(Rules.targets,s,cat),s)end
assert(not pcall(cfg,{radius=1/0}));assert(not pcall(cfg,{radius=25.5}))
assert(Rules.wanted(cfg(),{SheepBall=4},'SheepBall'))
assert(not Rules.wanted(cfg(),{SheepBall=5},'SheepBall'),'lifetime quota ignored')
assert(not Rules.wanted(cfg(),{},'PinkCat'),'unselected species targeted')
assert(Rules.wanted(cfg({capture_mode='all',quota=5}),{SheepBall=1},'SheepBall'))
assert(not Rules.complete(cfg(),{counts={},captures={SheepBall=4}},cat))
assert(Rules.complete(cfg(),{counts={},captures={SheepBall=5}},cat))
assert(not Rules.complete(cfg({wood=2}),{counts={Wood=1},captures={SheepBall=5}},cat))
local commands={};local playable=true;local health=1;local inv={counts={PalSphere=10},captures={},weight=0,max_weight=100,hunger=1,level=1};local present=true
local t={target='pal',position={x=200,y=0,z=0},distance_m=2,character={character_id='SheepBall',level=1,hp_ratio=1,dead=false,dying=false},wild=true,is_pal=true,player=false,capturing=false,boss=false,uncapturable=false}
local function call(a,c)
 commands[#commands+1]={a,c}
 if a=='state' then return {playable=playable,phase='world',hp_ratio=health,pose={position={x=0,y=0,z=0},camera={yaw=0}}} end
 if a=='autonomy_scan' then return {ready=true}end
 if a=='autonomy_inventory' then return inv end
 if a=='autonomy_creatures' then return {t} end
 if a=='autonomy_resources' then return {} end
 if a=='autonomy_patrol' then return {unavailable=true} end
 if a=='autonomy_actor' then assert(present,'expired actor');return t end
 if a=='gameplay' then return {melee=true} end
 if a=='stop' or a=='aim_at' or a=='autonomy_ball' or a=='act' or a=='camera_follow' then return {} end
 error('Unexpected action '..a)
end
local r=Runner.new(cfg({targets='Lamball=1',return_home=false,sphere_reserve=0}),cat,call)
r:tick(0);assert(r.phase=='approaching');r:tick(.2);assert(r.phase=='capturing' and r.stats.throws==1)
local n=#commands;r:tick(1);assert(r.stats.throws==1,'capture replayed before acknowledgement')
present=false;inv.captures.SheepBall=1;r:tick(1.8)
assert(r.phase=='complete' and r.stats.captures==1,'capture not confirmed after actor removed')
for i=n+1,#commands do assert(commands[i][1]~='autonomy_actor','expired actor dereferenced after record confirmed')end
inv.captures={};present=true
r=Runner.new(cfg({return_home=false}),cat,call);r:tick(0);playable=false;commands={};r:tick(.2)
assert(r.phase=='paused');for _,c in ipairs(commands)do assert(c[1]=='state' or c[1]=='stop','action during menu')end
playable=true;health=.2;commands={};r:tick(.4);assert(r.phase=='resting')
for _,c in ipairs(commands)do assert(c[1]~='act','attacked with low health')end
health=1;inv.counts.PalSphere=3
r=Runner.new(cfg({sphere_reserve=3}),cat,call);r:tick(0);assert(r.phase=='searching' and not r.target,'reserve spent')
inv.counts.PalSphere=10
for _,change in ipairs({{player=true},{boss=true},{wild=false},{uncapturable=true},{capturing=true}})do
 local k,v=next(change);local old=t[k];t[k]=v
 r=Runner.new(cfg(),cat,call);r:tick(0);assert(not r.target,'ineligible creature selected');t[k]=old
end
-- A cold observation pass must finish before any target selection or movement.
local cold={}
r=Runner.new(cfg({capture_mode='off',wood=2}),cat,function(a,c)
 cold[#cold+1]=a
 if a=='state' then return {playable=true,hp_ratio=1,pose={position={x=0,y=0,z=0},camera={yaw=0}}}end
 if a=='autonomy_inventory' then return {counts={},captures={},weight=0,max_weight=100,hunger=1}end
 if a=='autonomy_scan' then return {ready=false}end
 if a=='stop' then return {}end
 error('Action before observation finished: '..a)
end)
r:tick(0);assert(r.phase=='searching' and r.message.key=='status.observing' and not r.target)

-- Static routes survive the old four-second replan deadline. Moving capture
-- targets still refresh their route; prolonged movement is not a unit-test wait.
local paths=0
r=Runner.new(cfg(),cat,function(a,c)
 if a=='path' then paths=paths+1;return {partial=false,points={{x=0,y=0,z=0},{x=1000,y=0,z=0},{x=3000,y=0,z=0}}}end
 if a=='move' or a=='stop' or a=='camera_follow' then return {}end
 error(a)
end)
r.target={kind='pickup'};r.state={pose={position={x=0,y=0,z=0},camera={yaw=0}}};r.now=0
r:move_to({x=3000,y=0,z=0},'pickup',160)
r.now=5;r.state.pose.position={x=100,y=0,z=0};r:move_to({x=3000,y=0,z=0},'pickup',160)
assert(paths==1,'static route restarted after four seconds')
r.target.kind='capture';r.now=10;r.state.pose.position={x=200,y=0,z=0};r:move_to({x=3000,y=0,z=0},'pal',160)
assert(paths==2,'moving target route never refreshed')

-- A pickup below the walkable shoreline must not oscillate along its projection.
r=Runner.new(cfg(),cat,function(a)
 if a=='autonomy_actor' then return {position={x=100,y=0,z=0}}end
 if a=='stop' then return {}end
 error('Unreachable pickup triggered '..a)
end)
r.now=1;r.state={pose={position={x=0,y=0,z=300}}};r.target={target='buried',kind='pickup',started=0,label='Stone'}
r:target_step();assert(not r.target and r.skip.buried==91)
inv.counts.PalSphere=10;inv.captures={};present=true
r=Runner.new(cfg({targets='Lamball=1',return_home=false,sphere_reserve=0}),cat,function(a,c)
 if a=='aim_at' then assert(c.smooth==true);return {aligned=false}end
 if a=='autonomy_ball' or a=='act' then error('Capture fired while camera was turning')end
 return call(a,c)
end)
r:tick(0);r:tick(.2);assert(r.stats.throws==0,'Sphere spent before view aligned')
print('PASS: objectives, confirmed capture, menu pause, health, reserves, cold observation, stable navigation, unreachable pickups and camera alignment before throw')

-- Escape planning gets one path candidate per decision and backs off when none
-- is reachable, rather than forty synchronous searches/second forever.
local attempts,scans=0,0
r=Runner.new(cfg(),cat,function(a)
 if a=='autonomy_scan' then scans=scans+1;return {ready=true}end
 if a=='autonomy_creatures' then return {}end
 if a=='autonomy_patrol' then attempts=attempts+1;return {unavailable=true}end
 if a=='stop' then return {}end
 error('Unexpected escape action '..a)
end)
r.state={in_combat=true,pose={position={x=0,y=0,z=0}}}
for i=0,3 do r.now=i*.1;local before=attempts;r:flee();assert(attempts-before==1)end
assert(attempts==4 and r.phase=='blocked')
for i=4,12 do r.now=i*.1;r:flee()end
assert(attempts==4 and scans==13,'Failed escape retried every decision or stopped observing')
r.now=1.4;r:flee();assert(attempts==5)
r.state.in_combat=false;r:flee();assert(r.phase=='resting' and not r.escape_search)
print('PASS: escape candidates distributed across frames, failed-route backoff and observations during retreat')

local returns=0
r=Runner.new(cfg(),cat,function(a)
 if a=='path' then returns=returns+1;return {partial=true,points={}}end
 if a=='stop' or a=='camera_follow' then return {}end
 error(a)
end)
r.origin={x=0,y=0,z=0};r.state={pose={position={x=3000,y=0,z=0},camera={yaw=0}}}
for i=0,19 do r.now=i*.1;r:returning('Goals complete',true)end
assert(returns==1 and r.phase=='blocked' and not r.finished,'Failed return spammed paths or claimed completion')
r.now=2.1;r:returning('Goals complete',true);assert(returns==2)
r.state.pose.position={x=100,y=0,z=0};r.now=2.2;r:returning('Goals complete',true)
assert(r.phase=='complete' and r.finished,'Actual arrival not confirmed')
print('PASS: failed-return retry budget and completion only after arrival')
