import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../providers/firestore_provider.dart';
import '../providers/map_provider.dart';
import '../widgets/map_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import '../services/trip_persistence_service.dart';
import '../widgets/network_connectivity_widgets.dart';
import '../main.dart' show navigatorKey;
import 'home_screen_pro.dart';

// ── Design constants (matches HomeScreenPro / TripRequestScreenPro) ──
const _kBg = Color(0xFF121212);
const _kSurface = Color(0xFF1E1E1E);
const _kSurface2 = Color(0xFF2A2A2A);
const _kGold = Color(0xFFFFC107);
const _kGoldLight = Color(0xFFFFD54F);
const _kGreen = Color(0xFF4CAF50);
const _kRed = Color(0xFFE53935);
const _kOrange = Color(0xFFFF9800);

class TripTrackingScreen extends StatefulWidget {
  final String tripId;

  const TripTrackingScreen({Key? key, required this.tripId}) : super(key: key);

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen>
    with TickerProviderStateMixin {
  StreamSubscription<DocumentSnapshot>? _tripSubscription;
  Map<String, dynamic>? _tripData;
  String _tripStatus = 'searching';

  Timer? _progressUpdateTimer;
  Timer? _fallbackPollTimer;
  bool _isStreamOnline = true;
  double _progressValue = 0.0;

  static const int DRIVER_TIMEOUT_SECONDS = 60;

  Timer? _searchingTimer;
  int _searchingCount = 0;

  // ── Animation controllers ──────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late AnimationController _entranceController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    // Entrance animation
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();

    // If the screen opens in 'searching' state, start the search immediately.
    // This avoids calling _startPeriodicDriverSearch() inside build().
    if (_tripStatus == 'searching') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchingTimer == null) _startPeriodicDriverSearch();
      });
    }

    // Pulse for searching / notified states
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);

    // Shimmer for gold text
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();

    _saveTripToPersistence();
    _setupTripListener();
  }

  void _setupTripListener() {
    _tripSubscription = FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            // Stream is active — cancel fallback poll if it was running
            _fallbackPollTimer?.cancel();
            _fallbackPollTimer = null;
            _isStreamOnline = true;

            if (!snapshot.exists) {
              return;
            }

            final tripData = snapshot.data();
            if (tripData == null) return;

            final status = tripData['status'] as String?;

            // Keep local data updated on every snapshot
            setState(() {
              _tripData = tripData;
            });

            // If status transitioned, route through single state machine
            if (status != null && status != _tripStatus) {
              _transitionToStatus(status, tripData);
            }
          },
          onError: (error) {
            print('Trip stream connection error: $error');
            if (_isStreamOnline) {
              _isStreamOnline = false;
              _startFallbackPoll();
            }
          },
        );
  }

  void _startFallbackPoll() {
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('trips')
            .doc(widget.tripId)
            .get(const GetOptions(source: Source.server));

        if (snapshot.exists && snapshot.data() != null) {
          final tripData = snapshot.data()!;
          final status = tripData['status'] as String?;

          setState(() {
            _tripData = tripData;
          });

          if (status != null && status != _tripStatus) {
            _transitionToStatus(status, tripData);
          }
        }
      } catch (e) {
        print('Error in fallback poll: $e');
      }
    });
  }

  void _transitionToStatus(String newStatus, Map<String, dynamic> tripData) {
    if (_tripStatus == newStatus && _tripData != null) return;

    // Update persistence with new status
    _updatePersistenceStatus(newStatus);

    setState(() {
      _tripStatus = newStatus;
      _tripData = tripData;
    });

    switch (newStatus) {
      case 'searching':
        // Start search from state transition, never from inside build()
        if (_searchingTimer == null) _startPeriodicDriverSearch();
        break;
      case 'driver_notified':
        _handleDriverNotified(tripData);
        break;
      case 'driver_accepted':
        _cancelAllTimers();
        _handleDriverAccepted(tripData);
        break;
      case 'driver_arrived':
        _cancelAllTimers();
        _handleDriverArrived(tripData);
        break;
      case 'in_progress':
        _cancelAllTimers();
        _handleTripInProgress(tripData);
        break;
      case 'completed':
        _cancelAllTimers();
        _handleTripCompleted(tripData);
        break;
      case 'cancelled':
        _cancelAllTimers();
        _handleTripCancelled(tripData);
        break;
      case 'no_drivers_available':
        _cancelAllTimers();
        _handleNoDriversAvailable();
        break;
    }
  }

  void _cancelAllTimers() {
    _progressUpdateTimer?.cancel();
    _progressUpdateTimer = null;
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
    _searchingTimer?.cancel();
    _searchingTimer = null;
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _tripSubscription?.cancel();
    _pulseController.dispose();
    _shimmerController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // Save current trip to persistence
  void _saveTripToPersistence() async {
    try {
      final firestoreProvider = Provider.of<FirestoreProvider>(
        context,
        listen: false,
      );
      final currentUserId = firestoreProvider.currentUserId;

      if (currentUserId != null) {
        await TripPersistenceService.saveActiveTrip(
          tripId: widget.tripId,
          userId: currentUserId,
          tripData:
              _tripData ??
              {
                'status': _tripStatus,
                'createdAt': FieldValue.serverTimestamp(),
              },
        );
        print('Trip saved to persistence: ${widget.tripId}');
      }
    } catch (e) {
      print('Error saving trip to persistence: $e');
    }
  }

  // Clear trip from persistence
  void _clearTripFromPersistence() async {
    try {
      final firestoreProvider = Provider.of<FirestoreProvider>(
        context,
        listen: false,
      );
      final currentUserId = firestoreProvider.currentUserId;

      if (currentUserId != null) {
        await TripPersistenceService.clearActiveTripForUser(currentUserId);
        print('Trip cleared from persistence: ${widget.tripId}');
      }
    } catch (e) {
      print('Error clearing trip from persistence: $e');
    }
  }

  // Update trip status in persistence
  void _updatePersistenceStatus(String status) async {
    try {
      await TripPersistenceService.updateTripStatus(status);
      print('Updated persistence status: $status');
    } catch (e) {
      print('Error updating persistence status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tripStatus == 'completed') {
      return _buildCompletedFullScreen();
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Map fills the entire screen — never gets a zero-height constraint
          Positioned.fill(
            child: MapWidget(
              showDriverLocation:
                  _tripStatus == 'driver_accepted' ||
                  _tripStatus == 'driver_arrived' ||
                  _tripStatus == 'in_progress',
              tripId: widget.tripId,
            ),
          ),

          // Premium top bar floats over the map
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _buildTopBar(),
          ),

          // Status panel — fully isolated StatefulWidget so its rebuilds
          // never re-run the parent build() and cannot affect the map.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _TripStatusSheet(
              tripStatus: _tripStatus,
              tripData: _tripData,
              progressValue: _progressValue,
              onCancelTrip: _showCancelTripDialog,
              onCallDriver: _callDriver,
              onGoHome: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ),
        ],
      ),
    );
  }

  // ── Premium top bar ────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _shouldShowCancelButton() ? _showCancelTripDialog : null,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    _shouldShowCancelButton()
                        ? Icons.close_rounded
                        : Icons.local_taxi,
                    color: _kGold,
                    size: 20,
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _getTitleForStatus(),
                    key: ValueKey(_tripStatus),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                // RepaintBoundary isolates the pulsing dot animation so it
                // does NOT trigger a full parent build() on every tick.
                child: RepaintBoundary(child: _buildStatusIndicatorDot()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicatorDot() {
    final color = _getColorForStatus();
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final shouldPulse =
            _tripStatus == 'searching' ||
            _tripStatus == 'driver_notified' ||
            _tripStatus == 'in_progress';
        final scale = shouldPulse ? 1.0 + (_pulseController.value * 0.35) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getTitleForStatus() {
    switch (_tripStatus) {
      case 'searching':
        return 'Finding Drivers';
      case 'driver_notified':
        return 'Driver Requested';
      case 'driver_accepted':
        return 'Driver on the Way';
      case 'driver_arrived':
        return 'Driver Has Arrived';
      case 'in_progress':
        return 'Trip in Progress';
      case 'completed':
        return 'Trip Completed';
      case 'cancelled':
        return 'Trip Cancelled';
      case 'no_drivers_available':
        return 'No Drivers Available';
      default:
        return 'Trip Status';
    }
  }

  Color _getColorForStatus() {
    switch (_tripStatus) {
      case 'searching':
      case 'driver_notified':
        return _kGold;
      case 'driver_accepted':
      case 'driver_arrived':
      case 'in_progress':
        return _kGreen;
      case 'completed':
        return _kGold;
      case 'cancelled':
      case 'no_drivers_available':
        return _kRed;
      default:
        return _kGold;
    }
  }

  bool _shouldShowCancelButton() {
    // Only show cancel button for certain statuses
    return _tripStatus == 'searching' ||
        _tripStatus == 'driver_notified' ||
        _tripStatus == 'driver_accepted';
  }

  Widget _buildStatusPanel() {
    if (_tripStatus == 'searching') {
      return _buildSearchingPanel();
    }

    switch (_tripStatus) {
      case 'driver_notified':
        return _buildDriverNotifiedPanel();
      case 'driver_accepted':
        return _buildDriverAcceptedPanel();
      case 'driver_arrived':
        return _buildDriverArrivedPanel();
      case 'in_progress':
        return _buildInProgressPanel();
      case 'cancelled':
        return _buildCancelledPanel();
      case 'no_drivers_available':
        return _buildNoDriversPanel();
      default:
        return _buildSheetWrapper(
          child: _buildLoadingContent('Loading trip information...'),
        );
    }
  }

  void _showCancelTripDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: _kSurface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.cancel_outlined, color: _kRed, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Cancel Trip?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Are you sure you want to cancel your trip request?',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _cancelTrip();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kRed,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text(
                            'Yes, Cancel',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text(
                            'Keep Trip',
                            style: TextStyle(color: Colors.white70),
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

  void _cancelTrip() async {
    final networkProvider = Provider.of<NetworkConnectivityProvider>(
      context,
      listen: false,
    );
    if (!networkProvider.isConnected) {
      _showPremiumSnackBar(
        'Cannot cancel trip while offline. Please check your connection.',
        _kRed,
      );
      return;
    }

    // Show confirmation dialog
    final shouldCancel = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: _kSurface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cancel Trip?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Are you sure you want to cancel this trip? Cancellation may incur fees.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'No',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kRed,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Yes, Cancel',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );

    if (shouldCancel == true) {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder:
            (_) => Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: _kSurface.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            color: _kGold,
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Cancelling trip...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
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
        await FirebaseFirestore.instance
            .collection('trips')
            .doc(widget.tripId)
            .update({
              'status': 'cancelled',
              'cancelledBy': 'user',
              'cancellationTime': FieldValue.serverTimestamp(),
              'cancellationReason': 'user_cancelled',
            });
        Navigator.of(context).pop();
        _showPremiumSnackBar('Trip cancelled successfully', _kGold);
        if (mounted) {
          Provider.of<MapProvider>(context, listen: false).resetTripData();
        }
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (e) {
        Navigator.of(context).pop();
        _showPremiumSnackBar('Error cancelling trip: $e', _kRed);
      }
    }
  }

  // Driver has been notified but hasn't accepted yet
  void _handleDriverNotified(Map<String, dynamic> tripData) {
    setState(() {
      _progressValue = 0.0;
    });

    _startCountdownTimer(tripData);
  }

  // Single consolidated countdown and progress timer
  void _startCountdownTimer(Map<String, dynamic> tripData) {
    _progressUpdateTimer?.cancel();
    _progressUpdateTimer = null;

    final notificationTime =
        tripData['notificationTime'] != null
            ? (tripData['notificationTime'] as Timestamp).toDate()
            : DateTime.now();

    const totalTimeout = DRIVER_TIMEOUT_SECONDS;

    _progressUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // If status transitioned away from driver_notified, stop countdown
      if (_tripStatus != 'driver_notified') {
        timer.cancel();
        _progressUpdateTimer = null;
        return;
      }

      final elapsed =
          DateTime.now().difference(notificationTime).inMilliseconds / 1000;
      final progress = elapsed / totalTimeout;

      setState(() {
        _progressValue = progress > 1 ? 1.0 : progress;
      });

      if (progress >= 1.0) {
        timer.cancel();
        _progressUpdateTimer = null;
        _handleDriverTimeout();
      }
    });
  }

  void _handleDriverAccepted(Map<String, dynamic> tripData) {
    _cancelAllTimers();

    final driverId = tripData['driverId'] ?? tripData['claimedByDriverId'];
    if (driverId != null) {
      _loadDriverDetails(driverId.toString());
    }

    setState(() {
      _progressValue = 1.0;
    });

    _playNotificationSound();
    _showDriverDetailsDialog(tripData);
  }

  // Driver has arrived at pickup location
  void _handleDriverArrived(Map<String, dynamic> tripData) {
    _showPremiumSnackBar('Your driver has arrived! 🚗', _kGreen);
    _playArrivalSound();
  }

  // Trip is in progress
  void _handleTripInProgress(Map<String, dynamic> tripData) {
    _updateMapForInProgressTrip();
  }

  // Trip has been completed
  void _handleTripCompleted(Map<String, dynamic> tripData) {
    // Clear persistence immediately when trip completes
    _clearTripFromPersistence();
    print('Trip completed - persistence cleared immediately');
  }

  // No drivers available
  void _handleNoDriversAvailable() {
    // Clear persistence when no drivers available
    _clearTripFromPersistence();
    print('Persistence cleared - no drivers available');
    _showNoDriversDialog();
  }

  void _handleTripCancelled(Map<String, dynamic> tripData) {
    // Clear persistence immediately on cancellation
    _clearTripFromPersistence();
    print('Persistence cleared after trip cancellation');
  }

  void _handleDriverTimeout() async {
    if (!mounted || _tripStatus != 'driver_notified') return;

    try {
      await FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .update({
            'status': 'no_drivers_available',
            'noDriversAvailable': true,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error updating trip status on driver timeout: $e');
    }
  }

  void _loadDriverDetails(String driverId) {
    // Load driver details
  }

  void _playNotificationSound() {
    // Play notification sound
  }

  void _showDriverDetailsDialog(Map<String, dynamic> tripData) async {
    final driverId = tripData['driverId'];
    if (driverId == null) {
      _showPremiumSnackBar('Driver information not available', _kOrange);
      return;
    }

    // Fetch driver data SILENTLY — no full-screen black overlay that hides the map.
    // A brief snackbar informs the user while the data loads.
    _showPremiumSnackBar('Driver confirmed! Loading details...', _kGold);

    try {
      final driverDoc =
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(driverId)
              .get();

      if (!mounted) return;

      if (!driverDoc.exists) {
        _showPremiumSnackBar('Driver details not found', _kOrange);
        return;
      }

      final driverData = driverDoc.data()!;
      final carDetails = driverData['vehicleDetails'] ?? {};

      showDialog(
        context: context,
        builder:
            (ctx) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kSurface.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _kGold.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _kGold.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.directions_car,
                                color: _kGold,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Driver is on the way!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [_kGold, _kGoldLight],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kGold.withOpacity(0.3),
                                    blurRadius: 10,
                                  ),
                                ],
                                image:
                                    driverData['baseFaceImageUrl'] != null
                                        ? DecorationImage(
                                          image: NetworkImage(
                                            driverData['baseFaceImageUrl'],
                                          ),
                                          fit: BoxFit.cover,
                                        )
                                        : null,
                              ),
                              child:
                                  driverData['baseFaceImageUrl'] == null
                                      ? const Icon(
                                        Icons.person,
                                        color: Colors.black,
                                        size: 28,
                                      )
                                      : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    driverData['displayName'] ??
                                        driverData['name'] ??
                                        'Driver',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        color: _kGold,
                                        size: 15,
                                      ),
                                      Text(
                                        ' ${driverData['rating']?.toStringAsFixed(1) ?? '4.5'}',
                                        style: const TextStyle(
                                          color: _kGold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '  (${driverData['ratingCount'] ?? 0} trips)',
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (driverData['isOnline'] == true)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _kGreen.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _kGreen.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              color: _kGreen,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'Online',
                                            style: TextStyle(
                                              color: _kGreen,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (carDetails.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _kSurface2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Vehicle',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.directions_car,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${carDetails['color'] ?? 'N/A'}  ${carDetails['model'] ?? 'Car'}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.badge_outlined,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Plate: ${carDetails['plateNumber'] ?? 'N/A'}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _kGold.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kGold.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.schedule,
                                color: _kGold,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ETA: ${_formatEta(tripData['driverEta'])}',
                                style: const TextStyle(
                                  color: _kGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            if (driverData['phoneNumber'] != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _callDriver(driverData['phoneNumber']);
                                  },
                                  icon: const Icon(
                                    Icons.phone,
                                    size: 16,
                                    color: _kGold,
                                  ),
                                  label: const Text(
                                    'Call',
                                    style: TextStyle(color: _kGold),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: _kGold,
                                      width: 1.2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                  ),
                                ),
                              ),
                            if (driverData['phoneNumber'] != null)
                              const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kGold,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                ),
                                child: const Text(
                                  'OK',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      );
    } catch (e) {
      if (mounted)
        _showPremiumSnackBar('Error loading driver details: $e', _kRed);
    }
  }

  // Helper function to format ETA
  String _formatEta(dynamic etaMinutes) {
    if (etaMinutes == null) return 'calculating...';

    if (etaMinutes is int) {
      if (etaMinutes < 1) return 'less than a minute';
      if (etaMinutes == 1) return '1 minute';
      return '$etaMinutes minutes';
    }

    return 'calculating...';
  }

  void _callDriver(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      _showPremiumSnackBar('Driver phone number not available', _kOrange);
      return;
    }
    final Uri url = Uri.parse('tel:$phoneNumber');
    // launchUrl(url);
  }

  void _playArrivalSound() {
    // Play arrival sound
  }

  void _updateMapForInProgressTrip() {
    // Update map for in-progress trip
  }

  Future<void> _submitRating(double rating) async {
    await FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .update({
          'userRating': rating,
          'ratedAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
    // Refresh local state
    final updatedTrip =
        await FirebaseFirestore.instance
            .collection('trips')
            .doc(widget.tripId)
            .get();
    if (updatedTrip.exists && mounted) {
      setState(() {
        _tripData = updatedTrip.data()!;
      });
    }
  }

  String _formatDuration(dynamic duration) {
    if (duration == null) return 'N/A';

    if (duration is int) {
      final minutes = duration ~/ 60;
      final seconds = duration % 60;

      if (minutes <= 0) return '$seconds sec';
      if (seconds <= 0) return '$minutes min';
      return '$minutes min $seconds sec';
    }

    return 'N/A';
  }

  void _showNoDriversDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: _kSurface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            color: _kOrange,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'No Drivers Available',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'We couldn\'t find any available drivers in your area. Would you like to try again?',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            FirebaseFirestore.instance
                                .collection('trips')
                                .doc(widget.tripId)
                                .update({
                                  'status': 'searching',
                                  'searchStartedAt':
                                      FieldValue.serverTimestamp(),
                                  'noDriversAvailable': false,
                                });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text(
                            'TRY AGAIN',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst);
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text(
                            'CANCEL',
                            style: TextStyle(color: Colors.white70),
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

  Widget _buildSearchingPanel() {
    // NOTE: Do NOT call _startPeriodicDriverSearch() here.
    // Side-effects inside build() cause rebuild loops.
    // It is started from initState / _transitionToStatus instead.

    return _buildSheetWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 8),

          // Animated radar
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.5),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _kGold.withOpacity(
                            0.5 - (_pulseController.value * 0.45),
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.25),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _kGold.withOpacity(
                            0.4 - (_pulseController.value * 0.35),
                          ),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kGold, _kGoldLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _kGold.withOpacity(0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_taxi,
                      color: Colors.black,
                      size: 26,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _shimmerController,
            builder:
                (_, child) => ShaderMask(
                  shaderCallback:
                      (bounds) => LinearGradient(
                        colors: const [_kGold, _kGoldLight, _kGold],
                        stops: [
                          (_shimmerController.value - 0.3).clamp(0.0, 1.0),
                          _shimmerController.value,
                          (_shimmerController.value + 0.3).clamp(0.0, 1.0),
                        ],
                      ).createShader(bounds),
                  child: child,
                ),
            child: const Text(
              'Finding Your Driver',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchingCount > 3
                ? 'Taking a bit longer than usual...'
                : 'Scanning nearby drivers in your area',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildCancelOutlinedButton(),
        ],
      ),
    );
  }

  // Add this method to start periodic driver search
  void _startPeriodicDriverSearch() {
    _searchingCount = 0;

    // Cancel any existing timer
    _searchingTimer?.cancel();

    // First immediate search
    _triggerDriverSearch();

    // Then set up periodic search every 10 seconds
    _searchingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || _tripStatus != 'searching') {
        timer.cancel();
        _searchingTimer = null;
        return;
      }

      _searchingCount++;
      _triggerDriverSearch();

      // If we've been searching for a long time (e.g., 2 minutes),
      // consider showing a timeout message or handling differently
      if (_searchingCount > 12) {
        // 12 x 10 seconds = 2 minutes
        _checkForSearchTimeout();
      }
    });
  }

  // Add this method to trigger the cloud function search
  Future<void> _triggerDriverSearch() async {
    try {
      // Trigger the cloud function by updating the trip document with a fresh timestamp
      await FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .update({
            'searchRefreshedAt': FieldValue.serverTimestamp(),
            'searchAttempts': FieldValue.increment(1),
          });

      print('Triggered driver search (attempt $_searchingCount)');
    } catch (e) {
      print('Error triggering driver search: $e');
    }
  }

  // Add method to handle search timeout
  void _checkForSearchTimeout() async {
    // If we've been searching for too long with no results,
    // update to no_drivers_available status
    if (_tripStatus == 'searching') {
      try {
        await FirebaseFirestore.instance
            .collection('trips')
            .doc(widget.tripId)
            .update({
              'status': 'no_drivers_available',
              'noDriversAvailable': true,
              'searchEndedAt': FieldValue.serverTimestamp(),
            });
      } catch (e) {
        print('Error updating trip status to no_drivers_available: $e');
      }
    }
  }

  Widget _buildDriverNotifiedPanel() {
    return _buildSheetWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: CircularProgressIndicator(
                  value: _progressValue,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(_kGold),
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _kSurface2,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: _kGold.withOpacity(0.15), blurRadius: 12),
                  ],
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 30,
                  color: _kGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Awaiting Driver Confirmation',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your request has been sent. Waiting for a driver to accept...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildCancelOutlinedButton(),
        ],
      ),
    );
  }

  Widget _buildDriverAcceptedPanel() {
    final driverInfo = _tripData?['driverInfo'] ?? {};
    final driverEta = _tripData?['driverEta'];

    return _buildSheetWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: _kGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driver on the Way!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Your ride is confirmed',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _kGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGold.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Text(
                      _formatEta(driverEta),
                      style: const TextStyle(
                        color: _kGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Text(
                      'ETA',
                      style: TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDriverCard(driverInfo),
          const SizedBox(height: 16),
          _buildCancelOutlinedButton(),
        ],
      ),
    );
  }

  Widget _buildDriverArrivedPanel() {
    final driverInfo = _tripData?['driverInfo'] ?? {};
    final carDetails = driverInfo['carDetails'] ?? {};

    return _buildSheetWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_kGreen.withOpacity(0.2), _kGreen.withOpacity(0.08)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kGreen.withOpacity(0.4)),
            ),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder:
                      (_, child) => Transform.scale(
                        scale: 1.0 + (_pulseController.value * 0.08),
                        child: child,
                      ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: _kGreen,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your Driver Has Arrived!',
                  style: TextStyle(
                    color: _kGreen,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Please head to your pickup point',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildDriverCard(
            driverInfo,
            subtitle:
                carDetails.isNotEmpty
                    ? '${carDetails['color'] ?? ''} ${carDetails['model'] ?? 'Car'} · ${carDetails['plateNumber'] ?? ''}'
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _buildInProgressPanel() {
    final driverInfo = _tripData?['driverInfo'] ?? {};
    final dropoffAddress = _tripData?['dropoff']?['address'] ?? 'Destination';
    final distanceRemaining =
        _tripData?['distanceRemaining'] ?? _tripData?['distance'] ?? 0.0;
    final timeRemaining =
        _tripData?['timeRemaining'] ?? _tripData?['duration'] ?? 0;
    final fare = (_tripData?['fare'] ?? 0.0);

    return _buildSheetWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 4),
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder:
                    (_, child) => Transform.scale(
                      scale: 1.0 + (_pulseController.value * 0.12),
                      child: child,
                    ),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kGold, _kGoldLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _kGold.withOpacity(0.35),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: Colors.black,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trip in Progress',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      dropoffAddress,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildPhoneIconButton(driverInfo['phoneNumber']),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TripStatTile(
                  icon: Icons.straighten,
                  label: 'Distance',
                  value: '${distanceRemaining.toStringAsFixed(1)} km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TripStatTile(
                  icon: Icons.schedule,
                  label: 'Time',
                  value: '$timeRemaining min',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TripStatTile(
                  icon: Icons.payments_outlined,
                  label: 'Fare',
                  value: '\$${fare.toStringAsFixed(2)}',
                  valueColor: _kGold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedFullScreen() {
    final fare = _tripData?['fare'] ?? 0.0;
    final distance = (_tripData?['distance'] ?? 0).toStringAsFixed(1);
    final duration = _formatDuration(
      _tripData?['actualDuration'] ?? _tripData?['duration'],
    );

    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          Expanded(
            flex: 55,
            child: MapWidget(
              showCompletedTrip: true,
              tripData: _tripData,
              tripId: widget.tripId,
            ),
          ),
          Expanded(
            flex: 45,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _shimmerController,
                      builder:
                          (_, child) => ShaderMask(
                            shaderCallback:
                                (b) => LinearGradient(
                                  colors: const [_kGold, _kGoldLight, _kGold],
                                  stops: [
                                    (_shimmerController.value - 0.3).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    _shimmerController.value,
                                    (_shimmerController.value + 0.3).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                  ],
                                ).createShader(b),
                            child: child,
                          ),
                      child: const Text(
                        '🎉 Trip Completed',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Fare card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _kSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kGold.withOpacity(0.25)),
                        boxShadow: [
                          BoxShadow(
                            color: _kGold.withOpacity(0.08),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Total Fare',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '\$${fare.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: _kGold,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.06),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _TripStatTile(
                                icon: Icons.straighten,
                                label: 'Distance',
                                value: '$distance km',
                              ),
                              _TripStatTile(
                                icon: Icons.schedule,
                                label: 'Duration',
                                value: duration,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    if (_tripData?['userRating'] == null)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => _showRatingDialog(_tripData!),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'RATE YOUR TRIP  ⭐',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _kGold.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _kGold.withOpacity(0.25)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Your rating: ',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < (_tripData?['userRating'] ?? 5)
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: _kGold,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () async {
                        await TripPersistenceService.clearActiveTrip();
                        Provider.of<MapProvider>(
                          context,
                          listen: false,
                        ).resetTripData();
                        navigatorKey.currentState?.pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const HomeScreenPro(),
                          ),
                        );
                      },
                      child: const Text(
                        'BACK TO HOME',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelledPanel() {
    final cancelledBy = _tripData?['cancelledBy'] ?? 'unknown';
    final cancelledReason =
        _tripData?['cancellationReason'] ?? 'No reason provided';

    return _buildSheetWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kRed.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Icon(Icons.cancel_rounded, color: _kRed, size: 48),
                const SizedBox(height: 10),
                Text(
                  cancelledBy == 'user'
                      ? 'You cancelled this trip'
                      : 'Trip was cancelled',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cancelledReason,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                Provider.of<MapProvider>(
                  context,
                  listen: false,
                ).resetTripData();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGold,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'REQUEST NEW RIDE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDriversPanel() {
    return _buildSheetWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: _kOrange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kOrange.withOpacity(0.3)),
            ),
            child: const Column(
              children: [
                Icon(Icons.search_off_rounded, color: _kOrange, size: 48),
                SizedBox(height: 10),
                Text(
                  'No Drivers Available',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'We couldn\'t find drivers in your area right now.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('trips')
                    .doc(widget.tripId)
                    .update({
                      'status': 'searching',
                      'searchStartedAt': FieldValue.serverTimestamp(),
                      'noDriversAvailable': false,
                    });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGold,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'TRY AGAIN',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              Provider.of<MapProvider>(context, listen: false).resetTripData();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text(
              'Back to Home',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared UI helpers ──────────────────────────────────────────────────
  Widget _buildSheetWrapper({required Widget child}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 24, offset: Offset(0, -4)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildLoadingContent(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(color: _kGold, strokeWidth: 3),
        ),
        const SizedBox(height: 14),
        Text(
          message,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driverInfo, {String? subtitle}) {
    final photoUrl = driverInfo['photoURL'];
    final name = driverInfo['displayName'] ?? 'Your Driver';
    final rating = driverInfo['rating']?.toStringAsFixed(1) ?? '4.5';
    final phone = driverInfo['phoneNumber'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_kGold, _kGoldLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: _kGold.withOpacity(0.25), blurRadius: 8),
              ],
              image:
                  photoUrl != null
                      ? DecorationImage(
                        image: NetworkImage(photoUrl),
                        fit: BoxFit.cover,
                      )
                      : null,
            ),
            child:
                photoUrl == null
                    ? const Icon(Icons.person, color: Colors.black, size: 26)
                    : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: _kGold, size: 14),
                    Text(
                      ' $rating',
                      style: const TextStyle(color: _kGold, fontSize: 12),
                    ),
                  ],
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (phone != null) _buildPhoneIconButton(phone),
        ],
      ),
    );
  }

  Widget _buildPhoneIconButton(String? phoneNumber) {
    return Material(
      color: _kGreen.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _callDriver(phoneNumber),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGreen.withOpacity(0.3)),
          ),
          child: const Icon(Icons.phone_rounded, color: _kGreen, size: 20),
        ),
      ),
    );
  }

  Widget _buildCancelOutlinedButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _showCancelTripDialog,
        icon: const Icon(Icons.close_rounded, size: 16, color: _kRed),
        label: const Text(
          'CANCEL REQUEST',
          style: TextStyle(
            color: _kRed,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: _kRed.withOpacity(0.5), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  void _showPremiumSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: color == _kGold ? Colors.black : Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
      ),
    );
  }

  // ── Rating dialog ──────────────────────────────────────────────────────
  void _showRatingDialog(Map<String, dynamic> tripData) {
    double rating = 5.0;
    final globalContext = context;

    showDialog(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kSurface.withOpacity(0.97),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: _kGold.withOpacity(0.2)),
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_kGold, _kGoldLight],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _kGold.withOpacity(0.4),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.star_rounded,
                                color: Colors.black,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Rate Your Trip',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'How was your ride experience?',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(5, (i) {
                                return GestureDetector(
                                  onTap:
                                      () => setDialogState(
                                        () => rating = i + 1.0,
                                      ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Icon(
                                      i < rating
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: _kGold,
                                      size: 40,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed:
                                        () => Navigator.of(dialogContext).pop(),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Colors.white24,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      'Skip',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      Navigator.of(dialogContext).pop();
                                      // Show loading
                                      showDialog(
                                        context: globalContext,
                                        barrierDismissible: false,
                                        barrierColor: Colors.black54,
                                        builder:
                                            (_) => Dialog(
                                              backgroundColor:
                                                  Colors.transparent,
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                child: BackdropFilter(
                                                  filter: ImageFilter.blur(
                                                    sigmaX: 20,
                                                    sigmaY: 20,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 32,
                                                          vertical: 28,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: _kSurface
                                                          .withOpacity(0.95),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors.white12,
                                                      ),
                                                    ),
                                                    child: const Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        SizedBox(
                                                          width: 40,
                                                          height: 40,
                                                          child:
                                                              CircularProgressIndicator(
                                                                color: _kGold,
                                                                strokeWidth: 3,
                                                              ),
                                                        ),
                                                        SizedBox(height: 16),
                                                        Text(
                                                          'Submitting your rating...',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w500,
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
                                        await _submitRating(rating).timeout(
                                          const Duration(seconds: 10),
                                          onTimeout: () {
                                            throw TimeoutException(
                                              'Rating submission took too long',
                                            );
                                          },
                                        );
                                        if (globalContext.mounted) {
                                          Navigator.of(globalContext).pop();
                                          _showPremiumSnackBar(
                                            'Thank you for your rating! ⭐',
                                            _kGold,
                                          );
                                        }
                                      } catch (e) {
                                        if (globalContext.mounted) {
                                          Navigator.of(globalContext).pop();
                                          _showPremiumSnackBar(
                                            'Error submitting rating: $e',
                                            _kRed,
                                          );
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kGold,
                                      foregroundColor: Colors.black,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      'SUBMIT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Reusable sub-widgets
// ═════════════════════════════════════════════════════════════════════════

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _TripStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _TripStatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _kGold, size: 18),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TripStatusSheet — fully isolated StatefulWidget for the bottom panel.
//
// WHY a separate widget instead of a method on _TripTrackingScreenState?
//   • Its own AnimationControllers (entrance + pulse) live in its own State.
//   • When the panel animates or rebuilds, the parent's build() is NOT called.
//   • Google Maps (a platform view) is therefore never disturbed by panel redraws.
// ─────────────────────────────────────────────────────────────────────────────
class _TripStatusSheet extends StatefulWidget {
  final String tripStatus;
  final Map<String, dynamic>? tripData;
  final double progressValue;
  final VoidCallback onCancelTrip;
  final void Function(String? phone) onCallDriver;
  final VoidCallback onGoHome;

  const _TripStatusSheet({
    required this.tripStatus,
    required this.tripData,
    required this.progressValue,
    required this.onCancelTrip,
    required this.onCallDriver,
    required this.onGoHome,
  });

  @override
  State<_TripStatusSheet> createState() => _TripStatusSheetState();
}

class _TripStatusSheetState extends State<_TripStatusSheet>
    with TickerProviderStateMixin {
  // ── Own animation controllers ─────────────────────────────────────────────
  late AnimationController _entranceCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  String? _lastStatus; // track status changes to re-animate entrance

  @override
  void initState() {
    super.initState();
    _lastStatus = widget.tripStatus;

    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);

    _entranceCtrl = AnimationController(
      duration: const Duration(milliseconds: 480),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    ));
    _entranceCtrl.forward();
  }

  @override
  void didUpdateWidget(_TripStatusSheet old) {
    super.didUpdateWidget(old);
    // Re-trigger entrance animation whenever the status changes.
    if (widget.tripStatus != _lastStatus) {
      _lastStatus = widget.tripStatus;
      _entranceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: _buildSheet(context),
      ),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 14, 20, bottom + 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0x10FFFFFF)),
          left: BorderSide(color: Color(0x08FFFFFF)),
          right: BorderSide(color: Color(0x08FFFFFF)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle pill
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Content for current status
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.tripStatus) {
      case 'searching':
        return _buildSearching();
      case 'driver_notified':
        return _buildDriverNotified();
      case 'driver_accepted':
        return _buildDriverAccepted();
      case 'driver_arrived':
        return _buildDriverArrived();
      case 'in_progress':
        return _buildInProgress();
      case 'cancelled':
        return _buildCancelled();
      case 'no_drivers_available':
        return _buildNoDrivers();
      default:
        return _buildLoading();
    }
  }

  // ── Searching ─────────────────────────────────────────────────────────────
  Widget _buildSearching() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing radar — animations owned HERE, not in parent
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => SizedBox(
            width: 90,
            height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring
                Transform.scale(
                  scale: 1.0 + _pulseCtrl.value * 0.5,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _kGold.withOpacity(
                            0.5 - _pulseCtrl.value * 0.45),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                // Inner ring
                Transform.scale(
                  scale: 1.0 + _pulseCtrl.value * 0.25,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _kGold.withOpacity(
                            0.4 - _pulseCtrl.value * 0.35),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                // Center icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_kGold, _kGoldLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    color: Colors.black,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Finding Your Driver',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Scanning nearby drivers in your area...',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        _cancelButton(),
      ],
    );
  }

  // ── Driver Notified ───────────────────────────────────────────────────────
  Widget _buildDriverNotified() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                value: widget.progressValue.clamp(0.0, 1.0),
                backgroundColor: Colors.white12,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(_kGold),
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
              ),
            ),
            const Icon(Icons.directions_car, color: _kGold, size: 30),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Driver Requested',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Waiting for a driver to accept your ride',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        _cancelButton(),
      ],
    );
  }

  // ── Driver Accepted ───────────────────────────────────────────────────────
  Widget _buildDriverAccepted() {
    final driverInfo = widget.tripData?['driverInfo'] as Map? ?? {};
    final eta = widget.tripData?['driverEta'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.directions_car,
                color: Color(0xFF4CAF50),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driver on the Way!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Your ride is confirmed',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (eta != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _kGold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGold.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Text(
                      _formatEta(eta),
                      style: const TextStyle(
                        color: _kGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Text(
                      'ETA',
                      style: TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _driverCard(driverInfo),
        const SizedBox(height: 14),
        _cancelButton(),
      ],
    );
  }

  // ── Driver Arrived ────────────────────────────────────────────────────────
  Widget _buildDriverArrived() {
    final driverInfo = widget.tripData?['driverInfo'] as Map? ?? {};
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Arrived banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.35)),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF4CAF50),
                size: 42,
              ),
              const SizedBox(height: 6),
              const Text(
                'Your Driver Has Arrived!',
                style: TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Please head to your pickup point',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _driverCard(driverInfo),
      ],
    );
  }

  // ── In Progress ───────────────────────────────────────────────────────────
  Widget _buildInProgress() {
    final driverInfo = widget.tripData?['driverInfo'] as Map? ?? {};
    final dropoff =
        widget.tripData?['dropoff']?['address'] as String? ?? 'Destination';
    final distance =
        (widget.tripData?['distanceRemaining'] ?? widget.tripData?['distance'] ?? 0.0)
            as num;
    final time =
        (widget.tripData?['timeRemaining'] ?? widget.tripData?['duration'] ?? 0)
            as num;
    final fare = (widget.tripData?['fare'] ?? 0.0) as num;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kGold, _kGoldLight]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.directions_car, color: Colors.black, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trip in Progress',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    dropoff,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statTile(icon: Icons.straighten, label: 'Distance', value: '${distance.toStringAsFixed(1)} km')),
            const SizedBox(width: 8),
            Expanded(child: _statTile(icon: Icons.schedule, label: 'Time Left', value: '$time min')),
            const SizedBox(width: 8),
            Expanded(child: _statTile(icon: Icons.payments_outlined, label: 'Fare', value: '\$${fare.toStringAsFixed(2)}', valueColor: _kGold)),
          ],
        ),
        const SizedBox(height: 12),
        _driverCard(driverInfo),
      ],
    );
  }

  // ── Cancelled ─────────────────────────────────────────────────────────────
  Widget _buildCancelled() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cancel_rounded, color: Color(0xFFE53935), size: 52),
        const SizedBox(height: 12),
        const Text(
          'Trip Cancelled',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Your trip has been cancelled.',
          style:
              TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Back to Home',
          onPressed: widget.onGoHome,
        ),
      ],
    );
  }

  // ── No Drivers ────────────────────────────────────────────────────────────
  Widget _buildNoDrivers() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.car_crash_rounded,
            color: Color(0xFFFF9800), size: 52),
        const SizedBox(height: 12),
        const Text(
          'No Drivers Available',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'We could not find a driver in your area right now. Please try again.',
          style:
              TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Back to Home',
          onPressed: widget.onGoHome,
        ),
      ],
    );
  }

  // ── Loading (fallback) ────────────────────────────────────────────────────
  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _kGold, strokeWidth: 2.5),
          SizedBox(height: 14),
          Text(
            'Loading trip...',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────
  String _formatEta(dynamic eta) {
    if (eta == null) return '—';
    if (eta is int) return '$eta min';
    if (eta is double) return '${eta.toStringAsFixed(0)} min';
    return eta.toString();
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchWhatsApp(String phone) async {
    // Strip non-digits for WhatsApp deep link
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Full driver info card ─────────────────────────────────────────────────
  Widget _driverCard(Map driverInfo) {
    final photoUrl  = driverInfo['photoURL'] as String?;
    final name      = (driverInfo['displayName'] as String?) ?? 'Your Driver';
    final rating    = (driverInfo['rating'] as num?)?.toStringAsFixed(1) ?? '—';
    final phone     = driverInfo['phoneNumber'] as String?;
    final trips     = driverInfo['totalTrips'] as int?;
    final car       = driverInfo['carDetails'] as Map? ??
                      driverInfo['vehicleDetails'] as Map? ?? {};
    final carModel  = car['model']  as String?;
    final carColor  = car['color']  as String?;
    final carPlate  = car['plateNumber'] as String?
                   ?? car['licensePlate'] as String?;
    final carType   = car['type']   as String?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top: photo + name + rating + trips ──────────────────────────
          Row(
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_kGold, _kGoldLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(color: _kGold.withOpacity(0.3), blurRadius: 10)
                  ],
                  image: photoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(photoUrl), fit: BoxFit.cover)
                      : null,
                ),
                child: photoUrl == null
                    ? const Icon(Icons.person, color: Colors.black, size: 28)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: _kGold, size: 14),
                        Text(
                          ' $rating',
                          style: const TextStyle(color: _kGold, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        if (trips != null) ...[
                          Text(
                            '  ·  ',
                            style: TextStyle(color: Colors.white.withOpacity(0.3)),
                          ),
                          const Icon(Icons.directions_car_filled, size: 12, color: Colors.white38),
                          Text(
                            ' $trips trips',
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Divider ─────────────────────────────────────────────────────
          if (carModel != null || carPlate != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Container(
                  height: 1,
                  color: Colors.white.withOpacity(0.06),
                ),
                const SizedBox(height: 12),

                // ── Car details row ────────────────────────────────────────
                Row(
                  children: [
                    // Car icon badge
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _kGold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.directions_car, color: _kGold, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (carModel != null)
                            Text(
                              '${carColor != null ? '$carColor ' : ''}$carModel${carType != null ? ' ($carType)' : ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (carPlate != null)
                            Text(
                              carPlate,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                                letterSpacing: 1.2,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Plate badge
                    if (carPlate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Text(
                          carPlate,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

          // ── Contact buttons ──────────────────────────────────────────────
          if (phone != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                // Phone call
                Expanded(
                  child: GestureDetector(
                    onTap: () => _launchPhone(phone),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.13),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF4CAF50).withOpacity(0.35)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_rounded,
                              color: Color(0xFF4CAF50), size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Call',
                            style: TextStyle(
                              color: Color(0xFF4CAF50),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // WhatsApp
                Expanded(
                  child: GestureDetector(
                    onTap: () => _launchWhatsApp(phone),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withOpacity(0.13),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF25D366).withOpacity(0.35)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_rounded,
                              color: Color(0xFF25D366), size: 18),
                          SizedBox(width: 6),
                          Text(
                            'WhatsApp',
                            style: TextStyle(
                              color: Color(0xFF25D366),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cancelButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: widget.onCancelTrip,
        icon: const Icon(Icons.close_rounded, size: 16,
            color: Color(0xFFE53935)),
        label: const Text(
          'Cancel Trip',
          style: TextStyle(
              color: Color(0xFFE53935), fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFE53935), width: 1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _primaryButton(
      {required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kGold,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _statTile(
      {required IconData icon,
      required String label,
      required String value,
      Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _kGold, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
