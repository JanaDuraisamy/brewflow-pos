// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ShopsTable extends Shops with TableInfo<$ShopsTable, Shop> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShopsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shops';
  @override
  VerificationContext validateIntegrity(
    Insertable<Shop> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Shop map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Shop(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ShopsTable createAlias(String alias) {
    return $ShopsTable(attachedDatabase, alias);
  }
}

class Shop extends DataClass implements Insertable<Shop> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business display name; informational until business identity settings
  /// are linked to the shop row.
  final String name;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const Shop({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ShopsCompanion toCompanion(bool nullToAbsent) {
    return ShopsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Shop.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Shop(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Shop copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Shop(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Shop copyWithCompanion(ShopsCompanion data) {
    return Shop(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Shop(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Shop &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ShopsCompanion extends UpdateCompanion<Shop> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ShopsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShopsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Shop> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShopsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ShopsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShopsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _authUserIdMeta = const VerificationMeta(
    'authUserId',
  );
  @override
  late final GeneratedColumn<String> authUserId = GeneratedColumn<String>(
    'auth_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id)',
    ),
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    email,
    authUserId,
    shopId,
    displayName,
    role,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('auth_user_id')) {
      context.handle(
        _authUserIdMeta,
        authUserId.isAcceptableOrUnknown(
          data['auth_user_id']!,
          _authUserIdMeta,
        ),
      );
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      authUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_user_id'],
      ),
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Unique login email; identity for auth linking.
  final String email;

  /// Supabase auth user id; unique when present. Null for legacy rows that
  /// predate the auth integration and were never linked.
  final String? authUserId;

  /// Owning shop ([Shops.id]); null only for legacy rows awaiting linkage.
  final String? shopId;

  /// Display name shown in the POS UI.
  final String? displayName;

  /// Access role: 'OWNER' or 'STAFF'. Null until a profile is provisioned.
  final String? role;

  /// Soft switch to block sign-in without deleting the record.
  final bool isActive;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const User({
    required this.id,
    required this.email,
    this.authUserId,
    this.shopId,
    this.displayName,
    this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['email'] = Variable<String>(email);
    if (!nullToAbsent || authUserId != null) {
      map['auth_user_id'] = Variable<String>(authUserId);
    }
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || role != null) {
      map['role'] = Variable<String>(role);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      email: Value(email),
      authUserId: authUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(authUserId),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      role: role == null && nullToAbsent ? const Value.absent() : Value(role),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      id: serializer.fromJson<String>(json['id']),
      email: serializer.fromJson<String>(json['email']),
      authUserId: serializer.fromJson<String?>(json['authUserId']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      role: serializer.fromJson<String?>(json['role']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'email': serializer.toJson<String>(email),
      'authUserId': serializer.toJson<String?>(authUserId),
      'shopId': serializer.toJson<String?>(shopId),
      'displayName': serializer.toJson<String?>(displayName),
      'role': serializer.toJson<String?>(role),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  User copyWith({
    String? id,
    String? email,
    Value<String?> authUserId = const Value.absent(),
    Value<String?> shopId = const Value.absent(),
    Value<String?> displayName = const Value.absent(),
    Value<String?> role = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => User(
    id: id ?? this.id,
    email: email ?? this.email,
    authUserId: authUserId.present ? authUserId.value : this.authUserId,
    shopId: shopId.present ? shopId.value : this.shopId,
    displayName: displayName.present ? displayName.value : this.displayName,
    role: role.present ? role.value : this.role,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      id: data.id.present ? data.id.value : this.id,
      email: data.email.present ? data.email.value : this.email,
      authUserId: data.authUserId.present
          ? data.authUserId.value
          : this.authUserId,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      role: data.role.present ? data.role.value : this.role,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('id: $id, ')
          ..write('email: $email, ')
          ..write('authUserId: $authUserId, ')
          ..write('shopId: $shopId, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    email,
    authUserId,
    shopId,
    displayName,
    role,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.id == this.id &&
          other.email == this.email &&
          other.authUserId == this.authUserId &&
          other.shopId == this.shopId &&
          other.displayName == this.displayName &&
          other.role == this.role &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<String> id;
  final Value<String> email;
  final Value<String?> authUserId;
  final Value<String?> shopId;
  final Value<String?> displayName;
  final Value<String?> role;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.email = const Value.absent(),
    this.authUserId = const Value.absent(),
    this.shopId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.role = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    this.id = const Value.absent(),
    required String email,
    this.authUserId = const Value.absent(),
    this.shopId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.role = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : email = Value(email);
  static Insertable<User> custom({
    Expression<String>? id,
    Expression<String>? email,
    Expression<String>? authUserId,
    Expression<String>? shopId,
    Expression<String>? displayName,
    Expression<String>? role,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (email != null) 'email': email,
      if (authUserId != null) 'auth_user_id': authUserId,
      if (shopId != null) 'shop_id': shopId,
      if (displayName != null) 'display_name': displayName,
      if (role != null) 'role': role,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? id,
    Value<String>? email,
    Value<String?>? authUserId,
    Value<String?>? shopId,
    Value<String?>? displayName,
    Value<String?>? role,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      id: id ?? this.id,
      email: email ?? this.email,
      authUserId: authUserId ?? this.authUserId,
      shopId: shopId ?? this.shopId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (authUserId.present) {
      map['auth_user_id'] = Variable<String>(authUserId.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('email: $email, ')
          ..write('authUserId: $authUserId, ')
          ..write('shopId: $shopId, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DevicesTable extends Devices with TableInfo<$DevicesTable, Device> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id)',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    userId,
    deviceName,
    platform,
    createdAt,
    lastSeenAt,
    isActive,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<Device> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Device map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Device(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      ),
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class Device extends DataClass implements Insertable<Device> {
  /// Local UUID v4 identifier — also used as the server device id.
  final String id;

  /// Owning shop ([Shops.id]).
  final String shopId;

  /// Supabase auth user id that registered this installation.
  final String userId;

  /// Optional human-friendly label (e.g. 'Counter tablet').
  final String? deviceName;

  /// Platform hint (e.g. 'android', 'windows'); informational.
  final String? platform;

  /// UTC timestamp of registration.
  final DateTime createdAt;

  /// UTC timestamp of the last heartbeat/registration refresh.
  final DateTime lastSeenAt;

  /// Soft switch so a shop can retire a lost device without deleting it.
  final bool isActive;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const Device({
    required this.id,
    required this.shopId,
    required this.userId,
    this.deviceName,
    this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    required this.isActive,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['shop_id'] = Variable<String>(shopId);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || deviceName != null) {
      map['device_name'] = Variable<String>(deviceName);
    }
    if (!nullToAbsent || platform != null) {
      map['platform'] = Variable<String>(platform);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    map['is_active'] = Variable<bool>(isActive);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      id: Value(id),
      shopId: Value(shopId),
      userId: Value(userId),
      deviceName: deviceName == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceName),
      platform: platform == null && nullToAbsent
          ? const Value.absent()
          : Value(platform),
      createdAt: Value(createdAt),
      lastSeenAt: Value(lastSeenAt),
      isActive: Value(isActive),
      updatedAt: Value(updatedAt),
    );
  }

  factory Device.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Device(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String>(json['shopId']),
      userId: serializer.fromJson<String>(json['userId']),
      deviceName: serializer.fromJson<String?>(json['deviceName']),
      platform: serializer.fromJson<String?>(json['platform']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String>(shopId),
      'userId': serializer.toJson<String>(userId),
      'deviceName': serializer.toJson<String?>(deviceName),
      'platform': serializer.toJson<String?>(platform),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
      'isActive': serializer.toJson<bool>(isActive),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Device copyWith({
    String? id,
    String? shopId,
    String? userId,
    Value<String?> deviceName = const Value.absent(),
    Value<String?> platform = const Value.absent(),
    DateTime? createdAt,
    DateTime? lastSeenAt,
    bool? isActive,
    DateTime? updatedAt,
  }) => Device(
    id: id ?? this.id,
    shopId: shopId ?? this.shopId,
    userId: userId ?? this.userId,
    deviceName: deviceName.present ? deviceName.value : this.deviceName,
    platform: platform.present ? platform.value : this.platform,
    createdAt: createdAt ?? this.createdAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    isActive: isActive ?? this.isActive,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Device copyWithCompanion(DevicesCompanion data) {
    return Device(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      userId: data.userId.present ? data.userId.value : this.userId,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      platform: data.platform.present ? data.platform.value : this.platform,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Device(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('userId: $userId, ')
          ..write('deviceName: $deviceName, ')
          ..write('platform: $platform, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('isActive: $isActive, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    userId,
    deviceName,
    platform,
    createdAt,
    lastSeenAt,
    isActive,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Device &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.userId == this.userId &&
          other.deviceName == this.deviceName &&
          other.platform == this.platform &&
          other.createdAt == this.createdAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.isActive == this.isActive &&
          other.updatedAt == this.updatedAt);
}

class DevicesCompanion extends UpdateCompanion<Device> {
  final Value<String> id;
  final Value<String> shopId;
  final Value<String> userId;
  final Value<String?> deviceName;
  final Value<String?> platform;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastSeenAt;
  final Value<bool> isActive;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DevicesCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.userId = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.platform = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    this.id = const Value.absent(),
    required String shopId,
    required String userId,
    this.deviceName = const Value.absent(),
    this.platform = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : shopId = Value(shopId),
       userId = Value(userId);
  static Insertable<Device> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? userId,
    Expression<String>? deviceName,
    Expression<String>? platform,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastSeenAt,
    Expression<bool>? isActive,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (userId != null) 'user_id': userId,
      if (deviceName != null) 'device_name': deviceName,
      if (platform != null) 'platform': platform,
      if (createdAt != null) 'created_at': createdAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (isActive != null) 'is_active': isActive,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? id,
    Value<String>? shopId,
    Value<String>? userId,
    Value<String?>? deviceName,
    Value<String?>? platform,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastSeenAt,
    Value<bool>? isActive,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      userId: userId ?? this.userId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('userId: $userId, ')
          ..write('deviceName: $deviceName, ')
          ..write('platform: $platform, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('isActive: $isActive, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('UPSERT'),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('PENDING'),
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
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    shopId,
    entity,
    entityId,
    operation,
    payload,
    status,
    attemptCount,
    lastAttemptAt,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
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
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxData extends DataClass implements Insertable<SyncOutboxData> {
  /// Local UUID v4 identifier.
  final String id;

  /// Installation that produced the change.
  final String deviceId;

  /// Shop scope of the change (isolation boundary for upload/apply).
  final String shopId;

  /// Entity type key, e.g. 'PRODUCT', 'SALE'.
  final String entity;

  /// Stable UUID of the changed row.
  final String entityId;

  /// Operation: 'UPSERT' or 'DELETE'.
  final String operation;

  /// JSON payload carrying the row snapshot required by the server apply.
  final String payload;

  /// PENDING → IN_FLIGHT → DONE / FAILED (FAILED keeps rows for inspection
  /// and manual retry; retry counters live here too).
  final String status;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final DateTime createdAt;
  const SyncOutboxData({
    required this.id,
    required this.deviceId,
    required this.shopId,
    required this.entity,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.status,
    required this.attemptCount,
    this.lastAttemptAt,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['shop_id'] = Variable<String>(shopId);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      shopId: Value(shopId),
      entity: Value(entity),
      entityId: Value(entityId),
      operation: Value(operation),
      payload: Value(payload),
      status: Value(status),
      attemptCount: Value(attemptCount),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory SyncOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxData(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      shopId: serializer.fromJson<String>(json['shopId']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'shopId': serializer.toJson<String>(shopId),
      'entity': serializer.toJson<String>(entity),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncOutboxData copyWith({
    String? id,
    String? deviceId,
    String? shopId,
    String? entity,
    String? entityId,
    String? operation,
    String? payload,
    String? status,
    int? attemptCount,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => SyncOutboxData(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    shopId: shopId ?? this.shopId,
    entity: entity ?? this.entity,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payload: payload ?? this.payload,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncOutboxData copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxData(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxData(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('shopId: $shopId, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deviceId,
    shopId,
    entity,
    entityId,
    operation,
    payload,
    status,
    attemptCount,
    lastAttemptAt,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxData &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.shopId == this.shopId &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxData> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<String> shopId;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payload;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SyncOutboxCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.shopId = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    required String shopId,
    required String entity,
    required String entityId,
    this.operation = const Value.absent(),
    required String payload,
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       shopId = Value(shopId),
       entity = Value(entity),
       entityId = Value(entityId),
       payload = Value(payload);
  static Insertable<SyncOutboxData> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<String>? shopId,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (shopId != null) 'shop_id': shopId,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<String>? id,
    Value<String>? deviceId,
    Value<String>? shopId,
    Value<String>? entity,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payload,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<DateTime?>? lastAttemptAt,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SyncOutboxCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      shopId: shopId ?? this.shopId,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('shopId: $shopId, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastPulledAtMeta = const VerificationMeta(
    'lastPulledAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPulledAt = GeneratedColumn<DateTime>(
    'last_pulled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPushedAtMeta = const VerificationMeta(
    'lastPushedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPushedAt = GeneratedColumn<DateTime>(
    'last_pushed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    shopId,
    lastPulledAt,
    lastPushedAt,
    lastError,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('last_pulled_at')) {
      context.handle(
        _lastPulledAtMeta,
        lastPulledAt.isAcceptableOrUnknown(
          data['last_pulled_at']!,
          _lastPulledAtMeta,
        ),
      );
    }
    if (data.containsKey('last_pushed_at')) {
      context.handle(
        _lastPushedAtMeta,
        lastPushedAt.isAcceptableOrUnknown(
          data['last_pushed_at']!,
          _lastPushedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      lastPulledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_pulled_at'],
      ),
      lastPushedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_pushed_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  /// Device installation this state belongs to ([Devices.id]).
  final String deviceId;

  /// Owning shop scope.
  final String shopId;

  /// Incremental pull cursor (max server updated_at applied).
  final DateTime? lastPulledAt;

  /// Last successful push drain.
  final DateTime? lastPushedAt;

  /// Last sync error message (diagnostics only; never shown as success).
  final String? lastError;
  final DateTime updatedAt;
  const SyncStateData({
    required this.deviceId,
    required this.shopId,
    this.lastPulledAt,
    this.lastPushedAt,
    this.lastError,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['shop_id'] = Variable<String>(shopId);
    if (!nullToAbsent || lastPulledAt != null) {
      map['last_pulled_at'] = Variable<DateTime>(lastPulledAt);
    }
    if (!nullToAbsent || lastPushedAt != null) {
      map['last_pushed_at'] = Variable<DateTime>(lastPushedAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      deviceId: Value(deviceId),
      shopId: Value(shopId),
      lastPulledAt: lastPulledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPulledAt),
      lastPushedAt: lastPushedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPushedAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      shopId: serializer.fromJson<String>(json['shopId']),
      lastPulledAt: serializer.fromJson<DateTime?>(json['lastPulledAt']),
      lastPushedAt: serializer.fromJson<DateTime?>(json['lastPushedAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'shopId': serializer.toJson<String>(shopId),
      'lastPulledAt': serializer.toJson<DateTime?>(lastPulledAt),
      'lastPushedAt': serializer.toJson<DateTime?>(lastPushedAt),
      'lastError': serializer.toJson<String?>(lastError),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncStateData copyWith({
    String? deviceId,
    String? shopId,
    Value<DateTime?> lastPulledAt = const Value.absent(),
    Value<DateTime?> lastPushedAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? updatedAt,
  }) => SyncStateData(
    deviceId: deviceId ?? this.deviceId,
    shopId: shopId ?? this.shopId,
    lastPulledAt: lastPulledAt.present ? lastPulledAt.value : this.lastPulledAt,
    lastPushedAt: lastPushedAt.present ? lastPushedAt.value : this.lastPushedAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      lastPulledAt: data.lastPulledAt.present
          ? data.lastPulledAt.value
          : this.lastPulledAt,
      lastPushedAt: data.lastPushedAt.present
          ? data.lastPushedAt.value
          : this.lastPushedAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('deviceId: $deviceId, ')
          ..write('shopId: $shopId, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('lastPushedAt: $lastPushedAt, ')
          ..write('lastError: $lastError, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    shopId,
    lastPulledAt,
    lastPushedAt,
    lastError,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.deviceId == this.deviceId &&
          other.shopId == this.shopId &&
          other.lastPulledAt == this.lastPulledAt &&
          other.lastPushedAt == this.lastPushedAt &&
          other.lastError == this.lastError &&
          other.updatedAt == this.updatedAt);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> deviceId;
  final Value<String> shopId;
  final Value<DateTime?> lastPulledAt;
  final Value<DateTime?> lastPushedAt;
  final Value<String?> lastError;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.deviceId = const Value.absent(),
    this.shopId = const Value.absent(),
    this.lastPulledAt = const Value.absent(),
    this.lastPushedAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String deviceId,
    required String shopId,
    this.lastPulledAt = const Value.absent(),
    this.lastPushedAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       shopId = Value(shopId);
  static Insertable<SyncStateData> custom({
    Expression<String>? deviceId,
    Expression<String>? shopId,
    Expression<DateTime>? lastPulledAt,
    Expression<DateTime>? lastPushedAt,
    Expression<String>? lastError,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (shopId != null) 'shop_id': shopId,
      if (lastPulledAt != null) 'last_pulled_at': lastPulledAt,
      if (lastPushedAt != null) 'last_pushed_at': lastPushedAt,
      if (lastError != null) 'last_error': lastError,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? shopId,
    Value<DateTime?>? lastPulledAt,
    Value<DateTime?>? lastPushedAt,
    Value<String?>? lastError,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      deviceId: deviceId ?? this.deviceId,
      shopId: shopId ?? this.shopId,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
      lastPushedAt: lastPushedAt ?? this.lastPushedAt,
      lastError: lastError ?? this.lastError,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (lastPulledAt.present) {
      map['last_pulled_at'] = Variable<DateTime>(lastPulledAt.value);
    }
    if (lastPushedAt.present) {
      map['last_pushed_at'] = Variable<DateTime>(lastPushedAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('shopId: $shopId, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('lastPushedAt: $lastPushedAt, ')
          ..write('lastError: $lastError, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StaffPermissionsTable extends StaffPermissions
    with TableInfo<$StaffPermissionsTable, StaffPermission> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StaffPermissionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _permissionMeta = const VerificationMeta(
    'permission',
  );
  @override
  late final GeneratedColumn<String> permission = GeneratedColumn<String>(
    'permission',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [userId, permission, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'staff_permissions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StaffPermission> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('permission')) {
      context.handle(
        _permissionMeta,
        permission.isAcceptableOrUnknown(data['permission']!, _permissionMeta),
      );
    } else if (isInserting) {
      context.missing(_permissionMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, permission};
  @override
  StaffPermission map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StaffPermission(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      permission: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}permission'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
    );
  }

  @override
  $StaffPermissionsTable createAlias(String alias) {
    return $StaffPermissionsTable(attachedDatabase, alias);
  }
}

class StaffPermission extends DataClass implements Insertable<StaffPermission> {
  /// Owning staff profile ([Users.id]).
  final String userId;

  /// Permission key, e.g. 'BILLING' (stable enum dbValue).
  final String permission;

  /// Whether the owner granted this capability.
  final bool enabled;
  const StaffPermission({
    required this.userId,
    required this.permission,
    required this.enabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['permission'] = Variable<String>(permission);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  StaffPermissionsCompanion toCompanion(bool nullToAbsent) {
    return StaffPermissionsCompanion(
      userId: Value(userId),
      permission: Value(permission),
      enabled: Value(enabled),
    );
  }

  factory StaffPermission.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StaffPermission(
      userId: serializer.fromJson<String>(json['userId']),
      permission: serializer.fromJson<String>(json['permission']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'permission': serializer.toJson<String>(permission),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  StaffPermission copyWith({
    String? userId,
    String? permission,
    bool? enabled,
  }) => StaffPermission(
    userId: userId ?? this.userId,
    permission: permission ?? this.permission,
    enabled: enabled ?? this.enabled,
  );
  StaffPermission copyWithCompanion(StaffPermissionsCompanion data) {
    return StaffPermission(
      userId: data.userId.present ? data.userId.value : this.userId,
      permission: data.permission.present
          ? data.permission.value
          : this.permission,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StaffPermission(')
          ..write('userId: $userId, ')
          ..write('permission: $permission, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, permission, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StaffPermission &&
          other.userId == this.userId &&
          other.permission == this.permission &&
          other.enabled == this.enabled);
}

class StaffPermissionsCompanion extends UpdateCompanion<StaffPermission> {
  final Value<String> userId;
  final Value<String> permission;
  final Value<bool> enabled;
  final Value<int> rowid;
  const StaffPermissionsCompanion({
    this.userId = const Value.absent(),
    this.permission = const Value.absent(),
    this.enabled = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StaffPermissionsCompanion.insert({
    required String userId,
    required String permission,
    this.enabled = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       permission = Value(permission);
  static Insertable<StaffPermission> custom({
    Expression<String>? userId,
    Expression<String>? permission,
    Expression<bool>? enabled,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (permission != null) 'permission': permission,
      if (enabled != null) 'enabled': enabled,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StaffPermissionsCompanion copyWith({
    Value<String>? userId,
    Value<String>? permission,
    Value<bool>? enabled,
    Value<int>? rowid,
  }) {
    return StaffPermissionsCompanion(
      userId: userId ?? this.userId,
      permission: permission ?? this.permission,
      enabled: enabled ?? this.enabled,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (permission.present) {
      map['permission'] = Variable<String>(permission.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StaffPermissionsCompanion(')
          ..write('userId: $userId, ')
          ..write('permission: $permission, ')
          ..write('enabled: $enabled, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    name,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {shopId, name},
  ];
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this category.
  final String? shopId;

  /// Category name. Unique per shop so each business's menu stays unambiguous.
  final String name;

  /// Soft switch to hide a category (and its products from new orders)
  /// without deleting data.
  final bool isActive;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const Category({
    required this.id,
    this.shopId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['name'] = Variable<String>(name);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      name: Value(name),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      name: serializer.fromJson<String>(json['name']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'name': serializer.toJson<String>(name),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Category copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? name,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Category(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    name: name ?? this.name,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      name: data.name.present ? data.name.value : this.name,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, shopId, name, isActive, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.name == this.name &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> name;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.name = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String name,
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? name,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (name != null) 'name': name,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? name,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sellingPricePaiseMeta = const VerificationMeta(
    'sellingPricePaise',
  );
  @override
  late final GeneratedColumn<int> sellingPricePaise = GeneratedColumn<int>(
    'selling_price_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (selling_price_paise >= 0)',
  );
  static const VerificationMeta _costPricePaiseMeta = const VerificationMeta(
    'costPricePaise',
  );
  @override
  late final GeneratedColumn<int> costPricePaise = GeneratedColumn<int>(
    'cost_price_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (cost_price_paise IS NULL OR cost_price_paise >= 0)',
  );
  static const VerificationMeta _stockQuantityMeta = const VerificationMeta(
    'stockQuantity',
  );
  @override
  late final GeneratedColumn<int> stockQuantity = GeneratedColumn<int>(
    'stock_quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _stockUnitMeta = const VerificationMeta(
    'stockUnit',
  );
  @override
  late final GeneratedColumn<String> stockUnit = GeneratedColumn<String>(
    'stock_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'COUNT\' CHECK (stock_unit IN (\'COUNT\', \'ML\', \'GRAM\', \'KG\', \'NONE\'))',
    defaultValue: const CustomExpression('\'COUNT\''),
  );
  static const VerificationMeta _lowStockModeMeta = const VerificationMeta(
    'lowStockMode',
  );
  @override
  late final GeneratedColumn<String> lowStockMode = GeneratedColumn<String>(
    'low_stock_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'USE_DEFAULT\' CHECK (low_stock_mode IN (\'USE_DEFAULT\', \'CUSTOM\', \'OFF\'))',
    defaultValue: const CustomExpression('\'USE_DEFAULT\''),
  );
  static const VerificationMeta _lowStockThresholdMeta = const VerificationMeta(
    'lowStockThreshold',
  );
  @override
  late final GeneratedColumn<int> lowStockThreshold = GeneratedColumn<int>(
    'low_stock_threshold',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (low_stock_threshold IS NULL OR low_stock_threshold >= 0)',
  );
  static const VerificationMeta _membershipEnabledMeta = const VerificationMeta(
    'membershipEnabled',
  );
  @override
  late final GeneratedColumn<bool> membershipEnabled = GeneratedColumn<bool>(
    'membership_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT 0 CHECK (membership_enabled IN (0, 1))',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _memberPricePaiseMeta = const VerificationMeta(
    'memberPricePaise',
  );
  @override
  late final GeneratedColumn<int> memberPricePaise = GeneratedColumn<int>(
    'member_price_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (member_price_paise IS NULL OR member_price_paise >= 0)',
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cloudImagePathMeta = const VerificationMeta(
    'cloudImagePath',
  );
  @override
  late final GeneratedColumn<String> cloudImagePath = GeneratedColumn<String>(
    'cloud_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    categoryId,
    name,
    sku,
    sellingPricePaise,
    costPricePaise,
    stockQuantity,
    stockUnit,
    lowStockMode,
    lowStockThreshold,
    membershipEnabled,
    memberPricePaise,
    imagePath,
    cloudImagePath,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<Product> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    }
    if (data.containsKey('selling_price_paise')) {
      context.handle(
        _sellingPricePaiseMeta,
        sellingPricePaise.isAcceptableOrUnknown(
          data['selling_price_paise']!,
          _sellingPricePaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sellingPricePaiseMeta);
    }
    if (data.containsKey('cost_price_paise')) {
      context.handle(
        _costPricePaiseMeta,
        costPricePaise.isAcceptableOrUnknown(
          data['cost_price_paise']!,
          _costPricePaiseMeta,
        ),
      );
    }
    if (data.containsKey('stock_quantity')) {
      context.handle(
        _stockQuantityMeta,
        stockQuantity.isAcceptableOrUnknown(
          data['stock_quantity']!,
          _stockQuantityMeta,
        ),
      );
    }
    if (data.containsKey('stock_unit')) {
      context.handle(
        _stockUnitMeta,
        stockUnit.isAcceptableOrUnknown(data['stock_unit']!, _stockUnitMeta),
      );
    }
    if (data.containsKey('low_stock_mode')) {
      context.handle(
        _lowStockModeMeta,
        lowStockMode.isAcceptableOrUnknown(
          data['low_stock_mode']!,
          _lowStockModeMeta,
        ),
      );
    }
    if (data.containsKey('low_stock_threshold')) {
      context.handle(
        _lowStockThresholdMeta,
        lowStockThreshold.isAcceptableOrUnknown(
          data['low_stock_threshold']!,
          _lowStockThresholdMeta,
        ),
      );
    }
    if (data.containsKey('membership_enabled')) {
      context.handle(
        _membershipEnabledMeta,
        membershipEnabled.isAcceptableOrUnknown(
          data['membership_enabled']!,
          _membershipEnabledMeta,
        ),
      );
    }
    if (data.containsKey('member_price_paise')) {
      context.handle(
        _memberPricePaiseMeta,
        memberPricePaise.isAcceptableOrUnknown(
          data['member_price_paise']!,
          _memberPricePaiseMeta,
        ),
      );
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('cloud_image_path')) {
      context.handle(
        _cloudImagePathMeta,
        cloudImagePath.isAcceptableOrUnknown(
          data['cloud_image_path']!,
          _cloudImagePathMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {shopId, sku},
  ];
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      ),
      sellingPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}selling_price_paise'],
      )!,
      costPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cost_price_paise'],
      ),
      stockQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stock_quantity'],
      )!,
      stockUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stock_unit'],
      )!,
      lowStockMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}low_stock_mode'],
      )!,
      lowStockThreshold: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}low_stock_threshold'],
      ),
      membershipEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}membership_enabled'],
      )!,
      memberPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_price_paise'],
      ),
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      cloudImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_image_path'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this product.
  final String? shopId;

  /// Owning category. Deleting a category with products is rejected
  /// (RESTRICT) to protect order and inventory history.
  final String categoryId;

  /// Product display name.
  final String name;

  /// Stock keeping unit / product code. Unique when present, scoped per shop.
  final String? sku;

  /// Selling price in paise. Must be >= 0.
  final int sellingPricePaise;

  /// Cost price in paise; NULL when unknown. Must be >= 0 when present.
  final int? costPricePaise;

  /// Current stock quantity. Must be >= 0. For products with variants, this
  /// mirrors the sum of variant stock and is derived by the repository — the
  /// variant rows are the source of truth.
  final int stockQuantity;

  /// The unit this product's stock is counted in.
  /// COUNT = plain units, ML / GRAM / KG = measured goods, NONE = no stock
  /// tracking (e.g. services, made-to-order).
  final String stockUnit;

  /// How low-stock is decided for this product:
  /// USE_DEFAULT = use the global threshold, CUSTOM = use
  /// [Products.lowStockThreshold], OFF = never flagged as low stock.
  final String lowStockMode;

  /// Per-product low-stock threshold; only meaningful when
  /// [Products.lowStockMode] is CUSTOM. Must be >= 0 when present.
  final int? lowStockThreshold;

  /// Whether a member pricing tier exists for this product. Must be >= 0 when
  /// enabled (enforced at the repository layer).
  final bool membershipEnabled;

  /// Member-tier selling price in paise; required when
  /// [Products.membershipEnabled] is true. Must be >= 0 when present.
  final int? memberPricePaise;

  /// Local path (relative to the app documents directory) of the product
  /// image; NULL when no image is set. Stored locally so images keep working
  /// offline.
  final String? imagePath;

  /// Cloud object path (Supabase Storage) of the product image; NULL when the
  /// image is only local or absent. Stored as a path/metadata reference so the
  /// device never holds raw bytes in the database — other devices pull the
  /// object from cloud storage and cache it locally under [Products.imagePath].
  final String? cloudImagePath;

  /// Soft switch to hide a product from the POS without deleting it.
  final bool isActive;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const Product({
    required this.id,
    this.shopId,
    required this.categoryId,
    required this.name,
    this.sku,
    required this.sellingPricePaise,
    this.costPricePaise,
    required this.stockQuantity,
    required this.stockUnit,
    required this.lowStockMode,
    this.lowStockThreshold,
    required this.membershipEnabled,
    this.memberPricePaise,
    this.imagePath,
    this.cloudImagePath,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['category_id'] = Variable<String>(categoryId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || sku != null) {
      map['sku'] = Variable<String>(sku);
    }
    map['selling_price_paise'] = Variable<int>(sellingPricePaise);
    if (!nullToAbsent || costPricePaise != null) {
      map['cost_price_paise'] = Variable<int>(costPricePaise);
    }
    map['stock_quantity'] = Variable<int>(stockQuantity);
    map['stock_unit'] = Variable<String>(stockUnit);
    map['low_stock_mode'] = Variable<String>(lowStockMode);
    if (!nullToAbsent || lowStockThreshold != null) {
      map['low_stock_threshold'] = Variable<int>(lowStockThreshold);
    }
    map['membership_enabled'] = Variable<bool>(membershipEnabled);
    if (!nullToAbsent || memberPricePaise != null) {
      map['member_price_paise'] = Variable<int>(memberPricePaise);
    }
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    if (!nullToAbsent || cloudImagePath != null) {
      map['cloud_image_path'] = Variable<String>(cloudImagePath);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      categoryId: Value(categoryId),
      name: Value(name),
      sku: sku == null && nullToAbsent ? const Value.absent() : Value(sku),
      sellingPricePaise: Value(sellingPricePaise),
      costPricePaise: costPricePaise == null && nullToAbsent
          ? const Value.absent()
          : Value(costPricePaise),
      stockQuantity: Value(stockQuantity),
      stockUnit: Value(stockUnit),
      lowStockMode: Value(lowStockMode),
      lowStockThreshold: lowStockThreshold == null && nullToAbsent
          ? const Value.absent()
          : Value(lowStockThreshold),
      membershipEnabled: Value(membershipEnabled),
      memberPricePaise: memberPricePaise == null && nullToAbsent
          ? const Value.absent()
          : Value(memberPricePaise),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      cloudImagePath: cloudImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudImagePath),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Product.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      name: serializer.fromJson<String>(json['name']),
      sku: serializer.fromJson<String?>(json['sku']),
      sellingPricePaise: serializer.fromJson<int>(json['sellingPricePaise']),
      costPricePaise: serializer.fromJson<int?>(json['costPricePaise']),
      stockQuantity: serializer.fromJson<int>(json['stockQuantity']),
      stockUnit: serializer.fromJson<String>(json['stockUnit']),
      lowStockMode: serializer.fromJson<String>(json['lowStockMode']),
      lowStockThreshold: serializer.fromJson<int?>(json['lowStockThreshold']),
      membershipEnabled: serializer.fromJson<bool>(json['membershipEnabled']),
      memberPricePaise: serializer.fromJson<int?>(json['memberPricePaise']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      cloudImagePath: serializer.fromJson<String?>(json['cloudImagePath']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'categoryId': serializer.toJson<String>(categoryId),
      'name': serializer.toJson<String>(name),
      'sku': serializer.toJson<String?>(sku),
      'sellingPricePaise': serializer.toJson<int>(sellingPricePaise),
      'costPricePaise': serializer.toJson<int?>(costPricePaise),
      'stockQuantity': serializer.toJson<int>(stockQuantity),
      'stockUnit': serializer.toJson<String>(stockUnit),
      'lowStockMode': serializer.toJson<String>(lowStockMode),
      'lowStockThreshold': serializer.toJson<int?>(lowStockThreshold),
      'membershipEnabled': serializer.toJson<bool>(membershipEnabled),
      'memberPricePaise': serializer.toJson<int?>(memberPricePaise),
      'imagePath': serializer.toJson<String?>(imagePath),
      'cloudImagePath': serializer.toJson<String?>(cloudImagePath),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Product copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? categoryId,
    String? name,
    Value<String?> sku = const Value.absent(),
    int? sellingPricePaise,
    Value<int?> costPricePaise = const Value.absent(),
    int? stockQuantity,
    String? stockUnit,
    String? lowStockMode,
    Value<int?> lowStockThreshold = const Value.absent(),
    bool? membershipEnabled,
    Value<int?> memberPricePaise = const Value.absent(),
    Value<String?> imagePath = const Value.absent(),
    Value<String?> cloudImagePath = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Product(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    categoryId: categoryId ?? this.categoryId,
    name: name ?? this.name,
    sku: sku.present ? sku.value : this.sku,
    sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
    costPricePaise: costPricePaise.present
        ? costPricePaise.value
        : this.costPricePaise,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    stockUnit: stockUnit ?? this.stockUnit,
    lowStockMode: lowStockMode ?? this.lowStockMode,
    lowStockThreshold: lowStockThreshold.present
        ? lowStockThreshold.value
        : this.lowStockThreshold,
    membershipEnabled: membershipEnabled ?? this.membershipEnabled,
    memberPricePaise: memberPricePaise.present
        ? memberPricePaise.value
        : this.memberPricePaise,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    cloudImagePath: cloudImagePath.present
        ? cloudImagePath.value
        : this.cloudImagePath,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      name: data.name.present ? data.name.value : this.name,
      sku: data.sku.present ? data.sku.value : this.sku,
      sellingPricePaise: data.sellingPricePaise.present
          ? data.sellingPricePaise.value
          : this.sellingPricePaise,
      costPricePaise: data.costPricePaise.present
          ? data.costPricePaise.value
          : this.costPricePaise,
      stockQuantity: data.stockQuantity.present
          ? data.stockQuantity.value
          : this.stockQuantity,
      stockUnit: data.stockUnit.present ? data.stockUnit.value : this.stockUnit,
      lowStockMode: data.lowStockMode.present
          ? data.lowStockMode.value
          : this.lowStockMode,
      lowStockThreshold: data.lowStockThreshold.present
          ? data.lowStockThreshold.value
          : this.lowStockThreshold,
      membershipEnabled: data.membershipEnabled.present
          ? data.membershipEnabled.value
          : this.membershipEnabled,
      memberPricePaise: data.memberPricePaise.present
          ? data.memberPricePaise.value
          : this.memberPricePaise,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      cloudImagePath: data.cloudImagePath.present
          ? data.cloudImagePath.value
          : this.cloudImagePath,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('sku: $sku, ')
          ..write('sellingPricePaise: $sellingPricePaise, ')
          ..write('costPricePaise: $costPricePaise, ')
          ..write('stockQuantity: $stockQuantity, ')
          ..write('stockUnit: $stockUnit, ')
          ..write('lowStockMode: $lowStockMode, ')
          ..write('lowStockThreshold: $lowStockThreshold, ')
          ..write('membershipEnabled: $membershipEnabled, ')
          ..write('memberPricePaise: $memberPricePaise, ')
          ..write('imagePath: $imagePath, ')
          ..write('cloudImagePath: $cloudImagePath, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    categoryId,
    name,
    sku,
    sellingPricePaise,
    costPricePaise,
    stockQuantity,
    stockUnit,
    lowStockMode,
    lowStockThreshold,
    membershipEnabled,
    memberPricePaise,
    imagePath,
    cloudImagePath,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.categoryId == this.categoryId &&
          other.name == this.name &&
          other.sku == this.sku &&
          other.sellingPricePaise == this.sellingPricePaise &&
          other.costPricePaise == this.costPricePaise &&
          other.stockQuantity == this.stockQuantity &&
          other.stockUnit == this.stockUnit &&
          other.lowStockMode == this.lowStockMode &&
          other.lowStockThreshold == this.lowStockThreshold &&
          other.membershipEnabled == this.membershipEnabled &&
          other.memberPricePaise == this.memberPricePaise &&
          other.imagePath == this.imagePath &&
          other.cloudImagePath == this.cloudImagePath &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> categoryId;
  final Value<String> name;
  final Value<String?> sku;
  final Value<int> sellingPricePaise;
  final Value<int?> costPricePaise;
  final Value<int> stockQuantity;
  final Value<String> stockUnit;
  final Value<String> lowStockMode;
  final Value<int?> lowStockThreshold;
  final Value<bool> membershipEnabled;
  final Value<int?> memberPricePaise;
  final Value<String?> imagePath;
  final Value<String?> cloudImagePath;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.name = const Value.absent(),
    this.sku = const Value.absent(),
    this.sellingPricePaise = const Value.absent(),
    this.costPricePaise = const Value.absent(),
    this.stockQuantity = const Value.absent(),
    this.stockUnit = const Value.absent(),
    this.lowStockMode = const Value.absent(),
    this.lowStockThreshold = const Value.absent(),
    this.membershipEnabled = const Value.absent(),
    this.memberPricePaise = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.cloudImagePath = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String categoryId,
    required String name,
    this.sku = const Value.absent(),
    required int sellingPricePaise,
    this.costPricePaise = const Value.absent(),
    this.stockQuantity = const Value.absent(),
    this.stockUnit = const Value.absent(),
    this.lowStockMode = const Value.absent(),
    this.lowStockThreshold = const Value.absent(),
    this.membershipEnabled = const Value.absent(),
    this.memberPricePaise = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.cloudImagePath = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : categoryId = Value(categoryId),
       name = Value(name),
       sellingPricePaise = Value(sellingPricePaise);
  static Insertable<Product> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? categoryId,
    Expression<String>? name,
    Expression<String>? sku,
    Expression<int>? sellingPricePaise,
    Expression<int>? costPricePaise,
    Expression<int>? stockQuantity,
    Expression<String>? stockUnit,
    Expression<String>? lowStockMode,
    Expression<int>? lowStockThreshold,
    Expression<bool>? membershipEnabled,
    Expression<int>? memberPricePaise,
    Expression<String>? imagePath,
    Expression<String>? cloudImagePath,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (categoryId != null) 'category_id': categoryId,
      if (name != null) 'name': name,
      if (sku != null) 'sku': sku,
      if (sellingPricePaise != null) 'selling_price_paise': sellingPricePaise,
      if (costPricePaise != null) 'cost_price_paise': costPricePaise,
      if (stockQuantity != null) 'stock_quantity': stockQuantity,
      if (stockUnit != null) 'stock_unit': stockUnit,
      if (lowStockMode != null) 'low_stock_mode': lowStockMode,
      if (lowStockThreshold != null) 'low_stock_threshold': lowStockThreshold,
      if (membershipEnabled != null) 'membership_enabled': membershipEnabled,
      if (memberPricePaise != null) 'member_price_paise': memberPricePaise,
      if (imagePath != null) 'image_path': imagePath,
      if (cloudImagePath != null) 'cloud_image_path': cloudImagePath,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? categoryId,
    Value<String>? name,
    Value<String?>? sku,
    Value<int>? sellingPricePaise,
    Value<int?>? costPricePaise,
    Value<int>? stockQuantity,
    Value<String>? stockUnit,
    Value<String>? lowStockMode,
    Value<int?>? lowStockThreshold,
    Value<bool>? membershipEnabled,
    Value<int?>? memberPricePaise,
    Value<String?>? imagePath,
    Value<String?>? cloudImagePath,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
      costPricePaise: costPricePaise ?? this.costPricePaise,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      stockUnit: stockUnit ?? this.stockUnit,
      lowStockMode: lowStockMode ?? this.lowStockMode,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      membershipEnabled: membershipEnabled ?? this.membershipEnabled,
      memberPricePaise: memberPricePaise ?? this.memberPricePaise,
      imagePath: imagePath ?? this.imagePath,
      cloudImagePath: cloudImagePath ?? this.cloudImagePath,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (sellingPricePaise.present) {
      map['selling_price_paise'] = Variable<int>(sellingPricePaise.value);
    }
    if (costPricePaise.present) {
      map['cost_price_paise'] = Variable<int>(costPricePaise.value);
    }
    if (stockQuantity.present) {
      map['stock_quantity'] = Variable<int>(stockQuantity.value);
    }
    if (stockUnit.present) {
      map['stock_unit'] = Variable<String>(stockUnit.value);
    }
    if (lowStockMode.present) {
      map['low_stock_mode'] = Variable<String>(lowStockMode.value);
    }
    if (lowStockThreshold.present) {
      map['low_stock_threshold'] = Variable<int>(lowStockThreshold.value);
    }
    if (membershipEnabled.present) {
      map['membership_enabled'] = Variable<bool>(membershipEnabled.value);
    }
    if (memberPricePaise.present) {
      map['member_price_paise'] = Variable<int>(memberPricePaise.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (cloudImagePath.present) {
      map['cloud_image_path'] = Variable<String>(cloudImagePath.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('sku: $sku, ')
          ..write('sellingPricePaise: $sellingPricePaise, ')
          ..write('costPricePaise: $costPricePaise, ')
          ..write('stockQuantity: $stockQuantity, ')
          ..write('stockUnit: $stockUnit, ')
          ..write('lowStockMode: $lowStockMode, ')
          ..write('lowStockThreshold: $lowStockThreshold, ')
          ..write('membershipEnabled: $membershipEnabled, ')
          ..write('memberPricePaise: $memberPricePaise, ')
          ..write('imagePath: $imagePath, ')
          ..write('cloudImagePath: $cloudImagePath, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductVariantsTable extends ProductVariants
    with TableInfo<$ProductVariantsTable, ProductVariant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductVariantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES products (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sellingPricePaiseMeta = const VerificationMeta(
    'sellingPricePaise',
  );
  @override
  late final GeneratedColumn<int> sellingPricePaise = GeneratedColumn<int>(
    'selling_price_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (selling_price_paise >= 0)',
  );
  static const VerificationMeta _costPricePaiseMeta = const VerificationMeta(
    'costPricePaise',
  );
  @override
  late final GeneratedColumn<int> costPricePaise = GeneratedColumn<int>(
    'cost_price_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (cost_price_paise IS NULL OR cost_price_paise >= 0)',
  );
  static const VerificationMeta _stockQuantityMeta = const VerificationMeta(
    'stockQuantity',
  );
  @override
  late final GeneratedColumn<int> stockQuantity = GeneratedColumn<int>(
    'stock_quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _lowStockModeMeta = const VerificationMeta(
    'lowStockMode',
  );
  @override
  late final GeneratedColumn<String> lowStockMode = GeneratedColumn<String>(
    'low_stock_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'USE_DEFAULT\' CHECK (low_stock_mode IN (\'USE_DEFAULT\', \'CUSTOM\', \'OFF\'))',
    defaultValue: const CustomExpression('\'USE_DEFAULT\''),
  );
  static const VerificationMeta _lowStockThresholdMeta = const VerificationMeta(
    'lowStockThreshold',
  );
  @override
  late final GeneratedColumn<int> lowStockThreshold = GeneratedColumn<int>(
    'low_stock_threshold',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (low_stock_threshold IS NULL OR low_stock_threshold >= 0)',
  );
  static const VerificationMeta _membershipEnabledMeta = const VerificationMeta(
    'membershipEnabled',
  );
  @override
  late final GeneratedColumn<bool> membershipEnabled = GeneratedColumn<bool>(
    'membership_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT 0 CHECK (membership_enabled IN (0, 1))',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _memberPricePaiseMeta = const VerificationMeta(
    'memberPricePaise',
  );
  @override
  late final GeneratedColumn<int> memberPricePaise = GeneratedColumn<int>(
    'member_price_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (member_price_paise IS NULL OR member_price_paise >= 0)',
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    productId,
    name,
    sku,
    sellingPricePaise,
    costPricePaise,
    stockQuantity,
    lowStockMode,
    lowStockThreshold,
    membershipEnabled,
    memberPricePaise,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_variants';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductVariant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    }
    if (data.containsKey('selling_price_paise')) {
      context.handle(
        _sellingPricePaiseMeta,
        sellingPricePaise.isAcceptableOrUnknown(
          data['selling_price_paise']!,
          _sellingPricePaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sellingPricePaiseMeta);
    }
    if (data.containsKey('cost_price_paise')) {
      context.handle(
        _costPricePaiseMeta,
        costPricePaise.isAcceptableOrUnknown(
          data['cost_price_paise']!,
          _costPricePaiseMeta,
        ),
      );
    }
    if (data.containsKey('stock_quantity')) {
      context.handle(
        _stockQuantityMeta,
        stockQuantity.isAcceptableOrUnknown(
          data['stock_quantity']!,
          _stockQuantityMeta,
        ),
      );
    }
    if (data.containsKey('low_stock_mode')) {
      context.handle(
        _lowStockModeMeta,
        lowStockMode.isAcceptableOrUnknown(
          data['low_stock_mode']!,
          _lowStockModeMeta,
        ),
      );
    }
    if (data.containsKey('low_stock_threshold')) {
      context.handle(
        _lowStockThresholdMeta,
        lowStockThreshold.isAcceptableOrUnknown(
          data['low_stock_threshold']!,
          _lowStockThresholdMeta,
        ),
      );
    }
    if (data.containsKey('membership_enabled')) {
      context.handle(
        _membershipEnabledMeta,
        membershipEnabled.isAcceptableOrUnknown(
          data['membership_enabled']!,
          _membershipEnabledMeta,
        ),
      );
    }
    if (data.containsKey('member_price_paise')) {
      context.handle(
        _memberPricePaiseMeta,
        memberPricePaise.isAcceptableOrUnknown(
          data['member_price_paise']!,
          _memberPricePaiseMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {shopId, sku},
  ];
  @override
  ProductVariant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductVariant(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      ),
      sellingPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}selling_price_paise'],
      )!,
      costPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cost_price_paise'],
      ),
      stockQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stock_quantity'],
      )!,
      lowStockMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}low_stock_mode'],
      )!,
      lowStockThreshold: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}low_stock_threshold'],
      ),
      membershipEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}membership_enabled'],
      )!,
      memberPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_price_paise'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProductVariantsTable createAlias(String alias) {
    return $ProductVariantsTable(attachedDatabase, alias);
  }
}

class ProductVariant extends DataClass implements Insertable<ProductVariant> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this product variant.
  final String? shopId;

  /// Owning product. Products are never hard-deleted (soft deactivation
  /// instead); RESTRICT keeps variant history bound to its owner.
  final String productId;

  /// Variant display name, e.g. '250 ml'.
  final String name;

  /// Variant stock keeping unit / code. Unique when present, scoped per shop.
  final String? sku;

  /// Selling price in paise. Must be >= 0.
  final int sellingPricePaise;

  /// Cost price in paise; NULL when unknown. Must be >= 0 when present.
  final int? costPricePaise;

  /// Current variant stock quantity. Must be >= 0.
  final int stockQuantity;

  /// How low-stock is decided for this variant:
  /// USE_DEFAULT = fall back to the parent product's policy (and then the
  /// global threshold), CUSTOM = use [ProductVariants.lowStockThreshold],
  /// OFF = never flagged as low stock.
  final String lowStockMode;

  /// Per-variant low-stock threshold; only meaningful when
  /// [ProductVariants.lowStockMode] is CUSTOM. Must be >= 0 when present.
  final int? lowStockThreshold;

  /// Whether a member pricing tier exists for this variant.
  final bool membershipEnabled;

  /// Member-tier selling price in paise; required when
  /// [ProductVariants.membershipEnabled] is true.
  final int? memberPricePaise;

  /// Soft switch to hide a variant from the POS without deleting it.
  final bool isActive;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const ProductVariant({
    required this.id,
    this.shopId,
    required this.productId,
    required this.name,
    this.sku,
    required this.sellingPricePaise,
    this.costPricePaise,
    required this.stockQuantity,
    required this.lowStockMode,
    this.lowStockThreshold,
    required this.membershipEnabled,
    this.memberPricePaise,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['product_id'] = Variable<String>(productId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || sku != null) {
      map['sku'] = Variable<String>(sku);
    }
    map['selling_price_paise'] = Variable<int>(sellingPricePaise);
    if (!nullToAbsent || costPricePaise != null) {
      map['cost_price_paise'] = Variable<int>(costPricePaise);
    }
    map['stock_quantity'] = Variable<int>(stockQuantity);
    map['low_stock_mode'] = Variable<String>(lowStockMode);
    if (!nullToAbsent || lowStockThreshold != null) {
      map['low_stock_threshold'] = Variable<int>(lowStockThreshold);
    }
    map['membership_enabled'] = Variable<bool>(membershipEnabled);
    if (!nullToAbsent || memberPricePaise != null) {
      map['member_price_paise'] = Variable<int>(memberPricePaise);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductVariantsCompanion toCompanion(bool nullToAbsent) {
    return ProductVariantsCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      productId: Value(productId),
      name: Value(name),
      sku: sku == null && nullToAbsent ? const Value.absent() : Value(sku),
      sellingPricePaise: Value(sellingPricePaise),
      costPricePaise: costPricePaise == null && nullToAbsent
          ? const Value.absent()
          : Value(costPricePaise),
      stockQuantity: Value(stockQuantity),
      lowStockMode: Value(lowStockMode),
      lowStockThreshold: lowStockThreshold == null && nullToAbsent
          ? const Value.absent()
          : Value(lowStockThreshold),
      membershipEnabled: Value(membershipEnabled),
      memberPricePaise: memberPricePaise == null && nullToAbsent
          ? const Value.absent()
          : Value(memberPricePaise),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProductVariant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductVariant(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      productId: serializer.fromJson<String>(json['productId']),
      name: serializer.fromJson<String>(json['name']),
      sku: serializer.fromJson<String?>(json['sku']),
      sellingPricePaise: serializer.fromJson<int>(json['sellingPricePaise']),
      costPricePaise: serializer.fromJson<int?>(json['costPricePaise']),
      stockQuantity: serializer.fromJson<int>(json['stockQuantity']),
      lowStockMode: serializer.fromJson<String>(json['lowStockMode']),
      lowStockThreshold: serializer.fromJson<int?>(json['lowStockThreshold']),
      membershipEnabled: serializer.fromJson<bool>(json['membershipEnabled']),
      memberPricePaise: serializer.fromJson<int?>(json['memberPricePaise']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'productId': serializer.toJson<String>(productId),
      'name': serializer.toJson<String>(name),
      'sku': serializer.toJson<String?>(sku),
      'sellingPricePaise': serializer.toJson<int>(sellingPricePaise),
      'costPricePaise': serializer.toJson<int?>(costPricePaise),
      'stockQuantity': serializer.toJson<int>(stockQuantity),
      'lowStockMode': serializer.toJson<String>(lowStockMode),
      'lowStockThreshold': serializer.toJson<int?>(lowStockThreshold),
      'membershipEnabled': serializer.toJson<bool>(membershipEnabled),
      'memberPricePaise': serializer.toJson<int?>(memberPricePaise),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProductVariant copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? productId,
    String? name,
    Value<String?> sku = const Value.absent(),
    int? sellingPricePaise,
    Value<int?> costPricePaise = const Value.absent(),
    int? stockQuantity,
    String? lowStockMode,
    Value<int?> lowStockThreshold = const Value.absent(),
    bool? membershipEnabled,
    Value<int?> memberPricePaise = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProductVariant(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    productId: productId ?? this.productId,
    name: name ?? this.name,
    sku: sku.present ? sku.value : this.sku,
    sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
    costPricePaise: costPricePaise.present
        ? costPricePaise.value
        : this.costPricePaise,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    lowStockMode: lowStockMode ?? this.lowStockMode,
    lowStockThreshold: lowStockThreshold.present
        ? lowStockThreshold.value
        : this.lowStockThreshold,
    membershipEnabled: membershipEnabled ?? this.membershipEnabled,
    memberPricePaise: memberPricePaise.present
        ? memberPricePaise.value
        : this.memberPricePaise,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProductVariant copyWithCompanion(ProductVariantsCompanion data) {
    return ProductVariant(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      productId: data.productId.present ? data.productId.value : this.productId,
      name: data.name.present ? data.name.value : this.name,
      sku: data.sku.present ? data.sku.value : this.sku,
      sellingPricePaise: data.sellingPricePaise.present
          ? data.sellingPricePaise.value
          : this.sellingPricePaise,
      costPricePaise: data.costPricePaise.present
          ? data.costPricePaise.value
          : this.costPricePaise,
      stockQuantity: data.stockQuantity.present
          ? data.stockQuantity.value
          : this.stockQuantity,
      lowStockMode: data.lowStockMode.present
          ? data.lowStockMode.value
          : this.lowStockMode,
      lowStockThreshold: data.lowStockThreshold.present
          ? data.lowStockThreshold.value
          : this.lowStockThreshold,
      membershipEnabled: data.membershipEnabled.present
          ? data.membershipEnabled.value
          : this.membershipEnabled,
      memberPricePaise: data.memberPricePaise.present
          ? data.memberPricePaise.value
          : this.memberPricePaise,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductVariant(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('productId: $productId, ')
          ..write('name: $name, ')
          ..write('sku: $sku, ')
          ..write('sellingPricePaise: $sellingPricePaise, ')
          ..write('costPricePaise: $costPricePaise, ')
          ..write('stockQuantity: $stockQuantity, ')
          ..write('lowStockMode: $lowStockMode, ')
          ..write('lowStockThreshold: $lowStockThreshold, ')
          ..write('membershipEnabled: $membershipEnabled, ')
          ..write('memberPricePaise: $memberPricePaise, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    productId,
    name,
    sku,
    sellingPricePaise,
    costPricePaise,
    stockQuantity,
    lowStockMode,
    lowStockThreshold,
    membershipEnabled,
    memberPricePaise,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductVariant &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.productId == this.productId &&
          other.name == this.name &&
          other.sku == this.sku &&
          other.sellingPricePaise == this.sellingPricePaise &&
          other.costPricePaise == this.costPricePaise &&
          other.stockQuantity == this.stockQuantity &&
          other.lowStockMode == this.lowStockMode &&
          other.lowStockThreshold == this.lowStockThreshold &&
          other.membershipEnabled == this.membershipEnabled &&
          other.memberPricePaise == this.memberPricePaise &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductVariantsCompanion extends UpdateCompanion<ProductVariant> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> productId;
  final Value<String> name;
  final Value<String?> sku;
  final Value<int> sellingPricePaise;
  final Value<int?> costPricePaise;
  final Value<int> stockQuantity;
  final Value<String> lowStockMode;
  final Value<int?> lowStockThreshold;
  final Value<bool> membershipEnabled;
  final Value<int?> memberPricePaise;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProductVariantsCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.productId = const Value.absent(),
    this.name = const Value.absent(),
    this.sku = const Value.absent(),
    this.sellingPricePaise = const Value.absent(),
    this.costPricePaise = const Value.absent(),
    this.stockQuantity = const Value.absent(),
    this.lowStockMode = const Value.absent(),
    this.lowStockThreshold = const Value.absent(),
    this.membershipEnabled = const Value.absent(),
    this.memberPricePaise = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductVariantsCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String productId,
    required String name,
    this.sku = const Value.absent(),
    required int sellingPricePaise,
    this.costPricePaise = const Value.absent(),
    this.stockQuantity = const Value.absent(),
    this.lowStockMode = const Value.absent(),
    this.lowStockThreshold = const Value.absent(),
    this.membershipEnabled = const Value.absent(),
    this.memberPricePaise = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : productId = Value(productId),
       name = Value(name),
       sellingPricePaise = Value(sellingPricePaise);
  static Insertable<ProductVariant> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? productId,
    Expression<String>? name,
    Expression<String>? sku,
    Expression<int>? sellingPricePaise,
    Expression<int>? costPricePaise,
    Expression<int>? stockQuantity,
    Expression<String>? lowStockMode,
    Expression<int>? lowStockThreshold,
    Expression<bool>? membershipEnabled,
    Expression<int>? memberPricePaise,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (productId != null) 'product_id': productId,
      if (name != null) 'name': name,
      if (sku != null) 'sku': sku,
      if (sellingPricePaise != null) 'selling_price_paise': sellingPricePaise,
      if (costPricePaise != null) 'cost_price_paise': costPricePaise,
      if (stockQuantity != null) 'stock_quantity': stockQuantity,
      if (lowStockMode != null) 'low_stock_mode': lowStockMode,
      if (lowStockThreshold != null) 'low_stock_threshold': lowStockThreshold,
      if (membershipEnabled != null) 'membership_enabled': membershipEnabled,
      if (memberPricePaise != null) 'member_price_paise': memberPricePaise,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductVariantsCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? productId,
    Value<String>? name,
    Value<String?>? sku,
    Value<int>? sellingPricePaise,
    Value<int?>? costPricePaise,
    Value<int>? stockQuantity,
    Value<String>? lowStockMode,
    Value<int?>? lowStockThreshold,
    Value<bool>? membershipEnabled,
    Value<int?>? memberPricePaise,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProductVariantsCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
      costPricePaise: costPricePaise ?? this.costPricePaise,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      lowStockMode: lowStockMode ?? this.lowStockMode,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      membershipEnabled: membershipEnabled ?? this.membershipEnabled,
      memberPricePaise: memberPricePaise ?? this.memberPricePaise,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (sellingPricePaise.present) {
      map['selling_price_paise'] = Variable<int>(sellingPricePaise.value);
    }
    if (costPricePaise.present) {
      map['cost_price_paise'] = Variable<int>(costPricePaise.value);
    }
    if (stockQuantity.present) {
      map['stock_quantity'] = Variable<int>(stockQuantity.value);
    }
    if (lowStockMode.present) {
      map['low_stock_mode'] = Variable<String>(lowStockMode.value);
    }
    if (lowStockThreshold.present) {
      map['low_stock_threshold'] = Variable<int>(lowStockThreshold.value);
    }
    if (membershipEnabled.present) {
      map['membership_enabled'] = Variable<bool>(membershipEnabled.value);
    }
    if (memberPricePaise.present) {
      map['member_price_paise'] = Variable<int>(memberPricePaise.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductVariantsCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('productId: $productId, ')
          ..write('name: $name, ')
          ..write('sku: $sku, ')
          ..write('sellingPricePaise: $sellingPricePaise, ')
          ..write('costPricePaise: $costPricePaise, ')
          ..write('stockQuantity: $stockQuantity, ')
          ..write('lowStockMode: $lowStockMode, ')
          ..write('lowStockThreshold: $lowStockThreshold, ')
          ..write('membershipEnabled: $membershipEnabled, ')
          ..write('memberPricePaise: $memberPricePaise, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomersTable extends Customers
    with TableInfo<$CustomersTable, Customer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _membershipActiveMeta = const VerificationMeta(
    'membershipActive',
  );
  @override
  late final GeneratedColumn<bool> membershipActive = GeneratedColumn<bool>(
    'membership_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("membership_active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _membershipFeePaiseMeta =
      const VerificationMeta('membershipFeePaise');
  @override
  late final GeneratedColumn<int> membershipFeePaise = GeneratedColumn<int>(
    'membership_fee_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _whatsappStatusMeta = const VerificationMeta(
    'whatsappStatus',
  );
  @override
  late final GeneratedColumn<String> whatsappStatus = GeneratedColumn<String>(
    'whatsapp_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('UNKNOWN'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    name,
    phone,
    email,
    address,
    isActive,
    membershipActive,
    membershipFeePaise,
    whatsappStatus,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Customer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('membership_active')) {
      context.handle(
        _membershipActiveMeta,
        membershipActive.isAcceptableOrUnknown(
          data['membership_active']!,
          _membershipActiveMeta,
        ),
      );
    }
    if (data.containsKey('membership_fee_paise')) {
      context.handle(
        _membershipFeePaiseMeta,
        membershipFeePaise.isAcceptableOrUnknown(
          data['membership_fee_paise']!,
          _membershipFeePaiseMeta,
        ),
      );
    }
    if (data.containsKey('whatsapp_status')) {
      context.handle(
        _whatsappStatusMeta,
        whatsappStatus.isAcceptableOrUnknown(
          data['whatsapp_status']!,
          _whatsappStatusMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Customer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Customer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      membershipActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}membership_active'],
      )!,
      membershipFeePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}membership_fee_paise'],
      ),
      whatsappStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}whatsapp_status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CustomersTable createAlias(String alias) {
    return $CustomersTable(attachedDatabase, alias);
  }
}

class Customer extends DataClass implements Insertable<Customer> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this customer.
  final String? shopId;

  /// Customer display name.
  final String name;

  /// Phone number; optional. Unique when present (SQLite unique indexes
  /// treat NULLs as distinct). Case-insensitive uniqueness is enforced by
  /// the repository before insert/update.
  final String? phone;

  /// Email address; optional. Not unique — a household or business may
  /// share an inbox.
  final String? email;

  /// Billing/delivery address; optional.
  final String? address;

  /// Soft switch to hide a customer without deleting their records.
  final bool isActive;

  /// Membership enrolment. When active — and membership pricing is enabled
  /// globally in settings — the counter charges this customer the member
  /// price of every membership-enabled product/variant.
  final bool membershipActive;

  /// Membership fee snapshot in integer paise (e.g. 5000 = ₹50); optional,
  /// informational, and fully owner-editable. Never a billing rule by
  /// itself — charged prices always come from the product/variant member
  /// prices.
  final int? membershipFeePaise;

  /// Honest WhatsApp reachability state reported by a verification provider.
  /// 'UNKNOWN' until a real provider verifies the number; never inferred
  /// from formatting/country code.
  final String whatsappStatus;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const Customer({
    required this.id,
    this.shopId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    required this.isActive,
    required this.membershipActive,
    this.membershipFeePaise,
    required this.whatsappStatus,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['membership_active'] = Variable<bool>(membershipActive);
    if (!nullToAbsent || membershipFeePaise != null) {
      map['membership_fee_paise'] = Variable<int>(membershipFeePaise);
    }
    map['whatsapp_status'] = Variable<String>(whatsappStatus);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CustomersCompanion toCompanion(bool nullToAbsent) {
    return CustomersCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      isActive: Value(isActive),
      membershipActive: Value(membershipActive),
      membershipFeePaise: membershipFeePaise == null && nullToAbsent
          ? const Value.absent()
          : Value(membershipFeePaise),
      whatsappStatus: Value(whatsappStatus),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Customer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Customer(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      email: serializer.fromJson<String?>(json['email']),
      address: serializer.fromJson<String?>(json['address']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      membershipActive: serializer.fromJson<bool>(json['membershipActive']),
      membershipFeePaise: serializer.fromJson<int?>(json['membershipFeePaise']),
      whatsappStatus: serializer.fromJson<String>(json['whatsappStatus']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'email': serializer.toJson<String?>(email),
      'address': serializer.toJson<String?>(address),
      'isActive': serializer.toJson<bool>(isActive),
      'membershipActive': serializer.toJson<bool>(membershipActive),
      'membershipFeePaise': serializer.toJson<int?>(membershipFeePaise),
      'whatsappStatus': serializer.toJson<String>(whatsappStatus),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Customer copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> address = const Value.absent(),
    bool? isActive,
    bool? membershipActive,
    Value<int?> membershipFeePaise = const Value.absent(),
    String? whatsappStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Customer(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    email: email.present ? email.value : this.email,
    address: address.present ? address.value : this.address,
    isActive: isActive ?? this.isActive,
    membershipActive: membershipActive ?? this.membershipActive,
    membershipFeePaise: membershipFeePaise.present
        ? membershipFeePaise.value
        : this.membershipFeePaise,
    whatsappStatus: whatsappStatus ?? this.whatsappStatus,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Customer copyWithCompanion(CustomersCompanion data) {
    return Customer(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      email: data.email.present ? data.email.value : this.email,
      address: data.address.present ? data.address.value : this.address,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      membershipActive: data.membershipActive.present
          ? data.membershipActive.value
          : this.membershipActive,
      membershipFeePaise: data.membershipFeePaise.present
          ? data.membershipFeePaise.value
          : this.membershipFeePaise,
      whatsappStatus: data.whatsappStatus.present
          ? data.whatsappStatus.value
          : this.whatsappStatus,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Customer(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('address: $address, ')
          ..write('isActive: $isActive, ')
          ..write('membershipActive: $membershipActive, ')
          ..write('membershipFeePaise: $membershipFeePaise, ')
          ..write('whatsappStatus: $whatsappStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    name,
    phone,
    email,
    address,
    isActive,
    membershipActive,
    membershipFeePaise,
    whatsappStatus,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Customer &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.email == this.email &&
          other.address == this.address &&
          other.isActive == this.isActive &&
          other.membershipActive == this.membershipActive &&
          other.membershipFeePaise == this.membershipFeePaise &&
          other.whatsappStatus == this.whatsappStatus &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CustomersCompanion extends UpdateCompanion<Customer> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> email;
  final Value<String?> address;
  final Value<bool> isActive;
  final Value<bool> membershipActive;
  final Value<int?> membershipFeePaise;
  final Value<String> whatsappStatus;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CustomersCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.address = const Value.absent(),
    this.isActive = const Value.absent(),
    this.membershipActive = const Value.absent(),
    this.membershipFeePaise = const Value.absent(),
    this.whatsappStatus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomersCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String name,
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.address = const Value.absent(),
    this.isActive = const Value.absent(),
    this.membershipActive = const Value.absent(),
    this.membershipFeePaise = const Value.absent(),
    this.whatsappStatus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Customer> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? email,
    Expression<String>? address,
    Expression<bool>? isActive,
    Expression<bool>? membershipActive,
    Expression<int>? membershipFeePaise,
    Expression<String>? whatsappStatus,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
      if (isActive != null) 'is_active': isActive,
      if (membershipActive != null) 'membership_active': membershipActive,
      if (membershipFeePaise != null)
        'membership_fee_paise': membershipFeePaise,
      if (whatsappStatus != null) 'whatsapp_status': whatsappStatus,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomersCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? email,
    Value<String?>? address,
    Value<bool>? isActive,
    Value<bool>? membershipActive,
    Value<int?>? membershipFeePaise,
    Value<String>? whatsappStatus,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CustomersCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      isActive: isActive ?? this.isActive,
      membershipActive: membershipActive ?? this.membershipActive,
      membershipFeePaise: membershipFeePaise ?? this.membershipFeePaise,
      whatsappStatus: whatsappStatus ?? this.whatsappStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (membershipActive.present) {
      map['membership_active'] = Variable<bool>(membershipActive.value);
    }
    if (membershipFeePaise.present) {
      map['membership_fee_paise'] = Variable<int>(membershipFeePaise.value);
    }
    if (whatsappStatus.present) {
      map['whatsapp_status'] = Variable<String>(whatsappStatus.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomersCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('address: $address, ')
          ..write('isActive: $isActive, ')
          ..write('membershipActive: $membershipActive, ')
          ..write('membershipFeePaise: $membershipFeePaise, ')
          ..write('whatsappStatus: $whatsappStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SalesTable extends Sales with TableInfo<$SalesTable, Sale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES customers (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _receiptNumberMeta = const VerificationMeta(
    'receiptNumber',
  );
  @override
  late final GeneratedColumn<String> receiptNumber = GeneratedColumn<String>(
    'receipt_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subtotalPaiseMeta = const VerificationMeta(
    'subtotalPaise',
  );
  @override
  late final GeneratedColumn<int> subtotalPaise = GeneratedColumn<int>(
    'subtotal_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (subtotal_paise >= 0)',
  );
  static const VerificationMeta _totalPaiseMeta = const VerificationMeta(
    'totalPaise',
  );
  @override
  late final GeneratedColumn<int> totalPaise = GeneratedColumn<int>(
    'total_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (total_paise >= 0)',
  );
  static const VerificationMeta _offerDiscountPaiseMeta =
      const VerificationMeta('offerDiscountPaise');
  @override
  late final GeneratedColumn<int> offerDiscountPaise = GeneratedColumn<int>(
    'offer_discount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (offer_discount_paise >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (payment_method IN (\'CASH\', \'UPI\', \'BANK\'))',
  );
  static const VerificationMeta _paymentStatusMeta = const VerificationMeta(
    'paymentStatus',
  );
  @override
  late final GeneratedColumn<String> paymentStatus = GeneratedColumn<String>(
    'payment_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'PAID\' CHECK (payment_status IN (\'PAID\', \'NOT_PAID\'))',
    defaultValue: const CustomExpression('\'PAID\''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _voidedMeta = const VerificationMeta('voided');
  @override
  late final GeneratedColumn<bool> voided = GeneratedColumn<bool>(
    'voided',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("voided" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _voidedAtMeta = const VerificationMeta(
    'voidedAt',
  );
  @override
  late final GeneratedColumn<DateTime> voidedAt = GeneratedColumn<DateTime>(
    'voided_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    customerId,
    receiptNumber,
    subtotalPaise,
    totalPaise,
    offerDiscountPaise,
    paymentMethod,
    paymentStatus,
    createdAt,
    updatedAt,
    voided,
    voidedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sales';
  @override
  VerificationContext validateIntegrity(
    Insertable<Sale> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    }
    if (data.containsKey('receipt_number')) {
      context.handle(
        _receiptNumberMeta,
        receiptNumber.isAcceptableOrUnknown(
          data['receipt_number']!,
          _receiptNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receiptNumberMeta);
    }
    if (data.containsKey('subtotal_paise')) {
      context.handle(
        _subtotalPaiseMeta,
        subtotalPaise.isAcceptableOrUnknown(
          data['subtotal_paise']!,
          _subtotalPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_subtotalPaiseMeta);
    }
    if (data.containsKey('total_paise')) {
      context.handle(
        _totalPaiseMeta,
        totalPaise.isAcceptableOrUnknown(data['total_paise']!, _totalPaiseMeta),
      );
    } else if (isInserting) {
      context.missing(_totalPaiseMeta);
    }
    if (data.containsKey('offer_discount_paise')) {
      context.handle(
        _offerDiscountPaiseMeta,
        offerDiscountPaise.isAcceptableOrUnknown(
          data['offer_discount_paise']!,
          _offerDiscountPaiseMeta,
        ),
      );
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    }
    if (data.containsKey('payment_status')) {
      context.handle(
        _paymentStatusMeta,
        paymentStatus.isAcceptableOrUnknown(
          data['payment_status']!,
          _paymentStatusMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('voided')) {
      context.handle(
        _voidedMeta,
        voided.isAcceptableOrUnknown(data['voided']!, _voidedMeta),
      );
    }
    if (data.containsKey('voided_at')) {
      context.handle(
        _voidedAtMeta,
        voidedAt.isAcceptableOrUnknown(data['voided_at']!, _voidedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {shopId, receiptNumber},
  ];
  @override
  Sale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sale(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      ),
      receiptNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_number'],
      )!,
      subtotalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subtotal_paise'],
      )!,
      totalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_paise'],
      )!,
      offerDiscountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offer_discount_paise'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      ),
      paymentStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      voided: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}voided'],
      )!,
      voidedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}voided_at'],
      ),
    );
  }

  @override
  $SalesTable createAlias(String alias) {
    return $SalesTable(attachedDatabase, alias);
  }
}

class Sale extends DataClass implements Insertable<Sale> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this sale.
  final String? shopId;

  /// Owning customer for customer-linked sales; NULL for walk-ins. Deleting a
  /// customer with sales history is rejected (RESTRICT).
  final String? customerId;

  /// Human-readable receipt reference; unique per shop.
  final String receiptNumber;

  /// Sum of line totals in paise, before any adjustments. Must be >= 0.
  final int subtotalPaise;

  /// Amount charged in paise. Equals the subtotal (no discounts/taxes yet).
  final int totalPaise;

  /// Total offer discount applied to this sale in paise. >= 0.
  final int offerDiscountPaise;

  /// Payment method captured at the counter: CASH, UPI or BANK. NULL for
  /// NOT_PAID (credit) sales, where no money moved at the counter.
  final String? paymentMethod;

  /// Collection status of the sale: PAID or NOT_PAID (credit sale whose
  /// total becomes customer debt). Defaults to PAID so existing rows (and
  /// future inserts that omit it) are treated as settled.
  final String paymentStatus;

  /// UTC timestamp of the sale.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;

  /// Whether this sale has been voided. A voided sale is never hard-deleted;
  /// the row is kept for audit purposes, stock is restored and payments
  /// reversed.
  final bool voided;

  /// When the sale was voided; NULL when still active.
  final DateTime? voidedAt;
  const Sale({
    required this.id,
    this.shopId,
    this.customerId,
    required this.receiptNumber,
    required this.subtotalPaise,
    required this.totalPaise,
    required this.offerDiscountPaise,
    this.paymentMethod,
    required this.paymentStatus,
    required this.createdAt,
    required this.updatedAt,
    required this.voided,
    this.voidedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    map['receipt_number'] = Variable<String>(receiptNumber);
    map['subtotal_paise'] = Variable<int>(subtotalPaise);
    map['total_paise'] = Variable<int>(totalPaise);
    map['offer_discount_paise'] = Variable<int>(offerDiscountPaise);
    if (!nullToAbsent || paymentMethod != null) {
      map['payment_method'] = Variable<String>(paymentMethod);
    }
    map['payment_status'] = Variable<String>(paymentStatus);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['voided'] = Variable<bool>(voided);
    if (!nullToAbsent || voidedAt != null) {
      map['voided_at'] = Variable<DateTime>(voidedAt);
    }
    return map;
  }

  SalesCompanion toCompanion(bool nullToAbsent) {
    return SalesCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      receiptNumber: Value(receiptNumber),
      subtotalPaise: Value(subtotalPaise),
      totalPaise: Value(totalPaise),
      offerDiscountPaise: Value(offerDiscountPaise),
      paymentMethod: paymentMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentMethod),
      paymentStatus: Value(paymentStatus),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      voided: Value(voided),
      voidedAt: voidedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(voidedAt),
    );
  }

  factory Sale.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sale(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      receiptNumber: serializer.fromJson<String>(json['receiptNumber']),
      subtotalPaise: serializer.fromJson<int>(json['subtotalPaise']),
      totalPaise: serializer.fromJson<int>(json['totalPaise']),
      offerDiscountPaise: serializer.fromJson<int>(json['offerDiscountPaise']),
      paymentMethod: serializer.fromJson<String?>(json['paymentMethod']),
      paymentStatus: serializer.fromJson<String>(json['paymentStatus']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      voided: serializer.fromJson<bool>(json['voided']),
      voidedAt: serializer.fromJson<DateTime?>(json['voidedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'customerId': serializer.toJson<String?>(customerId),
      'receiptNumber': serializer.toJson<String>(receiptNumber),
      'subtotalPaise': serializer.toJson<int>(subtotalPaise),
      'totalPaise': serializer.toJson<int>(totalPaise),
      'offerDiscountPaise': serializer.toJson<int>(offerDiscountPaise),
      'paymentMethod': serializer.toJson<String?>(paymentMethod),
      'paymentStatus': serializer.toJson<String>(paymentStatus),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'voided': serializer.toJson<bool>(voided),
      'voidedAt': serializer.toJson<DateTime?>(voidedAt),
    };
  }

  Sale copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    Value<String?> customerId = const Value.absent(),
    String? receiptNumber,
    int? subtotalPaise,
    int? totalPaise,
    int? offerDiscountPaise,
    Value<String?> paymentMethod = const Value.absent(),
    String? paymentStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? voided,
    Value<DateTime?> voidedAt = const Value.absent(),
  }) => Sale(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    customerId: customerId.present ? customerId.value : this.customerId,
    receiptNumber: receiptNumber ?? this.receiptNumber,
    subtotalPaise: subtotalPaise ?? this.subtotalPaise,
    totalPaise: totalPaise ?? this.totalPaise,
    offerDiscountPaise: offerDiscountPaise ?? this.offerDiscountPaise,
    paymentMethod: paymentMethod.present
        ? paymentMethod.value
        : this.paymentMethod,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    voided: voided ?? this.voided,
    voidedAt: voidedAt.present ? voidedAt.value : this.voidedAt,
  );
  Sale copyWithCompanion(SalesCompanion data) {
    return Sale(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      receiptNumber: data.receiptNumber.present
          ? data.receiptNumber.value
          : this.receiptNumber,
      subtotalPaise: data.subtotalPaise.present
          ? data.subtotalPaise.value
          : this.subtotalPaise,
      totalPaise: data.totalPaise.present
          ? data.totalPaise.value
          : this.totalPaise,
      offerDiscountPaise: data.offerDiscountPaise.present
          ? data.offerDiscountPaise.value
          : this.offerDiscountPaise,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      paymentStatus: data.paymentStatus.present
          ? data.paymentStatus.value
          : this.paymentStatus,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      voided: data.voided.present ? data.voided.value : this.voided,
      voidedAt: data.voidedAt.present ? data.voidedAt.value : this.voidedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sale(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('customerId: $customerId, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('subtotalPaise: $subtotalPaise, ')
          ..write('totalPaise: $totalPaise, ')
          ..write('offerDiscountPaise: $offerDiscountPaise, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('voided: $voided, ')
          ..write('voidedAt: $voidedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    customerId,
    receiptNumber,
    subtotalPaise,
    totalPaise,
    offerDiscountPaise,
    paymentMethod,
    paymentStatus,
    createdAt,
    updatedAt,
    voided,
    voidedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sale &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.customerId == this.customerId &&
          other.receiptNumber == this.receiptNumber &&
          other.subtotalPaise == this.subtotalPaise &&
          other.totalPaise == this.totalPaise &&
          other.offerDiscountPaise == this.offerDiscountPaise &&
          other.paymentMethod == this.paymentMethod &&
          other.paymentStatus == this.paymentStatus &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.voided == this.voided &&
          other.voidedAt == this.voidedAt);
}

class SalesCompanion extends UpdateCompanion<Sale> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String?> customerId;
  final Value<String> receiptNumber;
  final Value<int> subtotalPaise;
  final Value<int> totalPaise;
  final Value<int> offerDiscountPaise;
  final Value<String?> paymentMethod;
  final Value<String> paymentStatus;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> voided;
  final Value<DateTime?> voidedAt;
  final Value<int> rowid;
  const SalesCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.receiptNumber = const Value.absent(),
    this.subtotalPaise = const Value.absent(),
    this.totalPaise = const Value.absent(),
    this.offerDiscountPaise = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.voided = const Value.absent(),
    this.voidedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SalesCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.customerId = const Value.absent(),
    required String receiptNumber,
    required int subtotalPaise,
    required int totalPaise,
    this.offerDiscountPaise = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.voided = const Value.absent(),
    this.voidedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : receiptNumber = Value(receiptNumber),
       subtotalPaise = Value(subtotalPaise),
       totalPaise = Value(totalPaise);
  static Insertable<Sale> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? customerId,
    Expression<String>? receiptNumber,
    Expression<int>? subtotalPaise,
    Expression<int>? totalPaise,
    Expression<int>? offerDiscountPaise,
    Expression<String>? paymentMethod,
    Expression<String>? paymentStatus,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? voided,
    Expression<DateTime>? voidedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (customerId != null) 'customer_id': customerId,
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (subtotalPaise != null) 'subtotal_paise': subtotalPaise,
      if (totalPaise != null) 'total_paise': totalPaise,
      if (offerDiscountPaise != null)
        'offer_discount_paise': offerDiscountPaise,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (voided != null) 'voided': voided,
      if (voidedAt != null) 'voided_at': voidedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SalesCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String?>? customerId,
    Value<String>? receiptNumber,
    Value<int>? subtotalPaise,
    Value<int>? totalPaise,
    Value<int>? offerDiscountPaise,
    Value<String?>? paymentMethod,
    Value<String>? paymentStatus,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? voided,
    Value<DateTime?>? voidedAt,
    Value<int>? rowid,
  }) {
    return SalesCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      customerId: customerId ?? this.customerId,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      subtotalPaise: subtotalPaise ?? this.subtotalPaise,
      totalPaise: totalPaise ?? this.totalPaise,
      offerDiscountPaise: offerDiscountPaise ?? this.offerDiscountPaise,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      voided: voided ?? this.voided,
      voidedAt: voidedAt ?? this.voidedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (receiptNumber.present) {
      map['receipt_number'] = Variable<String>(receiptNumber.value);
    }
    if (subtotalPaise.present) {
      map['subtotal_paise'] = Variable<int>(subtotalPaise.value);
    }
    if (totalPaise.present) {
      map['total_paise'] = Variable<int>(totalPaise.value);
    }
    if (offerDiscountPaise.present) {
      map['offer_discount_paise'] = Variable<int>(offerDiscountPaise.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (paymentStatus.present) {
      map['payment_status'] = Variable<String>(paymentStatus.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (voided.present) {
      map['voided'] = Variable<bool>(voided.value);
    }
    if (voidedAt.present) {
      map['voided_at'] = Variable<DateTime>(voidedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SalesCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('customerId: $customerId, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('subtotalPaise: $subtotalPaise, ')
          ..write('totalPaise: $totalPaise, ')
          ..write('offerDiscountPaise: $offerDiscountPaise, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('voided: $voided, ')
          ..write('voidedAt: $voidedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomerPaymentsTable extends CustomerPayments
    with TableInfo<$CustomerPaymentsTable, CustomerPayment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomerPaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES customers (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
    'sale_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sales (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (amount_paise >= 0)',
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (payment_method IN (\'CASH\', \'UPI\', \'BANK\'))',
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paidAtMeta = const VerificationMeta('paidAt');
  @override
  late final GeneratedColumn<DateTime> paidAt = GeneratedColumn<DateTime>(
    'paid_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reversedMeta = const VerificationMeta(
    'reversed',
  );
  @override
  late final GeneratedColumn<bool> reversed = GeneratedColumn<bool>(
    'reversed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reversed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _reversedAtMeta = const VerificationMeta(
    'reversedAt',
  );
  @override
  late final GeneratedColumn<DateTime> reversedAt = GeneratedColumn<DateTime>(
    'reversed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    customerId,
    saleId,
    amountPaise,
    paymentMethod,
    note,
    paidAt,
    reversed,
    reversedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customer_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomerPayment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_customerIdMeta);
    }
    if (data.containsKey('sale_id')) {
      context.handle(
        _saleIdMeta,
        saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta),
      );
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('paid_at')) {
      context.handle(
        _paidAtMeta,
        paidAt.isAcceptableOrUnknown(data['paid_at']!, _paidAtMeta),
      );
    } else if (isInserting) {
      context.missing(_paidAtMeta);
    }
    if (data.containsKey('reversed')) {
      context.handle(
        _reversedMeta,
        reversed.isAcceptableOrUnknown(data['reversed']!, _reversedMeta),
      );
    }
    if (data.containsKey('reversed_at')) {
      context.handle(
        _reversedAtMeta,
        reversedAt.isAcceptableOrUnknown(data['reversed_at']!, _reversedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomerPayment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomerPayment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      )!,
      saleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_id'],
      ),
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      paidAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paid_at'],
      )!,
      reversed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reversed'],
      )!,
      reversedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reversed_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CustomerPaymentsTable createAlias(String alias) {
    return $CustomerPaymentsTable(attachedDatabase, alias);
  }
}

class CustomerPayment extends DataClass implements Insertable<CustomerPayment> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this customer payment.
  final String? shopId;

  /// Owning customer. Deleting a customer with payments is rejected.
  final String customerId;

  /// Sale the payment is allocated to; NULL is reserved for future
  /// advance/whole-balance payments (the repository requires allocation).
  final String? saleId;

  /// Amount paid in paise. Must be >= 0; the repository requires > 0.
  final int amountPaise;

  /// Payment method captured at the counter: CASH, UPI or BANK.
  final String paymentMethod;

  /// Optional free-form note; NULL when blank.
  final String? note;

  /// Exact UTC instant the money moved (the business timestamp; no
  /// back-dating in Phase 8).
  final DateTime paidAt;

  /// Compensating-entry flag; FALSE for every Phase 8 payment.
  final bool reversed;

  /// When [reversed] flips true; NULL otherwise.
  final DateTime? reversedAt;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const CustomerPayment({
    required this.id,
    this.shopId,
    required this.customerId,
    this.saleId,
    required this.amountPaise,
    required this.paymentMethod,
    this.note,
    required this.paidAt,
    required this.reversed,
    this.reversedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['customer_id'] = Variable<String>(customerId);
    if (!nullToAbsent || saleId != null) {
      map['sale_id'] = Variable<String>(saleId);
    }
    map['amount_paise'] = Variable<int>(amountPaise);
    map['payment_method'] = Variable<String>(paymentMethod);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['paid_at'] = Variable<DateTime>(paidAt);
    map['reversed'] = Variable<bool>(reversed);
    if (!nullToAbsent || reversedAt != null) {
      map['reversed_at'] = Variable<DateTime>(reversedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CustomerPaymentsCompanion toCompanion(bool nullToAbsent) {
    return CustomerPaymentsCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      customerId: Value(customerId),
      saleId: saleId == null && nullToAbsent
          ? const Value.absent()
          : Value(saleId),
      amountPaise: Value(amountPaise),
      paymentMethod: Value(paymentMethod),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      paidAt: Value(paidAt),
      reversed: Value(reversed),
      reversedAt: reversedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reversedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CustomerPayment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomerPayment(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      customerId: serializer.fromJson<String>(json['customerId']),
      saleId: serializer.fromJson<String?>(json['saleId']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      note: serializer.fromJson<String?>(json['note']),
      paidAt: serializer.fromJson<DateTime>(json['paidAt']),
      reversed: serializer.fromJson<bool>(json['reversed']),
      reversedAt: serializer.fromJson<DateTime?>(json['reversedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'customerId': serializer.toJson<String>(customerId),
      'saleId': serializer.toJson<String?>(saleId),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'note': serializer.toJson<String?>(note),
      'paidAt': serializer.toJson<DateTime>(paidAt),
      'reversed': serializer.toJson<bool>(reversed),
      'reversedAt': serializer.toJson<DateTime?>(reversedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CustomerPayment copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? customerId,
    Value<String?> saleId = const Value.absent(),
    int? amountPaise,
    String? paymentMethod,
    Value<String?> note = const Value.absent(),
    DateTime? paidAt,
    bool? reversed,
    Value<DateTime?> reversedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CustomerPayment(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    customerId: customerId ?? this.customerId,
    saleId: saleId.present ? saleId.value : this.saleId,
    amountPaise: amountPaise ?? this.amountPaise,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    note: note.present ? note.value : this.note,
    paidAt: paidAt ?? this.paidAt,
    reversed: reversed ?? this.reversed,
    reversedAt: reversedAt.present ? reversedAt.value : this.reversedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CustomerPayment copyWithCompanion(CustomerPaymentsCompanion data) {
    return CustomerPayment(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      note: data.note.present ? data.note.value : this.note,
      paidAt: data.paidAt.present ? data.paidAt.value : this.paidAt,
      reversed: data.reversed.present ? data.reversed.value : this.reversed,
      reversedAt: data.reversedAt.present
          ? data.reversedAt.value
          : this.reversedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomerPayment(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('customerId: $customerId, ')
          ..write('saleId: $saleId, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('note: $note, ')
          ..write('paidAt: $paidAt, ')
          ..write('reversed: $reversed, ')
          ..write('reversedAt: $reversedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    customerId,
    saleId,
    amountPaise,
    paymentMethod,
    note,
    paidAt,
    reversed,
    reversedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomerPayment &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.customerId == this.customerId &&
          other.saleId == this.saleId &&
          other.amountPaise == this.amountPaise &&
          other.paymentMethod == this.paymentMethod &&
          other.note == this.note &&
          other.paidAt == this.paidAt &&
          other.reversed == this.reversed &&
          other.reversedAt == this.reversedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CustomerPaymentsCompanion extends UpdateCompanion<CustomerPayment> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> customerId;
  final Value<String?> saleId;
  final Value<int> amountPaise;
  final Value<String> paymentMethod;
  final Value<String?> note;
  final Value<DateTime> paidAt;
  final Value<bool> reversed;
  final Value<DateTime?> reversedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CustomerPaymentsCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.saleId = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.note = const Value.absent(),
    this.paidAt = const Value.absent(),
    this.reversed = const Value.absent(),
    this.reversedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomerPaymentsCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String customerId,
    this.saleId = const Value.absent(),
    required int amountPaise,
    required String paymentMethod,
    this.note = const Value.absent(),
    required DateTime paidAt,
    this.reversed = const Value.absent(),
    this.reversedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : customerId = Value(customerId),
       amountPaise = Value(amountPaise),
       paymentMethod = Value(paymentMethod),
       paidAt = Value(paidAt);
  static Insertable<CustomerPayment> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? customerId,
    Expression<String>? saleId,
    Expression<int>? amountPaise,
    Expression<String>? paymentMethod,
    Expression<String>? note,
    Expression<DateTime>? paidAt,
    Expression<bool>? reversed,
    Expression<DateTime>? reversedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (customerId != null) 'customer_id': customerId,
      if (saleId != null) 'sale_id': saleId,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (note != null) 'note': note,
      if (paidAt != null) 'paid_at': paidAt,
      if (reversed != null) 'reversed': reversed,
      if (reversedAt != null) 'reversed_at': reversedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomerPaymentsCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? customerId,
    Value<String?>? saleId,
    Value<int>? amountPaise,
    Value<String>? paymentMethod,
    Value<String?>? note,
    Value<DateTime>? paidAt,
    Value<bool>? reversed,
    Value<DateTime?>? reversedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CustomerPaymentsCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      customerId: customerId ?? this.customerId,
      saleId: saleId ?? this.saleId,
      amountPaise: amountPaise ?? this.amountPaise,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      note: note ?? this.note,
      paidAt: paidAt ?? this.paidAt,
      reversed: reversed ?? this.reversed,
      reversedAt: reversedAt ?? this.reversedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (paidAt.present) {
      map['paid_at'] = Variable<DateTime>(paidAt.value);
    }
    if (reversed.present) {
      map['reversed'] = Variable<bool>(reversed.value);
    }
    if (reversedAt.present) {
      map['reversed_at'] = Variable<DateTime>(reversedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomerPaymentsCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('customerId: $customerId, ')
          ..write('saleId: $saleId, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('note: $note, ')
          ..write('paidAt: $paidAt, ')
          ..write('reversed: $reversed, ')
          ..write('reversedAt: $reversedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpensesTable extends Expenses with TableInfo<$ExpensesTable, Expense> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (amount_paise >= 0)',
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (category IN (\'SUPPLIES\', \'UTILITIES\', \'RENT\', \'SALARIES\', \'MAINTENANCE\', \'MARKETING\', \'TRANSPORT\', \'MISC\'))',
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (payment_method IN (\'CASH\', \'UPI\', \'BANK\'))',
  );
  static const VerificationMeta _paymentStatusMeta = const VerificationMeta(
    'paymentStatus',
  );
  @override
  late final GeneratedColumn<String> paymentStatus = GeneratedColumn<String>(
    'payment_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'PAID\' CHECK (payment_status IN (\'PAID\', \'NOT_PAID\'))',
    defaultValue: const CustomExpression('\'PAID\''),
  );
  static const VerificationMeta _expenseDateMeta = const VerificationMeta(
    'expenseDate',
  );
  @override
  late final GeneratedColumn<DateTime> expenseDate = GeneratedColumn<DateTime>(
    'expense_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    name,
    amountPaise,
    category,
    paymentMethod,
    paymentStatus,
    expenseDate,
    note,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(
    Insertable<Expense> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('payment_status')) {
      context.handle(
        _paymentStatusMeta,
        paymentStatus.isAcceptableOrUnknown(
          data['payment_status']!,
          _paymentStatusMeta,
        ),
      );
    }
    if (data.containsKey('expense_date')) {
      context.handle(
        _expenseDateMeta,
        expenseDate.isAcceptableOrUnknown(
          data['expense_date']!,
          _expenseDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expenseDateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Expense map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Expense(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      )!,
      paymentStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_status'],
      )!,
      expenseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expense_date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ExpensesTable createAlias(String alias) {
    return $ExpensesTable(attachedDatabase, alias);
  }
}

class Expense extends DataClass implements Insertable<Expense> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this expense.
  final String? shopId;

  /// Expense display name.
  final String name;

  /// Amount spent in paise. Must be >= 0; the expense form requires > 0.
  final int amountPaise;

  /// Predefined expense category (stable DB value, see the domain enum).
  final String category;

  /// Payment method captured at the counter: CASH, UPI or BANK.
  final String paymentMethod;

  /// Payment status: PAID or NOT_PAID (stable DB value, see the expenses
  /// domain enum). NOT_PAID expenses still count in history and totals and
  /// become shop payable. Existing records default to PAID.
  final String paymentStatus;

  /// Business date of the expense; UTC instant at local midnight of the
  /// user-selected local day.
  final DateTime expenseDate;

  /// Optional free-form note; NULL when blank.
  final String? note;

  /// Soft switch to hide an expense from active lists without deleting it.
  final bool isActive;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const Expense({
    required this.id,
    this.shopId,
    required this.name,
    required this.amountPaise,
    required this.category,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.expenseDate,
    this.note,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['name'] = Variable<String>(name);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['category'] = Variable<String>(category);
    map['payment_method'] = Variable<String>(paymentMethod);
    map['payment_status'] = Variable<String>(paymentStatus);
    map['expense_date'] = Variable<DateTime>(expenseDate);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ExpensesCompanion toCompanion(bool nullToAbsent) {
    return ExpensesCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      name: Value(name),
      amountPaise: Value(amountPaise),
      category: Value(category),
      paymentMethod: Value(paymentMethod),
      paymentStatus: Value(paymentStatus),
      expenseDate: Value(expenseDate),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Expense.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Expense(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      name: serializer.fromJson<String>(json['name']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      category: serializer.fromJson<String>(json['category']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      paymentStatus: serializer.fromJson<String>(json['paymentStatus']),
      expenseDate: serializer.fromJson<DateTime>(json['expenseDate']),
      note: serializer.fromJson<String?>(json['note']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'name': serializer.toJson<String>(name),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'category': serializer.toJson<String>(category),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'paymentStatus': serializer.toJson<String>(paymentStatus),
      'expenseDate': serializer.toJson<DateTime>(expenseDate),
      'note': serializer.toJson<String?>(note),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Expense copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? name,
    int? amountPaise,
    String? category,
    String? paymentMethod,
    String? paymentStatus,
    DateTime? expenseDate,
    Value<String?> note = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Expense(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    name: name ?? this.name,
    amountPaise: amountPaise ?? this.amountPaise,
    category: category ?? this.category,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    expenseDate: expenseDate ?? this.expenseDate,
    note: note.present ? note.value : this.note,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Expense copyWithCompanion(ExpensesCompanion data) {
    return Expense(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      name: data.name.present ? data.name.value : this.name,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      category: data.category.present ? data.category.value : this.category,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      paymentStatus: data.paymentStatus.present
          ? data.paymentStatus.value
          : this.paymentStatus,
      expenseDate: data.expenseDate.present
          ? data.expenseDate.value
          : this.expenseDate,
      note: data.note.present ? data.note.value : this.note,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Expense(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('category: $category, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('expenseDate: $expenseDate, ')
          ..write('note: $note, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    name,
    amountPaise,
    category,
    paymentMethod,
    paymentStatus,
    expenseDate,
    note,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Expense &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.name == this.name &&
          other.amountPaise == this.amountPaise &&
          other.category == this.category &&
          other.paymentMethod == this.paymentMethod &&
          other.paymentStatus == this.paymentStatus &&
          other.expenseDate == this.expenseDate &&
          other.note == this.note &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ExpensesCompanion extends UpdateCompanion<Expense> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> name;
  final Value<int> amountPaise;
  final Value<String> category;
  final Value<String> paymentMethod;
  final Value<String> paymentStatus;
  final Value<DateTime> expenseDate;
  final Value<String?> note;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ExpensesCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.name = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.category = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.expenseDate = const Value.absent(),
    this.note = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpensesCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String name,
    required int amountPaise,
    required String category,
    required String paymentMethod,
    this.paymentStatus = const Value.absent(),
    required DateTime expenseDate,
    this.note = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       amountPaise = Value(amountPaise),
       category = Value(category),
       paymentMethod = Value(paymentMethod),
       expenseDate = Value(expenseDate);
  static Insertable<Expense> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? name,
    Expression<int>? amountPaise,
    Expression<String>? category,
    Expression<String>? paymentMethod,
    Expression<String>? paymentStatus,
    Expression<DateTime>? expenseDate,
    Expression<String>? note,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (name != null) 'name': name,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (category != null) 'category': category,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (expenseDate != null) 'expense_date': expenseDate,
      if (note != null) 'note': note,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpensesCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? name,
    Value<int>? amountPaise,
    Value<String>? category,
    Value<String>? paymentMethod,
    Value<String>? paymentStatus,
    Value<DateTime>? expenseDate,
    Value<String?>? note,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ExpensesCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      amountPaise: amountPaise ?? this.amountPaise,
      category: category ?? this.category,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      expenseDate: expenseDate ?? this.expenseDate,
      note: note ?? this.note,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (paymentStatus.present) {
      map['payment_status'] = Variable<String>(paymentStatus.value);
    }
    if (expenseDate.present) {
      map['expense_date'] = Variable<DateTime>(expenseDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpensesCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('category: $category, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('expenseDate: $expenseDate, ')
          ..write('note: $note, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SaleItemsTable extends SaleItems
    with TableInfo<$SaleItemsTable, SaleItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SaleItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
    'sale_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sales (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES products (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<String> variantId = GeneratedColumn<String>(
    'variant_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES product_variants (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _productNameMeta = const VerificationMeta(
    'productName',
  );
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
    'product_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantNameMeta = const VerificationMeta(
    'variantName',
  );
  @override
  late final GeneratedColumn<String> variantName = GeneratedColumn<String>(
    'variant_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitPricePaiseMeta = const VerificationMeta(
    'unitPricePaise',
  );
  @override
  late final GeneratedColumn<int> unitPricePaise = GeneratedColumn<int>(
    'unit_price_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (unit_price_paise >= 0)',
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (quantity > 0)',
  );
  static const VerificationMeta _lineTotalPaiseMeta = const VerificationMeta(
    'lineTotalPaise',
  );
  @override
  late final GeneratedColumn<int> lineTotalPaise = GeneratedColumn<int>(
    'line_total_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (line_total_paise >= 0)',
  );
  static const VerificationMeta _offerDiscountPaiseMeta =
      const VerificationMeta('offerDiscountPaise');
  @override
  late final GeneratedColumn<int> offerDiscountPaise = GeneratedColumn<int>(
    'offer_discount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (offer_discount_paise >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _appliedOfferIdMeta = const VerificationMeta(
    'appliedOfferId',
  );
  @override
  late final GeneratedColumn<String> appliedOfferId = GeneratedColumn<String>(
    'applied_offer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appliedOfferNameMeta = const VerificationMeta(
    'appliedOfferName',
  );
  @override
  late final GeneratedColumn<String> appliedOfferName = GeneratedColumn<String>(
    'applied_offer_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appliedOfferTypeMeta = const VerificationMeta(
    'appliedOfferType',
  );
  @override
  late final GeneratedColumn<String> appliedOfferType = GeneratedColumn<String>(
    'applied_offer_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (applied_offer_type IS NULL OR applied_offer_type IN (\'PERCENTAGE\',\'COMBO\',\'BUY_X_GET_Y\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    saleId,
    productId,
    variantId,
    productName,
    variantName,
    sku,
    unitPricePaise,
    quantity,
    lineTotalPaise,
    offerDiscountPaise,
    appliedOfferId,
    appliedOfferName,
    appliedOfferType,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sale_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<SaleItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('sale_id')) {
      context.handle(
        _saleIdMeta,
        saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_saleIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    }
    if (data.containsKey('product_name')) {
      context.handle(
        _productNameMeta,
        productName.isAcceptableOrUnknown(
          data['product_name']!,
          _productNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_productNameMeta);
    }
    if (data.containsKey('variant_name')) {
      context.handle(
        _variantNameMeta,
        variantName.isAcceptableOrUnknown(
          data['variant_name']!,
          _variantNameMeta,
        ),
      );
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    }
    if (data.containsKey('unit_price_paise')) {
      context.handle(
        _unitPricePaiseMeta,
        unitPricePaise.isAcceptableOrUnknown(
          data['unit_price_paise']!,
          _unitPricePaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unitPricePaiseMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('line_total_paise')) {
      context.handle(
        _lineTotalPaiseMeta,
        lineTotalPaise.isAcceptableOrUnknown(
          data['line_total_paise']!,
          _lineTotalPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lineTotalPaiseMeta);
    }
    if (data.containsKey('offer_discount_paise')) {
      context.handle(
        _offerDiscountPaiseMeta,
        offerDiscountPaise.isAcceptableOrUnknown(
          data['offer_discount_paise']!,
          _offerDiscountPaiseMeta,
        ),
      );
    }
    if (data.containsKey('applied_offer_id')) {
      context.handle(
        _appliedOfferIdMeta,
        appliedOfferId.isAcceptableOrUnknown(
          data['applied_offer_id']!,
          _appliedOfferIdMeta,
        ),
      );
    }
    if (data.containsKey('applied_offer_name')) {
      context.handle(
        _appliedOfferNameMeta,
        appliedOfferName.isAcceptableOrUnknown(
          data['applied_offer_name']!,
          _appliedOfferNameMeta,
        ),
      );
    }
    if (data.containsKey('applied_offer_type')) {
      context.handle(
        _appliedOfferTypeMeta,
        appliedOfferType.isAcceptableOrUnknown(
          data['applied_offer_type']!,
          _appliedOfferTypeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SaleItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaleItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      saleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_id'],
      ),
      productName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_name'],
      )!,
      variantName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_name'],
      ),
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      ),
      unitPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_price_paise'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      lineTotalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_total_paise'],
      )!,
      offerDiscountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offer_discount_paise'],
      )!,
      appliedOfferId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}applied_offer_id'],
      ),
      appliedOfferName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}applied_offer_name'],
      ),
      appliedOfferType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}applied_offer_type'],
      ),
    );
  }

  @override
  $SaleItemsTable createAlias(String alias) {
    return $SaleItemsTable(attachedDatabase, alias);
  }
}

class SaleItem extends DataClass implements Insertable<SaleItem> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this sale item.
  final String? shopId;

  /// Owning sale. Deleting a sale with items is rejected (RESTRICT).
  final String saleId;

  /// Product sold. Deleting a product with sale history is rejected.
  final String productId;

  /// Variant sold; NULL for non-variant lines. RESTRICT protects history.
  final String? variantId;

  /// Product name at the time of the sale (snapshot).
  final String productName;

  /// Variant name at the time of the sale (snapshot); NULL when the line is
  /// not a variant line.
  final String? variantName;

  /// Product SKU at the time of the sale (snapshot); NULL when absent.
  final String? sku;

  /// Unit selling price in paise at sale time. Must be >= 0.
  final int unitPricePaise;

  /// Quantity sold. Must be > 0.
  final int quantity;

  /// unitPricePaise * quantity in paise. Must be >= 0.
  final int lineTotalPaise;

  /// Offer discount applied to this line in paise. >= 0.
  final int offerDiscountPaise;

  /// Applied offer ID; NULL when no offer applied.
  final String? appliedOfferId;

  /// Applied offer name; NULL when no offer applied.
  final String? appliedOfferName;

  /// Applied offer type; NULL when no offer applied.
  final String? appliedOfferType;
  const SaleItem({
    required this.id,
    this.shopId,
    required this.saleId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantName,
    this.sku,
    required this.unitPricePaise,
    required this.quantity,
    required this.lineTotalPaise,
    required this.offerDiscountPaise,
    this.appliedOfferId,
    this.appliedOfferName,
    this.appliedOfferType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['sale_id'] = Variable<String>(saleId);
    map['product_id'] = Variable<String>(productId);
    if (!nullToAbsent || variantId != null) {
      map['variant_id'] = Variable<String>(variantId);
    }
    map['product_name'] = Variable<String>(productName);
    if (!nullToAbsent || variantName != null) {
      map['variant_name'] = Variable<String>(variantName);
    }
    if (!nullToAbsent || sku != null) {
      map['sku'] = Variable<String>(sku);
    }
    map['unit_price_paise'] = Variable<int>(unitPricePaise);
    map['quantity'] = Variable<int>(quantity);
    map['line_total_paise'] = Variable<int>(lineTotalPaise);
    map['offer_discount_paise'] = Variable<int>(offerDiscountPaise);
    if (!nullToAbsent || appliedOfferId != null) {
      map['applied_offer_id'] = Variable<String>(appliedOfferId);
    }
    if (!nullToAbsent || appliedOfferName != null) {
      map['applied_offer_name'] = Variable<String>(appliedOfferName);
    }
    if (!nullToAbsent || appliedOfferType != null) {
      map['applied_offer_type'] = Variable<String>(appliedOfferType);
    }
    return map;
  }

  SaleItemsCompanion toCompanion(bool nullToAbsent) {
    return SaleItemsCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      saleId: Value(saleId),
      productId: Value(productId),
      variantId: variantId == null && nullToAbsent
          ? const Value.absent()
          : Value(variantId),
      productName: Value(productName),
      variantName: variantName == null && nullToAbsent
          ? const Value.absent()
          : Value(variantName),
      sku: sku == null && nullToAbsent ? const Value.absent() : Value(sku),
      unitPricePaise: Value(unitPricePaise),
      quantity: Value(quantity),
      lineTotalPaise: Value(lineTotalPaise),
      offerDiscountPaise: Value(offerDiscountPaise),
      appliedOfferId: appliedOfferId == null && nullToAbsent
          ? const Value.absent()
          : Value(appliedOfferId),
      appliedOfferName: appliedOfferName == null && nullToAbsent
          ? const Value.absent()
          : Value(appliedOfferName),
      appliedOfferType: appliedOfferType == null && nullToAbsent
          ? const Value.absent()
          : Value(appliedOfferType),
    );
  }

  factory SaleItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaleItem(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      saleId: serializer.fromJson<String>(json['saleId']),
      productId: serializer.fromJson<String>(json['productId']),
      variantId: serializer.fromJson<String?>(json['variantId']),
      productName: serializer.fromJson<String>(json['productName']),
      variantName: serializer.fromJson<String?>(json['variantName']),
      sku: serializer.fromJson<String?>(json['sku']),
      unitPricePaise: serializer.fromJson<int>(json['unitPricePaise']),
      quantity: serializer.fromJson<int>(json['quantity']),
      lineTotalPaise: serializer.fromJson<int>(json['lineTotalPaise']),
      offerDiscountPaise: serializer.fromJson<int>(json['offerDiscountPaise']),
      appliedOfferId: serializer.fromJson<String?>(json['appliedOfferId']),
      appliedOfferName: serializer.fromJson<String?>(json['appliedOfferName']),
      appliedOfferType: serializer.fromJson<String?>(json['appliedOfferType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'saleId': serializer.toJson<String>(saleId),
      'productId': serializer.toJson<String>(productId),
      'variantId': serializer.toJson<String?>(variantId),
      'productName': serializer.toJson<String>(productName),
      'variantName': serializer.toJson<String?>(variantName),
      'sku': serializer.toJson<String?>(sku),
      'unitPricePaise': serializer.toJson<int>(unitPricePaise),
      'quantity': serializer.toJson<int>(quantity),
      'lineTotalPaise': serializer.toJson<int>(lineTotalPaise),
      'offerDiscountPaise': serializer.toJson<int>(offerDiscountPaise),
      'appliedOfferId': serializer.toJson<String?>(appliedOfferId),
      'appliedOfferName': serializer.toJson<String?>(appliedOfferName),
      'appliedOfferType': serializer.toJson<String?>(appliedOfferType),
    };
  }

  SaleItem copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? saleId,
    String? productId,
    Value<String?> variantId = const Value.absent(),
    String? productName,
    Value<String?> variantName = const Value.absent(),
    Value<String?> sku = const Value.absent(),
    int? unitPricePaise,
    int? quantity,
    int? lineTotalPaise,
    int? offerDiscountPaise,
    Value<String?> appliedOfferId = const Value.absent(),
    Value<String?> appliedOfferName = const Value.absent(),
    Value<String?> appliedOfferType = const Value.absent(),
  }) => SaleItem(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    saleId: saleId ?? this.saleId,
    productId: productId ?? this.productId,
    variantId: variantId.present ? variantId.value : this.variantId,
    productName: productName ?? this.productName,
    variantName: variantName.present ? variantName.value : this.variantName,
    sku: sku.present ? sku.value : this.sku,
    unitPricePaise: unitPricePaise ?? this.unitPricePaise,
    quantity: quantity ?? this.quantity,
    lineTotalPaise: lineTotalPaise ?? this.lineTotalPaise,
    offerDiscountPaise: offerDiscountPaise ?? this.offerDiscountPaise,
    appliedOfferId: appliedOfferId.present
        ? appliedOfferId.value
        : this.appliedOfferId,
    appliedOfferName: appliedOfferName.present
        ? appliedOfferName.value
        : this.appliedOfferName,
    appliedOfferType: appliedOfferType.present
        ? appliedOfferType.value
        : this.appliedOfferType,
  );
  SaleItem copyWithCompanion(SaleItemsCompanion data) {
    return SaleItem(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      productId: data.productId.present ? data.productId.value : this.productId,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      productName: data.productName.present
          ? data.productName.value
          : this.productName,
      variantName: data.variantName.present
          ? data.variantName.value
          : this.variantName,
      sku: data.sku.present ? data.sku.value : this.sku,
      unitPricePaise: data.unitPricePaise.present
          ? data.unitPricePaise.value
          : this.unitPricePaise,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      lineTotalPaise: data.lineTotalPaise.present
          ? data.lineTotalPaise.value
          : this.lineTotalPaise,
      offerDiscountPaise: data.offerDiscountPaise.present
          ? data.offerDiscountPaise.value
          : this.offerDiscountPaise,
      appliedOfferId: data.appliedOfferId.present
          ? data.appliedOfferId.value
          : this.appliedOfferId,
      appliedOfferName: data.appliedOfferName.present
          ? data.appliedOfferName.value
          : this.appliedOfferName,
      appliedOfferType: data.appliedOfferType.present
          ? data.appliedOfferType.value
          : this.appliedOfferType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaleItem(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('productName: $productName, ')
          ..write('variantName: $variantName, ')
          ..write('sku: $sku, ')
          ..write('unitPricePaise: $unitPricePaise, ')
          ..write('quantity: $quantity, ')
          ..write('lineTotalPaise: $lineTotalPaise, ')
          ..write('offerDiscountPaise: $offerDiscountPaise, ')
          ..write('appliedOfferId: $appliedOfferId, ')
          ..write('appliedOfferName: $appliedOfferName, ')
          ..write('appliedOfferType: $appliedOfferType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    saleId,
    productId,
    variantId,
    productName,
    variantName,
    sku,
    unitPricePaise,
    quantity,
    lineTotalPaise,
    offerDiscountPaise,
    appliedOfferId,
    appliedOfferName,
    appliedOfferType,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaleItem &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.saleId == this.saleId &&
          other.productId == this.productId &&
          other.variantId == this.variantId &&
          other.productName == this.productName &&
          other.variantName == this.variantName &&
          other.sku == this.sku &&
          other.unitPricePaise == this.unitPricePaise &&
          other.quantity == this.quantity &&
          other.lineTotalPaise == this.lineTotalPaise &&
          other.offerDiscountPaise == this.offerDiscountPaise &&
          other.appliedOfferId == this.appliedOfferId &&
          other.appliedOfferName == this.appliedOfferName &&
          other.appliedOfferType == this.appliedOfferType);
}

class SaleItemsCompanion extends UpdateCompanion<SaleItem> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> saleId;
  final Value<String> productId;
  final Value<String?> variantId;
  final Value<String> productName;
  final Value<String?> variantName;
  final Value<String?> sku;
  final Value<int> unitPricePaise;
  final Value<int> quantity;
  final Value<int> lineTotalPaise;
  final Value<int> offerDiscountPaise;
  final Value<String?> appliedOfferId;
  final Value<String?> appliedOfferName;
  final Value<String?> appliedOfferType;
  final Value<int> rowid;
  const SaleItemsCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.saleId = const Value.absent(),
    this.productId = const Value.absent(),
    this.variantId = const Value.absent(),
    this.productName = const Value.absent(),
    this.variantName = const Value.absent(),
    this.sku = const Value.absent(),
    this.unitPricePaise = const Value.absent(),
    this.quantity = const Value.absent(),
    this.lineTotalPaise = const Value.absent(),
    this.offerDiscountPaise = const Value.absent(),
    this.appliedOfferId = const Value.absent(),
    this.appliedOfferName = const Value.absent(),
    this.appliedOfferType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SaleItemsCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String saleId,
    required String productId,
    this.variantId = const Value.absent(),
    required String productName,
    this.variantName = const Value.absent(),
    this.sku = const Value.absent(),
    required int unitPricePaise,
    required int quantity,
    required int lineTotalPaise,
    this.offerDiscountPaise = const Value.absent(),
    this.appliedOfferId = const Value.absent(),
    this.appliedOfferName = const Value.absent(),
    this.appliedOfferType = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : saleId = Value(saleId),
       productId = Value(productId),
       productName = Value(productName),
       unitPricePaise = Value(unitPricePaise),
       quantity = Value(quantity),
       lineTotalPaise = Value(lineTotalPaise);
  static Insertable<SaleItem> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? saleId,
    Expression<String>? productId,
    Expression<String>? variantId,
    Expression<String>? productName,
    Expression<String>? variantName,
    Expression<String>? sku,
    Expression<int>? unitPricePaise,
    Expression<int>? quantity,
    Expression<int>? lineTotalPaise,
    Expression<int>? offerDiscountPaise,
    Expression<String>? appliedOfferId,
    Expression<String>? appliedOfferName,
    Expression<String>? appliedOfferType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (saleId != null) 'sale_id': saleId,
      if (productId != null) 'product_id': productId,
      if (variantId != null) 'variant_id': variantId,
      if (productName != null) 'product_name': productName,
      if (variantName != null) 'variant_name': variantName,
      if (sku != null) 'sku': sku,
      if (unitPricePaise != null) 'unit_price_paise': unitPricePaise,
      if (quantity != null) 'quantity': quantity,
      if (lineTotalPaise != null) 'line_total_paise': lineTotalPaise,
      if (offerDiscountPaise != null)
        'offer_discount_paise': offerDiscountPaise,
      if (appliedOfferId != null) 'applied_offer_id': appliedOfferId,
      if (appliedOfferName != null) 'applied_offer_name': appliedOfferName,
      if (appliedOfferType != null) 'applied_offer_type': appliedOfferType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SaleItemsCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? saleId,
    Value<String>? productId,
    Value<String?>? variantId,
    Value<String>? productName,
    Value<String?>? variantName,
    Value<String?>? sku,
    Value<int>? unitPricePaise,
    Value<int>? quantity,
    Value<int>? lineTotalPaise,
    Value<int>? offerDiscountPaise,
    Value<String?>? appliedOfferId,
    Value<String?>? appliedOfferName,
    Value<String?>? appliedOfferType,
    Value<int>? rowid,
  }) {
    return SaleItemsCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      saleId: saleId ?? this.saleId,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      variantName: variantName ?? this.variantName,
      sku: sku ?? this.sku,
      unitPricePaise: unitPricePaise ?? this.unitPricePaise,
      quantity: quantity ?? this.quantity,
      lineTotalPaise: lineTotalPaise ?? this.lineTotalPaise,
      offerDiscountPaise: offerDiscountPaise ?? this.offerDiscountPaise,
      appliedOfferId: appliedOfferId ?? this.appliedOfferId,
      appliedOfferName: appliedOfferName ?? this.appliedOfferName,
      appliedOfferType: appliedOfferType ?? this.appliedOfferType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<String>(variantId.value);
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (variantName.present) {
      map['variant_name'] = Variable<String>(variantName.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (unitPricePaise.present) {
      map['unit_price_paise'] = Variable<int>(unitPricePaise.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (lineTotalPaise.present) {
      map['line_total_paise'] = Variable<int>(lineTotalPaise.value);
    }
    if (offerDiscountPaise.present) {
      map['offer_discount_paise'] = Variable<int>(offerDiscountPaise.value);
    }
    if (appliedOfferId.present) {
      map['applied_offer_id'] = Variable<String>(appliedOfferId.value);
    }
    if (appliedOfferName.present) {
      map['applied_offer_name'] = Variable<String>(appliedOfferName.value);
    }
    if (appliedOfferType.present) {
      map['applied_offer_type'] = Variable<String>(appliedOfferType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SaleItemsCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('productName: $productName, ')
          ..write('variantName: $variantName, ')
          ..write('sku: $sku, ')
          ..write('unitPricePaise: $unitPricePaise, ')
          ..write('quantity: $quantity, ')
          ..write('lineTotalPaise: $lineTotalPaise, ')
          ..write('offerDiscountPaise: $offerDiscountPaise, ')
          ..write('appliedOfferId: $appliedOfferId, ')
          ..write('appliedOfferName: $appliedOfferName, ')
          ..write('appliedOfferType: $appliedOfferType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SaleSequencesTable extends SaleSequences
    with TableInfo<$SaleSequencesTable, SaleSequence> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SaleSequencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nextValueMeta = const VerificationMeta(
    'nextValue',
  );
  @override
  late final GeneratedColumn<int> nextValue = GeneratedColumn<int>(
    'next_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (next_value >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, shopId, nextValue];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sale_sequences';
  @override
  VerificationContext validateIntegrity(
    Insertable<SaleSequence> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('next_value')) {
      context.handle(
        _nextValueMeta,
        nextValue.isAcceptableOrUnknown(data['next_value']!, _nextValueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, shopId};
  @override
  SaleSequence map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaleSequence(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      nextValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_value'],
      )!,
    );
  }

  @override
  $SaleSequencesTable createAlias(String alias) {
    return $SaleSequencesTable(attachedDatabase, alias);
  }
}

class SaleSequence extends DataClass implements Insertable<SaleSequence> {
  /// Fixed row id: 'receipt'.
  final String id;

  /// Business/shop that owns this sequence.
  final String shopId;

  /// The next sequence value to hand out, seeded at 0 so the first receipt
  /// is 1. Must be >= 0.
  final int nextValue;
  const SaleSequence({
    required this.id,
    required this.shopId,
    required this.nextValue,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['shop_id'] = Variable<String>(shopId);
    map['next_value'] = Variable<int>(nextValue);
    return map;
  }

  SaleSequencesCompanion toCompanion(bool nullToAbsent) {
    return SaleSequencesCompanion(
      id: Value(id),
      shopId: Value(shopId),
      nextValue: Value(nextValue),
    );
  }

  factory SaleSequence.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaleSequence(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String>(json['shopId']),
      nextValue: serializer.fromJson<int>(json['nextValue']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String>(shopId),
      'nextValue': serializer.toJson<int>(nextValue),
    };
  }

  SaleSequence copyWith({String? id, String? shopId, int? nextValue}) =>
      SaleSequence(
        id: id ?? this.id,
        shopId: shopId ?? this.shopId,
        nextValue: nextValue ?? this.nextValue,
      );
  SaleSequence copyWithCompanion(SaleSequencesCompanion data) {
    return SaleSequence(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      nextValue: data.nextValue.present ? data.nextValue.value : this.nextValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaleSequence(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('nextValue: $nextValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, shopId, nextValue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaleSequence &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.nextValue == this.nextValue);
}

class SaleSequencesCompanion extends UpdateCompanion<SaleSequence> {
  final Value<String> id;
  final Value<String> shopId;
  final Value<int> nextValue;
  final Value<int> rowid;
  const SaleSequencesCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.nextValue = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SaleSequencesCompanion.insert({
    required String id,
    required String shopId,
    this.nextValue = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       shopId = Value(shopId);
  static Insertable<SaleSequence> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<int>? nextValue,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (nextValue != null) 'next_value': nextValue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SaleSequencesCompanion copyWith({
    Value<String>? id,
    Value<String>? shopId,
    Value<int>? nextValue,
    Value<int>? rowid,
  }) {
    return SaleSequencesCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      nextValue: nextValue ?? this.nextValue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (nextValue.present) {
      map['next_value'] = Variable<int>(nextValue.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SaleSequencesCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('nextValue: $nextValue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockMovementsTable extends StockMovements
    with TableInfo<$StockMovementsTable, StockMovement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockMovementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES products (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<String> variantId = GeneratedColumn<String>(
    'variant_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES product_variants (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _movementTypeMeta = const VerificationMeta(
    'movementType',
  );
  @override
  late final GeneratedColumn<String> movementType = GeneratedColumn<String>(
    'movement_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (movement_type IN (\'OPENING\', \'SALE\', \'PURCHASE\', \'ADJUSTMENT_IN\', \'ADJUSTMENT_OUT\'))',
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (quantity <> 0)',
  );
  static const VerificationMeta _stockBeforeMeta = const VerificationMeta(
    'stockBefore',
  );
  @override
  late final GeneratedColumn<int> stockBefore = GeneratedColumn<int>(
    'stock_before',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (stock_before >= 0)',
  );
  static const VerificationMeta _stockAfterMeta = const VerificationMeta(
    'stockAfter',
  );
  @override
  late final GeneratedColumn<int> stockAfter = GeneratedColumn<int>(
    'stock_after',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (stock_after >= 0)',
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (reason IS NULL OR reason IN (\'PURCHASE\', \'DAMAGE\', \'WASTAGE\', \'MISSING\', \'CORRECTION\', \'OTHER\'))',
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceTypeMeta = const VerificationMeta(
    'referenceType',
  );
  @override
  late final GeneratedColumn<String> referenceType = GeneratedColumn<String>(
    'reference_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceIdMeta = const VerificationMeta(
    'referenceId',
  );
  @override
  late final GeneratedColumn<String> referenceId = GeneratedColumn<String>(
    'reference_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    productId,
    variantId,
    movementType,
    quantity,
    stockBefore,
    stockAfter,
    reason,
    note,
    referenceType,
    referenceId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_movements';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockMovement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    }
    if (data.containsKey('movement_type')) {
      context.handle(
        _movementTypeMeta,
        movementType.isAcceptableOrUnknown(
          data['movement_type']!,
          _movementTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_movementTypeMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('stock_before')) {
      context.handle(
        _stockBeforeMeta,
        stockBefore.isAcceptableOrUnknown(
          data['stock_before']!,
          _stockBeforeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_stockBeforeMeta);
    }
    if (data.containsKey('stock_after')) {
      context.handle(
        _stockAfterMeta,
        stockAfter.isAcceptableOrUnknown(data['stock_after']!, _stockAfterMeta),
      );
    } else if (isInserting) {
      context.missing(_stockAfterMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('reference_type')) {
      context.handle(
        _referenceTypeMeta,
        referenceType.isAcceptableOrUnknown(
          data['reference_type']!,
          _referenceTypeMeta,
        ),
      );
    }
    if (data.containsKey('reference_id')) {
      context.handle(
        _referenceIdMeta,
        referenceId.isAcceptableOrUnknown(
          data['reference_id']!,
          _referenceIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockMovement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockMovement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_id'],
      ),
      movementType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}movement_type'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      stockBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stock_before'],
      )!,
      stockAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stock_after'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      referenceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_type'],
      ),
      referenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StockMovementsTable createAlias(String alias) {
    return $StockMovementsTable(attachedDatabase, alias);
  }
}

class StockMovement extends DataClass implements Insertable<StockMovement> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this movement.
  final String? shopId;

  /// The product the movement belongs to. Products are never hard-deleted
  /// (soft deactivation instead); RESTRICT keeps history bound to its owner.
  final String productId;

  /// The variant the movement belongs to; NULL for movements against the
  /// product itself. Variants are never hard-deleted (soft deactivation
  /// instead); RESTRICT keeps history bound to its owner.
  final String? variantId;

  /// What happened to stock: OPENING, SALE, PURCHASE, ADJUSTMENT_IN or
  /// ADJUSTMENT_OUT.
  final String movementType;

  /// Signed delta applied to stock; never zero.
  final int quantity;

  /// Stock level before the movement. Must be >= 0.
  final int stockBefore;

  /// Stock level after the movement. Must be >= 0.
  final int stockAfter;

  /// Why an adjustment happened; NULL unless the movement is an adjustment.
  final String? reason;

  /// Optional free-form note; NULL when blank.
  final String? note;

  /// Kind of referenced record (e.g. 'SALE'); NULL for standalone movements.
  final String? referenceType;

  /// Id of the referenced record (e.g. sales.id); NULL for standalone
  /// movements. Audit reference only — no database FK.
  final String? referenceId;

  /// UTC timestamp of the movement.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const StockMovement({
    required this.id,
    this.shopId,
    required this.productId,
    this.variantId,
    required this.movementType,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    this.reason,
    this.note,
    this.referenceType,
    this.referenceId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['product_id'] = Variable<String>(productId);
    if (!nullToAbsent || variantId != null) {
      map['variant_id'] = Variable<String>(variantId);
    }
    map['movement_type'] = Variable<String>(movementType);
    map['quantity'] = Variable<int>(quantity);
    map['stock_before'] = Variable<int>(stockBefore);
    map['stock_after'] = Variable<int>(stockAfter);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || referenceType != null) {
      map['reference_type'] = Variable<String>(referenceType);
    }
    if (!nullToAbsent || referenceId != null) {
      map['reference_id'] = Variable<String>(referenceId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StockMovementsCompanion toCompanion(bool nullToAbsent) {
    return StockMovementsCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      productId: Value(productId),
      variantId: variantId == null && nullToAbsent
          ? const Value.absent()
          : Value(variantId),
      movementType: Value(movementType),
      quantity: Value(quantity),
      stockBefore: Value(stockBefore),
      stockAfter: Value(stockAfter),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      referenceType: referenceType == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceType),
      referenceId: referenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory StockMovement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockMovement(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      productId: serializer.fromJson<String>(json['productId']),
      variantId: serializer.fromJson<String?>(json['variantId']),
      movementType: serializer.fromJson<String>(json['movementType']),
      quantity: serializer.fromJson<int>(json['quantity']),
      stockBefore: serializer.fromJson<int>(json['stockBefore']),
      stockAfter: serializer.fromJson<int>(json['stockAfter']),
      reason: serializer.fromJson<String?>(json['reason']),
      note: serializer.fromJson<String?>(json['note']),
      referenceType: serializer.fromJson<String?>(json['referenceType']),
      referenceId: serializer.fromJson<String?>(json['referenceId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'productId': serializer.toJson<String>(productId),
      'variantId': serializer.toJson<String?>(variantId),
      'movementType': serializer.toJson<String>(movementType),
      'quantity': serializer.toJson<int>(quantity),
      'stockBefore': serializer.toJson<int>(stockBefore),
      'stockAfter': serializer.toJson<int>(stockAfter),
      'reason': serializer.toJson<String?>(reason),
      'note': serializer.toJson<String?>(note),
      'referenceType': serializer.toJson<String?>(referenceType),
      'referenceId': serializer.toJson<String?>(referenceId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  StockMovement copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? productId,
    Value<String?> variantId = const Value.absent(),
    String? movementType,
    int? quantity,
    int? stockBefore,
    int? stockAfter,
    Value<String?> reason = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<String?> referenceType = const Value.absent(),
    Value<String?> referenceId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => StockMovement(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    productId: productId ?? this.productId,
    variantId: variantId.present ? variantId.value : this.variantId,
    movementType: movementType ?? this.movementType,
    quantity: quantity ?? this.quantity,
    stockBefore: stockBefore ?? this.stockBefore,
    stockAfter: stockAfter ?? this.stockAfter,
    reason: reason.present ? reason.value : this.reason,
    note: note.present ? note.value : this.note,
    referenceType: referenceType.present
        ? referenceType.value
        : this.referenceType,
    referenceId: referenceId.present ? referenceId.value : this.referenceId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StockMovement copyWithCompanion(StockMovementsCompanion data) {
    return StockMovement(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      productId: data.productId.present ? data.productId.value : this.productId,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      movementType: data.movementType.present
          ? data.movementType.value
          : this.movementType,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      stockBefore: data.stockBefore.present
          ? data.stockBefore.value
          : this.stockBefore,
      stockAfter: data.stockAfter.present
          ? data.stockAfter.value
          : this.stockAfter,
      reason: data.reason.present ? data.reason.value : this.reason,
      note: data.note.present ? data.note.value : this.note,
      referenceType: data.referenceType.present
          ? data.referenceType.value
          : this.referenceType,
      referenceId: data.referenceId.present
          ? data.referenceId.value
          : this.referenceId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockMovement(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('movementType: $movementType, ')
          ..write('quantity: $quantity, ')
          ..write('stockBefore: $stockBefore, ')
          ..write('stockAfter: $stockAfter, ')
          ..write('reason: $reason, ')
          ..write('note: $note, ')
          ..write('referenceType: $referenceType, ')
          ..write('referenceId: $referenceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    productId,
    variantId,
    movementType,
    quantity,
    stockBefore,
    stockAfter,
    reason,
    note,
    referenceType,
    referenceId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockMovement &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.productId == this.productId &&
          other.variantId == this.variantId &&
          other.movementType == this.movementType &&
          other.quantity == this.quantity &&
          other.stockBefore == this.stockBefore &&
          other.stockAfter == this.stockAfter &&
          other.reason == this.reason &&
          other.note == this.note &&
          other.referenceType == this.referenceType &&
          other.referenceId == this.referenceId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StockMovementsCompanion extends UpdateCompanion<StockMovement> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> productId;
  final Value<String?> variantId;
  final Value<String> movementType;
  final Value<int> quantity;
  final Value<int> stockBefore;
  final Value<int> stockAfter;
  final Value<String?> reason;
  final Value<String?> note;
  final Value<String?> referenceType;
  final Value<String?> referenceId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const StockMovementsCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.productId = const Value.absent(),
    this.variantId = const Value.absent(),
    this.movementType = const Value.absent(),
    this.quantity = const Value.absent(),
    this.stockBefore = const Value.absent(),
    this.stockAfter = const Value.absent(),
    this.reason = const Value.absent(),
    this.note = const Value.absent(),
    this.referenceType = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockMovementsCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String productId,
    this.variantId = const Value.absent(),
    required String movementType,
    required int quantity,
    required int stockBefore,
    required int stockAfter,
    this.reason = const Value.absent(),
    this.note = const Value.absent(),
    this.referenceType = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : productId = Value(productId),
       movementType = Value(movementType),
       quantity = Value(quantity),
       stockBefore = Value(stockBefore),
       stockAfter = Value(stockAfter);
  static Insertable<StockMovement> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? productId,
    Expression<String>? variantId,
    Expression<String>? movementType,
    Expression<int>? quantity,
    Expression<int>? stockBefore,
    Expression<int>? stockAfter,
    Expression<String>? reason,
    Expression<String>? note,
    Expression<String>? referenceType,
    Expression<String>? referenceId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (productId != null) 'product_id': productId,
      if (variantId != null) 'variant_id': variantId,
      if (movementType != null) 'movement_type': movementType,
      if (quantity != null) 'quantity': quantity,
      if (stockBefore != null) 'stock_before': stockBefore,
      if (stockAfter != null) 'stock_after': stockAfter,
      if (reason != null) 'reason': reason,
      if (note != null) 'note': note,
      if (referenceType != null) 'reference_type': referenceType,
      if (referenceId != null) 'reference_id': referenceId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockMovementsCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? productId,
    Value<String?>? variantId,
    Value<String>? movementType,
    Value<int>? quantity,
    Value<int>? stockBefore,
    Value<int>? stockAfter,
    Value<String?>? reason,
    Value<String?>? note,
    Value<String?>? referenceType,
    Value<String?>? referenceId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return StockMovementsCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      movementType: movementType ?? this.movementType,
      quantity: quantity ?? this.quantity,
      stockBefore: stockBefore ?? this.stockBefore,
      stockAfter: stockAfter ?? this.stockAfter,
      reason: reason ?? this.reason,
      note: note ?? this.note,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<String>(variantId.value);
    }
    if (movementType.present) {
      map['movement_type'] = Variable<String>(movementType.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (stockBefore.present) {
      map['stock_before'] = Variable<int>(stockBefore.value);
    }
    if (stockAfter.present) {
      map['stock_after'] = Variable<int>(stockAfter.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (referenceType.present) {
      map['reference_type'] = Variable<String>(referenceType.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<String>(referenceId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockMovementsCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('movementType: $movementType, ')
          ..write('quantity: $quantity, ')
          ..write('stockBefore: $stockBefore, ')
          ..write('stockAfter: $stockAfter, ')
          ..write('reason: $reason, ')
          ..write('note: $note, ')
          ..write('referenceType: $referenceType, ')
          ..write('referenceId: $referenceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SuppliersTable extends Suppliers
    with TableInfo<$SuppliersTable, Supplier> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SuppliersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    name,
    phone,
    email,
    address,
    notes,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'suppliers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Supplier> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Supplier map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Supplier(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SuppliersTable createAlias(String alias) {
    return $SuppliersTable(attachedDatabase, alias);
  }
}

class Supplier extends DataClass implements Insertable<Supplier> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this supplier.
  final String? shopId;

  /// Supplier display name.
  final String name;

  /// Phone number; optional. Unique when present (SQLite unique indexes
  /// treat NULLs as distinct). Case-insensitive uniqueness is enforced by
  /// the repository before insert/update.
  final String? phone;

  /// Email address; optional. Not unique — a business may share an inbox.
  final String? email;

  /// Billing/delivery address; optional.
  final String? address;

  /// Optional free-form note about the supplier.
  final String? notes;

  /// Soft switch to hide a supplier without deleting their records.
  final bool isActive;

  /// UTC timestamp of record creation.
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const Supplier({
    required this.id,
    this.shopId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SuppliersCompanion toCompanion(bool nullToAbsent) {
    return SuppliersCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Supplier.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Supplier(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      email: serializer.fromJson<String?>(json['email']),
      address: serializer.fromJson<String?>(json['address']),
      notes: serializer.fromJson<String?>(json['notes']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'email': serializer.toJson<String?>(email),
      'address': serializer.toJson<String?>(address),
      'notes': serializer.toJson<String?>(notes),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Supplier copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Supplier(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    email: email.present ? email.value : this.email,
    address: address.present ? address.value : this.address,
    notes: notes.present ? notes.value : this.notes,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Supplier copyWithCompanion(SuppliersCompanion data) {
    return Supplier(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      email: data.email.present ? data.email.value : this.email,
      address: data.address.present ? data.address.value : this.address,
      notes: data.notes.present ? data.notes.value : this.notes,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Supplier(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('address: $address, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    name,
    phone,
    email,
    address,
    notes,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Supplier &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.email == this.email &&
          other.address == this.address &&
          other.notes == this.notes &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SuppliersCompanion extends UpdateCompanion<Supplier> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> email;
  final Value<String?> address;
  final Value<String?> notes;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SuppliersCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.address = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SuppliersCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String name,
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.address = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Supplier> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? email,
    Expression<String>? address,
    Expression<String>? notes,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
      if (notes != null) 'notes': notes,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SuppliersCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? email,
    Value<String?>? address,
    Value<String?>? notes,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SuppliersCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SuppliersCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('address: $address, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchasesTable extends Purchases
    with TableInfo<$PurchasesTable, Purchase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _supplierIdMeta = const VerificationMeta(
    'supplierId',
  );
  @override
  late final GeneratedColumn<String> supplierId = GeneratedColumn<String>(
    'supplier_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES suppliers (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _purchaseNumberMeta = const VerificationMeta(
    'purchaseNumber',
  );
  @override
  late final GeneratedColumn<String> purchaseNumber = GeneratedColumn<String>(
    'purchase_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subtotalPaiseMeta = const VerificationMeta(
    'subtotalPaise',
  );
  @override
  late final GeneratedColumn<int> subtotalPaise = GeneratedColumn<int>(
    'subtotal_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (subtotal_paise >= 0)',
  );
  static const VerificationMeta _totalPaiseMeta = const VerificationMeta(
    'totalPaise',
  );
  @override
  late final GeneratedColumn<int> totalPaise = GeneratedColumn<int>(
    'total_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (total_paise >= 0)',
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    supplierId,
    purchaseNumber,
    subtotalPaise,
    totalPaise,
    notes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchases';
  @override
  VerificationContext validateIntegrity(
    Insertable<Purchase> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('supplier_id')) {
      context.handle(
        _supplierIdMeta,
        supplierId.isAcceptableOrUnknown(data['supplier_id']!, _supplierIdMeta),
      );
    }
    if (data.containsKey('purchase_number')) {
      context.handle(
        _purchaseNumberMeta,
        purchaseNumber.isAcceptableOrUnknown(
          data['purchase_number']!,
          _purchaseNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_purchaseNumberMeta);
    }
    if (data.containsKey('subtotal_paise')) {
      context.handle(
        _subtotalPaiseMeta,
        subtotalPaise.isAcceptableOrUnknown(
          data['subtotal_paise']!,
          _subtotalPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_subtotalPaiseMeta);
    }
    if (data.containsKey('total_paise')) {
      context.handle(
        _totalPaiseMeta,
        totalPaise.isAcceptableOrUnknown(data['total_paise']!, _totalPaiseMeta),
      );
    } else if (isInserting) {
      context.missing(_totalPaiseMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {shopId, purchaseNumber},
  ];
  @override
  Purchase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Purchase(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      supplierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supplier_id'],
      ),
      purchaseNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purchase_number'],
      )!,
      subtotalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subtotal_paise'],
      )!,
      totalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_paise'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PurchasesTable createAlias(String alias) {
    return $PurchasesTable(attachedDatabase, alias);
  }
}

class Purchase extends DataClass implements Insertable<Purchase> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this purchase.
  final String? shopId;

  /// Owning supplier for supplier-linked purchases; NULL for walk-ins.
  /// Deleting a supplier with purchase history is rejected (RESTRICT).
  final String? supplierId;

  /// Human-readable purchase reference; unique per shop.
  final String purchaseNumber;

  /// Sum of line totals in paise, before any adjustments. Must be >= 0.
  final int subtotalPaise;

  /// Amount recorded in paise. Equals the subtotal (no discounts/taxes yet).
  final int totalPaise;

  /// Optional free-form note about the purchase.
  final String? notes;

  /// UTC timestamp of the purchase (the receiving transaction).
  final DateTime createdAt;

  /// UTC timestamp of the last change; drives future sync.
  final DateTime updatedAt;
  const Purchase({
    required this.id,
    this.shopId,
    this.supplierId,
    required this.purchaseNumber,
    required this.subtotalPaise,
    required this.totalPaise,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    if (!nullToAbsent || supplierId != null) {
      map['supplier_id'] = Variable<String>(supplierId);
    }
    map['purchase_number'] = Variable<String>(purchaseNumber);
    map['subtotal_paise'] = Variable<int>(subtotalPaise);
    map['total_paise'] = Variable<int>(totalPaise);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PurchasesCompanion toCompanion(bool nullToAbsent) {
    return PurchasesCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      supplierId: supplierId == null && nullToAbsent
          ? const Value.absent()
          : Value(supplierId),
      purchaseNumber: Value(purchaseNumber),
      subtotalPaise: Value(subtotalPaise),
      totalPaise: Value(totalPaise),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Purchase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Purchase(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      supplierId: serializer.fromJson<String?>(json['supplierId']),
      purchaseNumber: serializer.fromJson<String>(json['purchaseNumber']),
      subtotalPaise: serializer.fromJson<int>(json['subtotalPaise']),
      totalPaise: serializer.fromJson<int>(json['totalPaise']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'supplierId': serializer.toJson<String?>(supplierId),
      'purchaseNumber': serializer.toJson<String>(purchaseNumber),
      'subtotalPaise': serializer.toJson<int>(subtotalPaise),
      'totalPaise': serializer.toJson<int>(totalPaise),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Purchase copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    Value<String?> supplierId = const Value.absent(),
    String? purchaseNumber,
    int? subtotalPaise,
    int? totalPaise,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Purchase(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    supplierId: supplierId.present ? supplierId.value : this.supplierId,
    purchaseNumber: purchaseNumber ?? this.purchaseNumber,
    subtotalPaise: subtotalPaise ?? this.subtotalPaise,
    totalPaise: totalPaise ?? this.totalPaise,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Purchase copyWithCompanion(PurchasesCompanion data) {
    return Purchase(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      supplierId: data.supplierId.present
          ? data.supplierId.value
          : this.supplierId,
      purchaseNumber: data.purchaseNumber.present
          ? data.purchaseNumber.value
          : this.purchaseNumber,
      subtotalPaise: data.subtotalPaise.present
          ? data.subtotalPaise.value
          : this.subtotalPaise,
      totalPaise: data.totalPaise.present
          ? data.totalPaise.value
          : this.totalPaise,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Purchase(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('supplierId: $supplierId, ')
          ..write('purchaseNumber: $purchaseNumber, ')
          ..write('subtotalPaise: $subtotalPaise, ')
          ..write('totalPaise: $totalPaise, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    supplierId,
    purchaseNumber,
    subtotalPaise,
    totalPaise,
    notes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Purchase &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.supplierId == this.supplierId &&
          other.purchaseNumber == this.purchaseNumber &&
          other.subtotalPaise == this.subtotalPaise &&
          other.totalPaise == this.totalPaise &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PurchasesCompanion extends UpdateCompanion<Purchase> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String?> supplierId;
  final Value<String> purchaseNumber;
  final Value<int> subtotalPaise;
  final Value<int> totalPaise;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PurchasesCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.supplierId = const Value.absent(),
    this.purchaseNumber = const Value.absent(),
    this.subtotalPaise = const Value.absent(),
    this.totalPaise = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchasesCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.supplierId = const Value.absent(),
    required String purchaseNumber,
    required int subtotalPaise,
    required int totalPaise,
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : purchaseNumber = Value(purchaseNumber),
       subtotalPaise = Value(subtotalPaise),
       totalPaise = Value(totalPaise);
  static Insertable<Purchase> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? supplierId,
    Expression<String>? purchaseNumber,
    Expression<int>? subtotalPaise,
    Expression<int>? totalPaise,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (supplierId != null) 'supplier_id': supplierId,
      if (purchaseNumber != null) 'purchase_number': purchaseNumber,
      if (subtotalPaise != null) 'subtotal_paise': subtotalPaise,
      if (totalPaise != null) 'total_paise': totalPaise,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchasesCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String?>? supplierId,
    Value<String>? purchaseNumber,
    Value<int>? subtotalPaise,
    Value<int>? totalPaise,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PurchasesCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      supplierId: supplierId ?? this.supplierId,
      purchaseNumber: purchaseNumber ?? this.purchaseNumber,
      subtotalPaise: subtotalPaise ?? this.subtotalPaise,
      totalPaise: totalPaise ?? this.totalPaise,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (supplierId.present) {
      map['supplier_id'] = Variable<String>(supplierId.value);
    }
    if (purchaseNumber.present) {
      map['purchase_number'] = Variable<String>(purchaseNumber.value);
    }
    if (subtotalPaise.present) {
      map['subtotal_paise'] = Variable<int>(subtotalPaise.value);
    }
    if (totalPaise.present) {
      map['total_paise'] = Variable<int>(totalPaise.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchasesCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('supplierId: $supplierId, ')
          ..write('purchaseNumber: $purchaseNumber, ')
          ..write('subtotalPaise: $subtotalPaise, ')
          ..write('totalPaise: $totalPaise, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchaseItemsTable extends PurchaseItems
    with TableInfo<$PurchaseItemsTable, PurchaseItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchaseItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _purchaseIdMeta = const VerificationMeta(
    'purchaseId',
  );
  @override
  late final GeneratedColumn<String> purchaseId = GeneratedColumn<String>(
    'purchase_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES purchases (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES products (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<String> variantId = GeneratedColumn<String>(
    'variant_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES product_variants (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _productNameMeta = const VerificationMeta(
    'productName',
  );
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
    'product_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantNameMeta = const VerificationMeta(
    'variantName',
  );
  @override
  late final GeneratedColumn<String> variantName = GeneratedColumn<String>(
    'variant_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitCostPaiseMeta = const VerificationMeta(
    'unitCostPaise',
  );
  @override
  late final GeneratedColumn<int> unitCostPaise = GeneratedColumn<int>(
    'unit_cost_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (unit_cost_paise >= 0)',
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (quantity > 0)',
  );
  static const VerificationMeta _lineTotalPaiseMeta = const VerificationMeta(
    'lineTotalPaise',
  );
  @override
  late final GeneratedColumn<int> lineTotalPaise = GeneratedColumn<int>(
    'line_total_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (line_total_paise >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    purchaseId,
    productId,
    variantId,
    productName,
    variantName,
    sku,
    unitCostPaise,
    quantity,
    lineTotalPaise,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchase_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<PurchaseItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('purchase_id')) {
      context.handle(
        _purchaseIdMeta,
        purchaseId.isAcceptableOrUnknown(data['purchase_id']!, _purchaseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_purchaseIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    }
    if (data.containsKey('product_name')) {
      context.handle(
        _productNameMeta,
        productName.isAcceptableOrUnknown(
          data['product_name']!,
          _productNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_productNameMeta);
    }
    if (data.containsKey('variant_name')) {
      context.handle(
        _variantNameMeta,
        variantName.isAcceptableOrUnknown(
          data['variant_name']!,
          _variantNameMeta,
        ),
      );
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    }
    if (data.containsKey('unit_cost_paise')) {
      context.handle(
        _unitCostPaiseMeta,
        unitCostPaise.isAcceptableOrUnknown(
          data['unit_cost_paise']!,
          _unitCostPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unitCostPaiseMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('line_total_paise')) {
      context.handle(
        _lineTotalPaiseMeta,
        lineTotalPaise.isAcceptableOrUnknown(
          data['line_total_paise']!,
          _lineTotalPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lineTotalPaiseMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PurchaseItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PurchaseItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      purchaseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purchase_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_id'],
      ),
      productName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_name'],
      )!,
      variantName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_name'],
      ),
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      ),
      unitCostPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_cost_paise'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      lineTotalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_total_paise'],
      )!,
    );
  }

  @override
  $PurchaseItemsTable createAlias(String alias) {
    return $PurchaseItemsTable(attachedDatabase, alias);
  }
}

class PurchaseItem extends DataClass implements Insertable<PurchaseItem> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this purchase item.
  final String? shopId;

  /// Owning purchase. Deleting a purchase with items is rejected (RESTRICT).
  final String purchaseId;

  /// Product received. Deleting a product with purchase history is rejected.
  final String productId;

  /// Variant received; NULL for non-variant lines. RESTRICT protects history.
  final String? variantId;

  /// Product name at the time of the purchase (snapshot).
  final String productName;

  /// Variant name at the time of the purchase (snapshot); NULL when the line
  /// is not a variant line.
  final String? variantName;

  /// Product SKU at the time of the purchase (snapshot); NULL when absent.
  final String? sku;

  /// Unit cost price in paise at purchase time. Must be >= 0.
  final int unitCostPaise;

  /// Quantity received. Must be > 0.
  final int quantity;

  /// unitCostPaise * quantity in paise. Must be >= 0.
  final int lineTotalPaise;
  const PurchaseItem({
    required this.id,
    this.shopId,
    required this.purchaseId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantName,
    this.sku,
    required this.unitCostPaise,
    required this.quantity,
    required this.lineTotalPaise,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['purchase_id'] = Variable<String>(purchaseId);
    map['product_id'] = Variable<String>(productId);
    if (!nullToAbsent || variantId != null) {
      map['variant_id'] = Variable<String>(variantId);
    }
    map['product_name'] = Variable<String>(productName);
    if (!nullToAbsent || variantName != null) {
      map['variant_name'] = Variable<String>(variantName);
    }
    if (!nullToAbsent || sku != null) {
      map['sku'] = Variable<String>(sku);
    }
    map['unit_cost_paise'] = Variable<int>(unitCostPaise);
    map['quantity'] = Variable<int>(quantity);
    map['line_total_paise'] = Variable<int>(lineTotalPaise);
    return map;
  }

  PurchaseItemsCompanion toCompanion(bool nullToAbsent) {
    return PurchaseItemsCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      purchaseId: Value(purchaseId),
      productId: Value(productId),
      variantId: variantId == null && nullToAbsent
          ? const Value.absent()
          : Value(variantId),
      productName: Value(productName),
      variantName: variantName == null && nullToAbsent
          ? const Value.absent()
          : Value(variantName),
      sku: sku == null && nullToAbsent ? const Value.absent() : Value(sku),
      unitCostPaise: Value(unitCostPaise),
      quantity: Value(quantity),
      lineTotalPaise: Value(lineTotalPaise),
    );
  }

  factory PurchaseItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PurchaseItem(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      purchaseId: serializer.fromJson<String>(json['purchaseId']),
      productId: serializer.fromJson<String>(json['productId']),
      variantId: serializer.fromJson<String?>(json['variantId']),
      productName: serializer.fromJson<String>(json['productName']),
      variantName: serializer.fromJson<String?>(json['variantName']),
      sku: serializer.fromJson<String?>(json['sku']),
      unitCostPaise: serializer.fromJson<int>(json['unitCostPaise']),
      quantity: serializer.fromJson<int>(json['quantity']),
      lineTotalPaise: serializer.fromJson<int>(json['lineTotalPaise']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'purchaseId': serializer.toJson<String>(purchaseId),
      'productId': serializer.toJson<String>(productId),
      'variantId': serializer.toJson<String?>(variantId),
      'productName': serializer.toJson<String>(productName),
      'variantName': serializer.toJson<String?>(variantName),
      'sku': serializer.toJson<String?>(sku),
      'unitCostPaise': serializer.toJson<int>(unitCostPaise),
      'quantity': serializer.toJson<int>(quantity),
      'lineTotalPaise': serializer.toJson<int>(lineTotalPaise),
    };
  }

  PurchaseItem copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? purchaseId,
    String? productId,
    Value<String?> variantId = const Value.absent(),
    String? productName,
    Value<String?> variantName = const Value.absent(),
    Value<String?> sku = const Value.absent(),
    int? unitCostPaise,
    int? quantity,
    int? lineTotalPaise,
  }) => PurchaseItem(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    purchaseId: purchaseId ?? this.purchaseId,
    productId: productId ?? this.productId,
    variantId: variantId.present ? variantId.value : this.variantId,
    productName: productName ?? this.productName,
    variantName: variantName.present ? variantName.value : this.variantName,
    sku: sku.present ? sku.value : this.sku,
    unitCostPaise: unitCostPaise ?? this.unitCostPaise,
    quantity: quantity ?? this.quantity,
    lineTotalPaise: lineTotalPaise ?? this.lineTotalPaise,
  );
  PurchaseItem copyWithCompanion(PurchaseItemsCompanion data) {
    return PurchaseItem(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      purchaseId: data.purchaseId.present
          ? data.purchaseId.value
          : this.purchaseId,
      productId: data.productId.present ? data.productId.value : this.productId,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      productName: data.productName.present
          ? data.productName.value
          : this.productName,
      variantName: data.variantName.present
          ? data.variantName.value
          : this.variantName,
      sku: data.sku.present ? data.sku.value : this.sku,
      unitCostPaise: data.unitCostPaise.present
          ? data.unitCostPaise.value
          : this.unitCostPaise,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      lineTotalPaise: data.lineTotalPaise.present
          ? data.lineTotalPaise.value
          : this.lineTotalPaise,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseItem(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('purchaseId: $purchaseId, ')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('productName: $productName, ')
          ..write('variantName: $variantName, ')
          ..write('sku: $sku, ')
          ..write('unitCostPaise: $unitCostPaise, ')
          ..write('quantity: $quantity, ')
          ..write('lineTotalPaise: $lineTotalPaise')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    purchaseId,
    productId,
    variantId,
    productName,
    variantName,
    sku,
    unitCostPaise,
    quantity,
    lineTotalPaise,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseItem &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.purchaseId == this.purchaseId &&
          other.productId == this.productId &&
          other.variantId == this.variantId &&
          other.productName == this.productName &&
          other.variantName == this.variantName &&
          other.sku == this.sku &&
          other.unitCostPaise == this.unitCostPaise &&
          other.quantity == this.quantity &&
          other.lineTotalPaise == this.lineTotalPaise);
}

class PurchaseItemsCompanion extends UpdateCompanion<PurchaseItem> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> purchaseId;
  final Value<String> productId;
  final Value<String?> variantId;
  final Value<String> productName;
  final Value<String?> variantName;
  final Value<String?> sku;
  final Value<int> unitCostPaise;
  final Value<int> quantity;
  final Value<int> lineTotalPaise;
  final Value<int> rowid;
  const PurchaseItemsCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.purchaseId = const Value.absent(),
    this.productId = const Value.absent(),
    this.variantId = const Value.absent(),
    this.productName = const Value.absent(),
    this.variantName = const Value.absent(),
    this.sku = const Value.absent(),
    this.unitCostPaise = const Value.absent(),
    this.quantity = const Value.absent(),
    this.lineTotalPaise = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchaseItemsCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String purchaseId,
    required String productId,
    this.variantId = const Value.absent(),
    required String productName,
    this.variantName = const Value.absent(),
    this.sku = const Value.absent(),
    required int unitCostPaise,
    required int quantity,
    required int lineTotalPaise,
    this.rowid = const Value.absent(),
  }) : purchaseId = Value(purchaseId),
       productId = Value(productId),
       productName = Value(productName),
       unitCostPaise = Value(unitCostPaise),
       quantity = Value(quantity),
       lineTotalPaise = Value(lineTotalPaise);
  static Insertable<PurchaseItem> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? purchaseId,
    Expression<String>? productId,
    Expression<String>? variantId,
    Expression<String>? productName,
    Expression<String>? variantName,
    Expression<String>? sku,
    Expression<int>? unitCostPaise,
    Expression<int>? quantity,
    Expression<int>? lineTotalPaise,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (purchaseId != null) 'purchase_id': purchaseId,
      if (productId != null) 'product_id': productId,
      if (variantId != null) 'variant_id': variantId,
      if (productName != null) 'product_name': productName,
      if (variantName != null) 'variant_name': variantName,
      if (sku != null) 'sku': sku,
      if (unitCostPaise != null) 'unit_cost_paise': unitCostPaise,
      if (quantity != null) 'quantity': quantity,
      if (lineTotalPaise != null) 'line_total_paise': lineTotalPaise,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchaseItemsCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? purchaseId,
    Value<String>? productId,
    Value<String?>? variantId,
    Value<String>? productName,
    Value<String?>? variantName,
    Value<String?>? sku,
    Value<int>? unitCostPaise,
    Value<int>? quantity,
    Value<int>? lineTotalPaise,
    Value<int>? rowid,
  }) {
    return PurchaseItemsCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      purchaseId: purchaseId ?? this.purchaseId,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      variantName: variantName ?? this.variantName,
      sku: sku ?? this.sku,
      unitCostPaise: unitCostPaise ?? this.unitCostPaise,
      quantity: quantity ?? this.quantity,
      lineTotalPaise: lineTotalPaise ?? this.lineTotalPaise,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (purchaseId.present) {
      map['purchase_id'] = Variable<String>(purchaseId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<String>(variantId.value);
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (variantName.present) {
      map['variant_name'] = Variable<String>(variantName.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (unitCostPaise.present) {
      map['unit_cost_paise'] = Variable<int>(unitCostPaise.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (lineTotalPaise.present) {
      map['line_total_paise'] = Variable<int>(lineTotalPaise.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseItemsCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('purchaseId: $purchaseId, ')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('productName: $productName, ')
          ..write('variantName: $variantName, ')
          ..write('sku: $sku, ')
          ..write('unitCostPaise: $unitCostPaise, ')
          ..write('quantity: $quantity, ')
          ..write('lineTotalPaise: $lineTotalPaise, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchaseSequencesTable extends PurchaseSequences
    with TableInfo<$PurchaseSequencesTable, PurchaseSequence> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchaseSequencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nextValueMeta = const VerificationMeta(
    'nextValue',
  );
  @override
  late final GeneratedColumn<int> nextValue = GeneratedColumn<int>(
    'next_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (next_value >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, shopId, nextValue];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchase_sequences';
  @override
  VerificationContext validateIntegrity(
    Insertable<PurchaseSequence> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('next_value')) {
      context.handle(
        _nextValueMeta,
        nextValue.isAcceptableOrUnknown(data['next_value']!, _nextValueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, shopId};
  @override
  PurchaseSequence map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PurchaseSequence(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      nextValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_value'],
      )!,
    );
  }

  @override
  $PurchaseSequencesTable createAlias(String alias) {
    return $PurchaseSequencesTable(attachedDatabase, alias);
  }
}

class PurchaseSequence extends DataClass
    implements Insertable<PurchaseSequence> {
  /// Fixed row id: 'purchase'.
  final String id;

  /// Business/shop that owns this sequence.
  final String shopId;

  /// The next sequence value to hand out, seeded at 0 so the first purchase
  /// is 1. Must be >= 0.
  final int nextValue;
  const PurchaseSequence({
    required this.id,
    required this.shopId,
    required this.nextValue,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['shop_id'] = Variable<String>(shopId);
    map['next_value'] = Variable<int>(nextValue);
    return map;
  }

  PurchaseSequencesCompanion toCompanion(bool nullToAbsent) {
    return PurchaseSequencesCompanion(
      id: Value(id),
      shopId: Value(shopId),
      nextValue: Value(nextValue),
    );
  }

  factory PurchaseSequence.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PurchaseSequence(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String>(json['shopId']),
      nextValue: serializer.fromJson<int>(json['nextValue']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String>(shopId),
      'nextValue': serializer.toJson<int>(nextValue),
    };
  }

  PurchaseSequence copyWith({String? id, String? shopId, int? nextValue}) =>
      PurchaseSequence(
        id: id ?? this.id,
        shopId: shopId ?? this.shopId,
        nextValue: nextValue ?? this.nextValue,
      );
  PurchaseSequence copyWithCompanion(PurchaseSequencesCompanion data) {
    return PurchaseSequence(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      nextValue: data.nextValue.present ? data.nextValue.value : this.nextValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseSequence(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('nextValue: $nextValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, shopId, nextValue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseSequence &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.nextValue == this.nextValue);
}

class PurchaseSequencesCompanion extends UpdateCompanion<PurchaseSequence> {
  final Value<String> id;
  final Value<String> shopId;
  final Value<int> nextValue;
  final Value<int> rowid;
  const PurchaseSequencesCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.nextValue = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchaseSequencesCompanion.insert({
    required String id,
    required String shopId,
    this.nextValue = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       shopId = Value(shopId);
  static Insertable<PurchaseSequence> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<int>? nextValue,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (nextValue != null) 'next_value': nextValue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchaseSequencesCompanion copyWith({
    Value<String>? id,
    Value<String>? shopId,
    Value<int>? nextValue,
    Value<int>? rowid,
  }) {
    return PurchaseSequencesCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      nextValue: nextValue ?? this.nextValue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (nextValue.present) {
      map['next_value'] = Variable<int>(nextValue.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseSequencesCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('nextValue: $nextValue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OffersTable extends Offers with TableInfo<$OffersTable, Offer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OffersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shops (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'CHECK (type IN (\'PERCENTAGE\',\'COMBO\',\'BUY_X_GET_Y\')) NOT NULL',
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<DateTime> startAt = GeneratedColumn<DateTime>(
    'start_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<DateTime> endAt = GeneratedColumn<DateTime>(
    'end_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    name,
    type,
    configJson,
    isActive,
    startAt,
    endAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Offer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_configJsonMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    }
    if (data.containsKey('end_at')) {
      context.handle(
        _endAtMeta,
        endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Offer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Offer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_at'],
      ),
      endAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $OffersTable createAlias(String alias) {
    return $OffersTable(attachedDatabase, alias);
  }
}

class Offer extends DataClass implements Insertable<Offer> {
  /// Local UUID v4 identifier, generated on this device.
  final String id;

  /// Business/shop that owns this offer.
  final String? shopId;
  final String name;

  /// Offer type wire value: PERCENTAGE | COMBO | BUY_X_GET_Y
  final String type;

  /// JSON config: percentage, combo price, buyXGetY numbers, productIds, etc.
  final String configJson;
  final bool isActive;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Offer({
    required this.id,
    this.shopId,
    required this.name,
    required this.type,
    required this.configJson,
    required this.isActive,
    this.startAt,
    this.endAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || shopId != null) {
      map['shop_id'] = Variable<String>(shopId);
    }
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['config_json'] = Variable<String>(configJson);
    map['is_active'] = Variable<bool>(isActive);
    if (!nullToAbsent || startAt != null) {
      map['start_at'] = Variable<DateTime>(startAt);
    }
    if (!nullToAbsent || endAt != null) {
      map['end_at'] = Variable<DateTime>(endAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OffersCompanion toCompanion(bool nullToAbsent) {
    return OffersCompanion(
      id: Value(id),
      shopId: shopId == null && nullToAbsent
          ? const Value.absent()
          : Value(shopId),
      name: Value(name),
      type: Value(type),
      configJson: Value(configJson),
      isActive: Value(isActive),
      startAt: startAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startAt),
      endAt: endAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Offer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Offer(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String?>(json['shopId']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      configJson: serializer.fromJson<String>(json['configJson']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      startAt: serializer.fromJson<DateTime?>(json['startAt']),
      endAt: serializer.fromJson<DateTime?>(json['endAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String?>(shopId),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'configJson': serializer.toJson<String>(configJson),
      'isActive': serializer.toJson<bool>(isActive),
      'startAt': serializer.toJson<DateTime?>(startAt),
      'endAt': serializer.toJson<DateTime?>(endAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Offer copyWith({
    String? id,
    Value<String?> shopId = const Value.absent(),
    String? name,
    String? type,
    String? configJson,
    bool? isActive,
    Value<DateTime?> startAt = const Value.absent(),
    Value<DateTime?> endAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Offer(
    id: id ?? this.id,
    shopId: shopId.present ? shopId.value : this.shopId,
    name: name ?? this.name,
    type: type ?? this.type,
    configJson: configJson ?? this.configJson,
    isActive: isActive ?? this.isActive,
    startAt: startAt.present ? startAt.value : this.startAt,
    endAt: endAt.present ? endAt.value : this.endAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Offer copyWithCompanion(OffersCompanion data) {
    return Offer(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Offer(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('configJson: $configJson, ')
          ..write('isActive: $isActive, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    name,
    type,
    configJson,
    isActive,
    startAt,
    endAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Offer &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.name == this.name &&
          other.type == this.type &&
          other.configJson == this.configJson &&
          other.isActive == this.isActive &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OffersCompanion extends UpdateCompanion<Offer> {
  final Value<String> id;
  final Value<String?> shopId;
  final Value<String> name;
  final Value<String> type;
  final Value<String> configJson;
  final Value<bool> isActive;
  final Value<DateTime?> startAt;
  final Value<DateTime?> endAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const OffersCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.configJson = const Value.absent(),
    this.isActive = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OffersCompanion.insert({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    required String name,
    required String type,
    required String configJson,
    this.isActive = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       type = Value(type),
       configJson = Value(configJson);
  static Insertable<Offer> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? configJson,
    Expression<bool>? isActive,
    Expression<DateTime>? startAt,
    Expression<DateTime>? endAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (configJson != null) 'config_json': configJson,
      if (isActive != null) 'is_active': isActive,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OffersCompanion copyWith({
    Value<String>? id,
    Value<String?>? shopId,
    Value<String>? name,
    Value<String>? type,
    Value<String>? configJson,
    Value<bool>? isActive,
    Value<DateTime?>? startAt,
    Value<DateTime?>? endAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return OffersCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      type: type ?? this.type,
      configJson: configJson ?? this.configJson,
      isActive: isActive ?? this.isActive,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<DateTime>(startAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<DateTime>(endAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OffersCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('configJson: $configJson, ')
          ..write('isActive: $isActive, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductImageSyncTable extends ProductImageSync
    with TableInfo<$ProductImageSyncTable, ProductImageSyncData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductImageSyncTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cloudPathMeta = const VerificationMeta(
    'cloudPath',
  );
  @override
  late final GeneratedColumn<String> cloudPath = GeneratedColumn<String>(
    'cloud_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('PENDING'),
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
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    productId,
    operation,
    cloudPath,
    localPath,
    status,
    attemptCount,
    lastAttemptAt,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_image_sync';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductImageSyncData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('cloud_path')) {
      context.handle(
        _cloudPathMeta,
        cloudPath.isAcceptableOrUnknown(data['cloud_path']!, _cloudPathMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
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
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductImageSyncData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductImageSyncData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      cloudPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_path'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ProductImageSyncTable createAlias(String alias) {
    return $ProductImageSyncTable(attachedDatabase, alias);
  }
}

class ProductImageSyncData extends DataClass
    implements Insertable<ProductImageSyncData> {
  /// Local UUID v4 identifier.
  final String id;

  /// Shop scope of the image (isolation boundary for cloud path + RLS).
  final String shopId;

  /// Stable UUID of the product the image belongs to.
  final String productId;

  /// Operation: 'UPLOAD', 'DOWNLOAD' or 'DELETE'.
  final String operation;

  /// Supabase Storage object path for this image (the destination of an
  /// UPLOAD, the source of a DOWNLOAD, or the object a DELETE removes).
  final String? cloudPath;

  /// Local relative image path involved in the intent: the local file an
  /// UPLOAD reads from, or the cache path a DOWNLOAD writes to.
  final String? localPath;

  /// PENDING → IN_FLIGHT → DONE / FAILED (FAILED keeps rows for inspection;
  /// retry counters live here too).
  final String status;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final DateTime createdAt;
  const ProductImageSyncData({
    required this.id,
    required this.shopId,
    required this.productId,
    required this.operation,
    this.cloudPath,
    this.localPath,
    required this.status,
    required this.attemptCount,
    this.lastAttemptAt,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['shop_id'] = Variable<String>(shopId);
    map['product_id'] = Variable<String>(productId);
    map['operation'] = Variable<String>(operation);
    if (!nullToAbsent || cloudPath != null) {
      map['cloud_path'] = Variable<String>(cloudPath);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProductImageSyncCompanion toCompanion(bool nullToAbsent) {
    return ProductImageSyncCompanion(
      id: Value(id),
      shopId: Value(shopId),
      productId: Value(productId),
      operation: Value(operation),
      cloudPath: cloudPath == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudPath),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      status: Value(status),
      attemptCount: Value(attemptCount),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory ProductImageSyncData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductImageSyncData(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String>(json['shopId']),
      productId: serializer.fromJson<String>(json['productId']),
      operation: serializer.fromJson<String>(json['operation']),
      cloudPath: serializer.fromJson<String?>(json['cloudPath']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String>(shopId),
      'productId': serializer.toJson<String>(productId),
      'operation': serializer.toJson<String>(operation),
      'cloudPath': serializer.toJson<String?>(cloudPath),
      'localPath': serializer.toJson<String?>(localPath),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ProductImageSyncData copyWith({
    String? id,
    String? shopId,
    String? productId,
    String? operation,
    Value<String?> cloudPath = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    String? status,
    int? attemptCount,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => ProductImageSyncData(
    id: id ?? this.id,
    shopId: shopId ?? this.shopId,
    productId: productId ?? this.productId,
    operation: operation ?? this.operation,
    cloudPath: cloudPath.present ? cloudPath.value : this.cloudPath,
    localPath: localPath.present ? localPath.value : this.localPath,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  ProductImageSyncData copyWithCompanion(ProductImageSyncCompanion data) {
    return ProductImageSyncData(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      productId: data.productId.present ? data.productId.value : this.productId,
      operation: data.operation.present ? data.operation.value : this.operation,
      cloudPath: data.cloudPath.present ? data.cloudPath.value : this.cloudPath,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductImageSyncData(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('productId: $productId, ')
          ..write('operation: $operation, ')
          ..write('cloudPath: $cloudPath, ')
          ..write('localPath: $localPath, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    productId,
    operation,
    cloudPath,
    localPath,
    status,
    attemptCount,
    lastAttemptAt,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductImageSyncData &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.productId == this.productId &&
          other.operation == this.operation &&
          other.cloudPath == this.cloudPath &&
          other.localPath == this.localPath &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class ProductImageSyncCompanion extends UpdateCompanion<ProductImageSyncData> {
  final Value<String> id;
  final Value<String> shopId;
  final Value<String> productId;
  final Value<String> operation;
  final Value<String?> cloudPath;
  final Value<String?> localPath;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ProductImageSyncCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.productId = const Value.absent(),
    this.operation = const Value.absent(),
    this.cloudPath = const Value.absent(),
    this.localPath = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductImageSyncCompanion.insert({
    this.id = const Value.absent(),
    required String shopId,
    required String productId,
    required String operation,
    this.cloudPath = const Value.absent(),
    this.localPath = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : shopId = Value(shopId),
       productId = Value(productId),
       operation = Value(operation);
  static Insertable<ProductImageSyncData> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? productId,
    Expression<String>? operation,
    Expression<String>? cloudPath,
    Expression<String>? localPath,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (productId != null) 'product_id': productId,
      if (operation != null) 'operation': operation,
      if (cloudPath != null) 'cloud_path': cloudPath,
      if (localPath != null) 'local_path': localPath,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductImageSyncCompanion copyWith({
    Value<String>? id,
    Value<String>? shopId,
    Value<String>? productId,
    Value<String>? operation,
    Value<String?>? cloudPath,
    Value<String?>? localPath,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<DateTime?>? lastAttemptAt,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ProductImageSyncCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      productId: productId ?? this.productId,
      operation: operation ?? this.operation,
      cloudPath: cloudPath ?? this.cloudPath,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (cloudPath.present) {
      map['cloud_path'] = Variable<String>(cloudPath.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductImageSyncCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('productId: $productId, ')
          ..write('operation: $operation, ')
          ..write('cloudPath: $cloudPath, ')
          ..write('localPath: $localPath, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StorageCleanupNotificationTable extends StorageCleanupNotification
    with
        TableInfo<
          $StorageCleanupNotificationTable,
          StorageCleanupNotificationData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StorageCleanupNotificationTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => Uuid().v4(),
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orphanCountMeta = const VerificationMeta(
    'orphanCount',
  );
  @override
  late final GeneratedColumn<int> orphanCount = GeneratedColumn<int>(
    'orphan_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _reclaimableBytesMeta = const VerificationMeta(
    'reclaimableBytes',
  );
  @override
  late final GeneratedColumn<int> reclaimableBytes = GeneratedColumn<int>(
    'reclaimable_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dismissedMeta = const VerificationMeta(
    'dismissed',
  );
  @override
  late final GeneratedColumn<bool> dismissed = GeneratedColumn<bool>(
    'dismissed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dismissed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now().toUtc(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shopId,
    kind,
    orphanCount,
    reclaimableBytes,
    isRead,
    dismissed,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'storage_cleanup_notification';
  @override
  VerificationContext validateIntegrity(
    Insertable<StorageCleanupNotificationData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('orphan_count')) {
      context.handle(
        _orphanCountMeta,
        orphanCount.isAcceptableOrUnknown(
          data['orphan_count']!,
          _orphanCountMeta,
        ),
      );
    }
    if (data.containsKey('reclaimable_bytes')) {
      context.handle(
        _reclaimableBytesMeta,
        reclaimableBytes.isAcceptableOrUnknown(
          data['reclaimable_bytes']!,
          _reclaimableBytesMeta,
        ),
      );
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    }
    if (data.containsKey('dismissed')) {
      context.handle(
        _dismissedMeta,
        dismissed.isAcceptableOrUnknown(data['dismissed']!, _dismissedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StorageCleanupNotificationData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StorageCleanupNotificationData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      orphanCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orphan_count'],
      )!,
      reclaimableBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reclaimable_bytes'],
      )!,
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
      dismissed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dismissed'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $StorageCleanupNotificationTable createAlias(String alias) {
    return $StorageCleanupNotificationTable(attachedDatabase, alias);
  }
}

class StorageCleanupNotificationData extends DataClass
    implements Insertable<StorageCleanupNotificationData> {
  /// Local UUID v4 identifier.
  final String id;

  /// Shop scope of the cleanup (isolation boundary).
  final String shopId;

  /// Notification kind: 'CLEANUP_AVAILABLE'.
  final String kind;

  /// Number of orphan (unreferenced) product images found.
  final int orphanCount;

  /// Total reclaimable bytes across the orphan images.
  final int reclaimableBytes;

  /// Whether the owner has opened the notification details.
  final bool isRead;

  /// Whether the owner has dismissed/cleared the notification.
  final bool dismissed;
  final DateTime createdAt;
  const StorageCleanupNotificationData({
    required this.id,
    required this.shopId,
    required this.kind,
    required this.orphanCount,
    required this.reclaimableBytes,
    required this.isRead,
    required this.dismissed,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['shop_id'] = Variable<String>(shopId);
    map['kind'] = Variable<String>(kind);
    map['orphan_count'] = Variable<int>(orphanCount);
    map['reclaimable_bytes'] = Variable<int>(reclaimableBytes);
    map['is_read'] = Variable<bool>(isRead);
    map['dismissed'] = Variable<bool>(dismissed);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  StorageCleanupNotificationCompanion toCompanion(bool nullToAbsent) {
    return StorageCleanupNotificationCompanion(
      id: Value(id),
      shopId: Value(shopId),
      kind: Value(kind),
      orphanCount: Value(orphanCount),
      reclaimableBytes: Value(reclaimableBytes),
      isRead: Value(isRead),
      dismissed: Value(dismissed),
      createdAt: Value(createdAt),
    );
  }

  factory StorageCleanupNotificationData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StorageCleanupNotificationData(
      id: serializer.fromJson<String>(json['id']),
      shopId: serializer.fromJson<String>(json['shopId']),
      kind: serializer.fromJson<String>(json['kind']),
      orphanCount: serializer.fromJson<int>(json['orphanCount']),
      reclaimableBytes: serializer.fromJson<int>(json['reclaimableBytes']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      dismissed: serializer.fromJson<bool>(json['dismissed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shopId': serializer.toJson<String>(shopId),
      'kind': serializer.toJson<String>(kind),
      'orphanCount': serializer.toJson<int>(orphanCount),
      'reclaimableBytes': serializer.toJson<int>(reclaimableBytes),
      'isRead': serializer.toJson<bool>(isRead),
      'dismissed': serializer.toJson<bool>(dismissed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  StorageCleanupNotificationData copyWith({
    String? id,
    String? shopId,
    String? kind,
    int? orphanCount,
    int? reclaimableBytes,
    bool? isRead,
    bool? dismissed,
    DateTime? createdAt,
  }) => StorageCleanupNotificationData(
    id: id ?? this.id,
    shopId: shopId ?? this.shopId,
    kind: kind ?? this.kind,
    orphanCount: orphanCount ?? this.orphanCount,
    reclaimableBytes: reclaimableBytes ?? this.reclaimableBytes,
    isRead: isRead ?? this.isRead,
    dismissed: dismissed ?? this.dismissed,
    createdAt: createdAt ?? this.createdAt,
  );
  StorageCleanupNotificationData copyWithCompanion(
    StorageCleanupNotificationCompanion data,
  ) {
    return StorageCleanupNotificationData(
      id: data.id.present ? data.id.value : this.id,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      kind: data.kind.present ? data.kind.value : this.kind,
      orphanCount: data.orphanCount.present
          ? data.orphanCount.value
          : this.orphanCount,
      reclaimableBytes: data.reclaimableBytes.present
          ? data.reclaimableBytes.value
          : this.reclaimableBytes,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      dismissed: data.dismissed.present ? data.dismissed.value : this.dismissed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StorageCleanupNotificationData(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('kind: $kind, ')
          ..write('orphanCount: $orphanCount, ')
          ..write('reclaimableBytes: $reclaimableBytes, ')
          ..write('isRead: $isRead, ')
          ..write('dismissed: $dismissed, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shopId,
    kind,
    orphanCount,
    reclaimableBytes,
    isRead,
    dismissed,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StorageCleanupNotificationData &&
          other.id == this.id &&
          other.shopId == this.shopId &&
          other.kind == this.kind &&
          other.orphanCount == this.orphanCount &&
          other.reclaimableBytes == this.reclaimableBytes &&
          other.isRead == this.isRead &&
          other.dismissed == this.dismissed &&
          other.createdAt == this.createdAt);
}

class StorageCleanupNotificationCompanion
    extends UpdateCompanion<StorageCleanupNotificationData> {
  final Value<String> id;
  final Value<String> shopId;
  final Value<String> kind;
  final Value<int> orphanCount;
  final Value<int> reclaimableBytes;
  final Value<bool> isRead;
  final Value<bool> dismissed;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const StorageCleanupNotificationCompanion({
    this.id = const Value.absent(),
    this.shopId = const Value.absent(),
    this.kind = const Value.absent(),
    this.orphanCount = const Value.absent(),
    this.reclaimableBytes = const Value.absent(),
    this.isRead = const Value.absent(),
    this.dismissed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StorageCleanupNotificationCompanion.insert({
    this.id = const Value.absent(),
    required String shopId,
    required String kind,
    this.orphanCount = const Value.absent(),
    this.reclaimableBytes = const Value.absent(),
    this.isRead = const Value.absent(),
    this.dismissed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : shopId = Value(shopId),
       kind = Value(kind);
  static Insertable<StorageCleanupNotificationData> custom({
    Expression<String>? id,
    Expression<String>? shopId,
    Expression<String>? kind,
    Expression<int>? orphanCount,
    Expression<int>? reclaimableBytes,
    Expression<bool>? isRead,
    Expression<bool>? dismissed,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shopId != null) 'shop_id': shopId,
      if (kind != null) 'kind': kind,
      if (orphanCount != null) 'orphan_count': orphanCount,
      if (reclaimableBytes != null) 'reclaimable_bytes': reclaimableBytes,
      if (isRead != null) 'is_read': isRead,
      if (dismissed != null) 'dismissed': dismissed,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StorageCleanupNotificationCompanion copyWith({
    Value<String>? id,
    Value<String>? shopId,
    Value<String>? kind,
    Value<int>? orphanCount,
    Value<int>? reclaimableBytes,
    Value<bool>? isRead,
    Value<bool>? dismissed,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return StorageCleanupNotificationCompanion(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      kind: kind ?? this.kind,
      orphanCount: orphanCount ?? this.orphanCount,
      reclaimableBytes: reclaimableBytes ?? this.reclaimableBytes,
      isRead: isRead ?? this.isRead,
      dismissed: dismissed ?? this.dismissed,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (orphanCount.present) {
      map['orphan_count'] = Variable<int>(orphanCount.value);
    }
    if (reclaimableBytes.present) {
      map['reclaimable_bytes'] = Variable<int>(reclaimableBytes.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (dismissed.present) {
      map['dismissed'] = Variable<bool>(dismissed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StorageCleanupNotificationCompanion(')
          ..write('id: $id, ')
          ..write('shopId: $shopId, ')
          ..write('kind: $kind, ')
          ..write('orphanCount: $orphanCount, ')
          ..write('reclaimableBytes: $reclaimableBytes, ')
          ..write('isRead: $isRead, ')
          ..write('dismissed: $dismissed, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StorageCleanupStateTable extends StorageCleanupState
    with TableInfo<$StorageCleanupStateTable, StorageCleanupStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StorageCleanupStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastScanAtMeta = const VerificationMeta(
    'lastScanAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastScanAt = GeneratedColumn<DateTime>(
    'last_scan_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCleanupAtMeta = const VerificationMeta(
    'lastCleanupAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCleanupAt =
      GeneratedColumn<DateTime>(
        'last_cleanup_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastUsedBytesMeta = const VerificationMeta(
    'lastUsedBytes',
  );
  @override
  late final GeneratedColumn<int> lastUsedBytes = GeneratedColumn<int>(
    'last_used_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReclaimableBytesMeta =
      const VerificationMeta('lastReclaimableBytes');
  @override
  late final GeneratedColumn<int> lastReclaimableBytes = GeneratedColumn<int>(
    'last_reclaimable_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    shopId,
    lastScanAt,
    lastCleanupAt,
    lastUsedBytes,
    lastReclaimableBytes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'storage_cleanup_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<StorageCleanupStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('last_scan_at')) {
      context.handle(
        _lastScanAtMeta,
        lastScanAt.isAcceptableOrUnknown(
          data['last_scan_at']!,
          _lastScanAtMeta,
        ),
      );
    }
    if (data.containsKey('last_cleanup_at')) {
      context.handle(
        _lastCleanupAtMeta,
        lastCleanupAt.isAcceptableOrUnknown(
          data['last_cleanup_at']!,
          _lastCleanupAtMeta,
        ),
      );
    }
    if (data.containsKey('last_used_bytes')) {
      context.handle(
        _lastUsedBytesMeta,
        lastUsedBytes.isAcceptableOrUnknown(
          data['last_used_bytes']!,
          _lastUsedBytesMeta,
        ),
      );
    }
    if (data.containsKey('last_reclaimable_bytes')) {
      context.handle(
        _lastReclaimableBytesMeta,
        lastReclaimableBytes.isAcceptableOrUnknown(
          data['last_reclaimable_bytes']!,
          _lastReclaimableBytesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {shopId};
  @override
  StorageCleanupStateData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StorageCleanupStateData(
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      lastScanAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_scan_at'],
      ),
      lastCleanupAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_cleanup_at'],
      ),
      lastUsedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_used_bytes'],
      ),
      lastReclaimableBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_reclaimable_bytes'],
      ),
    );
  }

  @override
  $StorageCleanupStateTable createAlias(String alias) {
    return $StorageCleanupStateTable(attachedDatabase, alias);
  }
}

class StorageCleanupStateData extends DataClass
    implements Insertable<StorageCleanupStateData> {
  /// Shop scope (isolation boundary). The natural key for this bookkeeping.
  final String shopId;

  /// UTC timestamp of the last completed usage scan.
  final DateTime? lastScanAt;

  /// UTC timestamp of the last owner-confirmed cleanup.
  final DateTime? lastCleanupAt;

  /// Latest known used bytes (snapshot, informational for offline display).
  final int? lastUsedBytes;

  /// Latest known reclaimable bytes (snapshot).
  final int? lastReclaimableBytes;
  const StorageCleanupStateData({
    required this.shopId,
    this.lastScanAt,
    this.lastCleanupAt,
    this.lastUsedBytes,
    this.lastReclaimableBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['shop_id'] = Variable<String>(shopId);
    if (!nullToAbsent || lastScanAt != null) {
      map['last_scan_at'] = Variable<DateTime>(lastScanAt);
    }
    if (!nullToAbsent || lastCleanupAt != null) {
      map['last_cleanup_at'] = Variable<DateTime>(lastCleanupAt);
    }
    if (!nullToAbsent || lastUsedBytes != null) {
      map['last_used_bytes'] = Variable<int>(lastUsedBytes);
    }
    if (!nullToAbsent || lastReclaimableBytes != null) {
      map['last_reclaimable_bytes'] = Variable<int>(lastReclaimableBytes);
    }
    return map;
  }

  StorageCleanupStateCompanion toCompanion(bool nullToAbsent) {
    return StorageCleanupStateCompanion(
      shopId: Value(shopId),
      lastScanAt: lastScanAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastScanAt),
      lastCleanupAt: lastCleanupAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCleanupAt),
      lastUsedBytes: lastUsedBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedBytes),
      lastReclaimableBytes: lastReclaimableBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReclaimableBytes),
    );
  }

  factory StorageCleanupStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StorageCleanupStateData(
      shopId: serializer.fromJson<String>(json['shopId']),
      lastScanAt: serializer.fromJson<DateTime?>(json['lastScanAt']),
      lastCleanupAt: serializer.fromJson<DateTime?>(json['lastCleanupAt']),
      lastUsedBytes: serializer.fromJson<int?>(json['lastUsedBytes']),
      lastReclaimableBytes: serializer.fromJson<int?>(
        json['lastReclaimableBytes'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'shopId': serializer.toJson<String>(shopId),
      'lastScanAt': serializer.toJson<DateTime?>(lastScanAt),
      'lastCleanupAt': serializer.toJson<DateTime?>(lastCleanupAt),
      'lastUsedBytes': serializer.toJson<int?>(lastUsedBytes),
      'lastReclaimableBytes': serializer.toJson<int?>(lastReclaimableBytes),
    };
  }

  StorageCleanupStateData copyWith({
    String? shopId,
    Value<DateTime?> lastScanAt = const Value.absent(),
    Value<DateTime?> lastCleanupAt = const Value.absent(),
    Value<int?> lastUsedBytes = const Value.absent(),
    Value<int?> lastReclaimableBytes = const Value.absent(),
  }) => StorageCleanupStateData(
    shopId: shopId ?? this.shopId,
    lastScanAt: lastScanAt.present ? lastScanAt.value : this.lastScanAt,
    lastCleanupAt: lastCleanupAt.present
        ? lastCleanupAt.value
        : this.lastCleanupAt,
    lastUsedBytes: lastUsedBytes.present
        ? lastUsedBytes.value
        : this.lastUsedBytes,
    lastReclaimableBytes: lastReclaimableBytes.present
        ? lastReclaimableBytes.value
        : this.lastReclaimableBytes,
  );
  StorageCleanupStateData copyWithCompanion(StorageCleanupStateCompanion data) {
    return StorageCleanupStateData(
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      lastScanAt: data.lastScanAt.present
          ? data.lastScanAt.value
          : this.lastScanAt,
      lastCleanupAt: data.lastCleanupAt.present
          ? data.lastCleanupAt.value
          : this.lastCleanupAt,
      lastUsedBytes: data.lastUsedBytes.present
          ? data.lastUsedBytes.value
          : this.lastUsedBytes,
      lastReclaimableBytes: data.lastReclaimableBytes.present
          ? data.lastReclaimableBytes.value
          : this.lastReclaimableBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StorageCleanupStateData(')
          ..write('shopId: $shopId, ')
          ..write('lastScanAt: $lastScanAt, ')
          ..write('lastCleanupAt: $lastCleanupAt, ')
          ..write('lastUsedBytes: $lastUsedBytes, ')
          ..write('lastReclaimableBytes: $lastReclaimableBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    shopId,
    lastScanAt,
    lastCleanupAt,
    lastUsedBytes,
    lastReclaimableBytes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StorageCleanupStateData &&
          other.shopId == this.shopId &&
          other.lastScanAt == this.lastScanAt &&
          other.lastCleanupAt == this.lastCleanupAt &&
          other.lastUsedBytes == this.lastUsedBytes &&
          other.lastReclaimableBytes == this.lastReclaimableBytes);
}

class StorageCleanupStateCompanion
    extends UpdateCompanion<StorageCleanupStateData> {
  final Value<String> shopId;
  final Value<DateTime?> lastScanAt;
  final Value<DateTime?> lastCleanupAt;
  final Value<int?> lastUsedBytes;
  final Value<int?> lastReclaimableBytes;
  final Value<int> rowid;
  const StorageCleanupStateCompanion({
    this.shopId = const Value.absent(),
    this.lastScanAt = const Value.absent(),
    this.lastCleanupAt = const Value.absent(),
    this.lastUsedBytes = const Value.absent(),
    this.lastReclaimableBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StorageCleanupStateCompanion.insert({
    required String shopId,
    this.lastScanAt = const Value.absent(),
    this.lastCleanupAt = const Value.absent(),
    this.lastUsedBytes = const Value.absent(),
    this.lastReclaimableBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : shopId = Value(shopId);
  static Insertable<StorageCleanupStateData> custom({
    Expression<String>? shopId,
    Expression<DateTime>? lastScanAt,
    Expression<DateTime>? lastCleanupAt,
    Expression<int>? lastUsedBytes,
    Expression<int>? lastReclaimableBytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (shopId != null) 'shop_id': shopId,
      if (lastScanAt != null) 'last_scan_at': lastScanAt,
      if (lastCleanupAt != null) 'last_cleanup_at': lastCleanupAt,
      if (lastUsedBytes != null) 'last_used_bytes': lastUsedBytes,
      if (lastReclaimableBytes != null)
        'last_reclaimable_bytes': lastReclaimableBytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StorageCleanupStateCompanion copyWith({
    Value<String>? shopId,
    Value<DateTime?>? lastScanAt,
    Value<DateTime?>? lastCleanupAt,
    Value<int?>? lastUsedBytes,
    Value<int?>? lastReclaimableBytes,
    Value<int>? rowid,
  }) {
    return StorageCleanupStateCompanion(
      shopId: shopId ?? this.shopId,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      lastCleanupAt: lastCleanupAt ?? this.lastCleanupAt,
      lastUsedBytes: lastUsedBytes ?? this.lastUsedBytes,
      lastReclaimableBytes: lastReclaimableBytes ?? this.lastReclaimableBytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (lastScanAt.present) {
      map['last_scan_at'] = Variable<DateTime>(lastScanAt.value);
    }
    if (lastCleanupAt.present) {
      map['last_cleanup_at'] = Variable<DateTime>(lastCleanupAt.value);
    }
    if (lastUsedBytes.present) {
      map['last_used_bytes'] = Variable<int>(lastUsedBytes.value);
    }
    if (lastReclaimableBytes.present) {
      map['last_reclaimable_bytes'] = Variable<int>(lastReclaimableBytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StorageCleanupStateCompanion(')
          ..write('shopId: $shopId, ')
          ..write('lastScanAt: $lastScanAt, ')
          ..write('lastCleanupAt: $lastCleanupAt, ')
          ..write('lastUsedBytes: $lastUsedBytes, ')
          ..write('lastReclaimableBytes: $lastReclaimableBytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ShopsTable shops = $ShopsTable(this);
  late final $UsersTable users = $UsersTable(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $StaffPermissionsTable staffPermissions = $StaffPermissionsTable(
    this,
  );
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $ProductVariantsTable productVariants = $ProductVariantsTable(
    this,
  );
  late final $CustomersTable customers = $CustomersTable(this);
  late final $SalesTable sales = $SalesTable(this);
  late final $CustomerPaymentsTable customerPayments = $CustomerPaymentsTable(
    this,
  );
  late final $ExpensesTable expenses = $ExpensesTable(this);
  late final $SaleItemsTable saleItems = $SaleItemsTable(this);
  late final $SaleSequencesTable saleSequences = $SaleSequencesTable(this);
  late final $StockMovementsTable stockMovements = $StockMovementsTable(this);
  late final $SuppliersTable suppliers = $SuppliersTable(this);
  late final $PurchasesTable purchases = $PurchasesTable(this);
  late final $PurchaseItemsTable purchaseItems = $PurchaseItemsTable(this);
  late final $PurchaseSequencesTable purchaseSequences =
      $PurchaseSequencesTable(this);
  late final $OffersTable offers = $OffersTable(this);
  late final $ProductImageSyncTable productImageSync = $ProductImageSyncTable(
    this,
  );
  late final $StorageCleanupNotificationTable storageCleanupNotification =
      $StorageCleanupNotificationTable(this);
  late final $StorageCleanupStateTable storageCleanupState =
      $StorageCleanupStateTable(this);
  late final Index idxUsersUpdatedAt = Index(
    'idx_users_updated_at',
    'CREATE INDEX idx_users_updated_at ON users (updated_at)',
  );
  late final Index idxShopsUpdatedAt = Index(
    'idx_shops_updated_at',
    'CREATE INDEX idx_shops_updated_at ON shops (updated_at)',
  );
  late final Index idxDevicesShop = Index(
    'idx_devices_shop',
    'CREATE INDEX idx_devices_shop ON devices (shop_id)',
  );
  late final Index idxDevicesUpdatedAt = Index(
    'idx_devices_updated_at',
    'CREATE INDEX idx_devices_updated_at ON devices (updated_at)',
  );
  late final Index idxSyncOutboxIdentity = Index(
    'idx_sync_outbox_identity',
    'CREATE INDEX idx_sync_outbox_identity ON sync_outbox (entity, entity_id, operation)',
  );
  late final Index idxSyncOutboxStatus = Index(
    'idx_sync_outbox_status',
    'CREATE INDEX idx_sync_outbox_status ON sync_outbox (status, created_at)',
  );
  late final Index idxStaffPermissionsUser = Index(
    'idx_staff_permissions_user',
    'CREATE INDEX idx_staff_permissions_user ON staff_permissions (user_id)',
  );
  late final Index idxCategoriesShop = Index(
    'idx_categories_shop',
    'CREATE INDEX idx_categories_shop ON categories (shop_id)',
  );
  late final Index idxCategoriesUpdatedAt = Index(
    'idx_categories_updated_at',
    'CREATE INDEX idx_categories_updated_at ON categories (shop_id, updated_at)',
  );
  late final Index idxProductsShop = Index(
    'idx_products_shop',
    'CREATE INDEX idx_products_shop ON products (shop_id)',
  );
  late final Index idxProductsCategoryId = Index(
    'idx_products_category_id',
    'CREATE INDEX idx_products_category_id ON products (category_id)',
  );
  late final Index idxProductsName = Index(
    'idx_products_name',
    'CREATE INDEX idx_products_name ON products (name)',
  );
  late final Index idxProductsUpdatedAt = Index(
    'idx_products_updated_at',
    'CREATE INDEX idx_products_updated_at ON products (shop_id, updated_at)',
  );
  late final Index idxProductVariantsShop = Index(
    'idx_product_variants_shop',
    'CREATE INDEX idx_product_variants_shop ON product_variants (shop_id)',
  );
  late final Index idxProductVariantsProductId = Index(
    'idx_product_variants_product_id',
    'CREATE INDEX idx_product_variants_product_id ON product_variants (product_id)',
  );
  late final Index idxProductVariantsSku = Index(
    'idx_product_variants_sku',
    'CREATE INDEX idx_product_variants_sku ON product_variants (sku)',
  );
  late final Index idxProductVariantsUpdatedAt = Index(
    'idx_product_variants_updated_at',
    'CREATE INDEX idx_product_variants_updated_at ON product_variants (shop_id, updated_at)',
  );
  late final Index idxCustomersShop = Index(
    'idx_customers_shop',
    'CREATE INDEX idx_customers_shop ON customers (shop_id)',
  );
  late final Index idxCustomersName = Index(
    'idx_customers_name',
    'CREATE INDEX idx_customers_name ON customers (name)',
  );
  late final Index idxCustomersUpdatedAt = Index(
    'idx_customers_updated_at',
    'CREATE INDEX idx_customers_updated_at ON customers (shop_id, updated_at)',
  );
  late final Index idxCustomerPaymentsShop = Index(
    'idx_customer_payments_shop',
    'CREATE INDEX idx_customer_payments_shop ON customer_payments (shop_id)',
  );
  late final Index idxCustomerPaymentsCustomerId = Index(
    'idx_customer_payments_customer_id',
    'CREATE INDEX idx_customer_payments_customer_id ON customer_payments (shop_id, customer_id)',
  );
  late final Index idxCustomerPaymentsSaleId = Index(
    'idx_customer_payments_sale_id',
    'CREATE INDEX idx_customer_payments_sale_id ON customer_payments (sale_id)',
  );
  late final Index idxCustomerPaymentsPaidAt = Index(
    'idx_customer_payments_paid_at',
    'CREATE INDEX idx_customer_payments_paid_at ON customer_payments (shop_id, paid_at)',
  );
  late final Index idxExpensesShop = Index(
    'idx_expenses_shop',
    'CREATE INDEX idx_expenses_shop ON expenses (shop_id)',
  );
  late final Index idxExpensesExpenseDate = Index(
    'idx_expenses_expense_date',
    'CREATE INDEX idx_expenses_expense_date ON expenses (shop_id, expense_date)',
  );
  late final Index idxExpensesCategory = Index(
    'idx_expenses_category',
    'CREATE INDEX idx_expenses_category ON expenses (shop_id, category)',
  );
  late final Index idxExpensesUpdatedAt = Index(
    'idx_expenses_updated_at',
    'CREATE INDEX idx_expenses_updated_at ON expenses (shop_id, updated_at)',
  );
  late final Index idxSalesShop = Index(
    'idx_sales_shop',
    'CREATE INDEX idx_sales_shop ON sales (shop_id)',
  );
  late final Index idxSalesCreatedAt = Index(
    'idx_sales_created_at',
    'CREATE INDEX idx_sales_created_at ON sales (shop_id, created_at)',
  );
  late final Index idxSalesCustomerId = Index(
    'idx_sales_customer_id',
    'CREATE INDEX idx_sales_customer_id ON sales (shop_id, customer_id)',
  );
  late final Index idxSaleItemsShop = Index(
    'idx_sale_items_shop',
    'CREATE INDEX idx_sale_items_shop ON sale_items (shop_id)',
  );
  late final Index idxSaleItemsSaleId = Index(
    'idx_sale_items_sale_id',
    'CREATE INDEX idx_sale_items_sale_id ON sale_items (shop_id, sale_id)',
  );
  late final Index idxStockMovementsShop = Index(
    'idx_stock_movements_shop',
    'CREATE INDEX idx_stock_movements_shop ON stock_movements (shop_id)',
  );
  late final Index idxStockMovementsProductCreatedAt = Index(
    'idx_stock_movements_product_created_at',
    'CREATE INDEX idx_stock_movements_product_created_at ON stock_movements (shop_id, product_id, created_at)',
  );
  late final Index idxStockMovementsVariantCreatedAt = Index(
    'idx_stock_movements_variant_created_at',
    'CREATE INDEX idx_stock_movements_variant_created_at ON stock_movements (shop_id, variant_id, created_at)',
  );
  late final Index idxSuppliersShop = Index(
    'idx_suppliers_shop',
    'CREATE INDEX idx_suppliers_shop ON suppliers (shop_id)',
  );
  late final Index idxSuppliersName = Index(
    'idx_suppliers_name',
    'CREATE INDEX idx_suppliers_name ON suppliers (name)',
  );
  late final Index idxSuppliersUpdatedAt = Index(
    'idx_suppliers_updated_at',
    'CREATE INDEX idx_suppliers_updated_at ON suppliers (shop_id, updated_at)',
  );
  late final Index idxPurchasesShop = Index(
    'idx_purchases_shop',
    'CREATE INDEX idx_purchases_shop ON purchases (shop_id)',
  );
  late final Index idxPurchasesCreatedAt = Index(
    'idx_purchases_created_at',
    'CREATE INDEX idx_purchases_created_at ON purchases (shop_id, created_at)',
  );
  late final Index idxPurchasesSupplierId = Index(
    'idx_purchases_supplier_id',
    'CREATE INDEX idx_purchases_supplier_id ON purchases (shop_id, supplier_id)',
  );
  late final Index idxPurchaseItemsShop = Index(
    'idx_purchase_items_shop',
    'CREATE INDEX idx_purchase_items_shop ON purchase_items (shop_id)',
  );
  late final Index idxPurchaseItemsPurchaseId = Index(
    'idx_purchase_items_purchase_id',
    'CREATE INDEX idx_purchase_items_purchase_id ON purchase_items (shop_id, purchase_id)',
  );
  late final Index idxOffersShop = Index(
    'idx_offers_shop',
    'CREATE INDEX idx_offers_shop ON offers (shop_id)',
  );
  late final Index idxOffersShopActive = Index(
    'idx_offers_shop_active',
    'CREATE INDEX idx_offers_shop_active ON offers (shop_id, is_active)',
  );
  late final Index idxProductImageSyncIdentity = Index(
    'idx_product_image_sync_identity',
    'CREATE INDEX idx_product_image_sync_identity ON product_image_sync (product_id, operation)',
  );
  late final Index idxProductImageSyncStatus = Index(
    'idx_product_image_sync_status',
    'CREATE INDEX idx_product_image_sync_status ON product_image_sync (status, created_at)',
  );
  late final Index idxStorageCleanupNotification = Index(
    'idx_storage_cleanup_notification',
    'CREATE INDEX idx_storage_cleanup_notification ON storage_cleanup_notification (shop_id, kind)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    shops,
    users,
    devices,
    syncOutbox,
    syncState,
    staffPermissions,
    categories,
    products,
    productVariants,
    customers,
    sales,
    customerPayments,
    expenses,
    saleItems,
    saleSequences,
    stockMovements,
    suppliers,
    purchases,
    purchaseItems,
    purchaseSequences,
    offers,
    productImageSync,
    storageCleanupNotification,
    storageCleanupState,
    idxUsersUpdatedAt,
    idxShopsUpdatedAt,
    idxDevicesShop,
    idxDevicesUpdatedAt,
    idxSyncOutboxIdentity,
    idxSyncOutboxStatus,
    idxStaffPermissionsUser,
    idxCategoriesShop,
    idxCategoriesUpdatedAt,
    idxProductsShop,
    idxProductsCategoryId,
    idxProductsName,
    idxProductsUpdatedAt,
    idxProductVariantsShop,
    idxProductVariantsProductId,
    idxProductVariantsSku,
    idxProductVariantsUpdatedAt,
    idxCustomersShop,
    idxCustomersName,
    idxCustomersUpdatedAt,
    idxCustomerPaymentsShop,
    idxCustomerPaymentsCustomerId,
    idxCustomerPaymentsSaleId,
    idxCustomerPaymentsPaidAt,
    idxExpensesShop,
    idxExpensesExpenseDate,
    idxExpensesCategory,
    idxExpensesUpdatedAt,
    idxSalesShop,
    idxSalesCreatedAt,
    idxSalesCustomerId,
    idxSaleItemsShop,
    idxSaleItemsSaleId,
    idxStockMovementsShop,
    idxStockMovementsProductCreatedAt,
    idxStockMovementsVariantCreatedAt,
    idxSuppliersShop,
    idxSuppliersName,
    idxSuppliersUpdatedAt,
    idxPurchasesShop,
    idxPurchasesCreatedAt,
    idxPurchasesSupplierId,
    idxPurchaseItemsShop,
    idxPurchaseItemsPurchaseId,
    idxOffersShop,
    idxOffersShopActive,
    idxProductImageSyncIdentity,
    idxProductImageSyncStatus,
    idxStorageCleanupNotification,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('categories', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('products', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('product_variants', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('customers', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sales', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('customer_payments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('expenses', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sale_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sale_sequences', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('stock_movements', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('suppliers', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('purchases', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('purchase_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('purchase_sequences', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shops',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('offers', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$ShopsTableCreateCompanionBuilder =
    ShopsCompanion Function({
      Value<String> id,
      required String name,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ShopsTableUpdateCompanionBuilder =
    ShopsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ShopsTableReferences
    extends BaseReferences<_$AppDatabase, $ShopsTable, Shop> {
  $$ShopsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$UsersTable, List<User>> _usersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.users,
    aliasName: $_aliasNameGenerator(db.shops.id, db.users.shopId),
  );

  $$UsersTableProcessedTableManager get usersRefs {
    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_usersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DevicesTable, List<Device>> _devicesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.devices,
    aliasName: $_aliasNameGenerator(db.shops.id, db.devices.shopId),
  );

  $$DevicesTableProcessedTableManager get devicesRefs {
    final manager = $$DevicesTableTableManager(
      $_db,
      $_db.devices,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_devicesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CategoriesTable, List<Category>>
  _categoriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.categories,
    aliasName: $_aliasNameGenerator(db.shops.id, db.categories.shopId),
  );

  $$CategoriesTableProcessedTableManager get categoriesRefs {
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_categoriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProductsTable, List<Product>> _productsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.products,
    aliasName: $_aliasNameGenerator(db.shops.id, db.products.shopId),
  );

  $$ProductsTableProcessedTableManager get productsRefs {
    final manager = $$ProductsTableTableManager(
      $_db,
      $_db.products,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_productsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProductVariantsTable, List<ProductVariant>>
  _productVariantsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.productVariants,
    aliasName: $_aliasNameGenerator(db.shops.id, db.productVariants.shopId),
  );

  $$ProductVariantsTableProcessedTableManager get productVariantsRefs {
    final manager = $$ProductVariantsTableTableManager(
      $_db,
      $_db.productVariants,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _productVariantsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CustomersTable, List<Customer>>
  _customersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.customers,
    aliasName: $_aliasNameGenerator(db.shops.id, db.customers.shopId),
  );

  $$CustomersTableProcessedTableManager get customersRefs {
    final manager = $$CustomersTableTableManager(
      $_db,
      $_db.customers,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_customersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SalesTable, List<Sale>> _salesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.sales,
    aliasName: $_aliasNameGenerator(db.shops.id, db.sales.shopId),
  );

  $$SalesTableProcessedTableManager get salesRefs {
    final manager = $$SalesTableTableManager(
      $_db,
      $_db.sales,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_salesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CustomerPaymentsTable, List<CustomerPayment>>
  _customerPaymentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.customerPayments,
    aliasName: $_aliasNameGenerator(db.shops.id, db.customerPayments.shopId),
  );

  $$CustomerPaymentsTableProcessedTableManager get customerPaymentsRefs {
    final manager = $$CustomerPaymentsTableTableManager(
      $_db,
      $_db.customerPayments,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _customerPaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ExpensesTable, List<Expense>> _expensesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.expenses,
    aliasName: $_aliasNameGenerator(db.shops.id, db.expenses.shopId),
  );

  $$ExpensesTableProcessedTableManager get expensesRefs {
    final manager = $$ExpensesTableTableManager(
      $_db,
      $_db.expenses,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_expensesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SaleItemsTable, List<SaleItem>>
  _saleItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.saleItems,
    aliasName: $_aliasNameGenerator(db.shops.id, db.saleItems.shopId),
  );

  $$SaleItemsTableProcessedTableManager get saleItemsRefs {
    final manager = $$SaleItemsTableTableManager(
      $_db,
      $_db.saleItems,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_saleItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SaleSequencesTable, List<SaleSequence>>
  _saleSequencesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.saleSequences,
    aliasName: $_aliasNameGenerator(db.shops.id, db.saleSequences.shopId),
  );

  $$SaleSequencesTableProcessedTableManager get saleSequencesRefs {
    final manager = $$SaleSequencesTableTableManager(
      $_db,
      $_db.saleSequences,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_saleSequencesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$StockMovementsTable, List<StockMovement>>
  _stockMovementsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.stockMovements,
    aliasName: $_aliasNameGenerator(db.shops.id, db.stockMovements.shopId),
  );

  $$StockMovementsTableProcessedTableManager get stockMovementsRefs {
    final manager = $$StockMovementsTableTableManager(
      $_db,
      $_db.stockMovements,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_stockMovementsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SuppliersTable, List<Supplier>>
  _suppliersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.suppliers,
    aliasName: $_aliasNameGenerator(db.shops.id, db.suppliers.shopId),
  );

  $$SuppliersTableProcessedTableManager get suppliersRefs {
    final manager = $$SuppliersTableTableManager(
      $_db,
      $_db.suppliers,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_suppliersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PurchasesTable, List<Purchase>>
  _purchasesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.purchases,
    aliasName: $_aliasNameGenerator(db.shops.id, db.purchases.shopId),
  );

  $$PurchasesTableProcessedTableManager get purchasesRefs {
    final manager = $$PurchasesTableTableManager(
      $_db,
      $_db.purchases,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_purchasesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PurchaseItemsTable, List<PurchaseItem>>
  _purchaseItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.purchaseItems,
    aliasName: $_aliasNameGenerator(db.shops.id, db.purchaseItems.shopId),
  );

  $$PurchaseItemsTableProcessedTableManager get purchaseItemsRefs {
    final manager = $$PurchaseItemsTableTableManager(
      $_db,
      $_db.purchaseItems,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_purchaseItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PurchaseSequencesTable, List<PurchaseSequence>>
  _purchaseSequencesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.purchaseSequences,
        aliasName: $_aliasNameGenerator(
          db.shops.id,
          db.purchaseSequences.shopId,
        ),
      );

  $$PurchaseSequencesTableProcessedTableManager get purchaseSequencesRefs {
    final manager = $$PurchaseSequencesTableTableManager(
      $_db,
      $_db.purchaseSequences,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _purchaseSequencesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OffersTable, List<Offer>> _offersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.offers,
    aliasName: $_aliasNameGenerator(db.shops.id, db.offers.shopId),
  );

  $$OffersTableProcessedTableManager get offersRefs {
    final manager = $$OffersTableTableManager(
      $_db,
      $_db.offers,
    ).filter((f) => f.shopId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_offersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ShopsTableFilterComposer extends Composer<_$AppDatabase, $ShopsTable> {
  $$ShopsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> usersRefs(
    Expression<bool> Function($$UsersTableFilterComposer f) f,
  ) {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> devicesRefs(
    Expression<bool> Function($$DevicesTableFilterComposer f) f,
  ) {
    final $$DevicesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableFilterComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> categoriesRefs(
    Expression<bool> Function($$CategoriesTableFilterComposer f) f,
  ) {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> productsRefs(
    Expression<bool> Function($$ProductsTableFilterComposer f) f,
  ) {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> productVariantsRefs(
    Expression<bool> Function($$ProductVariantsTableFilterComposer f) f,
  ) {
    final $$ProductVariantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableFilterComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> customersRefs(
    Expression<bool> Function($$CustomersTableFilterComposer f) f,
  ) {
    final $$CustomersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableFilterComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> salesRefs(
    Expression<bool> Function($$SalesTableFilterComposer f) f,
  ) {
    final $$SalesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableFilterComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> customerPaymentsRefs(
    Expression<bool> Function($$CustomerPaymentsTableFilterComposer f) f,
  ) {
    final $$CustomerPaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customerPayments,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomerPaymentsTableFilterComposer(
            $db: $db,
            $table: $db.customerPayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> expensesRefs(
    Expression<bool> Function($$ExpensesTableFilterComposer f) f,
  ) {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> saleItemsRefs(
    Expression<bool> Function($$SaleItemsTableFilterComposer f) f,
  ) {
    final $$SaleItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleItems,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleItemsTableFilterComposer(
            $db: $db,
            $table: $db.saleItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> saleSequencesRefs(
    Expression<bool> Function($$SaleSequencesTableFilterComposer f) f,
  ) {
    final $$SaleSequencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleSequences,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleSequencesTableFilterComposer(
            $db: $db,
            $table: $db.saleSequences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> stockMovementsRefs(
    Expression<bool> Function($$StockMovementsTableFilterComposer f) f,
  ) {
    final $$StockMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stockMovements,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StockMovementsTableFilterComposer(
            $db: $db,
            $table: $db.stockMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> suppliersRefs(
    Expression<bool> Function($$SuppliersTableFilterComposer f) f,
  ) {
    final $$SuppliersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableFilterComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> purchasesRefs(
    Expression<bool> Function($$PurchasesTableFilterComposer f) f,
  ) {
    final $$PurchasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchases,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchasesTableFilterComposer(
            $db: $db,
            $table: $db.purchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> purchaseItemsRefs(
    Expression<bool> Function($$PurchaseItemsTableFilterComposer f) f,
  ) {
    final $$PurchaseItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseItems,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseItemsTableFilterComposer(
            $db: $db,
            $table: $db.purchaseItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> purchaseSequencesRefs(
    Expression<bool> Function($$PurchaseSequencesTableFilterComposer f) f,
  ) {
    final $$PurchaseSequencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseSequences,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseSequencesTableFilterComposer(
            $db: $db,
            $table: $db.purchaseSequences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> offersRefs(
    Expression<bool> Function($$OffersTableFilterComposer f) f,
  ) {
    final $$OffersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.offers,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OffersTableFilterComposer(
            $db: $db,
            $table: $db.offers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShopsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShopsTable> {
  $$ShopsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShopsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShopsTable> {
  $$ShopsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> usersRefs<T extends Object>(
    Expression<T> Function($$UsersTableAnnotationComposer a) f,
  ) {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> devicesRefs<T extends Object>(
    Expression<T> Function($$DevicesTableAnnotationComposer a) f,
  ) {
    final $$DevicesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableAnnotationComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> categoriesRefs<T extends Object>(
    Expression<T> Function($$CategoriesTableAnnotationComposer a) f,
  ) {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> productsRefs<T extends Object>(
    Expression<T> Function($$ProductsTableAnnotationComposer a) f,
  ) {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> productVariantsRefs<T extends Object>(
    Expression<T> Function($$ProductVariantsTableAnnotationComposer a) f,
  ) {
    final $$ProductVariantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableAnnotationComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> customersRefs<T extends Object>(
    Expression<T> Function($$CustomersTableAnnotationComposer a) f,
  ) {
    final $$CustomersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableAnnotationComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> salesRefs<T extends Object>(
    Expression<T> Function($$SalesTableAnnotationComposer a) f,
  ) {
    final $$SalesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableAnnotationComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> customerPaymentsRefs<T extends Object>(
    Expression<T> Function($$CustomerPaymentsTableAnnotationComposer a) f,
  ) {
    final $$CustomerPaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customerPayments,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomerPaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.customerPayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> expensesRefs<T extends Object>(
    Expression<T> Function($$ExpensesTableAnnotationComposer a) f,
  ) {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> saleItemsRefs<T extends Object>(
    Expression<T> Function($$SaleItemsTableAnnotationComposer a) f,
  ) {
    final $$SaleItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleItems,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.saleItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> saleSequencesRefs<T extends Object>(
    Expression<T> Function($$SaleSequencesTableAnnotationComposer a) f,
  ) {
    final $$SaleSequencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleSequences,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleSequencesTableAnnotationComposer(
            $db: $db,
            $table: $db.saleSequences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> stockMovementsRefs<T extends Object>(
    Expression<T> Function($$StockMovementsTableAnnotationComposer a) f,
  ) {
    final $$StockMovementsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stockMovements,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StockMovementsTableAnnotationComposer(
            $db: $db,
            $table: $db.stockMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> suppliersRefs<T extends Object>(
    Expression<T> Function($$SuppliersTableAnnotationComposer a) f,
  ) {
    final $$SuppliersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableAnnotationComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> purchasesRefs<T extends Object>(
    Expression<T> Function($$PurchasesTableAnnotationComposer a) f,
  ) {
    final $$PurchasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchases,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchasesTableAnnotationComposer(
            $db: $db,
            $table: $db.purchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> purchaseItemsRefs<T extends Object>(
    Expression<T> Function($$PurchaseItemsTableAnnotationComposer a) f,
  ) {
    final $$PurchaseItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseItems,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.purchaseItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> purchaseSequencesRefs<T extends Object>(
    Expression<T> Function($$PurchaseSequencesTableAnnotationComposer a) f,
  ) {
    final $$PurchaseSequencesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.purchaseSequences,
          getReferencedColumn: (t) => t.shopId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PurchaseSequencesTableAnnotationComposer(
                $db: $db,
                $table: $db.purchaseSequences,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> offersRefs<T extends Object>(
    Expression<T> Function($$OffersTableAnnotationComposer a) f,
  ) {
    final $$OffersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.offers,
      getReferencedColumn: (t) => t.shopId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OffersTableAnnotationComposer(
            $db: $db,
            $table: $db.offers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShopsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShopsTable,
          Shop,
          $$ShopsTableFilterComposer,
          $$ShopsTableOrderingComposer,
          $$ShopsTableAnnotationComposer,
          $$ShopsTableCreateCompanionBuilder,
          $$ShopsTableUpdateCompanionBuilder,
          (Shop, $$ShopsTableReferences),
          Shop,
          PrefetchHooks Function({
            bool usersRefs,
            bool devicesRefs,
            bool categoriesRefs,
            bool productsRefs,
            bool productVariantsRefs,
            bool customersRefs,
            bool salesRefs,
            bool customerPaymentsRefs,
            bool expensesRefs,
            bool saleItemsRefs,
            bool saleSequencesRefs,
            bool stockMovementsRefs,
            bool suppliersRefs,
            bool purchasesRefs,
            bool purchaseItemsRefs,
            bool purchaseSequencesRefs,
            bool offersRefs,
          })
        > {
  $$ShopsTableTableManager(_$AppDatabase db, $ShopsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShopsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShopsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShopsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShopsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String name,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShopsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$ShopsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                usersRefs = false,
                devicesRefs = false,
                categoriesRefs = false,
                productsRefs = false,
                productVariantsRefs = false,
                customersRefs = false,
                salesRefs = false,
                customerPaymentsRefs = false,
                expensesRefs = false,
                saleItemsRefs = false,
                saleSequencesRefs = false,
                stockMovementsRefs = false,
                suppliersRefs = false,
                purchasesRefs = false,
                purchaseItemsRefs = false,
                purchaseSequencesRefs = false,
                offersRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (usersRefs) db.users,
                    if (devicesRefs) db.devices,
                    if (categoriesRefs) db.categories,
                    if (productsRefs) db.products,
                    if (productVariantsRefs) db.productVariants,
                    if (customersRefs) db.customers,
                    if (salesRefs) db.sales,
                    if (customerPaymentsRefs) db.customerPayments,
                    if (expensesRefs) db.expenses,
                    if (saleItemsRefs) db.saleItems,
                    if (saleSequencesRefs) db.saleSequences,
                    if (stockMovementsRefs) db.stockMovements,
                    if (suppliersRefs) db.suppliers,
                    if (purchasesRefs) db.purchases,
                    if (purchaseItemsRefs) db.purchaseItems,
                    if (purchaseSequencesRefs) db.purchaseSequences,
                    if (offersRefs) db.offers,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (usersRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, User>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._usersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(db, table, p0).usersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (devicesRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Device>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._devicesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(db, table, p0).devicesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (categoriesRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Category>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._categoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).categoriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (productsRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Product>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._productsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).productsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (productVariantsRefs)
                        await $_getPrefetchedData<
                          Shop,
                          $ShopsTable,
                          ProductVariant
                        >(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._productVariantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).productVariantsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (customersRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Customer>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._customersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).customersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (salesRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Sale>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._salesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(db, table, p0).salesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (customerPaymentsRefs)
                        await $_getPrefetchedData<
                          Shop,
                          $ShopsTable,
                          CustomerPayment
                        >(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._customerPaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).customerPaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (expensesRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Expense>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._expensesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).expensesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (saleItemsRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, SaleItem>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._saleItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).saleItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (saleSequencesRefs)
                        await $_getPrefetchedData<
                          Shop,
                          $ShopsTable,
                          SaleSequence
                        >(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._saleSequencesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).saleSequencesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (stockMovementsRefs)
                        await $_getPrefetchedData<
                          Shop,
                          $ShopsTable,
                          StockMovement
                        >(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._stockMovementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).stockMovementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (suppliersRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Supplier>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._suppliersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).suppliersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (purchasesRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Purchase>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._purchasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).purchasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (purchaseItemsRefs)
                        await $_getPrefetchedData<
                          Shop,
                          $ShopsTable,
                          PurchaseItem
                        >(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._purchaseItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).purchaseItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (purchaseSequencesRefs)
                        await $_getPrefetchedData<
                          Shop,
                          $ShopsTable,
                          PurchaseSequence
                        >(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._purchaseSequencesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(
                                db,
                                table,
                                p0,
                              ).purchaseSequencesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (offersRefs)
                        await $_getPrefetchedData<Shop, $ShopsTable, Offer>(
                          currentTable: table,
                          referencedTable: $$ShopsTableReferences
                              ._offersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShopsTableReferences(db, table, p0).offersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.shopId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ShopsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShopsTable,
      Shop,
      $$ShopsTableFilterComposer,
      $$ShopsTableOrderingComposer,
      $$ShopsTableAnnotationComposer,
      $$ShopsTableCreateCompanionBuilder,
      $$ShopsTableUpdateCompanionBuilder,
      (Shop, $$ShopsTableReferences),
      Shop,
      PrefetchHooks Function({
        bool usersRefs,
        bool devicesRefs,
        bool categoriesRefs,
        bool productsRefs,
        bool productVariantsRefs,
        bool customersRefs,
        bool salesRefs,
        bool customerPaymentsRefs,
        bool expensesRefs,
        bool saleItemsRefs,
        bool saleSequencesRefs,
        bool stockMovementsRefs,
        bool suppliersRefs,
        bool purchasesRefs,
        bool purchaseItemsRefs,
        bool purchaseSequencesRefs,
        bool offersRefs,
      })
    >;
typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      Value<String> id,
      required String email,
      Value<String?> authUserId,
      Value<String?> shopId,
      Value<String?> displayName,
      Value<String?> role,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<String> id,
      Value<String> email,
      Value<String?> authUserId,
      Value<String?> shopId,
      Value<String?> displayName,
      Value<String?> role,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$UsersTableReferences
    extends BaseReferences<_$AppDatabase, $UsersTable, User> {
  $$UsersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) =>
      db.shops.createAlias($_aliasNameGenerator(db.users.shopId, db.shops.id));

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$StaffPermissionsTable, List<StaffPermission>>
  _staffPermissionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.staffPermissions,
    aliasName: $_aliasNameGenerator(db.users.id, db.staffPermissions.userId),
  );

  $$StaffPermissionsTableProcessedTableManager get staffPermissionsRefs {
    final manager = $$StaffPermissionsTableTableManager(
      $_db,
      $_db.staffPermissions,
    ).filter((f) => f.userId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _staffPermissionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authUserId => $composableBuilder(
    column: $table.authUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> staffPermissionsRefs(
    Expression<bool> Function($$StaffPermissionsTableFilterComposer f) f,
  ) {
    final $$StaffPermissionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.staffPermissions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StaffPermissionsTableFilterComposer(
            $db: $db,
            $table: $db.staffPermissions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authUserId => $composableBuilder(
    column: $table.authUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get authUserId => $composableBuilder(
    column: $table.authUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> staffPermissionsRefs<T extends Object>(
    Expression<T> Function($$StaffPermissionsTableAnnotationComposer a) f,
  ) {
    final $$StaffPermissionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.staffPermissions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StaffPermissionsTableAnnotationComposer(
            $db: $db,
            $table: $db.staffPermissions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, $$UsersTableReferences),
          User,
          PrefetchHooks Function({bool shopId, bool staffPermissionsRefs})
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String?> authUserId = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> role = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                id: id,
                email: email,
                authUserId: authUserId,
                shopId: shopId,
                displayName: displayName,
                role: role,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String email,
                Value<String?> authUserId = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> role = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                id: id,
                email: email,
                authUserId: authUserId,
                shopId: shopId,
                displayName: displayName,
                role: role,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$UsersTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({shopId = false, staffPermissionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (staffPermissionsRefs) db.staffPermissions,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable: $$UsersTableReferences
                                        ._shopIdTable(db),
                                    referencedColumn: $$UsersTableReferences
                                        ._shopIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (staffPermissionsRefs)
                        await $_getPrefetchedData<
                          User,
                          $UsersTable,
                          StaffPermission
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._staffPermissionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).staffPermissionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, $$UsersTableReferences),
      User,
      PrefetchHooks Function({bool shopId, bool staffPermissionsRefs})
    >;
typedef $$DevicesTableCreateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> id,
      required String shopId,
      required String userId,
      Value<String?> deviceName,
      Value<String?> platform,
      Value<DateTime> createdAt,
      Value<DateTime> lastSeenAt,
      Value<bool> isActive,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$DevicesTableUpdateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> id,
      Value<String> shopId,
      Value<String> userId,
      Value<String?> deviceName,
      Value<String?> platform,
      Value<DateTime> createdAt,
      Value<DateTime> lastSeenAt,
      Value<bool> isActive,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$DevicesTableReferences
    extends BaseReferences<_$AppDatabase, $DevicesTable, Device> {
  $$DevicesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.devices.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager get shopId {
    final $_column = $_itemColumn<String>('shop_id')!;

    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DevicesTableFilterComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DevicesTable,
          Device,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (Device, $$DevicesTableReferences),
          Device,
          PrefetchHooks Function({bool shopId})
        > {
  $$DevicesTableTableManager(_$AppDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> shopId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> deviceName = const Value.absent(),
                Value<String?> platform = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                id: id,
                shopId: shopId,
                userId: userId,
                deviceName: deviceName,
                platform: platform,
                createdAt: createdAt,
                lastSeenAt: lastSeenAt,
                isActive: isActive,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String shopId,
                required String userId,
                Value<String?> deviceName = const Value.absent(),
                Value<String?> platform = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                id: id,
                shopId: shopId,
                userId: userId,
                deviceName: deviceName,
                platform: platform,
                createdAt: createdAt,
                lastSeenAt: lastSeenAt,
                isActive: isActive,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DevicesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shopId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shopId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.shopId,
                                referencedTable: $$DevicesTableReferences
                                    ._shopIdTable(db),
                                referencedColumn: $$DevicesTableReferences
                                    ._shopIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DevicesTable,
      Device,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (Device, $$DevicesTableReferences),
      Device,
      PrefetchHooks Function({bool shopId})
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<String> id,
      required String deviceId,
      required String shopId,
      required String entity,
      required String entityId,
      Value<String> operation,
      required String payload,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<String> id,
      Value<String> deviceId,
      Value<String> shopId,
      Value<String> entity,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payload,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get shopId =>
      $composableBuilder(column: $table.shopId, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          SyncOutboxData,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxData,
            BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
          ),
          SyncOutboxData,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> shopId = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion(
                id: id,
                deviceId: deviceId,
                shopId: shopId,
                entity: entity,
                entityId: entityId,
                operation: operation,
                payload: payload,
                status: status,
                attemptCount: attemptCount,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String deviceId,
                required String shopId,
                required String entity,
                required String entityId,
                Value<String> operation = const Value.absent(),
                required String payload,
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                id: id,
                deviceId: deviceId,
                shopId: shopId,
                entity: entity,
                entityId: entityId,
                operation: operation,
                payload: payload,
                status: status,
                attemptCount: attemptCount,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      SyncOutboxData,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxData,
        BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
      ),
      SyncOutboxData,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      required String deviceId,
      required String shopId,
      Value<DateTime?> lastPulledAt,
      Value<DateTime?> lastPushedAt,
      Value<String?> lastError,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<String> deviceId,
      Value<String> shopId,
      Value<DateTime?> lastPulledAt,
      Value<DateTime?> lastPushedAt,
      Value<String?> lastError,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPushedAt => $composableBuilder(
    column: $table.lastPushedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPushedAt => $composableBuilder(
    column: $table.lastPushedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get shopId =>
      $composableBuilder(column: $table.shopId, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPushedAt => $composableBuilder(
    column: $table.lastPushedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String> shopId = const Value.absent(),
                Value<DateTime?> lastPulledAt = const Value.absent(),
                Value<DateTime?> lastPushedAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(
                deviceId: deviceId,
                shopId: shopId,
                lastPulledAt: lastPulledAt,
                lastPushedAt: lastPushedAt,
                lastError: lastError,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String shopId,
                Value<DateTime?> lastPulledAt = const Value.absent(),
                Value<DateTime?> lastPushedAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                deviceId: deviceId,
                shopId: shopId,
                lastPulledAt: lastPulledAt,
                lastPushedAt: lastPushedAt,
                lastError: lastError,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$StaffPermissionsTableCreateCompanionBuilder =
    StaffPermissionsCompanion Function({
      required String userId,
      required String permission,
      Value<bool> enabled,
      Value<int> rowid,
    });
typedef $$StaffPermissionsTableUpdateCompanionBuilder =
    StaffPermissionsCompanion Function({
      Value<String> userId,
      Value<String> permission,
      Value<bool> enabled,
      Value<int> rowid,
    });

final class $$StaffPermissionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $StaffPermissionsTable, StaffPermission> {
  $$StaffPermissionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $UsersTable _userIdTable(_$AppDatabase db) => db.users.createAlias(
    $_aliasNameGenerator(db.staffPermissions.userId, db.users.id),
  );

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StaffPermissionsTableFilterComposer
    extends Composer<_$AppDatabase, $StaffPermissionsTable> {
  $$StaffPermissionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StaffPermissionsTableOrderingComposer
    extends Composer<_$AppDatabase, $StaffPermissionsTable> {
  $$StaffPermissionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StaffPermissionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StaffPermissionsTable> {
  $$StaffPermissionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StaffPermissionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StaffPermissionsTable,
          StaffPermission,
          $$StaffPermissionsTableFilterComposer,
          $$StaffPermissionsTableOrderingComposer,
          $$StaffPermissionsTableAnnotationComposer,
          $$StaffPermissionsTableCreateCompanionBuilder,
          $$StaffPermissionsTableUpdateCompanionBuilder,
          (StaffPermission, $$StaffPermissionsTableReferences),
          StaffPermission,
          PrefetchHooks Function({bool userId})
        > {
  $$StaffPermissionsTableTableManager(
    _$AppDatabase db,
    $StaffPermissionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StaffPermissionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StaffPermissionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StaffPermissionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> permission = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StaffPermissionsCompanion(
                userId: userId,
                permission: permission,
                enabled: enabled,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String permission,
                Value<bool> enabled = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StaffPermissionsCompanion.insert(
                userId: userId,
                permission: permission,
                enabled: enabled,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StaffPermissionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable:
                                    $$StaffPermissionsTableReferences
                                        ._userIdTable(db),
                                referencedColumn:
                                    $$StaffPermissionsTableReferences
                                        ._userIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$StaffPermissionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StaffPermissionsTable,
      StaffPermission,
      $$StaffPermissionsTableFilterComposer,
      $$StaffPermissionsTableOrderingComposer,
      $$StaffPermissionsTableAnnotationComposer,
      $$StaffPermissionsTableCreateCompanionBuilder,
      $$StaffPermissionsTableUpdateCompanionBuilder,
      (StaffPermission, $$StaffPermissionsTableReferences),
      StaffPermission,
      PrefetchHooks Function({bool userId})
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String name,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> name,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, Category> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.categories.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ProductsTable, List<Product>> _productsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.products,
    aliasName: $_aliasNameGenerator(db.categories.id, db.products.categoryId),
  );

  $$ProductsTableProcessedTableManager get productsRefs {
    final manager = $$ProductsTableTableManager(
      $_db,
      $_db.products,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_productsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> productsRefs(
    Expression<bool> Function($$ProductsTableFilterComposer f) f,
  ) {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> productsRefs<T extends Object>(
    Expression<T> Function($$ProductsTableAnnotationComposer a) f,
  ) {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, $$CategoriesTableReferences),
          Category,
          PrefetchHooks Function({bool shopId, bool productsRefs})
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                shopId: shopId,
                name: name,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String name,
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                shopId: shopId,
                name: name,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shopId = false, productsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (productsRefs) db.products],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shopId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.shopId,
                                referencedTable: $$CategoriesTableReferences
                                    ._shopIdTable(db),
                                referencedColumn: $$CategoriesTableReferences
                                    ._shopIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (productsRefs)
                    await $_getPrefetchedData<
                      Category,
                      $CategoriesTable,
                      Product
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._productsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CategoriesTableReferences(
                            db,
                            table,
                            p0,
                          ).productsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, $$CategoriesTableReferences),
      Category,
      PrefetchHooks Function({bool shopId, bool productsRefs})
    >;
typedef $$ProductsTableCreateCompanionBuilder =
    ProductsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String categoryId,
      required String name,
      Value<String?> sku,
      required int sellingPricePaise,
      Value<int?> costPricePaise,
      Value<int> stockQuantity,
      Value<String> stockUnit,
      Value<String> lowStockMode,
      Value<int?> lowStockThreshold,
      Value<bool> membershipEnabled,
      Value<int?> memberPricePaise,
      Value<String?> imagePath,
      Value<String?> cloudImagePath,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ProductsTableUpdateCompanionBuilder =
    ProductsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> categoryId,
      Value<String> name,
      Value<String?> sku,
      Value<int> sellingPricePaise,
      Value<int?> costPricePaise,
      Value<int> stockQuantity,
      Value<String> stockUnit,
      Value<String> lowStockMode,
      Value<int?> lowStockThreshold,
      Value<bool> membershipEnabled,
      Value<int?> memberPricePaise,
      Value<String?> imagePath,
      Value<String?> cloudImagePath,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ProductsTableReferences
    extends BaseReferences<_$AppDatabase, $ProductsTable, Product> {
  $$ProductsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.products.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias(
        $_aliasNameGenerator(db.products.categoryId, db.categories.id),
      );

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ProductVariantsTable, List<ProductVariant>>
  _productVariantsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.productVariants,
    aliasName: $_aliasNameGenerator(
      db.products.id,
      db.productVariants.productId,
    ),
  );

  $$ProductVariantsTableProcessedTableManager get productVariantsRefs {
    final manager = $$ProductVariantsTableTableManager(
      $_db,
      $_db.productVariants,
    ).filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _productVariantsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SaleItemsTable, List<SaleItem>>
  _saleItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.saleItems,
    aliasName: $_aliasNameGenerator(db.products.id, db.saleItems.productId),
  );

  $$SaleItemsTableProcessedTableManager get saleItemsRefs {
    final manager = $$SaleItemsTableTableManager(
      $_db,
      $_db.saleItems,
    ).filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_saleItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$StockMovementsTable, List<StockMovement>>
  _stockMovementsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.stockMovements,
    aliasName: $_aliasNameGenerator(
      db.products.id,
      db.stockMovements.productId,
    ),
  );

  $$StockMovementsTableProcessedTableManager get stockMovementsRefs {
    final manager = $$StockMovementsTableTableManager(
      $_db,
      $_db.stockMovements,
    ).filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_stockMovementsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PurchaseItemsTable, List<PurchaseItem>>
  _purchaseItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.purchaseItems,
    aliasName: $_aliasNameGenerator(db.products.id, db.purchaseItems.productId),
  );

  $$PurchaseItemsTableProcessedTableManager get purchaseItemsRefs {
    final manager = $$PurchaseItemsTableTableManager(
      $_db,
      $_db.purchaseItems,
    ).filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_purchaseItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sellingPricePaise => $composableBuilder(
    column: $table.sellingPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get costPricePaise => $composableBuilder(
    column: $table.costPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stockQuantity => $composableBuilder(
    column: $table.stockQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stockUnit => $composableBuilder(
    column: $table.stockUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lowStockMode => $composableBuilder(
    column: $table.lowStockMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lowStockThreshold => $composableBuilder(
    column: $table.lowStockThreshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get membershipEnabled => $composableBuilder(
    column: $table.membershipEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memberPricePaise => $composableBuilder(
    column: $table.memberPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudImagePath => $composableBuilder(
    column: $table.cloudImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> productVariantsRefs(
    Expression<bool> Function($$ProductVariantsTableFilterComposer f) f,
  ) {
    final $$ProductVariantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableFilterComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> saleItemsRefs(
    Expression<bool> Function($$SaleItemsTableFilterComposer f) f,
  ) {
    final $$SaleItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleItems,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleItemsTableFilterComposer(
            $db: $db,
            $table: $db.saleItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> stockMovementsRefs(
    Expression<bool> Function($$StockMovementsTableFilterComposer f) f,
  ) {
    final $$StockMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stockMovements,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StockMovementsTableFilterComposer(
            $db: $db,
            $table: $db.stockMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> purchaseItemsRefs(
    Expression<bool> Function($$PurchaseItemsTableFilterComposer f) f,
  ) {
    final $$PurchaseItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseItems,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseItemsTableFilterComposer(
            $db: $db,
            $table: $db.purchaseItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sellingPricePaise => $composableBuilder(
    column: $table.sellingPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get costPricePaise => $composableBuilder(
    column: $table.costPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stockQuantity => $composableBuilder(
    column: $table.stockQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stockUnit => $composableBuilder(
    column: $table.stockUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lowStockMode => $composableBuilder(
    column: $table.lowStockMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lowStockThreshold => $composableBuilder(
    column: $table.lowStockThreshold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get membershipEnabled => $composableBuilder(
    column: $table.membershipEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memberPricePaise => $composableBuilder(
    column: $table.memberPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudImagePath => $composableBuilder(
    column: $table.cloudImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<int> get sellingPricePaise => $composableBuilder(
    column: $table.sellingPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get costPricePaise => $composableBuilder(
    column: $table.costPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stockQuantity => $composableBuilder(
    column: $table.stockQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stockUnit =>
      $composableBuilder(column: $table.stockUnit, builder: (column) => column);

  GeneratedColumn<String> get lowStockMode => $composableBuilder(
    column: $table.lowStockMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lowStockThreshold => $composableBuilder(
    column: $table.lowStockThreshold,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get membershipEnabled => $composableBuilder(
    column: $table.membershipEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get memberPricePaise => $composableBuilder(
    column: $table.memberPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get cloudImagePath => $composableBuilder(
    column: $table.cloudImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> productVariantsRefs<T extends Object>(
    Expression<T> Function($$ProductVariantsTableAnnotationComposer a) f,
  ) {
    final $$ProductVariantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableAnnotationComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> saleItemsRefs<T extends Object>(
    Expression<T> Function($$SaleItemsTableAnnotationComposer a) f,
  ) {
    final $$SaleItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleItems,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.saleItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> stockMovementsRefs<T extends Object>(
    Expression<T> Function($$StockMovementsTableAnnotationComposer a) f,
  ) {
    final $$StockMovementsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stockMovements,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StockMovementsTableAnnotationComposer(
            $db: $db,
            $table: $db.stockMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> purchaseItemsRefs<T extends Object>(
    Expression<T> Function($$PurchaseItemsTableAnnotationComposer a) f,
  ) {
    final $$PurchaseItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseItems,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.purchaseItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductsTable,
          Product,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (Product, $$ProductsTableReferences),
          Product,
          PrefetchHooks Function({
            bool shopId,
            bool categoryId,
            bool productVariantsRefs,
            bool saleItemsRefs,
            bool stockMovementsRefs,
            bool purchaseItemsRefs,
          })
        > {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<int> sellingPricePaise = const Value.absent(),
                Value<int?> costPricePaise = const Value.absent(),
                Value<int> stockQuantity = const Value.absent(),
                Value<String> stockUnit = const Value.absent(),
                Value<String> lowStockMode = const Value.absent(),
                Value<int?> lowStockThreshold = const Value.absent(),
                Value<bool> membershipEnabled = const Value.absent(),
                Value<int?> memberPricePaise = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> cloudImagePath = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion(
                id: id,
                shopId: shopId,
                categoryId: categoryId,
                name: name,
                sku: sku,
                sellingPricePaise: sellingPricePaise,
                costPricePaise: costPricePaise,
                stockQuantity: stockQuantity,
                stockUnit: stockUnit,
                lowStockMode: lowStockMode,
                lowStockThreshold: lowStockThreshold,
                membershipEnabled: membershipEnabled,
                memberPricePaise: memberPricePaise,
                imagePath: imagePath,
                cloudImagePath: cloudImagePath,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String categoryId,
                required String name,
                Value<String?> sku = const Value.absent(),
                required int sellingPricePaise,
                Value<int?> costPricePaise = const Value.absent(),
                Value<int> stockQuantity = const Value.absent(),
                Value<String> stockUnit = const Value.absent(),
                Value<String> lowStockMode = const Value.absent(),
                Value<int?> lowStockThreshold = const Value.absent(),
                Value<bool> membershipEnabled = const Value.absent(),
                Value<int?> memberPricePaise = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> cloudImagePath = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion.insert(
                id: id,
                shopId: shopId,
                categoryId: categoryId,
                name: name,
                sku: sku,
                sellingPricePaise: sellingPricePaise,
                costPricePaise: costPricePaise,
                stockQuantity: stockQuantity,
                stockUnit: stockUnit,
                lowStockMode: lowStockMode,
                lowStockThreshold: lowStockThreshold,
                membershipEnabled: membershipEnabled,
                memberPricePaise: memberPricePaise,
                imagePath: imagePath,
                cloudImagePath: cloudImagePath,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProductsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                shopId = false,
                categoryId = false,
                productVariantsRefs = false,
                saleItemsRefs = false,
                stockMovementsRefs = false,
                purchaseItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (productVariantsRefs) db.productVariants,
                    if (saleItemsRefs) db.saleItems,
                    if (stockMovementsRefs) db.stockMovements,
                    if (purchaseItemsRefs) db.purchaseItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable: $$ProductsTableReferences
                                        ._shopIdTable(db),
                                    referencedColumn: $$ProductsTableReferences
                                        ._shopIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable: $$ProductsTableReferences
                                        ._categoryIdTable(db),
                                    referencedColumn: $$ProductsTableReferences
                                        ._categoryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (productVariantsRefs)
                        await $_getPrefetchedData<
                          Product,
                          $ProductsTable,
                          ProductVariant
                        >(
                          currentTable: table,
                          referencedTable: $$ProductsTableReferences
                              ._productVariantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProductsTableReferences(
                                db,
                                table,
                                p0,
                              ).productVariantsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.productId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (saleItemsRefs)
                        await $_getPrefetchedData<
                          Product,
                          $ProductsTable,
                          SaleItem
                        >(
                          currentTable: table,
                          referencedTable: $$ProductsTableReferences
                              ._saleItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProductsTableReferences(
                                db,
                                table,
                                p0,
                              ).saleItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.productId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (stockMovementsRefs)
                        await $_getPrefetchedData<
                          Product,
                          $ProductsTable,
                          StockMovement
                        >(
                          currentTable: table,
                          referencedTable: $$ProductsTableReferences
                              ._stockMovementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProductsTableReferences(
                                db,
                                table,
                                p0,
                              ).stockMovementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.productId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (purchaseItemsRefs)
                        await $_getPrefetchedData<
                          Product,
                          $ProductsTable,
                          PurchaseItem
                        >(
                          currentTable: table,
                          referencedTable: $$ProductsTableReferences
                              ._purchaseItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProductsTableReferences(
                                db,
                                table,
                                p0,
                              ).purchaseItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.productId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductsTable,
      Product,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (Product, $$ProductsTableReferences),
      Product,
      PrefetchHooks Function({
        bool shopId,
        bool categoryId,
        bool productVariantsRefs,
        bool saleItemsRefs,
        bool stockMovementsRefs,
        bool purchaseItemsRefs,
      })
    >;
typedef $$ProductVariantsTableCreateCompanionBuilder =
    ProductVariantsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String productId,
      required String name,
      Value<String?> sku,
      required int sellingPricePaise,
      Value<int?> costPricePaise,
      Value<int> stockQuantity,
      Value<String> lowStockMode,
      Value<int?> lowStockThreshold,
      Value<bool> membershipEnabled,
      Value<int?> memberPricePaise,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ProductVariantsTableUpdateCompanionBuilder =
    ProductVariantsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> productId,
      Value<String> name,
      Value<String?> sku,
      Value<int> sellingPricePaise,
      Value<int?> costPricePaise,
      Value<int> stockQuantity,
      Value<String> lowStockMode,
      Value<int?> lowStockThreshold,
      Value<bool> membershipEnabled,
      Value<int?> memberPricePaise,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ProductVariantsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ProductVariantsTable, ProductVariant> {
  $$ProductVariantsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.productVariants.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias(
        $_aliasNameGenerator(db.productVariants.productId, db.products.id),
      );

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager(
      $_db,
      $_db.products,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SaleItemsTable, List<SaleItem>>
  _saleItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.saleItems,
    aliasName: $_aliasNameGenerator(
      db.productVariants.id,
      db.saleItems.variantId,
    ),
  );

  $$SaleItemsTableProcessedTableManager get saleItemsRefs {
    final manager = $$SaleItemsTableTableManager(
      $_db,
      $_db.saleItems,
    ).filter((f) => f.variantId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_saleItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$StockMovementsTable, List<StockMovement>>
  _stockMovementsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.stockMovements,
    aliasName: $_aliasNameGenerator(
      db.productVariants.id,
      db.stockMovements.variantId,
    ),
  );

  $$StockMovementsTableProcessedTableManager get stockMovementsRefs {
    final manager = $$StockMovementsTableTableManager(
      $_db,
      $_db.stockMovements,
    ).filter((f) => f.variantId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_stockMovementsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PurchaseItemsTable, List<PurchaseItem>>
  _purchaseItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.purchaseItems,
    aliasName: $_aliasNameGenerator(
      db.productVariants.id,
      db.purchaseItems.variantId,
    ),
  );

  $$PurchaseItemsTableProcessedTableManager get purchaseItemsRefs {
    final manager = $$PurchaseItemsTableTableManager(
      $_db,
      $_db.purchaseItems,
    ).filter((f) => f.variantId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_purchaseItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProductVariantsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sellingPricePaise => $composableBuilder(
    column: $table.sellingPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get costPricePaise => $composableBuilder(
    column: $table.costPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stockQuantity => $composableBuilder(
    column: $table.stockQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lowStockMode => $composableBuilder(
    column: $table.lowStockMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lowStockThreshold => $composableBuilder(
    column: $table.lowStockThreshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get membershipEnabled => $composableBuilder(
    column: $table.membershipEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memberPricePaise => $composableBuilder(
    column: $table.memberPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> saleItemsRefs(
    Expression<bool> Function($$SaleItemsTableFilterComposer f) f,
  ) {
    final $$SaleItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleItems,
      getReferencedColumn: (t) => t.variantId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleItemsTableFilterComposer(
            $db: $db,
            $table: $db.saleItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> stockMovementsRefs(
    Expression<bool> Function($$StockMovementsTableFilterComposer f) f,
  ) {
    final $$StockMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stockMovements,
      getReferencedColumn: (t) => t.variantId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StockMovementsTableFilterComposer(
            $db: $db,
            $table: $db.stockMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> purchaseItemsRefs(
    Expression<bool> Function($$PurchaseItemsTableFilterComposer f) f,
  ) {
    final $$PurchaseItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseItems,
      getReferencedColumn: (t) => t.variantId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseItemsTableFilterComposer(
            $db: $db,
            $table: $db.purchaseItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProductVariantsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sellingPricePaise => $composableBuilder(
    column: $table.sellingPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get costPricePaise => $composableBuilder(
    column: $table.costPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stockQuantity => $composableBuilder(
    column: $table.stockQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lowStockMode => $composableBuilder(
    column: $table.lowStockMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lowStockThreshold => $composableBuilder(
    column: $table.lowStockThreshold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get membershipEnabled => $composableBuilder(
    column: $table.membershipEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memberPricePaise => $composableBuilder(
    column: $table.memberPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableOrderingComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductVariantsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<int> get sellingPricePaise => $composableBuilder(
    column: $table.sellingPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get costPricePaise => $composableBuilder(
    column: $table.costPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stockQuantity => $composableBuilder(
    column: $table.stockQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lowStockMode => $composableBuilder(
    column: $table.lowStockMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lowStockThreshold => $composableBuilder(
    column: $table.lowStockThreshold,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get membershipEnabled => $composableBuilder(
    column: $table.membershipEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get memberPricePaise => $composableBuilder(
    column: $table.memberPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> saleItemsRefs<T extends Object>(
    Expression<T> Function($$SaleItemsTableAnnotationComposer a) f,
  ) {
    final $$SaleItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleItems,
      getReferencedColumn: (t) => t.variantId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.saleItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> stockMovementsRefs<T extends Object>(
    Expression<T> Function($$StockMovementsTableAnnotationComposer a) f,
  ) {
    final $$StockMovementsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stockMovements,
      getReferencedColumn: (t) => t.variantId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StockMovementsTableAnnotationComposer(
            $db: $db,
            $table: $db.stockMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> purchaseItemsRefs<T extends Object>(
    Expression<T> Function($$PurchaseItemsTableAnnotationComposer a) f,
  ) {
    final $$PurchaseItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseItems,
      getReferencedColumn: (t) => t.variantId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.purchaseItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProductVariantsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductVariantsTable,
          ProductVariant,
          $$ProductVariantsTableFilterComposer,
          $$ProductVariantsTableOrderingComposer,
          $$ProductVariantsTableAnnotationComposer,
          $$ProductVariantsTableCreateCompanionBuilder,
          $$ProductVariantsTableUpdateCompanionBuilder,
          (ProductVariant, $$ProductVariantsTableReferences),
          ProductVariant,
          PrefetchHooks Function({
            bool shopId,
            bool productId,
            bool saleItemsRefs,
            bool stockMovementsRefs,
            bool purchaseItemsRefs,
          })
        > {
  $$ProductVariantsTableTableManager(
    _$AppDatabase db,
    $ProductVariantsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductVariantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductVariantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductVariantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<int> sellingPricePaise = const Value.absent(),
                Value<int?> costPricePaise = const Value.absent(),
                Value<int> stockQuantity = const Value.absent(),
                Value<String> lowStockMode = const Value.absent(),
                Value<int?> lowStockThreshold = const Value.absent(),
                Value<bool> membershipEnabled = const Value.absent(),
                Value<int?> memberPricePaise = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductVariantsCompanion(
                id: id,
                shopId: shopId,
                productId: productId,
                name: name,
                sku: sku,
                sellingPricePaise: sellingPricePaise,
                costPricePaise: costPricePaise,
                stockQuantity: stockQuantity,
                lowStockMode: lowStockMode,
                lowStockThreshold: lowStockThreshold,
                membershipEnabled: membershipEnabled,
                memberPricePaise: memberPricePaise,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String productId,
                required String name,
                Value<String?> sku = const Value.absent(),
                required int sellingPricePaise,
                Value<int?> costPricePaise = const Value.absent(),
                Value<int> stockQuantity = const Value.absent(),
                Value<String> lowStockMode = const Value.absent(),
                Value<int?> lowStockThreshold = const Value.absent(),
                Value<bool> membershipEnabled = const Value.absent(),
                Value<int?> memberPricePaise = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductVariantsCompanion.insert(
                id: id,
                shopId: shopId,
                productId: productId,
                name: name,
                sku: sku,
                sellingPricePaise: sellingPricePaise,
                costPricePaise: costPricePaise,
                stockQuantity: stockQuantity,
                lowStockMode: lowStockMode,
                lowStockThreshold: lowStockThreshold,
                membershipEnabled: membershipEnabled,
                memberPricePaise: memberPricePaise,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProductVariantsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                shopId = false,
                productId = false,
                saleItemsRefs = false,
                stockMovementsRefs = false,
                purchaseItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (saleItemsRefs) db.saleItems,
                    if (stockMovementsRefs) db.stockMovements,
                    if (purchaseItemsRefs) db.purchaseItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable:
                                        $$ProductVariantsTableReferences
                                            ._shopIdTable(db),
                                    referencedColumn:
                                        $$ProductVariantsTableReferences
                                            ._shopIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (productId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.productId,
                                    referencedTable:
                                        $$ProductVariantsTableReferences
                                            ._productIdTable(db),
                                    referencedColumn:
                                        $$ProductVariantsTableReferences
                                            ._productIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (saleItemsRefs)
                        await $_getPrefetchedData<
                          ProductVariant,
                          $ProductVariantsTable,
                          SaleItem
                        >(
                          currentTable: table,
                          referencedTable: $$ProductVariantsTableReferences
                              ._saleItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProductVariantsTableReferences(
                                db,
                                table,
                                p0,
                              ).saleItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.variantId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (stockMovementsRefs)
                        await $_getPrefetchedData<
                          ProductVariant,
                          $ProductVariantsTable,
                          StockMovement
                        >(
                          currentTable: table,
                          referencedTable: $$ProductVariantsTableReferences
                              ._stockMovementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProductVariantsTableReferences(
                                db,
                                table,
                                p0,
                              ).stockMovementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.variantId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (purchaseItemsRefs)
                        await $_getPrefetchedData<
                          ProductVariant,
                          $ProductVariantsTable,
                          PurchaseItem
                        >(
                          currentTable: table,
                          referencedTable: $$ProductVariantsTableReferences
                              ._purchaseItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProductVariantsTableReferences(
                                db,
                                table,
                                p0,
                              ).purchaseItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.variantId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProductVariantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductVariantsTable,
      ProductVariant,
      $$ProductVariantsTableFilterComposer,
      $$ProductVariantsTableOrderingComposer,
      $$ProductVariantsTableAnnotationComposer,
      $$ProductVariantsTableCreateCompanionBuilder,
      $$ProductVariantsTableUpdateCompanionBuilder,
      (ProductVariant, $$ProductVariantsTableReferences),
      ProductVariant,
      PrefetchHooks Function({
        bool shopId,
        bool productId,
        bool saleItemsRefs,
        bool stockMovementsRefs,
        bool purchaseItemsRefs,
      })
    >;
typedef $$CustomersTableCreateCompanionBuilder =
    CustomersCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String name,
      Value<String?> phone,
      Value<String?> email,
      Value<String?> address,
      Value<bool> isActive,
      Value<bool> membershipActive,
      Value<int?> membershipFeePaise,
      Value<String> whatsappStatus,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$CustomersTableUpdateCompanionBuilder =
    CustomersCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> name,
      Value<String?> phone,
      Value<String?> email,
      Value<String?> address,
      Value<bool> isActive,
      Value<bool> membershipActive,
      Value<int?> membershipFeePaise,
      Value<String> whatsappStatus,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$CustomersTableReferences
    extends BaseReferences<_$AppDatabase, $CustomersTable, Customer> {
  $$CustomersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.customers.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SalesTable, List<Sale>> _salesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.sales,
    aliasName: $_aliasNameGenerator(db.customers.id, db.sales.customerId),
  );

  $$SalesTableProcessedTableManager get salesRefs {
    final manager = $$SalesTableTableManager(
      $_db,
      $_db.sales,
    ).filter((f) => f.customerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_salesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CustomerPaymentsTable, List<CustomerPayment>>
  _customerPaymentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.customerPayments,
    aliasName: $_aliasNameGenerator(
      db.customers.id,
      db.customerPayments.customerId,
    ),
  );

  $$CustomerPaymentsTableProcessedTableManager get customerPaymentsRefs {
    final manager = $$CustomerPaymentsTableTableManager(
      $_db,
      $_db.customerPayments,
    ).filter((f) => f.customerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _customerPaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CustomersTableFilterComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get membershipActive => $composableBuilder(
    column: $table.membershipActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get membershipFeePaise => $composableBuilder(
    column: $table.membershipFeePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get whatsappStatus => $composableBuilder(
    column: $table.whatsappStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> salesRefs(
    Expression<bool> Function($$SalesTableFilterComposer f) f,
  ) {
    final $$SalesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.customerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableFilterComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> customerPaymentsRefs(
    Expression<bool> Function($$CustomerPaymentsTableFilterComposer f) f,
  ) {
    final $$CustomerPaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customerPayments,
      getReferencedColumn: (t) => t.customerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomerPaymentsTableFilterComposer(
            $db: $db,
            $table: $db.customerPayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get membershipActive => $composableBuilder(
    column: $table.membershipActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get membershipFeePaise => $composableBuilder(
    column: $table.membershipFeePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get whatsappStatus => $composableBuilder(
    column: $table.whatsappStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<bool> get membershipActive => $composableBuilder(
    column: $table.membershipActive,
    builder: (column) => column,
  );

  GeneratedColumn<int> get membershipFeePaise => $composableBuilder(
    column: $table.membershipFeePaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get whatsappStatus => $composableBuilder(
    column: $table.whatsappStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> salesRefs<T extends Object>(
    Expression<T> Function($$SalesTableAnnotationComposer a) f,
  ) {
    final $$SalesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.customerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableAnnotationComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> customerPaymentsRefs<T extends Object>(
    Expression<T> Function($$CustomerPaymentsTableAnnotationComposer a) f,
  ) {
    final $$CustomerPaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customerPayments,
      getReferencedColumn: (t) => t.customerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomerPaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.customerPayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CustomersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomersTable,
          Customer,
          $$CustomersTableFilterComposer,
          $$CustomersTableOrderingComposer,
          $$CustomersTableAnnotationComposer,
          $$CustomersTableCreateCompanionBuilder,
          $$CustomersTableUpdateCompanionBuilder,
          (Customer, $$CustomersTableReferences),
          Customer,
          PrefetchHooks Function({
            bool shopId,
            bool salesRefs,
            bool customerPaymentsRefs,
          })
        > {
  $$CustomersTableTableManager(_$AppDatabase db, $CustomersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<bool> membershipActive = const Value.absent(),
                Value<int?> membershipFeePaise = const Value.absent(),
                Value<String> whatsappStatus = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomersCompanion(
                id: id,
                shopId: shopId,
                name: name,
                phone: phone,
                email: email,
                address: address,
                isActive: isActive,
                membershipActive: membershipActive,
                membershipFeePaise: membershipFeePaise,
                whatsappStatus: whatsappStatus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<bool> membershipActive = const Value.absent(),
                Value<int?> membershipFeePaise = const Value.absent(),
                Value<String> whatsappStatus = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomersCompanion.insert(
                id: id,
                shopId: shopId,
                name: name,
                phone: phone,
                email: email,
                address: address,
                isActive: isActive,
                membershipActive: membershipActive,
                membershipFeePaise: membershipFeePaise,
                whatsappStatus: whatsappStatus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CustomersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                shopId = false,
                salesRefs = false,
                customerPaymentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (salesRefs) db.sales,
                    if (customerPaymentsRefs) db.customerPayments,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable: $$CustomersTableReferences
                                        ._shopIdTable(db),
                                    referencedColumn: $$CustomersTableReferences
                                        ._shopIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (salesRefs)
                        await $_getPrefetchedData<
                          Customer,
                          $CustomersTable,
                          Sale
                        >(
                          currentTable: table,
                          referencedTable: $$CustomersTableReferences
                              ._salesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CustomersTableReferences(
                                db,
                                table,
                                p0,
                              ).salesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.customerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (customerPaymentsRefs)
                        await $_getPrefetchedData<
                          Customer,
                          $CustomersTable,
                          CustomerPayment
                        >(
                          currentTable: table,
                          referencedTable: $$CustomersTableReferences
                              ._customerPaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CustomersTableReferences(
                                db,
                                table,
                                p0,
                              ).customerPaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.customerId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomersTable,
      Customer,
      $$CustomersTableFilterComposer,
      $$CustomersTableOrderingComposer,
      $$CustomersTableAnnotationComposer,
      $$CustomersTableCreateCompanionBuilder,
      $$CustomersTableUpdateCompanionBuilder,
      (Customer, $$CustomersTableReferences),
      Customer,
      PrefetchHooks Function({
        bool shopId,
        bool salesRefs,
        bool customerPaymentsRefs,
      })
    >;
typedef $$SalesTableCreateCompanionBuilder =
    SalesCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String?> customerId,
      required String receiptNumber,
      required int subtotalPaise,
      required int totalPaise,
      Value<int> offerDiscountPaise,
      Value<String?> paymentMethod,
      Value<String> paymentStatus,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> voided,
      Value<DateTime?> voidedAt,
      Value<int> rowid,
    });
typedef $$SalesTableUpdateCompanionBuilder =
    SalesCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String?> customerId,
      Value<String> receiptNumber,
      Value<int> subtotalPaise,
      Value<int> totalPaise,
      Value<int> offerDiscountPaise,
      Value<String?> paymentMethod,
      Value<String> paymentStatus,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> voided,
      Value<DateTime?> voidedAt,
      Value<int> rowid,
    });

final class $$SalesTableReferences
    extends BaseReferences<_$AppDatabase, $SalesTable, Sale> {
  $$SalesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) =>
      db.shops.createAlias($_aliasNameGenerator(db.sales.shopId, db.shops.id));

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CustomersTable _customerIdTable(_$AppDatabase db) => db.customers
      .createAlias($_aliasNameGenerator(db.sales.customerId, db.customers.id));

  $$CustomersTableProcessedTableManager? get customerId {
    final $_column = $_itemColumn<String>('customer_id');
    if ($_column == null) return null;
    final manager = $$CustomersTableTableManager(
      $_db,
      $_db.customers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_customerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$CustomerPaymentsTable, List<CustomerPayment>>
  _customerPaymentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.customerPayments,
    aliasName: $_aliasNameGenerator(db.sales.id, db.customerPayments.saleId),
  );

  $$CustomerPaymentsTableProcessedTableManager get customerPaymentsRefs {
    final manager = $$CustomerPaymentsTableTableManager(
      $_db,
      $_db.customerPayments,
    ).filter((f) => f.saleId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _customerPaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SaleItemsTable, List<SaleItem>>
  _saleItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.saleItems,
    aliasName: $_aliasNameGenerator(db.sales.id, db.saleItems.saleId),
  );

  $$SaleItemsTableProcessedTableManager get saleItemsRefs {
    final manager = $$SaleItemsTableTableManager(
      $_db,
      $_db.saleItems,
    ).filter((f) => f.saleId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_saleItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SalesTableFilterComposer extends Composer<_$AppDatabase, $SalesTable> {
  $$SalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get offerDiscountPaise => $composableBuilder(
    column: $table.offerDiscountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get voided => $composableBuilder(
    column: $table.voided,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get voidedAt => $composableBuilder(
    column: $table.voidedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableFilterComposer get customerId {
    final $$CustomersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableFilterComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> customerPaymentsRefs(
    Expression<bool> Function($$CustomerPaymentsTableFilterComposer f) f,
  ) {
    final $$CustomerPaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customerPayments,
      getReferencedColumn: (t) => t.saleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomerPaymentsTableFilterComposer(
            $db: $db,
            $table: $db.customerPayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> saleItemsRefs(
    Expression<bool> Function($$SaleItemsTableFilterComposer f) f,
  ) {
    final $$SaleItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleItems,
      getReferencedColumn: (t) => t.saleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleItemsTableFilterComposer(
            $db: $db,
            $table: $db.saleItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SalesTableOrderingComposer
    extends Composer<_$AppDatabase, $SalesTable> {
  $$SalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offerDiscountPaise => $composableBuilder(
    column: $table.offerDiscountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get voided => $composableBuilder(
    column: $table.voided,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get voidedAt => $composableBuilder(
    column: $table.voidedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableOrderingComposer get customerId {
    final $$CustomersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableOrderingComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SalesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SalesTable> {
  $$SalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get offerDiscountPaise => $composableBuilder(
    column: $table.offerDiscountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get voided =>
      $composableBuilder(column: $table.voided, builder: (column) => column);

  GeneratedColumn<DateTime> get voidedAt =>
      $composableBuilder(column: $table.voidedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableAnnotationComposer get customerId {
    final $$CustomersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableAnnotationComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> customerPaymentsRefs<T extends Object>(
    Expression<T> Function($$CustomerPaymentsTableAnnotationComposer a) f,
  ) {
    final $$CustomerPaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customerPayments,
      getReferencedColumn: (t) => t.saleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomerPaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.customerPayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> saleItemsRefs<T extends Object>(
    Expression<T> Function($$SaleItemsTableAnnotationComposer a) f,
  ) {
    final $$SaleItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saleItems,
      getReferencedColumn: (t) => t.saleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaleItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.saleItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SalesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SalesTable,
          Sale,
          $$SalesTableFilterComposer,
          $$SalesTableOrderingComposer,
          $$SalesTableAnnotationComposer,
          $$SalesTableCreateCompanionBuilder,
          $$SalesTableUpdateCompanionBuilder,
          (Sale, $$SalesTableReferences),
          Sale,
          PrefetchHooks Function({
            bool shopId,
            bool customerId,
            bool customerPaymentsRefs,
            bool saleItemsRefs,
          })
        > {
  $$SalesTableTableManager(_$AppDatabase db, $SalesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String> receiptNumber = const Value.absent(),
                Value<int> subtotalPaise = const Value.absent(),
                Value<int> totalPaise = const Value.absent(),
                Value<int> offerDiscountPaise = const Value.absent(),
                Value<String?> paymentMethod = const Value.absent(),
                Value<String> paymentStatus = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> voided = const Value.absent(),
                Value<DateTime?> voidedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SalesCompanion(
                id: id,
                shopId: shopId,
                customerId: customerId,
                receiptNumber: receiptNumber,
                subtotalPaise: subtotalPaise,
                totalPaise: totalPaise,
                offerDiscountPaise: offerDiscountPaise,
                paymentMethod: paymentMethod,
                paymentStatus: paymentStatus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                voided: voided,
                voidedAt: voidedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                required String receiptNumber,
                required int subtotalPaise,
                required int totalPaise,
                Value<int> offerDiscountPaise = const Value.absent(),
                Value<String?> paymentMethod = const Value.absent(),
                Value<String> paymentStatus = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> voided = const Value.absent(),
                Value<DateTime?> voidedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SalesCompanion.insert(
                id: id,
                shopId: shopId,
                customerId: customerId,
                receiptNumber: receiptNumber,
                subtotalPaise: subtotalPaise,
                totalPaise: totalPaise,
                offerDiscountPaise: offerDiscountPaise,
                paymentMethod: paymentMethod,
                paymentStatus: paymentStatus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                voided: voided,
                voidedAt: voidedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$SalesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                shopId = false,
                customerId = false,
                customerPaymentsRefs = false,
                saleItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (customerPaymentsRefs) db.customerPayments,
                    if (saleItemsRefs) db.saleItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable: $$SalesTableReferences
                                        ._shopIdTable(db),
                                    referencedColumn: $$SalesTableReferences
                                        ._shopIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (customerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.customerId,
                                    referencedTable: $$SalesTableReferences
                                        ._customerIdTable(db),
                                    referencedColumn: $$SalesTableReferences
                                        ._customerIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (customerPaymentsRefs)
                        await $_getPrefetchedData<
                          Sale,
                          $SalesTable,
                          CustomerPayment
                        >(
                          currentTable: table,
                          referencedTable: $$SalesTableReferences
                              ._customerPaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SalesTableReferences(
                                db,
                                table,
                                p0,
                              ).customerPaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.saleId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (saleItemsRefs)
                        await $_getPrefetchedData<Sale, $SalesTable, SaleItem>(
                          currentTable: table,
                          referencedTable: $$SalesTableReferences
                              ._saleItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SalesTableReferences(
                                db,
                                table,
                                p0,
                              ).saleItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.saleId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SalesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SalesTable,
      Sale,
      $$SalesTableFilterComposer,
      $$SalesTableOrderingComposer,
      $$SalesTableAnnotationComposer,
      $$SalesTableCreateCompanionBuilder,
      $$SalesTableUpdateCompanionBuilder,
      (Sale, $$SalesTableReferences),
      Sale,
      PrefetchHooks Function({
        bool shopId,
        bool customerId,
        bool customerPaymentsRefs,
        bool saleItemsRefs,
      })
    >;
typedef $$CustomerPaymentsTableCreateCompanionBuilder =
    CustomerPaymentsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String customerId,
      Value<String?> saleId,
      required int amountPaise,
      required String paymentMethod,
      Value<String?> note,
      required DateTime paidAt,
      Value<bool> reversed,
      Value<DateTime?> reversedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$CustomerPaymentsTableUpdateCompanionBuilder =
    CustomerPaymentsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> customerId,
      Value<String?> saleId,
      Value<int> amountPaise,
      Value<String> paymentMethod,
      Value<String?> note,
      Value<DateTime> paidAt,
      Value<bool> reversed,
      Value<DateTime?> reversedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$CustomerPaymentsTableReferences
    extends
        BaseReferences<_$AppDatabase, $CustomerPaymentsTable, CustomerPayment> {
  $$CustomerPaymentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.customerPayments.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CustomersTable _customerIdTable(_$AppDatabase db) =>
      db.customers.createAlias(
        $_aliasNameGenerator(db.customerPayments.customerId, db.customers.id),
      );

  $$CustomersTableProcessedTableManager get customerId {
    final $_column = $_itemColumn<String>('customer_id')!;

    final manager = $$CustomersTableTableManager(
      $_db,
      $_db.customers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_customerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SalesTable _saleIdTable(_$AppDatabase db) => db.sales.createAlias(
    $_aliasNameGenerator(db.customerPayments.saleId, db.sales.id),
  );

  $$SalesTableProcessedTableManager? get saleId {
    final $_column = $_itemColumn<String>('sale_id');
    if ($_column == null) return null;
    final manager = $$SalesTableTableManager(
      $_db,
      $_db.sales,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_saleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CustomerPaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $CustomerPaymentsTable> {
  $$CustomerPaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get paidAt => $composableBuilder(
    column: $table.paidAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reversed => $composableBuilder(
    column: $table.reversed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reversedAt => $composableBuilder(
    column: $table.reversedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableFilterComposer get customerId {
    final $$CustomersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableFilterComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SalesTableFilterComposer get saleId {
    final $$SalesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleId,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableFilterComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CustomerPaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomerPaymentsTable> {
  $$CustomerPaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paidAt => $composableBuilder(
    column: $table.paidAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reversed => $composableBuilder(
    column: $table.reversed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reversedAt => $composableBuilder(
    column: $table.reversedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableOrderingComposer get customerId {
    final $$CustomersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableOrderingComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SalesTableOrderingComposer get saleId {
    final $$SalesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleId,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableOrderingComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CustomerPaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomerPaymentsTable> {
  $$CustomerPaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get paidAt =>
      $composableBuilder(column: $table.paidAt, builder: (column) => column);

  GeneratedColumn<bool> get reversed =>
      $composableBuilder(column: $table.reversed, builder: (column) => column);

  GeneratedColumn<DateTime> get reversedAt => $composableBuilder(
    column: $table.reversedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableAnnotationComposer get customerId {
    final $$CustomersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableAnnotationComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SalesTableAnnotationComposer get saleId {
    final $$SalesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleId,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableAnnotationComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CustomerPaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomerPaymentsTable,
          CustomerPayment,
          $$CustomerPaymentsTableFilterComposer,
          $$CustomerPaymentsTableOrderingComposer,
          $$CustomerPaymentsTableAnnotationComposer,
          $$CustomerPaymentsTableCreateCompanionBuilder,
          $$CustomerPaymentsTableUpdateCompanionBuilder,
          (CustomerPayment, $$CustomerPaymentsTableReferences),
          CustomerPayment,
          PrefetchHooks Function({bool shopId, bool customerId, bool saleId})
        > {
  $$CustomerPaymentsTableTableManager(
    _$AppDatabase db,
    $CustomerPaymentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomerPaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomerPaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomerPaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> customerId = const Value.absent(),
                Value<String?> saleId = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> paidAt = const Value.absent(),
                Value<bool> reversed = const Value.absent(),
                Value<DateTime?> reversedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomerPaymentsCompanion(
                id: id,
                shopId: shopId,
                customerId: customerId,
                saleId: saleId,
                amountPaise: amountPaise,
                paymentMethod: paymentMethod,
                note: note,
                paidAt: paidAt,
                reversed: reversed,
                reversedAt: reversedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String customerId,
                Value<String?> saleId = const Value.absent(),
                required int amountPaise,
                required String paymentMethod,
                Value<String?> note = const Value.absent(),
                required DateTime paidAt,
                Value<bool> reversed = const Value.absent(),
                Value<DateTime?> reversedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomerPaymentsCompanion.insert(
                id: id,
                shopId: shopId,
                customerId: customerId,
                saleId: saleId,
                amountPaise: amountPaise,
                paymentMethod: paymentMethod,
                note: note,
                paidAt: paidAt,
                reversed: reversed,
                reversedAt: reversedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CustomerPaymentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({shopId = false, customerId = false, saleId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable:
                                        $$CustomerPaymentsTableReferences
                                            ._shopIdTable(db),
                                    referencedColumn:
                                        $$CustomerPaymentsTableReferences
                                            ._shopIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (customerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.customerId,
                                    referencedTable:
                                        $$CustomerPaymentsTableReferences
                                            ._customerIdTable(db),
                                    referencedColumn:
                                        $$CustomerPaymentsTableReferences
                                            ._customerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (saleId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.saleId,
                                    referencedTable:
                                        $$CustomerPaymentsTableReferences
                                            ._saleIdTable(db),
                                    referencedColumn:
                                        $$CustomerPaymentsTableReferences
                                            ._saleIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$CustomerPaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomerPaymentsTable,
      CustomerPayment,
      $$CustomerPaymentsTableFilterComposer,
      $$CustomerPaymentsTableOrderingComposer,
      $$CustomerPaymentsTableAnnotationComposer,
      $$CustomerPaymentsTableCreateCompanionBuilder,
      $$CustomerPaymentsTableUpdateCompanionBuilder,
      (CustomerPayment, $$CustomerPaymentsTableReferences),
      CustomerPayment,
      PrefetchHooks Function({bool shopId, bool customerId, bool saleId})
    >;
typedef $$ExpensesTableCreateCompanionBuilder =
    ExpensesCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String name,
      required int amountPaise,
      required String category,
      required String paymentMethod,
      Value<String> paymentStatus,
      required DateTime expenseDate,
      Value<String?> note,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ExpensesTableUpdateCompanionBuilder =
    ExpensesCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> name,
      Value<int> amountPaise,
      Value<String> category,
      Value<String> paymentMethod,
      Value<String> paymentStatus,
      Value<DateTime> expenseDate,
      Value<String?> note,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ExpensesTableReferences
    extends BaseReferences<_$AppDatabase, $ExpensesTable, Expense> {
  $$ExpensesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.expenses.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExpensesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpensesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpensesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpensesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpensesTable,
          Expense,
          $$ExpensesTableFilterComposer,
          $$ExpensesTableOrderingComposer,
          $$ExpensesTableAnnotationComposer,
          $$ExpensesTableCreateCompanionBuilder,
          $$ExpensesTableUpdateCompanionBuilder,
          (Expense, $$ExpensesTableReferences),
          Expense,
          PrefetchHooks Function({bool shopId})
        > {
  $$ExpensesTableTableManager(_$AppDatabase db, $ExpensesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<String> paymentStatus = const Value.absent(),
                Value<DateTime> expenseDate = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensesCompanion(
                id: id,
                shopId: shopId,
                name: name,
                amountPaise: amountPaise,
                category: category,
                paymentMethod: paymentMethod,
                paymentStatus: paymentStatus,
                expenseDate: expenseDate,
                note: note,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String name,
                required int amountPaise,
                required String category,
                required String paymentMethod,
                Value<String> paymentStatus = const Value.absent(),
                required DateTime expenseDate,
                Value<String?> note = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensesCompanion.insert(
                id: id,
                shopId: shopId,
                name: name,
                amountPaise: amountPaise,
                category: category,
                paymentMethod: paymentMethod,
                paymentStatus: paymentStatus,
                expenseDate: expenseDate,
                note: note,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExpensesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shopId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shopId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.shopId,
                                referencedTable: $$ExpensesTableReferences
                                    ._shopIdTable(db),
                                referencedColumn: $$ExpensesTableReferences
                                    ._shopIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ExpensesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpensesTable,
      Expense,
      $$ExpensesTableFilterComposer,
      $$ExpensesTableOrderingComposer,
      $$ExpensesTableAnnotationComposer,
      $$ExpensesTableCreateCompanionBuilder,
      $$ExpensesTableUpdateCompanionBuilder,
      (Expense, $$ExpensesTableReferences),
      Expense,
      PrefetchHooks Function({bool shopId})
    >;
typedef $$SaleItemsTableCreateCompanionBuilder =
    SaleItemsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String saleId,
      required String productId,
      Value<String?> variantId,
      required String productName,
      Value<String?> variantName,
      Value<String?> sku,
      required int unitPricePaise,
      required int quantity,
      required int lineTotalPaise,
      Value<int> offerDiscountPaise,
      Value<String?> appliedOfferId,
      Value<String?> appliedOfferName,
      Value<String?> appliedOfferType,
      Value<int> rowid,
    });
typedef $$SaleItemsTableUpdateCompanionBuilder =
    SaleItemsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> saleId,
      Value<String> productId,
      Value<String?> variantId,
      Value<String> productName,
      Value<String?> variantName,
      Value<String?> sku,
      Value<int> unitPricePaise,
      Value<int> quantity,
      Value<int> lineTotalPaise,
      Value<int> offerDiscountPaise,
      Value<String?> appliedOfferId,
      Value<String?> appliedOfferName,
      Value<String?> appliedOfferType,
      Value<int> rowid,
    });

final class $$SaleItemsTableReferences
    extends BaseReferences<_$AppDatabase, $SaleItemsTable, SaleItem> {
  $$SaleItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.saleItems.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SalesTable _saleIdTable(_$AppDatabase db) => db.sales.createAlias(
    $_aliasNameGenerator(db.saleItems.saleId, db.sales.id),
  );

  $$SalesTableProcessedTableManager get saleId {
    final $_column = $_itemColumn<String>('sale_id')!;

    final manager = $$SalesTableTableManager(
      $_db,
      $_db.sales,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_saleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias(
        $_aliasNameGenerator(db.saleItems.productId, db.products.id),
      );

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager(
      $_db,
      $_db.products,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProductVariantsTable _variantIdTable(_$AppDatabase db) =>
      db.productVariants.createAlias(
        $_aliasNameGenerator(db.saleItems.variantId, db.productVariants.id),
      );

  $$ProductVariantsTableProcessedTableManager? get variantId {
    final $_column = $_itemColumn<String>('variant_id');
    if ($_column == null) return null;
    final manager = $$ProductVariantsTableTableManager(
      $_db,
      $_db.productVariants,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_variantIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SaleItemsTableFilterComposer
    extends Composer<_$AppDatabase, $SaleItemsTable> {
  $$SaleItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variantName => $composableBuilder(
    column: $table.variantName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitPricePaise => $composableBuilder(
    column: $table.unitPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get offerDiscountPaise => $composableBuilder(
    column: $table.offerDiscountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appliedOfferId => $composableBuilder(
    column: $table.appliedOfferId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appliedOfferName => $composableBuilder(
    column: $table.appliedOfferName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appliedOfferType => $composableBuilder(
    column: $table.appliedOfferType,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SalesTableFilterComposer get saleId {
    final $$SalesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleId,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableFilterComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableFilterComposer get variantId {
    final $$ProductVariantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableFilterComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaleItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $SaleItemsTable> {
  $$SaleItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variantName => $composableBuilder(
    column: $table.variantName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitPricePaise => $composableBuilder(
    column: $table.unitPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offerDiscountPaise => $composableBuilder(
    column: $table.offerDiscountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appliedOfferId => $composableBuilder(
    column: $table.appliedOfferId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appliedOfferName => $composableBuilder(
    column: $table.appliedOfferName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appliedOfferType => $composableBuilder(
    column: $table.appliedOfferType,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SalesTableOrderingComposer get saleId {
    final $$SalesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleId,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableOrderingComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableOrderingComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableOrderingComposer get variantId {
    final $$ProductVariantsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableOrderingComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaleItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SaleItemsTable> {
  $$SaleItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get variantName => $composableBuilder(
    column: $table.variantName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<int> get unitPricePaise => $composableBuilder(
    column: $table.unitPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get offerDiscountPaise => $composableBuilder(
    column: $table.offerDiscountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appliedOfferId => $composableBuilder(
    column: $table.appliedOfferId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appliedOfferName => $composableBuilder(
    column: $table.appliedOfferName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appliedOfferType => $composableBuilder(
    column: $table.appliedOfferType,
    builder: (column) => column,
  );

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SalesTableAnnotationComposer get saleId {
    final $$SalesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleId,
      referencedTable: $db.sales,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SalesTableAnnotationComposer(
            $db: $db,
            $table: $db.sales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableAnnotationComposer get variantId {
    final $$ProductVariantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableAnnotationComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaleItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SaleItemsTable,
          SaleItem,
          $$SaleItemsTableFilterComposer,
          $$SaleItemsTableOrderingComposer,
          $$SaleItemsTableAnnotationComposer,
          $$SaleItemsTableCreateCompanionBuilder,
          $$SaleItemsTableUpdateCompanionBuilder,
          (SaleItem, $$SaleItemsTableReferences),
          SaleItem,
          PrefetchHooks Function({
            bool shopId,
            bool saleId,
            bool productId,
            bool variantId,
          })
        > {
  $$SaleItemsTableTableManager(_$AppDatabase db, $SaleItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SaleItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SaleItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SaleItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> saleId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String?> variantId = const Value.absent(),
                Value<String> productName = const Value.absent(),
                Value<String?> variantName = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<int> unitPricePaise = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<int> lineTotalPaise = const Value.absent(),
                Value<int> offerDiscountPaise = const Value.absent(),
                Value<String?> appliedOfferId = const Value.absent(),
                Value<String?> appliedOfferName = const Value.absent(),
                Value<String?> appliedOfferType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SaleItemsCompanion(
                id: id,
                shopId: shopId,
                saleId: saleId,
                productId: productId,
                variantId: variantId,
                productName: productName,
                variantName: variantName,
                sku: sku,
                unitPricePaise: unitPricePaise,
                quantity: quantity,
                lineTotalPaise: lineTotalPaise,
                offerDiscountPaise: offerDiscountPaise,
                appliedOfferId: appliedOfferId,
                appliedOfferName: appliedOfferName,
                appliedOfferType: appliedOfferType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String saleId,
                required String productId,
                Value<String?> variantId = const Value.absent(),
                required String productName,
                Value<String?> variantName = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                required int unitPricePaise,
                required int quantity,
                required int lineTotalPaise,
                Value<int> offerDiscountPaise = const Value.absent(),
                Value<String?> appliedOfferId = const Value.absent(),
                Value<String?> appliedOfferName = const Value.absent(),
                Value<String?> appliedOfferType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SaleItemsCompanion.insert(
                id: id,
                shopId: shopId,
                saleId: saleId,
                productId: productId,
                variantId: variantId,
                productName: productName,
                variantName: variantName,
                sku: sku,
                unitPricePaise: unitPricePaise,
                quantity: quantity,
                lineTotalPaise: lineTotalPaise,
                offerDiscountPaise: offerDiscountPaise,
                appliedOfferId: appliedOfferId,
                appliedOfferName: appliedOfferName,
                appliedOfferType: appliedOfferType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SaleItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                shopId = false,
                saleId = false,
                productId = false,
                variantId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable: $$SaleItemsTableReferences
                                        ._shopIdTable(db),
                                    referencedColumn: $$SaleItemsTableReferences
                                        ._shopIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (saleId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.saleId,
                                    referencedTable: $$SaleItemsTableReferences
                                        ._saleIdTable(db),
                                    referencedColumn: $$SaleItemsTableReferences
                                        ._saleIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (productId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.productId,
                                    referencedTable: $$SaleItemsTableReferences
                                        ._productIdTable(db),
                                    referencedColumn: $$SaleItemsTableReferences
                                        ._productIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (variantId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.variantId,
                                    referencedTable: $$SaleItemsTableReferences
                                        ._variantIdTable(db),
                                    referencedColumn: $$SaleItemsTableReferences
                                        ._variantIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$SaleItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SaleItemsTable,
      SaleItem,
      $$SaleItemsTableFilterComposer,
      $$SaleItemsTableOrderingComposer,
      $$SaleItemsTableAnnotationComposer,
      $$SaleItemsTableCreateCompanionBuilder,
      $$SaleItemsTableUpdateCompanionBuilder,
      (SaleItem, $$SaleItemsTableReferences),
      SaleItem,
      PrefetchHooks Function({
        bool shopId,
        bool saleId,
        bool productId,
        bool variantId,
      })
    >;
typedef $$SaleSequencesTableCreateCompanionBuilder =
    SaleSequencesCompanion Function({
      required String id,
      required String shopId,
      Value<int> nextValue,
      Value<int> rowid,
    });
typedef $$SaleSequencesTableUpdateCompanionBuilder =
    SaleSequencesCompanion Function({
      Value<String> id,
      Value<String> shopId,
      Value<int> nextValue,
      Value<int> rowid,
    });

final class $$SaleSequencesTableReferences
    extends BaseReferences<_$AppDatabase, $SaleSequencesTable, SaleSequence> {
  $$SaleSequencesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.saleSequences.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager get shopId {
    final $_column = $_itemColumn<String>('shop_id')!;

    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SaleSequencesTableFilterComposer
    extends Composer<_$AppDatabase, $SaleSequencesTable> {
  $$SaleSequencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextValue => $composableBuilder(
    column: $table.nextValue,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaleSequencesTableOrderingComposer
    extends Composer<_$AppDatabase, $SaleSequencesTable> {
  $$SaleSequencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextValue => $composableBuilder(
    column: $table.nextValue,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaleSequencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SaleSequencesTable> {
  $$SaleSequencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get nextValue =>
      $composableBuilder(column: $table.nextValue, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaleSequencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SaleSequencesTable,
          SaleSequence,
          $$SaleSequencesTableFilterComposer,
          $$SaleSequencesTableOrderingComposer,
          $$SaleSequencesTableAnnotationComposer,
          $$SaleSequencesTableCreateCompanionBuilder,
          $$SaleSequencesTableUpdateCompanionBuilder,
          (SaleSequence, $$SaleSequencesTableReferences),
          SaleSequence,
          PrefetchHooks Function({bool shopId})
        > {
  $$SaleSequencesTableTableManager(_$AppDatabase db, $SaleSequencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SaleSequencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SaleSequencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SaleSequencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> shopId = const Value.absent(),
                Value<int> nextValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SaleSequencesCompanion(
                id: id,
                shopId: shopId,
                nextValue: nextValue,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String shopId,
                Value<int> nextValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SaleSequencesCompanion.insert(
                id: id,
                shopId: shopId,
                nextValue: nextValue,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SaleSequencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shopId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shopId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.shopId,
                                referencedTable: $$SaleSequencesTableReferences
                                    ._shopIdTable(db),
                                referencedColumn: $$SaleSequencesTableReferences
                                    ._shopIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SaleSequencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SaleSequencesTable,
      SaleSequence,
      $$SaleSequencesTableFilterComposer,
      $$SaleSequencesTableOrderingComposer,
      $$SaleSequencesTableAnnotationComposer,
      $$SaleSequencesTableCreateCompanionBuilder,
      $$SaleSequencesTableUpdateCompanionBuilder,
      (SaleSequence, $$SaleSequencesTableReferences),
      SaleSequence,
      PrefetchHooks Function({bool shopId})
    >;
typedef $$StockMovementsTableCreateCompanionBuilder =
    StockMovementsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String productId,
      Value<String?> variantId,
      required String movementType,
      required int quantity,
      required int stockBefore,
      required int stockAfter,
      Value<String?> reason,
      Value<String?> note,
      Value<String?> referenceType,
      Value<String?> referenceId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$StockMovementsTableUpdateCompanionBuilder =
    StockMovementsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> productId,
      Value<String?> variantId,
      Value<String> movementType,
      Value<int> quantity,
      Value<int> stockBefore,
      Value<int> stockAfter,
      Value<String?> reason,
      Value<String?> note,
      Value<String?> referenceType,
      Value<String?> referenceId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$StockMovementsTableReferences
    extends BaseReferences<_$AppDatabase, $StockMovementsTable, StockMovement> {
  $$StockMovementsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.stockMovements.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias(
        $_aliasNameGenerator(db.stockMovements.productId, db.products.id),
      );

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager(
      $_db,
      $_db.products,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProductVariantsTable _variantIdTable(_$AppDatabase db) =>
      db.productVariants.createAlias(
        $_aliasNameGenerator(
          db.stockMovements.variantId,
          db.productVariants.id,
        ),
      );

  $$ProductVariantsTableProcessedTableManager? get variantId {
    final $_column = $_itemColumn<String>('variant_id');
    if ($_column == null) return null;
    final manager = $$ProductVariantsTableTableManager(
      $_db,
      $_db.productVariants,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_variantIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StockMovementsTableFilterComposer
    extends Composer<_$AppDatabase, $StockMovementsTable> {
  $$StockMovementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get movementType => $composableBuilder(
    column: $table.movementType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stockBefore => $composableBuilder(
    column: $table.stockBefore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stockAfter => $composableBuilder(
    column: $table.stockAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceType => $composableBuilder(
    column: $table.referenceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceId => $composableBuilder(
    column: $table.referenceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableFilterComposer get variantId {
    final $$ProductVariantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableFilterComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockMovementsTableOrderingComposer
    extends Composer<_$AppDatabase, $StockMovementsTable> {
  $$StockMovementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get movementType => $composableBuilder(
    column: $table.movementType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stockBefore => $composableBuilder(
    column: $table.stockBefore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stockAfter => $composableBuilder(
    column: $table.stockAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceType => $composableBuilder(
    column: $table.referenceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceId => $composableBuilder(
    column: $table.referenceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableOrderingComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableOrderingComposer get variantId {
    final $$ProductVariantsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableOrderingComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockMovementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StockMovementsTable> {
  $$StockMovementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get movementType => $composableBuilder(
    column: $table.movementType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get stockBefore => $composableBuilder(
    column: $table.stockBefore,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stockAfter => $composableBuilder(
    column: $table.stockAfter,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get referenceType => $composableBuilder(
    column: $table.referenceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get referenceId => $composableBuilder(
    column: $table.referenceId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableAnnotationComposer get variantId {
    final $$ProductVariantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableAnnotationComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockMovementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StockMovementsTable,
          StockMovement,
          $$StockMovementsTableFilterComposer,
          $$StockMovementsTableOrderingComposer,
          $$StockMovementsTableAnnotationComposer,
          $$StockMovementsTableCreateCompanionBuilder,
          $$StockMovementsTableUpdateCompanionBuilder,
          (StockMovement, $$StockMovementsTableReferences),
          StockMovement,
          PrefetchHooks Function({bool shopId, bool productId, bool variantId})
        > {
  $$StockMovementsTableTableManager(
    _$AppDatabase db,
    $StockMovementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StockMovementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StockMovementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StockMovementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String?> variantId = const Value.absent(),
                Value<String> movementType = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<int> stockBefore = const Value.absent(),
                Value<int> stockAfter = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> referenceType = const Value.absent(),
                Value<String?> referenceId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StockMovementsCompanion(
                id: id,
                shopId: shopId,
                productId: productId,
                variantId: variantId,
                movementType: movementType,
                quantity: quantity,
                stockBefore: stockBefore,
                stockAfter: stockAfter,
                reason: reason,
                note: note,
                referenceType: referenceType,
                referenceId: referenceId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String productId,
                Value<String?> variantId = const Value.absent(),
                required String movementType,
                required int quantity,
                required int stockBefore,
                required int stockAfter,
                Value<String?> reason = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> referenceType = const Value.absent(),
                Value<String?> referenceId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StockMovementsCompanion.insert(
                id: id,
                shopId: shopId,
                productId: productId,
                variantId: variantId,
                movementType: movementType,
                quantity: quantity,
                stockBefore: stockBefore,
                stockAfter: stockAfter,
                reason: reason,
                note: note,
                referenceType: referenceType,
                referenceId: referenceId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StockMovementsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({shopId = false, productId = false, variantId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable:
                                        $$StockMovementsTableReferences
                                            ._shopIdTable(db),
                                    referencedColumn:
                                        $$StockMovementsTableReferences
                                            ._shopIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (productId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.productId,
                                    referencedTable:
                                        $$StockMovementsTableReferences
                                            ._productIdTable(db),
                                    referencedColumn:
                                        $$StockMovementsTableReferences
                                            ._productIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (variantId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.variantId,
                                    referencedTable:
                                        $$StockMovementsTableReferences
                                            ._variantIdTable(db),
                                    referencedColumn:
                                        $$StockMovementsTableReferences
                                            ._variantIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$StockMovementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StockMovementsTable,
      StockMovement,
      $$StockMovementsTableFilterComposer,
      $$StockMovementsTableOrderingComposer,
      $$StockMovementsTableAnnotationComposer,
      $$StockMovementsTableCreateCompanionBuilder,
      $$StockMovementsTableUpdateCompanionBuilder,
      (StockMovement, $$StockMovementsTableReferences),
      StockMovement,
      PrefetchHooks Function({bool shopId, bool productId, bool variantId})
    >;
typedef $$SuppliersTableCreateCompanionBuilder =
    SuppliersCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String name,
      Value<String?> phone,
      Value<String?> email,
      Value<String?> address,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SuppliersTableUpdateCompanionBuilder =
    SuppliersCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> name,
      Value<String?> phone,
      Value<String?> email,
      Value<String?> address,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$SuppliersTableReferences
    extends BaseReferences<_$AppDatabase, $SuppliersTable, Supplier> {
  $$SuppliersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.suppliers.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PurchasesTable, List<Purchase>>
  _purchasesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.purchases,
    aliasName: $_aliasNameGenerator(db.suppliers.id, db.purchases.supplierId),
  );

  $$PurchasesTableProcessedTableManager get purchasesRefs {
    final manager = $$PurchasesTableTableManager(
      $_db,
      $_db.purchases,
    ).filter((f) => f.supplierId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_purchasesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SuppliersTableFilterComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> purchasesRefs(
    Expression<bool> Function($$PurchasesTableFilterComposer f) f,
  ) {
    final $$PurchasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchases,
      getReferencedColumn: (t) => t.supplierId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchasesTableFilterComposer(
            $db: $db,
            $table: $db.purchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SuppliersTableOrderingComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SuppliersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> purchasesRefs<T extends Object>(
    Expression<T> Function($$PurchasesTableAnnotationComposer a) f,
  ) {
    final $$PurchasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchases,
      getReferencedColumn: (t) => t.supplierId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchasesTableAnnotationComposer(
            $db: $db,
            $table: $db.purchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SuppliersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SuppliersTable,
          Supplier,
          $$SuppliersTableFilterComposer,
          $$SuppliersTableOrderingComposer,
          $$SuppliersTableAnnotationComposer,
          $$SuppliersTableCreateCompanionBuilder,
          $$SuppliersTableUpdateCompanionBuilder,
          (Supplier, $$SuppliersTableReferences),
          Supplier,
          PrefetchHooks Function({bool shopId, bool purchasesRefs})
        > {
  $$SuppliersTableTableManager(_$AppDatabase db, $SuppliersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SuppliersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SuppliersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SuppliersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SuppliersCompanion(
                id: id,
                shopId: shopId,
                name: name,
                phone: phone,
                email: email,
                address: address,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SuppliersCompanion.insert(
                id: id,
                shopId: shopId,
                name: name,
                phone: phone,
                email: email,
                address: address,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SuppliersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shopId = false, purchasesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (purchasesRefs) db.purchases],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shopId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.shopId,
                                referencedTable: $$SuppliersTableReferences
                                    ._shopIdTable(db),
                                referencedColumn: $$SuppliersTableReferences
                                    ._shopIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (purchasesRefs)
                    await $_getPrefetchedData<
                      Supplier,
                      $SuppliersTable,
                      Purchase
                    >(
                      currentTable: table,
                      referencedTable: $$SuppliersTableReferences
                          ._purchasesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SuppliersTableReferences(
                            db,
                            table,
                            p0,
                          ).purchasesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.supplierId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SuppliersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SuppliersTable,
      Supplier,
      $$SuppliersTableFilterComposer,
      $$SuppliersTableOrderingComposer,
      $$SuppliersTableAnnotationComposer,
      $$SuppliersTableCreateCompanionBuilder,
      $$SuppliersTableUpdateCompanionBuilder,
      (Supplier, $$SuppliersTableReferences),
      Supplier,
      PrefetchHooks Function({bool shopId, bool purchasesRefs})
    >;
typedef $$PurchasesTableCreateCompanionBuilder =
    PurchasesCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String?> supplierId,
      required String purchaseNumber,
      required int subtotalPaise,
      required int totalPaise,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$PurchasesTableUpdateCompanionBuilder =
    PurchasesCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String?> supplierId,
      Value<String> purchaseNumber,
      Value<int> subtotalPaise,
      Value<int> totalPaise,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$PurchasesTableReferences
    extends BaseReferences<_$AppDatabase, $PurchasesTable, Purchase> {
  $$PurchasesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.purchases.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SuppliersTable _supplierIdTable(_$AppDatabase db) =>
      db.suppliers.createAlias(
        $_aliasNameGenerator(db.purchases.supplierId, db.suppliers.id),
      );

  $$SuppliersTableProcessedTableManager? get supplierId {
    final $_column = $_itemColumn<String>('supplier_id');
    if ($_column == null) return null;
    final manager = $$SuppliersTableTableManager(
      $_db,
      $_db.suppliers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_supplierIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PurchaseItemsTable, List<PurchaseItem>>
  _purchaseItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.purchaseItems,
    aliasName: $_aliasNameGenerator(
      db.purchases.id,
      db.purchaseItems.purchaseId,
    ),
  );

  $$PurchaseItemsTableProcessedTableManager get purchaseItemsRefs {
    final manager = $$PurchaseItemsTableTableManager(
      $_db,
      $_db.purchaseItems,
    ).filter((f) => f.purchaseId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_purchaseItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PurchasesTableFilterComposer
    extends Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purchaseNumber => $composableBuilder(
    column: $table.purchaseNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableFilterComposer get supplierId {
    final $$SuppliersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableFilterComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> purchaseItemsRefs(
    Expression<bool> Function($$PurchaseItemsTableFilterComposer f) f,
  ) {
    final $$PurchaseItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseItems,
      getReferencedColumn: (t) => t.purchaseId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseItemsTableFilterComposer(
            $db: $db,
            $table: $db.purchaseItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PurchasesTableOrderingComposer
    extends Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purchaseNumber => $composableBuilder(
    column: $table.purchaseNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableOrderingComposer get supplierId {
    final $$SuppliersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableOrderingComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurchasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get purchaseNumber => $composableBuilder(
    column: $table.purchaseNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableAnnotationComposer get supplierId {
    final $$SuppliersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableAnnotationComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> purchaseItemsRefs<T extends Object>(
    Expression<T> Function($$PurchaseItemsTableAnnotationComposer a) f,
  ) {
    final $$PurchaseItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purchaseItems,
      getReferencedColumn: (t) => t.purchaseId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchaseItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.purchaseItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PurchasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PurchasesTable,
          Purchase,
          $$PurchasesTableFilterComposer,
          $$PurchasesTableOrderingComposer,
          $$PurchasesTableAnnotationComposer,
          $$PurchasesTableCreateCompanionBuilder,
          $$PurchasesTableUpdateCompanionBuilder,
          (Purchase, $$PurchasesTableReferences),
          Purchase,
          PrefetchHooks Function({
            bool shopId,
            bool supplierId,
            bool purchaseItemsRefs,
          })
        > {
  $$PurchasesTableTableManager(_$AppDatabase db, $PurchasesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PurchasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PurchasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PurchasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String?> supplierId = const Value.absent(),
                Value<String> purchaseNumber = const Value.absent(),
                Value<int> subtotalPaise = const Value.absent(),
                Value<int> totalPaise = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PurchasesCompanion(
                id: id,
                shopId: shopId,
                supplierId: supplierId,
                purchaseNumber: purchaseNumber,
                subtotalPaise: subtotalPaise,
                totalPaise: totalPaise,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String?> supplierId = const Value.absent(),
                required String purchaseNumber,
                required int subtotalPaise,
                required int totalPaise,
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PurchasesCompanion.insert(
                id: id,
                shopId: shopId,
                supplierId: supplierId,
                purchaseNumber: purchaseNumber,
                subtotalPaise: subtotalPaise,
                totalPaise: totalPaise,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PurchasesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                shopId = false,
                supplierId = false,
                purchaseItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (purchaseItemsRefs) db.purchaseItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable: $$PurchasesTableReferences
                                        ._shopIdTable(db),
                                    referencedColumn: $$PurchasesTableReferences
                                        ._shopIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (supplierId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.supplierId,
                                    referencedTable: $$PurchasesTableReferences
                                        ._supplierIdTable(db),
                                    referencedColumn: $$PurchasesTableReferences
                                        ._supplierIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (purchaseItemsRefs)
                        await $_getPrefetchedData<
                          Purchase,
                          $PurchasesTable,
                          PurchaseItem
                        >(
                          currentTable: table,
                          referencedTable: $$PurchasesTableReferences
                              ._purchaseItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PurchasesTableReferences(
                                db,
                                table,
                                p0,
                              ).purchaseItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.purchaseId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PurchasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PurchasesTable,
      Purchase,
      $$PurchasesTableFilterComposer,
      $$PurchasesTableOrderingComposer,
      $$PurchasesTableAnnotationComposer,
      $$PurchasesTableCreateCompanionBuilder,
      $$PurchasesTableUpdateCompanionBuilder,
      (Purchase, $$PurchasesTableReferences),
      Purchase,
      PrefetchHooks Function({
        bool shopId,
        bool supplierId,
        bool purchaseItemsRefs,
      })
    >;
typedef $$PurchaseItemsTableCreateCompanionBuilder =
    PurchaseItemsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String purchaseId,
      required String productId,
      Value<String?> variantId,
      required String productName,
      Value<String?> variantName,
      Value<String?> sku,
      required int unitCostPaise,
      required int quantity,
      required int lineTotalPaise,
      Value<int> rowid,
    });
typedef $$PurchaseItemsTableUpdateCompanionBuilder =
    PurchaseItemsCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> purchaseId,
      Value<String> productId,
      Value<String?> variantId,
      Value<String> productName,
      Value<String?> variantName,
      Value<String?> sku,
      Value<int> unitCostPaise,
      Value<int> quantity,
      Value<int> lineTotalPaise,
      Value<int> rowid,
    });

final class $$PurchaseItemsTableReferences
    extends BaseReferences<_$AppDatabase, $PurchaseItemsTable, PurchaseItem> {
  $$PurchaseItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.purchaseItems.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PurchasesTable _purchaseIdTable(_$AppDatabase db) =>
      db.purchases.createAlias(
        $_aliasNameGenerator(db.purchaseItems.purchaseId, db.purchases.id),
      );

  $$PurchasesTableProcessedTableManager get purchaseId {
    final $_column = $_itemColumn<String>('purchase_id')!;

    final manager = $$PurchasesTableTableManager(
      $_db,
      $_db.purchases,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_purchaseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias(
        $_aliasNameGenerator(db.purchaseItems.productId, db.products.id),
      );

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager(
      $_db,
      $_db.products,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProductVariantsTable _variantIdTable(_$AppDatabase db) =>
      db.productVariants.createAlias(
        $_aliasNameGenerator(db.purchaseItems.variantId, db.productVariants.id),
      );

  $$ProductVariantsTableProcessedTableManager? get variantId {
    final $_column = $_itemColumn<String>('variant_id');
    if ($_column == null) return null;
    final manager = $$ProductVariantsTableTableManager(
      $_db,
      $_db.productVariants,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_variantIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PurchaseItemsTableFilterComposer
    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
  $$PurchaseItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variantName => $composableBuilder(
    column: $table.variantName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitCostPaise => $composableBuilder(
    column: $table.unitCostPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PurchasesTableFilterComposer get purchaseId {
    final $$PurchasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.purchaseId,
      referencedTable: $db.purchases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchasesTableFilterComposer(
            $db: $db,
            $table: $db.purchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableFilterComposer get variantId {
    final $$ProductVariantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableFilterComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurchaseItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
  $$PurchaseItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variantName => $composableBuilder(
    column: $table.variantName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitCostPaise => $composableBuilder(
    column: $table.unitCostPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PurchasesTableOrderingComposer get purchaseId {
    final $$PurchasesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.purchaseId,
      referencedTable: $db.purchases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchasesTableOrderingComposer(
            $db: $db,
            $table: $db.purchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableOrderingComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableOrderingComposer get variantId {
    final $$ProductVariantsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableOrderingComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurchaseItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
  $$PurchaseItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get variantName => $composableBuilder(
    column: $table.variantName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<int> get unitCostPaise => $composableBuilder(
    column: $table.unitCostPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => column,
  );

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PurchasesTableAnnotationComposer get purchaseId {
    final $$PurchasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.purchaseId,
      referencedTable: $db.purchases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurchasesTableAnnotationComposer(
            $db: $db,
            $table: $db.purchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProductVariantsTableAnnotationComposer get variantId {
    final $$ProductVariantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.variantId,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableAnnotationComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurchaseItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PurchaseItemsTable,
          PurchaseItem,
          $$PurchaseItemsTableFilterComposer,
          $$PurchaseItemsTableOrderingComposer,
          $$PurchaseItemsTableAnnotationComposer,
          $$PurchaseItemsTableCreateCompanionBuilder,
          $$PurchaseItemsTableUpdateCompanionBuilder,
          (PurchaseItem, $$PurchaseItemsTableReferences),
          PurchaseItem,
          PrefetchHooks Function({
            bool shopId,
            bool purchaseId,
            bool productId,
            bool variantId,
          })
        > {
  $$PurchaseItemsTableTableManager(_$AppDatabase db, $PurchaseItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PurchaseItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PurchaseItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PurchaseItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> purchaseId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String?> variantId = const Value.absent(),
                Value<String> productName = const Value.absent(),
                Value<String?> variantName = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<int> unitCostPaise = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<int> lineTotalPaise = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PurchaseItemsCompanion(
                id: id,
                shopId: shopId,
                purchaseId: purchaseId,
                productId: productId,
                variantId: variantId,
                productName: productName,
                variantName: variantName,
                sku: sku,
                unitCostPaise: unitCostPaise,
                quantity: quantity,
                lineTotalPaise: lineTotalPaise,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String purchaseId,
                required String productId,
                Value<String?> variantId = const Value.absent(),
                required String productName,
                Value<String?> variantName = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                required int unitCostPaise,
                required int quantity,
                required int lineTotalPaise,
                Value<int> rowid = const Value.absent(),
              }) => PurchaseItemsCompanion.insert(
                id: id,
                shopId: shopId,
                purchaseId: purchaseId,
                productId: productId,
                variantId: variantId,
                productName: productName,
                variantName: variantName,
                sku: sku,
                unitCostPaise: unitCostPaise,
                quantity: quantity,
                lineTotalPaise: lineTotalPaise,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PurchaseItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                shopId = false,
                purchaseId = false,
                productId = false,
                variantId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (shopId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.shopId,
                                    referencedTable:
                                        $$PurchaseItemsTableReferences
                                            ._shopIdTable(db),
                                    referencedColumn:
                                        $$PurchaseItemsTableReferences
                                            ._shopIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (purchaseId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.purchaseId,
                                    referencedTable:
                                        $$PurchaseItemsTableReferences
                                            ._purchaseIdTable(db),
                                    referencedColumn:
                                        $$PurchaseItemsTableReferences
                                            ._purchaseIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (productId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.productId,
                                    referencedTable:
                                        $$PurchaseItemsTableReferences
                                            ._productIdTable(db),
                                    referencedColumn:
                                        $$PurchaseItemsTableReferences
                                            ._productIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (variantId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.variantId,
                                    referencedTable:
                                        $$PurchaseItemsTableReferences
                                            ._variantIdTable(db),
                                    referencedColumn:
                                        $$PurchaseItemsTableReferences
                                            ._variantIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$PurchaseItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PurchaseItemsTable,
      PurchaseItem,
      $$PurchaseItemsTableFilterComposer,
      $$PurchaseItemsTableOrderingComposer,
      $$PurchaseItemsTableAnnotationComposer,
      $$PurchaseItemsTableCreateCompanionBuilder,
      $$PurchaseItemsTableUpdateCompanionBuilder,
      (PurchaseItem, $$PurchaseItemsTableReferences),
      PurchaseItem,
      PrefetchHooks Function({
        bool shopId,
        bool purchaseId,
        bool productId,
        bool variantId,
      })
    >;
typedef $$PurchaseSequencesTableCreateCompanionBuilder =
    PurchaseSequencesCompanion Function({
      required String id,
      required String shopId,
      Value<int> nextValue,
      Value<int> rowid,
    });
typedef $$PurchaseSequencesTableUpdateCompanionBuilder =
    PurchaseSequencesCompanion Function({
      Value<String> id,
      Value<String> shopId,
      Value<int> nextValue,
      Value<int> rowid,
    });

final class $$PurchaseSequencesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $PurchaseSequencesTable,
          PurchaseSequence
        > {
  $$PurchaseSequencesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ShopsTable _shopIdTable(_$AppDatabase db) => db.shops.createAlias(
    $_aliasNameGenerator(db.purchaseSequences.shopId, db.shops.id),
  );

  $$ShopsTableProcessedTableManager get shopId {
    final $_column = $_itemColumn<String>('shop_id')!;

    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PurchaseSequencesTableFilterComposer
    extends Composer<_$AppDatabase, $PurchaseSequencesTable> {
  $$PurchaseSequencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextValue => $composableBuilder(
    column: $table.nextValue,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurchaseSequencesTableOrderingComposer
    extends Composer<_$AppDatabase, $PurchaseSequencesTable> {
  $$PurchaseSequencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextValue => $composableBuilder(
    column: $table.nextValue,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurchaseSequencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PurchaseSequencesTable> {
  $$PurchaseSequencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get nextValue =>
      $composableBuilder(column: $table.nextValue, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurchaseSequencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PurchaseSequencesTable,
          PurchaseSequence,
          $$PurchaseSequencesTableFilterComposer,
          $$PurchaseSequencesTableOrderingComposer,
          $$PurchaseSequencesTableAnnotationComposer,
          $$PurchaseSequencesTableCreateCompanionBuilder,
          $$PurchaseSequencesTableUpdateCompanionBuilder,
          (PurchaseSequence, $$PurchaseSequencesTableReferences),
          PurchaseSequence,
          PrefetchHooks Function({bool shopId})
        > {
  $$PurchaseSequencesTableTableManager(
    _$AppDatabase db,
    $PurchaseSequencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PurchaseSequencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PurchaseSequencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PurchaseSequencesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> shopId = const Value.absent(),
                Value<int> nextValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PurchaseSequencesCompanion(
                id: id,
                shopId: shopId,
                nextValue: nextValue,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String shopId,
                Value<int> nextValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PurchaseSequencesCompanion.insert(
                id: id,
                shopId: shopId,
                nextValue: nextValue,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PurchaseSequencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shopId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shopId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.shopId,
                                referencedTable:
                                    $$PurchaseSequencesTableReferences
                                        ._shopIdTable(db),
                                referencedColumn:
                                    $$PurchaseSequencesTableReferences
                                        ._shopIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PurchaseSequencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PurchaseSequencesTable,
      PurchaseSequence,
      $$PurchaseSequencesTableFilterComposer,
      $$PurchaseSequencesTableOrderingComposer,
      $$PurchaseSequencesTableAnnotationComposer,
      $$PurchaseSequencesTableCreateCompanionBuilder,
      $$PurchaseSequencesTableUpdateCompanionBuilder,
      (PurchaseSequence, $$PurchaseSequencesTableReferences),
      PurchaseSequence,
      PrefetchHooks Function({bool shopId})
    >;
typedef $$OffersTableCreateCompanionBuilder =
    OffersCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      required String name,
      required String type,
      required String configJson,
      Value<bool> isActive,
      Value<DateTime?> startAt,
      Value<DateTime?> endAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$OffersTableUpdateCompanionBuilder =
    OffersCompanion Function({
      Value<String> id,
      Value<String?> shopId,
      Value<String> name,
      Value<String> type,
      Value<String> configJson,
      Value<bool> isActive,
      Value<DateTime?> startAt,
      Value<DateTime?> endAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$OffersTableReferences
    extends BaseReferences<_$AppDatabase, $OffersTable, Offer> {
  $$OffersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShopsTable _shopIdTable(_$AppDatabase db) =>
      db.shops.createAlias($_aliasNameGenerator(db.offers.shopId, db.shops.id));

  $$ShopsTableProcessedTableManager? get shopId {
    final $_column = $_itemColumn<String>('shop_id');
    if ($_column == null) return null;
    final manager = $$ShopsTableTableManager(
      $_db,
      $_db.shops,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shopIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OffersTableFilterComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ShopsTableFilterComposer get shopId {
    final $$ShopsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableFilterComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OffersTableOrderingComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShopsTableOrderingComposer get shopId {
    final $$ShopsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableOrderingComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OffersTableAnnotationComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ShopsTableAnnotationComposer get shopId {
    final $$ShopsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shopId,
      referencedTable: $db.shops,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShopsTableAnnotationComposer(
            $db: $db,
            $table: $db.shops,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OffersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OffersTable,
          Offer,
          $$OffersTableFilterComposer,
          $$OffersTableOrderingComposer,
          $$OffersTableAnnotationComposer,
          $$OffersTableCreateCompanionBuilder,
          $$OffersTableUpdateCompanionBuilder,
          (Offer, $$OffersTableReferences),
          Offer,
          PrefetchHooks Function({bool shopId})
        > {
  $$OffersTableTableManager(_$AppDatabase db, $OffersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OffersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OffersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OffersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime?> startAt = const Value.absent(),
                Value<DateTime?> endAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OffersCompanion(
                id: id,
                shopId: shopId,
                name: name,
                type: type,
                configJson: configJson,
                isActive: isActive,
                startAt: startAt,
                endAt: endAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> shopId = const Value.absent(),
                required String name,
                required String type,
                required String configJson,
                Value<bool> isActive = const Value.absent(),
                Value<DateTime?> startAt = const Value.absent(),
                Value<DateTime?> endAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OffersCompanion.insert(
                id: id,
                shopId: shopId,
                name: name,
                type: type,
                configJson: configJson,
                isActive: isActive,
                startAt: startAt,
                endAt: endAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$OffersTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({shopId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shopId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.shopId,
                                referencedTable: $$OffersTableReferences
                                    ._shopIdTable(db),
                                referencedColumn: $$OffersTableReferences
                                    ._shopIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OffersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OffersTable,
      Offer,
      $$OffersTableFilterComposer,
      $$OffersTableOrderingComposer,
      $$OffersTableAnnotationComposer,
      $$OffersTableCreateCompanionBuilder,
      $$OffersTableUpdateCompanionBuilder,
      (Offer, $$OffersTableReferences),
      Offer,
      PrefetchHooks Function({bool shopId})
    >;
typedef $$ProductImageSyncTableCreateCompanionBuilder =
    ProductImageSyncCompanion Function({
      Value<String> id,
      required String shopId,
      required String productId,
      required String operation,
      Value<String?> cloudPath,
      Value<String?> localPath,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ProductImageSyncTableUpdateCompanionBuilder =
    ProductImageSyncCompanion Function({
      Value<String> id,
      Value<String> shopId,
      Value<String> productId,
      Value<String> operation,
      Value<String?> cloudPath,
      Value<String?> localPath,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ProductImageSyncTableFilterComposer
    extends Composer<_$AppDatabase, $ProductImageSyncTable> {
  $$ProductImageSyncTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudPath => $composableBuilder(
    column: $table.cloudPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductImageSyncTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductImageSyncTable> {
  $$ProductImageSyncTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudPath => $composableBuilder(
    column: $table.cloudPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductImageSyncTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductImageSyncTable> {
  $$ProductImageSyncTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get shopId =>
      $composableBuilder(column: $table.shopId, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get cloudPath =>
      $composableBuilder(column: $table.cloudPath, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ProductImageSyncTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductImageSyncTable,
          ProductImageSyncData,
          $$ProductImageSyncTableFilterComposer,
          $$ProductImageSyncTableOrderingComposer,
          $$ProductImageSyncTableAnnotationComposer,
          $$ProductImageSyncTableCreateCompanionBuilder,
          $$ProductImageSyncTableUpdateCompanionBuilder,
          (
            ProductImageSyncData,
            BaseReferences<
              _$AppDatabase,
              $ProductImageSyncTable,
              ProductImageSyncData
            >,
          ),
          ProductImageSyncData,
          PrefetchHooks Function()
        > {
  $$ProductImageSyncTableTableManager(
    _$AppDatabase db,
    $ProductImageSyncTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductImageSyncTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductImageSyncTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductImageSyncTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> shopId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String?> cloudPath = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductImageSyncCompanion(
                id: id,
                shopId: shopId,
                productId: productId,
                operation: operation,
                cloudPath: cloudPath,
                localPath: localPath,
                status: status,
                attemptCount: attemptCount,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String shopId,
                required String productId,
                required String operation,
                Value<String?> cloudPath = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductImageSyncCompanion.insert(
                id: id,
                shopId: shopId,
                productId: productId,
                operation: operation,
                cloudPath: cloudPath,
                localPath: localPath,
                status: status,
                attemptCount: attemptCount,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductImageSyncTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductImageSyncTable,
      ProductImageSyncData,
      $$ProductImageSyncTableFilterComposer,
      $$ProductImageSyncTableOrderingComposer,
      $$ProductImageSyncTableAnnotationComposer,
      $$ProductImageSyncTableCreateCompanionBuilder,
      $$ProductImageSyncTableUpdateCompanionBuilder,
      (
        ProductImageSyncData,
        BaseReferences<
          _$AppDatabase,
          $ProductImageSyncTable,
          ProductImageSyncData
        >,
      ),
      ProductImageSyncData,
      PrefetchHooks Function()
    >;
typedef $$StorageCleanupNotificationTableCreateCompanionBuilder =
    StorageCleanupNotificationCompanion Function({
      Value<String> id,
      required String shopId,
      required String kind,
      Value<int> orphanCount,
      Value<int> reclaimableBytes,
      Value<bool> isRead,
      Value<bool> dismissed,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$StorageCleanupNotificationTableUpdateCompanionBuilder =
    StorageCleanupNotificationCompanion Function({
      Value<String> id,
      Value<String> shopId,
      Value<String> kind,
      Value<int> orphanCount,
      Value<int> reclaimableBytes,
      Value<bool> isRead,
      Value<bool> dismissed,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$StorageCleanupNotificationTableFilterComposer
    extends Composer<_$AppDatabase, $StorageCleanupNotificationTable> {
  $$StorageCleanupNotificationTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orphanCount => $composableBuilder(
    column: $table.orphanCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reclaimableBytes => $composableBuilder(
    column: $table.reclaimableBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dismissed => $composableBuilder(
    column: $table.dismissed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StorageCleanupNotificationTableOrderingComposer
    extends Composer<_$AppDatabase, $StorageCleanupNotificationTable> {
  $$StorageCleanupNotificationTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orphanCount => $composableBuilder(
    column: $table.orphanCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reclaimableBytes => $composableBuilder(
    column: $table.reclaimableBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dismissed => $composableBuilder(
    column: $table.dismissed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StorageCleanupNotificationTableAnnotationComposer
    extends Composer<_$AppDatabase, $StorageCleanupNotificationTable> {
  $$StorageCleanupNotificationTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get shopId =>
      $composableBuilder(column: $table.shopId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get orphanCount => $composableBuilder(
    column: $table.orphanCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reclaimableBytes => $composableBuilder(
    column: $table.reclaimableBytes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<bool> get dismissed =>
      $composableBuilder(column: $table.dismissed, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$StorageCleanupNotificationTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StorageCleanupNotificationTable,
          StorageCleanupNotificationData,
          $$StorageCleanupNotificationTableFilterComposer,
          $$StorageCleanupNotificationTableOrderingComposer,
          $$StorageCleanupNotificationTableAnnotationComposer,
          $$StorageCleanupNotificationTableCreateCompanionBuilder,
          $$StorageCleanupNotificationTableUpdateCompanionBuilder,
          (
            StorageCleanupNotificationData,
            BaseReferences<
              _$AppDatabase,
              $StorageCleanupNotificationTable,
              StorageCleanupNotificationData
            >,
          ),
          StorageCleanupNotificationData,
          PrefetchHooks Function()
        > {
  $$StorageCleanupNotificationTableTableManager(
    _$AppDatabase db,
    $StorageCleanupNotificationTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StorageCleanupNotificationTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$StorageCleanupNotificationTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StorageCleanupNotificationTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> shopId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> orphanCount = const Value.absent(),
                Value<int> reclaimableBytes = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<bool> dismissed = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StorageCleanupNotificationCompanion(
                id: id,
                shopId: shopId,
                kind: kind,
                orphanCount: orphanCount,
                reclaimableBytes: reclaimableBytes,
                isRead: isRead,
                dismissed: dismissed,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String shopId,
                required String kind,
                Value<int> orphanCount = const Value.absent(),
                Value<int> reclaimableBytes = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<bool> dismissed = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StorageCleanupNotificationCompanion.insert(
                id: id,
                shopId: shopId,
                kind: kind,
                orphanCount: orphanCount,
                reclaimableBytes: reclaimableBytes,
                isRead: isRead,
                dismissed: dismissed,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StorageCleanupNotificationTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StorageCleanupNotificationTable,
      StorageCleanupNotificationData,
      $$StorageCleanupNotificationTableFilterComposer,
      $$StorageCleanupNotificationTableOrderingComposer,
      $$StorageCleanupNotificationTableAnnotationComposer,
      $$StorageCleanupNotificationTableCreateCompanionBuilder,
      $$StorageCleanupNotificationTableUpdateCompanionBuilder,
      (
        StorageCleanupNotificationData,
        BaseReferences<
          _$AppDatabase,
          $StorageCleanupNotificationTable,
          StorageCleanupNotificationData
        >,
      ),
      StorageCleanupNotificationData,
      PrefetchHooks Function()
    >;
typedef $$StorageCleanupStateTableCreateCompanionBuilder =
    StorageCleanupStateCompanion Function({
      required String shopId,
      Value<DateTime?> lastScanAt,
      Value<DateTime?> lastCleanupAt,
      Value<int?> lastUsedBytes,
      Value<int?> lastReclaimableBytes,
      Value<int> rowid,
    });
typedef $$StorageCleanupStateTableUpdateCompanionBuilder =
    StorageCleanupStateCompanion Function({
      Value<String> shopId,
      Value<DateTime?> lastScanAt,
      Value<DateTime?> lastCleanupAt,
      Value<int?> lastUsedBytes,
      Value<int?> lastReclaimableBytes,
      Value<int> rowid,
    });

class $$StorageCleanupStateTableFilterComposer
    extends Composer<_$AppDatabase, $StorageCleanupStateTable> {
  $$StorageCleanupStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCleanupAt => $composableBuilder(
    column: $table.lastCleanupAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUsedBytes => $composableBuilder(
    column: $table.lastUsedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReclaimableBytes => $composableBuilder(
    column: $table.lastReclaimableBytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StorageCleanupStateTableOrderingComposer
    extends Composer<_$AppDatabase, $StorageCleanupStateTable> {
  $$StorageCleanupStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCleanupAt => $composableBuilder(
    column: $table.lastCleanupAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUsedBytes => $composableBuilder(
    column: $table.lastUsedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReclaimableBytes => $composableBuilder(
    column: $table.lastReclaimableBytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StorageCleanupStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $StorageCleanupStateTable> {
  $$StorageCleanupStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get shopId =>
      $composableBuilder(column: $table.shopId, builder: (column) => column);

  GeneratedColumn<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCleanupAt => $composableBuilder(
    column: $table.lastCleanupAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastUsedBytes => $composableBuilder(
    column: $table.lastUsedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReclaimableBytes => $composableBuilder(
    column: $table.lastReclaimableBytes,
    builder: (column) => column,
  );
}

class $$StorageCleanupStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StorageCleanupStateTable,
          StorageCleanupStateData,
          $$StorageCleanupStateTableFilterComposer,
          $$StorageCleanupStateTableOrderingComposer,
          $$StorageCleanupStateTableAnnotationComposer,
          $$StorageCleanupStateTableCreateCompanionBuilder,
          $$StorageCleanupStateTableUpdateCompanionBuilder,
          (
            StorageCleanupStateData,
            BaseReferences<
              _$AppDatabase,
              $StorageCleanupStateTable,
              StorageCleanupStateData
            >,
          ),
          StorageCleanupStateData,
          PrefetchHooks Function()
        > {
  $$StorageCleanupStateTableTableManager(
    _$AppDatabase db,
    $StorageCleanupStateTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StorageCleanupStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StorageCleanupStateTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StorageCleanupStateTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> shopId = const Value.absent(),
                Value<DateTime?> lastScanAt = const Value.absent(),
                Value<DateTime?> lastCleanupAt = const Value.absent(),
                Value<int?> lastUsedBytes = const Value.absent(),
                Value<int?> lastReclaimableBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StorageCleanupStateCompanion(
                shopId: shopId,
                lastScanAt: lastScanAt,
                lastCleanupAt: lastCleanupAt,
                lastUsedBytes: lastUsedBytes,
                lastReclaimableBytes: lastReclaimableBytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String shopId,
                Value<DateTime?> lastScanAt = const Value.absent(),
                Value<DateTime?> lastCleanupAt = const Value.absent(),
                Value<int?> lastUsedBytes = const Value.absent(),
                Value<int?> lastReclaimableBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StorageCleanupStateCompanion.insert(
                shopId: shopId,
                lastScanAt: lastScanAt,
                lastCleanupAt: lastCleanupAt,
                lastUsedBytes: lastUsedBytes,
                lastReclaimableBytes: lastReclaimableBytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StorageCleanupStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StorageCleanupStateTable,
      StorageCleanupStateData,
      $$StorageCleanupStateTableFilterComposer,
      $$StorageCleanupStateTableOrderingComposer,
      $$StorageCleanupStateTableAnnotationComposer,
      $$StorageCleanupStateTableCreateCompanionBuilder,
      $$StorageCleanupStateTableUpdateCompanionBuilder,
      (
        StorageCleanupStateData,
        BaseReferences<
          _$AppDatabase,
          $StorageCleanupStateTable,
          StorageCleanupStateData
        >,
      ),
      StorageCleanupStateData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db, _db.shops);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$StaffPermissionsTableTableManager get staffPermissions =>
      $$StaffPermissionsTableTableManager(_db, _db.staffPermissions);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(_db, _db.productVariants);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db, _db.customers);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db, _db.sales);
  $$CustomerPaymentsTableTableManager get customerPayments =>
      $$CustomerPaymentsTableTableManager(_db, _db.customerPayments);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db, _db.saleItems);
  $$SaleSequencesTableTableManager get saleSequences =>
      $$SaleSequencesTableTableManager(_db, _db.saleSequences);
  $$StockMovementsTableTableManager get stockMovements =>
      $$StockMovementsTableTableManager(_db, _db.stockMovements);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db, _db.suppliers);
  $$PurchasesTableTableManager get purchases =>
      $$PurchasesTableTableManager(_db, _db.purchases);
  $$PurchaseItemsTableTableManager get purchaseItems =>
      $$PurchaseItemsTableTableManager(_db, _db.purchaseItems);
  $$PurchaseSequencesTableTableManager get purchaseSequences =>
      $$PurchaseSequencesTableTableManager(_db, _db.purchaseSequences);
  $$OffersTableTableManager get offers =>
      $$OffersTableTableManager(_db, _db.offers);
  $$ProductImageSyncTableTableManager get productImageSync =>
      $$ProductImageSyncTableTableManager(_db, _db.productImageSync);
  $$StorageCleanupNotificationTableTableManager
  get storageCleanupNotification =>
      $$StorageCleanupNotificationTableTableManager(
        _db,
        _db.storageCleanupNotification,
      );
  $$StorageCleanupStateTableTableManager get storageCleanupState =>
      $$StorageCleanupStateTableTableManager(_db, _db.storageCleanupState);
}
