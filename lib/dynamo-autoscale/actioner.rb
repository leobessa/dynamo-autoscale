module DynamoAutoscale
  class Actioner
    include DynamoAutoscale::Logger

    def initialize
      @downscales         = Hash.new(0)
      @upscales           = Hash.new(0)
      @provisioned_writes = Hash.new { |h, k| h[k] = [] }
      @provisioned_reads  = Hash.new { |h, k| h[k] = [] }

      @last_scale_check   = Time.now.utc
      @downscale_warn     = false
    end

    def provisioned_reads table
      @provisioned_reads[table]
    end

    def provisioned_writes table
      @provisioned_writes[table]
    end

    def check_day_reset! table
      now = Time.now.utc

      if now >= (check = (@last_scale_check + 1.day).midnight)
        logger.info "[scales] New day! Reset scaling counts back to 0."
        logger.debug "[scales] now: #{now}, comp: #{check}"

        if @downscales[table] < 4
          logger.warn "[scales] Unused downscales. Used: #{@downscales[table]}"
        end

        @upscales[table]   = 0
        @downscales[table] = 0
        @downscale_warn    = false
      end

      @last_scale_check = now
    end

    def upscales table, new_val = nil
      check_day_reset! table
      @upscales[table] = new_val if new_val
      @upscales[table]
    end

    def downscales table, new_val = nil
      check_day_reset! table
      @downscales[table] = new_val if new_val
      @downscales[table]
    end

    def set metric, table, value
      check_day_reset! table

      key = case metric
      when :reads, :provisioned_reads, :consumed_reads
        :reads
      when :writes, :provisioned_writes, :consumed_writes
        :writes
      end

      time      = table.latest_data_time
      prev      = table.last_provisioned_for(metric)
      direction = prev > value ? "down".blue : "up  ".blue

      if prev == value
        logger.debug "Attempted to scale by 1. Ignoring..."
        return false
      end

      if prev > value and @downscales[table] >= 4
        unless @downscale_warn
          @downscale_warn = true
          logger.warn "[#{key.to_s.ljust(6)}][scaling #{"failed".red}]" +
            " Hit upper limit of downward scales per day."
        end

        return false
      end

      if value > prev * 2
        value = prev * 2

        logger.warn "[#{key.to_s.ljust(6)}] Attempted to scale up " +
          "more than allowed. Capped scale to #{value}."
      end

      logger.info "[#{key.to_s.ljust(6)}][scaling #{direction}] " +
        "#{prev.round(2)} -> #{value.round(2)}"

      case key
      when :reads
        if scale(key, table, value)
          if prev > value
            @downscales[table] += 1
          else
            @upscales[table] += 1
          end

          provisioned_reads(table) << [time, value]

          return true
        else
          return false
        end
      when :writes
        if scale(key, table, value)
          if prev > value
            @downscales[table] += 1
          else
            @upscales[table] += 1
          end

          provisioned_writes(table) << [time, value]

          return true
        else
          return false
        end
      end
    end
  end
end
