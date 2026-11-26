<p align="center">
  <img src="Assets/icon-256.png" width="160" alt="Velvet icon">
</p>

<h1 align="center">Velvet</h1>

<p align="center">A native macOS YouTube Music player — SwiftUI, no Electron.</p>

## Features

- **Discover** — recently played, on repeat, your top artists, suggestions, and the YouTube Music home feed
- **Search** — songs, videos, albums, artists, and playlists with live suggestions
- **Liked Songs** — your full library, with pagination
- **Picture-in-Picture** — a draggable floating mini-player
- **Fast artwork** — a moving-window image cache with scroll prefetch, so art is always loaded
- Sign in with your Google account; playback and library come from YouTube Music

## Build

```sh
./build.sh
open dist/Velvet.app
```

Requires macOS 15+ and a Swift 6.2 toolchain.

The app icon is generated from code: `swift Scripts/make-icon.swift icon.png`.
