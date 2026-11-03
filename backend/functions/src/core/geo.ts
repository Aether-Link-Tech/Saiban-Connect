export interface GeoSite {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radiusM: number;
}

const EARTH_RADIUS_M = 6_371_000;

/** Great-circle distance in metres (haversine). */
export function distanceM(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

export interface NearestSite {
  site: GeoSite;
  distanceM: number;
  inside: boolean;
}

export function nearestSite(lat: number, lng: number, sites: GeoSite[]): NearestSite | null {
  let best: NearestSite | null = null;
  for (const site of sites) {
    const d = distanceM(lat, lng, site.latitude, site.longitude);
    if (!best || d < best.distanceM) best = { site, distanceM: d, inside: d <= site.radiusM };
  }
  return best;
}
