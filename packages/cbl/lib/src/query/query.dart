import 'dart:async';

import 'package:cbl_ffi/cbl_ffi.dart';
import 'package:meta/meta.dart';

import '../couchbase_lite.dart';
import '../database.dart';
import '../database/database.dart';
import '../database/ffi_database.dart';
import '../database/proxy_database.dart';
import '../support/resource.dart';
import '../support/utils.dart';
import 'ffi_query.dart';
import 'parameters.dart';
import 'proxy_query.dart';
import 'query_change.dart';
import 'result.dart';
import 'result_set.dart';

/// A listener that is called when the results of a [Query] have changed.
typedef QueryChangeListener<T extends ResultSet> = void Function(
  QueryChange<T> change,
);

/// A [Database] query.
abstract class Query implements Resource {
  /// Creates an [Query] from a N1QL [query].
  static FutureOr<Query> fromN1ql(Database database, String query) {
    if (database is AsyncDatabase) {
      return Query.fromN1qlAsync(database, query);
    }

    if (database is SyncDatabase) {
      return Query.fromN1qlSync(database, query);
    }

    throw UnimplementedError();
  }

  /// {@template cbl.Query.fromN1qlAsync}
  /// Creates an [AsyncQuery] from a N1QL [query].
  /// {@endtemplate}
  static Future<AsyncQuery> fromN1qlAsync(
    AsyncDatabase database,
    String query,
  ) =>
      AsyncQuery.fromN1ql(database, query);

  /// {@template cbl.Query.fromN1qlSync}
  /// Creates a [SyncQuery] from a N1QL [query].
  /// {@endtemplate}
  // ignore: prefer_constructors_over_static_methods
  static SyncQuery fromN1qlSync(SyncDatabase database, String query) =>
      SyncQuery.fromN1ql(database, query);

  /// Creates a [Query] from the [Query.jsonRepresentation] of a query.
  static FutureOr<Query> fromJsonRepresentation(
    Database database,
    String jsonRepresentation,
  ) {
    if (database is AsyncDatabase) {
      return Query.fromJsonRepresentationAsync(database, jsonRepresentation);
    }

    if (database is SyncDatabase) {
      return Query.fromJsonRepresentationSync(database, jsonRepresentation);
    }

    throw UnimplementedError();
  }

  /// {@template cbl.Query.fromJsonRepresentation}
  /// Creates an [AsyncQuery] from the [Query.jsonRepresentation] of a query.
  /// {@endtemplate}
  static Future<AsyncQuery> fromJsonRepresentationAsync(
    AsyncDatabase database,
    String jsonRepresentation,
  ) =>
      AsyncQuery.fromJsonRepresentation(database, jsonRepresentation);

  /// {@template cbl.Query.fromJsonRepresentation}
  /// Creates an [SyncQuery] from the [Query.jsonRepresentation] of a query.
  /// {@endtemplate}
  // ignore: prefer_constructors_over_static_methods
  static SyncQuery fromJsonRepresentationSync(
    SyncDatabase database,
    String jsonRepresentation,
  ) =>
      SyncQuery.fromJsonRepresentation(database, jsonRepresentation);

  /// The values with which to substitute the parameters defined in the query.
  ///
  /// All parameters defined in the query must be given values before running
  /// the query, or the query will fail.
  ///
  /// The returned [Parameters] will be readonly.
  Parameters? get parameters;

  /// Sets the [parameters] of this query.
  FutureOr<void> setParameters(Parameters? value);

  /// Executes this query.
  ///
  /// Returns a [ResultSet] that iterates over [Result] rows one at a time. You
  /// can run the query any number of times, and you can have multiple
  /// [ResultSet]s active at once.
  ///
  /// The results come from a snapshot of the database taken at the moment
  /// [execute] is called, so they will not reflect any changes made to the
  /// database afterwards.
  FutureOr<ResultSet> execute();

  /// Returns a string describing the implementation of the compiled query.
  ///
  /// This is intended to be read by a developer for purposes of optimizing the
  /// query, especially to add database indexes. It's not machine-readable and
  /// its format may change.
  ///
  /// As currently implemented, the result has three sections, separated by two
  /// newlines:
  /// * The first section is this query compiled into an SQLite query.
  /// * The second section is the output of SQLite's "EXPLAIN QUERY PLAN"
  ///   command applied to that query; for help interpreting this, see
  ///   https://www.sqlite.org/eqp.html . The most important thing to know is
  ///   that if you see "SCAN TABLE", it means that SQLite is doing a slow
  ///   linear scan of the documents instead of using an index.
  /// * The third sections is this queries JSON representation. This is the data
  ///   structure that is built to describe this query, either by the the query
  ///   builder or when a N1QL query is compiled.
  FutureOr<String> explain();

  /// Adds a [listener] to be notified of changes to the results of this query.
  ///
  /// A new listener will be called with the current results, after being added.
  /// Subsequently it will only be called when the results change, either
  /// because the contents of the database have changed or this query's
  /// [parameters] have been changed through [setParameters].
  ///
  /// {@macro cbl.Database.addChangeListener}
  ///
  /// See also:
  ///
  ///   - [QueryChange] for the change event given to [listener].
  ///   - [removeChangeListener] for removing a previously added listener.
  FutureOr<ListenerToken> addChangeListener(QueryChangeListener listener);

