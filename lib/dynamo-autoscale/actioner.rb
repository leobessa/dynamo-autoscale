module DynamoAutoscale
  class Actioner
    def initialize
      @downscales         = Hash.new { |h, k| h[k] = { reads: 0, writes: 0 } }
      @upscales           = Hash.new { |h, k| h[k] = { reads: 0, writes: 0 } }
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

        if @downscales[table][:reads] < 4 or @downscales[table][:writes] < 4
          logger.warn "[scales] Unused downscales: #{@downscales[table]}"
        end

        @upscales[table] = { reads: 0, writes: 0 }
        @downscales[table] = { reads: 0, writes: 0 }
        @downscale_warn = false
      end

      @last_scale_check = now
    end

    def upscales table
      check_day_reset! table
      @upscales[table]
    end

    def downscales table
      check_day_reset! table
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
        return
      end

      if prev > value and @downscales[table][key] >= 4
        unless @downscale_warn
          @downscale_warn = true
          logger.warn "[#{key.to_s.ljust(6)}][scaling #{"failed".red}]" +
            " Hit upper limit of downward scales per day."
        end

        return
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
            @downscales[table][key] += 1
          else
            @upscales[table][key] += 1
          end

          provisioned_reads(table) << [time, value]
        end
      when :writes
        if scale(key, table, value)
          if prev > value
            @downscales[table][key] += 1
          else
            @upscales[table][key] += 1
          end

          provisioned_writes(table) << [time, value]
        end
      end
    end
  end
end
