require_relative 'ratp_utils'

unless defined? TRANSPORTS
  TRANSPORTS = [].freeze
  puts('WARN: RATP: Transports not defined. See README for more info!')
end

unless defined? RATP_UPDATE_INTERVAL
  RATP_UPDATE_INTERVAL = '10s'.freeze
end

stations = {}
directions = {}

SCHEDULER.every RATP_UPDATE_INTERVAL, first_in: 0 do |job|
  begin
    results = []

    TRANSPORTS.each do |transport|
      line_key = line_key(transport)

      if stations[line_key].nil?
        stations[line_key] = read_stations(transport)
        next if stations[line_key].nil?
      end

      if stations[line_key][transport.stop].nil?
        raise ConfigurationError, "Invalid stop '#{transport.stop}', possible values are #{stations[line_key].keys}"
      end

      if directions[line_key].nil?
        directions[line_key] = read_directions(transport)
        next if directions[line_key].nil?
      end

      if directions[line_key][transport.destination].nil?
        raise ConfigurationError, "Invalid destination '#{transport.destination}', possible values are #{directions[line_key].keys}"
      end

      stop = stations[line_key][transport.stop]
      dir = directions[line_key][transport.destination]

      timings = read_timings(transport, stop, dir)
      next if timings.nil?

      status = read_status(transport)
      next if status.nil?

      first_destination, first_time, second_destination, second_time = timings

      first_time_parsed, second_time_parsed = reword(first_time, second_time)

      stop_escaped = stop.delete('+')

      key = "#{line_key}-#{stop_escaped}-#{dir}"

      results.push(
        key: key,
        value: {
          type: transport.type[:ui],
          id: transport.number,
          d1: first_destination, t1: first_time_parsed,
          d2: second_destination, t2: second_time_parsed,
          status: status
        }
      )
    end

    send_event('ratp', results: results)
  rescue ConfigurationError => e
    warn("ERROR: RATP: #{e}")
    job.unschedule
  end
end
