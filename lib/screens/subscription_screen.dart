import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String selectedPlan = 'monthly'; // 'monthly' or 'annual'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Image at the very top (no SafeArea)
          Stack(
            children: [
              // Full-width Image extending to the very top
              Image.asset(
                'assets/images/Subscription_image.png',
                width: double.infinity,
                fit: BoxFit.contain,
              ),
              // Close button overlay with SafeArea padding
              SafeArea(
                child: Positioned(
                  top: 12.0,
                  left: 24.0,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Rest of the content with SafeArea
          Expanded(
            child: SafeArea(
              top: false, // Don't add top padding since image handles it
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),

                    // Title - positioned to overlap the image
                    Transform.translate(
                      offset: const Offset(0, -80), // Move up to overlap image
                      child: Column(
                        children: [
                          Text(
                            'Try Noteable Pro',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Geist',
                              color: Colors.black,
                              height: 1.2,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                'for ',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Geist',
                                  color: Colors.black,
                                  height: 1.2,
                                ),
                              ),
                              Column(
                                children: [
                                  Text(
                                    'free',
                                    style: GoogleFonts.fuzzyBubbles(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E44FF),
                                      height: 1.2,
                                    ),
                                  ),
                                  Transform.translate(
                                    offset: Offset(0, -3),
                                    child: Container(
                                      width:
                                          52, // Adjust width to match text width
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Color(0xFF1E44FF),
                                        borderRadius:
                                            BorderRadius.circular(1.5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Features
                    Transform.translate(
                      offset: const Offset(0,
                          -12), // Move features up to achieve 64px gap from title
                      child: Column(
                        children: [
                          Center(
                            child: _buildFeatureRow(
                              iconAsset: 'assets/icons/unlimited.svg',
                              title: 'Unlimited recordings',
                              description:
                                  'Record and create as many\nentries as you want.',
                            ),
                          ),
                          const SizedBox(height: 36),
                          Center(
                            child: _buildFeatureRow(
                              iconAsset: 'assets/icons/safe.svg',
                              title: 'Your data stays with you',
                              description:
                                  'All your data are saved offline\n— no cloud, no tracking.',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Pricing options
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => selectedPlan = 'monthly'),
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: selectedPlan == 'monthly'
                                    ? const Color(0xFF1C1A1B)
                                    : const Color(0xFFF3F4F7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13.5,
                                  vertical: 9.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F7),
                                  borderRadius: BorderRadius.circular(13.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Monthly',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Geist',
                                        color: Colors.black,
                                      ),
                                    ),
                                    Text(
                                      '₹199',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Geist',
                                        color: const Color(0xFF464347),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => selectedPlan = 'annual'),
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: selectedPlan == 'annual'
                                    ? Colors.black
                                    : const Color(0xFFF3F4F7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Container(
                                padding: const EdgeInsets.only(
                                  top: 9.5,
                                  bottom: 9.5,
                                  left: 13.5,
                                  right: 9.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F7),
                                  borderRadius: BorderRadius.circular(13.5),
                                ),
                                child: Stack(
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Annual',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Geist',
                                            color: Colors.black,
                                          ),
                                        ),
                                        Text(
                                          '₹999',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'Geist',
                                            color: const Color(0xFF464347),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          '-58%',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Geist',
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
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Start trial button
                    Container(
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () {
                            // TODO: Implement subscription logic
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Subscription flow coming soon!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Start 3-day free trial',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Geist',
                                    height: 1.5,
                                  ),
                                ),
                                Text(
                                  'No payment now!',
                                  style: TextStyle(
                                    color: Color(0xFFABABAB),
                                    fontSize: 14,
                                    fontFamily: 'Geist',
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 0),

                    // Restore purchase
                    TextButton(
                      onPressed: () {
                        // TODO: Implement restore purchase logic
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Restore purchase coming soon!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text(
                        'Restore Purchase',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Geist',
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

  Widget _buildFeatureRow({
    required String iconAsset,
    required String title,
    required String description,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: SvgPicture.asset(
            iconAsset,
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              Colors.black,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 32),
        SizedBox(
          width: 280, // Constrain text width
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Geist',
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 18,
                  fontFamily: 'Geist',
                  color: Color(0xFF7F7C7F),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
