import 'chat_persistence.dart';
import 'conversation_timeline.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';

class StoryTurnHandle {
  const StoryTurnHandle(
      {required this.id,
      required this.contactId,
      required this.branchId,
      required this.startSequence,
      required this.beforeRevision});
  final String id, contactId, branchId;
  final int startSequence, beforeRevision;
}

class StoryTruncation {
  const StoryTruncation(
      {required this.contactId,
      required this.branchId,
      required this.startSequence,
      required this.expectedRevision,
      required this.beforeRevision,
      required this.turnCount,
      required this.input,
      this.turnId,
      this.legacyCheckpointId});
  final String contactId, branchId, input;
  final String? turnId, legacyCheckpointId;
  final int startSequence, expectedRevision, beforeRevision, turnCount;
}

abstract interface class StoryTurnPersistence {
  Future<StoryTurnHandle> beginStoryTurn(
      {required String contactId, required Message userMessage});
  Future<void> commitStoryTurn(
      {required StoryTurnHandle turn,
      required Contact contact,
      required List<Message> messages});
  Future<void> abortStoryTurn(
      {required StoryTurnHandle turn, required List<Message> messages});
  Future<StoryTruncation?> previewStoryTruncation(
      {required String contactId, String? messageId});
  Future<void> truncateStory(StoryTruncation target);
  Future<void> recoverStoryAttempts();
  Future<void> restoreStoryBackup(
      ChatSnapshot snapshot, ConversationTimelineArchive archive);
}
