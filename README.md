**WebSiphon** is a lightweight, high-performance native macOS utility designed to download entire websites asynchronously for offline browsing. Inspired by classic archiving tools like SiteSucker, WebSiphon targets modern macOS standards, utilizing an intuitive SwiftUI interface backed by a swift concurrency architecture.

<p align="center">
  <img src="https://raw.githubusercontent.com/ArmandIsCoding/WebSiphon/main/WebSiphonMockup.png" alt="WebSiphon Interface Preview" width="700">
</p>

## ✨ Features

- **100% Native Architecture:** Built from the ground up using **SwiftUI**, delivering a fluid, pixel-perfect macOS experience with Dark Mode support.
- **Asynchronous Engine:** Powered by Swift Concurrency (`async/await` and Actors) to handle multi-threaded file downloading without locking the main UI thread.
- **Local Sandbox & Privacy First:** All downloads and operations occur locally on your Mac. No external analytics, no telemetry, no cloud servers involved.
- **Smart Site Sandboxing:** Automatically provisions dedicated structured directories for every unique domain you siphon.
- **Real-Time Diagnostics:** Live `Table` monitoring displaying execution levels, download status, file paths, sizing metadata, and granular progress.

## 🛠️ Tech Stack & Architecture

WebSiphon modernizes offline web crawling using Apple's latest software development practices:
- **UI Framework:** SwiftUI (Declarative UI with native macOS scaling)
- **Data Persistence:** SwiftData (Modern object management for download states and configuration targets)
- **Concurrency:** Swift Tasks & Structured Concurrency for fast, efficient background URL session pooling.

---

## 🚀 Getting Started

### Prerequisites
- macOS 14.0 (Sonoma) or higher.
- Xcode 15.0+ (with Command Line Tools installed).

### Installation & Compilation
Clone the repository and run it locally via Xcode:

```bash
# Clone the repository
git clone [https://github.com/ArmandIsCoding/WebSiphon.git](https://github.com/ArmandIsCoding/WebSiphon.git)

# Navigate into the project folder
cd WebSiphon

# Open the project in Xcode
open WebSiphon.xcodeproj

1. Once open, select your destination target as My Mac.
2. Press Cmd + R to build and run the application instantly.
📈 Roadmap
• [x] Initial SwiftUI Layout & Native Tables
• [x] Dynamic directory provisioning per Target URL
• [x] Asynchronous Single-Page HTML Harvesting
• [ ] Deep Recursive Crawling (Asset Extraction: CSS, JS, Images)
• [ ] Local URL Rewriting (Transforming hyperlinks into relative offline paths)
• [ ] Custom User-Agent and Throttle controls in Settings

📄 License
Distributed under the MIT License. See LICENSE for more information.
<p align="center">
Generated with ❤️ for the macOS indie dev community.
</p>
