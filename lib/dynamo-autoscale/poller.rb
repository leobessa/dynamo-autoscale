module DynamoAutoscale
  class Poller
    # The poller constructor accepts a hash of options. The following arguments
    # are valid but optional:
    #
    #   - :tables  - An array of the tables you would like to poll.
    #   - :filters - This is primarily for working with local data but there
    #   could maybe be a production use for it. Locally, it is used to modify
    #   each datum before it gets sent to the dispatcher. It helps fake setting
    #   provisioned throughput.
    def initialize opts = {}
      @opts = opts
    end

    def run &block
      poll(@opts[:tables]) do |table_name, data|
        logger.debug "[poller] Got data: #{data}"
        table = DynamoAutoscale.tables[table_name]

        times = data.inject([]) do |memo, (_, timeseries)|
          memo += timeseries.keys
        end.sort!.uniq!

        times.each do |time|
          datum = {
            provisioned_writes: data[:provisioned_writes][time],
            provisioned_reads:  data[:provisioned_reads][time],
            consumed_writes:    data[:consumed_writes][time],
            consumed_reads:     data[:consumed_reads][time],
          }

          if @opts[:filters]
            @opts[:filters].each { |filter| filter.call(table, time, datum) }
          end

          DynamoAutoscale.dispatcher.dispatch(table, time, datum, &block)
        end
      end
    end
  end
end
