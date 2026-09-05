// LiveView Map hook — renders one Leaflet circleMarker per centre.
//
// Two data paths:
//   1. Initial render — reads `data-markers` JSON from the element
//      (server has already serialised the marker list into the
//      attribute on first paint, so the map is correct before the
//      WebSocket is even connected).
//   2. Live updates — listens for the LV `map:set-markers` push
//      event. The element carries `phx-update="ignore"` so Phoenix
//      doesn't fight Leaflet's DOM; the server pushes refreshed
//      marker payloads over the WebSocket instead.
//
// If `window.L` isn't loaded (tests, asset-pipeline races) the
// hook gracefully no-ops — the legend + page content still render.

const AVAILABILITY_COLOUR = {
  green: "#0d9488",  // teal-600
  amber: "#d97706",  // amber-600
  red: "#b91c1c"     // red-700
}

export const Map = {
  mounted() {
    this.markers = parseMarkers(this.el.getAttribute("data-markers"))
    this.renderMap()

    this.handleEvent("map:set-markers", ({markers}) => {
      this.markers = Array.isArray(markers) ? markers : []
      this.renderMap()
    })
  },

  destroyed() {
    if (this._map) {
      this._map.remove()
      this._map = null
    }
  },

  renderMap() {
    if (typeof window.L === "undefined") return

    if (this._map) {
      this._map.remove()
    }

    const markers = this.markers || []

    const centre = markers.length
      ? [markers[0].latitude, markers[0].longitude]
      : [54.5, -3.0]    // UK roughly-centre fallback

    this._map = window.L.map(this.el, {
      center: centre,
      zoom: markers.length ? 10 : 5,
      scrollWheelZoom: false
    })

    window.L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "&copy; OpenStreetMap contributors",
      maxZoom: 18,
      subdomains: ["a", "b", "c"]
    }).addTo(this._map)

    markers.forEach(m => {
      const colour = AVAILABILITY_COLOUR[m.availability] || "#6b7280"
      window.L
        .circleMarker([m.latitude, m.longitude], {
          radius: 8,
          color: colour,
          weight: 2,
          fillColor: colour,
          fillOpacity: 0.6
        })
        .bindPopup(popupHtml(m))
        .addTo(this._map)
    })
  }
}

function parseMarkers(raw) {
  if (!raw) return []
  try {
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch (_err) {
    return []
  }
}

function popupHtml(m) {
  const slots = `${m.slot_count} slot${m.slot_count === 1 ? "" : "s"}`
  const seats =
    typeof m.seat_capacity === "number"
      ? `${m.available_count}/${m.seat_capacity} seats`
      : `${m.available_count} seats`
  return `<strong>${m.name}</strong><br/>${slots} · ${seats} free`
}
