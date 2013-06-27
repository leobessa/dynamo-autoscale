require 'spec_helper'

describe DynamoAutoscale::Actioner do
  let(:actioner) { DynamoAutoscale::LocalActioner.new }
  let(:table)    { DynamoAutoscale::TableTracker.new("table") }

  before { DynamoAutoscale.current_table = table }
  after  { DynamoAutoscale.current_table = nil }

  describe "scaling down" do
    before do
      table.tick(5.minutes.ago, {
        provisioned_writes: 100, consumed_writes: 50,
        provisioned_reads:  100, consumed_reads:  20,
      })
    end

    it "should not be allowed more than 4 times per day" do
      actioner.set(:writes, table, 90).should be_true
      actioner.set(:writes, table, 80).should be_true
      actioner.set(:writes, table, 70).should be_true
      actioner.set(:writes, table, 60).should be_true
      actioner.set(:writes, table, 60).should be_false
    end
  end

  describe "scale resets" do
    before do
      table.tick(5.minutes.ago, {
        provisioned_writes: 100, consumed_writes: 50,
        provisioned_reads:  100, consumed_reads:  20,
      })
    end

    it "once per day at midnight" do
      actioner.set(:writes, table, 90).should be_true
      actioner.set(:writes, table, 80).should be_true
      actioner.set(:writes, table, 70).should be_true
      actioner.set(:writes, table, 60).should be_true
      actioner.set(:writes, table, 60).should be_false

      Timecop.travel(1.day.from_now.utc.midnight)

      actioner.set(:writes, table, 50).should be_true
      actioner.set(:writes, table, 40).should be_true
      actioner.set(:writes, table, 30).should be_true
      actioner.set(:writes, table, 20).should be_true
      actioner.set(:writes, table, 10).should be_false
    end

    specify "and not a second sooner" do
      actioner.set(:writes, table, 90).should be_true
      actioner.set(:writes, table, 80).should be_true
      actioner.set(:writes, table, 70).should be_true
      actioner.set(:writes, table, 60).should be_true
      actioner.set(:writes, table, 60).should be_false

      Timecop.travel(1.day.from_now.utc.midnight - 1.second)

      actioner.set(:writes, table, 50).should be_false
    end
  end

  describe "scaling up" do
    before do
      table.tick(5.minutes.ago, {
        provisioned_writes: 100, consumed_writes: 50,
        provisioned_reads:  100, consumed_reads:  20,
      })

      actioner.set(:writes, table, 100000)
    end

    it "should only go up to 2x your current provisioned" do
      time, val = actioner.provisioned_writes(table).last
      val.should == 200
    end

    it "can happen as much as it fucking wants to" do
      100.times do
        actioner.set(:writes, table, 100000).should be_true
      end
    end
  end
end