  /// {@macro cbl.Database.removeChangeListener}
  ///
  /// See also:
  ///
  ///   - [addChangeListener] for listening to changes in the results of this
  ///     query.
  FutureOr<void> removeChangeListener(ListenerToken token);

  /// Returns a [Stream] to be notified of changes to the results of this query.
  ///
  /// This is an alternative stream based API for the [addChangeListener] API.
  ///
  /// {@macro cbl.Database.AsyncListenStream}
  Stream<QueryChange> changes();

  /// The JSON representation of this query.
  ///
  /// This value can be used to recreate this query with
  /// [SyncQuery.fromJsonRepresentation] or [AsyncQuery.fromJsonRepresentation].
  ///
  /// Is `null`, if this query was created from a N1QL query.
  String? get jsonRepresentation;
}

/// A [Query] with a primarily synchronous API.
abstract class SyncQuery implements Query {
  /// {@macro cbl.Query.fromN1qlSync}
  factory SyncQuery.fromN1ql(SyncDatabase database, String query) => FfiQuery(
        database: database as FfiDatabase,
        definition: query,
        language: CBLQueryLanguage.n1ql,
        debugCreator: 'SyncQuery.fromN1ql()',
      )..prepare();

  /// {@macro cbl.Query.fromJsonRepresentationSync}
  factory SyncQuery.fromJsonRepresentation(
    SyncDatabase database,
    String json,
  ) =>
      FfiQuery(
        database: database as FfiDatabase,
        definition: json,
        language: CBLQueryLanguage.json,
        debugCreator: 'SyncQuery.fromJsonRepresentation()',
      )..prepare();

  @override
  void setParameters(Parameters? value);

  @override
  SyncResultSet execute();

  @override
  String explain();

  @override
  ListenerToken addChangeListener(QueryChangeListener<SyncResultSet> listener);

  @override
  void removeChangeListener(ListenerToken token);

  @override
  Stream<QueryChange<SyncResultSet>> changes();
}

/// A [Query] query with a primarily asynchronous API.
abstract class AsyncQuery implements Query {
  /// {@macro cbl.Query.fromN1qlAsync}
  static Future<AsyncQuery> fromN1ql(
    AsyncDatabase database,
    String query,
  ) async {
    final q = ProxyQuery(
      database: database as ProxyDatabase,
      debugCreator: 'AsyncQuery.fromN1ql()',
      language: CBLQueryLanguage.n1ql,
      definition: query,
    );

    await q.prepare();

    return q;
  }

  /// {@macro cbl.Query.fromJsonRepresentation}
  static Future<AsyncQuery> fromJsonRepresentation(
    AsyncDatabase database,
    String json,
  ) async {
    final q = ProxyQuery(
      database: database as ProxyDatabase,
      debugCreator: 'AsyncQuery.fromJsonRepresentation()',
      language: CBLQueryLanguage.json,
      definition: json,
    );

    await q.prepare();

    return q;
  }

  @override
  Future<void> setParameters(Parameters? value);

  @override
  Future<ResultSet> execute();

  @override
  Future<String> explain();

  @override
  Future<ListenerToken> addChangeListener(QueryChangeListener listener);

  @override
  Future<void> removeChangeListener(ListenerToken token);

  @override
  AsyncListenStream<QueryChange> changes();
}

abstract class QueryBase with ClosableResourceMixin implements Query {
  QueryBase({
    required this.typeName,
    required this.debugCreator,
    this.database,
    required this.language,
    String? definition,
  }) : definition = language == CBLQueryLanguage.n1ql
            ? _normalizeN1qlQuery(definition!)
            : definition;

  final String typeName;
  final String debugCreator;
  final Database? database;
  final CBLQueryLanguage language;
  String? definition;
  bool _didAttachToParentResource = false;

  bool get _wasPrepared => _prepared != false;
  FutureOr<bool>? _prepared = false;

  FutureOr<void> prepare() {
    _attachToParentResource();

    if (_wasPrepared) {
      return null;
    }

    // ignore: void_checks
    return _prepared = performPrepare().then((_) => true);
  }

  @protected
  FutureOr<void> performPrepare();

  @override
  T useSync<T>(T Function() f) {
    _attachToParentResource();
    return super.useSync(() {
      assert(_prepared is! Future);
      if (_prepared == false) {
        final result = performPrepare();
        assert(result is! Future);
        _prepared = true;
      }
      return f();
    });
  }

  @override
  Future<T> use<T>(FutureOr<T> Function() f) {
    _attachToParentResource();
    return super.use(() async {
      if (_prepared == false) {
        _prepared = performPrepare().then((_) => true);
      }
      await _prepared;
      return f();
    });
  }

  @override
  String? get jsonRepresentation =>
      language == CBLQueryLanguage.json ? definition : null;

  @override
  String toString() => '$typeName(${describeEnum(language)}: $definition)';

  void _attachToParentResource() {
    if (!_didAttachToParentResource) {
      needsFinalization = false;
      attachTo(database! as ClosableResourceMixin);
      _didAttachToParentResource = true;
    }
  }
}

String _normalizeN1qlQuery(String query) => query
    // Collapse whitespace.
    .replaceAll(RegExp(r'\s+'), ' ');
