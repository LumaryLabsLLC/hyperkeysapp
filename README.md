# HyperKeys

A macOS menu bar app that turns any key into a **Hyper Key** — giving you instant access to app launching, window management, and menu item shortcuts, all from a single modifier.

![Keyboard View](pics/image1.png)

## Getting Started

1. Download `HyperKeys.zip` from [Releases](https://github.com/LumaryLabsLLC/hyperkeysapp/releases)
2. Unzip and move `HyperKeys.app` to `/Applications`
3. Open the app — it appears in your menu bar
4. Grant **Accessibility** and **Input Monitoring** permissions when prompted
5. Double-tap the Hyper Key to open settings at any time

> **Note:** Since the app is not notarized, macOS may block it on first launch. Right-click the app → **Open** → **Open** to bypass Gatekeeper.

## How It Works

HyperKeys remaps a single key (default: **Caps Lock**) into a **Hyper Key**. Quick-tap it and the original character still types. Hold it down and press any other key to trigger a custom action.

## Features

### App Launcher

Click any key on the keyboard view to bind it. In the **Apps** tab, select one or more apps to launch with a single shortcut. When selecting multiple apps, you can assign each a window position — one keypress launches them all, tiled exactly where you want.

![App Bindings](pics/image2.png)

![App Group with Window Positions](pics/image5.png)

### Window Management

In the **Window** tab, pick a tiling position for the focused window. Supports halves, quarters, thirds, sixths, fourths, full screen, center, and more. Configure the gap between tiled windows in **Settings → Window Management**.

![Window Positions](pics/image3.png)

### Menu Item Shortcuts

In the **Menu Item** tab, select any running app to browse its menu bar. Pick any menu action and bind it to your Hyper Key combo — no need to memorize deep menu paths.

![Menu Item Bindings](pics/image4.png)

### Profiles

Create multiple binding profiles in the **Profiles** tab. Switch between them from the menu bar. Set up per-app automatic switching so your bindings adapt to the frontmost application.

### Changing the Hyper Key

Go to **Settings → Hyper Key** and click **Change**, then press the key you want to use. Popular choices: Caps Lock (default), backtick, or right Option.

### Double-Tap

Double-tap the Hyper Key to toggle the settings window open or closed.

## Requirements

- macOS 15.0+
- Accessibility permissions (window management and menu bar reading)
- Input Monitoring permissions (key event tap)

## Building from Source

```
git clone https://github.com/LumaryLabsLLC/hyperkeysapp.git
cd hyperkeysapp
open HyperKeys.xcworkspace
```

Build and run the **HyperKeys** scheme in Xcode 16+.

## License

MIT

## Links

- [GitHub](https://github.com/LumaryLabsLLC/hyperkeysapp)
- [Lumary Labs](https://lumarylabs.com/)
