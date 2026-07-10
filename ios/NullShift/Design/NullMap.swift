import CoreLocation
import MapLibre
import SwiftUI

/// Real basemap from the self-hosted NullMaps stack (maps.nullshift.sh) —
/// replaces the prototype's map doodle. Style + tiles are public read-only
/// on that gateway; the API key there only guards routing/geocoding routes.
struct NullMap: UIViewRepresentable {
    var dark = false
    /// Camera follows this when set (prerun/live).
    var center: CLLocationCoordinate2D?
    /// Route polyline; with `fitToRoute` the camera frames it (summary).
    var route: [CLLocationCoordinate2D] = []
    var fitToRoute = false
    var zoom: Double = 16

    private static let styleBase = "https://maps.nullshift.sh"
    /// Ho Chi Minh City — default camera until the first GPS fix.
    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let style = URL(string: "\(Self.styleBase)/\(dark ? "style-dark.json" : "style.json")")
        let map = MLNMapView(frame: .zero, styleURL: style)
        map.logoView.isHidden = true
        map.compassView.isHidden = true
        map.attributionButton.alpha = 0.25
        map.allowsRotating = false
        map.allowsTilting = false
        // Panels drive the camera themselves; gestures would fight the follow.
        map.isUserInteractionEnabled = false
        map.delegate = context.coordinator
        map.setCenter(center ?? Self.fallbackCenter, zoomLevel: center == nil ? 11 : zoom, animated: false)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        if let center, !fitToRoute {
            if !context.coordinator.centeredOnce {
                // First real fix: snap to running zoom even if the fix
                // happens to equal the fallback camera position.
                context.coordinator.centeredOnce = true
                map.setCenter(center, zoomLevel: zoom, animated: true)
            } else {
                let moved = CLLocation(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)
                    .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                // Re-center only on real movement — tiny jitter would make
                // the camera swim.
                if moved > 2 {
                    map.setCenter(center, zoomLevel: zoom, animated: true)
                }
            }
        }
        context.coordinator.apply(route: route, fit: fitToRoute, to: map)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var centeredOnce = false
        private var styleLoaded = false
        private var pendingRoute: [CLLocationCoordinate2D] = []
        private var pendingFit = false

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleLoaded = true
            installRouteLayer(on: style)
            if !pendingRoute.isEmpty {
                apply(route: pendingRoute, fit: pendingFit, to: mapView)
            }
        }

        private func installRouteLayer(on style: MLNStyle) {
            guard style.source(withIdentifier: "run-route") == nil else { return }
            let source = MLNShapeSource(identifier: "run-route", shape: nil)
            style.addSource(source)
            let line = MLNLineStyleLayer(identifier: "run-route-line", source: source)
            // Theme.greenBright #34B37D
            line.lineColor = NSExpression(forConstantValue: UIColor(red: 0x34 / 255, green: 0xB3 / 255, blue: 0x7D / 255, alpha: 1))
            line.lineWidth = NSExpression(forConstantValue: 4.5)
            line.lineCap = NSExpression(forConstantValue: "round")
            line.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(line)
        }

        func apply(route: [CLLocationCoordinate2D], fit: Bool, to map: MLNMapView) {
            guard styleLoaded, let style = map.style else {
                pendingRoute = route
                pendingFit = fit
                return
            }
            guard let source = style.source(withIdentifier: "run-route") as? MLNShapeSource else { return }
            guard route.count >= 2 else {
                source.shape = nil
                return
            }
            var coords = route
            source.shape = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            if fit {
                let polyline = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
                map.setVisibleCoordinateBounds(
                    polyline.overlayBounds,
                    edgePadding: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
                    animated: false,
                    completionHandler: nil
                )
            }
        }
    }
}
