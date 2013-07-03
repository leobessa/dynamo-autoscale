ENV['RACK_ENV'] = "test"
require_relative 'common'
require 'timecop'

path = File.join(DynamoAutoscale.root, 'config', 'dynamo-autoscale-test.yml')
DynamoAutoscale.setup_from_config(path)
