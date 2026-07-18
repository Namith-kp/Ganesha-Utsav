// Web stub for dart:io

class File {
  final String path;
  File(this.path);

  Future<bool> exists() async => false;
  Future<void> writeAsBytes(List<int> bytes) async {}
  Future<void> writeAsString(String contents) async {}
}

class Directory {
  final String path;
  Directory(this.path);

  Future<bool> exists() async => false;
  Future<void> create({bool recursive = false}) async {}
}
