module DynamoAutoscale
  class Dispatcher
    def initialize
      @last_check = {}
    end

    # The dispatch method expects the data to be in the following format:
    #
    #   {:provisioned_reads=>{2013-06-18 01:00:00 UTC=>800.0},
    #    :provisioned_writes=>{2013-06-18 01:00:00 UTC=>600.0},
    #    :consumed_reads=>{2013-06-18 01:00:00 UTC=>419.34166666666664},
    #    :consumed_writes=>{2013-06-18 01:00:00 UTC=>198.58666666666667}}
    #
    # Hash table with a nested hash table of time => value pairs. It will
    # break this up internally and send messages to the underlying table
    # tracking objects.
    def dispatch table, time, datum, &block
      DynamoAutoscale.current_table = table
      logger.debug "#{time}: Dispatching to #{table.name} with data: #{datum}"

      if datum[:provisioned_reads] and (datum[:consumed_reads] > datum[:provisioned_reads])
        lost_reads = datum[:consumed_reads] - datum[:provisioned_reads]

        logger.warn "Lost read units: #{lost_reads} " +
          "(#{datum[:consumed_reads]} - #{datum[:provisioned_reads]})"
      end

      if datum[:provisioned_writes] and (datum[:consumed_writes] > datum[:provisioned_writes])
        lost_writes = datum[:consumed_writes] - datum[:provisioned_writes]

        logger.warn "Lost write units: #{lost_writes} " +
          "(#{datum[:consumed_writes]} - #{datum[:provisioned_writes]})"
      end

      table.tick(time, datum)
      block.call(table, time, datum) if block

      if @last_check[table.name].nil? or @last_check[table.name] < time
        DynamoAutoscale.rules.test(table)
        @last_check[table.name] = time
      else
        logger.debug "#{table.name}: Check skipping, last time later than #{time}"
      end

      DynamoAutoscale.current_table = nil
    end
  end
end
