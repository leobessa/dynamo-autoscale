module DynamoAutoscale
  class Poller
    def initialize opts = {}
      @opts = opts
    end

    def run &block
      poll(@opts[:tables]) do |table_name, data|
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
