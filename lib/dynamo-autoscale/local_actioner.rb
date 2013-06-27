module DynamoAutoscale
  class LocalActioner < Actioner
    # Dummy scaling method.
    def scale metric, table, value
      return true
    end

    # These filters use the arrays inside the local actioner to fake the
    # provisioned reads and writes when the local data enters the system. It
    # makes it look like we're actually modifying the provisioned numbers.
    def self.faux_provisioning_filters
      [Proc.new do |table, time, datum|
        wtime, writes = DynamoAutoscale.actioner.provisioned_writes(table).last
        rtime, reads  = DynamoAutoscale.actioner.provisioned_reads(table).last

        datum[:provisioned_writes] = writes if writes and time > wtime
        datum[:provisioned_reads]  = reads  if reads  and time > rtime
      end]
    end
  end
end
