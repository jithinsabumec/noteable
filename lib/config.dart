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
