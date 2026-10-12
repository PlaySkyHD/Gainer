// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $LocalResourcesTable extends LocalResources
    with TableInfo<$LocalResourcesTable, LocalResource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalResourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _aggregateTypeMeta = const VerificationMeta(
    'aggregateType',
  );
  @override
  late final GeneratedColumn<String> aggregateType = GeneratedColumn<String>(
    'aggregate_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _envelopeJsonMeta = const VerificationMeta(
    'envelopeJson',
  );
  @override
  late final GeneratedColumn<String> envelopeJson = GeneratedColumn<String>(
    'envelope_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtEpochMsMeta = const VerificationMeta(
    'updatedAtEpochMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtEpochMs = GeneratedColumn<int>(
    'updated_at_epoch_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    aggregateType,
    aggregateId,
    envelopeJson,
    updatedAtEpochMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_resources';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalResource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('aggregate_type')) {
      context.handle(
        _aggregateTypeMeta,
        aggregateType.isAcceptableOrUnknown(
          data['aggregate_type']!,
          _aggregateTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateTypeMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateIdMeta);
    }
    if (data.containsKey('envelope_json')) {
      context.handle(
        _envelopeJsonMeta,
        envelopeJson.isAcceptableOrUnknown(
          data['envelope_json']!,
          _envelopeJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_envelopeJsonMeta);
    }
    if (data.containsKey('updated_at_epoch_ms')) {
      context.handle(
        _updatedAtEpochMsMeta,
        updatedAtEpochMs.isAcceptableOrUnknown(
          data['updated_at_epoch_ms']!,
          _updatedAtEpochMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtEpochMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {aggregateType, aggregateId};
  @override
  LocalResource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalResource(
      aggregateType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_type'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      )!,
      envelopeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope_json'],
      )!,
      updatedAtEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_epoch_ms'],
      )!,
    );
  }

  @override
  $LocalResourcesTable createAlias(String alias) {
    return $LocalResourcesTable(attachedDatabase, alias);
  }
}

class LocalResource extends DataClass implements Insertable<LocalResource> {
  final String aggregateType;
  final String aggregateId;
  final String envelopeJson;
  final int updatedAtEpochMs;
  const LocalResource({
    required this.aggregateType,
    required this.aggregateId,
    required this.envelopeJson,
    required this.updatedAtEpochMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['aggregate_type'] = Variable<String>(aggregateType);
    map['aggregate_id'] = Variable<String>(aggregateId);
    map['envelope_json'] = Variable<String>(envelopeJson);
    map['updated_at_epoch_ms'] = Variable<int>(updatedAtEpochMs);
    return map;
  }

  LocalResourcesCompanion toCompanion(bool nullToAbsent) {
    return LocalResourcesCompanion(
      aggregateType: Value(aggregateType),
      aggregateId: Value(aggregateId),
      envelopeJson: Value(envelopeJson),
      updatedAtEpochMs: Value(updatedAtEpochMs),
    );
  }

  factory LocalResource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalResource(
      aggregateType: serializer.fromJson<String>(json['aggregateType']),
      aggregateId: serializer.fromJson<String>(json['aggregateId']),
      envelopeJson: serializer.fromJson<String>(json['envelopeJson']),
      updatedAtEpochMs: serializer.fromJson<int>(json['updatedAtEpochMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'aggregateType': serializer.toJson<String>(aggregateType),
      'aggregateId': serializer.toJson<String>(aggregateId),
      'envelopeJson': serializer.toJson<String>(envelopeJson),
      'updatedAtEpochMs': serializer.toJson<int>(updatedAtEpochMs),
    };
  }

  LocalResource copyWith({
    String? aggregateType,
    String? aggregateId,
    String? envelopeJson,
    int? updatedAtEpochMs,
  }) => LocalResource(
    aggregateType: aggregateType ?? this.aggregateType,
    aggregateId: aggregateId ?? this.aggregateId,
    envelopeJson: envelopeJson ?? this.envelopeJson,
    updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
  );
  LocalResource copyWithCompanion(LocalResourcesCompanion data) {
    return LocalResource(
      aggregateType: data.aggregateType.present
          ? data.aggregateType.value
          : this.aggregateType,
      aggregateId: data.aggregateId.present
          ? data.aggregateId.value
          : this.aggregateId,
      envelopeJson: data.envelopeJson.present
          ? data.envelopeJson.value
          : this.envelopeJson,
      updatedAtEpochMs: data.updatedAtEpochMs.present
          ? data.updatedAtEpochMs.value
          : this.updatedAtEpochMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalResource(')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('envelopeJson: $envelopeJson, ')
          ..write('updatedAtEpochMs: $updatedAtEpochMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(aggregateType, aggregateId, envelopeJson, updatedAtEpochMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalResource &&
          other.aggregateType == this.aggregateType &&
          other.aggregateId == this.aggregateId &&
          other.envelopeJson == this.envelopeJson &&
          other.updatedAtEpochMs == this.updatedAtEpochMs);
}

class LocalResourcesCompanion extends UpdateCompanion<LocalResource> {
  final Value<String> aggregateType;
  final Value<String> aggregateId;
  final Value<String> envelopeJson;
  final Value<int> updatedAtEpochMs;
  final Value<int> rowid;
  const LocalResourcesCompanion({
    this.aggregateType = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.envelopeJson = const Value.absent(),
    this.updatedAtEpochMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalResourcesCompanion.insert({
    required String aggregateType,
    required String aggregateId,
    required String envelopeJson,
    required int updatedAtEpochMs,
    this.rowid = const Value.absent(),
  }) : aggregateType = Value(aggregateType),
       aggregateId = Value(aggregateId),
       envelopeJson = Value(envelopeJson),
       updatedAtEpochMs = Value(updatedAtEpochMs);
  static Insertable<LocalResource> custom({
    Expression<String>? aggregateType,
    Expression<String>? aggregateId,
    Expression<String>? envelopeJson,
    Expression<int>? updatedAtEpochMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (aggregateType != null) 'aggregate_type': aggregateType,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (envelopeJson != null) 'envelope_json': envelopeJson,
      if (updatedAtEpochMs != null) 'updated_at_epoch_ms': updatedAtEpochMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalResourcesCompanion copyWith({
    Value<String>? aggregateType,
    Value<String>? aggregateId,
    Value<String>? envelopeJson,
    Value<int>? updatedAtEpochMs,
    Value<int>? rowid,
  }) {
    return LocalResourcesCompanion(
      aggregateType: aggregateType ?? this.aggregateType,
      aggregateId: aggregateId ?? this.aggregateId,
      envelopeJson: envelopeJson ?? this.envelopeJson,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (aggregateType.present) {
      map['aggregate_type'] = Variable<String>(aggregateType.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (envelopeJson.present) {
      map['envelope_json'] = Variable<String>(envelopeJson.value);
    }
    if (updatedAtEpochMs.present) {
      map['updated_at_epoch_ms'] = Variable<int>(updatedAtEpochMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalResourcesCompanion(')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('envelopeJson: $envelopeJson, ')
          ..write('updatedAtEpochMs: $updatedAtEpochMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalOutboxTable extends LocalOutbox
    with TableInfo<$LocalOutboxTable, LocalOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateTypeMeta = const VerificationMeta(
    'aggregateType',
  );
  @override
  late final GeneratedColumn<String> aggregateType = GeneratedColumn<String>(
    'aggregate_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<String> createdAtUtc = GeneratedColumn<String>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseVersionMeta = const VerificationMeta(
    'baseVersion',
  );
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
    'base_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clientSequenceMeta = const VerificationMeta(
    'clientSequence',
  );
  @override
  late final GeneratedColumn<int> clientSequence = GeneratedColumn<int>(
    'client_sequence',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dependsOnMutationIdMeta =
      const VerificationMeta('dependsOnMutationId');
  @override
  late final GeneratedColumn<String> dependsOnMutationId =
      GeneratedColumn<String>(
        'depends_on_mutation_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtUtcMeta = const VerificationMeta(
    'nextAttemptAtUtc',
  );
  @override
  late final GeneratedColumn<String> nextAttemptAtUtc = GeneratedColumn<String>(
    'next_attempt_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mutationId,
    accountId,
    aggregateType,
    aggregateId,
    sequence,
    status,
    createdAtUtc,
    payloadJson,
    baseVersion,
    clientSequence,
    dependsOnMutationId,
    attemptCount,
    nextAttemptAtUtc,
    lastErrorCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('aggregate_type')) {
      context.handle(
        _aggregateTypeMeta,
        aggregateType.isAcceptableOrUnknown(
          data['aggregate_type']!,
          _aggregateTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateTypeMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
        _baseVersionMeta,
        baseVersion.isAcceptableOrUnknown(
          data['base_version']!,
          _baseVersionMeta,
        ),
      );
    }
    if (data.containsKey('client_sequence')) {
      context.handle(
        _clientSequenceMeta,
        clientSequence.isAcceptableOrUnknown(
          data['client_sequence']!,
          _clientSequenceMeta,
        ),
      );
    }
    if (data.containsKey('depends_on_mutation_id')) {
      context.handle(
        _dependsOnMutationIdMeta,
        dependsOnMutationId.isAcceptableOrUnknown(
          data['depends_on_mutation_id']!,
          _dependsOnMutationIdMeta,
        ),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at_utc')) {
      context.handle(
        _nextAttemptAtUtcMeta,
        nextAttemptAtUtc.isAcceptableOrUnknown(
          data['next_attempt_at_utc']!,
          _nextAttemptAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mutationId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {accountId, aggregateType, aggregateId, sequence},
  ];
  @override
  LocalOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalOutboxData(
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      aggregateType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_type'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at_utc'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      baseVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_version'],
      ),
      clientSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}client_sequence'],
      ),
      dependsOnMutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}depends_on_mutation_id'],
      ),
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_attempt_at_utc'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
    );
  }

  @override
  $LocalOutboxTable createAlias(String alias) {
    return $LocalOutboxTable(attachedDatabase, alias);
  }
}

class LocalOutboxData extends DataClass implements Insertable<LocalOutboxData> {
  final String mutationId;
  final String accountId;
  final String aggregateType;
  final String aggregateId;
  final int sequence;
  final String status;
  final String createdAtUtc;
  final String payloadJson;
  final int? baseVersion;
  final int? clientSequence;
  final String? dependsOnMutationId;
  final int attemptCount;
  final String? nextAttemptAtUtc;
  final String? lastErrorCode;
  const LocalOutboxData({
    required this.mutationId,
    required this.accountId,
    required this.aggregateType,
    required this.aggregateId,
    required this.sequence,
    required this.status,
    required this.createdAtUtc,
    required this.payloadJson,
    this.baseVersion,
    this.clientSequence,
    this.dependsOnMutationId,
    required this.attemptCount,
    this.nextAttemptAtUtc,
    this.lastErrorCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mutation_id'] = Variable<String>(mutationId);
    map['account_id'] = Variable<String>(accountId);
    map['aggregate_type'] = Variable<String>(aggregateType);
    map['aggregate_id'] = Variable<String>(aggregateId);
    map['sequence'] = Variable<int>(sequence);
    map['status'] = Variable<String>(status);
    map['created_at_utc'] = Variable<String>(createdAtUtc);
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || baseVersion != null) {
      map['base_version'] = Variable<int>(baseVersion);
    }
    if (!nullToAbsent || clientSequence != null) {
      map['client_sequence'] = Variable<int>(clientSequence);
    }
    if (!nullToAbsent || dependsOnMutationId != null) {
      map['depends_on_mutation_id'] = Variable<String>(dependsOnMutationId);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAtUtc != null) {
      map['next_attempt_at_utc'] = Variable<String>(nextAttemptAtUtc);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    return map;
  }

  LocalOutboxCompanion toCompanion(bool nullToAbsent) {
    return LocalOutboxCompanion(
      mutationId: Value(mutationId),
      accountId: Value(accountId),
      aggregateType: Value(aggregateType),
      aggregateId: Value(aggregateId),
      sequence: Value(sequence),
      status: Value(status),
      createdAtUtc: Value(createdAtUtc),
      payloadJson: Value(payloadJson),
      baseVersion: baseVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(baseVersion),
      clientSequence: clientSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(clientSequence),
      dependsOnMutationId: dependsOnMutationId == null && nullToAbsent
          ? const Value.absent()
          : Value(dependsOnMutationId),
      attemptCount: Value(attemptCount),
      nextAttemptAtUtc: nextAttemptAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAtUtc),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
    );
  }

  factory LocalOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalOutboxData(
      mutationId: serializer.fromJson<String>(json['mutationId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      aggregateType: serializer.fromJson<String>(json['aggregateType']),
      aggregateId: serializer.fromJson<String>(json['aggregateId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      status: serializer.fromJson<String>(json['status']),
      createdAtUtc: serializer.fromJson<String>(json['createdAtUtc']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      baseVersion: serializer.fromJson<int?>(json['baseVersion']),
      clientSequence: serializer.fromJson<int?>(json['clientSequence']),
      dependsOnMutationId: serializer.fromJson<String?>(
        json['dependsOnMutationId'],
      ),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAtUtc: serializer.fromJson<String?>(json['nextAttemptAtUtc']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mutationId': serializer.toJson<String>(mutationId),
      'accountId': serializer.toJson<String>(accountId),
      'aggregateType': serializer.toJson<String>(aggregateType),
      'aggregateId': serializer.toJson<String>(aggregateId),
      'sequence': serializer.toJson<int>(sequence),
      'status': serializer.toJson<String>(status),
      'createdAtUtc': serializer.toJson<String>(createdAtUtc),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'baseVersion': serializer.toJson<int?>(baseVersion),
      'clientSequence': serializer.toJson<int?>(clientSequence),
      'dependsOnMutationId': serializer.toJson<String?>(dependsOnMutationId),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAtUtc': serializer.toJson<String?>(nextAttemptAtUtc),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
    };
  }

  LocalOutboxData copyWith({
    String? mutationId,
    String? accountId,
    String? aggregateType,
    String? aggregateId,
    int? sequence,
    String? status,
    String? createdAtUtc,
    String? payloadJson,
    Value<int?> baseVersion = const Value.absent(),
    Value<int?> clientSequence = const Value.absent(),
    Value<String?> dependsOnMutationId = const Value.absent(),
    int? attemptCount,
    Value<String?> nextAttemptAtUtc = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
  }) => LocalOutboxData(
    mutationId: mutationId ?? this.mutationId,
    accountId: accountId ?? this.accountId,
    aggregateType: aggregateType ?? this.aggregateType,
    aggregateId: aggregateId ?? this.aggregateId,
    sequence: sequence ?? this.sequence,
    status: status ?? this.status,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    payloadJson: payloadJson ?? this.payloadJson,
    baseVersion: baseVersion.present ? baseVersion.value : this.baseVersion,
    clientSequence: clientSequence.present
        ? clientSequence.value
        : this.clientSequence,
    dependsOnMutationId: dependsOnMutationId.present
        ? dependsOnMutationId.value
        : this.dependsOnMutationId,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAtUtc: nextAttemptAtUtc.present
        ? nextAttemptAtUtc.value
        : this.nextAttemptAtUtc,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
  );
  LocalOutboxData copyWithCompanion(LocalOutboxCompanion data) {
    return LocalOutboxData(
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      aggregateType: data.aggregateType.present
          ? data.aggregateType.value
          : this.aggregateType,
      aggregateId: data.aggregateId.present
          ? data.aggregateId.value
          : this.aggregateId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      status: data.status.present ? data.status.value : this.status,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      baseVersion: data.baseVersion.present
          ? data.baseVersion.value
          : this.baseVersion,
      clientSequence: data.clientSequence.present
          ? data.clientSequence.value
          : this.clientSequence,
      dependsOnMutationId: data.dependsOnMutationId.present
          ? data.dependsOnMutationId.value
          : this.dependsOnMutationId,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAtUtc: data.nextAttemptAtUtc.present
          ? data.nextAttemptAtUtc.value
          : this.nextAttemptAtUtc,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalOutboxData(')
          ..write('mutationId: $mutationId, ')
          ..write('accountId: $accountId, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('sequence: $sequence, ')
          ..write('status: $status, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('clientSequence: $clientSequence, ')
          ..write('dependsOnMutationId: $dependsOnMutationId, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAtUtc: $nextAttemptAtUtc, ')
          ..write('lastErrorCode: $lastErrorCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mutationId,
    accountId,
    aggregateType,
    aggregateId,
    sequence,
    status,
    createdAtUtc,
    payloadJson,
    baseVersion,
    clientSequence,
    dependsOnMutationId,
    attemptCount,
    nextAttemptAtUtc,
    lastErrorCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalOutboxData &&
          other.mutationId == this.mutationId &&
          other.accountId == this.accountId &&
          other.aggregateType == this.aggregateType &&
          other.aggregateId == this.aggregateId &&
          other.sequence == this.sequence &&
          other.status == this.status &&
          other.createdAtUtc == this.createdAtUtc &&
          other.payloadJson == this.payloadJson &&
          other.baseVersion == this.baseVersion &&
          other.clientSequence == this.clientSequence &&
          other.dependsOnMutationId == this.dependsOnMutationId &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAtUtc == this.nextAttemptAtUtc &&
          other.lastErrorCode == this.lastErrorCode);
}

class LocalOutboxCompanion extends UpdateCompanion<LocalOutboxData> {
  final Value<String> mutationId;
  final Value<String> accountId;
  final Value<String> aggregateType;
  final Value<String> aggregateId;
  final Value<int> sequence;
  final Value<String> status;
  final Value<String> createdAtUtc;
  final Value<String> payloadJson;
  final Value<int?> baseVersion;
  final Value<int?> clientSequence;
  final Value<String?> dependsOnMutationId;
  final Value<int> attemptCount;
  final Value<String?> nextAttemptAtUtc;
  final Value<String?> lastErrorCode;
  final Value<int> rowid;
  const LocalOutboxCompanion({
    this.mutationId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.aggregateType = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.clientSequence = const Value.absent(),
    this.dependsOnMutationId = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAtUtc = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalOutboxCompanion.insert({
    required String mutationId,
    required String accountId,
    required String aggregateType,
    required String aggregateId,
    required int sequence,
    required String status,
    required String createdAtUtc,
    required String payloadJson,
    this.baseVersion = const Value.absent(),
    this.clientSequence = const Value.absent(),
    this.dependsOnMutationId = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAtUtc = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mutationId = Value(mutationId),
       accountId = Value(accountId),
       aggregateType = Value(aggregateType),
       aggregateId = Value(aggregateId),
       sequence = Value(sequence),
       status = Value(status),
       createdAtUtc = Value(createdAtUtc),
       payloadJson = Value(payloadJson);
  static Insertable<LocalOutboxData> custom({
    Expression<String>? mutationId,
    Expression<String>? accountId,
    Expression<String>? aggregateType,
    Expression<String>? aggregateId,
    Expression<int>? sequence,
    Expression<String>? status,
    Expression<String>? createdAtUtc,
    Expression<String>? payloadJson,
    Expression<int>? baseVersion,
    Expression<int>? clientSequence,
    Expression<String>? dependsOnMutationId,
    Expression<int>? attemptCount,
    Expression<String>? nextAttemptAtUtc,
    Expression<String>? lastErrorCode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mutationId != null) 'mutation_id': mutationId,
      if (accountId != null) 'account_id': accountId,
      if (aggregateType != null) 'aggregate_type': aggregateType,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (sequence != null) 'sequence': sequence,
      if (status != null) 'status': status,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (baseVersion != null) 'base_version': baseVersion,
      if (clientSequence != null) 'client_sequence': clientSequence,
      if (dependsOnMutationId != null)
        'depends_on_mutation_id': dependsOnMutationId,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAtUtc != null) 'next_attempt_at_utc': nextAttemptAtUtc,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalOutboxCompanion copyWith({
    Value<String>? mutationId,
    Value<String>? accountId,
    Value<String>? aggregateType,
    Value<String>? aggregateId,
    Value<int>? sequence,
    Value<String>? status,
    Value<String>? createdAtUtc,
    Value<String>? payloadJson,
    Value<int?>? baseVersion,
    Value<int?>? clientSequence,
    Value<String?>? dependsOnMutationId,
    Value<int>? attemptCount,
    Value<String?>? nextAttemptAtUtc,
    Value<String?>? lastErrorCode,
    Value<int>? rowid,
  }) {
    return LocalOutboxCompanion(
      mutationId: mutationId ?? this.mutationId,
      accountId: accountId ?? this.accountId,
      aggregateType: aggregateType ?? this.aggregateType,
      aggregateId: aggregateId ?? this.aggregateId,
      sequence: sequence ?? this.sequence,
      status: status ?? this.status,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      payloadJson: payloadJson ?? this.payloadJson,
      baseVersion: baseVersion ?? this.baseVersion,
      clientSequence: clientSequence ?? this.clientSequence,
      dependsOnMutationId: dependsOnMutationId ?? this.dependsOnMutationId,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAtUtc: nextAttemptAtUtc ?? this.nextAttemptAtUtc,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (aggregateType.present) {
      map['aggregate_type'] = Variable<String>(aggregateType.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<String>(createdAtUtc.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (clientSequence.present) {
      map['client_sequence'] = Variable<int>(clientSequence.value);
    }
    if (dependsOnMutationId.present) {
      map['depends_on_mutation_id'] = Variable<String>(
        dependsOnMutationId.value,
      );
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAtUtc.present) {
      map['next_attempt_at_utc'] = Variable<String>(nextAttemptAtUtc.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalOutboxCompanion(')
          ..write('mutationId: $mutationId, ')
          ..write('accountId: $accountId, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('sequence: $sequence, ')
          ..write('status: $status, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('clientSequence: $clientSequence, ')
          ..write('dependsOnMutationId: $dependsOnMutationId, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAtUtc: $nextAttemptAtUtc, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSyncMetadataTable extends LocalSyncMetadata
    with TableInfo<$LocalSyncMetadataTable, LocalSyncMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSyncMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, valueJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sync_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSyncMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  LocalSyncMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSyncMetadataData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
    );
  }

  @override
  $LocalSyncMetadataTable createAlias(String alias) {
    return $LocalSyncMetadataTable(attachedDatabase, alias);
  }
}

class LocalSyncMetadataData extends DataClass
    implements Insertable<LocalSyncMetadataData> {
  final String key;
  final String valueJson;
  const LocalSyncMetadataData({required this.key, required this.valueJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    return map;
  }

  LocalSyncMetadataCompanion toCompanion(bool nullToAbsent) {
    return LocalSyncMetadataCompanion(
      key: Value(key),
      valueJson: Value(valueJson),
    );
  }

  factory LocalSyncMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSyncMetadataData(
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
    };
  }

  LocalSyncMetadataData copyWith({String? key, String? valueJson}) =>
      LocalSyncMetadataData(
        key: key ?? this.key,
        valueJson: valueJson ?? this.valueJson,
      );
  LocalSyncMetadataData copyWithCompanion(LocalSyncMetadataCompanion data) {
    return LocalSyncMetadataData(
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncMetadataData(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSyncMetadataData &&
          other.key == this.key &&
          other.valueJson == this.valueJson);
}

class LocalSyncMetadataCompanion
    extends UpdateCompanion<LocalSyncMetadataData> {
  final Value<String> key;
  final Value<String> valueJson;
  final Value<int> rowid;
  const LocalSyncMetadataCompanion({
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSyncMetadataCompanion.insert({
    required String key,
    required String valueJson,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       valueJson = Value(valueJson);
  static Insertable<LocalSyncMetadataData> custom({
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSyncMetadataCompanion copyWith({
    Value<String>? key,
    Value<String>? valueJson,
    Value<int>? rowid,
  }) {
    return LocalSyncMetadataCompanion(
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncMetadataCompanion(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalConflictsTable extends LocalConflicts
    with TableInfo<$LocalConflictsTable, LocalConflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conflictIdMeta = const VerificationMeta(
    'conflictId',
  );
  @override
  late final GeneratedColumn<String> conflictId = GeneratedColumn<String>(
    'conflict_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateTypeMeta = const VerificationMeta(
    'aggregateType',
  );
  @override
  late final GeneratedColumn<String> aggregateType = GeneratedColumn<String>(
    'aggregate_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<String> createdAtUtc = GeneratedColumn<String>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailJsonMeta = const VerificationMeta(
    'detailJson',
  );
  @override
  late final GeneratedColumn<String> detailJson = GeneratedColumn<String>(
    'detail_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    conflictId,
    aggregateType,
    aggregateId,
    createdAtUtc,
    code,
    detailJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalConflict> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conflict_id')) {
      context.handle(
        _conflictIdMeta,
        conflictId.isAcceptableOrUnknown(data['conflict_id']!, _conflictIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conflictIdMeta);
    }
    if (data.containsKey('aggregate_type')) {
      context.handle(
        _aggregateTypeMeta,
        aggregateType.isAcceptableOrUnknown(
          data['aggregate_type']!,
          _aggregateTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateTypeMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateIdMeta);
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('detail_json')) {
      context.handle(
        _detailJsonMeta,
        detailJson.isAcceptableOrUnknown(data['detail_json']!, _detailJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_detailJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conflictId};
  @override
  LocalConflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalConflict(
      conflictId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_id'],
      )!,
      aggregateType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_type'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at_utc'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      detailJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail_json'],
      )!,
    );
  }

  @override
  $LocalConflictsTable createAlias(String alias) {
    return $LocalConflictsTable(attachedDatabase, alias);
  }
}

class LocalConflict extends DataClass implements Insertable<LocalConflict> {
  final String conflictId;
  final String aggregateType;
  final String aggregateId;
  final String createdAtUtc;
  final String code;
  final String detailJson;
  const LocalConflict({
    required this.conflictId,
    required this.aggregateType,
    required this.aggregateId,
    required this.createdAtUtc,
    required this.code,
    required this.detailJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conflict_id'] = Variable<String>(conflictId);
    map['aggregate_type'] = Variable<String>(aggregateType);
    map['aggregate_id'] = Variable<String>(aggregateId);
    map['created_at_utc'] = Variable<String>(createdAtUtc);
    map['code'] = Variable<String>(code);
    map['detail_json'] = Variable<String>(detailJson);
    return map;
  }

  LocalConflictsCompanion toCompanion(bool nullToAbsent) {
    return LocalConflictsCompanion(
      conflictId: Value(conflictId),
      aggregateType: Value(aggregateType),
      aggregateId: Value(aggregateId),
      createdAtUtc: Value(createdAtUtc),
      code: Value(code),
      detailJson: Value(detailJson),
    );
  }

  factory LocalConflict.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalConflict(
      conflictId: serializer.fromJson<String>(json['conflictId']),
      aggregateType: serializer.fromJson<String>(json['aggregateType']),
      aggregateId: serializer.fromJson<String>(json['aggregateId']),
      createdAtUtc: serializer.fromJson<String>(json['createdAtUtc']),
      code: serializer.fromJson<String>(json['code']),
      detailJson: serializer.fromJson<String>(json['detailJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conflictId': serializer.toJson<String>(conflictId),
      'aggregateType': serializer.toJson<String>(aggregateType),
      'aggregateId': serializer.toJson<String>(aggregateId),
      'createdAtUtc': serializer.toJson<String>(createdAtUtc),
      'code': serializer.toJson<String>(code),
      'detailJson': serializer.toJson<String>(detailJson),
    };
  }

  LocalConflict copyWith({
    String? conflictId,
    String? aggregateType,
    String? aggregateId,
    String? createdAtUtc,
    String? code,
    String? detailJson,
  }) => LocalConflict(
    conflictId: conflictId ?? this.conflictId,
    aggregateType: aggregateType ?? this.aggregateType,
    aggregateId: aggregateId ?? this.aggregateId,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    code: code ?? this.code,
    detailJson: detailJson ?? this.detailJson,
  );
  LocalConflict copyWithCompanion(LocalConflictsCompanion data) {
    return LocalConflict(
      conflictId: data.conflictId.present
          ? data.conflictId.value
          : this.conflictId,
      aggregateType: data.aggregateType.present
          ? data.aggregateType.value
          : this.aggregateType,
      aggregateId: data.aggregateId.present
          ? data.aggregateId.value
          : this.aggregateId,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      code: data.code.present ? data.code.value : this.code,
      detailJson: data.detailJson.present
          ? data.detailJson.value
          : this.detailJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalConflict(')
          ..write('conflictId: $conflictId, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('code: $code, ')
          ..write('detailJson: $detailJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    conflictId,
    aggregateType,
    aggregateId,
    createdAtUtc,
    code,
    detailJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalConflict &&
          other.conflictId == this.conflictId &&
          other.aggregateType == this.aggregateType &&
          other.aggregateId == this.aggregateId &&
          other.createdAtUtc == this.createdAtUtc &&
          other.code == this.code &&
          other.detailJson == this.detailJson);
}

class LocalConflictsCompanion extends UpdateCompanion<LocalConflict> {
  final Value<String> conflictId;
  final Value<String> aggregateType;
  final Value<String> aggregateId;
  final Value<String> createdAtUtc;
  final Value<String> code;
  final Value<String> detailJson;
  final Value<int> rowid;
  const LocalConflictsCompanion({
    this.conflictId = const Value.absent(),
    this.aggregateType = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.code = const Value.absent(),
    this.detailJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalConflictsCompanion.insert({
    required String conflictId,
    required String aggregateType,
    required String aggregateId,
    required String createdAtUtc,
    required String code,
    required String detailJson,
    this.rowid = const Value.absent(),
  }) : conflictId = Value(conflictId),
       aggregateType = Value(aggregateType),
       aggregateId = Value(aggregateId),
       createdAtUtc = Value(createdAtUtc),
       code = Value(code),
       detailJson = Value(detailJson);
  static Insertable<LocalConflict> custom({
    Expression<String>? conflictId,
    Expression<String>? aggregateType,
    Expression<String>? aggregateId,
    Expression<String>? createdAtUtc,
    Expression<String>? code,
    Expression<String>? detailJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conflictId != null) 'conflict_id': conflictId,
      if (aggregateType != null) 'aggregate_type': aggregateType,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (code != null) 'code': code,
      if (detailJson != null) 'detail_json': detailJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalConflictsCompanion copyWith({
    Value<String>? conflictId,
    Value<String>? aggregateType,
    Value<String>? aggregateId,
    Value<String>? createdAtUtc,
    Value<String>? code,
    Value<String>? detailJson,
    Value<int>? rowid,
  }) {
    return LocalConflictsCompanion(
      conflictId: conflictId ?? this.conflictId,
      aggregateType: aggregateType ?? this.aggregateType,
      aggregateId: aggregateId ?? this.aggregateId,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      code: code ?? this.code,
      detailJson: detailJson ?? this.detailJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conflictId.present) {
      map['conflict_id'] = Variable<String>(conflictId.value);
    }
    if (aggregateType.present) {
      map['aggregate_type'] = Variable<String>(aggregateType.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<String>(createdAtUtc.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (detailJson.present) {
      map['detail_json'] = Variable<String>(detailJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalConflictsCompanion(')
          ..write('conflictId: $conflictId, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('code: $code, ')
          ..write('detailJson: $detailJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTombstonesTable extends LocalTombstones
    with TableInfo<$LocalTombstonesTable, LocalTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _resourceTypeMeta = const VerificationMeta(
    'resourceType',
  );
  @override
  late final GeneratedColumn<String> resourceType = GeneratedColumn<String>(
    'resource_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resourceIdMeta = const VerificationMeta(
    'resourceId',
  );
  @override
  late final GeneratedColumn<String> resourceId = GeneratedColumn<String>(
    'resource_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [resourceType, resourceId, revision];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTombstone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('resource_type')) {
      context.handle(
        _resourceTypeMeta,
        resourceType.isAcceptableOrUnknown(
          data['resource_type']!,
          _resourceTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resourceTypeMeta);
    }
    if (data.containsKey('resource_id')) {
      context.handle(
        _resourceIdMeta,
        resourceId.isAcceptableOrUnknown(data['resource_id']!, _resourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_resourceIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {resourceType, resourceId};
  @override
  LocalTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTombstone(
      resourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_type'],
      )!,
      resourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $LocalTombstonesTable createAlias(String alias) {
    return $LocalTombstonesTable(attachedDatabase, alias);
  }
}

class LocalTombstone extends DataClass implements Insertable<LocalTombstone> {
  final String resourceType;
  final String resourceId;
  final int revision;
  const LocalTombstone({
    required this.resourceType,
    required this.resourceId,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['resource_type'] = Variable<String>(resourceType);
    map['resource_id'] = Variable<String>(resourceId);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  LocalTombstonesCompanion toCompanion(bool nullToAbsent) {
    return LocalTombstonesCompanion(
      resourceType: Value(resourceType),
      resourceId: Value(resourceId),
      revision: Value(revision),
    );
  }

  factory LocalTombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTombstone(
      resourceType: serializer.fromJson<String>(json['resourceType']),
      resourceId: serializer.fromJson<String>(json['resourceId']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'resourceType': serializer.toJson<String>(resourceType),
      'resourceId': serializer.toJson<String>(resourceId),
      'revision': serializer.toJson<int>(revision),
    };
  }

  LocalTombstone copyWith({
    String? resourceType,
    String? resourceId,
    int? revision,
  }) => LocalTombstone(
    resourceType: resourceType ?? this.resourceType,
    resourceId: resourceId ?? this.resourceId,
    revision: revision ?? this.revision,
  );
  LocalTombstone copyWithCompanion(LocalTombstonesCompanion data) {
    return LocalTombstone(
      resourceType: data.resourceType.present
          ? data.resourceType.value
          : this.resourceType,
      resourceId: data.resourceId.present
          ? data.resourceId.value
          : this.resourceId,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTombstone(')
          ..write('resourceType: $resourceType, ')
          ..write('resourceId: $resourceId, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(resourceType, resourceId, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTombstone &&
          other.resourceType == this.resourceType &&
          other.resourceId == this.resourceId &&
          other.revision == this.revision);
}

class LocalTombstonesCompanion extends UpdateCompanion<LocalTombstone> {
  final Value<String> resourceType;
  final Value<String> resourceId;
  final Value<int> revision;
  final Value<int> rowid;
  const LocalTombstonesCompanion({
    this.resourceType = const Value.absent(),
    this.resourceId = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTombstonesCompanion.insert({
    required String resourceType,
    required String resourceId,
    required int revision,
    this.rowid = const Value.absent(),
  }) : resourceType = Value(resourceType),
       resourceId = Value(resourceId),
       revision = Value(revision);
  static Insertable<LocalTombstone> custom({
    Expression<String>? resourceType,
    Expression<String>? resourceId,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (resourceType != null) 'resource_type': resourceType,
      if (resourceId != null) 'resource_id': resourceId,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTombstonesCompanion copyWith({
    Value<String>? resourceType,
    Value<String>? resourceId,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return LocalTombstonesCompanion(
      resourceType: resourceType ?? this.resourceType,
      resourceId: resourceId ?? this.resourceId,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (resourceType.present) {
      map['resource_type'] = Variable<String>(resourceType.value);
    }
    if (resourceId.present) {
      map['resource_id'] = Variable<String>(resourceId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTombstonesCompanion(')
          ..write('resourceType: $resourceType, ')
          ..write('resourceId: $resourceId, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InstallationMetadataTable extends InstallationMetadata
    with TableInfo<$InstallationMetadataTable, InstallationMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstallationMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'installation_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstallationMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  InstallationMetadataData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstallationMetadataData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $InstallationMetadataTable createAlias(String alias) {
    return $InstallationMetadataTable(attachedDatabase, alias);
  }
}

class InstallationMetadataData extends DataClass
    implements Insertable<InstallationMetadataData> {
  final String key;
  final String value;
  const InstallationMetadataData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  InstallationMetadataCompanion toCompanion(bool nullToAbsent) {
    return InstallationMetadataCompanion(key: Value(key), value: Value(value));
  }

  factory InstallationMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstallationMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  InstallationMetadataData copyWith({String? key, String? value}) =>
      InstallationMetadataData(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  InstallationMetadataData copyWithCompanion(
    InstallationMetadataCompanion data,
  ) {
    return InstallationMetadataData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstallationMetadataData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstallationMetadataData &&
          other.key == this.key &&
          other.value == this.value);
}

class InstallationMetadataCompanion
    extends UpdateCompanion<InstallationMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const InstallationMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstallationMetadataCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<InstallationMetadataData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstallationMetadataCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return InstallationMetadataCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstallationMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $LocalResourcesTable localResources = $LocalResourcesTable(this);
  late final $LocalOutboxTable localOutbox = $LocalOutboxTable(this);
  late final $LocalSyncMetadataTable localSyncMetadata =
      $LocalSyncMetadataTable(this);
  late final $LocalConflictsTable localConflicts = $LocalConflictsTable(this);
  late final $LocalTombstonesTable localTombstones = $LocalTombstonesTable(
    this,
  );
  late final $InstallationMetadataTable installationMetadata =
      $InstallationMetadataTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localResources,
    localOutbox,
    localSyncMetadata,
    localConflicts,
    localTombstones,
    installationMetadata,
  ];
}

typedef $$LocalResourcesTableCreateCompanionBuilder =
    LocalResourcesCompanion Function({
      required String aggregateType,
      required String aggregateId,
      required String envelopeJson,
      required int updatedAtEpochMs,
      Value<int> rowid,
    });
typedef $$LocalResourcesTableUpdateCompanionBuilder =
    LocalResourcesCompanion Function({
      Value<String> aggregateType,
      Value<String> aggregateId,
      Value<String> envelopeJson,
      Value<int> updatedAtEpochMs,
      Value<int> rowid,
    });

class $$LocalResourcesTableFilterComposer
    extends Composer<_$LocalDatabase, $LocalResourcesTable> {
  $$LocalResourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get envelopeJson => $composableBuilder(
    column: $table.envelopeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtEpochMs => $composableBuilder(
    column: $table.updatedAtEpochMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalResourcesTableOrderingComposer
    extends Composer<_$LocalDatabase, $LocalResourcesTable> {
  $$LocalResourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get envelopeJson => $composableBuilder(
    column: $table.envelopeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtEpochMs => $composableBuilder(
    column: $table.updatedAtEpochMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalResourcesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $LocalResourcesTable> {
  $$LocalResourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get envelopeJson => $composableBuilder(
    column: $table.envelopeJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtEpochMs => $composableBuilder(
    column: $table.updatedAtEpochMs,
    builder: (column) => column,
  );
}

class $$LocalResourcesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $LocalResourcesTable,
          LocalResource,
          $$LocalResourcesTableFilterComposer,
          $$LocalResourcesTableOrderingComposer,
          $$LocalResourcesTableAnnotationComposer,
          $$LocalResourcesTableCreateCompanionBuilder,
          $$LocalResourcesTableUpdateCompanionBuilder,
          (
            LocalResource,
            BaseReferences<
              _$LocalDatabase,
              $LocalResourcesTable,
              LocalResource
            >,
          ),
          LocalResource,
          PrefetchHooks Function()
        > {
  $$LocalResourcesTableTableManager(
    _$LocalDatabase db,
    $LocalResourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalResourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalResourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalResourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> aggregateType = const Value.absent(),
                Value<String> aggregateId = const Value.absent(),
                Value<String> envelopeJson = const Value.absent(),
                Value<int> updatedAtEpochMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalResourcesCompanion(
                aggregateType: aggregateType,
                aggregateId: aggregateId,
                envelopeJson: envelopeJson,
                updatedAtEpochMs: updatedAtEpochMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String aggregateType,
                required String aggregateId,
                required String envelopeJson,
                required int updatedAtEpochMs,
                Value<int> rowid = const Value.absent(),
              }) => LocalResourcesCompanion.insert(
                aggregateType: aggregateType,
                aggregateId: aggregateId,
                envelopeJson: envelopeJson,
                updatedAtEpochMs: updatedAtEpochMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalResourcesTable, LocalResource>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $LocalResourcesTable,
                    LocalResource
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalResourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $LocalResourcesTable,
      LocalResource,
      $$LocalResourcesTableFilterComposer,
      $$LocalResourcesTableOrderingComposer,
      $$LocalResourcesTableAnnotationComposer,
      $$LocalResourcesTableCreateCompanionBuilder,
      $$LocalResourcesTableUpdateCompanionBuilder,
      (
        LocalResource,
        BaseReferences<_$LocalDatabase, $LocalResourcesTable, LocalResource>,
      ),
      LocalResource,
      PrefetchHooks Function()
    >;
typedef $$LocalOutboxTableCreateCompanionBuilder =
    LocalOutboxCompanion Function({
      required String mutationId,
      required String accountId,
      required String aggregateType,
      required String aggregateId,
      required int sequence,
      required String status,
      required String createdAtUtc,
      required String payloadJson,
      Value<int?> baseVersion,
      Value<int?> clientSequence,
      Value<String?> dependsOnMutationId,
      Value<int> attemptCount,
      Value<String?> nextAttemptAtUtc,
      Value<String?> lastErrorCode,
      Value<int> rowid,
    });
typedef $$LocalOutboxTableUpdateCompanionBuilder =
    LocalOutboxCompanion Function({
      Value<String> mutationId,
      Value<String> accountId,
      Value<String> aggregateType,
      Value<String> aggregateId,
      Value<int> sequence,
      Value<String> status,
      Value<String> createdAtUtc,
      Value<String> payloadJson,
      Value<int?> baseVersion,
      Value<int?> clientSequence,
      Value<String?> dependsOnMutationId,
      Value<int> attemptCount,
      Value<String?> nextAttemptAtUtc,
      Value<String?> lastErrorCode,
      Value<int> rowid,
    });

class $$LocalOutboxTableFilterComposer
    extends Composer<_$LocalDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clientSequence => $composableBuilder(
    column: $table.clientSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dependsOnMutationId => $composableBuilder(
    column: $table.dependsOnMutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextAttemptAtUtc => $composableBuilder(
    column: $table.nextAttemptAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalOutboxTableOrderingComposer
    extends Composer<_$LocalDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clientSequence => $composableBuilder(
    column: $table.clientSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dependsOnMutationId => $composableBuilder(
    column: $table.dependsOnMutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextAttemptAtUtc => $composableBuilder(
    column: $table.nextAttemptAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalOutboxTableAnnotationComposer
    extends Composer<_$LocalDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get clientSequence => $composableBuilder(
    column: $table.clientSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dependsOnMutationId => $composableBuilder(
    column: $table.dependsOnMutationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextAttemptAtUtc => $composableBuilder(
    column: $table.nextAttemptAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );
}

class $$LocalOutboxTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $LocalOutboxTable,
          LocalOutboxData,
          $$LocalOutboxTableFilterComposer,
          $$LocalOutboxTableOrderingComposer,
          $$LocalOutboxTableAnnotationComposer,
          $$LocalOutboxTableCreateCompanionBuilder,
          $$LocalOutboxTableUpdateCompanionBuilder,
          (
            LocalOutboxData,
            BaseReferences<_$LocalDatabase, $LocalOutboxTable, LocalOutboxData>,
          ),
          LocalOutboxData,
          PrefetchHooks Function()
        > {
  $$LocalOutboxTableTableManager(_$LocalDatabase db, $LocalOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mutationId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> aggregateType = const Value.absent(),
                Value<String> aggregateId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> createdAtUtc = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int?> baseVersion = const Value.absent(),
                Value<int?> clientSequence = const Value.absent(),
                Value<String?> dependsOnMutationId = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> nextAttemptAtUtc = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalOutboxCompanion(
                mutationId: mutationId,
                accountId: accountId,
                aggregateType: aggregateType,
                aggregateId: aggregateId,
                sequence: sequence,
                status: status,
                createdAtUtc: createdAtUtc,
                payloadJson: payloadJson,
                baseVersion: baseVersion,
                clientSequence: clientSequence,
                dependsOnMutationId: dependsOnMutationId,
                attemptCount: attemptCount,
                nextAttemptAtUtc: nextAttemptAtUtc,
                lastErrorCode: lastErrorCode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mutationId,
                required String accountId,
                required String aggregateType,
                required String aggregateId,
                required int sequence,
                required String status,
                required String createdAtUtc,
                required String payloadJson,
                Value<int?> baseVersion = const Value.absent(),
                Value<int?> clientSequence = const Value.absent(),
                Value<String?> dependsOnMutationId = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> nextAttemptAtUtc = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalOutboxCompanion.insert(
                mutationId: mutationId,
                accountId: accountId,
                aggregateType: aggregateType,
                aggregateId: aggregateId,
                sequence: sequence,
                status: status,
                createdAtUtc: createdAtUtc,
                payloadJson: payloadJson,
                baseVersion: baseVersion,
                clientSequence: clientSequence,
                dependsOnMutationId: dependsOnMutationId,
                attemptCount: attemptCount,
                nextAttemptAtUtc: nextAttemptAtUtc,
                lastErrorCode: lastErrorCode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalOutboxTable, LocalOutboxData>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $LocalOutboxTable,
                    LocalOutboxData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $LocalOutboxTable,
      LocalOutboxData,
      $$LocalOutboxTableFilterComposer,
      $$LocalOutboxTableOrderingComposer,
      $$LocalOutboxTableAnnotationComposer,
      $$LocalOutboxTableCreateCompanionBuilder,
      $$LocalOutboxTableUpdateCompanionBuilder,
      (
        LocalOutboxData,
        BaseReferences<_$LocalDatabase, $LocalOutboxTable, LocalOutboxData>,
      ),
      LocalOutboxData,
      PrefetchHooks Function()
    >;
typedef $$LocalSyncMetadataTableCreateCompanionBuilder =
    LocalSyncMetadataCompanion Function({
      required String key,
      required String valueJson,
      Value<int> rowid,
    });
typedef $$LocalSyncMetadataTableUpdateCompanionBuilder =
    LocalSyncMetadataCompanion Function({
      Value<String> key,
      Value<String> valueJson,
      Value<int> rowid,
    });

class $$LocalSyncMetadataTableFilterComposer
    extends Composer<_$LocalDatabase, $LocalSyncMetadataTable> {
  $$LocalSyncMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSyncMetadataTableOrderingComposer
    extends Composer<_$LocalDatabase, $LocalSyncMetadataTable> {
  $$LocalSyncMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSyncMetadataTableAnnotationComposer
    extends Composer<_$LocalDatabase, $LocalSyncMetadataTable> {
  $$LocalSyncMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);
}

class $$LocalSyncMetadataTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $LocalSyncMetadataTable,
          LocalSyncMetadataData,
          $$LocalSyncMetadataTableFilterComposer,
          $$LocalSyncMetadataTableOrderingComposer,
          $$LocalSyncMetadataTableAnnotationComposer,
          $$LocalSyncMetadataTableCreateCompanionBuilder,
          $$LocalSyncMetadataTableUpdateCompanionBuilder,
          (
            LocalSyncMetadataData,
            BaseReferences<
              _$LocalDatabase,
              $LocalSyncMetadataTable,
              LocalSyncMetadataData
            >,
          ),
          LocalSyncMetadataData,
          PrefetchHooks Function()
        > {
  $$LocalSyncMetadataTableTableManager(
    _$LocalDatabase db,
    $LocalSyncMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSyncMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSyncMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSyncMetadataTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncMetadataCompanion(
                key: key,
                valueJson: valueJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String valueJson,
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncMetadataCompanion.insert(
                key: key,
                valueJson: valueJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalSyncMetadataTable, LocalSyncMetadataData>(
                    table,
                  ),
                  BaseReferences<
                    _$LocalDatabase,
                    $LocalSyncMetadataTable,
                    LocalSyncMetadataData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSyncMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $LocalSyncMetadataTable,
      LocalSyncMetadataData,
      $$LocalSyncMetadataTableFilterComposer,
      $$LocalSyncMetadataTableOrderingComposer,
      $$LocalSyncMetadataTableAnnotationComposer,
      $$LocalSyncMetadataTableCreateCompanionBuilder,
      $$LocalSyncMetadataTableUpdateCompanionBuilder,
      (
        LocalSyncMetadataData,
        BaseReferences<
          _$LocalDatabase,
          $LocalSyncMetadataTable,
          LocalSyncMetadataData
        >,
      ),
      LocalSyncMetadataData,
      PrefetchHooks Function()
    >;
typedef $$LocalConflictsTableCreateCompanionBuilder =
    LocalConflictsCompanion Function({
      required String conflictId,
      required String aggregateType,
      required String aggregateId,
      required String createdAtUtc,
      required String code,
      required String detailJson,
      Value<int> rowid,
    });
typedef $$LocalConflictsTableUpdateCompanionBuilder =
    LocalConflictsCompanion Function({
      Value<String> conflictId,
      Value<String> aggregateType,
      Value<String> aggregateId,
      Value<String> createdAtUtc,
      Value<String> code,
      Value<String> detailJson,
      Value<int> rowid,
    });

class $$LocalConflictsTableFilterComposer
    extends Composer<_$LocalDatabase, $LocalConflictsTable> {
  $$LocalConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalConflictsTableOrderingComposer
    extends Composer<_$LocalDatabase, $LocalConflictsTable> {
  $$LocalConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalConflictsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $LocalConflictsTable> {
  $$LocalConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => column,
  );
}

class $$LocalConflictsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $LocalConflictsTable,
          LocalConflict,
          $$LocalConflictsTableFilterComposer,
          $$LocalConflictsTableOrderingComposer,
          $$LocalConflictsTableAnnotationComposer,
          $$LocalConflictsTableCreateCompanionBuilder,
          $$LocalConflictsTableUpdateCompanionBuilder,
          (
            LocalConflict,
            BaseReferences<
              _$LocalDatabase,
              $LocalConflictsTable,
              LocalConflict
            >,
          ),
          LocalConflict,
          PrefetchHooks Function()
        > {
  $$LocalConflictsTableTableManager(
    _$LocalDatabase db,
    $LocalConflictsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> conflictId = const Value.absent(),
                Value<String> aggregateType = const Value.absent(),
                Value<String> aggregateId = const Value.absent(),
                Value<String> createdAtUtc = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> detailJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalConflictsCompanion(
                conflictId: conflictId,
                aggregateType: aggregateType,
                aggregateId: aggregateId,
                createdAtUtc: createdAtUtc,
                code: code,
                detailJson: detailJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conflictId,
                required String aggregateType,
                required String aggregateId,
                required String createdAtUtc,
                required String code,
                required String detailJson,
                Value<int> rowid = const Value.absent(),
              }) => LocalConflictsCompanion.insert(
                conflictId: conflictId,
                aggregateType: aggregateType,
                aggregateId: aggregateId,
                createdAtUtc: createdAtUtc,
                code: code,
                detailJson: detailJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalConflictsTable, LocalConflict>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $LocalConflictsTable,
                    LocalConflict
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalConflictsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $LocalConflictsTable,
      LocalConflict,
      $$LocalConflictsTableFilterComposer,
      $$LocalConflictsTableOrderingComposer,
      $$LocalConflictsTableAnnotationComposer,
      $$LocalConflictsTableCreateCompanionBuilder,
      $$LocalConflictsTableUpdateCompanionBuilder,
      (
        LocalConflict,
        BaseReferences<_$LocalDatabase, $LocalConflictsTable, LocalConflict>,
      ),
      LocalConflict,
      PrefetchHooks Function()
    >;
typedef $$LocalTombstonesTableCreateCompanionBuilder =
    LocalTombstonesCompanion Function({
      required String resourceType,
      required String resourceId,
      required int revision,
      Value<int> rowid,
    });
typedef $$LocalTombstonesTableUpdateCompanionBuilder =
    LocalTombstonesCompanion Function({
      Value<String> resourceType,
      Value<String> resourceId,
      Value<int> revision,
      Value<int> rowid,
    });

class $$LocalTombstonesTableFilterComposer
    extends Composer<_$LocalDatabase, $LocalTombstonesTable> {
  $$LocalTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get resourceType => $composableBuilder(
    column: $table.resourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTombstonesTableOrderingComposer
    extends Composer<_$LocalDatabase, $LocalTombstonesTable> {
  $$LocalTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get resourceType => $composableBuilder(
    column: $table.resourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTombstonesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $LocalTombstonesTable> {
  $$LocalTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get resourceType => $composableBuilder(
    column: $table.resourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$LocalTombstonesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $LocalTombstonesTable,
          LocalTombstone,
          $$LocalTombstonesTableFilterComposer,
          $$LocalTombstonesTableOrderingComposer,
          $$LocalTombstonesTableAnnotationComposer,
          $$LocalTombstonesTableCreateCompanionBuilder,
          $$LocalTombstonesTableUpdateCompanionBuilder,
          (
            LocalTombstone,
            BaseReferences<
              _$LocalDatabase,
              $LocalTombstonesTable,
              LocalTombstone
            >,
          ),
          LocalTombstone,
          PrefetchHooks Function()
        > {
  $$LocalTombstonesTableTableManager(
    _$LocalDatabase db,
    $LocalTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> resourceType = const Value.absent(),
                Value<String> resourceId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTombstonesCompanion(
                resourceType: resourceType,
                resourceId: resourceId,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String resourceType,
                required String resourceId,
                required int revision,
                Value<int> rowid = const Value.absent(),
              }) => LocalTombstonesCompanion.insert(
                resourceType: resourceType,
                resourceId: resourceId,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalTombstonesTable, LocalTombstone>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $LocalTombstonesTable,
                    LocalTombstone
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $LocalTombstonesTable,
      LocalTombstone,
      $$LocalTombstonesTableFilterComposer,
      $$LocalTombstonesTableOrderingComposer,
      $$LocalTombstonesTableAnnotationComposer,
      $$LocalTombstonesTableCreateCompanionBuilder,
      $$LocalTombstonesTableUpdateCompanionBuilder,
      (
        LocalTombstone,
        BaseReferences<_$LocalDatabase, $LocalTombstonesTable, LocalTombstone>,
      ),
      LocalTombstone,
      PrefetchHooks Function()
    >;
typedef $$InstallationMetadataTableCreateCompanionBuilder =
    InstallationMetadataCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$InstallationMetadataTableUpdateCompanionBuilder =
    InstallationMetadataCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$InstallationMetadataTableFilterComposer
    extends Composer<_$LocalDatabase, $InstallationMetadataTable> {
  $$InstallationMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InstallationMetadataTableOrderingComposer
    extends Composer<_$LocalDatabase, $InstallationMetadataTable> {
  $$InstallationMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstallationMetadataTableAnnotationComposer
    extends Composer<_$LocalDatabase, $InstallationMetadataTable> {
  $$InstallationMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$InstallationMetadataTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $InstallationMetadataTable,
          InstallationMetadataData,
          $$InstallationMetadataTableFilterComposer,
          $$InstallationMetadataTableOrderingComposer,
          $$InstallationMetadataTableAnnotationComposer,
          $$InstallationMetadataTableCreateCompanionBuilder,
          $$InstallationMetadataTableUpdateCompanionBuilder,
          (
            InstallationMetadataData,
            BaseReferences<
              _$LocalDatabase,
              $InstallationMetadataTable,
              InstallationMetadataData
            >,
          ),
          InstallationMetadataData,
          PrefetchHooks Function()
        > {
  $$InstallationMetadataTableTableManager(
    _$LocalDatabase db,
    $InstallationMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstallationMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstallationMetadataTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$InstallationMetadataTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstallationMetadataCompanion(
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => InstallationMetadataCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $InstallationMetadataTable,
                    InstallationMetadataData
                  >(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $InstallationMetadataTable,
                    InstallationMetadataData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InstallationMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $InstallationMetadataTable,
      InstallationMetadataData,
      $$InstallationMetadataTableFilterComposer,
      $$InstallationMetadataTableOrderingComposer,
      $$InstallationMetadataTableAnnotationComposer,
      $$InstallationMetadataTableCreateCompanionBuilder,
      $$InstallationMetadataTableUpdateCompanionBuilder,
      (
        InstallationMetadataData,
        BaseReferences<
          _$LocalDatabase,
          $InstallationMetadataTable,
          InstallationMetadataData
        >,
      ),
      InstallationMetadataData,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$LocalResourcesTableTableManager get localResources =>
      $$LocalResourcesTableTableManager(_db, _db.localResources);
  $$LocalOutboxTableTableManager get localOutbox =>
      $$LocalOutboxTableTableManager(_db, _db.localOutbox);
  $$LocalSyncMetadataTableTableManager get localSyncMetadata =>
      $$LocalSyncMetadataTableTableManager(_db, _db.localSyncMetadata);
  $$LocalConflictsTableTableManager get localConflicts =>
      $$LocalConflictsTableTableManager(_db, _db.localConflicts);
  $$LocalTombstonesTableTableManager get localTombstones =>
      $$LocalTombstonesTableTableManager(_db, _db.localTombstones);
  $$InstallationMetadataTableTableManager get installationMetadata =>
      $$InstallationMetadataTableTableManager(_db, _db.installationMetadata);
}
