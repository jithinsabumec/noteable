class Config {
  static const String assemblyAIKey = String.fromEnvironment(
    'ASSEMBLY_AI_KEY',
  );

  static const String openRouterAPIKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
  );

  /// RevenueCat API keys
  static const String revenueCatGoogleApiKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_API_KEY',
  );

  static const String revenueCatAppleApiKey = String.fromEnvironment(
    'REVENUECAT_APPLE_API_KEY',
  );

  /// Google Auth client ID
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );
}
