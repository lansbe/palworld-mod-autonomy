-- Keep presentation records independent of the active language and controller state.
local Text={}
function Text.message(key,arguments) return {key=key,arguments=arguments or {}} end
function Text.render(message,translate)
    if type(message)~='table' then return tostring(message or '') end
    local arguments={}
    for key,value in pairs(message.arguments) do
        arguments[key]=type(value)=='table' and Text.render(value,translate) or value
    end
    return translate(message.key,arguments)
end
function Text.same(a,b)
    if type(a)~='table' or type(b)~='table' then return a==b end
    if a.key~=b.key then return false end
    for key,value in pairs(a.arguments) do if not Text.same(value,b.arguments[key]) then return false end end
    for key in pairs(b.arguments) do if a.arguments[key]==nil then return false end end
    return true
end
function Text.failure(detail)
    local message=Text.message('status.target_failed')
    message.diagnostic=tostring(detail):gsub('^.-%.lua:%d+: ','')
    return message
end
function Text.diagnostics(events)
    local result={}
    for index,event in ipairs(events) do
        if type(event)=='table' and event.diagnostic then result[#result+1]={event=index,detail=event.diagnostic} end
    end
    return result
end
return Text
