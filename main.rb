require 'logger'
require 'json'
require 'thread'
require 'thread/pool'

require 'citysdk'
require 'metoffice_datapoint'
require 'trollop'


MET_OFFICE_RESOLUTIONS = ['3hourly', 'daily']

THREAD_POOL_SIZE = 16


def main
  opts = parse_options
  logger = Logger.new(STDOUT)

  datapoint_key = opts[:datapointkey]
  unitary_authority = opts[:unitaryauthority]
  resolution = opts[:resolution]

  url = opts.fetch(:url)
  email = opts.fetch(:email)
  password = opts.fetch(:password)

  api = CitySDK::API.new(url)
  api.set_credentials(email, password)

  layer = opts.fetch(:layer)
  unless api.layer?(layer)
    logger.info("Creating layer: #{layer}, as it does not exist")
    api.create_layer(
      name:         layer,
      description:  opts.fetch(:description),
      organization: opts.fetch(:organization),
      category:     opts.fetch(:category),
      webservice:   opts.fetch(:webservice)
    )
  end # unless

  client = MetofficeDatapoint.new(api_key: datapoint_key)

  # TODO: check whether there any new forecasts to retrieve, aborting if not.
  forecasts_capabilities = client.forecasts_capabilities(res: resolution)

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
    node = {}
    data = siteDv['Location']
    # Rename the id key to what citysdk expects
    node[:id] = data['i']
    data['id'] = data['i']
    node[:name] = data['name']
    node[:data] = data
    data.delete 'i'
    data.delete 'Period'
    nodes.push node
  end

  nodes.each do |node|
    data = node.fetch(:data)
    pop = lambda { |key| data.delete(key).to_f }
    coordinates = [pop.call('lon'), pop.call('lat')]
    node[:geometry] = { type: 'Point', coordinates: coordinates}
  end

  logger.info('Creating nodes through the CitySDK API')
  api.create_nodes(layer, nodes)

  return 0
end


def parse_options
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
    opt(:poolsize,
        'Number of download threads in pool',
        :default => THREAD_POOL_SIZE)
    opt(:category    , 'Layer category'      , type: :string)
    opt(:layer       , 'Layer name'          , type: :string)
    opt(:description , 'Layer description'   , type: :string)
    opt(:organization, 'Layer organization'  , type: :string)
    opt(:webservice  , 'Layer webservice'    , type: :string)
    opt(:email       , 'CitySDK email'       , type: :string)
    opt(:password    , 'CitySDK password'    , type: :string)
    opt(:url         , 'CitySDK API base URL', type: :string)
  end

  if opts[:config]
    configFile = opts[:config]
    config = JSON.parse(IO.read(configFile), {symbolize_names: true})
    opts = opts.merge(config)
  end

  required = [
    :datapointkey,
    :unitaryauthority,
    :resolution,
    :category,
    :description,
    :layer,
    :organization,
    :webservice,
    :password,
    :url,
    :email
  ]

  required.each do |opt|
    Trollop::die(opt, 'must be specified.') if opts[opt].nil?
  end # do

  opts
end


if __FILE__ == $0
  exit main
end

