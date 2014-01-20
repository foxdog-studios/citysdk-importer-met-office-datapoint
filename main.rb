require 'logger'
require 'json'
require 'thread'
require 'thread/pool'

require 'metoffice_datapoint'
require 'trollop'


MET_OFFICE_RESOLUTIONS = ['3hourly', 'daily']

THREAD_POOL_SIZE = 16

opts = Trollop::options do
  opt(:datapointkey,
      'Met Office datapoint key',
      :type => :string,
      :required => true)
  opt(:unitaryauthority,
      'Unitary authority, e.g. "Greater Manchester"',
      :type => :string,
      :required => true)
  opt(:resolution,
      "Forecast resolution, one of #{MET_OFFICE_RESOLUTIONS.join(', ')}",
      :type => :string,
      :required => true)
  opt(:output,
      'File path to output JSON to',
      :type => :string,
      :required => true)
  opt(:poolsize,
      'Number of download threads in pool',
      :default => THREAD_POOL_SIZE)
end

logger = Logger.new(STDOUT)

datapoint_key = opts[:datapointkey]
unitary_authority = opts[:unitaryauthority]
resolution = opts[:resolution]
output_file_path = opts[:output]

client = MetofficeDatapoint.new(api_key: datapoint_key)

forecasts_capabilities = client.forecasts_capabilities(res: resolution)

logger.info forecasts_capabilities

site_list = client.forecasts_sitelist
locations = site_list['Locations']['Location']

# Get all the sites that are in the unitary authority
auth_area_sites = locations.select { |location|
  location['unitaryAuthArea'] == unitary_authority
}


number_of_sites = auth_area_sites.length
logger.info "Number of sites: #{number_of_sites}"

pool = Thread.pool(THREAD_POOL_SIZE)
semaphore = Mutex.new

site_forecasts = []
number_of_forecasts_downloaded_so_far = 0

auth_area_sites.each do |site|
  pool.process {
    id = site['id']
    forecasts = client.forecasts(id, {res: resolution})
    # Not sure if we really need to synchronize because of GIL. But who knows
    # what will happen in the future.
    semaphore.synchronize {
      site_forecasts.push forecasts
      number_of_forecasts_downloaded_so_far += 1
      logger.info ("#{number_of_forecasts_downloaded_so_far}" \
                   "/#{number_of_sites} Recieved forecasts for site id: #{id}")
    }
  }
end

pool.shutdown

logger.info 'Download done'

File.open(output_file_path, 'w') do |file|
  file.write(JSON.pretty_generate(site_forecasts))
end

