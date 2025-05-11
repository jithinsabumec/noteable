# Zelo

A Flutter project using the Geist font for a modern, clean UI.

## Getting Started

This project uses Geist font from Vercel.

### Font Installation

To install the Geist font:

1. Run `npm install geist` to download the font package
2. Copy the font files to the `fonts` directory:
   ```
   mkdir -p fonts
   cp node_modules/geist/dist/fonts/geist-sans/Geist-Regular.ttf fonts/
   cp node_modules/geist/dist/fonts/geist-sans/Geist-Medium.ttf fonts/
   cp node_modules/geist/dist/fonts/geist-sans/Geist-Bold.ttf fonts/
   ```
3. Update your `pubspec.yaml` to include the font:
   ```yaml
   fonts:
     - family: Geist
       fonts:
         - asset: fonts/Geist-Regular.ttf
         - asset: fonts/Geist-Medium.ttf
           weight: 500
         - asset: fonts/Geist-Bold.ttf
           weight: 700
   ```
4. Run `flutter pub get` to update your dependencies

## Flutter Resources

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
