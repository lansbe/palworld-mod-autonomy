-- Pure configuration and goal rules, also used by the native settings broker.
local M={}
M.defaults={capture_mode='all',targets='',materials='',quota=5,wood=0,stone=0,radius=100,max_level=5,health=45,weaken=false,sphere_reserve=3,max_throws=5,explore=true,eat=true,return_home=true,session_minutes=30}
local bounds={quota={1,100},wood={0,9999},stone={0,9999},radius={20,500},max_level={1,100},health={20,90},sphere_reserve={0,999},max_throws={1,20},session_minutes={1,240}}
local function trim(s)return s:match('^%s*(.-)%s*$')end
local function key(s)return trim(s):lower():gsub('%s+',' ')end
function M.targets(text,catalog,kind)
    kind=kind or 'Pal'
    assert(type(text)=='string' and #text<=1024,'Target list exceeds 1024 characters')
    local index={}
    for _,p in ipairs(catalog) do index[key(p.id)]=p.id;index[key(p.label)]=p.id end
    local out={}
    if trim(text)=='' then return out end
    assert(not text:match(';%s*$') and not text:match('^%s*;') and not text:match(';%s*;'),'A target is empty')
    for token in text:gmatch('[^;]+') do
        local name,n=token:match('^%s*(.-)%s*=%s*(%d+)%s*$')
        assert(name and n,'Expected format: Lamball=5; Cattiva=3')
        local id=index[key(name)];assert(id,kind..' is unknown: '..tostring(name))
        n=tonumber(n);assert(n>=1 and n<=(kind=='Pal' and 999 or 9999),'Quantity is out of range')
        assert(not out[id],kind..' is duplicated: '..name);out[id]=n
    end
    return out
end
function M.validate(v,catalog,materials)
    local cfg={}
    for k,d in pairs(M.defaults) do
        local x=v[k];if x==nil then x=d end
        if bounds[k] then assert(type(x)=='number' and x==math.floor(x) and x>=bounds[k][1] and x<=bounds[k][2],'Invalid value: '..k)
        elseif type(d)=='boolean' then assert(type(x)=='boolean','Invalid value: '..k)
        elseif k=='capture_mode' then assert(x=='off' or x=='selected' or x=='all','Invalid capture mode')
        end
        cfg[k]=x
    end
    cfg.goals=M.targets(cfg.targets,catalog)
    cfg.resources=M.targets(cfg.materials,materials or {},'Item')
    assert(not cfg.resources.Wood or cfg.wood==0,'Wood appears in both fields')
    assert(not cfg.resources.Stone or cfg.stone==0,'Stone appears in both fields')
    cfg.resources.Wood=cfg.resources.Wood or cfg.wood;cfg.resources.Stone=cfg.resources.Stone or cfg.stone
    assert(cfg.capture_mode~='selected' or next(cfg.goals)~=nil or next(M.remaining_resources(cfg,{counts={}}))~=nil,'Add a capture or gathering goal')
    assert(cfg.capture_mode~='off' or next(M.remaining_resources(cfg,{counts={}}))~=nil,'Add a gathering goal')
    return cfg
end
function M.goal(cfg,id)
    if cfg.capture_mode=='off' then return 0 end
    if cfg.capture_mode=='all' then return cfg.quota end
    return cfg.goals[id] or 0
end
function M.wanted(cfg,counts,id)return (counts[id] or 0)<M.goal(cfg,id)end
function M.remaining_resources(cfg,inv)
    local out={}
    for id,n in pairs(cfg.resources)do if (inv.counts[id] or 0)<n then out[id]=n-(inv.counts[id] or 0)end end
    return out
end
function M.complete(cfg,inv,catalog)
    if next(M.remaining_resources(cfg,inv)) then return false end
    if cfg.capture_mode=='all' then
        for _,p in ipairs(catalog) do if M.wanted(cfg,inv.captures,p.id) then return false end end
    elseif cfg.capture_mode=='selected' then
        for id,n in pairs(cfg.goals) do if (inv.captures[id] or 0)<n then return false end end
    end
    return true
end
return M
