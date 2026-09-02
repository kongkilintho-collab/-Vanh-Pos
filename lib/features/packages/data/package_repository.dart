import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/package.dart';
import '../../../shared/models/package_item.dart';

/// packages/package_items follow the catalog write pattern (same class as
/// ServiceRepository) -- direct table writes, RLS-gated at MANAGER+
/// (0032_packages_schema.sql), no RPC. package_items are replaced wholesale
/// on update (delete all, re-insert) since a package's service/session
/// composition has no independent identity worth preserving row-by-row --
/// this only ever affects future purchases; customer_package_items
/// snapshots already taken are untouched (0032's snapshot design).
class PackageRepository {
  final SupabaseClient _client;

  PackageRepository(this._client);

  static const _selectColumns = '*, package_items(*, services(name))';

  Future<List<Package>> listForBusiness(String businessId) async {
    final rows = await _client
        .from('packages')
        .select(_selectColumns)
        .eq('business_id', businessId)
        .order('name');
    return (rows as List).map((r) => Package.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Package> create(Package package, List<PackageItem> items) async {
    final row = await _client
        .from('packages')
        .insert(package.toInsertJson(businessId: package.businessId))
        .select()
        .single();
    final packageId = row['id'] as String;
    if (items.isNotEmpty) {
      await _client.from('package_items').insert(
            items.map((i) => i.toInsertJson(businessId: package.businessId, packageId: packageId)).toList(),
          );
    }
    return _fetchById(package.businessId, packageId);
  }

  Future<Package> update(Package package, List<PackageItem> items) async {
    await _client
        .from('packages')
        .update(package.toInsertJson(businessId: package.businessId))
        .eq('id', package.id);
    await _client.from('package_items').delete().eq('package_id', package.id);
    if (items.isNotEmpty) {
      await _client.from('package_items').insert(
            items.map((i) => i.toInsertJson(businessId: package.businessId, packageId: package.id)).toList(),
          );
    }
    return _fetchById(package.businessId, package.id);
  }

  Future<void> setActive(String id, bool active) async {
    await _client.from('packages').update({'active': active}).eq('id', id);
  }

  Future<Package> _fetchById(String businessId, String id) async {
    final row = await _client
        .from('packages')
        .select(_selectColumns)
        .eq('business_id', businessId)
        .eq('id', id)
        .single();
    return Package.fromJson(row);
  }
}
