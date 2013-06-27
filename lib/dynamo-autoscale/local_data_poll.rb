module DynamoAutoscale
  class LocalDataPoll < Poller
    def initialize *args
      super(*args)
      @cache = Hash.new { |h, k| h[k] = {} }
    end

    def poll tables, &block
      if tables.nil?
        tables = ["*"]
      end

      tables.each do |table_name|
        unless @cache[table_name].empty?
          @cache[table_name].each do |day, table_day_data|
            block.call(table_name, table_day_data)
          end
        else
          file = "#{table_name}.json"

          Dir[File.join(DynamoAutoscale.data_dir, '*')].each do |day_path|
            Dir[File.join(day_path, file)].each do |table_path|
              data = JSON.parse(File.read(table_path)).symbolize_keys

              if data[:consumed_writes].nil? or data[:consumed_reads].nil?
                logger.warn "Lacking data for table #{table_name}. Skipping."
                next
              end

              # All this monstrosity below is doing is parsing the time keys in
              # the nested hash from strings into Time objects. Hash mapping
              # semantics are weird, hence why this looks ridiculous.
              data = Hash[data.map do |key, ts|
                [
                  key,
                  Hash[ts.map do |t, d|
                    [Time.parse(t), d]
                  end],
                ]
              end]

              @cache[table_name][day_path] = data

              block.call(table_name, data)
            end
          end
        end
      end
    end
  end
end
