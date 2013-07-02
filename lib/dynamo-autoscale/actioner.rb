module DynamoAutoscale
  class Actioner
    include DynamoAutoscale::Logger

    def self.minimum_throughput
      @minimum_throughput ||= 10
    end

    def self.minimum_throughput= new_minimum_throughput
      @minimum_throughput = new_minimum_throughput
    end

    def self.maximum_throughput
      @maximum_throughput ||= 20000
    end

    def self.maximum_throughput= new_maximum_throughput
      @maximum_throughput = new_maximum_throughput
    end

    attr_accessor :table, :upscales, :downscales

    def initialize table, opts = {}
      @table            = table
      @downscales       = 0
      @upscales         = 0
      @provisioned      = { reads: RBTree.new, writes: RBTree.new }
      @pending          = { reads: nil, writes: nil }
      @last_action      = Time.now.utc
      @last_scale_check = Time.now.utc
      @downscale_warn   = false
      @opts             = opts
    end

    def provisioned_for metric
      @provisioned[normalize_metric(metric)]
    end

    def provisioned_writes
      @provisioned[:writes]
    end

    def provisioned_reads
      @provisioned[:reads]
    end

    def check_day_reset!
      now = Time.now.utc

      if now >= (check = (@last_scale_check + 1.day).midnight)
        logger.info "[scales] New day! Reset scaling counts back to 0."
        logger.debug "[scales] now: #{now}, comp: #{check}"

        if @downscales < 4
          logger.warn "[scales] Unused downscales. Used: #{@downscales}"
        end

        @upscales   = 0
        @downscales = 0
        @downscale_warn    = false
      end

      @last_scale_check = now
    end

    def upscales
      check_day_reset!
      @upscales
    end

    def downscales new_val = nil
      check_day_reset!
      @downscales
    end

    def set metric, to
      check_day_reset!

      metric = normalize_metric(metric)
      ptime, _ = provisioned_for(metric).last

      if ptime and ptime > 2.minutes.ago
        logger.warn "[actioner] Attempted to scale the same metric more than " +
          "once in a 2 minute window. Disallowing."
        return false
      end

      from = table.last_provisioned_for(metric)

      if from and to > (from * 2)
        to = from * 2

        logger.warn "[#{metric}] Attempted to scale up " +
          "more than allowed. Capped scale to #{to}."
      end

      if to < Actioner.minimum_throughput
        to = Actioner.minimum_throughput

        logger.warn "[#{metric}] Attempted to scale down to " +
          "less than minimum throughput. Capped scale to #{to}."
      end

      if to > Actioner.maximum_throughput
        to = Actioner.maximum_throughput

        logger.warn "[#{metric}] Attempted to scale up to " +
          "greater than maximum throughput. Capped scale to #{to}."
      end

      if from and from == to
        logger.info "[#{metric}] Attempted to scale to same value. Ignoring..."
        return false
      end

      if from and from > to
        downscale metric, from, to
      else
        upscale metric, from, to
      end
    end

    def upscale metric, from, to
      logger.info "[#{metric}][scaling up] " +
        "#{from ? from.round(2) : "Unknown"} -> #{to.round(2)}"


      # Because upscales are not limited, we don't need to queue this operation.
      if result = scale(metric, to)
        @provisioned[metric][Time.now.utc] = to
        @upscales += 1
      end

      return result
    end

    def downscale metric, from, to
      if @downscales >= 4
        unless @downscale_warn
          @downscale_warn = true
          logger.warn "[#{metric.to_s.ljust(6)}][scaling failed]" +
            " Hit upper limit of downward scales per day."
        end

        return false
      end

      if @pending[metric]
        previous_pending = @pending[metric].last
        logger.info "[#{metric}][scaling down] " +
          "#{previous_pending} -> #{to.round(2)} (overwritten pending)"
      else
        logger.info "[#{metric}][scaling down] " +
          "#{from ? from.round(2) : "Unknown"} -> #{to.round(2)}"
      end

      queue_operation! metric, to
    end

    def queue_operation! metric, value
      if @pending[metric]
        logger.debug "[#{metric}] Overwriting pending op with #{value.round(2)}"
      end

      @pending[metric] = [Time.now.utc, value]

      try_flush!
    end

    def try_flush!
      if should_flush?
        if flush_operations!
          @downscales += 1
          @last_action = Time.now.utc
          return true
        else
          return false
        end
      else
        return false
      end
    end

    def flush_operations!
      result = nil

      if @pending[:writes] and @pending[:reads]
        _, wvalue = @pending[:writes]
        _, rvalue = @pending[:reads]

        if result = scale_both(rvalue, wvalue)
          @provisioned[:writes][Time.now.utc] = wvalue
          @provisioned[:reads][Time.now.utc] = rvalue

          @pending[:writes] = nil
          @pending[:reads] = nil
        end
      elsif @pending[:writes]
        time, value = @pending[:writes]

        if result = scale(:writes, value)
          @provisioned[:writes][Time.now.utc] = value

          @pending[:writes] = nil
        end
      elsif @pending[:reads]
        time, value = @pending[:reads]

        if result = scale(:reads, value)
          @provisioned[:reads][Time.now.utc] = value
          @pending[:reads] = nil
        end
      end

      logger.info "[flush] All pending downscales have been flushed."
      return result
    end

    def should_flush?
      if @opts[:group_downscales].nil?
        logger.info "[flush] Downscales are not being grouped. Should flush."
        return true
      end

      if @pending[:reads] and @pending[:writes]
        logger.info "[flush] Both a read and a write are pending. Should flush."
        return true
      end

      now = Time.now.utc

      # I know what you're thinking. How would the last action ever be in the
      # future? Locally, we use Timecop to fake out the time. Unfortunately it
      # doesn't kick in until after the first data point, so when this object is
      # created the @last_action is set to Time.now.utc, then the time gets
      # rolled back, causing the last action to be in the future. This hack
      # fixes that.
      @last_action = now if @last_action > now

      if (@opts[:flush_after] and @last_action and
        (now > @last_action + @opts[:flush_after]))

        logger.info "[flush] Flush timeout of #{@opts[:flush_after]} reached."
        return true
      end

      logger.info "[flush] Flushing conditions not met. Pending operations: " +
        "#{@pending[:reads] ? "1 read" : "no reads"}, " +
        "#{@pending[:writes] ? "1 write" : "no writes"}"

      return false
    end

    private

    def normalize_metric metric
      case metric
      when :reads, :provisioned_reads, :consumed_reads
        :reads
      when :writes, :provisioned_writes, :consumed_writes
        :writes
      end
    end
  end
end
