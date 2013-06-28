module DynamoAutoscale
  class LocalActioner < Actioner
    # Dummy scaling method.
    def scale metric, value
      return true
    end

    def scale_both reads, writes
      return true
    end

    # These filters use the arrays inside the local actioner to fake the
    # provisioned reads and writes when the local data enters the system. It
    # makes it look like we're actually modifying the provisioned numbers.
    def self.faux_provisioning_filters
      [Proc.new do |table, time, datum|
        wtime, writes = DynamoAutoscale.actioners[table].provisioned_writes.last
        rtime, reads  = DynamoAutoscale.actioners[table].provisioned_reads.last

        datum[:provisioned_writes] = writes if writes and time > wtime
        datum[:provisioned_reads]  = reads  if reads  and time > rtime
      end]
    end
  end
end
