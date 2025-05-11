class Config {
  static const String assemblyAIKey = String.fromEnvironment(
    'ASSEMBLY_AI_KEY',
    defaultValue: '62e8e9b15cef4e42a42bd4b5849faada',
  );

  static const String deepseekAPIKey = String.fromEnvironment(
    'DEEPSEEK_API_KEY',
    defaultValue: 'sk-1ef8bd82e1cd4a64a2c1a687a5117743',
  );
}
