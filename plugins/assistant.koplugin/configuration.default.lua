-- Safe local UI default. Real provider credentials are never shipped in the APK.
return {
    provider = "offline",
    provider_settings = {
        offline = { model = "Not configured (local UI only)", base_url = "", api_key = "" },
    },
    features = {},
}
