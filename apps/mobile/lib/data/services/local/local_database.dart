import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

class LocalResources extends Table {
  TextColumn get aggregateType => text()();
  TextColumn get aggregateId => text()();
  TextColumn get envelopeJson => text()();
  IntColumn get updatedAtEpochMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {aggregateType, aggregateId};
}

class LocalOutbox extends Table {
  TextColumn get mutationId => text()();
  TextColumn get accountId => text()();
  TextColumn get aggregateType => text()();
  TextColumn get aggregateId => text()();
  IntColumn get sequence => integer()();
  TextColumn get status => text()();
  TextColumn get createdAtUtc => text()();
  TextColumn get payloadJson => text()();
  IntColumn get baseVersion => integer().nullable()();
  IntColumn get clientSequence => integer().nullable()();
  TextColumn get dependsOnMutationId => text().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get nextAttemptAtUtc => text().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  // Set once when the entry is claimed for sending and never cleared. Only
  // entries without it may be coalesced: a sent mutation id must keep its body.
  TextColumn get sentAtUtc => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {mutationId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {accountId, aggregateType, aggregateId, sequence},
  ];
}

class LocalSyncMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class LocalConflicts extends Table {
  TextColumn get conflictId => text()();
  TextColumn get aggregateType => text()();
  TextColumn get aggregateId => text()();
  TextColumn get createdAtUtc => text()();
  TextColumn get code => text()();
  TextColumn get detailJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {conflictId};
}

class LocalTombstones extends Table {
  TextColumn get resourceType => text()();
  TextColumn get resourceId => text()();
  IntColumn get revision => integer()();

  @override
  Set<Column<Object>> get primaryKey => {resourceType, resourceId};
}

class InstallationMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Sync metadata key holding the training schema version of an account
/// database. Databases without it predate the training rebuild (D11).
const trainingSchemaVersionKey = 'training-schema-version';
const currentTrainingSchemaVersion = 2;

@DriftDatabase(
  tables: [
    LocalResources,
    LocalOutbox,
    LocalSyncMetadata,
    LocalConflicts,
    LocalTombstones,
    InstallationMetadata,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  static const accountIdPattern =
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

  static Future<LocalDatabase> openForAccount(String accountId) async {
    _validateAccountId(accountId);
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'accounts'));
    await directory.create(recursive: true);
    final file = File(
      p.join(directory.path, 'account-${accountId.toLowerCase()}.sqlite'),
    );
    return LocalDatabase(NativeDatabase.createInBackground(file));
  }

  /// Stable installation identity is stored in a separate global database,
  /// never in a user account database and never derived from personal data.
  static Future<LocalDatabase> openInstallationStore() async {
    final root = await getApplicationSupportDirectory();
    final file = File(p.join(root.path, 'installation.sqlite'));
    return LocalDatabase(NativeDatabase.createInBackground(file));
  }

  static void _validateAccountId(String accountId) {
    if (!RegExp(accountIdPattern).hasMatch(accountId)) {
      throw ArgumentError.value(accountId, 'accountId', 'Expected a UUID.');
    }
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // A new database has no training data from before the rebuild.
      await into(localSyncMetadata).insert(
        LocalSyncMetadataCompanion.insert(
          key: trainingSchemaVersionKey,
          valueJson: '$currentTrainingSchemaVersion',
        ),
      );
    },
    onUpgrade: (m, from, to) async {
      // Version 1 already had a durable outbox. Version 2 adds retry state;
      // these additive columns preserve all queued rows during upgrade.
      if (from < 2) {
        await m.addColumn(localOutbox, localOutbox.attemptCount);
        await m.addColumn(localOutbox, localOutbox.nextAttemptAtUtc);
        await m.addColumn(localOutbox, localOutbox.lastErrorCode);
      }
      // Entries queued before this version may already have been sent, so
      // they are marked as sent and never coalesced.
      if (from < 3) {
        await m.addColumn(localOutbox, localOutbox.sentAtUtc);
        await customStatement(
          'UPDATE local_outbox SET sent_at_utc = created_at_utc',
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );
}
