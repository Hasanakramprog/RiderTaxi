import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/animated_taxi_road.dart';
import 'trip_request_screen.dart';
import 'trip_history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_taxi, size: 24),
            SizedBox(width: 8),
            Text('Ismail Taxi'),
          ],
        ),
        backgroundColor: Colors.amber,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              // Navigate to profile screen or show profile dialog
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('User Profile'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email: ${authProvider.user?.email ?? "Not signed in"}'),
                      const SizedBox(height: 8),
                      const Text('Member since: May 2023'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      child: const Text('Close'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      child: const Text('Sign Out'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        authProvider.signOut();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Add our custom animated taxi on road
          const AnimatedTaxiRoad(),
          
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Welcome to Ismail Taxi',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Where do you want to go?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Quick destination options
                    _buildDestinationOptions(),
                    const SizedBox(height: 40),
                    // CTA button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const TripRequestScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black87,
                          elevation: 4,
                          shadowColor: Colors.amberAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_rounded, size: 28),
                            SizedBox(width: 8),
                            Text(
                              'BOOK A TAXI',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Bottom options
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCircleButton(
                          icon: Icons.history,
                          label: 'My Trips',
                          onPressed: () {
                            // Navigate to trip history screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const TripHistoryScreen()),
                            );
                          },
                        ),
                        _buildCircleButton(
                          icon: Icons.card_giftcard,
                          label: 'Promotions',
                          onPressed: () {
                            // Navigate to promotions screen
                          },
                        ),
                        _buildCircleButton(
                          icon: Icons.support_agent,
                          label: 'Support',
                          onPressed: () {
                            // Navigate to support screen or show support dialog
                          },
                        ),
                      ],
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
  
  Widget _buildDestinationOptions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDestinationCard(
                icon: Icons.home,
                title: 'Home',
                address: '123 Main St',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDestinationCard(
                icon: Icons.work,
                title: 'Work',
                address: '456 Office Blvd',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDestinationCard(
                icon: Icons.shopping_bag,
                title: 'Shopping',
                address: 'City Mall',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDestinationCard(
                icon: Icons.restaurant,
                title: 'Restaurant',
                address: 'Food Street',
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildDestinationCard({
    required IconData icon,
    required String title,
    required String address,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              address,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCircleButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.amber.shade800,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}