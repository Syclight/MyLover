return {
    name = "Love2dTest",
    -- game = os.getenv("LOVE_GAME") or "games.surveillance.Game",
    game = os.getenv("LOVE_GAME") or "games.nagashino.Game",
    globalManifest = "engine/assets/manifest/global.lua",
    testModule = "tests.run",
    debugOverlay = true,
}
