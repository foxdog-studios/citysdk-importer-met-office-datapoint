require 'metoffice_datapoint'
require 'trollop'

opts = Trollop::options do
  opt(:datapointkey,
      'Met Office datapoint key',
      :type => :string,
      :required => true)
end

datapoint_key = opts[:datapointkey]

client = MetofficeDatapoint.new(api_key: datapoint_key)
forecasts_capabilities = client.forecasts_capabilities(res: 'daily')

puts forecasts_capabilities

