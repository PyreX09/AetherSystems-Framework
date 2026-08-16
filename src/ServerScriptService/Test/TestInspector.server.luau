local RS = game:GetService("ReplicatedStorage")

local NetworkCore = require(
	RS.AetherShared.Utils.NetworkCore
)

NetworkCore.TraceEnabled = true

NetworkCore.Trace({
	Direction = "TEST",
	Event = "Hello.World",
	Target = "Server"
})

task.wait(1)

local logs = NetworkCore.GetTrace()

for _, data in ipairs(logs) do
	print(
		data.Time,
		data.Direction,
		data.Event,
		data.Target
	)
end