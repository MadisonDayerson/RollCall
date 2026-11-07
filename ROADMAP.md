# Route information roadmap

Goal: give riders as much about a ride's route as possible, in the ride's page (the right-hand column):
a map of the route, the weather along it, and road alerts on it.

Built one task at a time, each tried in the app before the next starts. Every task keeps to its own files, so
it can be fixed or taken out without touching the others.

## Shared groundwork (used by every task)

- **The route's places** come from `Route.places(meetingPlace:notes:)` (meeting place, stops, destination),
  which Route already uses. Nothing new is read from chats or posts.
- **No new accounts or tracking.** Only Task 3 needs a key, and it's the user's own, kept in the keychain.
- **Privacy:** each task adds its line to the README's "What goes online", and nothing it fetches is saved
  to disk except what the ride already holds.

---

## Task 1: Route map preview

**Status: built and tried.** The map is greyscale to suit the black-and-white look. Since then (1e): RollCall
works out each ride's start, stops and destination itself (labelled lines, phrases like "heading to …", titles
like "A to B", then Apple Intelligence), checks them with Apple Maps (`RouteFinder.swift`), and maps one-place
rides from your suburb. (1f) An organiser's Google or Apple Maps route link wins: its stops and the points the route
was dragged through are read from the link (short maps.app.goo.gl links are followed once), so the map follows their roads. On the owner's rides, every one with a place now gets a map.

A still picture of the planned road route under the ride's About box, plus Kurviger as a Route choice.

| Step | What | Resources |
|---|---|---|
| 1a | Turn the ride's places into points and plan the road route between them | MapKit `MKLocalSearch` (places near home) and `MKDirections` (driving, one leg per stop). Free, no key. New file `RoutePlanner.swift` |
| 1b | Draw the route as a picture, muted map with a black route line, start and finish marks | MapKit `MKMapSnapshotter` with the muted map style. New file `RouteMapImage.swift` |
| 1c | Show it on the ride page: a "Route" box with the picture, distance and riding time; click opens Route | SwiftUI in a new `RouteBox.swift`; kept in memory per ride, redrawn for light and dark mode |
| 1d | Kurviger in Settings → Maps app for Route | Kurviger web links (`kurviger.de/?point=…`), in `Route.swift` |

- **Owner provides:** nothing.
- **Tests:** places → legs, link building for Kurviger; the picture is checked by snapshot.
- **Done when:** a ride with a meeting place and destination shows its route, one with neither shows nothing,
  and Kurviger opens with every stop.

## Task 2: Weather along the route

**Status: next.**

Temperature, chance of rain and wind at points along the route, at the time you'd reach each one.

| Step | What | Resources |
|---|---|---|
| 2a | Pick points every 40–50 km along the planned route, each with the time you'd get there | Task 1's route line and riding time. New file `RouteWeather.swift` |
| 2b | Fetch the hourly forecast for those points (BOM's ACCESS-G model, falling back to the best model) | [Open-Meteo](https://open-meteo.com/) forecast API: free for non-commercial use, no key, one request for all points |
| 2c | Show it under the map: a short row per point (place, time, temperature, rain chance, wind) | SwiftUI in `RouteBox.swift`; "Forecast from BOM via Open-Meteo" credit |
| 2d | Rides more than a week out say when the forecast will be ready | Open-Meteo's 7-day range |

- **Owner provides:** nothing.
- **Tests:** points along a made-up route, times at each point, reading a saved sample reply.
- **Done when:** this week's rides show weather along their route, and later rides say when to check back.

## Task 3: Road alerts on the route

Crashes, closures, hazards and roadworks near the route, from the Victorian Department of Transport and Planning.

| Step | What | Resources |
|---|---|---|
| 3a | Get a free key (owner, with step-by-step guidance) and add a Settings box to paste it | [Data Exchange Platform](https://opendata.transport.vic.gov.au/organization/disruptions?tags=road) sign-up; key in the keychain like the Beeper key |
| 3b | Download Victoria's unplanned and planned road disruptions | DTP Open Data API v3 (`api.opendata.transport.vic.gov.au`), CC BY 4.0, 20 calls a minute. New file `RoadAlerts.swift` |
| 3c | Keep the alerts within about 500 m of the route, and planned works that overlap the ride's time | Task 1's route line, worked out on the Mac (the route isn't sent anywhere) |
| 3d | Show them under the weather: what, where, how long | SwiftUI in `RouteBox.swift`, warnings in orange |

- **Owner provides:** a free DTP key (friends who want alerts paste their own).
- **Not available:** Linkt and Digital Twin Victoria publish no alerts feed; DTP's data is the source.
- **Tests:** matching alerts to a made-up route, reading a saved sample reply.
- **Done when:** a closure on the route shows on the ride, and one in another suburb doesn't.

## Task 4: Rain radar on ride day

The latest rain radar over the route map, only in the few hours before a ride.

| Step | What | Resources |
|---|---|---|
| 4a | Fetch the latest radar frame for the map's area | [RainViewer](https://rainviewer.com/api.html) free API (personal use, zoomed out to level 7 at most) |
| 4b | Lay it over the route picture, with "Weather data by RainViewer" | `RouteMapImage.swift` |
| 4c | Only on ride day, refreshed when the ride is opened | `RouteBox.swift` |

- **Owner provides:** nothing.
- **Done when:** on ride day the map shows rain bands over the route, credited to RainViewer.
