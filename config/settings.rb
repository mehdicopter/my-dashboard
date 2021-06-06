require_relative '../jobs/ratp_utils.rb'

TRANSPORTS = [
  Transport.new(Type::TRAM, '2', 'Jacqueline Auriol', 'Porte de Versailles (Parc des Expositions)')
]

RATP_UPDATE_INTERVAL = '10s'
