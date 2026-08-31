import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/backup/domain/backup_repository.dart';

/// In-memory [BackupRepository] for widget tests.
///
/// [buildBackup] returns [envelope] (or throws [buildError]).
/// [restoreBackup] records the restored envelope (or throws [restoreError]).
final class FakeBackupRepository implements BackupRepository {
  BackupEnvelope envelope = BackupEnvelope(
    shopId: 'shop-1',
    tables: BackupTables(),
  );

  /// Thrown by [buildBackup] when set.
  Object? buildError;

  /// Thrown by [restoreBackup] when set.
  Object? restoreError;

  /// Whether [restoreBackup] has been invoked.
  bool restoreCalled = false;

  /// The last envelope passed to [restoreBackup].
  BackupEnvelope? restored;

  @override
  Future<BackupEnvelope> buildBackup() async {
    final error = buildError;
    if (error != null) throw error;
    return envelope;
  }

  @override
  Future<void> restoreBackup(BackupEnvelope envelope) async {
    restoreCalled = true;
    final error = restoreError;
    if (error != null) throw error;
    restored = envelope;
  }
}
