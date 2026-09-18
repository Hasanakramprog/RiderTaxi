import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_connectivity_service.dart';

// Provider to manage network connectivity state
class NetworkConnectivityProvider extends ChangeNotifier {
  final NetworkConnectivityService _networkService = NetworkConnectivityService();
  bool _isConnected = true;
  bool _isChecking = false;

  bool get isConnected => _isConnected;
  bool get isChecking => _isChecking;

  NetworkConnectivityProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    // Initialize network service
    await _networkService.initialize();
    
    // Set initial state
    _isConnected = _networkService.isConnected;
    
    // Listen for connectivity changes
    _networkService.addListener((connected) {
      _isConnected = connected;
      notifyListeners();
    });
    
    notifyListeners();
  }

  Future<bool> checkConnectivity() async {
    if (_isChecking) return _isConnected;
    
    _isChecking = true;
    notifyListeners();
    
    try {
      final isConnected = await _networkService.checkConnectivityWithRetry();
      _isConnected = isConnected;
      return isConnected;
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  void disposeService() {
    _networkService.dispose();
  }
}

// Widget to show network connectivity banner (like YouTube)
class NetworkConnectivityBanner extends StatefulWidget {
  final Widget child;
  final Duration animationDuration;

  const NetworkConnectivityBanner({
    Key? key,
    required this.child,
    this.animationDuration = const Duration(milliseconds: 300),
  }) : super(key: key);

  @override
  State<NetworkConnectivityBanner> createState() => _NetworkConnectivityBannerState();
}

class _NetworkConnectivityBannerState extends State<NetworkConnectivityBanner> {
  bool? _previousConnected;
  bool _showBackOnline = false;
  bool _isManuallyDismissed = false;
  Timer? _dismissTimer;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _onConnectivityChanged(bool isConnected) {
    if (_previousConnected == null) {
      // First initial observation: if already connected, do nothing. If offline, stay offline.
      _previousConnected = isConnected;
      return;
    }

    if (_previousConnected == false && isConnected == true) {
      // Transitioned from OFFLINE -> ONLINE
      _dismissTimer?.cancel();
      setState(() {
        _showBackOnline = true;
        _isManuallyDismissed = false;
      });
      _dismissTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showBackOnline = false;
          });
        }
      });
    } else if (isConnected == false) {
      // Transitioned to OFFLINE
      _dismissTimer?.cancel();
      setState(() {
        _showBackOnline = false;
        _isManuallyDismissed = false;
      });
    }

    _previousConnected = isConnected;
  }

  @override
  Widget build(BuildContext context) {
    final networkProvider = Provider.of<NetworkConnectivityProvider>(context);
    final isConnected = networkProvider.isConnected;

    if (_previousConnected != isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onConnectivityChanged(isConnected);
        }
      });
    }

    final bool isOffline = !isConnected;
    final bool shouldShowBanner = (isOffline || _showBackOnline) && !_isManuallyDismissed;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !shouldShowBanner,
            child: AnimatedSlide(
              duration: widget.animationDuration,
              curve: Curves.easeOutCubic,
              offset: shouldShowBanner ? Offset.zero : const Offset(0, -1.0),
              child: AnimatedOpacity(
                duration: widget.animationDuration,
                opacity: shouldShowBanner ? 1.0 : 0.0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(10),
                      color: isOffline
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFF2E7D32),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isOffline
                                  ? Icons.wifi_off_rounded
                                  : Icons.wifi_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isOffline
                                    ? 'No connection. Check your internet settings.'
                                    : 'Back online',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isOffline) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  networkProvider.checkConnectivity();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'RETRY',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            // Close button for both states
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isManuallyDismissed = true;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'HIDE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
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
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Widget to disable functionality when offline
class NetworkAwareButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool requireConnection;
  final String offlineMessage;
  final Widget? offlineChild;

  const NetworkAwareButton({
    Key? key,
    required this.child,
    this.onPressed,
    this.requireConnection = true,
    this.offlineMessage = 'No internet connection',
    this.offlineChild,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final networkProvider = Provider.of<NetworkConnectivityProvider>(context);
    final isConnected = networkProvider.isConnected;
    
    final bool isEnabled = !requireConnection || isConnected;
    
    return Tooltip(
      message: !isEnabled ? offlineMessage : '',
      child: Stack(
        children: [
          Opacity(
            opacity: isEnabled ? 1.0 : 0.5,
            child: AbsorbPointer(
              absorbing: !isEnabled,
              child: InkWell(
                onTap: isEnabled ? onPressed : null,
                child: child,
              ),
            ),
          ),
          if (!isEnabled && offlineChild != null)
            Positioned.fill(child: offlineChild!),
        ],
      ),
    );
  }
}

// Network-aware text field for booking
class NetworkAwareTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final IconData? icon;
  final bool enabled;
  final bool requireConnection;
  final String offlineHint;

  const NetworkAwareTextField({
    Key? key,
    required this.controller,
    required this.labelText,
    required this.hintText,
    this.icon,
    this.enabled = true,
    this.requireConnection = true,
    this.offlineHint = 'Connect to internet to use',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final networkProvider = Provider.of<NetworkConnectivityProvider>(context);
    final isConnected = networkProvider.isConnected;
    
    final bool isEnabled = enabled && (!requireConnection || isConnected);
    
    return TextField(
      controller: controller,
      enabled: isEnabled,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: isEnabled ? hintText : offlineHint,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: !isEnabled,
        fillColor: !isEnabled ? Colors.grey[100] : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
