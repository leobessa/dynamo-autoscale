module DynamoAutoscale
  class LocalActioner < Actioner
    include DynamoAutoscale::Logger

    def scale metric, value
      @updating_until = rand(4.0..7.0).minutes.from_now.utc
      return true
    end

    def scale_both reads, writes
      @updating_until = rand(4.0..7.0).minutes.from_now.utc
      return true
    end

    def can_run?
      return true if @updating_until.nil?

      if Time.now.utc > @updating_until
        @updating_until = nil
        return true
      end

      return false
    end

    # These filters use the arrays inside the local actioner to fake the
    # provisioned reads and writes when the local data enters the system. It
    # makes it look like we're actually modifying the provisioned numbers.
    def self.faux_provisioning_filters
      [Proc.new do |table, time, datum|
        actioner = DynamoAutoscale.actioners[table]

        actioner.provisioned_reads.reverse_each do |rtime, reads|
          if time > rtime
            logger.debug "[filter] Faked provisioned_reads to be #{reads} at #{time}"
            datum[:provisioned_reads] = reads
            break
          end
        end

        actioner.provisioned_writes.reverse_each do |wtime, writes|
          if time > wtime
            logger.debug "[filter] Faked provisioned_writes to be #{writes} at #{time}"
            datum[:provisioned_writes] = writes
            break
          end
        end
      end]
    end
  end
end
