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
