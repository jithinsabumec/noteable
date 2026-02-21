class Config {
  static const String assemblyAIKey = String.fromEnvironment(
    'ASSEMBLY_AI_KEY',
    defaultValue: '62e8e9b15cef4e42a42bd4b5849faada',
  );

  static const String openRouterAPIKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue:
        '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',
  );
}
