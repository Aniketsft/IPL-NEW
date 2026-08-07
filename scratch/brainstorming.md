# Brainstorming: Auto Logout and Timeouts

## How Auto Logout Works

Auto logout in the application is primarily handled by the `InactivityWatcher` widget (`frontend/lib/core/widgets/inactivity_watcher.dart`), which wraps the entire application.

1.  **Interaction Tracking**: The `InactivityWatcher` uses a `Listener` to detect touch events (`onPointerDown`, `onPointerMove`, `onPointerUp`). Every time the user interacts with the app, it resets an internal inactivity timer.
2.  **Inactivity Timeout**: If the user does not interact with the app for **30 minutes**, the inactivity timer fires.
3.  **Logout Execution**: When the timeout fires, it dispatches a `LogoutRequested()` event to the `AuthBloc`, which handles clearing the session and returning the user to the login screen.
4.  **Token Refresh**: While the app is active, `InactivityWatcher` also has a refresh timer that attempts to refresh the authentication token every **5 minutes**.

## Timeouts Configured in the App

There are a few key timeouts currently configured in the codebase:

### 1. Inactivity Timeout
*   **Duration**: 30 minutes
*   **Location**: `InactivityWatcher.timeoutDuration` (`inactivity_watcher.dart:23`)
*   **Purpose**: Logs the user out if they are idle for too long.

### 2. Offline Session TTL (Time-To-Live)
*   **Duration**: 30 minutes (from `lastSyncTime`)
*   **Location**: `AuthRepository.isOfflineSessionValid()` (`auth_repository.dart:184`)
*   **Purpose**: Validates if the locally cached offline session is still valid. *Note: The enforcement of this TTL in `InactivityWatcher` is currently commented out.*

### 3. Network Timeouts
*   **Global API Timeouts**:
    *   Connect Timeout: 15 seconds
    *   Receive Timeout: 60 seconds
    *   *Location*: `network_service.dart:22-23`
*   **Administration API Timeouts**:
    *   Connect Timeout: 10 seconds
    *   Receive Timeout: 15 seconds
    *   *Location*: `user_management_repository.dart:26-27`
*   **End of Day (Manufacturing) Timeouts**:
    *   Send Timeout: 10 minutes
    *   Receive Timeout: 10 minutes
    *   *Location*: `end_of_day_screen.dart:530-531`
    *   *Reason*: Generating and uploading/syncing EOD reports can take a significant amount of time.
*   **TCP Print Service Timeout**:
    *   Connect Timeout: 5 seconds
    *   *Location*: `tcp_print_service.dart:10`
