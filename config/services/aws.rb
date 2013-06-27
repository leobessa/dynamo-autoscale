config_location = nil

if File.exists? './aws.yml'
  config_location = './aws.yml'
elsif ENV['AWS_CONFIG'] and File.exists? ENV['AWS_CONFIG']
  config_location = ENV['AWS_CONFIG']
elsif File.exists?(File.join(DynamoAutoscale.root, 'config', 'aws.yml'))
  config_location = File.join(DynamoAutoscale.root, 'config', 'aws.yml')
end

if config_location.nil?
  STDERR.puts "Could not load AWS configuration. Searched in: ./aws.yml and " +
    "ENV['AWS_CONFIG']"

  exit 1
end

DynamoAutoscale.with_config(config_location, absolute: true) do |config|
  AWS.config(config)
end
