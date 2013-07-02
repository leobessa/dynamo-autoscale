require 'logger'
require 'time'
require 'csv'
require 'tempfile'
require 'aws-sdk'
require 'active_support/all'
require 'rbtree'
require 'colored'

require_relative '../../lib/dynamo-autoscale/logger'
require_relative '../../lib/dynamo-autoscale/poller'

module DynamoAutoscale
  include DynamoAutoscale::Logger

  DEFAULT_AWS_REGION = 'us-east-1'

  def self.root
    File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
  end

  def self.data_dir
    File.join(self.root, 'data')
  end

  def self.env
    ENV['RACK_ENV'] || 'development'
  end

  def self.with_config name, opts ={}
    path = nil

    if opts[:absolute]
      path = name
    else
      path = File.join(root, 'config', "#{name}.yml")
    end

    conf = YAML.load_file(path)[env]
    yield conf if block_given?
    conf
  end

  def self.require_all path
    Dir[File.join(root, path, '*.rb')].each { |file| require file }
  end

  def self.dispatcher= new_dispatcher
    @@dispatcher = new_dispatcher
  end

  def self.dispatcher
    @@dispatcher ||= Dispatcher.new
  end

  def self.poller= new_poller
    @@poller = new_poller
  end

  def self.poller
    @@poller ||= LocalDataPoll.new
  end

  def self.actioner_class= klass
    @@actioner_class = klass
  end

  def self.actioner_class
    @@actioner_class ||= LocalActioner
  end

  def self.actioner_opts= new_opts
    @@actioner_opts = new_opts
  end

  def self.actioner_opts
    @@actioner_opts ||= {}
  end

  def self.actioners
    @@actioners ||= Hash.new { |h, k| h[k] = actioner_class.new(k, actioner_opts) }
  end

  def self.tables= new_tables
    @@tables = new_tables
  end

  def self.tables
    @@tables ||= Hash.new { |h, k| h[k] = TableTracker.new(k) }
  end

  def self.current_table= new_current_table
    @@current_table = new_current_table
  end

  def self.current_table
    @@current_table
  end

  def self.rules= new_rules
    @@rules = new_rules
  end

  def self.rules
    @@rules ||= RuleSet.new
  end
end

DynamoAutoscale.require_all 'lib/dynamo-autoscale'
DynamoAutoscale.require_all 'lib/dynamo-autoscale/ext/**'

Dir[File.join(DynamoAutoscale.root, 'config', 'services', '*.rb')].each do |path|
  load path
end
