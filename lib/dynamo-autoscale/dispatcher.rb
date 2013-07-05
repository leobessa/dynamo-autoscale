module DynamoAutoscale
  class Dispatcher
    include DynamoAutoscale::Logger

    def initialize
      @last_check = {}
    end

    def dispatch table, time, datum, &block
      DynamoAutoscale.current_table = table
      logger.debug "#{time}: Dispatching to #{table.name} with data: #{datum}"

      # If a nil value comes through, we can reasoanbly assume that it should
      # have been 0.
      datum[:consumed_writes] = 0 if datum[:consumed_writes].nil?
      datum[:consumed_reads]  = 0 if datum[:consumed_reads].nil?

      if datum[:provisioned_reads] and (datum[:consumed_reads] > datum[:provisioned_reads])
        lost_reads = datum[:consumed_reads] - datum[:provisioned_reads]

        logger.warn "[dispatcher][reads] Lost units: #{lost_reads} " +
          "(#{datum[:consumed_reads]} - #{datum[:provisioned_reads]})"
      end

      if datum[:provisioned_writes] and (datum[:consumed_writes] > datum[:provisioned_writes])
        lost_writes = datum[:consumed_writes] - datum[:provisioned_writes]

        logger.warn "[dispatcher][writes] Lost units: #{lost_writes} " +
          "(#{datum[:consumed_writes]} - #{datum[:provisioned_writes]})"
      end

      table.tick(time, datum)
      block.call(table, time, datum) if block

      if @last_check[table.name].nil? or @last_check[table.name] < time
        if time > 20.minutes.ago # Too young to vote!
          if DynamoAutoscale.actioners[table].can_run?
            logger.debug "[dispatcher] Checking rules..."
            DynamoAutoscale.rules.test(table)
            @last_check[table.name] = time
          else
            logger.debug "[dispatcher] Skipped rule check, table is not ready " +
              "to have its throughputs modified."
          end
        else
          logger.debug "[dispatcher] Skipped rule check, data point was from " +
            "more than 20 minutes ago. Too young to vote!"
        end
      else
        logger.debug "[dispatcher] Skipped rule check, already checked for " +
          "a later data point."
      end

      DynamoAutoscale.current_table = nil
    end
  end
end
