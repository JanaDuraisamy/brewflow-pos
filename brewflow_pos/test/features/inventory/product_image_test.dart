import 'dart:io';
import 'dart:typed_data';

import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_picker.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_store.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/product_form_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Images (Todo 12)
///
/// Covers the image store contract (persist/resolve/delete/restart) and the
/// end-to-end product form flow: pick → preview → save → persistent path,
/// replacement cleanup, removal, cancelled picker, missing-file fallback and
/// variant-product regression. All file IO happens in temporary directories;
/// the real gallery is never touched.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

/// One fully transparent 1x1 PNG — enough for Image.file to render without
/// decode errors.
final Uint8List _pngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0xDA,
  0x63,
  0x64,
  0x60,
  0xF8,
  0x5F,
  0x0F,
  0x00,
  0x02,
  0x87,
  0x01,
  0x80,
  0xEB,
  0x47,
  0xBA,
  0x92,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// Fake picker: returns a pre-built file, or null to simulate cancellation.
final class _FakePicker implements ProductImagePicker {
  File? result;
  int calls = 0;

  @override
  Future<PickedProductImage?> pickGallery() async {
    calls += 1;
    final file = result;
    if (file == null) {
      return null;
    }
    return PickedProductImage(file);
  }
}

void main() {
  late Directory tempDir;
  late ProductImageStore store;
  late Directory pickerDir;
  late FakeAuthRepository fakeAuth;
  late FakeInventoryRepository fakeInventory;
  late _FakePicker fakePicker;

  final now = DateTime.now().toUtc();

  Category category(String id, String name) => Category(
    id: id,
    name: name,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );

  Product product(
    String id,
    String name, {
    String categoryId = 'c1',
    String? imagePath,
  }) => Product(
    id: id,
    categoryId: categoryId,
    name: name,
    sku: null,
    sellingPricePaise: 14950,
    costPricePaise: null,
    stockQuantity: 0,
    imagePath: imagePath,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('brewflow_images_');
    store = ProductImageStore(documentsDir: tempDir);
    pickerDir = await Directory.systemTemp.createTemp('brewflow_picker_');
    fakeAuth = FakeAuthRepository();
    fakeInventory = FakeInventoryRepository();
    fakePicker = _FakePicker();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
    await pickerDir.delete(recursive: true);
  });

  group('ProductImageStore', () {
    test('saveFrom copies bytes and returns a relative path under '
        'product_images/', () async {
      final source = File('${pickerDir.path}/picked.jpg');
      await source.writeAsBytes(_pngBytes);

      final imagePath = await store.saveFrom(source);

      expect(imagePath, startsWith('${ProductImageStore.folderName}/'));
      expect(imagePath, endsWith('.jpg'));
      final resolved = store.resolve(imagePath);
      expect(resolved, isNotNull);
      expect(await resolved!.readAsBytes(), _pngBytes);
      // The picker's cache file is never the persisted reference.
      expect(imagePath.contains(pickerDir.path), isFalse);
    });

    test(
      'each save creates a fresh file and never mutates the previous one',
      () async {
        final first = File('${pickerDir.path}/a.jpg');
        await first.writeAsBytes(_pngBytes);
        final second = File('${pickerDir.path}/b.jpg');
        await second.writeAsBytes([1, 2, 3]);

        final firstPath = await store.saveFrom(first);
        final secondPath = await store.saveFrom(second);

        expect(firstPath, isNot(secondPath));
        expect(store.resolve(firstPath), isNotNull);
        expect(store.resolve(secondPath), isNotNull);
        expect(await store.resolve(firstPath)!.readAsBytes(), _pngBytes);
      },
    );

    test('resolve returns null for missing files', () {
      expect(store.resolve('${ProductImageStore.folderName}/nope.jpg'), isNull);
      expect(store.resolve('outside.jpg'), isNull);
    });

    test('delete removes the file and tolerates missing files', () async {
      final source = File('${pickerDir.path}/picked.jpg');
      await source.writeAsBytes(_pngBytes);
      final imagePath = await store.saveFrom(source);

      await store.delete(imagePath);
      expect(store.resolve(imagePath), isNull);

      // Deleting again (or a never-existing path) is a silent no-op.
      await store.delete(imagePath);
      await store.delete('${ProductImageStore.folderName}/ghost.jpg');
    });

    test('images survive a restart: a fresh store over the same directory '
        'resolves the same file', () async {
      final source = File('${pickerDir.path}/picked.jpg');
      await source.writeAsBytes(_pngBytes);
      final imagePath = await store.saveFrom(source);

      final restarted = ProductImageStore(documentsDir: tempDir);
      final resolved = restarted.resolve(imagePath);

      expect(resolved, isNotNull);
      expect(await resolved!.readAsBytes(), _pngBytes);
    });
  });

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      inventoryRepositoryProvider.overrideWithValue(fakeInventory),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
      productImageStoreProvider.overrideWith((ref) async => store),
      productImagePickerProvider.overrideWithValue(fakePicker),
    ],
    child: const BrewFlowApp(),
  );

  Future<void> pumpAuthenticated(WidgetTester tester) async {
    await tester.pumpWidget(app());
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
  }

  Future<void> pumpAsync(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> openInventory(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.inventory);
    await pumpAsync(tester);
  }

  Future<void> openNewProductForm(WidgetTester tester) async {
    await openInventory(tester);
    await tester.tap(find.text('Add Product').first);
    await pumpAsync(tester);
    expect(find.byType(ProductFormPage), findsOneWidget);
  }

  Future<void> openEditForm(WidgetTester tester, String name) async {
    await openInventory(tester);
    await tester.tap(find.text(name));
    await pumpAsync(tester);
    expect(find.byType(ProductFormPage), findsOneWidget);
  }

  Future<void> selectCategory(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beverages').last);
    await tester.pumpAndSettle();
  }

  Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
    final list = find.descendant(
      of: find.byType(ProductFormPage),
      matching: find.byType(Scrollable),
    );
    final scrollable = list.first;
    final viewport = tester.getRect(find.byType(ProductFormPage));
    for (var i = 0; i < 40; i++) {
      final elements = finder.evaluate();
      if (elements.isNotEmpty) {
        final box = elements.first.renderObject! as RenderBox;
        final topLeft = box.localToGlobal(Offset.zero);
        final bottomRight = topLeft + box.size.bottomRight(Offset.zero);
        final fullyVisible =
            topLeft.dy >= 0 && bottomRight.dy <= viewport.height;
        if (fullyVisible) {
          await tester.pump();
          return;
        }
      }
      await tester.drag(scrollable, const Offset(0, -160));
      await tester.pump();
    }
    fail('Could not scroll $finder into view');
  }

  /// Completes the create flow for a plain product with a picked image, or
  /// without one when [image] is false. The save runs inside [tester.runAsync]
  /// because persisting the image is real file IO.
  Future<void> createProduct(
    WidgetTester tester, {
    required bool image,
    String name = 'Filter Coffee',
  }) async {
    await openNewProductForm(tester);
    if (image) {
      await tester.tap(find.text('Choose Image'));
      await tester.pump();
    }
    await tester.enterText(find.byType(TextFormField).at(0), name);
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await tester.enterText(find.byType(TextFormField).at(2), '150');
    await tester.enterText(find.byType(TextFormField).at(3), '');
    await tester.enterText(find.byType(TextFormField).at(4), '0');
    await selectCategory(tester);

    final save = find.widgetWithText(FilledButton, 'Save Product');
    await scrollFormTo(tester, save);
    await tester.runAsync(() async {
      await tester.tap(save);
      // Real file IO on the submit chain is not awaited by the framework, so
      // give it generous real time and render each step; a bounded pump loop
      // avoids pumpAndSettle (which never settles while a real-zone image
      // decode or snackbar timer is in flight).
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    // Back in the fake zone: finish the pop transition (and any snackbar)
    // so the form is fully gone.
    await tester.pumpAndSettle();
  }

  /// Lets a discarded preview's [Image.file] finish its real decode so it
  /// releases its file handle; on Windows an open handle blocks deletion.
  Future<void> flushRealIo(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
  }

  /// Completes the edit flow without changing any field; the image section is
  /// left as it is unless [remove] is set.
  Future<void> saveEdit(WidgetTester tester, {bool remove = false}) async {
    if (remove) {
      await tester.tap(find.text('Remove Image'));
      await tester.pump();
    }
    final save = find.widgetWithText(FilledButton, 'Save Changes');
    await scrollFormTo(tester, save);
    await tester.runAsync(() async {
      await tester.tap(save);
      // See createProduct: bounded real-time pump loop instead of
      // pumpAndSettle so the fire-and-forget submit chain always completes.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    // Back in the fake zone: finish the pop transition (and any snackbar)
    // so the form is fully gone.
    await tester.pumpAndSettle();
  }

  group('product form images', () {
    testWidgets('no image regression: saving without an image keeps '
        'imagePath null', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      await pumpAuthenticated(tester);

      expect(find.text('Choose Image'), findsNothing);
      await createProduct(tester, image: false);

      expect(find.byType(ProductFormPage), findsNothing);
      final saved = fakeInventory.storedProducts.single;
      expect(saved.imagePath, isNull);
      expect(fakePicker.calls, 0);
    });

    testWidgets('picking an image shows a preview and persists the stored '
        'file on save', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakePicker.result = File('${pickerDir.path}/gallery_pick.jpg')
        ..writeAsBytesSync(_pngBytes);
      await pumpAuthenticated(tester);

      await createProduct(tester, image: true);

      final saved = fakeInventory.storedProducts.single;
      expect(saved.imagePath, isNotNull);
      final resolved = store.resolve(saved.imagePath!);
      expect(resolved, isNotNull);
      expect(resolved!.readAsBytesSync(), _pngBytes);
    });

    testWidgets('the preview reflects a picked image before saving', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakePicker.result = File('${pickerDir.path}/gallery_pick.jpg')
        ..writeAsBytesSync(_pngBytes);
      await pumpAuthenticated(tester);
      await openNewProductForm(tester);

      expect(
        find.descendant(
          of: find.byType(ProductFormPage),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Choose Image'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(ProductFormPage),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(find.text('Change Image'), findsOneWidget);
      expect(find.text('Remove Image'), findsOneWidget);
    });

    testWidgets('a cancelled picker leaves the form untouched', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakePicker.result = null;
      await pumpAuthenticated(tester);
      await openNewProductForm(tester);

      await tester.tap(find.text('Choose Image'));
      await tester.pump();

      expect(fakePicker.calls, 1);
      expect(
        find.descendant(
          of: find.byType(ProductFormPage),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      expect(find.text('Remove Image'), findsNothing);
      expect(find.text('Choose Image'), findsOneWidget);
    });

    testWidgets('editing restores the stored image and keeps it on save', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      final source = File('${pickerDir.path}/picked.jpg');
      source.writeAsBytesSync(_pngBytes);
      final imagePath = (await tester.runAsync(() => store.saveFrom(source)))!;
      fakeInventory.storedProducts.add(
        product('p1', 'Filter Coffee', imagePath: imagePath),
      );
      await pumpAuthenticated(tester);

      await openEditForm(tester, 'Filter Coffee');
      expect(
        find.descendant(
          of: find.byType(ProductFormPage),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(find.text('Change Image'), findsOneWidget);

      await saveEdit(tester);

      expect(fakeInventory.storedProducts.single.imagePath, imagePath);
      expect(store.resolve(imagePath), isNotNull);
    });

    testWidgets('replacement persists the new image and cleans up the old '
        'file', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      final source = File('${pickerDir.path}/picked.jpg');
      source.writeAsBytesSync(_pngBytes);
      final oldPath = (await tester.runAsync(() => store.saveFrom(source)))!;
      fakeInventory.storedProducts.add(
        product('p1', 'Filter Coffee', imagePath: oldPath),
      );
      fakePicker.result = File('${pickerDir.path}/replacement.jpg')
        ..writeAsBytesSync(_pngBytes);
      await pumpAuthenticated(tester);

      await openEditForm(tester, 'Filter Coffee');
      await tester.tap(find.text('Change Image'));
      await tester.pump();
      // The replaced preview's FileImage is disposed mid-decode; give it real
      // time to release its handle so the cleanup delete below succeeds.
      await flushRealIo(tester);
      await saveEdit(tester);

      final saved = fakeInventory.storedProducts.single;
      expect(saved.imagePath, isNot(oldPath));
      expect(store.resolve(saved.imagePath!), isNotNull);
      expect(
        store.resolve(oldPath),
        isNull,
        reason: 'the replaced file must be cleaned up',
      );
    });

    testWidgets('removal clears imagePath and deletes the stored file', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      final source = File('${pickerDir.path}/picked.jpg');
      source.writeAsBytesSync(_pngBytes);
      final imagePath = (await tester.runAsync(() => store.saveFrom(source)))!;
      fakeInventory.storedProducts.add(
        product('p1', 'Filter Coffee', imagePath: imagePath),
      );
      await pumpAuthenticated(tester);

      await openEditForm(tester, 'Filter Coffee');
      await tester.tap(find.text('Remove Image'));
      await tester.pump();
      expect(find.text('Change Image'), findsNothing);
      // The removed preview's FileImage is disposed mid-decode; give it real
      // time to release its handle so the cleanup delete below succeeds.
      await flushRealIo(tester);
      await saveEdit(tester);

      final saved = fakeInventory.storedProducts.single;
      expect(saved.imagePath, isNull);
      expect(
        store.resolve(imagePath),
        isNull,
        reason: 'removing the image must clean the stored file',
      );
    });

    testWidgets('a missing image file falls back without crashing', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Filter Coffee',
          imagePath: '${ProductImageStore.folderName}/gone.jpg',
        ),
      );
      await pumpAuthenticated(tester);

      await openEditForm(tester, 'Filter Coffee');

      // Form preview renders the placeholder; no exceptions are thrown.
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets);

      // Saving without touching the image keeps the (missing) reference.
      await saveEdit(tester);
      expect(
        fakeInventory.storedProducts.single.imagePath,
        '${ProductImageStore.folderName}/gone.jpg',
      );
    });

    testWidgets('a variant product saves with an image (variant regression)', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakePicker.result = File('${pickerDir.path}/gallery_pick.jpg')
        ..writeAsBytesSync(_pngBytes);
      await pumpAuthenticated(tester);

      await openNewProductForm(tester);
      await tester.tap(find.text('Choose Image'));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).at(0), 'Filter Coffee');
      await tester.enterText(find.byType(TextFormField).at(2), '150');
      await tester.enterText(find.byType(TextFormField).at(4), '0');
      await selectCategory(tester);

      await scrollFormTo(tester, find.text('Add Variant'));
      await tester.tap(find.text('Add Variant'));
      await tester.pump();
      final variantField = find.widgetWithText(TextFormField, 'Variant name *');
      await scrollFormTo(tester, variantField);
      await tester.enterText(variantField, 'Small');
      final variantCard = find.ancestor(
        of: find.text('Variant 1'),
        matching: find.byType(AppCard),
      );
      final variantPrice = find.descendant(
        of: variantCard,
        matching: find.widgetWithText(TextFormField, 'Selling price (₹) *'),
      );
      await scrollFormTo(tester, variantPrice);
      await tester.enterText(variantPrice, '150');
      final variantStock = find.descendant(
        of: variantCard,
        matching: find.widgetWithText(TextFormField, 'Opening stock *'),
      );
      await scrollFormTo(tester, variantStock);
      await tester.enterText(variantStock, '10');

      final save = find.widgetWithText(FilledButton, 'Save Product');
      await scrollFormTo(tester, save);
      await tester.runAsync(() async {
        await tester.tap(save);
        // See createProduct: bounded real-time pump loop.
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      final saved = fakeInventory.storedProducts.single;
      expect(saved.imagePath, isNotNull);
      expect(store.resolve(saved.imagePath!), isNotNull);
      expect(saved.variants, hasLength(1));
      expect(saved.variants.single.name, 'Small');
    });
  });

  group('inventory display', () {
    testWidgets('inventory shows the stored image thumbnail and falls back '
        'for a missing file', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      final source = File('${pickerDir.path}/picked.jpg');
      source.writeAsBytesSync(_pngBytes);
      final imagePath = (await tester.runAsync(() => store.saveFrom(source)))!;
      fakeInventory.storedProducts.addAll([
        product('p1', 'With Image', imagePath: imagePath),
        product(
          'p2',
          'Broken Image',
          imagePath: '${ProductImageStore.folderName}/gone.jpg',
        ),
        product('p3', 'No Image'),
      ]);
      await pumpAuthenticated(tester);
      await openInventory(tester);

      // Two thumbnails render real images; the placeholder covers the rest.
      expect(find.text('With Image'), findsOneWidget);
      expect(find.text('Broken Image'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
