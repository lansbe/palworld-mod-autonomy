package.path='src/?.lua;'..package.path
local Text=require('presentation')
local messages={en={['status.return']='Returning: {reason}',['status.done']='Captured {count} {name}'},
    fr={['status.return']='Retour : {reason}',['status.done']='{count} {name} capturés'}}
local language='en'
local function translate(key,args)
    return (messages[language][key]:gsub('{(%w+)}',function(name) return tostring(args[name]) end))
end
local reason=Text.message('status.done',{count=5,name='Lamball'})
local event=Text.message('status.return',{reason=reason})
assert(Text.render(event,translate)=='Returning: Captured 5 Lamball')
language='fr'
assert(Text.render(event,translate)=='Retour : 5 Lamball capturés')
assert(reason.arguments.name=='Lamball' and reason.arguments.count==5,'Rendering must not mutate controller data')
assert(Text.same(event,Text.message('status.return',{reason=Text.message('status.done',{count=5,name='Lamball'})})))
assert(not Text.same(reason,Text.message('status.done',{count=6,name='Lamball'})))
local failure=Text.failure('backend.lua:52: Unreachable target')
assert(failure.key=='status.target_failed' and failure.diagnostic=='Unreachable target')
assert(Text.diagnostics({reason,failure})[1].detail=='Unreachable target','Localized failures must retain technical detail')
print('PASS: existing status records change language without changing controller state')
