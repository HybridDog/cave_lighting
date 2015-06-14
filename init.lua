local load_time_start = os.clock()

local function pos_allowed(pos, maxlight)
	local light = minetest.get_node_light(pos, 0.5)
	if not light
	or light > maxlight then
		return false
	end
	if minetest.get_node(pos).name ~= "air" then
		return false
	end
	for i = -1,1,2 do
		for _,p2 in pairs({
			{x=pos.x+i, y=pos.y, z=pos.z},
			{x=pos.x, y=pos.y+i, z=pos.z},
			{x=pos.x, y=pos.y, z=pos.z+i},
		}) do
			if minetest.get_node(p2).name ~= "air" then
				return true
			end
		end
	end
	return false
end

local function get_ps(pos, maxlight, max)
	local tab = {pos}
	local todo = {pos}
	local num = 2
	local tab_avoid = {[pos.x.." "..pos.y.." "..pos.z] = true}
	while todo[1] do
		for n,p in pairs(todo) do
			for i = -1,1 do
				for j = -1,1 do
					for k = -1,1 do
						local p2 = {x=p.x+i, y=p.y+j, z=p.z+k}
						local pstr = p2.x.." "..p2.y.." "..p2.z
						if not tab_avoid[pstr]
						and pos_allowed(p2, maxlight) then
		minetest.chat_send_all("It big.")
							tab[num] = p2
							tab_avoid[pstr] = true
							num = num+1
							table.insert(todo, p2)
							if max
							and num > max then
								return false
							end
						end
					end
				end
			end
			todo[n] = nil
		end
	end
	return tab
end

local function place_torches(pos, maxlight, player, name)
	local ps = get_ps(pos, maxlight, 2000)
	if not ps then
		minetest.chat_send_player(name, "It doesn't seem to be dark there or the cave is too big.")
		return
	end
	while next(ps) do
		for n,pos in pairs(ps) do
			local light = minetest.get_node_light(pos, 0.5) or 0
			if light <= maxlight then
				minetest.set_node(pos, {name = "default:torch"})
				minetest.chat_send_player(name, "Torch placed.")
			end
			ps[n] = nil
		end
	end
	return true
end

local function light_cave(player, name, maxlight)
	local pos = player:getpos()
	pos.y = pos.y+1.625
	pos = vector.round(pos)
	local dir = player:get_look_dir()
	local p2 = vector.add(pos, vector.round(vector.multiply(dir, 20)))
	local bl, pos2 = minetest.line_of_sight(pos, p2, 1)
	if bl then
		minetest.chat_send_player(name, "Could not find a node you look at.")
		return
	end
	pos = vector.round(vector.subtract(pos2, dir))
	if minetest.get_node(pos).name ~= "air" then
		minetest.chat_send_player(name, "Something went wrong.")
		return
	end
	if place_torches(pos, maxlight, player, name) then
		minetest.chat_send_player(name, "Successfully lit a cave.")
	end
end

minetest.register_chatcommand("light_cave",{
	description = "light a cave",
	params = "[maxlight]",
	privs = {give = true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		local maxlight = tonumber(param) or 5
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
