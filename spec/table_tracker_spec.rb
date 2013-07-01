require 'spec_helper'

describe DynamoAutoscale::TableTracker do
  let(:table_name) { "test_table" }
  let(:table)      { DynamoAutoscale::TableTracker.new(table_name) }
  subject          { table }

  before do
    table.tick(5.seconds.ago, {
      provisioned_reads: 600.0,
      provisioned_writes: 800.0,
      consumed_reads: 20.0,
      consumed_writes: 30.0,
    })

    table.tick(5.minutes.ago, {
      provisioned_reads: 600.0,
      provisioned_writes: 800.0,
      consumed_reads: 20.0,
      consumed_writes: 30.0,
    })

    table.tick(15.seconds.ago, {
      provisioned_reads: 600.0,
      provisioned_writes: 800.0,
      consumed_reads: 20.0,
      consumed_writes: 30.0,
    })
  end

  describe 'storing data' do
    specify "should be done in order" do
      table.data.keys.should == table.data.keys.sort
    end
  end

  describe 'retrieving data' do
    let(:now) { Time.now }

    before do
      table.tick(now, {
        provisioned_reads: 100.0,
        provisioned_writes: 200.0,
        consumed_reads: 20.0,
        consumed_writes: 30.0,
      })
    end

    describe "#name" do
      subject { table.name }
      it      { should == table_name }
    end

    describe "#last 3.seconds, :consumed_reads" do
      subject { table.last 3.seconds, :consumed_reads }
      it      { should == [20.0] }
    end

    describe "#last 1, :consumed_writes" do
      subject { table.last 1, :consumed_writes }
      it      { should == [30.0] }
    end

    describe "#last_provisioned_for :reads" do
      subject { table.last_provisioned_for :reads }
      it      { should == 100.0 }
    end

    describe "#last_provisioned_for :writes, at: now" do
      subject { table.last_provisioned_for :writes, at: now }
      it      { should == 200.0 }
    end

    describe "#last_provisioned_for :writes, at: 3.minutes.ago" do
      subject { table.last_provisioned_for :writes, at: 3.minutes.ago }
      it      { should == 800.0 }
    end

    describe "#all_times" do
      subject      { table.all_times }
      its(:length) { should == 4 }

      specify("is ordered") { subject.should == subject.sort }
    end
  end

  describe 'clearing data' do
    before { table.clear_data }

    specify "table.data should be totally empty" do
      table.data.keys.each do |key|
        table.data[key].should be_empty
      end
    end
  end

  describe 'stats' do
    before do
      table.clear_data

      table.tick(3.seconds.ago, {
        provisioned_reads: 100.0,
        consumed_reads:    99.0,

        provisioned_writes: 200.0,
        consumed_writes:    198.0,
      })

      table.tick(12.seconds.ago, {
        provisioned_reads: 100.0,
        consumed_reads:    99.0,

        provisioned_writes: 200.0,
        consumed_writes:    198.0,
      })
    end

    describe 'wasted_read_units' do
      subject { table.wasted_read_units }
      it      { should == 2.0 }
    end

    describe 'wasted_write_units' do
      subject { table.wasted_write_units }
      it      { should == 4.0 }
    end

    describe 'lost_read_units' do
      before do
        table.clear_data
        table.tick(12.seconds.ago, {
          provisioned_reads: 100.0,
          consumed_reads:    102.0,
        })
      end

      subject { table.lost_read_units }
      it      { should == 2.0 }
    end

    describe 'lost_write_units' do
      before do
        table.clear_data
        table.tick(12.seconds.ago, {
          provisioned_writes: 100.0,
          consumed_writes:    105.0,
        })
      end

      subject { table.lost_write_units }
      it      { should == 5.0 }
    end
  end

  describe 'no data' do
    before { table.clear_data }

    describe 'lost_write_units' do
      subject { table.lost_write_units }
      it      { should == 0.0 }
    end

    describe 'lost_read_units' do
      subject { table.lost_read_units }
      it      { should == 0.0 }
    end

    describe 'wasted_read_units' do
      subject { table.wasted_read_units }
      it      { should == 0.0 }
    end

    describe 'wasted_write_units' do
      subject { table.wasted_write_units }
      it      { should == 0.0 }
    end

    describe "#all_times" do
      subject      { table.all_times }
      its(:length) { should == 0 }
    end

    describe "#last 3.seconds, :consumed_reads" do
      subject { table.last 3.seconds, :consumed_reads }
      it      { should == [] }
    end

    describe "#last 1, :consumed_writes" do
      subject { table.last 1, :consumed_writes }
      it      { should == [] }
    end

    describe "#last_provisioned_for :reads" do
      subject { table.last_provisioned_for :reads }
      it      { should be_nil }
    end

    describe "#last_provisioned_for :writes" do
      subject { table.last_provisioned_for :writes }
      it      { should be_nil }
    end
  end

  describe 'time window' do
    describe 'inserting data outside of time window' do
      before do
        table.clear_data
        table.tick(12.weeks.ago, {
          provisioned_reads: 600.0,
          provisioned_writes: 800.0,
          consumed_reads: 20.0,
          consumed_writes: 30.0,
        })
      end

      it 'should not work' do
        table.all_times.should be_empty
      end
    end

    describe 'data time based cleanup' do
      before do
        table.clear_data
        Timecop.travel(2.weeks.ago)

        table.tick(Time.now, {
          provisioned_reads: 600.0,
          provisioned_writes: 800.0,
          consumed_reads: 20.0,
          consumed_writes: 30.0,
        })

        to_the_future = Time.now + DynamoAutoscale::TableTracker::TIME_WINDOW +
          2.minutes

        Timecop.travel(to_the_future)

        table.tick(Time.now, {
          provisioned_reads: 600.0,
          provisioned_writes: 800.0,
          consumed_reads: 20.0,
          consumed_writes: 30.0,
        })
      end

      it 'should remove data outside of the time window' do
        table.all_times.length.should == 1
      end

      it 'should not remove data inside of the time window' do
        table.tick(2.seconds.from_now, {})
        table.all_times.length.should == 2
      end
    end
  end
end
