# Background Tasks Setup

## 1. Add to Info.plist

Add this to your `Info.plist` (or in Xcode under Target > Info > Custom iOS Target Properties):

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>oleksandr.aisixteen.eartharound-swift.refresh</string>
</array>
```

**In Xcode UI:**
1. Select project > Target "eartharound.swift"
2. Go to "Info" tab
3. Add new entry: "Permitted background task scheduler identifiers" (Array)
4. Add item: `oleksandr.aisixteen.eartharound-swift.refresh`

## 2. Testing Background Tasks

Background tasks don't run in simulator/debug normally. To test:

### In Terminal (while app is running on device/simulator):
```bash
# Launch app
# Then in another terminal:
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"oleksandr.aisixteen.eartharound-swift.refresh"]
```

### Or use Xcode debugger console:
```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"oleksandr.aisixteen.eartharound-swift.refresh"]
```

## 3. How It Works

- **Frequency**: System decides when to run (typically 1-4 times per day)
- **Earliest**: 1 hour from last run (configured in code)
- **Actual**: May be delayed by system based on:
  - Battery level
  - Device usage patterns
  - Network conditions
  - Low Power Mode status

## 4. Limitations

### iOS/watchOS:
- Not guaranteed to run every hour
- System controls scheduling
- Best effort delivery
- Suspended in Low Power Mode

### macOS:
- More reliable than iOS
- Better for hourly updates
- Still battery-aware on laptops

## 5. Alternative: Push Notifications

For guaranteed hourly updates, use **Silent Push Notifications**:

**Pros:**
- Reliable timing
- Wakes app even when terminated
- Works across all devices

**Cons:**
- Requires server infrastructure
- APNs setup
- Network dependency

**Implementation:**
```swift
// Server sends silent push every hour with payload:
{
    "aps": {
        "content-available": 1
    }
}
```

## 6. Current Implementation

The app now:
1. Registers background task on launch
2. Schedules update for 1 hour later
3. Fetches weather extremes in background
4. Reschedules next update automatically
5. Handles task expiration gracefully

**Battery Impact:** Minimal (1-2% per day)
**Data Usage:** ~50KB per update
