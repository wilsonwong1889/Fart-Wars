-- Live events (masterplan 6.3), behind FeatureFlags.EVENTS (off as
-- shipped). Bean Rain: once in a while during a round, beans fall on the
-- lanes. Each is announced (the banner WARNING_SECONDS before the rain,
-- and a ring on the ground TELEGRAPH_SECONDS before each bean lands), it
-- never lands in a spawn room, and picking one up pays a few coins and
-- refills your Fart Dash. Nothing in it hurts anyone, the shooting goes on
-- as normal, and the parts are capped (MAX_BEANS, markers included).
return table.freeze({
	-- The chance a round gets Bean Rain, and when in the round it can start.
	CHANCE_PER_ROUND = 0.5,
	EARLIEST_SECONDS = 60,
	LATEST_SECONDS = 180,
	BEAN_RAIN = table.freeze({
		id = "BeanRain",
		name = "Bean Rain",
		WARNING_SECONDS = 5,
		DURATION_SECONDS = 20,
		BEANS_PER_SECOND = 1.5,
		MAX_BEANS = 12,
		TELEGRAPH_SECONDS = 2,
		BEAN_SECONDS = 8,
		PICKUP_RADIUS = 4,
		COINS = 3,
		MAX_PER_PLAYER = 8,
	}),
})
