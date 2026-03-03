class ApiConstants {
  ApiConstants._();

  static String runtimeApiKey = '';
  static const String model = 'deepseek-chat';
  static const String chatCompletionsUrl =
      'https://api.deepseek.com/chat/completions';
  static const String chatCompletionsCompatUrl =
      'https://api.deepseek.com/v1/chat/completions';
  static const int requestTimeoutSeconds = 60;

  static bool get hasApiKey => runtimeApiKey.trim().isNotEmpty;
}
