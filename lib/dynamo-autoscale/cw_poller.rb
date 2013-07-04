module DynamoAutoscale
  class CWPoller < Poller
    include DynamoAutoscale::Logger
    INTERVAL = 5.minutes

    def poll tables, &block
      if tables.nil?
        tables = AWS::DynamoDB.new.tables.to_a.map(&:name)
      end

      loop do
        # Sleep until the next interval occurrs. This calculation ensures that
        # polling always happens on interval boundaries regardless of how long
        # polling takes.
        sleep_duration = INTERVAL - ((Time.now.to_i + INTERVAL) % INTERVAL)
        logger.debug "[cw_poller] Sleeping for #{sleep_duration} seconds..."
        sleep(sleep_duration)

        do_poll(tables, &block)
      end
    end

    def do_poll tables, &block
      logger.debug "[cw_poller] Beginning CloudWatch poll..."
      now = Time.now

      tables.each do |table|
        # This code will dispatch a message to the listening table that looks
        # like this:
        #
        #   {
        #     :consumed_reads=>{
        #       2013-06-19 12:22:00 UTC=>2.343117697349672
        #     },
        #     :consumed_writes=>{
        #       2013-06-19 12:22:00 UTC=>3.0288461538461537
        #     }
        #   }
        #
        # There may also be :provisioned_reads and :provisioned_writes
        # depending on how the CloudWatch API feels.
        block.call(table, Metrics.all_metrics(table, {
          period:     5.minutes,
          start_time: now - 20.minutes,
          end_time:   now,
        }))
      end
    end
  end
end
