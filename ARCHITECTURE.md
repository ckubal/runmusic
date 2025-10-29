# RunMusic Architecture Documentation

## Navigation Flow (CRITICAL - Always Reference This)

### Main App Flow
```
ContentView (entry point)
  ↓
RunCardStackView (main interface - card stack)
  ↓ [user taps run]
  → .navigationDestination(for: RunActivity.self)
  ↓
RunCanvasDestinationView(initialRun: run)
  ↓
SimpleRunCanvasView(run: $run) ← ACTUAL CANVAS VIEW
```

### Key Files by Usage
1. **`SimpleRunCanvasView`** (in RunCardStackView.swift) - ACTIVE canvas implementation
2. **`RunDetailView`** - Complex customization view (separate flow)
3. **`RunCanvasView`** - UNUSED separate canvas (legacy)

## Canvas System Architecture

### Asset Generation
- **Source**: `CanvasAsset.generateDefaultAssets(for:canvasSize:)` in CanvasAsset.swift
- **Used by**: `SimpleRunCanvasView.setupSimpleAssets()`
- **Rendering**: `EnhancedAssetView` for all asset types

### Asset Types
- `.titleDistance` - Title and distance display
- `.route` - Route map visualization  
- `.songList` - Spotify track list
- `.powerSong` - Power song highlight
- `.stats` - Combined stats cluster
- `.location` - Location display

## Debugging Protocol

### Before Making ANY Changes:
1. **Find navigation flow**: `grep -r "navigationDestination\|NavigationLink" Views/`
2. **Match log messages**: `grep -r "CRITICAL\|SIMPLE CANVAS" .`
3. **Verify view hierarchy**: Understand which view is actually rendered
4. **Test in simulator**: Check logs match expected view

### Log Message Patterns
- `🎨 SIMPLE CANVAS:` = SimpleRunCanvasView
- `🎨 Creating default canvas layout:` = CanvasAsset.generateDefaultAssets
- `🎨 RENDERING ASSET:` = EnhancedAssetView rendering

## File Organization

### Canvas Views
- `RunCardStackView.swift` - Contains SimpleRunCanvasView (ACTIVE)
- `RunDetailView.swift` - Complex customization view

### Canvas Assets
- `CanvasAsset.swift` - Asset models and generation
- `EnhancedAssetView.swift` - Asset rendering

### Core Services
- `StravaService.swift` - Run data and API integration
- `SpotifyService.swift` - Music data and authentication
- `FirestoreService.swift` - Cloud storage and sync
- `AuthViewModel.swift` - Authentication state management
- `PhotoService.swift` - Background photo management

### Archive Structure
Unused/legacy files moved to `Archive/` folder:
- `Archive/unused_views/` - RunCanvasView.swift and unused animated components
- `Archive/build_logs/` - Build logs, debug scripts, helper scripts
- `Archive/documentation/` - Legacy documentation files
- `Archive/supporting_files/` - Design assets and reference materials

## Critical Rules

1. **NEVER assume file names indicate usage**
2. **ALWAYS trace navigation from user action**
3. **ALWAYS verify with log messages**
4. **ALWAYS test changes in actual navigation flow**

## Navigation Verification Commands

```bash
# Find navigation destinations
grep -r "navigationDestination\|NavigationLink" Views/

# Find sheet presentations  
grep -r "sheet.*isPresented" Views/

# Find log messages to identify active code
grep -r "SIMPLE CANVAS\|Creating default canvas" .
```

Last Updated: October 17, 2025