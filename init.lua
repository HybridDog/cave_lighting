local load_time_start = os.clock()

local function light_cave(player, name, maxlight)
	local pos = 
end

minetest.register_chatcommand("light_cave",{
	description = "light a cave",
	params = "[maxlight]",
	privs = {give = true},
	func = function(name, param)
		local player = minetest.get_player_from_name(name)
		local maxlight = tonumber(param) or 10
		if not player then
			return false, "Player not found"
		end
		light_cave(player, name, maxlight)
	end
})

local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "[cave_lighting] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
