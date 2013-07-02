module DynamoAutoscale
  class DynamoActioner < Actioner
    def dynamo
      @dynamo ||= AWS::DynamoDB.new.tables[table.name]
    end

    def scale metric, value
      aws_throughput_key = case metric
      when :reads
        :read_capacity_units
      when :writes
        :write_capacity_units
      end

      dynamo_scale(table, aws_throughput_key => metric)
    end

    def scale_both reads, writes
      dynamo_scale(read_capacity_units: reads, write_capacity_units: writes)
    end

    private

    def dynamo_scale opts
      if dynamo.status == :updating
        logger.warn "[actioner] Cannot scale throughputs. Table is updating."
        return false
      end

      dynamo.provision_throughput(opts)
      return true
    rescue AWS::DynamoDB::Errors::ValidationException => e
      # When you try to set throughput to a negative value or the same value it
      # was previously you get this.
      logger.warn "[#{e.class}] #{e.message}"
      return false
    rescue AWS::DynamoDB::Errors::ResourceInUseException => e
      # When you try to update a table that is being updated you get this.
      logger.warn "[#{e.class}] #{e.message}"
      return false
    rescue AWS::DynamoDB::Errors::LimitExceededException => e
      # When you try to increase throughput greater than 2x or you try to
      # decrease more than 4 times per day you get this.

      aws_description = self.describe_table(table)
      decreases_today = aws_description[:provisioned_throughput][:number_of_decreases_today]

      downscales(table, decreases_today)
      logger.warn "[#{e.class}] #{e.message}"
      return false
    end

    def self.describe_table
      data = AWS::DynamoDB::ClientV2.new.describe_table(table_name: table.name)

      data[:table]
    end
  end
end
