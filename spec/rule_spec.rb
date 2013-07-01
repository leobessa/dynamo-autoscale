require 'spec_helper'

describe DynamoAutoscale::Rule do
  let(:table) { DynamoAutoscale::TableTracker.new("test_table") }

  describe 'basics' do
    let(:rule) do
      DynamoAutoscale::Rule.new(:consumed_reads, greater_than: 5, last: 2) do

      end
    end

    subject          { rule }
    its(:to_english) { should be_a String }
  end

  describe 'invalid rules' do
    describe 'no greater_than or less_than' do
      it 'should throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, last: 2) do

          end
        end.to raise_error ArgumentError
      end
    end

    describe 'greater_than and less_than make no logical sense' do
      it 'should throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, greater_than: 5, less_than: 2) do

          end
        end.to raise_error ArgumentError
      end

      it 'percentages should also throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, for: 1, greater_than: "5%", less_than: "2%") do

          end
        end.to raise_error ArgumentError
      end
    end

    describe 'greater_than less than 0' do
      it 'should throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, for: 1, greater_than: -1) do

          end
        end.to raise_error ArgumentError
      end

      it 'percentages should also throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, for: 1, greater_than: "-5%") do

          end
        end.to raise_error ArgumentError
      end
    end

    describe 'less_than less than 0' do
      it 'should throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, for: 1, less_than: -1) do

          end
        end.to raise_error ArgumentError
      end

      it 'percentages should also throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, for: 1, less_than: "-5%") do

          end
        end.to raise_error ArgumentError
      end
    end

    describe 'min less than 0' do
      it 'should throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, for: 1, greater_than: 1, min: -1) do

          end
        end.to raise_error ArgumentError
      end
    end

    describe 'max less than 0' do
      it 'should throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, for: 1, greater_than: 1, max: -1) do

          end
        end.to raise_error ArgumentError
      end
    end

    describe 'count less than 0' do
      it 'should throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:consumed_reads, for: 1, greater_than: 1, count: -1) do

          end
        end.to raise_error ArgumentError
      end
    end

    describe 'incorrect metrics' do
      it 'should throw an error' do
        expect do
          DynamoAutoscale::Rule.new(:whoops, for: 1, greater_than: 1) do

          end
        end.to raise_error ArgumentError
      end
    end

    describe 'scale' do
      describe 'scale and block are not given' do
        it 'should throw an error' do
          expect do
            DynamoAutoscale::Rule.new(:consumed_reads, last: 1, greater_than: 1)
          end.to raise_error ArgumentError
        end
      end

      describe 'scale given but not hash' do
        it 'should throw an error' do
          expect do
            DynamoAutoscale::Rule.new(:consumed_reads, last: 1, greater_than: 1, scale: 2)
          end.to raise_error ArgumentError
        end
      end

      describe 'scale given without :on or :by' do
        it 'should throw an error' do
          expect do
            DynamoAutoscale::Rule.new(:consumed_reads, last: 1, greater_than: 1, scale: {})
          end.to raise_error ArgumentError
        end
      end

      describe 'scale given with invalid :on' do
        it 'should throw an error' do
          expect do
            DynamoAutoscale::Rule.new(:consumed_reads, last: 1, greater_than: 1, scale: { on: :whoops, by: 2 })
          end.to raise_error ArgumentError
        end
      end

      describe 'scale given with invalid :by' do
        it 'should throw an error' do
          expect do
            DynamoAutoscale::Rule.new(:consumed_reads, last: 1, greater_than: 1, scale: { on: :consumed, by: -0.3 })
          end.to raise_error ArgumentError
        end
      end
    end
  end

  describe "test" do
    describe "should match" do
      let(:rule) do
        DynamoAutoscale::Rule.new(:consumed_reads, greater_than: 5, last: 2) do

        end
      end

      before do
        table.tick(3.seconds.ago, {
          provisioned_writes: 50,  consumed_writes: 12,
          provisioned_reads:  100, consumed_reads:  20,
        })

        table.tick(5.seconds.ago, {
          provisioned_writes: 50,  consumed_writes: 12,
          provisioned_reads:  100, consumed_reads:  20,
        })
      end

      subject { rule.test(table) }
      it      { should be_true }
    end

    describe 'should not match' do
      let(:rule) do
        DynamoAutoscale::Rule.new(:consumed_reads, greater_than: 5, last: 2) do

        end
      end

      context 'too few data points' do
        before do
          table.tick(5.seconds.ago, {
            provisioned_writes: 50,  consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })
        end

        subject { rule.test(table) }
        it      { should be_false }
      end

      context 'rule not satisfied' do
        before do
          table.tick(5.seconds.ago, {
            provisioned_writes: 50,  consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })

          table.tick(10.seconds.ago, {
            provisioned_writes: 50,  consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  0,
          })
        end

        subject { rule.test(table) }
        it      { should be_false }
      end
    end

    describe 'using time ranges in rules' do
      describe "should match" do
        let(:rule) do
          DynamoAutoscale::Rule.new(:consumed_reads, {
            greater_than: 5, for: 10.minutes, min: 2
          }) do

          end
        end

        before do
          table.tick(3.seconds.ago, {
            provisioned_writes: 50,  consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })

          table.tick(11.minutes.ago, {
            provisioned_writes: 50,  consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  0,
          })

          table.tick(23.seconds.ago, {
            provisioned_writes: 50,  consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })
        end

        subject { rule.test(table) }
        it      { should be_true }
      end

      describe "should not match" do
        let(:rule) do
          DynamoAutoscale::Rule.new(:consumed_writes, {
            greater_than: 5, for: 10.minutes, min: 2
          }) do

          end
        end

        context 'too few data points in range' do
          before do
            table.tick(12.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  20,
            })

            table.tick(11.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  0,
            })

            table.tick(23.seconds.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  20,
            })
          end

          subject { rule.test(table) }
          it      { should be_false }
        end

        context 'rule not satisfied' do
          before do
            table.tick(12.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  20,
            })

            table.tick(9.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 0,
              provisioned_reads:  100, consumed_reads:  0,
            })

            table.tick(23.seconds.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  20,
            })
          end

          subject { rule.test(table) }
          it      { should be_false }
        end
      end

      context 'using a :max value' do
        let(:rule) do
          DynamoAutoscale::Rule.new(:consumed_writes, {
            greater_than: 5, for: 10.minutes, min: 2, max: 2
          }) do

          end
        end

        describe 'should match' do
          before do
            table.tick(6.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  20,
            })

            table.tick(7.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  0,
            })

            table.tick(9.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 0,
              provisioned_reads:  100, consumed_reads:  20,
            })
          end

          subject { rule.test(table) }
          it      { should be_true }
        end

        describe 'should not match' do
          before do
            table.tick(6.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  20,
            })

            table.tick(9.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 0,
              provisioned_reads:  100, consumed_reads:  0,
            })

            table.tick(10.minutes.ago, {
              provisioned_writes: 50,  consumed_writes: 12,
              provisioned_reads:  100, consumed_reads:  20,
            })
          end

          subject { rule.test(table) }
          it      { should be_false }
        end
      end
    end

    describe 'using percentage values' do
      let(:rule) do
        DynamoAutoscale::Rule.new(:consumed_writes, {
          greater_than: "50%", for: 10.minutes, min: 2
        }) do

        end
      end

      describe 'should match' do
        before do
          table.tick(6.minutes.ago, {
            provisioned_writes: 100,  consumed_writes: 80,
            provisioned_reads:  100, consumed_reads:  20,
          })

          table.tick(7.minutes.ago, {
            provisioned_writes: 100,  consumed_writes: 80,
            provisioned_reads:  100, consumed_reads:  0,
          })

          table.tick(9.minutes.ago, {
            provisioned_writes: 100,  consumed_writes: 51,
            provisioned_reads:  100, consumed_reads:  20,
          })
        end

        subject { rule.test(table) }
        it      { should be_true }
      end

      describe 'should not match' do
        before do
          table.tick(6.minutes.ago, {
            provisioned_writes: 100,  consumed_writes: 51,
            provisioned_reads:  100, consumed_reads:  20,
          })

          table.tick(7.minutes.ago, {
            provisioned_writes: 100,  consumed_writes: 50,
            provisioned_reads:  100, consumed_reads:  0,
          })

          table.tick(8.minutes.ago, {
            provisioned_writes: 100,  consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })
        end

        subject { rule.test(table) }
        it      { should be_false }
      end
    end

    describe 'using a :times variable' do
      let :rule do
        DynamoAutoscale::Rule.new(:consumed_reads, {
          greater_than: 5, last: 2, times: 3, min: 2
        }) do

        end
      end

      describe 'should not match' do
        before do
          table.clear_data
          table.tick(8.minutes.ago, {
            provisioned_writes: 100, consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })

          rule.test(table)

          table.tick(7.minutes.ago, {
            provisioned_writes: 100, consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })

          rule.test(table)

          table.tick(6.minutes.ago, {
            provisioned_writes: 100, consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })
        end

        subject { rule.test(table) }
        it      { should be_false }
      end

      describe 'should match' do
        before do
          table.clear_data
          table.tick(5.minutes.ago, {
            provisioned_writes: 100, consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })

          rule.test(table)

          table.tick(6.minutes.ago, {
            provisioned_writes: 100, consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })

          rule.test(table)

          table.tick(7.minutes.ago, {
            provisioned_writes: 100, consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })

          rule.test(table)

          table.tick(8.minutes.ago, {
            provisioned_writes: 100, consumed_writes: 12,
            provisioned_reads:  100, consumed_reads:  20,
          })
        end

        subject { rule.test(table) }
        it      { should be_true }
      end
    end
  end # describe 'test'
end # describe DynamoAutoscale::Rule
