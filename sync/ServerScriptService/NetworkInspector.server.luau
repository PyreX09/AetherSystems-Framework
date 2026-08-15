local RS = game:GetService("ReplicatedStorage")

local NetworkCore = require(RS.AetherShared.Utils.NetworkCore)

task.wait(5)

while true do
	task.wait(5)

	print("===== NETWORK TRACE =====")

	local logs = NetworkCore.GetTrace()

	for _, data in ipairs(logs) do
		print(string.format(
			"%s | %s | %s",
			data.Direction,
			data.Event,
			data.Target
			))

		if data.Meta then
			for key, value in pairs(data.Meta) do
				print(string.format(
					"%s: %s",
					key,
					tostring(value)
					))
			end
		end
	end
end