# Hover-Dock

Hover-Dock is a macOS utility that enhances your Dock experience by displaying live window previews when you hover over open applications. It brings Windows-style taskbar previews to macOS, allowing for better window management and navigation.

## Features

- **Live Window Previews**: Hover over any Dock icon to see thumbnails of all open windows for that application.
- **Smart Positioning**: Automatically detects your Dock position (Bottom, Left, or Right) and tiles previews accordingly (Horizontal or Vertical).
- **Window Management**:
  - **Activate**: Click a preview to bring the window to the front.
  - **Minimize**: Quickly minimize windows directly from the preview.
  - **Close**: Close windows without leaving the preview.
- **Native Look & Feel**: Designed with native macOS blur effects and animations to blend seamlessly with your system.
- **Performance**: Uses modern `ScreenCaptureKit` for efficient, high-performance thumbnail capture.

## Requirements

- macOS 12.3 or later (Required for `ScreenCaptureKit`)
- Screen Recording Permission (Required to capture window thumbnails)

## Installation

1. Clone the repository.
2. Open `Hover-Dock.xcodeproj` in Xcode.
3. Build and Run.
4. Grant **Screen Recording** permission when prompted (or manually in System Settings > Privacy & Security > Screen Recording).

## Usage

Simply hover your mouse cursor over any running application in the Dock. A panel will appear showing all non-fullscreen windows for that app. Move your mouse into the panel to interact with the previews.

