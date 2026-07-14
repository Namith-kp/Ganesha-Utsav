import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/street_view_service.dart';

final streetViewServiceProvider = Provider((ref) => StreetViewService());
