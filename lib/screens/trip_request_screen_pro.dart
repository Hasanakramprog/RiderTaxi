import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:math' show min, max;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/location_model.dart';
import '../providers/map_provider.dart';
import '../providers/firestore_provider.dart';
import '../widgets/map_widget.dart';
import '../widgets/network_connectivity_widgets.dart';
import 'trip_tracking_screen.dart';

enum _BookingStep { pickup, dropoff, stop, confirm }

class TripRequestScreenPro extends StatefulWidget {
  const TripRequestScreenPro({Key? key}) : super(key: key);

  @override
  State<TripRequestScreenPro> createState() => _TripRequestScreenProState();
}

class _TripRequestScreenProState extends State<TripRequestScreenPro>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────
  _BookingStep _step = _BookingStep.pickup;
  bool _isDragging = false;
  String _dragAddress = '';
  LatLng? _dragLatLng;
  Timer? _geocodeDebounce;
  int _editingStopIndex = -1;
  String _selectedCarType = 'standard';

  late AnimationController _sheetController;

  static const double _stopCharge = 2.0;
  static const double _waitingChargePerMinute = 0.5;

  final List<Map<String, dynamic>> _carTypes = [
    {
      'id': 'standard',
      'name': 'Standard',
      'icon': Icons.directions_car,
      'capacity': '4 seats',
      'price': 1.0,
    },
    {
      'id': 'xl',
      'name': 'XL',
      'icon': Icons.airport_shuttle,
      'capacity': '6 seats',
      'price': 1.5,
    },
    {
      'id': 'vip',
      'name': 'VIP',
      'icon': Icons.electric_car,
      'capacity': '4 seats',
      'price': 2.0,
    },
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();

    Future.delayed(Duration.zero, () async {
      if (!mounted) return;
      final mp = Provider.of<MapProvider>(context, listen: false);
      if (!mp.hasInitializedLocation) {
        await mp.initializeUserLocation();
      }
      if (!mounted) return;
      setState(() {
        _dragAddress = mp.pickupLocation?.address ?? '';
        _dragLatLng = mp.pickupLocation?.coordinates ?? mp.currentUserLocation;
      });
    });
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  // ── Computed helpers ───────────────────────────────────────────────
  Color get _pinColor {
    switch (_step) {
      case _BookingStep.pickup:
        return const Color(0xFF4CAF50);
      case _BookingStep.dropoff:
        return const Color(0xFFE53935);
      case _BookingStep.stop:
        return const Color(0xFFFF9800);
      case _BookingStep.confirm:
        return Colors.transparent;
    }
  }

  String get _stepLabel {
    switch (_step) {
      case _BookingStep.pickup:
        return 'Set Pickup';
      case _BookingStep.dropoff:
        return 'Set Destination';
      case _BookingStep.stop:
        return 'Set Stop ${_editingStopIndex + 1}';
      case _BookingStep.confirm:
        return 'Confirm Ride';
    }
  }

  // ── Camera callbacks ───────────────────────────────────────────────
  void _onCameraMove(LatLng center) {
    _dragLatLng = center;
    if (!_isDragging || _dragAddress != 'Moving...') {
      setState(() {
        _isDragging = true;
        _dragAddress = 'Moving...';
      });
    }
    _geocodeDebounce?.cancel();
  }

  void _onCameraIdle(LatLng center) {
    setState(() {
      _isDragging = false;
      _dragLatLng = center;
    });
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _resolveAddress(center),
    );
  }

  Future<void> _resolveAddress(LatLng latLng) async {
    if (!mounted) return;
    final mp = Provider.of<MapProvider>(context, listen: false);
    final loc = await mp.reverseGeocodeLatLng(latLng);
    if (!mounted) return;
    setState(() {
      _dragAddress =
          loc?.address ??
          '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
    });
  }

  // ── Step actions ───────────────────────────────────────────────────
  Future<void> _confirmPickup() async {
    if (_dragLatLng == null ||
        _dragAddress.isEmpty ||
        _dragAddress == 'Moving...')
      return;
    final mp = Provider.of<MapProvider>(context, listen: false);
    final loc = LocationModel(
      placeId: 'drag_pickup',
      address: _dragAddress,
      coordinates: _dragLatLng!,
      name: _dragAddress.split(',').first.trim(),
    );
    mp.setPickupLocationSilent(loc);
    final existingDropoff = mp.dropoffLocation;
    setState(() {
      _step = _BookingStep.dropoff;
      _dragAddress = existingDropoff?.address ?? '';
      _dragLatLng = existingDropoff?.coordinates;
    });
    if (existingDropoff != null) {
      await mp.animateCameraTo(existingDropoff.coordinates);
    }
  }

  Future<void> _confirmDropoff() async {
    if (_dragLatLng == null ||
        _dragAddress.isEmpty ||
        _dragAddress == 'Moving...')
      return;
    final mp = Provider.of<MapProvider>(context, listen: false);
    final loc = LocationModel(
      placeId: 'drag_dropoff',
      address: _dragAddress,
      coordinates: _dragLatLng!,
      name: _dragAddress.split(',').first.trim(),
    );
    await mp.setDropoffLocation(loc);
    if (!mounted) return;
    setState(() => _step = _BookingStep.confirm);
    // Delay slightly so the bottom-sheet slide animation completes before
    // the camera moves — gives a polished, non-jarring transition.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _fitCameraToRoute(mp);
    });
  }

  void _addStop() {
    final mp = Provider.of<MapProvider>(context, listen: false);
    mp.addStop();
    setState(() {
      _editingStopIndex = mp.stops.length - 1;
      _step = _BookingStep.stop;
      _dragAddress = '';
      _dragLatLng = null;
    });
  }

  Future<void> _confirmStop() async {
    if (_dragLatLng == null ||
        _dragAddress.isEmpty ||
        _dragAddress == 'Moving...')
      return;
    final mp = Provider.of<MapProvider>(context, listen: false);
    await mp.setStopLocationFromMap(_dragLatLng!, _editingStopIndex);
    if (!mounted) return;
    setState(() {
      _step = _BookingStep.confirm;
      _editingStopIndex = -1;
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _fitCameraToRoute(mp);
    });
  }

  /// Animates the camera to fit all confirmed route points (pickup, stops,
  /// dropoff) with padding that accounts for the bottom sheet overlay.
  void _fitCameraToRoute(MapProvider mp) {
    final pickup = mp.pickupLocation;
    final dropoff = mp.dropoffLocation;
    if (pickup == null || dropoff == null) return;

    // Collect all route coordinates
    final List<LatLng> points = [
      pickup.coordinates,
      dropoff.coordinates,
      ...mp.stops
          .map((s) => (s['location'] as LocationModel?)?.coordinates)
          .whereType<LatLng>(),
    ];

    double minLat = points.map((p) => p.latitude).reduce(min);
    double maxLat = points.map((p) => p.latitude).reduce(max);
    double minLng = points.map((p) => p.longitude).reduce(min);
    double maxLng = points.map((p) => p.longitude).reduce(max);

    // Ensure a minimum span so very close points still zoom out a little
    const double minSpan = 0.004;
    if ((maxLat - minLat) < minSpan) {
      minLat -= minSpan / 2;
      maxLat += minSpan / 2;
    }
    if ((maxLng - minLng) < minSpan) {
      minLng -= minSpan / 2;
      maxLng += minSpan / 2;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // Use generous padding; the confirm bottom sheet is ~300 px tall so
    // we push the viewport up with extra bottom padding.
    mp.animateToLatLngBounds(bounds, 100);
  }

  void _removeCurrentStop() {
    final mp = Provider.of<MapProvider>(context, listen: false);
    mp.removeStop(_editingStopIndex);
    setState(() {
      _step = _BookingStep.confirm;
      _editingStopIndex = -1;
    });
  }

  Future<void> _editLocation(_BookingStep toStep, {int stopIndex = -1}) async {
    final mp = Provider.of<MapProvider>(context, listen: false);
    LatLng? targetLatLng;
    String targetAddr = '';
    if (toStep == _BookingStep.pickup) {
      targetLatLng = mp.pickupLocation?.coordinates;
      targetAddr = mp.pickupLocation?.address ?? '';
    } else if (toStep == _BookingStep.dropoff) {
      targetLatLng = mp.dropoffLocation?.coordinates;
      targetAddr = mp.dropoffLocation?.address ?? '';
    } else if (toStep == _BookingStep.stop && stopIndex >= 0) {
      final stop = mp.stops[stopIndex];
      targetLatLng = (stop['location'] as LocationModel?)?.coordinates;
      targetAddr = stop['address'] as String? ?? '';
    }
    setState(() {
      _step = toStep;
      _editingStopIndex = stopIndex;
      _dragAddress = targetAddr;
      _dragLatLng = targetLatLng;
    });
    if (targetLatLng != null) await mp.animateCameraTo(targetLatLng);
  }

  void _useMyLocation() {
    final mp = Provider.of<MapProvider>(context, listen: false);
    mp.moveToCurrentLocation().then((_) {
      if (!mounted) return;
      setState(() => _dragLatLng = mp.currentUserLocation);
    });
  }

  void _goBack() {
    final mp = Provider.of<MapProvider>(context, listen: false);
    switch (_step) {
      case _BookingStep.pickup:
        // On pickup step, back = leaving the screen entirely
        _showExitDialog();
        break;
      case _BookingStep.dropoff:
        setState(() {
          _step = _BookingStep.pickup;
          _dragAddress = mp.pickupLocation?.address ?? '';
          _dragLatLng = mp.pickupLocation?.coordinates;
        });
        if (_dragLatLng != null) mp.animateCameraTo(_dragLatLng!);
        break;
      case _BookingStep.stop:
        _removeCurrentStop();
        break;
      case _BookingStep.confirm:
        setState(() {
          _step = _BookingStep.dropoff;
          _dragAddress = mp.dropoffLocation?.address ?? '';
          _dragLatLng = mp.dropoffLocation?.coordinates;
        });
        if (_dragLatLng != null) mp.animateCameraTo(_dragLatLng!);
        break;
    }
  }

  /// Shows the exit dialog when the user tries to leave the booking screen.
  /// Offers three choices:
  ///  • Clear Map  — wipes all pins/route, then goes home (fresh start)
  ///  • Keep       — keeps pins so they reappear next time, then goes home
  ///  • Stay       — dismisses the dialog, stays on the screen
  Future<void> _showExitDialog() async {
    final mp = Provider.of<MapProvider>(context, listen: false);
    final bool hasAnyData =
        mp.pickupLocation != null ||
        mp.dropoffLocation != null ||
        mp.stops.isNotEmpty;

    // If nothing has been set yet, just pop immediately — no need for dialog
    if (!hasAnyData) {
      Navigator.pop(context);
      return;
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black38,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      const Row(
                        children: [
                          Icon(
                            Icons.map_outlined,
                            color: Color(0xFFFFC107),
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Leave Booking?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Subtitle
                      const Text(
                        'What would you like to do with your selected locations?',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Clear & Exit
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(ctx).pop('clear'),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Clear Map & Exit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC107),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Keep & Exit
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(ctx).pop('keep'),
                          icon: const Icon(
                            Icons.bookmark_outline,
                            size: 18,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            'Keep Locations & Exit',
                            style: TextStyle(color: Colors.white70),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Colors.white24,
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Continue booking
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop('stay'),
                          child: const Text(
                            'Continue Booking',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );

    if (!mounted) return;
    if (result == 'clear') {
      mp.resetTripData();
      Navigator.pop(context);
    } else if (result == 'keep') {
      Navigator.pop(context);
    }
    // 'stay' or dismissed dialog → do nothing
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bool showPin = _step != _BookingStep.confirm;

    return PopScope(
      // Prevent the system back gesture/button from popping immediately;
      // route it through _goBack() so we can show the exit dialog.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // 1. Full-screen map
            Positioned.fill(
              child: MapWidget(
                allowMapTaps: false,
                isDragPinMode: showPin,
                onCameraMove: showPin ? _onCameraMove : null,
                onCameraIdle: showPin ? _onCameraIdle : null,
              ),
            ),

            // 2. Floating center pin (hidden on confirm step)
            if (showPin) _buildFloatingPin(),

            // 3. Top bar
            Positioned(
              top: mq.padding.top + 8,
              left: 12,
              right: 12,
              child: _buildTopBar(),
            ),

            // 4. My Location FAB
            if (showPin)
              Positioned(
                right: 14,
                bottom: 240,
                child: _MyLocationFab(onTap: _useMyLocation),
              ),

            // 5. Step-based bottom sheet
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomSheet(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Floating pin ───────────────────────────────────────────────────
  // The pin tip (bottom of Icons.location_pin) must point to the exact
  // camera center coordinate, not the icon's bounding-box center.
  // We use a Stack so:
  //  • The shadow stays AT the camera center (acts as the ground dot)
  //  • The pin icon is translated UP by iconSize/2, so its BOTTOM TIP
  //    lands exactly at the camera center
  Widget _buildFloatingPin() {
    const double baseSize = 52.0; // icon size when idle
    const double dragSize = 52.0; // keep same size; only glow grows
    const double dragLift =
        18.0; // how far the tip rises above center when dragging

    return Center(
      child: IgnorePointer(
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // ── Ground shadow (stays at camera center) ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isDragging ? 20 : 8,
              height: _isDragging ? 7 : 3,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(_isDragging ? 0.32 : 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
            ),

            // ── Pin icon (tip anchored at camera center) ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              // Shift UP by iconSize/2 so the tip (bottom of icon) is at
              // camera center. Add dragLift when dragging so tip lifts above.
              transform: Matrix4.translationValues(
                0,
                _isDragging
                    ? -(baseSize / 2 +
                        dragLift) // tip lifts dragLift above center
                    : -(baseSize / 2), // tip exactly at center
                0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: _pinColor.withOpacity(_isDragging ? 0.6 : 0.28),
                      blurRadius: _isDragging ? 24 : 8,
                      spreadRadius: _isDragging ? 6 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.location_pin,
                  color: _pinColor,
                  size: _isDragging ? dragSize : baseSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _goBack,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Color(0xFFFFC107),
                size: 18,
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                _stepLabel,
                key: ValueKey(_step),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          // Step breadcrumb dots
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepDot(
                  active: _step == _BookingStep.pickup,
                  done: _step.index > 0,
                  color: const Color(0xFF4CAF50),
                ),
                const SizedBox(width: 4),
                _StepDot(
                  active: _step == _BookingStep.dropoff,
                  done: _step.index > 1,
                  color: const Color(0xFFE53935),
                ),
                const SizedBox(width: 4),
                _StepDot(
                  active: _step == _BookingStep.confirm,
                  done: false,
                  color: const Color(0xFFFFC107),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom sheet dispatcher ────────────────────────────────────────
  Widget _buildBottomSheet() {
    late Widget content;
    switch (_step) {
      case _BookingStep.pickup:
        content = _buildPickupSheet();
        break;
      case _BookingStep.dropoff:
        content = _buildDropoffSheet();
        break;
      case _BookingStep.stop:
        content = _buildStopSheet();
        break;
      case _BookingStep.confirm:
        content = _buildConfirmSheet();
        break;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder:
          (child, anim) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
      child: content,
    );
  }

  // ── Pickup sheet ───────────────────────────────────────────────────
  Widget _buildPickupSheet() {
    return _SheetWrapper(
      key: const ValueKey('pickup'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          _AddressRow(
            dot: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            address:
                _isDragging
                    ? 'Moving...'
                    : (_dragAddress.isEmpty
                        ? 'Drag the map to set pickup'
                        : _dragAddress),
            isLoading: _isDragging,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _useMyLocation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.near_me, color: Color(0xFFFFC107), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Use current location',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: 'CONFIRM PICKUP',
            enabled:
                _dragAddress.isNotEmpty &&
                _dragAddress != 'Moving...' &&
                _dragLatLng != null,
            onPressed: _confirmPickup,
          ),
        ],
      ),
    );
  }

  // ── Dropoff sheet ──────────────────────────────────────────────────
  Widget _buildDropoffSheet() {
    return Consumer<MapProvider>(
      builder:
          (context, mp, _) => _SheetWrapper(
            key: const ValueKey('dropoff'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                _ConfirmedChip(
                  icon: Icons.circle,
                  color: const Color(0xFF4CAF50),
                  address: mp.pickupLocation?.address ?? 'Pickup',
                  onEdit: () => _editLocation(_BookingStep.pickup),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 6, top: 5, bottom: 5),
                  width: 2,
                  height: 18,
                  color: Colors.white12,
                ),
                _AddressRow(
                  dot: const Icon(
                    Icons.location_on,
                    color: Color(0xFFE53935),
                    size: 20,
                  ),
                  address:
                      _isDragging
                          ? 'Moving...'
                          : (_dragAddress.isEmpty
                              ? 'Drag to set destination'
                              : _dragAddress),
                  isLoading: _isDragging,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _addStop,
                  icon: const Icon(
                    Icons.add_circle_outline,
                    size: 16,
                    color: Color(0xFFFFC107),
                  ),
                  label: const Text(
                    'Add a stop',
                    style: TextStyle(color: Color(0xFFFFC107), fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(height: 10),
                _PrimaryButton(
                  label: 'CONFIRM DESTINATION',
                  enabled:
                      _dragAddress.isNotEmpty &&
                      _dragAddress != 'Moving...' &&
                      _dragLatLng != null,
                  onPressed: _confirmDropoff,
                ),
              ],
            ),
          ),
    );
  }

  // ── Stop sheet ─────────────────────────────────────────────────────
  Widget _buildStopSheet() {
    return _SheetWrapper(
      key: ValueKey('stop_$_editingStopIndex'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          _AddressRow(
            dot: CircleAvatar(
              radius: 10,
              backgroundColor: const Color(0xFFFF9800),
              child: Text(
                '${_editingStopIndex + 1}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            address:
                _isDragging
                    ? 'Moving...'
                    : (_dragAddress.isEmpty
                        ? 'Drag map to set stop location'
                        : _dragAddress),
            isLoading: _isDragging,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PrimaryButton(
                  label: 'CONFIRM STOP',
                  enabled:
                      _dragAddress.isNotEmpty &&
                      _dragAddress != 'Moving...' &&
                      _dragLatLng != null,
                  onPressed: _confirmStop,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _removeCurrentStop,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'REMOVE',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Confirm sheet ──────────────────────────────────────────────────
  Widget _buildConfirmSheet() {
    return Consumer<MapProvider>(
      builder: (context, mp, _) {
        final hasLocs = mp.pickupLocation != null && mp.dropoffLocation != null;
        final base = mp.estimatedFare;
        final extra = mp.calculateAdditionalCharges(
          _stopCharge,
          _waitingChargePerMinute,
        );
        final selCar = _carTypes.firstWhere(
          (c) => c['id'] == _selectedCarType,
          orElse: () => _carTypes[0],
        );
        final total = (base + extra) * (selCar['price'] as double);

        return _SheetWrapper(
          key: const ValueKey('confirm'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),

              // Route summary card
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF242424),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    _ConfirmedChip(
                      icon: Icons.circle,
                      color: const Color(0xFF4CAF50),
                      address: mp.pickupLocation?.address ?? 'Pickup',
                      onEdit: () => _editLocation(_BookingStep.pickup),
                    ),
                    if (mp.stops.isNotEmpty)
                      ...List.generate(mp.stops.length, (i) {
                        final stop = mp.stops[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(
                                left: 6,
                                top: 6,
                                bottom: 4,
                              ),
                              width: 2,
                              height: 12,
                              color: Colors.white12,
                            ),
                            _ConfirmedChip(
                              icon: Icons.circle,
                              color: const Color(0xFFFF9800),
                              address:
                                  stop['address'] as String? ?? 'Stop ${i + 1}',
                              label: 'Stop ${i + 1}',
                              onEdit:
                                  () => _editLocation(
                                    _BookingStep.stop,
                                    stopIndex: i,
                                  ),
                            ),
                          ],
                        );
                      }),
                    Container(
                      margin: const EdgeInsets.only(left: 6, top: 8, bottom: 4),
                      width: 2,
                      height: 14,
                      color: Colors.white12,
                    ),
                    _ConfirmedChip(
                      icon: Icons.location_on,
                      color: const Color(0xFFE53935),
                      address: mp.dropoffLocation?.address ?? 'Destination',
                      onEdit: () => _editLocation(_BookingStep.dropoff),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _addStop,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          size: 13,
                          color: Color(0xFFFFC107),
                        ),
                        label: const Text(
                          'Add stop',
                          style: TextStyle(
                            color: Color(0xFFFFC107),
                            fontSize: 12,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Vehicle class
              const Text(
                'Select Ride Class',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _carTypes.length,
                  itemBuilder: (ctx, i) {
                    final car = _carTypes[i];
                    final isSelected = car['id'] == _selectedCarType;
                    final farePreview =
                        (base + extra) * (car['price'] as double);
                    return GestureDetector(
                      onTap:
                          () => setState(
                            () => _selectedCarType = car['id'] as String,
                          ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 110,
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? const Color(0xFFFFC107).withOpacity(0.12)
                                  : const Color(0xFF242424),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                isSelected
                                    ? const Color(0xFFFFC107)
                                    : Colors.white12,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              car['icon'] as IconData,
                              size: 26,
                              color:
                                  isSelected
                                      ? const Color(0xFFFFC107)
                                      : Colors.grey,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              car['name'] as String,
                              style: TextStyle(
                                color:
                                    isSelected
                                        ? Colors.white
                                        : Colors.grey.shade400,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              hasLocs
                                  ? '\$${farePreview.toStringAsFixed(2)}'
                                  : 'x${car["price"]}',
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    isSelected
                                        ? const Color(0xFFFFC107)
                                        : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Fare summary
              if (hasLocs)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${mp.estimatedDistance.toStringAsFixed(1)} km  •  ${mp.estimatedDuration} min',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const Text(
                            'Cash on Arrival',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFC107),
                        ),
                      ),
                    ],
                  ),
                ),

              // CTA button
              _PrimaryButton(
                label:
                    hasLocs ? 'REQUEST PRO RIDE' : 'SET PICKUP & DESTINATION',
                enabled: hasLocs,
                onPressed: () => _requestRide(context),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Request ride ───────────────────────────────────────────────────
  Future<void> _requestRide(BuildContext context) async {
    final networkProvider = Provider.of<NetworkConnectivityProvider>(
      context,
      listen: false,
    );
    if (!networkProvider.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No internet connection. Please connect to internet to request a ride.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black38,
      builder:
          (_) => Dialog(
            backgroundColor: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFFC107)),
                      SizedBox(height: 18),
                      Text(
                        'Creating trip...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
    try {
      final mp = Provider.of<MapProvider>(context, listen: false);
      final fp = Provider.of<FirestoreProvider>(context, listen: false);
      final selCar = _carTypes.firstWhere(
        (c) => c['id'] == _selectedCarType,
        orElse: () => _carTypes[0],
      );
      final base = mp.estimatedFare;
      final extra = mp.calculateAdditionalCharges(
        _stopCharge,
        _waitingChargePerMinute,
      );
      final fare = (base + extra) * (selCar['price'] as double);

      final tripData = {
        'carType': _selectedCarType,
        'fare': fare,
        'distance': mp.estimatedDistance,
        'duration': mp.estimatedDuration,
        'paymentMethod': 'cash',
        'pickup': {
          'address': mp.pickupLocation?.address,
          'placeId': mp.pickupLocation?.placeId,
          'name': mp.pickupLocation?.name,
          'latitude': mp.pickupLocation?.coordinates.latitude,
          'longitude': mp.pickupLocation?.coordinates.longitude,
        },
        'dropoff': {
          'address': mp.dropoffLocation?.address,
          'placeId': mp.dropoffLocation?.placeId,
          'name': mp.dropoffLocation?.name,
          'latitude': mp.dropoffLocation?.coordinates.latitude,
          'longitude': mp.dropoffLocation?.coordinates.longitude,
        },
        'stops':
            mp.stops
                .map(
                  (s) => {
                    'address': s['address'],
                    'placeId': (s['location'] as LocationModel?)?.placeId,
                    'name': (s['location'] as LocationModel?)?.name,
                    'latitude':
                        (s['location'] as LocationModel?)?.coordinates.latitude,
                    'longitude':
                        (s['location'] as LocationModel?)
                            ?.coordinates
                            .longitude,
                    'waitingTime': s['waitingTime'] ?? 0,
                  },
                )
                .toList(),
        'searchStartedAt': DateTime.now().millisecondsSinceEpoch,
      };

      final tripRef = await fp.createTrip(tripData);
      mp.resetTripData();

      if (!context.mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TripTrackingScreen(tripId: tripRef.id),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showDialog(
        context: context,
        barrierColor: Colors.black38,
        builder:
            (_) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 28),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 22,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Trip Error',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to create trip: $e',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: Color(0xFFFFC107),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// Reusable sub-widgets
// ══════════════════════════════════════════════════════════════════════

class _SheetWrapper extends StatelessWidget {
  final Widget child;
  const _SheetWrapper({required super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade700,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _AddressRow extends StatelessWidget {
  final Widget dot;
  final String address;
  final bool isLoading;

  const _AddressRow({
    required this.dot,
    required this.address,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        dot,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: TextStyle(
              color: isLoading ? Colors.grey.shade500 : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFFC107),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConfirmedChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String address;
  final VoidCallback onEdit;
  final String? label;

  const _ConfirmedChip({
    required this.icon,
    required this.color,
    required this.address,
    required this.onEdit,
    this.label,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Text(
                label!,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Text(
              address,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      GestureDetector(
        onTap: onEdit,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            Icons.edit_location_alt_outlined,
            size: 16,
            color: Colors.white38,
          ),
        ),
      ),
    ],
  );
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFFC107),
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        disabledBackgroundColor: Colors.grey.shade800,
        disabledForegroundColor: Colors.grey.shade600,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    ),
  );
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final Color color;

  const _StepDot({
    required this.active,
    required this.done,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    width: active ? 18 : 8,
    height: 8,
    decoration: BoxDecoration(
      color:
          done
              ? const Color(0xFF4CAF50)
              : active
              ? color
              : Colors.white24,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class _MyLocationFab extends StatelessWidget {
  final VoidCallback onTap;
  const _MyLocationFab({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    elevation: 4,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.all(10),
        child: Icon(Icons.my_location, color: Color(0xFF1A1A1A), size: 20),
      ),
    ),
  );
}
