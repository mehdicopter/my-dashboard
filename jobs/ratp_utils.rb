require 'net/http'
require 'json'

API_V4 = 'https://api-ratp.pierre-grimaud.fr/v4'.freeze

SINGLETONS_REPLACEMENTS = {
  "Train a l'approche" => 'Approche',
  "Train à l'approche" => 'Approche',
  "A l'approche" => 'Approche',
  'Train a quai' => 'Quai',
  'Train à quai' => 'Quai',
  'Train retarde' => 'Retardé',
  "A l'arret" => 'Arrêt',
  'Train arrete' => 'Arrêté',
  'Service Termine' => 'Terminé',
  'Service termine' => 'Terminé',

  'PERTURBATIONS' => 'Perturbé',
  'BUS SUIVANT DEVIE' => 'Dévié',
  'DERNIER PASSAGE' => 'Terminé',
  'PREMIER PASSAGE' => '',
  'TRAFIC REDUIT' => 'Trafic Réduit'
}.freeze

PAIR_REPLACEMENTS = {
  ['INTERROMPU', 'ARRET NON DESSERVI'] => ['Interrompu', 'N/Desservi'],

  ['INTERROMPU', 'INTERROMPU'] => ['Interrompu', 'Interrompu'],
  ['INTERROMPU', 'MANIFESTATION'] => ['Interrompu', 'Manifestation'],
  ['INTERROMPU', 'INTEMPERIES'] => ['Interrompu', 'Intempéries'],

  ['ARRET NON DESSERVI', 'ARRET NON DESSERVI'] => ['N/Desservi', 'N/Desservi'],
  ['ARRET NON DESSERVI', 'MANIFESTATION'] => ['N/Desservi', 'Manifestation'],
  ['ARRET NON DESSERVI', 'DEVIATION'] => ['N/Desservi', 'Déviation'],
  ['ARRET NON DESSERVI', 'ARRET REPORTE'] => ['N/Desservi', 'Reporté'],
  ['ARRET NON DESSERVI', 'INTEMPERIES'] => ['N/Desservi', 'Intempéries'],

  ['SERVICE', 'NON ASSURE'] => ['Non Assuré', 'Non Assuré'],
  ['NON ASSURE', 'NON ASSURE'] => ['Non Assuré', 'Non Assuré'],

  ['NON ASSURE', 'MANIFESTATION'] => ['Non Assuré', 'Manifestation'],
  ['NON ASSURE', 'INTEMPERIES'] => ['Non Assuré', 'Intempéries'],

  ['CIRCULATION DENSE', 'MANIFESTATION'] => ['Circul Dense', 'Manifestation'],

  ['INTEMPERIES', 'INTEMPERIES'] => ['Intempéries', 'Intempéries'],

  ['INFO INDISPO ....'] => ['Indispo', 'Indispo'],

  ['SERVICE TERMINE'] => ['Terminé', 'Terminé'],
  ['TERMINE'] => ['Terminé', 'Terminé'],

  ['SERVICE', 'NON COMMENCE'] => ['N/Commencé', 'N/Commencé'],
  ['SERVICE NON COMMENCE'] => ['N/Commencé', 'N/Commencé'],
  ['NON COMMENCE'] => ['N/Commencé', 'N/Commencé'],

  ['BUS PERTURBE', '59 mn'] => %w[Perturbé Perturbé]
}.freeze

NA_UI = '[ND]'.freeze

Transport = Struct.new(:type, :number, :stop, :destination) do
  def to_s
    "#{type[:ui]} #{number}"
  end
end

class Type
  METRO = { apiv4: 'metros', ui: 'metro' }.freeze
  BUS = { apiv4: 'buses', ui: 'bus' }.freeze
  RER = { apiv4: 'rers', ui: 'rer' }.freeze
  TRAM = { apiv4: 'tramways', ui: 'tram' }.freeze
  NOCTILIEN = { apiv4: 'noctiliens', ui: 'noctilien' }.freeze
end

# Due to bugs, some transports have the A/R destinations swapped - this is a hardcoded, non-exhaustive list of swaps
TRANSPORTS_TO_SWAP = [
  { type: Type::TRAM, id: '2' },
  { type: Type::TRAM, id: '5' },
  { type: Type::TRAM, id: '7' }
].freeze

class ConfigurationError < StandardError
end

private def line_key(transport)
  transport.type[:apiv4] + '-' + transport.number
end

private def get_as_json(path)
  response = Net::HTTP.get_response(URI(path))
  JSON.parse(response.body)
end

