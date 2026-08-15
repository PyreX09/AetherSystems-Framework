local Logger = require(game.ReplicatedStorage.AetherShared.Utils.Logger)

for _, entry in ipairs(Logger:GetHistory()) do
	print(
		"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
		"\nID:", entry.id,
		"\nTimestamp:", entry.timestamp,
		"\nTime:", entry.time,
		"\nLevel:", entry.level,
		"\nCategory:", entry.category,
		"\nMessage:", entry.message,
		"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	)
end