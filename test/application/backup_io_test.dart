import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/backup_io.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/backup_dao.dart';
import 'package:ledger/data/database.dart';

void main() {
  test('backupIOProvider and backupDaoProvider resolve', () {
    final db = AppDatabase.open(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    expect(container.read(backupIOProvider), isA<SharePlusBackupIO>());
    expect(container.read(backupDaoProvider), isA<BackupDao>());
  });
}
