module DynamoAutoscale
  class UnitCost
    # Pricing information obtained from: http://aws.amazon.com/dynamodb/pricing/
    HOURLY_PRICING = {
      'us-east-1' => {
        read:  { dollars: 0.0065, per: 50 },
        write: { dollars: 0.0065, per: 10 },
      },
      'us-west-1' => {
        read:  { dollars: 0.0065, per: 50 },
        write: { dollars: 0.0065, per: 10 },
      },
    }

    # Returns the cost of N read units for an hour in a given region, which
    # defaults to whatever is in
    # DynamoAutoscale::DEFAULT_AWS_REGION.
    #
    # Example:
    #
    #   DynamoAutoscale::UnitCost.read(500, region: 'us-west-1')
    #   #=> 0.065
    def self.read units, opts = {}
      pricing = HOURLY_PRICING[opts[:region] || DEFAULT_AWS_REGION][:read]
      ((units / pricing[:per].to_f) * pricing[:dollars])
    end

    # Returns the cost of N write units for an hour in a given region, which
    # defaults to whatever is in
    # DynamoAutoscale::DEFAULT_AWS_REGION.
    #
    # Example:
    #
    #   DynamoAutoscale::UnitCost.write(500, region: 'us-west-1')
    #   #=> 0.325
    def self.write units, opts = {}
      pricing = HOURLY_PRICING[opts[:region] || DEFAULT_AWS_REGION][:write]
      ((units / pricing[:per].to_f) * pricing[:dollars])
    end
  end
end
