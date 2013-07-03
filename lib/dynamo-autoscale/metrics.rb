module DynamoAutoscale
  class Metrics
    include DynamoAutoscale::Logger

    DEFAULT_OPTS = {
      namespace:   'AWS/DynamoDB',
      period:      300,
      # metric_name: metric,
      # start_time:  (NOW - 3600).iso8601,
      # end_time:    NOW.iso8601,
      # dimensions:  [{
      #   name: "TableName", value: TABLE_NAME,
      # }],
    }

    # Returns a CloudWatch client object for a given region. If no region
    # exists, the region defaults to whatever is in
    # DynamoAutoscale::DEFAULT_AWS_REGION.
    #
    # CloudWatch client documentation:
    #   https://github.com/aws/aws-sdk-ruby/blob/master/lib/aws/cloud_watch/client.rb
    def self.client region = nil
      @client ||= Hash.new do |hash, _region|
        hash[_region] = AWS::CloudWatch.new({
          cloud_watch_endpoint: "monitoring.#{_region}.amazonaws.com",
        }).client
      end

      @client[region || DEFAULT_AWS_REGION]
    end

    # Returns a hash of timeseries data. Looks a bit like this:
    #
    #   {
    #     provisioned_reads:  { date => value... },
    #     provisioned_writes: { date => value... },
    #     consumed_reads:     { date => value... },
    #     consumed_writes:    { date => value... },
    #   }
    def self.all_metrics table_name, opts = {}
      data = Hash.new { |h, k| h[k] = {} }

      pr = provisioned_reads(table_name, opts).sort_by do |datum|
        datum[:timestamp]
      end

      pr.each do |timeslice|
        data[:provisioned_reads][timeslice[:timestamp]] = timeslice[:average]
      end

      cr = consumed_reads(table_name, opts).sort_by do |datum|
        datum[:timestamp]
      end

      cr.each do |timeslice|
        data[:consumed_reads][timeslice[:timestamp]] = timeslice[:sum]
      end

      pw = provisioned_writes(table_name, opts).sort_by do |datum|
        datum[:timestamp]
      end

      pw.each do |timeslice|
        data[:provisioned_writes][timeslice[:timestamp]] = timeslice[:average]
      end

      cw = consumed_writes(table_name, opts).sort_by do |datum|
        datum[:timestamp]
      end

      cw.each do |timeslice|
        data[:consumed_writes][timeslice[:timestamp]] = timeslice[:sum]
      end

      data
    end

    # Returns provisioned througput reads for a table in DynamoDB. Works on
    # moving averages.
    #
    # Example:
    #
    #   pp DynamoAutoscale::Metrics.provisioned_reads("table_name")
    #   #=> [{:timestamp=>2013-06-18 15:25:00 UTC, :unit=>"Count", :average=>800.0},
    #        {:timestamp=>2013-06-18 15:05:00 UTC, :unit=>"Count", :average=>800.0},
    #        ...
    #       ]
    def self.provisioned_reads table_name, opts = {}
      opts[:metric_name] = "ProvisionedReadCapacityUnits"
      provisioned_metric_statistics(table_name, opts)
    end

    # Returns provisioned througput writes for a table in DynamoDB. Works on
    # moving averages.
    #
    # Example:
    #
    #   pp DynamoAutoscale::Metrics.provisioned_writes("table_name")
    #   #=> [{:timestamp=>2013-06-18 15:25:00 UTC, :unit=>"Count", :average=>600.0},
    #        {:timestamp=>2013-06-18 15:05:00 UTC, :unit=>"Count", :average=>600.0},
    #        ...
    #       ]
    def self.provisioned_writes table_name, opts = {}
      opts[:metric_name] = "ProvisionedWriteCapacityUnits"
      provisioned_metric_statistics(table_name, opts)
    end

    # Returns consumed througput reads for a table in DynamoDB. Works on
    # moving averages.
    #
    # Example:
    #
    #   pp DynamoAutoscale::Metrics.consumed_reads("table_name")
    #   #=> [{:timestamp=>2013-06-18 15:53:00 UTC,
    #         :unit=>"Count",
    #         :average=>1.2111202996546189},
    #        {:timestamp=>2013-06-18 15:18:00 UTC,
    #         :unit=>"Count",
    #         :average=>1.5604973943552964},
    #         ...
    #       ]
    def self.consumed_reads table_name, opts = {}
      opts[:metric_name] = "ConsumedReadCapacityUnits"
      opts[:statistics]  = ["Sum"]
      consumed_metric_statistics(table_name, opts)
    end

    # Returns consumed througput writes for a table in DynamoDB. Works on
    # moving averages.
    #
    # Example:
    #
    #   pp DynamoAutoscale::Metrics.consumed_writes("table_name")
    #   #=> [{:timestamp=>2013-06-18 15:39:00 UTC,
    #         :unit=>"Count",
    #         :average=>1.6882725354235755},
    #        {:timestamp=>2013-06-18 15:24:00 UTC,
    #         :unit=>"Count",
    #         :average=>1.7701510393300435},
    #         ...
    #       ]
    def self.consumed_writes table_name, opts = {}
      opts[:metric_name] = "ConsumedWriteCapacityUnits"
      opts[:statistics]  = ["Sum"]
      consumed_metric_statistics(table_name, opts)
    end

    private

    # Because there's a difference to how consumed and provisioned statistics
    # are gathered for DynamoDB, the two metrics are not comparable without a
    # little bit of modification.
    #
    # Relevant forum post:
    #   https://forums.aws.amazon.com/thread.jspa?threadID=119523
    def self.consumed_metric_statistics table_name, opts = {}
      opts[:statistics] = ["Sum"]
      data = metric_statistics(table_name, opts)

      data.map do |datum|
        datum[:sum] = datum[:sum] / (opts[:period] || DEFAULT_OPTS[:period])
        datum
      end
    end

    def self.provisioned_metric_statistics table_name, opts = {}
      opts[:statistics] = ["Average"]
      metric_statistics(table_name, opts)
    end

    # A base method that gets called by wrapper methods defined above. Makes a
    # call to CloudWatch, getting statistics on whatever metric is given.
    def self.metric_statistics table_name, opts = {}
      region = opts.delete :region
      opts   = DEFAULT_OPTS.merge({
        dimensions:  [{ name: "TableName", value: table_name }],
        start_time:  1.hour.ago,
        end_time:    Time.now,
      }).merge(opts)

      if opts[:start_time] and opts[:start_time].respond_to? :iso8601
        opts[:start_time] = opts[:start_time].iso8601
      end

      if opts[:end_time] and opts[:end_time].respond_to? :iso8601
        opts[:end_time] = opts[:end_time].iso8601
      end

      client(region).get_metric_statistics(opts)[:datapoints]
    end
  end
end
