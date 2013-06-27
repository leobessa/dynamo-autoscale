require 'spec_helper'

describe DynamoAutoscale::Rule do
  let(:table) { DynamoAutoscale::TableTracker.new("test_table") }

  describe 'basics' do
    let(:rule) do
      DynamoAutoscale::Rule.new(:consumed_reads, greater_than: 5, last: 2)
    end

    subject          { rule }
    its(:to_english) { should be_a String }
  end

  describe "test" do
    describe "should match" do
      let(:rule) do
        DynamoAutoscale::Rule.new(:consumed_reads, greater_than: 5, last: 2)
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
        DynamoAutoscale::Rule.new(:consumed_reads, greater_than: 5, last: 2)
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
          })
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
          })
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
          })
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
        })
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
        })
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