def read_stations(transport)
  url = "#{API_V4}/stations/#{transport.type[:apiv4]}/#{transport.number}?_format=json"
  begin
    json = get_as_json(url)
  rescue StandardError => e
    warn("ERROR: RATP: Unable to read stations for #{transport} (#{url}): #{e}")
    return nil
  end

  raise ConfigurationError, "Unable to read stations: #{transport}: #{json['result']['message']}" if json['result']['code'] == 400

  stations = station_name_to_slug_mapping(json)

  stations
end

private def station_name_to_slug_mapping(json)
  stations = {}

  json['result']['stations'].each do |station|
    stations[station['name']] = station['slug']
  end

  stations
end

def read_directions(transport)
  url = "#{API_V4}/destinations/#{transport.type[:apiv4]}/#{transport.number}?_format=json"
  begin
    json = get_as_json(url)
  rescue StandardError => e
    warn("ERROR: RATP: Unable to read directions for #{transport} (#{url}): #{e}")
    return nil
  end

  raise ConfigurationError, "Unable to read directions: #{transport}: #{json['result']['message']}" if json['result']['code'] == 400

  destinations = destination_name_to_way_mapping(json, transport)

  destinations
end

private def destination_name_to_way_mapping(json, transport)
  directions = {}

  json['result']['destinations'].each do |destination|
    directions[destination['name']] = destination['way']
  end

  TRANSPORTS_TO_SWAP.each do |transport_to_swap|
    if transport_to_swap[:type] == transport[:type] && transport_to_swap[:id] == transport[:number]
      directions.each { |dir, way| directions[dir] = way == 'A' ? 'R' : 'A' }
    end
  end

  directions
end

def read_timings(transport, stop, dir)
  url = "#{API_V4}/schedules/#{transport.type[:apiv4]}/#{transport.number}/#{stop}/#{dir}"
  begin
    json = get_as_json(url)
  rescue StandardError => e
    warn("ERROR: RATP: Unable to fetch timings for #{transport} (#{url}): #{e}")
    return [NA_UI, NA_UI,
            NA_UI, NA_UI]
  end

  if json['result']['schedules'].nil?
    warn("ERROR: RATP: Schedules not available for #{transport} (#{url}), json = #{json}")
    return [NA_UI, NA_UI,
            NA_UI, NA_UI]
  end

  schedules = json['result']['schedules']

  if schedules.length == 4 &&
     (['PREMIER DEPART', 'DEUXIEME DEPART'].include?(schedules[1]['message']) ||
      ['PREMIER DEPART', 'DEUXIEME DEPART'].include?(schedules[3]['message']))

    # T2, Porte de Versailles, dir Bezons
    premier = schedules[1]['message'] == 'PREMIER DEPART' ? 0 : 2
    deuxieme = (premier + 2) % 4

    [schedules[premier]['destination'],  schedules[premier]['message'],
     schedules[deuxieme]['destination'], schedules[deuxieme]['message']]
  elsif schedules.length >= 2
    [schedules[0]['destination'], schedules[0]['message'],
     schedules[1]['destination'], schedules[1]['message']]
  elsif schedules.length == 1
    if !schedules[0].key?('code')
      [schedules[0]['destination'], schedules[0]['message'],
       '',                          '']
    else
      warn("ERROR: RATP: #{schedules[0]['code']} for #{transport} (#{url}), json = #{json}")
      [schedules[0]['destination'], NA_UI,
       schedules[0]['destination'], NA_UI]
    end
  else
    warn("ERROR: RATP: Unable to parse timings for #{transport} (#{url}), json = #{json}")
    [schedules[0]['destination'], NA_UI,
     schedules[0]['destination'], NA_UI]
  end
end

def read_status(transport)
  return 'indispo' if transport.type == Type::BUS

  url = "#{API_V4}/traffic/#{transport.type[:apiv4]}/#{transport.number}"
  begin
    json = get_as_json(url)
  rescue StandardError => e
    warn("ERROR: RATP: Unable to read status for #{transport} (#{url}): #{e}")
    return NA_UI
  end

  if json['result']['slug'].nil?
    warn("ERROR: RATP: Status not available for #{transport} (#{url}), json = #{json}")
    return NA_UI
  end

  json['result']['slug']
end

private def reword(first_time, second_time)
  PAIR_REPLACEMENTS.each do |source_message, target_message|
    if (source_message.length == 1 &&
         (first_time == source_message[0] || second_time == source_message[0])) ||
       (source_message.length == 2 &&
         ((first_time == source_message[0] && second_time == source_message[1]) ||
          (first_time == source_message[1] && second_time == source_message[0])))
      return target_message
    end
  end

  first_time_parsed = shortcut(first_time)
  second_time_parsed = shortcut(second_time)
  [first_time_parsed, second_time_parsed]
end

private def shortcut(text)
  SINGLETONS_REPLACEMENTS[text] || text
end
