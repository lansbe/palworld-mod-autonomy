local Scanner={};Scanner.__index=Scanner
function Scanner.new() return setmetatable({characters={},resources={}},Scanner) end
function Scanner.character(object) return api.controls('character',{target=api.remember(object)}) end
function Scanner:step(command)
    local result=api.controls('scan',command)
    self.characters,self.resources=result.characters,result.resources
    return {ready=result.ready}
end
return Scanner
