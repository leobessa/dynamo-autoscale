module DynamoAutoscale
  class Rule
    attr_accessor :metric, :opts

    CONDITIONS = {
      greater_than: Proc.new { |a, b| a > b },
      less_than:    Proc.new { |a, b| a < b },
    }

    def initialize metric, opts, &block
      @metric = metric
      @opts   = opts
      @block  = block
      @count  = Hash.new(0)

      unless [:consumed_reads, :consumed_writes].include? @metric
        raise ArgumentError.new("Invalid metric: #{@metric}. Must be either " +
                                ":consumed_reads or :consumed_writes.")
      end

      if @opts[:greater_than].nil? and @opts[:less_than].nil?
        raise ArgumentError.new("Must specify at least one of greater_than " +
          "or less_than")
      end

      if @opts[:for].nil? and @opts[:last].nil?
        raise ArgumentError.new("Need to specify at least one of :for and :last.")
      end

      if @opts[:greater_than] and @opts[:less_than] and
        @opts[:greater_than].to_f >= @opts[:less_than].to_f
        raise ArgumentError.new("greater_than cannot be greater than or " +
                                "equal to less_than. Rule will never trigger.")
      end

      if @opts[:greater_than] and @opts[:greater_than].to_f <= 0
        raise ArgumentError.new("greater_than cannot be less than or equal to 0")
      end

      if @opts[:less_than] and @opts[:less_than].to_f <= 0
        raise ArgumentError.new("less_than cannot be less than or equal to 0")
      end

      if @opts[:min] and @opts[:min] <= 0
        raise ArgumentError.new("min cannot be less than or equal to 0")
      end

      if @opts[:max] and @opts[:max] <= 0
        raise ArgumentError.new("max cannot be less than or equal to 0")
      end

      if @opts[:count] and @opts[:count] <= 0
        raise ArgumentError.new("count cannot be less than or equal to 0")
      end

      if @opts[:scale].nil? and block.nil?
        raise ArgumentError.new("no :scale option or block specified. Rule has no action.")
      end

      if @opts[:scale] and !@opts[:scale].is_a? Hash
        raise ArgumentError.new(":scale option expects to be a hash.")
      end

      if @opts[:scale] and @opts[:scale][:on].nil? and @opts[:scale][:by].nil?
        raise ArgumentError.new(":scale option expects :on and :by options.")
      end

      if @opts[:scale] and ![:consumed, :provisioned].include?(@opts[:scale][:on])
        raise ArgumentError.new(":scale { :on } needs to be either :consumed " +
          "or :provisioned")
      end

      if @opts[:scale] and @opts[:scale][:by] <= 0
        raise ArgumentError.new(":scale { :by } needs to be greater than 0")
      end
    end

    def test table
      last_provisioned = table.last_provisioned_for(@metric)

      CONDITIONS.each do |key, comparator|
        if @opts[key]
          value = @opts[key].to_f

          # Get the value as a percentage of the last amount provisioned for
          # this metric if it is a string that ends with a percent symbol.
          if @opts[key].is_a? String and @opts[key].end_with? "%"
            # If we don't have a provisioned value yet, we have to move along.
            # We don't know what the headroom is and we can't trigger an
            # alarm.
            next if last_provisioned.nil?

            value = (value / 100.0) * last_provisioned
          end

          duration = @opts[:for] || @opts[:last]
          data     = table.last(duration, @metric)

          # If a specific number of points have been specified to look at,
          # make sure we have exactly that number of points before continuing.
          if !duration.is_a? ActiveSupport::Duration and data.length != duration
            return false
          end

          if @opts[:max]
            data = data.take(@opts[:max])
          end

          if @opts[:min]
            return false unless data.length >= @opts[:min]
          end

          if data.all? { |datum| comparator.call(datum, value) }
            @count[table.name] += 1

            if @opts[:times].nil? or @count[table.name] == @opts[:times]
              @count[table.name] = 0

              if scale = @opts[:scale]
                new_val = table.send("last_#{scale[:on]}_for", @metric) * scale[:by]
                DynamoAutoscale.actioners[table].set(@metric, new_val)
              end

              if @block
                @block.call(table, self, DynamoAutoscale.actioners[table])
              end

              return true
            else
              return false
            end
          else
            @count[table.name] = 0
          end
        end
      end

      false
    end

    def to_english
      message = "#{@metric} "
      if @opts[:greater_than]
        message << "were greater than " << @opts[:greater_than] << " "
      end

      if @opts[:less_than]
        message << "and " if @opts[:greater_than]
        message << "were less than " << @opts[:less_than] << " "
      end

      if @opts[:for] or @opts[:last]
        val = @opts[:for] || @opts[:last]

        if val.is_a? ActiveSupport::Duration
          message << "for #{val.inspect} "
        else
          message << "for #{val} data points "
        end
      end

      if @opts[:min]
        message << "with a minimum of #{@opts[:min]} data points "
      end

      if @opts[:max]
        message << "and " if @opts[:min]
        message << "with a maximum of #{@opts[:max]} data points "
      end

      message
    end

    def serialize
      metric = @metric == :consumed_reads ? "reads" : "writes"

      "#{metric}(#{@opts})"
    end
  end
end
