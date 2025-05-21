import 'dart:math' as math;
import 'dart:math'; // Redundant import, math is already imported as math
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

    _roadController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _taxiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _headlightController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

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

  // Helper widget for creating glass-like windows
  Widget _buildGlassWindow({
    required double width,
    required double height,
    BorderRadius? borderRadius,
    CustomClipper<Path>? clipper,
    Matrix4? transform,
    Color glassColor = const Color(0xAA607D8B), // Bluish-grey glass tint
    Color borderColor = Colors.black38,
  }) {
    Widget glass = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: glassColor,
        borderRadius: clipper == null ? borderRadius : null,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.15),
            glassColor.withOpacity(0.5),
            Colors.black.withOpacity(0.2),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
        border: Border.all(color: borderColor, width: 0.75),
      ),
    );

    if (clipper != null) {
      glass = ClipPath(clipper: clipper, child: glass);
    } else if (borderRadius != null) {
      glass = ClipRRect(borderRadius: borderRadius, child: glass);
    }
    
    if (transform != null) {
      glass = Transform(transform: transform, child: glass);
    }

    return glass;
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
    // Dimensions for car parts
    const double carBodyWidth = 95;
    const double carBodyHeight = 30; // Lowered for better proportion with cabin
    const double cabinWidth = 70;
    const double cabinHeight = 22; // Adjusted cabin height
    const double cabinTopOffset = 3; // How much cabin sits above the lower body's top
    
    // Windshield properties
    const double windshieldHeight = cabinHeight - 2;
    const double windshieldWidth = 20; // Width at the top of windshield

    // Rear window properties
    const double rearWindowHeight = cabinHeight - 4;
    const double rearWindowWidth = 18;


    return SizedBox(
      width: 120,
      height: 65,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Enhanced car shadow
          Positioned(
            bottom: -4,
            child: AnimatedBuilder(
              animation: _taxiMovement,
              builder: (context, child) {
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

          // Undercarriage
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

          // Main LOWER body part
          Positioned(
            bottom: 12, // Position of the lower body
            child: Container(
              width: carBodyWidth,
              height: carBodyHeight,
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
                    Colors.amber.shade400,
                    Colors.amber.shade500,
                    Colors.amber.shade600,
                    Colors.amber.shade700,
                  ],
                ),
              ),
            ),
          ),
          
          // Hood of car (front part) - relative to the lower body position
          Positioned(
            right: (120 - carBodyWidth) / 2 - 2, // Align with carBody edge
            bottom: 12, // Same level as carBody bottom edge
            child: Container(
              width: 25, // Width of the hood extending forward
              height: carBodyHeight * 0.85, // Slightly lower than main body
              decoration: BoxDecoration(
                color: Colors.amber.shade500,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(15),
                  bottomRight: Radius.circular(8),
                  topLeft: Radius.circular(5), // Slight curve towards body
                  bottomLeft: Radius.circular(3),
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

          // Trunk of car (back part) - relative to the lower body position
          Positioned(
            left: (120 - carBodyWidth) / 2 - 2, // Align with carBody edge
            bottom: 12, // Same level as carBody bottom edge
            child: Container(
              width: 20, // Width of the trunk extending backward
              height: carBodyHeight * 0.85, // Slightly lower than main body
              decoration: BoxDecoration(
                color: Colors.amber.shade500,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(8),
                  topRight: Radius.circular(5), // Slight curve towards body
                  bottomRight: Radius.circular(3),
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

          // Cabin Structure (Roof and Pillars area)
          Positioned(
            // Position cabin on top of the main lower body
            bottom: 12 + carBodyHeight - cabinTopOffset, 
            left: (120 - cabinWidth) / 2, // Centered
            child: Container(
              width: cabinWidth,
              height: cabinHeight,
              decoration: BoxDecoration(
                color: Colors.amber.shade500, // Same as body or slightly different
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
                 gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.amber.shade300,
                    Colors.amber.shade600,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 3,
                    offset: const Offset(0, -1), // Shadow upwards slightly for effect
                  ),
                ],
              ),
              // Child for the taxi sign, now inside the cabin structure for better layering
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1.0), // Adjust sign position on cabin
                  child: Container(
                      width: cabinWidth * 0.8, // Sign width relative to cabin
                      height: cabinHeight * 0.4, // Sign height
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 1, spreadRadius: 0,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'ISMAIL Taxi',
                          style: TextStyle(
                            fontSize: 8, // Adjusted size
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
          ),

          // Front Windshield
          Positioned(
            bottom: 12 + carBodyHeight - cabinTopOffset, // Base aligned with cabin bottom
            right: (120 - cabinWidth) / 2 - windshieldWidth + cabinWidth -3, // Connects to cabin front-right
            child: _buildGlassWindow(
              width: windshieldWidth,
              height: windshieldHeight,
              clipper: FrontWindshieldClipper(),
            ),
          ),
          
          // Rear Window
          Positioned(
            bottom: 12 + carBodyHeight - cabinTopOffset + 1, // Base aligned with cabin bottom
            left: (120 - cabinWidth) / 2 - rearWindowWidth + cabinWidth -3, // Connects to cabin front-left (this needs to be on the other side)
             // Correction: Position from the left edge of the cabin for rear window
            // left: (120 - cabinWidth) / 2, // Start at cabin's left edge
            // child: Transform(
            //   alignment: Alignment.center,
            //   transform: Matrix4.rotationY(math.pi), // Flip if needed, or adjust clipper
              child: _buildGlassWindow(
                width: rearWindowWidth,
                height: rearWindowHeight,
                clipper: RearWindowClipper(), // Potentially a different clipper or transformed
              // ),
            ),
          ),
          // Corrected Rear Window Position:
           Positioned(
            bottom: 12 + carBodyHeight - cabinTopOffset + 1,
            left: (120 - cabinWidth) / 2, // Aligns with the left of the cabin structure
            child: _buildGlassWindow(
              width: rearWindowWidth,
              height: rearWindowHeight,
              clipper: RearWindowClipper(),
            ),
          ),


          // Side Windows (within the cabin structure)
          // Positioned relative to the cabin container's coordinate space,
          // or absolutely if cabin is just a visual backdrop.
          // For simplicity, let's position them absolutely for now, aligned with the cabin.
          Positioned(
            bottom: 12 + carBodyHeight - cabinTopOffset + 3, // Vertically centered in cabin
            left: (120-cabinWidth)/2 + 22, // Adjust based on cabin width and desired pillar size
            child: _buildGlassWindow(
              width: cabinWidth * 0.22, // Width of side window
              height: cabinHeight * 0.6, // Height of side window
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Positioned(
            bottom: 12 + carBodyHeight - cabinTopOffset + 3,
            left: (120-cabinWidth)/2 + 4, // Second side window
            child: _buildGlassWindow(
              width: cabinWidth * 0.22,
              height: cabinHeight * 0.6,
              borderRadius: BorderRadius.circular(3),
            ),
          ),


          // Taxi sign on top (original position, adjust if needed with new cabin)
          Positioned(
            top: 0, // Adjust this based on new cabin height
            child: AnimatedBuilder(
              animation: _headlightController,
              builder: (context, child) {
                return Container(
                  width: 70,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 221, 189, 9),
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
                      'Ismeal TAXI',
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

          // // Windshield Wipers (simple lines)
          // Positioned(
          //   bottom: 12 + carBodyHeight - cabinTopOffset + windshieldHeight - 5, // On the windshield
          //   right: (120 - cabinWidth) / 2 - windshieldWidth + cabinWidth - 3 + 5, // Approx center-right of windshield
          //   child: Transform.rotate(
          //     angle: -0.3, // Angle of wiper
          //     child: Container(width: 10, height: 1.5, color: Colors.black54),
          //   ),
          // ),
          // Positioned(
          //   bottom: 12 + carBodyHeight - cabinTopOffset + windshieldHeight - 5,
          //   right: (120 - cabinWidth) / 2 - windshieldWidth + cabinWidth - 3 + 12, // Second wiper
          //   child: Transform.rotate(
          //     angle: -0.35,
          //     child: Container(width: 10, height: 1.5, color: Colors.black54),
          //   ),
          // ),


          // Door handles (adjust Y position based on new body/cabin line)
          Positioned(
            top: 28, // Approximate mid-point of the lower body, adjust as needed
            left: 35,
            child: Container(
              width: 6, height: 2,
              decoration: BoxDecoration(color: const Color.fromARGB(255, 100, 100, 100), borderRadius: BorderRadius.circular(1)),
            ),
          ),
          Positioned(
            top: 28,
            right: 40,
            child: Container(
              width: 6, height: 2,
              decoration: BoxDecoration(color: const Color.fromARGB(255, 100, 100, 100), borderRadius: BorderRadius.circular(1)),
            ),
          ),
          
          // Side mirrors
          Positioned(
            top: 22, // Near top of cabin/door line
            right: 15,
            child: Container(width: 3, height: 6, decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(1))),
          ),
          Positioned(
            top: 22,
            left: 15,
            child: Container(width: 3, height: 6, decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(1))),
          ),
          
          // License plate front & rear (original)
          Positioned(
            bottom: 6, right: 2,
            child: Container(
              width: 12, height: 5,
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black, width: 0.5)),
              child: const Center(child: Text('IS', style: TextStyle(fontSize: 3, fontWeight: FontWeight.bold))),
            ),
          ),
          Positioned(
            bottom: 6, left: 2,
            child: Container(
              width: 12, height: 5,
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black, width: 0.5)),
              child: const Center(child: Text('MAIL', style: TextStyle(fontSize: 3, fontWeight: FontWeight.bold))),
            ),
          ),
          
          // Bumpers (original)
          Positioned(
            bottom: 4, right: 2,
            child: Container(
              width: 16, height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4), topLeft: Radius.circular(1), bottomLeft: Radius.circular(1)),
              ),
            ),
          ),
          Positioned(
            bottom: 4, left: 2,
            child: Container(
              width: 16, height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4), topRight: Radius.circular(1), bottomRight: Radius.circular(1)),
              ),
            ),
          ),
          
          // Headlights & Taillights (original, check positioning with new body if needed)
           Positioned(
            bottom: 15, // Adjusted to be on the lower body part
            right: 2,
            child: AnimatedBuilder(
              animation: _headlightController,
              builder: (context, child) {
                // ... (original headlight code)
                 return Stack(
                  children: [
                    Positioned(
                      right: -5,
                      child: Container(
                        width: 20, height: 10,
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [Colors.yellow.withOpacity(0.7 * _headlightController.value), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade700, width: 1),
                        boxShadow: [BoxShadow(color: Colors.yellow.withOpacity(0.5 * _headlightController.value), blurRadius: 8, spreadRadius: 2 * _headlightController.value)],
                      ),
                      child: Center(child: Container(width: 4, height: 4, decoration: BoxDecoration(color: Colors.yellow.shade100, shape: BoxShape.circle))),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            bottom: 15, // Adjusted
            left: 2,
            child: AnimatedBuilder(
              animation: _taxiMovement,
              builder: (context, child) {
                // ... (original taillight code)
                final braking = (_taxiMovement.value.abs() < 0.05) ? 1.0 : 0.5;
                return Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: Colors.red.shade700, shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade700, width: 1),
                    boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.3 * braking), blurRadius: 5, spreadRadius: 1 * braking)],
                  ),
                  child: Center(child: Container(width: 3, height: 3, decoration: BoxDecoration(color: Colors.red.shade400, shape: BoxShape.circle))),
                );
              },
            ),
          ),
          
          // Checkerboard pattern (Adjust Y position if body height changed significantly)
          Positioned(
            bottom: 12 + carBodyHeight - 12, // On the lower body
            child: SizedBox( // Changed to SizedBox for alignment
              width: carBodyWidth,
              height: 6,
              child: Row(
                children: List.generate(10, (index) {
                  return Expanded( // Use Expanded for even distribution
                    child: Container(
                      height: 6,
                      color: index % 2 == 0 ? Colors.black : Colors.amber.shade300,
                    ),
                  );
                }),
              ),
            ),
          ),
          
          // Door lines (Adjust Y and height based on new body/cabin)
          Positioned(
            top: 26, // Adjusted
            left: 40,
            child: Container(width: 1.5, height: carBodyHeight * 0.7, color: Colors.black45),
          ),
          Positioned(
            top: 26, // Adjusted
            right: 42,
            child: Container(width: 1.5, height: carBodyHeight * 0.7, color: Colors.black45),
          ),
          
          // Wheels & Wheel arches (original, check Y position if overall car base moved)
          Positioned(bottom: 0, right: 20, child: _buildDetailedWheel()),
          Positioned(bottom: 0, left: 20, child: _buildDetailedWheel()),
          Positioned(
            bottom: 13, right: 20,
            child: Container(width: 22, height: 6, decoration: BoxDecoration(color: const Color.fromARGB(255, 15, 15, 15), borderRadius: const BorderRadius.vertical(top: Radius.circular(12)))),
          ),
          Positioned(
            bottom: 13, left: 20,
            child: Container(width: 22, height: 6, decoration: BoxDecoration(color: const Color.fromARGB(255, 15, 15, 15), borderRadius: const BorderRadius.vertical(top: Radius.circular(12)))),
          ),
          // REMOVED: Decorative green stripe on the top of the car
        ],
      ),
    );
  }

  Widget _buildDetailedWheel() {
    return AnimatedBuilder(
      animation: _roadController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _roadController.value * 2 * math.pi * 2, // Increased rotation speed for more visible spin
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
                  // Tire texture
                  ...List.generate(8, (index) {
                    final angle = (index / 8) * 2 * math.pi;
                    return Positioned(
                      left: 7.5 + (math.cos(angle) * 7),
                      top: 7.5 + (sin(angle) * 7),
                      child: Container(width: 1.5, height: 1.5, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
                    );
                  }),
                  // Hubcap
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300, shape: BoxShape.circle,
                      boxShadow: [const BoxShadow(color: Colors.black38, blurRadius: 1, offset: Offset(0, 1))],
                    ),
                    child: Center(child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle))),
                  ),
                  // Hubcap details - spokes
                  ...List.generate(4, (index) {
                    final angle = (index / 4) * 2 * math.pi;
                    return Transform.rotate(angle: angle, child: Container(width: 1, height: 8, color: Colors.grey.shade700));
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

// NEW/MODIFIED Custom Clippers for Windows

class FrontWindshieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0); // Top-left of windshield glass
    path.lineTo(size.width, 0); // Top-right
    path.lineTo(size.width * 0.85, size.height); // Bottom-right (slanted inwards)
    path.lineTo(size.width * 0.15, size.height); // Bottom-left (slanted inwards)
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class RearWindowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.15, 0); // Top-left (slanted inwards)
    path.lineTo(size.width * 0.85, 0); // Top-right (slanted inwards)
    path.lineTo(size.width, size.height); // Bottom-right
    path.lineTo(0, size.height); // Bottom-left
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}