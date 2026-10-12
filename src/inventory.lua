return {
    read=function() return api.controls('inventory') end,
    ball=function(command) return api.controls('select_sphere',command) end,
    food=function() return api.controls('use_food') end,
}
