module ActiveSupport
  class Duration
    def inspect
      "#{self.to_i}.seconds"
    end
  end
end
