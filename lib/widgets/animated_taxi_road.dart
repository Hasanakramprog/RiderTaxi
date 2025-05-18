import 'dart:math' as math;
import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedTaxiRoad extends StatefulWidget {
  const AnimatedTaxiRoad({Key? key}) : super(key: key);

  @override
  State<AnimatedTaxiRoad> createState() => _AnimatedTaxiRoadState();
}

class _AnimatedTaxiRoadState extends State<AnimatedTaxiRoad> with TickerProviderStateMixin {
  late AnimationController _taxiController;
  late AnimationController _roadController;
  late AnimationController _headlightController;
  late Animation<double> _taxiMovement;
  late Animation<double> _headlightOpacity;
  
  @override
  void initState() {
    super.initState();
    
    // Road animation controller - continuous scrolling effect
    _roadController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // Taxi movement controller - moves the taxi around
    _taxiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    
    // Headlight flashing controller
    _headlightController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    // Complex taxi movement animation
    _taxiMovement = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.2, end: 0.2)
          .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.2, end: -0.2)
          .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]).animate(_taxiController);
    
    // Headlight animation
    _headlightOpacity = Tween<double>(begin: 0.5, end: 1.0)
        .animate(_headlightController);
  }
  
  @override
  void dispose() {
    _taxiController.dispose();
    _roadController.dispose();
    _headlightController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        children: [
          // Background sky with gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.blue.shade200,
                  Colors.blue.shade300,
                ],
              ),
            ),
          ),
          
          // Buildings in background
          Positioned(
            bottom: 60, // Just above the road
            left: 0,
            right: 0,
            height: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(10, (index) {
                final height = 30.0 + (math.Random().nextDouble() * 40);
                final width = 20.0 + (math.Random().nextDouble() * 30);
                return Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 5),
                      // Windows
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                            ),
                            itemCount: 6,
                            itemBuilder: (context, i) => Container(
                              color: math.Random().nextBool()
                                  ? Colors.yellow.withOpacity(0.7)
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          
          // Clouds - floating by
          ...List.generate(3, (index) {
            final offset = index * 120.0;
            return AnimatedBuilder(
              animation: _roadController,
              builder: (context, child) {
                return Positioned(
                  top: 20.0 + (index * 8),
                  left: (((_roadController.value * 500) + offset) % (size.width + 100)) - 50,
                  child: Opacity(
                    opacity: 0.7,
                    child: Icon(
                      Icons.cloud,
                      size: 50 + (index * 10),
                      color: Colors.white,
                    ),
                  ),
                );
              },
            );
          }),
          
          // The road
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 60,
            child: Container(
              color: Colors.grey.shade800,
              child: Column(
                children: [
                  const SizedBox(height: 58),
                  // Curb
                  Container(
                    height: 2,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
          
          // Road markings - scrolling by
          AnimatedBuilder(
            animation: _roadController,
            builder: (context, child) {
              return Stack(
                children: List.generate(6, (index) {
                  final offset = index * 100.0;
                  return Positioned(
                    bottom: 30,
                    left: (((_roadController.value * 300) + offset) % (size.width + 100)) - 50,
                    child: Container(
                      height: 8,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          
          // The taxi car with animation
          AnimatedBuilder(
            animation: _taxiMovement,
            builder: (context, child) {
              return Positioned(
                bottom: 50,
                left: size.width * 0.4,
                child: Transform.translate(
                  offset: Offset(0, _taxiMovement.value * 10),
                  child: Transform.scale(
                    scale: 1.0 + (_taxiMovement.value * 0.05).abs(),
                    child: _buildTaxi(),
                  ),
                ),
              );
            },
          ),
          
          // Reflection of car on the road
          AnimatedBuilder(
            animation: _taxiMovement,
            builder: (context, child) {
              return Positioned(
                bottom: 4, // Just above bottom
                left: size.width * 0.4 + 10,
                child: Transform.scale(
                  scaleX: 1.0,
                  scaleY: -0.4, // Flip and squish for reflection
                  child: Opacity(
                    opacity: 0.3, // Semi-transparent
                    child: Transform.translate(
                      offset: Offset(0, _taxiMovement.value * 10),
                      child: SizedBox(
                        width: 80,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.amber.withOpacity(0.4),
                                Colors.amber.withOpacity(0.1),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildTaxi() {
    return SizedBox(
      width: 120,
      height: 65,  // Slightly taller for better proportions
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Enhanced car shadow with dynamic sizing
          Positioned(
            bottom: -4,
            child: AnimatedBuilder(
              animation: _taxiMovement,
              builder: (context, child) {
                // Shadow changes shape based on car movement
                return Container(
                  width: 100 + (_taxiMovement.value * 8).abs(),
                  height: 14 - (_taxiMovement.value * 4).abs(),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          // Undercarriage (dark shadow under car body)
          Positioned(
            bottom: 6,
            child: Container(
              width: 94,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          
          // Main body with unified solid shape (no windows)
          Container(
            width: 95,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.1, 0.3, 0.7, 1.0],
                colors: [
                  Colors.amber.shade400,  // Light reflection at top
                  Colors.amber.shade500,  // Main body color
                  Colors.amber.shade600,  // Shadow area
                  Colors.amber.shade700,  // Bottom shadow
                ],
              ),
            ),
          ),
          
          // Hood of car (front part)
          Positioned(
            right: 0,
            bottom: 12,
            child: Container(
              width: 25,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.amber.shade500,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(15),
                  bottomRight: Radius.circular(8),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.amber.shade400,
                    Colors.amber.shade600,
                  ],
                ),
              ),
            ),
          ),
          
          // Trunk of car (back part)
          Positioned(
            left: 0,
            bottom: 12,
            child: Container(
              width: 20,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.amber.shade500,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(8),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.amber.shade400,
                    Colors.amber.shade600,
                  ],
                ),
              ),
            ),
          ),
          
          // Taxi roof with company name (modified to be integrated with the body)
          Positioned(
            top: 2,
            child: Container(
              width: 70,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.amber.shade500,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.amber.shade300,  // Light at top
                    Colors.amber.shade600,  // Darker at bottom
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 1,
                        spreadRadius: 0,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'ISMAIL Taxi',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Door handles
          Positioned(
            top: 22,
            left: 35,
            child: Container(
              width: 6,
              height: 2,
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 170, 31, 31),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          
          Positioned(
            top: 22,
            right: 40,
            child: Container(
              width: 6,
              height: 2,
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 177, 78, 78),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          
          // Side mirrors
          Positioned(
            top: 20,
            right: 15,
            child: Container(
              width: 3,
              height: 6,
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 221, 14, 14),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          
          Positioned(
            top: 20,
            left: 15,
            child: Container(
              width: 3,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          
          // Taxi sign on top with glowing effect
          Positioned(
            top: -10,
            child: AnimatedBuilder(
              animation: _headlightController,
              builder: (context, child) {
                return Container(
                  width: 28,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.black87, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.3 + (_headlightController.value * 0.2)),
                        blurRadius: 8,
                        spreadRadius: 1 + (_headlightController.value * 1),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'TAXI',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // License plate front
          Positioned(
            bottom: 6,
            right: 2,
            child: Container(
              width: 12,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 0.5),
              ),
              child: const Center(
                child: Text(
                  'IS',
                  style: TextStyle(
                    fontSize: 3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          
          // License plate rear
          Positioned(
            bottom: 6,
            left: 2,
            child: Container(
              width: 12,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 0.5),
              ),
              child: const Center(
                child: Text(
                  'MAIL',
                  style: TextStyle(
                    fontSize: 3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          
          // Front bumper with more realistic shape
          Positioned(
            bottom: 4,
            right: 2,
            child: Container(
              width: 16,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                  topLeft: Radius.circular(1),
                  bottomLeft: Radius.circular(1),
                ),
              ),
            ),
          ),
          
          // Rear bumper with more realistic shape
          Positioned(
            bottom: 4,
            left: 2,
            child: Container(
              width: 16,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                  topRight: Radius.circular(1),
                  bottomRight: Radius.circular(1),
                ),
              ),
            ),
          ),
          
          // Headlights with dynamic glow
          Positioned(
            bottom: 15,
            right: 2,
            child: AnimatedBuilder(
              animation: _headlightController,
              builder: (context, child) {
                return Stack(
                  children: [
                    // Light beam effect
                    Positioned(
                      right: -5,
                      child: Container(
                        width: 20,
                        height: 10,
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.yellow.withOpacity(0.7 * _headlightController.value),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Headlight itself
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade700, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.yellow.withOpacity(0.5 * _headlightController.value),
                            blurRadius: 8,
                            spreadRadius: 2 * _headlightController.value,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.yellow.shade100,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          
          // Taillights with realistic brake effect
          Positioned(
            bottom: 15,
            left: 2,
            child: AnimatedBuilder(
              animation: _taxiMovement,
              builder: (context, child) {
                // Brakes light up more when the taxi slows down (changes direction)
                final braking = (_taxiMovement.value.abs() < 0.05) ? 1.0 : 0.5;
                return Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade700, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3 * braking),
                        blurRadius: 5,
                        spreadRadius: 1 * braking,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.red.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Classic taxi checkerboard pattern
          Positioned(
            bottom: 18,
            child: Container(
              width: 95,
              height: 6,
              child: Row(
                children: List.generate(10, (index) {
                  return Container(
                    width: 9.5,
                    height: 6,
                    color: index % 2 == 0 ? Colors.black : Colors.amber.shade300,
                  );
                }),
              ),
            ),
          ),
          
          // Door lines - more detailed
          Positioned(
            top: 10,
            left: 40,
            child: Container(
              width: 1.5,
              height: 24,
              color: Colors.black45,
            ),
          ),
          
          Positioned(
            top: 10,
            right: 42,
            child: Container(
              width: 1.5,
              height: 24,
              color: Colors.black45,
            ),
          ),
          
          // Enhanced front wheel with better detail
          Positioned(
            bottom: 0,
            right: 20,
            child: _buildDetailedWheel(),
          ),
          
          // Enhanced back wheel with better detail
          Positioned(
            bottom: 0,
            left: 20,
            child: _buildDetailedWheel(),
          ),
          
          // Wheel arches for more depth
          Positioned(
            bottom: 13,
            right: 20,
            child: Container(
              width: 22,
              height: 6,
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 15, 15, 15),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
          ),
          
          Positioned(
            bottom: 13,
            left: 20,
            child: Container(
              width: 22,
              height: 6,
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 15, 15, 15),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
          ),
          
          // Adding a decorative stripes on the top of the car
          Positioned(
            top: 8,
            child: Container(
              width: 65,
              height: 4,
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 0, 255, 0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // More detailed wheel with realistic hubcap and tire texturing
  Widget _buildDetailedWheel() {
    return AnimatedBuilder(
      animation: _roadController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _roadController.value * 2 * math.pi * 2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 2,
                  spreadRadius: 1,
                  offset: const Offset(0, 1)
                ),
              ],
            ),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Tire texture (small dots around the outer edge)
                  ...List.generate(8, (index) {
                    final angle = (index / 8) * 2 * math.pi;
                    return Positioned(
                      left: 7.5 + (math.cos(angle) * 7),
                      top: 7.5 + (sin(angle) * 7),
                      child: Container(
                        width: 1.5,
                        height: 1.5,
                        decoration: const BoxDecoration(
                          color: Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                  // Hubcap
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      shape: BoxShape.circle,
                      boxShadow: [
                        const BoxShadow(
                          color: Colors.black38,
                          blurRadius: 1,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  // Hubcap details - spokes
                  ...List.generate(4, (index) {
                    final angle = (index / 4) * 2 * math.pi;
                    return Transform.rotate(
                      angle: angle,
                      child: Container(
                        width: 1,
                        height: 8,
                        color: Colors.grey.shade700,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Add these classes outside of your widget class for window shapes
class WindshieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.3);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width, size.height * 0.3);
    path.quadraticBezierTo(size.width / 2, 0, 0, size.height * 0.3);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class BackWindowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.3);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width, size.height * 0.3);
    path.quadraticBezierTo(size.width / 2, 0, 0, size.height * 0.3);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}