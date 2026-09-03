// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_image_sync_repository.dart';

// ignore_for_file: type=lint
mixin _$DriftImageSyncRepositoryMixin on DatabaseAccessor<AppDatabase> {
  $ProductImageSyncTable get productImageSync =>
      attachedDatabase.productImageSync;
  $ShopsTable get shops => attachedDatabase.shops;
  $CategoriesTable get categories => attachedDatabase.categories;
  $ProductsTable get products => attachedDatabase.products;
  DriftImageSyncRepositoryManager get managers =>
      DriftImageSyncRepositoryManager(this);
}

class DriftImageSyncRepositoryManager {
  final _$DriftImageSyncRepositoryMixin _db;
  DriftImageSyncRepositoryManager(this._db);
  $$ProductImageSyncTableTableManager get productImageSync =>
      $$ProductImageSyncTableTableManager(
        _db.attachedDatabase,
        _db.productImageSync,
      );
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db.attachedDatabase, _db.shops);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
}
