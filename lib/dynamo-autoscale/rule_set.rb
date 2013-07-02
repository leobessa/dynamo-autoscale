module DynamoAutoscale
  class RuleSet
    attr_accessor :rules

    def initialize path = nil, &block
      @rules = Hash.new { |h, k| h[k] = [] }
      @current_table = :all

      if path
        instance_eval(File.read(path))
      elsif block
        instance_eval(&block)
      end
    end

    def for table_name
      return @rules[:all] if table_name == :all
      @rules[table_name] + @rules[:all]
    end

    def test table
      result = false
      rules  = self.for(table.name)

      rules.select(&:reads?).each do |rule|
        break result = true if rule.test(table)
      end

      rules.select(&:writes?).each do |rule|
        break result = true if rule.test(table)
      end

      result
    end

    def table table_name, &block
      @current_table = table_name
      instance_eval(&block)
      @current_table = :all
    end

    def writes opts, &block
      @rules[@current_table] << Rule.new(:consumed_writes, opts, &block)
    end

    def reads opts, &block
      @rules[@current_table] << Rule.new(:consumed_reads, opts, &block)
    end

    def serialize
      @rules.inject("") do |memo, (table_name, rules)|
        memo += "table #{table_name.inspect} do\n"
        rules.each do |rule|
          memo += "  #{rule.serialize}\n"
        end
        memo += "end\n"
      end
    end

    def checksum
      Digest::MD5.hexdigest(self.serialize)
    end

    def deep_dup
      duplicate = RuleSet.new
      new_rules = Hash.new { |h, k| h[k] = [] }

      @rules.each do |table_name, rules|
        rules.each do |rule|
          new_rules[table_name] << Rule.new(rule.metric, rule.opts)
        end
      end

      duplicate.rules = new_rules
      duplicate
    end
  end
end
