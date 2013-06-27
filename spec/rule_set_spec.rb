require 'spec_helper'

describe DynamoAutoscale::RuleSet do
  describe 'creating rules' do
    let :rules do
      DynamoAutoscale::RuleSet.new do
        table "test" do
          reads  greater_than: 50, for: 5.minutes
          writes greater_than: 100, for: 15.minutes
        end

        table :all do
          reads less_than: 20, for: 2
        end

        writes greater_than: "40%", for: 12.seconds
      end
    end

    describe 'for a single table' do
      subject      { rules.for "test" }
      its(:length) { should == 4 }
    end

    describe 'for all tables' do
      subject      { rules.for :all }
      its(:length) { should == 2 }
    end
  end

  describe 'using rules' do
    let :rules do
      DynamoAutoscale::RuleSet.new do
        table "test_table" do
          reads  greater_than: 50, for: 5.minutes do
            @__first = true
          end

          reads  greater_than: 100, for: 15.minutes do
            @__second = true
          end
        end

        reads greater_than: "40%", for: 12.minutes do
          @__third = true
        end
      end
    end

    describe 'earlier rules get precedence' do
      let(:table) { DynamoAutoscale::TableTracker.new("test_table") }

      before do
        table.tick(4.minutes.ago, {
          provisioned_reads: 100.0,
          provisioned_writes: 200.0,
          consumed_reads: 90.0,
          consumed_writes: 30.0,
        })

        rules.test(table)
      end

      describe 'first block should get called' do
        subject { rules.instance_variable_get(:@__first) }
        it      { should be_true }
      end

      describe 'second block should not get called' do
        subject { rules.instance_variable_get(:@__second) }
        it      { should be_nil }
      end

      describe 'third block should not get called' do
        subject { rules.instance_variable_get(:@__third) }
        it      { should be_nil }
      end
    end
  end
end
