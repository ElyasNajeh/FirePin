# FirePin local multi-client demo

This setup is disposable development infrastructure. Incident state exists only
in the Dart mock-server process; authentication and sessions remain local to
each Flutter client. It is not the production backend, authentication, storage,
or realtime transport.

## 1. Start and reset the shared server

From `C:\Projects\FirePin\FirePinUI`, use Terminal 1:

```powershell
dart run tool/mock_server.dart
```

The default server URL is `http://127.0.0.1:8787`. Android emulators reach the
same host server through `http://10.0.2.2:8787`.

Before a demo run, reset the in-memory incident state:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8787/reset
```

Stopping or restarting the server also clears all state.

## 2. Launch isolated clients

Check available device identifiers when needed:

```powershell
flutter devices
```

Terminal 2 — Android emulator client:

```powershell
flutter run -d emulator-5554
```

Terminal 3 — Chrome client:

```powershell
flutter run -d chrome --web-port=5201
```

Additional Chrome clients can use separate ports:

```powershell
flutter run -d chrome --web-port=5202
```

Use separate browser profiles or incognito sessions where necessary. Windows
in the same normal browser profile may share web authentication storage, which
prevents them from representing isolated users.

Desktop and Chrome use `127.0.0.1` automatically. Android emulators use
`10.0.2.2` automatically. Override the server URL for another host or a physical
phone with:

```powershell
flutter run -d <device-id> --dart-define=FIREPIN_MOCK_BASE_URL=http://192.168.1.10:8787
```

The phone and development computer must be on a network that permits that
connection, and the Windows firewall may need to allow the local Dart process.

## 3. Demo accounts

| Role | Name | Login | PIN / password |
|---|---|---|---|
| Citizen A | أحمد محمد عبد الله | `123456789` | `1234` |
| Citizen B | ريم سامر حمدان | `246813579` | `2468` |
| Volunteer A | ليان أحمد صالح | `987654321` | `4321` |
| Volunteer B | عمر يوسف النجار | `864209753` | `5678` |
| Municipality | بلدية القدس | `municipality@firepin.ps` | `firepin-demo` |

The pending volunteer remains available as `111222333` / `1234`, but cannot act
as an approved responder.

## 4. Suggested walkthrough

1. Log in as Citizen A on one client and report a fire.
2. Log in as Volunteer A on an isolated client and respond.
3. Log in as Volunteer B on another isolated client and respond.
4. Wait about one second for polling. Citizen A should show two responders but
   no volunteer markers or routes.
5. Each volunteer should see only their own marker and route.
6. Log in as the municipality on another isolated client. It should show both
   responders with deterministic presentation-only markers and routes.
7. Withdraw Volunteer A if desired; Volunteer B remains active.
8. Resolve the incident as an active responder. All clients should observe the
   resolved/non-active state after the next poll, and the shared fire should
   leave the municipality's active map while remaining in history.

Photo bytes remain only on the reporting client. The shared server transmits
photo-presence metadata, responder identities, and incident state—not image
content or real volunteer GPS coordinates.
