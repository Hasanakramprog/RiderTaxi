import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firestore_provider.dart';
import '../providers/map_provider.dart'; // Import the map provider
import '../widgets/map_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class TripTrackingScreen extends StatefulWidget {
  final String tripId;
  
  const TripTrackingScreen({Key? key, required this.tripId}) : super(key: key);

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen> {
  // Add these variables to your state class
  StreamSubscription<DocumentSnapshot>? _tripSubscription;
  Timer? _refreshTimer;
  Timestamp? _lastUpdateTimestamp;
  Map<String, dynamic>? _tripData;
  String _tripStatus = 'searching';

  // Existing variables...
  String? _statusMessage;
  bool _isWaitingForDriver = false;
  bool _isDriverOnTheWay = false;
  bool _isDriverArrived = false;
  bool _isTripInProgress = false;
  bool _isTripCompleted = false;
  bool _noDriversAvailable = false;
  Timer? _driverResponseTimer;

  // Add this timer to your existing variables
  Timer? _progressUpdateTimer;
  // Add this to track elapsed time for UI updates
  double _progressValue = 0.0;

  // Add this constant at the class level for consistency
  static const int DRIVER_TIMEOUT_SECONDS = 30;

  // Add these variables to your _TripTrackingScreenState class
  Timer? _searchingTimer;
  int _searchingCount = 0;

  @override
  void initState() {
    super.initState();
    // Listen for trip status changes
    _setupTripListener();
    
    // Set up a periodic refresh every 3 seconds for critical statuses
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _manualRefreshTripStatus();
    });
  }
 Future<void> _manualRefreshTripStatus() async {
    try {
      // Only refresh if we're in an active trip state
      if (_tripStatus == 'driver_accepted' || 
          _tripStatus == 'driver_arrived' || 
          _tripStatus == 'in_progress') {
        
        // Get latest data directly with cache disabled
        final snapshot = await FirebaseFirestore.instance
            .collection('trips')
            .doc(widget.tripId)
            .get(const GetOptions(source: Source.server));
        
        if (snapshot.exists) {
          final tripData = snapshot.data()!;
          final status = tripData['status'] as String?;
          final lastUpdated = tripData['updatedAt'] as Timestamp?;
          
          // Only process if it's newer than what we have
          if (lastUpdated != null && 
              (_lastUpdateTimestamp == null || 
               lastUpdated.compareTo(_lastUpdateTimestamp!) > 0)) {
            
            // If status has changed, update UI
            if (status != null && status != _tripStatus) {
              setState(() {
                _tripStatus = status;
                _tripData = tripData;
                _lastUpdateTimestamp = lastUpdated;
              });
              
              // Handle different status updates
              switch (status) {
                case 'driver_accepted':
                  _handleDriverAccepted(tripData);
                  break;
                case 'driver_arrived':
                  _handleDriverArrived(tripData);
                  break;
                case 'in_progress':
                  _handleTripInProgress(tripData);
                  break;
                case 'completed':
                  _handleTripCompleted(tripData);
                  break;
                // Add other cases as needed
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error manually refreshing trip status: $e');
    }
  }
  void _setupTripListener() {
    _tripSubscription = FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          // Only process if data is fresh from server
          if (snapshot.metadata.hasPendingWrites == false && 
              snapshot.metadata.isFromCache == false) {
            if (!snapshot.exists) {
              // Handle deleted trip
              return;
            }
          
            final tripData = snapshot.data()!;
            final status = tripData['status'] as String?;
            final lastUpdated = tripData['updatedAt'] as Timestamp?;
            
            // Update UI based on status changes
            setState(() {
              _tripStatus = status ?? 'unknown';
              _tripData = tripData;
              _lastUpdateTimestamp = lastUpdated;
            });
            
            // Handle different status updates
            switch (status) {
              case 'driver_notified':
                _handleDriverNotified(tripData);
                break;
              case 'driver_accepted':
                _handleDriverAccepted(tripData);
                break;
              case 'driver_arrived':
                _handleDriverArrived(tripData);
                break;
              case 'in_progress':
                _handleTripInProgress(tripData);
                break;
              case 'completed':
                _handleTripCompleted(tripData);
                break;
              case 'cancelled':
                _handleTripCancelled(tripData);
                break;
              case 'no_drivers_available':
                _handleNoDriversAvailable();
                break;
            }
          }
        });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tripSubscription?.cancel();
    _cancelDriverResponseTimer();
    _searchingTimer?.cancel(); // Add this line
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitleForStatus()),
        backgroundColor: _getColorForStatus(),
        actions: [
          // Add a small refresh indicator in the app bar
          if (_tripStatus == 'driver_accepted' || 
              _tripStatus == 'driver_arrived' || 
              _tripStatus == 'in_progress')
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getColorForStatus() == Colors.amber
                        ? Colors.black54
                        : Colors.white70,
                  ),
                ),
              ),
            ),
          // Your existing actions
          if (_shouldShowCancelButton())
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: _showCancelTripDialog,
              tooltip: 'Cancel Trip',
            ),
        ],
      ),
      body: _tripStatus == 'completed' 
          ? _buildCompletedPanel()  // Special full-screen panel for completed trips
          : Column(  // Regular layout for other trip statuses
              children: [
                // Map view showing trip progress
                Expanded(
                  flex: 3,
                  child: MapWidget(
                    showDriverLocation: _tripStatus == 'driver_accepted' || 
                                       _tripStatus == 'driver_arrived' || 
                                       _tripStatus == 'in_progress',
                    tripId: widget.tripId,
                  ),
                ),
                
                // Status panel
                Expanded(
                  flex: 2,
                  child: _buildStatusPanel(),
                ),
              ],
            ),
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
        return Colors.orange;
      case 'driver_accepted':
      case 'driver_arrived':
      case 'in_progress':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
      case 'no_drivers_available':
        return Colors.red;
      default:
        return Colors.amber;
    }
  }

  bool _shouldShowCancelButton() {
    // Only show cancel button for certain statuses
    return _tripStatus == 'searching' || 
           _tripStatus == 'driver_notified' || 
           _tripStatus == 'driver_accepted';
  }

  Widget _buildStatusPanel() {
  // Get the map provider to check loading status
  final mapProvider = Provider.of<MapProvider>(context, listen: true);
  
  // First check for specific trip statuses that should override the loading state
  if (_tripStatus == 'searching') {
    return _buildSearchingPanel();
  }
  
  // Then check if map is loading with no specific status
  if (mapProvider.isLoading) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.amber),
          const SizedBox(height: 16),
          Text(
            'Updating map location...',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
  
  // Continue with other status panels based on trip status
  switch (_tripStatus) {
    case 'driver_notified':
      return _buildDriverNotifiedPanel();
    case 'driver_accepted':
      return _buildDriverAcceptedPanel();
    case 'driver_arrived':
      return _buildDriverArrivedPanel();
    case 'in_progress':
      return _buildInProgressPanel();
    case 'completed':
      return _buildCompletedPanel();
    case 'cancelled':
      return _buildCancelledPanel();
    case 'no_drivers_available':
      return _buildNoDriversPanel();
    default:
      return const Center(child: Text('Loading trip information...'));
  }
}

  void _showCancelTripDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Trip?'),
        content: const Text('Are you sure you want to cancel your trip request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('NO'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _cancelTrip();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('YES, CANCEL'),
          ),
        ],
      ),
    );
  }
  
  void _cancelTrip() async {
    // Show confirmation dialog
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Trip?'),
        content: const Text('Are you sure you want to cancel this trip? Cancellation may incur fees.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    
    if (shouldCancel == true) {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cancelling trip...'),
            ],
          ),
        ),
      );
      
      try {
        // Update trip status to cancelled
        await FirebaseFirestore.instance.collection('trips').doc(widget.tripId).update({
          'status': 'cancelled',
          'cancelledBy': 'user',
          'cancellationTime': FieldValue.serverTimestamp(),
          'cancellationReason': 'user_cancelled'
        });
        
        // Close loading dialog
        Navigator.of(context).pop();
        
        // Show success and return to home screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip cancelled successfully')),
        );
        
        // Return to home screen
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (e) {
        // Close loading dialog
        Navigator.of(context).pop();
        
        // Show error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling trip: $e')),
        );
      }
    }
  }
  
  // Driver has been notified but hasn't accepted yet
  void _handleDriverNotified(Map<String, dynamic> tripData) {
    // Show waiting UI
    setState(() {
      _statusMessage = 'Waiting for driver to accept...';
      _isWaitingForDriver = true;
      _progressValue = 0.0; // Reset progress value
    });
    
    // Start a timer to handle driver timeout (e.g., 30 seconds)
    _startDriverResponseTimer();
    
    // Add this: Create a timer to update the progress indicator
    _startProgressUpdateTimer(tripData);
  }

  // Add this new method to start the progress update timer
  void _startProgressUpdateTimer(Map<String, dynamic> tripData) {
    // Cancel any existing timer
    _progressUpdateTimer?.cancel();
    
    // Get the notification time
    final notificationTime = tripData['notificationTime'] != null
        ? (tripData['notificationTime'] as Timestamp).toDate()
        : DateTime.now();
    
    // Use the same constant for consistency
    const totalTimeout = DRIVER_TIMEOUT_SECONDS;
    
    // Create a timer that fires every 0.5 seconds to update the progress smoothly
    _progressUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      // Calculate elapsed time
      final elapsed = DateTime.now().difference(notificationTime).inMilliseconds / 1000;
      final progress = elapsed / totalTimeout;
      
      setState(() {
        _progressValue = progress > 1 ? 1 : progress;
      });
      
      // If progress is complete, cancel the timer AND trigger the handler
      if (progress >= 0.99) {
        timer.cancel();
        
        // Important: Cancel the other timer to prevent double execution
        _driverResponseTimer?.cancel();
        
        setState(() {
          _progressValue = 1.0; // Force to exact 1.0 for visual completion
        });
        
        // Trigger the timeout handler directly
        _handleDriverTimeout();
      }
    });
  }

  // Update your _handleDriverAccepted method to cancel the progress timer
  void _handleDriverAccepted(Map<String, dynamic> tripData) {
    // Cancel both timers
    _cancelDriverResponseTimer();
    _progressUpdateTimer?.cancel();
    _progressUpdateTimer = null;
    
    // Extract driver information
    final driverId = tripData['driverId'];
    _loadDriverDetails(driverId);
    
    // Update UI to show driver is on the way
    setState(() {
      _progressValue = 1.0;
      _statusMessage = 'Driver is on the way!';
      _isWaitingForDriver = false;
      _isDriverOnTheWay = true;
    });
    
    // Play a sound notification
    _playNotificationSound();
    
    // Show driver details dialog
    _showDriverDetailsDialog(tripData);
  }

  // Driver has arrived at pickup location
  void _handleDriverArrived(Map<String, dynamic> tripData) {
    setState(() {
      _statusMessage = 'Your driver has arrived!';
      _isDriverOnTheWay = false;
      _isDriverArrived = true;
    });
    
    // Show notification
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Driver has arrived at your location'),
        backgroundColor: Colors.green,
      ),
    );
    
    // Play arrival sound
    _playArrivalSound();
  }

  // Trip is in progress
  void _handleTripInProgress(Map<String, dynamic> tripData) {
    setState(() {
      _statusMessage = 'Your trip is in progress';
      _isDriverArrived = false;
      _isTripInProgress = true;
    });
    
    // Update map to show route to destination
    _updateMapForInProgressTrip();
  }

  // Trip has been completed
  void _handleTripCompleted(Map<String, dynamic> tripData) {
    setState(() {
      _statusMessage = 'Trip completed';
      _isTripInProgress = false;
      _isTripCompleted = true;
    });
    
    // Show trip summary dialog
    // _showTripSummaryDialog(tripData);
  }

  // No drivers available
  void _handleNoDriversAvailable() {
    setState(() {
      _statusMessage = 'No drivers available nearby';
      _isWaitingForDriver = false;
      _noDriversAvailable = true;
    });
    
    // Show options to retry or cancel
    _showNoDriversDialog();
  }

  void _handleTripCancelled(Map<String, dynamic> tripData) {
    // Handle trip cancelled logic
  }

  void _startDriverResponseTimer() {
    // Cancel any existing timer
    _cancelDriverResponseTimer();
    
    // Start a new timer for 30 seconds
    _driverResponseTimer = Timer(const Duration(seconds: DRIVER_TIMEOUT_SECONDS), () {
      // If no response after 30 seconds, try the next driver or show no drivers
      _handleDriverTimeout();
    });
  }

  void _cancelDriverResponseTimer() {
    _driverResponseTimer?.cancel();
    _driverResponseTimer = null;
  }

  void _handleDriverTimeout() async {
    // Check if there are more drivers to notify
    if (_tripData != null && 
        _tripData!['nearbyDrivers'] != null && 
        (_tripData!['nearbyDrivers'] as List).length > 1) {
      
      // Get the next driver in the list
      final nearbyDrivers = List.from(_tripData!['nearbyDrivers']);
      nearbyDrivers.removeWhere((driver) => driver['id'] == _tripData!['notifiedDriverId']);
      
      if (nearbyDrivers.isNotEmpty) {
        final nextDriver = nearbyDrivers.first;
        
        // Update trip to notify next driver
        await FirebaseFirestore.instance.collection('trips').doc(widget.tripId).update({
          'notifiedDriverId': nextDriver['id'],
          'notificationTime': FieldValue.serverTimestamp(),
          'previouslyNotifiedDrivers': FieldValue.arrayUnion([_tripData!['notifiedDriverId']])
        });
        
        setState(() {
          _statusMessage = 'Finding another driver...';
        });
        
        // Start a new timer for the next driver
        _startDriverResponseTimer();
      } else {
        // No more drivers available
        await FirebaseFirestore.instance.collection('trips').doc(widget.tripId).update({
          'status': 'no_drivers_available',
          'noDriversAvailable': true
        });
      }
    } else {
      // No more drivers available
      await FirebaseFirestore.instance.collection('trips').doc(widget.tripId).update({
        'status': 'no_drivers_available',
        'noDriversAvailable': true
      });
    }
  }

  void _loadDriverDetails(String driverId) {
    // Load driver details
  }

  void _playNotificationSound() {
    // Play notification sound
  }

  void _showDriverDetailsDialog(Map<String, dynamic> tripData) {
    final driverInfo = tripData['driverInfo'] ?? {};
    final carDetails = driverInfo['carDetails'] ?? {};
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Driver is on the way!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: driverInfo['photoURL'] != null 
                      ? NetworkImage(driverInfo['photoURL']) 
                      : null,
                  child: driverInfo['photoURL'] == null 
                      ? const Icon(Icons.person, size: 30) 
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverInfo['displayName'] ?? 'Driver',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          Text(' ${driverInfo['rating']?.toStringAsFixed(1) ?? '4.5'}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Car details
            if (carDetails.isNotEmpty) ...[
              const Text(
                'Car Details',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.directions_car, size: 16),
                  const SizedBox(width: 8),
                  Text('${carDetails['color'] ?? 'N/A'} ${carDetails['model'] ?? 'Car'}'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.credit_card, size: 16),
                  const SizedBox(width: 8),
                  Text('Plate: ${carDetails['plateNumber'] ?? 'N/A'}'),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // ETA
            Text(
              'Estimated arrival: ${_formatEta(tripData['driverEta'])}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Launch phone call to driver
              _callDriver(driverInfo['phoneNumber']);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phone),
                SizedBox(width: 8),
                Text('Call Driver'),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

  // Function to call driver
  void _callDriver(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver phone number not available')),
      );
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

  void _showTripSummaryDialog(Map<String, dynamic> tripData) {
    double rating = 5.0;
    final totalFare = tripData['fare'] ?? 0.0;
    final driverInfo = tripData['driverInfo'] ?? {};
    
    // Store a global context for SnackBar that will remain valid
    final globalContext = context;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Trip Completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total Fare: \$${totalFare.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Rate your trip:'),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        rating = index + 1.0;
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 8),
              // Driver info
              Text('Driver: ${driverInfo['displayName'] ?? 'Your driver'}'),
              // Trip stats
              Text('Distance: ${(tripData['distance'] ?? 0).toStringAsFixed(1)} km'),
              Text('Duration: ${_formatDuration(tripData['actualDuration'])}'),
              
              const SizedBox(height: 16),
              const Text(
                'Thank you for riding with us!',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // First close the dialog to prevent getting stuck
                Navigator.of(dialogContext).pop();
                
                // Show loading indicator
                showDialog(
                  context: globalContext, // Use the stored context
                  barrierDismissible: false,
                  builder: (loadingContext) => const AlertDialog(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Submitting your rating...'),
                      ],
                    ),
                  ),
                );
                
                // Submit rating
                await _submitRating(rating);
                
                // Close loading dialog
                Navigator.of(globalContext).pop(); // Use the stored context
                
                // Show a confirmation toast using the stored context
                if (globalContext.mounted) { // Check if context is still valid
                  ScaffoldMessenger.of(globalContext).showSnackBar(
                    const SnackBar(
                      content: Text('Thank you for your rating!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('DONE'),
            ),
          ],
        ),
      ),
    );
  }

  // New method for rating dialog that doesn't auto-navigate home
  void _showRatingDialog(Map<String, dynamic> tripData) {
  double rating = 5.0;
  // Store a reference to the global context
  final globalContext = context;
  
  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Rate your Trip'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How was your ride experience?'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                  onPressed: () {
                    setDialogState(() {
                      rating = index + 1.0;
                    });
                  },
                );
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Close the rating dialog first
              Navigator.of(dialogContext).pop();
              
              // Show loading dialog
              showDialog(
                context: globalContext,
                barrierDismissible: false,
                builder: (loadingContext) => WillPopScope(
                  onWillPop: () async => false, // Prevent back button from closing
                  child: AlertDialog(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Submitting your rating...'),
                      ],
                    ),
                  ),
                ),
              );
              
              try {
                // Submit rating with timeout
                await _submitRating(rating).timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    print('Rating submission timed out');
                    throw TimeoutException('Rating submission took too long');
                  },
                );
                
                // Close loading dialog on success
                if (globalContext.mounted) {
                  Navigator.of(globalContext).pop();
                  
                  // Show success message
                  ScaffoldMessenger.of(globalContext).showSnackBar(
                    const SnackBar(
                      content: Text('Thank you for your rating!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                print('Error submitting rating: $e');
                
                // Close loading dialog on error
                if (globalContext.mounted) {
                  Navigator.of(globalContext).pop();
                  
                  // Show error message
                  ScaffoldMessenger.of(globalContext).showSnackBar(
                    SnackBar(
                      content: Text('Error submitting rating: ${e.toString().split(':').first}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('SUBMIT'),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _submitRating(double rating) async {
  try {
    // Update the trip with user rating
    await FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .update({
          'userRating': rating,
          'ratedAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
    
    // The cloud function will automatically update the driver's rating
    // No need to manually update driver collection here
    
    // Refresh trip data from Firestore to ensure UI is in sync
    final updatedTrip = await FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .get();
    
    if (updatedTrip.exists) {
      setState(() {
        _tripData = updatedTrip.data()!;
      });
    }
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thank you for your rating!'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    print('Error submitting rating: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to submit rating. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
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
      builder: (context) => AlertDialog(
        title: const Text('No Drivers Available'),
        content: const Text(
          'We couldn\'t find any available drivers in your area at this time. '
          'Would you like to try again or cancel your request?'
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Return to home screen
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Retry finding drivers
              FirebaseFirestore.instance.collection('trips').doc(widget.tripId).update({
                'status': 'searching',
                'searchStartedAt': FieldValue.serverTimestamp(),
                'noDriversAvailable': false
              });
            },
            child: const Text('TRY AGAIN'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchingPanel() {
    // Start the driver search timer if it's not already running
    if (_searchingTimer == null) {
      _startPeriodicDriverSearch();
    }
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          const Text(
            'Finding drivers near you...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            _searchingCount > 3 
                ? 'Taking longer than usual to find drivers...'
                : 'We are searching for available drivers in your area.',
            style: TextStyle(color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCancelTripDialog,
            icon: const Icon(Icons.cancel),
            label: const Text('CANCEL REQUEST'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[100],
              foregroundColor: Colors.red[900],
            ),
          ),
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
      if (_searchingCount > 12) {  // 12 x 10 seconds = 2 minutes
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
            'searchAttempts': FieldValue.increment(1)
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
              'searchEndedAt': FieldValue.serverTimestamp()
            });
      } catch (e) {
        print('Error updating trip status to no_drivers_available: $e');
      }
    }
  }

  Widget _buildDriverNotifiedPanel() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 80,
                width: 80,
                child: CircularProgressIndicator(
                  value: _progressValue, // Use the state variable instead
                  backgroundColor: Colors.grey[300],
                  color: Colors.orange,
                  strokeWidth: 8,
                ),
              ),
              const Icon(Icons.hourglass_top, size: 40, color: Colors.orange),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Request sent to driver',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Waiting for driver to accept your request...',
            style: TextStyle(color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCancelTripDialog,
            icon: const Icon(Icons.cancel),
            label: const Text('CANCEL REQUEST'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[100],
              foregroundColor: Colors.red[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverAcceptedPanel() {
    final driverInfo = _tripData?['driverInfo'] ?? {};
    final driverEta = _tripData?['driverEta'];
    
    return SingleChildScrollView(  // Add this wrapper
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,  // Add this property
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: driverInfo['photoURL'] != null 
                              ? NetworkImage(driverInfo['photoURL']) 
                              : null,
                          child: driverInfo['photoURL'] == null 
                              ? const Icon(Icons.person) 
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driverInfo['displayName'] ?? 'Your Driver',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 16),
                                  Text(' ${driverInfo['rating']?.toStringAsFixed(1) ?? '4.5'}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.phone, color: Colors.green),
                          onPressed: () => _callDriver(driverInfo['phoneNumber']),
                          tooltip: 'Call driver',
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Driver is on the way'),
                        Text(
                          'ETA: ${_formatEta(driverEta)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _showCancelTripDialog,
              icon: const Icon(Icons.cancel),
              label: const Text('CANCEL TRIP'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverArrivedPanel() {
  final driverInfo = _tripData?['driverInfo'] ?? {};
  final carDetails = driverInfo['carDetails'] ?? {};
  
  return SingleChildScrollView(  // Wrap in SingleChildScrollView
    physics: const AlwaysScrollableScrollPhysics(),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,  // Add this to prevent expansion
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            size: 64,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your driver has arrived!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: driverInfo['photoURL'] != null 
                            ? NetworkImage(driverInfo['photoURL']) 
                            : null,
                        child: driverInfo['photoURL'] == null 
                            ? const Icon(Icons.person) 
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverInfo['displayName'] ?? 'Your Driver',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (carDetails.isNotEmpty) 
                              Text(
                                '${carDetails['color'] ?? ''} ${carDetails['model'] ?? 'Car'} (${carDetails['plateNumber'] ?? ''})',
                                style: TextStyle(color: Colors.grey[700], fontSize: 14),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.phone, color: Colors.green),
                        onPressed: () => _callDriver(driverInfo['phoneNumber']),
                        tooltip: 'Call driver',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // ElevatedButton(
          //   onPressed: () {
          //     FirebaseFirestore.instance.collection('trips').doc(widget.tripId).update({
          //       'status': 'in_progress',
          //       'startTime': FieldValue.serverTimestamp(),
          //     });
          //   },
          //   style: ElevatedButton.styleFrom(
          //     backgroundColor: Colors.green,
          //     padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          //   ),
          //   child: const Text(
          //     'START TRIP',
          //     style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          //   ),
          // ),
        ],
      ),
    ),
  );
}

  Widget _buildInProgressPanel() {
    final driverInfo = _tripData?['driverInfo'] ?? {};
    final dropoffAddress = _tripData?['dropoff']?['address'] ?? 'Destination';
    final distanceRemaining = _tripData?['distanceRemaining'] ?? _tripData?['distance'] ?? 0.0;
    final timeRemaining = _tripData?['timeRemaining'] ?? _tripData?['duration'] ?? 0;
    
    return SingleChildScrollView(  // Add this wrapper
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,  // Add this
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Card(
              elevation: 4,
              color: Colors.green[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,  // Add this
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.directions_car, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Trip in Progress',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(  // Add this to prevent text overflow
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Destination',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dropoffAddress,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,  // Add this
                                maxLines: 2,  // Add this
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.phone, color: Colors.green),
                          onPressed: () => _callDriver(driverInfo['phoneNumber']),
                          tooltip: 'Call driver',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text(
                              'Distance',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${distanceRemaining.toStringAsFixed(1)} km',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const Text(
                              'Time',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$timeRemaining min',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const Text(
                              'Fare',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$${(_tripData?['fare'] ?? 0.0).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedPanel() {
  final fare = _tripData?['fare'] ?? 0.0;
  final distance = (_tripData?['distance'] ?? 0).toStringAsFixed(1);
  final duration = _formatDuration(_tripData?['actualDuration'] ?? _tripData?['duration']);
  final driverInfo = _tripData?['driverInfo'] ?? {};
  
  return Column(
    children: [
      // Map showing the trip route (takes 60% of the available space)
      Expanded(
        flex: 6,
        child: MapWidget(
          showCompletedTrip: true,
          tripData: _tripData,
          tripId: widget.tripId,
        ),
      ),
      
      // Trip details (takes 40% of the available space)
      Expanded(
        flex: 4,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Trip Completed',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Total Fare',
                          style: TextStyle(color: Colors.grey[700], fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${fare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              children: [
                                const Text('Distance', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                Text('$distance km', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Duration', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                Text(duration, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Only show the Rate button if user hasn't rated yet
                if (_tripData?['userRating'] == null)
                  ElevatedButton(
                    onPressed: () {
                      _showRatingDialog(_tripData!);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    ),
                    child: const Text(
                      'RATE YOUR TRIP',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Card(
                    color: Colors.amber[50],
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Your Rating: ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                          Row(
                            children: List.generate(5, (index) {
                              return Icon(
                                index < (_tripData?['userRating'] ?? 5) 
                                    ? Icons.star 
                                    : Icons.star_border,
                                color: Colors.amber,
                                size: 16,
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  child: const Text('BACK TO HOME', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

  Widget _buildCancelledPanel() {
    final cancelledBy = _tripData?['cancelledBy'] ?? 'unknown';
    final cancelledReason = _tripData?['cancellationReason'] ?? 'No reason provided';
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cancel,
            size: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            cancelledBy == 'user' 
                ? 'You cancelled this trip' 
                : 'Trip was cancelled',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Reason: $cancelledReason',
            style: TextStyle(color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text(
              'REQUEST NEW RIDE',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDriversPanel() {
    return SingleChildScrollView(  // Wrap in SingleChildScrollView
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,  // Add this
          children: [
            Icon(
              Icons.warning_rounded,
              size: 64,
              color: Colors.amber[700],
            ),
            const SizedBox(height: 16),
            const Text(
              'No Drivers Available',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'We couldn\'t find any available drivers in your area at this time.',
              style: TextStyle(color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                FirebaseFirestore.instance.collection('trips').doc(widget.tripId).update({
                  'status': 'searching',
                  'searchStartedAt': FieldValue.serverTimestamp(),
                  'noDriversAvailable': false
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text(
                'TRY AGAIN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('BACK TO HOME'),
            ),
          ],
        ),
      ),
    );
  }
}