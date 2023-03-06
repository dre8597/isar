// ignore_for_file: public_member_api_docs, invalid_use_of_protected_member

import 'dart:ffi';
import 'dart:html';
import 'dart:js_util';

import 'package:ffi/ffi.dart';
import 'package:isar/isar.dart';
import 'package:isar/src/common/schemas.dart';
import 'package:isar/src/native/bindings.dart';
import 'package:isar/src/native/isar_core.dart';

import 'package:isar/src/web/bindings.dart';
import 'package:isar/src/web/isar_collection_impl.dart';
import 'package:isar/src/web/isar_impl.dart';
import 'package:isar/src/web/isar_web.dart';
import 'package:meta/meta.dart';

bool _loaded = false;
Future<void> initializeIsarWeb([String? jsUrl]) async {
  if (_loaded) {
    return;
  }
  _loaded = true;

  final script = ScriptElement();
  script.type = 'text/javascript';
  // ignore: unsafe_html
  script.src = 'https://unpkg.com/isar@${Isar.version}/dist/index.js';
  script.async = true;
  document.head!.append(script);
  await script.onLoad.first.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      throw IsarError('Failed to load Isar');
    },
  );
}

@visibleForTesting
void doNotInitializeIsarWeb() {
  _loaded = true;
}

Future<Isar> openIsar({
  required List<CollectionSchema<dynamic>> schemas,
  String? directory,
  required String name,
  required int maxSizeMiB,
  required bool relaxedDurability,
  CompactCondition? compactOnLaunch,
}) async {
  await initializeIsarWeb();
  final schemasJson = getSchemas(schemas).map((e) => e.toJson());
  final schemasJs = jsify(schemasJson.toList()) as List<dynamic>;
  final instance = await openIsarJs(name, schemasJs, relaxedDurability).wait<IsarInstanceJs>();
  final isar = IsarImpl(name, instance);
  final cols = <Type, IsarCollection<dynamic>>{};
  final colPtrPtr = malloc<Pointer<CIsarCollection>>();

  for (final schema in schemas) {
    //TODO: Add in isarImpl here to allow this ncall to work
    // nCall(IC.isar_instance_get_collection(isar.ptr, colPtrPtr, schema.id));

    final offsets = _getOffsets(colPtrPtr.value, schema.properties.length, 0);

    for (final embeddedSchema in schema.embeddedSchemas.values) {
      final embeddedType = embeddedSchema.type;
      if (!isar.offsets.containsKey(embeddedType)) {
        final offsets = _getOffsets(
          colPtrPtr.value,
          embeddedSchema.properties.length,
          embeddedSchema.id,
        );
        isar.offsets[embeddedType] = offsets;
      }
    }

    final col = instance.getCollection(schema.name);
    schema.toCollection(<OBJ>() {
      schema as CollectionSchema<OBJ>;
      cols[OBJ] = IsarCollectionImpl<OBJ>(
        isar: isar,
        native: col,
        schema: schema,
      );
    });
  }

  isar.attachCollections(cols);
  return isar;
}

List<int> _getOffsets(
  Pointer<CIsarCollection> colPtr,
  int propertiesCount,
  int embeddedColId,
) {
  final offsetsPtr = malloc<Uint32>(propertiesCount);
  final staticSize = IC.isar_get_offsets(colPtr, embeddedColId, offsetsPtr);
  final offsets = offsetsPtr.asTypedList(propertiesCount).toList();
  offsets.add(staticSize);
  malloc.free(offsetsPtr);
  return offsets;
}


Isar openIsarSync({
  required List<CollectionSchema<dynamic>> schemas,
  String? directory,
  required String name,
  required int maxSizeMiB,
  required bool relaxedDurability,
  CompactCondition? compactOnLaunch,
}) =>
    unsupportedOnWeb();
