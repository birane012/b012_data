import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/entities.dart';
import 'support/harness.dart';

final DataAccess da = DataAccess.instance;

void main() {
  useSandbox();

  test('twenty first accesses at once open the database once', () async {
    final int before = da.debugOpenCount;
    final List<bool> results = await Future.wait(<Future<bool>>[
      for (int i = 0; i < 20; i++)
        da.insertObjet(Account(null, 'u$i@b.c', 'x')),
    ]);
    expect(results, everyElement(isTrue));
    expect(da.debugOpenCount - before, 1);
    expect(await da.countElementsOf<Account>(), 20);
  });

  test('closeDB then access reopens', () async {
    await da.insertObjet(Account(null, 'a@b.c', 'x'));
    final int before = da.debugOpenCount;
    await da.closeDB();
    expect(await da.countElementsOf<Account>(), 1);
    expect(da.debugOpenCount - before, 1);
  });

  test('dropTable forgets the table: the next insert recreates it', () async {
    await da.insertObjet(Account(null, 'a@b.c', 'x'));
    await da.dropTable<Account>();
    expect(await da.insertObjet(Account(null, 'a@b.c', 'x')), isTrue);
  });
}
