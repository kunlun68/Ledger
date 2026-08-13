import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.open(executor: NativeDatabase.memory()));
  tearDown(() => db.close());

  test('database opens and both tables exist', () async {
    final tables = await db
        .customSelect('SELECT name FROM sqlite_master WHERE type=\'table\'')
        .map((r) => r.read<String>('name'))
        .get();
    expect(tables, containsAll(['transactions', 'categories']));
  });
}
