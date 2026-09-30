module TrailMarker
  def self.minutes(distance_km, pace_minutes_per_km)
    possible = distance_km >= 0 && pace_minutes_per_km.positive?
    raise ArgumentError, 'distance and pace must be possible' unless possible

    (distance_km * pace_minutes_per_km).round
  end
end
