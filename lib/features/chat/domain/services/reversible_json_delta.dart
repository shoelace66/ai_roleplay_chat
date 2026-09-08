import 'dart:convert';

/// 可逆差量。列表只保存公共前后缀之间的替换段，恢复时校验当前值。
class ReversibleJsonDelta {
  const ReversibleJsonDelta();
  bool same(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && same(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => same(a[i], b[i]));
    }
    return a == b;
  }

  List<Map<String, dynamic>> between(dynamic before, dynamic after) {
    final result = <Map<String, dynamic>>[];
    void visit(dynamic a, dynamic b, List<dynamic> path) {
      if (same(a, b)) return;
      if (a is Map && b is Map) {
        for (final key in {...a.keys, ...b.keys}) {
          if (!a.containsKey(key) || !b.containsKey(key)) {
            result.add({
              'path': [...path, key],
              'beforeExists': a.containsKey(key),
              'afterExists': b.containsKey(key),
              'before': a[key],
              'after': b[key]
            });
          } else {
            visit(a[key], b[key], [...path, key]);
          }
        }
      } else if (a is List && b is List) {
        var prefix = 0;
        while (prefix < a.length &&
            prefix < b.length &&
            same(a[prefix], b[prefix])) {
          prefix++;
        }
        var suffix = 0;
        while (suffix < a.length - prefix &&
            suffix < b.length - prefix &&
            same(a[a.length - 1 - suffix], b[b.length - 1 - suffix])) {
          suffix++;
        }
        result.add({
          'path': path,
          'index': prefix,
          'before': a.sublist(prefix, a.length - suffix),
          'after': b.sublist(prefix, b.length - suffix)
        });
      } else {
        result.add({
          'path': path,
          'beforeExists': true,
          'afterExists': true,
          'before': a,
          'after': b
        });
      }
    }

    visit(before, after, []);
    return jsonDecode(jsonEncode(result)).cast<Map<String, dynamic>>();
  }

  dynamic apply(dynamic source, List<dynamic> changes, {bool reverse = false}) {
    dynamic root = jsonDecode(jsonEncode(source));
    for (final raw in reverse ? changes.reversed : changes) {
      final change = raw as Map;
      final path = change['path'] as List;
      final expected = change[reverse ? 'after' : 'before'];
      final replacement = change[reverse ? 'before' : 'after'];
      dynamic parent = root;
      for (final key in path.take(path.isEmpty ? 0 : path.length - 1)) {
        parent = parent[key];
      }
      final dynamic current = path.isEmpty ? root : parent[path.last];
      if (change.containsKey('index')) {
        if (current is! List || expected is! List || replacement is! List) {
          throw StateError('日志列表格式错误');
        }
        final index = change['index'] as int;
        if (index < 0 ||
            index + expected.length > current.length ||
            !same(current.sublist(index, index + expected.length), expected)) {
          throw StateError('剧情已变化，不能应用旧日志');
        }
        current.replaceRange(index, index + expected.length, replacement);
      } else {
        final exists = change[reverse ? 'afterExists' : 'beforeExists'] == true;
        final replaceExists =
            change[reverse ? 'beforeExists' : 'afterExists'] == true;
        if ((path.isNotEmpty &&
                parent is Map &&
                parent.containsKey(path.last) != exists) ||
            (exists && !same(current, expected))) {
          throw StateError('剧情已变化，不能应用旧日志');
        }
        if (path.isEmpty) {
          root = replacement;
        } else if (!replaceExists) {
          (parent as Map).remove(path.last);
        } else {
          parent[path.last] = replacement;
        }
      }
    }
    return root;
  }
}
