require 'logger'
require 'json'
require 'thread'
require 'thread/pool'

require 'metoffice_datapoint'
require 'trollop'


MET_OFFICE_RESOLUTIONS = ['3hourly', 'daily']

THREAD_POOL_SIZE = 16

opts = Trollop::options do
  opt(:config,
      'Configuration JSON file',
      :type => :string)
  opt(:datapointkey,
      'Met Office datapoint key',
      :type => :string)
  opt(:unitaryauthority,
      'Unitary authority, e.g. "Greater Manchester"',
      :type => :string)
  opt(:resolution,
      "Forecast resolution, one of #{MET_OFFICE_RESOLUTIONS.join(', ')}",
      :type => :string)
  opt(:output,
      'File path to output JSON to',
      :type => :string)
  opt(:poolsize,
      'Number of download threads in pool',
      :default => THREAD_POOL_SIZE)
end

if opts[:config]
  configFile = opts[:config]
  config = JSON.parse(IO.read(configFile), {symbolize_names: true})
  opts = opts.merge(config)
end

unless opts[:datapointkey]
  Trollop::die :datapointkey, 'Datapoint key is required'
end
unless opts[:unitaryauthority]
  Trollop::die :unitaryauthority, 'Unitary authority required'
end
unless opts[:resolution]
  Trollop::die :resolution, 'Resolution required'
end
unless opts[:output]
  Trollop::die :output, 'Output required'
end

logger = Logger.new(STDOUT)

datapoint_key = opts[:datapointkey]
unitary_authority = opts[:unitaryauthority]
resolution = opts[:resolution]
output_file_path = opts[:output]

client = MetofficeDatapoint.new(api_key: datapoint_key)

forecasts_capabilities = client.forecasts_capabilities(res: resolution)

# TODO: check whether there any new forecasts to retrieve, aborting if not.
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

nodes = []
site_forecasts.each do |site_forecast|
  # Don't know what DV stands for see
  # http://www.metoffice.gov.uk/datapoint/product/uk-3hourly-site-specific-forecast/detailed-documentation
  siteDv = site_forecast['SiteRep']['DV']
  node = siteDv['Location']
  # Rename the id key to what citysdk expects
  node['id'] = node['i']
  node.delete 'i'
  nodes.push siteDv['Location']
end

File.open(output_file_path, 'w') do |file|
  file.write(JSON.pretty_generate(nodes))
end

